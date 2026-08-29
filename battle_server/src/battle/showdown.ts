import { Battle, extractChannelMessages } from "pokemon-showdown/dist/sim/battle";
import { Dex } from "pokemon-showdown/dist/sim/dex";
import { Format } from "pokemon-showdown/dist/sim/dex-formats";
import { PRNG } from "pokemon-showdown/dist/sim/prng";
import { TeamValidator } from "pokemon-showdown/dist/sim/team-validator";
import { Teams } from "pokemon-showdown/dist/sim/teams";

import {
  FORMAT_VERSION,
  MAX_BATTLE_TURNS,
} from "./constants";
import { ServiceError } from "./errors";
import {
  prepareBattleTeams,
  resolveStartingHp,
} from "./teams";
import type {
  BattleAction,
  BattleResult,
  BattleTokenState,
  CanonicalBattleSide,
  CanonicalPokemonSet,
  MemberBattleState,
  PerSide,
  PlayerChoiceRequest,
  PreparedBattleTeams,
  PublicMemberBattleState,
} from "./types";

export const SHOWDOWN_FORMAT_ID = "pfrgen9singlesv1" as const;
const SHOWDOWN_BASE_FORMAT_ID = "gen9customgame";
const FORMAT_RULES = [
  "Min Team Size = 1",
  "Max Team Size = 6",
  "Max Move Count = 4",
  "Min Level = 1",
  "Max Level = 100",
  "Default Level = 100",
] as const;
const MAX_AI_CHOICES_PER_ACTION = 64;

type ShowdownPokemon = Battle["p1"]["pokemon"][number];
type ShowdownSide = Battle["p1"];
type SeedArgument = ConstructorParameters<typeof PRNG>[0];

interface StartingHpPlan {
  normalized?: PerSide<number[]>;
  resolved?: PerSide<number[]>;
}

export interface BattleRuntime {
  battle: Battle;
  prepared: PreparedBattleTeams;
  startingHp: PerSide<number[]>;
  memberIdByPokemon: WeakMap<ShowdownPokemon, string>;
  outcome: { winner: BattleResult["winner"] | null };
}

function isSupportedPrngSeed(seed: string): boolean {
  if (/^sodium,(?:[0-9a-f]{32}|[0-9a-f]{64})$/iu.test(seed)) return true;
  if (/^gen5,[0-9a-f]{16}$/iu.test(seed)) return true;

  const parts = seed.split(",");
  return (
    parts.length === 4 &&
    parts.every((part) => /^\d{1,5}$/u.test(part) && Number(part) <= 0xffff)
  );
}

function createPrng(seed: string, replay: boolean): PRNG {
  if (!isSupportedPrngSeed(seed)) {
    throw new ServiceError(
      replay ? 409 : 500,
      replay ? "incompatible_state_token" : "simulator_error",
      replay ? "State token contains an incompatible PRNG state" : "Battle PRNG seed is invalid",
      { expose: replay },
    );
  }

  try {
    return new PRNG(seed as SeedArgument);
  } catch (error) {
    throw new ServiceError(
      replay ? 409 : 500,
      replay ? "incompatible_state_token" : "simulator_error",
      replay ? "State token contains an incompatible PRNG state" : "Battle PRNG seed is invalid",
      { cause: error, expose: replay },
    );
  }
}

function sideKey(sideId: string): keyof PerSide<unknown> {
  if (sideId === "p1") return "player";
  if (sideId === "p2") return "opponent";
  throw new ServiceError(500, "simulator_error", "Unexpected simulator side", {
    expose: false,
  });
}

/**
 * Every construction gets a new Format because its onBegin callback closes
 * over request-local starting HP. Dex data caches remain immutable globals.
 */
