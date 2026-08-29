import { randomUUID } from "node:crypto";

import {
  API_VERSION,
  ENGINE_VERSION,
  FORMAT_VERSION,
  TOKEN_SCHEMA_VERSION,
} from "./constants";
import { ServiceError } from "./errors";
import { parseBattleActionRequest } from "./schemas";
import {
  advanceAiUntilPlayerDecision,
  aiPrngFromState,
  aiPrngState,
  applyPlayerAction,
  assertTurnLimit,
  battleParties,
  battleResult,
  getPlayerRequest,
  protocolEventsSince,
  replayShowdownBattle,
  startShowdownBattle,
} from "./showdown";
import { canonicalizeStartRequest, prepareBattleTeams } from "./teams";
import { openStateToken, sealStateToken } from "./token";
import type {
  BattleResponse,
  BattleTokenState,
  CanonicalStartBattleRequest,
  PerSide,
  PreparedBattleTeams,
} from "./types";

export interface BattleStartOptions {
  /** Internal deterministic-test seam; never accepted by the REST schema. */
  battleSeed?: string;
  /** Internal deterministic-test seam; never accepted by the REST schema. */
  aiSeed?: string;
  /** Internal deterministic-test seam; never accepted by the REST schema. */
  battleId?: string;
}

function copyPerSide<T>(values: PerSide<T[]>): PerSide<T[]> {
  return { player: [...values.player], opponent: [...values.opponent] };
}

function makeTokenState(
  canonical: CanonicalStartBattleRequest,
  prepared: PreparedBattleTeams,
  battleId: string,
  revision: number,
  inputLog: readonly string[],
  startingHp: PerSide<number[]>,
  currentAiState: string,
): BattleTokenState {
  return {
    schemaVersion: TOKEN_SCHEMA_VERSION,
    apiVersion: API_VERSION,
    engineVersion: ENGINE_VERSION,
    formatVersion: FORMAT_VERSION,
    battleId,
    revision,
    inputLog: [...inputLog],
    player: canonical.player,
    opponent: canonical.opponent,
    memberIds: {
      player: [...prepared.player.memberIds],
      opponent: [...prepared.opponent.memberIds],
    },
    startingHp: copyPerSide(startingHp),
    aiPrngState: currentAiState,
  };
}

function awaitingResponse(
  state: BattleTokenState,
  runtime: ReturnType<typeof startShowdownBattle>,
  eventsCursor: number,
): BattleResponse {
  const request = getPlayerRequest(runtime);
  if (!request) {
    throw new ServiceError(500, "simulator_error", "Battle is not awaiting a player choice", {
      expose: false,
    });
  }
  return {
    apiVersion: API_VERSION,
    engineVersion: ENGINE_VERSION,
    formatVersion: FORMAT_VERSION,
    battleId: state.battleId,
    revision: state.revision,
    phase: "awaiting_player",
    stateToken: sealStateToken(state),
    events: protocolEventsSince(runtime.battle, eventsCursor),
    request,
    parties: battleParties(runtime),
  };
}

export function startBattle(input: unknown, options: BattleStartOptions = {}): BattleResponse {
  const canonical = canonicalizeStartRequest(input);
  const prepared = prepareBattleTeams(canonical);
  const aiPrng = aiPrngFromState(options.aiSeed);
  const runtime = options.battleSeed
    ? startShowdownBattle(prepared, options.battleSeed)
    : startShowdownBattle(prepared);

  try {
    const state = makeTokenState(
      canonical,
      prepared,
      options.battleId ?? randomUUID(),
      0,
      runtime.battle.inputLog,
      runtime.startingHp,
      aiPrngState(aiPrng),
    );
    return awaitingResponse(state, runtime, 0);
  } finally {
    runtime.battle.destroy();
  }
}

export function applyBattleAction(input: unknown): BattleResponse {
  const parsed = parseBattleActionRequest(input);
  const state = openStateToken(parsed.stateToken);
  const runtime = replayShowdownBattle(state);

  try {
    const eventsCursor = runtime.battle.log.length;
    const aiPrng = aiPrngFromState(state.aiPrngState, true);
    applyPlayerAction(runtime, parsed.action);
    if (!runtime.battle.ended) advanceAiUntilPlayerDecision(runtime, aiPrng);
    assertTurnLimit(runtime.battle);

    const revision = state.revision + 1;
    if (!Number.isSafeInteger(revision)) {
      throw new ServiceError(409, "battle_limit_exceeded", "Battle revision limit exceeded");
    }

    if (runtime.battle.ended) {
      const result = battleResult(
        runtime,
        parsed.action.type === "forfeit" ? "forfeit" : "all_pokemon_fainted",
      );
      return {
        apiVersion: API_VERSION,
        engineVersion: ENGINE_VERSION,
        formatVersion: FORMAT_VERSION,
        battleId: state.battleId,
        revision,
        phase: "ended",
        events: protocolEventsSince(runtime.battle, eventsCursor),
        request: null,
        parties: battleParties(runtime),
        result,
      };
    }

    const nextState: BattleTokenState = {
      ...state,
      revision,
      inputLog: [...runtime.battle.inputLog],
      aiPrngState: aiPrngState(aiPrng),
    };
    return awaitingResponse(nextState, runtime, eventsCursor);
  } finally {
    runtime.battle.destroy();
  }
}
