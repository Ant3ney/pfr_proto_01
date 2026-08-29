import { Dex } from "pokemon-showdown/dist/sim/dex";

import { STAT_NAMES } from "./constants";
import { ServiceError } from "./errors";
import { parseStartBattleRequest } from "./schemas";
import type {
  BattleSideInput,
  CanonicalBattleSide,
  CanonicalPokemonSet,
  CanonicalStartBattleRequest,
  CanonicalTeamMember,
  PartialStatTable,
  PreparedBattleSide,
  PreparedBattleTeams,
  StatTable,
  TeamMemberInput,
} from "./types";

const dex = Dex.forGen(9);

function defaultStats(values: PartialStatTable | undefined, fallback: number): StatTable {
  return Object.fromEntries(
    STAT_NAMES.map((stat) => [stat, values?.[stat] ?? fallback]),
  ) as unknown as StatTable;
}

function invalidTeam(side: "player" | "opponent", memberId: string, message: string): never {
  throw new ServiceError(422, "invalid_team", message, {
    details: { side, memberId },
  });
}

function canonicalizeMember(
  input: TeamMemberInput,
  side: "player" | "opponent",
): CanonicalTeamMember {
  const species = dex.species.get(input.species);
  if (!species.exists) {
    invalidTeam(side, input.memberId, `Unknown species: ${input.species}`);
  }

  const moves = input.moves.map((value) => {
    const move = dex.moves.get(value);
    if (!move.exists) {
      invalidTeam(side, input.memberId, `Unknown move: ${value}`);
    }
    return move.name;
  });

  const abilityName = input.ability ?? species.abilities[0];
  const ability = dex.abilities.get(abilityName);
  if (!ability.exists) {
    invalidTeam(side, input.memberId, `Unknown ability: ${abilityName}`);
  }

  let itemName = "";
  if (input.item) {
    const item = dex.items.get(input.item);
    if (!item.exists) {
      invalidTeam(side, input.memberId, `Unknown item: ${input.item}`);
    }
    itemName = item.name;
  }

  const natureName = input.nature ?? "Serious";
  const nature = dex.natures.get(natureName);
  if (!nature.exists) {
    invalidTeam(side, input.memberId, `Unknown nature: ${natureName}`);
  }

  const nickname = input.nickname ?? species.name;
  if (input.nickname !== undefined && dex.getName(nickname) !== nickname) {
    invalidTeam(side, input.memberId, "Nickname is not safe for the Showdown protocol");
  }

  return {
    memberId: input.memberId,
    species: species.name,
    level: input.level,
    health: input.health,
    moves,
    nickname,
    ability: ability.name,
    item: itemName,
    nature: nature.name,
    gender: input.gender ?? "",
    ivs: defaultStats(input.ivs, 31),
    evs: defaultStats(input.evs, 0),
  };
}

function canonicalizeSide(
  input: BattleSideInput,
  side: "player" | "opponent",
): CanonicalBattleSide {
  if (dex.getName(input.name) !== input.name) {
    throw new ServiceError(422, "invalid_team", `${side} name is not safe for Showdown`);
  }

  const team = input.team.map((member) => canonicalizeMember(member, side));
  if (!team.some((member) => member.health > 0)) {
    throw new ServiceError(422, "invalid_team", `${side} team has no living members`, {
      details: { side },
    });
  }

  return { name: input.name, team };
}

export function canonicalizeStartRequest(value: unknown): CanonicalStartBattleRequest {
  const input = parseStartBattleRequest(value);
  return {
    player: canonicalizeSide(input.player, "player"),
    opponent: canonicalizeSide(input.opponent, "opponent"),
  };
}

export function toPokemonSet(member: CanonicalTeamMember): CanonicalPokemonSet {
  return {
    name: member.nickname,
    species: member.species,
    item: member.item,
    ability: member.ability,
    moves: [...member.moves],
    nature: member.nature,
    gender: member.gender,
    evs: { ...member.evs },
    ivs: { ...member.ivs },
    level: member.level,
  };
}

/** Return fresh Showdown-compatible sets for living members in caller order. */
export function toShowdownTeam(side: CanonicalBattleSide): CanonicalPokemonSet[] {
  return side.team.filter((member) => member.health > 0).map(toPokemonSet);
}

export function prepareBattleSide(side: CanonicalBattleSide): PreparedBattleSide {
  const living = side.team.filter((member) => member.health > 0);
  if (living.length === 0) {
    throw new ServiceError(422, "invalid_team", "Team has no living members");
  }

  return {
    name: side.name,
    roster: side.team.map((member) => ({
      ...member,
      moves: [...member.moves],
      ivs: { ...member.ivs },
      evs: { ...member.evs },
    })),
    team: toShowdownTeam(side),
    memberIds: living.map((member) => member.memberId),
    normalizedHealth: living.map((member) => member.health),
  };
}

export function prepareBattleTeams(start: CanonicalStartBattleRequest): PreparedBattleTeams {
  return {
    player: prepareBattleSide(start.player),
    opponent: prepareBattleSide(start.opponent),
  };
}

/**
 * Resolve a caller's normalized HP after Showdown has calculated max HP.
 *
 * Zero stays fainted. Positive values use nearest-integer rounding (JavaScript
 * `Math.round`, so exact half ties round upward) and are clamped to [1, maxHp].
 * This guarantees that a positive caller value cannot become fainted solely
 * because its fraction was smaller than half of one HP.
 */
export function resolveStartingHp(maxHp: number, normalized: number): number {
  if (!Number.isSafeInteger(maxHp) || maxHp <= 0) {
    throw new RangeError("maxHp must be a positive safe integer");
  }
  if (!Number.isFinite(normalized) || normalized < 0 || normalized > 1) {
    throw new RangeError("normalized health must be between 0 and 1");
  }
  if (normalized === 0) return 0;

  return Math.min(maxHp, Math.max(1, Math.round(maxHp * normalized)));
}

/**
 * Calculate Gen 9 max HP without constructing a Battle. This is used for
 * retained health=0 roster members, which Showdown intentionally never sees.
 */
export function calculateMemberMaxHp(member: CanonicalTeamMember): number {
  const species = dex.species.get(member.species);
  if (!species.exists) {
    throw new ServiceError(500, "invalid_battle_state", "Canonical species no longer exists", {
      expose: false,
    });
  }
  if (species.maxHP) return species.maxHP;

  const effort = Math.floor(member.evs.hp / 4);
  const scaled = Math.floor(
    ((2 * species.baseStats.hp + member.ivs.hp + effort) * member.level) / 100,
  );
  return scaled + member.level + 10;
}