export function createBattleFormat(
  hpPlan: StartingHpPlan,
  resolvedOutput: PerSide<number[]>,
  memberIds?: PerSide<string[]>,
  memberIdByPokemon = new WeakMap<ShowdownPokemon, string>(),
): Format {
  const base = Dex.formats.get(SHOWDOWN_BASE_FORMAT_ID, true);

  return new Format({
    name: FORMAT_VERSION,
    id: SHOWDOWN_FORMAT_ID,
    effectType: "Format",
    mod: base.mod,
    gameType: "singles",
    rated: false,
    debug: false,
    battle: base.battle,
    ruleset: [...FORMAT_RULES],
    baseRuleset: [...FORMAT_RULES],
    onBegin(this: Battle) {
      for (const side of this.sides) {
        const key = sideKey(side.id);
        const normalized = hpPlan.normalized?.[key];
        const stored = hpPlan.resolved?.[key];
        const ids = memberIds?.[key];

        if ((!normalized && !stored) || (normalized && stored)) {
          throw new ServiceError(
            500,
            "invalid_battle_state",
            "Starting HP plan is invalid",
            { expose: false },
          );
        }
        const values = stored ?? normalized;
        if (
          !values ||
          values.length !== side.pokemon.length ||
          (ids && ids.length !== side.pokemon.length)
        ) {
          throw new ServiceError(
            stored ? 409 : 500,
            stored ? "incompatible_state_token" : "invalid_battle_state",
            stored
              ? "State token starting HP does not match the battle team"
              : "Starting HP does not match the battle team",
            { expose: Boolean(stored) },
          );
        }

        for (const [index, pokemon] of side.pokemon.entries()) {
          const value = stored
            ? values[index]
            : resolveStartingHp(pokemon.maxhp, values[index]);
          if (!Number.isSafeInteger(value) || value <= 0 || value > pokemon.maxhp) {
            throw new ServiceError(
              stored ? 409 : 500,
              stored ? "incompatible_state_token" : "invalid_battle_state",
              stored
                ? "State token contains incompatible starting HP"
                : "Resolved starting HP is invalid",
              { expose: Boolean(stored) },
            );
          }
          pokemon.sethp(value);
          resolvedOutput[key].push(value);
          if (ids) memberIdByPokemon.set(pokemon, ids[index]);
        }
      }
    },
  });
}

function cloneTeam(team: CanonicalPokemonSet[]): CanonicalPokemonSet[] {
  return team.map((set) => ({
    ...set,
    moves: [...set.moves],
    ivs: { ...set.ivs },
    evs: { ...set.evs },
  }));
}

function validateTeam(
  format: Format,
  side: "player" | "opponent",
  team: CanonicalPokemonSet[],
  replay: boolean,
): CanonicalPokemonSet[] {
  const copy = cloneTeam(team);
  let problems: string[] | null;
  try {
    problems = new TeamValidator(format).validateTeam(copy);
  } catch (error) {
    throw new ServiceError(
      replay ? 409 : 422,
      replay ? "incompatible_state_token" : "invalid_team",
      replay ? "State token team is incompatible with the battle format" : `Invalid ${side} team`,
      { cause: error },
    );
  }
  if (problems?.length) {
    throw new ServiceError(
      replay ? 409 : 422,
      replay ? "incompatible_state_token" : "invalid_team",
      replay ? "State token team is incompatible with the battle format" : `Invalid ${side} team`,
      replay ? undefined : { details: { side, problems } },
    );
  }
  return copy;
}

function constructBattle(
  prepared: PreparedBattleTeams,
  seed: string,
  startingHp: PerSide<number[]> | undefined,
  replay: boolean,
): BattleRuntime {
  const resolvedOutput: PerSide<number[]> = { player: [], opponent: [] };
  const memberIdByPokemon = new WeakMap<ShowdownPokemon, string>();
  const format = createBattleFormat(
    startingHp
      ? { resolved: startingHp }
      : {
          normalized: {
            player: prepared.player.normalizedHealth,
            opponent: prepared.opponent.normalizedHealth,
          },
        },
    resolvedOutput,
    {
      player: prepared.player.memberIds,
      opponent: prepared.opponent.memberIds,
    },
    memberIdByPokemon,
  );
  const playerTeam = validateTeam(format, "player", prepared.player.team, replay);
  const opponentTeam = validateTeam(format, "opponent", prepared.opponent.team, replay);
  const outcome: BattleRuntime["outcome"] = { winner: null };
  let battle: Battle | undefined;

  try {
    const prng = createPrng(seed, replay);
    battle = new Battle({
      format,
      formatid: SHOWDOWN_FORMAT_ID,
      prng,
      rated: false,
      debug: false,
      strictChoices: true,
      send: () => undefined,
    });
    const originalWin = battle.win.bind(battle);
    battle.win = ((side) => {
      const sideId = typeof side === "string" ? side : side?.id;
      const winner = !sideId
        ? "tie"
        : sideId === "p1"
          ? "player"
          : sideId === "p2"
            ? "opponent"
            : null;
      const ended = originalWin(side);
      if (ended) outcome.winner = winner;
      return ended;
    }) as Battle["win"];
    battle.setPlayer("p1", { name: prepared.player.name, team: Teams.pack(playerTeam) });
    battle.setPlayer("p2", { name: prepared.opponent.name, team: Teams.pack(opponentTeam) });

    if (!battle.started || battle.ended || !playerNeedsChoice(battle)) {
      throw new ServiceError(
        replay ? 409 : 500,
        replay ? "incompatible_state_token" : "simulator_error",
        replay
          ? "State token does not reconstruct an active player decision"
          : "Battle did not reach its initial player decision",
        { expose: replay },
      );
    }
    return { battle, prepared, startingHp: resolvedOutput, memberIdByPokemon, outcome };
  } catch (error) {
    battle?.destroy();
    throw error;
  }
}

function parseStartSeed(record: string): string {
  const match = /^>start (\{.*\})$/u.exec(record);
  if (!match) {
    throw new ServiceError(409, "incompatible_state_token", "State token start record is invalid");
  }
  let value: unknown;
  try {
    value = JSON.parse(match[1]);
  } catch (error) {
    throw new ServiceError(409, "incompatible_state_token", "State token start record is invalid", {
      cause: error,
    });
  }
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).length !== 2 ||
    (value as Record<string, unknown>).formatid !== SHOWDOWN_FORMAT_ID ||
    typeof (value as Record<string, unknown>).seed !== "string"
  ) {
    throw new ServiceError(409, "incompatible_state_token", "State token start record is invalid");
  }
  return (value as { seed: string }).seed;
}

function assertCanonicalPrefix(runtime: BattleRuntime, state: BattleTokenState): void {
  // These records were regenerated solely from authenticated canonical state;
  // no raw player command or player JSON from the token is executed.
  const expected = runtime.battle.inputLog.slice(0, 3);
  if (expected.some((record, index) => record !== state.inputLog[index])) {
    throw new ServiceError(
      409,
      "incompatible_state_token",
      "State token player records are incompatible with the canonical teams",
    );
  }
}

function replayChoice(battle: Battle, record: string): void {
  const match = /^>(p[12]) ((?:move [a-z0-9]+)|(?:switch [1-6]))$/u.exec(record);
  if (!match || battle.ended) {
    throw new ServiceError(
      409,
      "incompatible_state_token",
      "State token contains an invalid committed choice record",
    );
  }

  try {
    if (!battle.choose(match[1] as "p1" | "p2", match[2])) {
      throw new ServiceError(
        409,
        "incompatible_state_token",
        "State token contains an invalid committed choice record",
      );
    }
  } catch (error) {
    if (isShowdownChoiceError(error)) {
      throw new ServiceError(
        409,
        "incompatible_state_token",
        "State token contains an invalid committed choice record",
        { cause: error },
      );
    }
    throw error;
  }
}

function sameRecords(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((record, index) => record === right[index]);
}

export function startShowdownBattle(
  prepared: PreparedBattleTeams,
  seed: string = PRNG.generateSeed(),
): BattleRuntime {
  return constructBattle(prepared, seed, undefined, false);
}

export function replayShowdownBattle(state: BattleTokenState): BattleRuntime {
  const prepared = prepareBattleTeams({ player: state.player, opponent: state.opponent });
  const seed = parseStartSeed(state.inputLog[0]);
  const runtime = constructBattle(prepared, seed, state.startingHp, true);

  try {
    assertCanonicalPrefix(runtime, state);
    for (const record of state.inputLog.slice(3)) replayChoice(runtime.battle, record);
    if (
      !sameRecords(runtime.battle.inputLog, state.inputLog) ||
      runtime.battle.ended ||
      !playerNeedsChoice(runtime.battle)
    ) {
      throw new ServiceError(
        409,
        "incompatible_state_token",
        "State token is not a stable player decision boundary",
      );
    }
    assertTurnLimit(runtime.battle);
    return runtime;
  } catch (error) {
    runtime.battle.destroy();
    throw error;
  }
}

function needsChoice(side: ShowdownSide): boolean {
  return Boolean(side.requestState) && !side.isChoiceDone();
}

function playerNeedsChoice(battle: Battle): boolean {
  return needsChoice(battle.p1);
}

function mappedMemberId(runtime: BattleRuntime, pokemon: ShowdownPokemon): string {
  const memberId = runtime.memberIdByPokemon.get(pokemon);
  if (!memberId) {
    throw new ServiceError(500, "simulator_error", "Simulator member mapping is invalid", {
      expose: false,
    });
  }
  return memberId;
}

function isActive(side: ShowdownSide, pokemon: ShowdownPokemon): boolean {
  return side.active.includes(pokemon);
}

function switchCandidates(runtime: BattleRuntime, sideName: "player" | "opponent"): ShowdownPokemon[] {
  const side = sideName === "player" ? runtime.battle.p1 : runtime.battle.p2;
  const request = side.activeRequest;
  if (!request || request.wait || !request.forceSwitch) return [];

  if (request.side.pokemon.some((entry) => entry.reviving)) {
    return side.pokemon.filter((pokemon) => pokemon.fainted);
  }
  return side.pokemon.filter((pokemon) => !pokemon.fainted && !isActive(side, pokemon));
}

function voluntarySwitchCandidates(runtime: BattleRuntime): ShowdownPokemon[] {
  const side = runtime.battle.p1;
  const active = side.active[0];
  if (!active || active.trapped) return [];
  return side.pokemon.filter((pokemon) => !pokemon.fainted && !isActive(side, pokemon));
}

export function getPlayerRequest(runtime: BattleRuntime): PlayerChoiceRequest | null {
  const request = runtime.battle.p1.activeRequest;
  if (!request || request.wait) return null;

  if (request.forceSwitch) {
    const active = runtime.battle.p1.active[0];
    return {
      type: "switch",
      ...(active ? { activeMemberId: mappedMemberId(runtime, active) } : {}),
      switchOptions: switchCandidates(runtime, "player").map((pokemon) => ({
        memberId: mappedMemberId(runtime, pokemon),
      })),
    };
  }

  if (request.teamPreview) {
    throw new ServiceError(500, "simulator_error", "Team Preview is disabled", {
      expose: false,
    });
  }

  const active = runtime.battle.p1.active[0];
  const activeRequest = request.active[0];
  if (!active || !activeRequest) {
    throw new ServiceError(500, "simulator_error", "Player move request is incomplete", {
      expose: false,
    });
  }
  return {
    type: "move",
    activeMemberId: mappedMemberId(runtime, active),
    moves: activeRequest.moves.map((move, index) => ({
      moveIndex: index + 1,
      id: move.id,
      name: move.move,
      pp: move.pp ?? 0,
      maxPp: move.maxpp ?? 0,
      disabled: Boolean(move.disabled),
    })),
    switchOptions: voluntarySwitchCandidates(runtime).map((pokemon) => ({
      memberId: mappedMemberId(runtime, pokemon),
    })),
  };
}

function invalidAction(message: string): never {
  throw new ServiceError(422, "invalid_action", message);
}

function isShowdownChoiceError(error: unknown): boolean {
  return (
    error instanceof Error &&
    /^\[(?:Invalid|Unavailable) choice\](?: |$)/u.test(error.message)
  );
}

function isShowdownUnavailableChoiceError(error: unknown): boolean {
  return error instanceof Error && /^\[Unavailable choice\](?: |$)/u.test(error.message);
}

export function applyPlayerAction(runtime: BattleRuntime, action: BattleAction): void {
  if (action.type === "forfeit") {
    runtime.battle.lose("p1");
    return;
  }
  const request = getPlayerRequest(runtime);
  if (!request) invalidAction("The battle is not waiting for a player action");

  let choice: string;
  if (action.type === "move") {
    if (request.type !== "move") invalidAction("A replacement must be selected");
    const move = request.moves[action.moveIndex - 1];
    if (!move) invalidAction("moveIndex is not available for the active Pokémon");
    if (move.disabled) invalidAction("The selected move is disabled");
    choice = `move ${action.moveIndex}`;
  } else {
    const option = request.switchOptions.find((candidate) => candidate.memberId === action.memberId);
    if (!option) invalidAction("The selected member is not an available switch option");
    const pokemon = runtime.battle.p1.pokemon.find(
      (candidate) => mappedMemberId(runtime, candidate) === option.memberId,
    );
    if (!pokemon) invalidAction("The selected member is not part of the battle team");
    choice = `switch ${pokemon.position + 1}`;
  }

  try {
    if (!runtime.battle.choose("p1", choice)) {
      invalidAction("The simulator rejected the selected action");
    }
  } catch (error) {
    if (isShowdownChoiceError(error)) {
      invalidAction("The simulator rejected the selected action");
    }
    throw error;
  }
}

function chooseAi(runtime: BattleRuntime, aiPrng: PRNG): void {
  const side = runtime.battle.p2;
  const request = side.activeRequest;
  if (!request || request.wait) {
    throw new ServiceError(500, "simulator_error", "AI has no actionable request", {
      expose: false,
    });
  }

  let choice: string;
  if (request.forceSwitch) {
    const candidates = switchCandidates(runtime, "opponent");
    if (!candidates.length) {
      throw new ServiceError(500, "simulator_error", "AI has no valid forced switch", {
        expose: false,
      });
    }
    choice = `switch ${aiPrng.sample(candidates).position + 1}`;
  } else if (request.teamPreview) {
    throw new ServiceError(500, "simulator_error", "Team Preview is disabled", {
      expose: false,
    });
  } else {
    const moves = request.active[0]?.moves ?? [];
    const enabled = moves
      .map((move, index) => ({ move, index }))
      .filter(({ move }) => !move.disabled);
    if (!enabled.length) {
      throw new ServiceError(500, "simulator_error", "AI has no enabled move", {
        expose: false,
      });
    }
    choice = `move ${aiPrng.sample(enabled).index + 1}`;
  }

  try {
    if (!runtime.battle.choose("p2", choice)) {
      throw new ServiceError(500, "simulator_error", "Simulator rejected the AI choice", {
        expose: false,
      });
    }
  } catch (error) {
    // Showdown can reveal a hidden disable only when a choice is attempted.
    // It updates the side request before throwing, so the driver can sample
    // again from the newly enabled set on its next iteration.
    if (isShowdownUnavailableChoiceError(error)) return;
    throw error;
  }
}

export function advanceAiUntilPlayerDecision(runtime: BattleRuntime, aiPrng: PRNG): void {
  for (let choices = 0; choices < MAX_AI_CHOICES_PER_ACTION; choices += 1) {
    if (runtime.battle.ended || playerNeedsChoice(runtime.battle)) {
      assertTurnLimit(runtime.battle);
      return;
    }
    if (needsChoice(runtime.battle.p2)) {
      chooseAi(runtime, aiPrng);
      continue;
    }
    throw new ServiceError(500, "simulator_error", "Battle stalled between decisions", {
      expose: false,
    });
  }
  throw new ServiceError(409, "battle_limit_exceeded", "Battle exceeded the AI decision limit");
}

export function assertTurnLimit(battle: Battle): void {
  if (battle.turn > MAX_BATTLE_TURNS) {
    throw new ServiceError(
      409,
      "battle_turn_limit_exceeded",
      `Battle exceeds the ${MAX_BATTLE_TURNS}-turn limit`,
    );
  }
}

export function protocolEventsSince(battle: Battle, cursor: number): string[] {
  const raw = battle.log.slice(cursor).join("\n");
  if (!raw) return [];
  return extractChannelMessages(raw, [1])[1].filter((line) => !line.startsWith("|t:|"));
}

function calculateMaxHp(member: CanonicalBattleSide["team"][number]): number {
  const species = Dex.forGen(9).species.get(member.species);
  if (!species.exists) {
    throw new ServiceError(500, "invalid_battle_state", "Canonical species no longer exists", {
      expose: false,
    });
  }
  if (species.baseStats.hp === 1) return 1;
  return (
    Math.floor(
      ((2 * species.baseStats.hp + member.ivs.hp + Math.floor(member.evs.hp / 4)) *
        member.level) /
        100,
    ) +
    member.level +
    10
  );
}

function maxMovePp(moveName: string): number {
  const move = Dex.forGen(9).moves.get(moveName);
  if (!move.exists) return 0;
  return move.noPPBoosts || move.id === "trumpcard" ? move.pp : (move.pp * 8) / 5;
}

function playerMoves(member: CanonicalBattleSide["team"][number], pokemon?: ShowdownPokemon) {
  if (pokemon) {
    return pokemon.baseMoveSlots.map((move, index) => ({
      moveIndex: index + 1,
      id: move.id,
      name: move.move,
      pp: move.pp,
      maxPp: move.maxpp,
    }));
  }
  return member.moves.map((moveName, index) => {
    const move = Dex.forGen(9).moves.get(moveName);
    const maxPp = maxMovePp(moveName);
    return { moveIndex: index + 1, id: move.id, name: move.name, pp: maxPp, maxPp };
  });
}

function snapshotSide(
  runtime: BattleRuntime,
  sideName: "player" | "opponent",
): MemberBattleState[] | PublicMemberBattleState[] {
  const canonical = runtime.prepared[sideName].roster;
  const side = sideName === "player" ? runtime.battle.p1 : runtime.battle.p2;
  const byMemberId = new Map<string, ShowdownPokemon>();
  for (const pokemon of side.pokemon) {
    byMemberId.set(mappedMemberId(runtime, pokemon), pokemon);
  }

  return canonical.map((member) => {
    const pokemon = byMemberId.get(member.memberId);
    const maxHp = pokemon?.maxhp ?? calculateMaxHp(member);
    const hp = pokemon?.hp ?? 0;
    const common = {
      memberId: member.memberId,
      species: member.species,
      nickname: member.nickname,
      level: member.level,
      hp,
      maxHp,
      normalizedHealth: maxHp > 0 ? hp / maxHp : 0,
      fainted: pokemon ? pokemon.fainted || hp <= 0 : true,
      active: pokemon ? isActive(side, pokemon) : false,
      status: pokemon?.status ? String(pokemon.status) : null,
    };
    return sideName === "player"
      ? { ...common, moves: playerMoves(member, pokemon) }
      : common;
  });
}

export function battleParties(runtime: BattleRuntime): {
  player: MemberBattleState[];
  opponent: PublicMemberBattleState[];
} {
  return {
    player: snapshotSide(runtime, "player") as MemberBattleState[],
    opponent: snapshotSide(runtime, "opponent") as PublicMemberBattleState[],
  };
}

export function battleResult(
  runtime: BattleRuntime,
  reason = "all_pokemon_fainted",
): BattleResult {
  if (!runtime.battle.ended) {
    throw new ServiceError(500, "simulator_error", "Battle result requested before battle end", {
      expose: false,
    });
  }
  if (!runtime.outcome.winner) {
    throw new ServiceError(500, "simulator_error", "Simulator winner was not captured", {
      expose: false,
    });
  }
  return { winner: runtime.outcome.winner, reason };
}

export function aiPrngFromState(state?: string, replay = false): PRNG {
  return createPrng(state ?? PRNG.generateSeed(), replay);
}

export function aiPrngState(prng: PRNG): string {
  return prng.getSeed();
}
