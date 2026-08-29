import { describe, expect, it, vi } from "vitest";

import { MAX_BATTLE_TURNS } from "../../src/battle/constants";
import { ServiceError } from "../../src/battle/errors";
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
} from "../../src/battle/showdown";
import { canonicalizeStartRequest, prepareBattleTeams } from "../../src/battle/teams";
import type { BattleTokenState } from "../../src/battle/types";
import {
  battleBody,
  FIXED_AI_SEED,
  FIXED_BATTLE_SEED,
  member,
} from "../fixtures";

function preparedBattle(
  playerTeam = [member("player-1")],
  opponentTeam = [member("opponent-1")],
) {
  return prepareBattleTeams(canonicalizeStartRequest(battleBody(playerTeam, opponentTeam)));
}

describe("Showdown adapter", () => {
  it("applies rounded reduced HP before the initial switch and exposes one singles request", () => {
    const prepared = preparedBattle(
      [member("hurt", { health: 0.503 })],
      [member("opponent", { species: "Bulbasaur", health: 0.25 })],
    );
    const runtime = startShowdownBattle(prepared, FIXED_BATTLE_SEED);

    try {
      const parties = battleParties(runtime);
      const player = parties.player[0];
      const opponent = parties.opponent[0];

      expect(runtime.startingHp).toEqual({
        player: [Math.round(player.maxHp * 0.503)],
        opponent: [Math.round(opponent.maxHp * 0.25)],
      });
      expect(player).toMatchObject({ memberId: "hurt", hp: runtime.startingHp.player[0], active: true });
      expect(opponent).toMatchObject({
        memberId: "opponent",
        hp: runtime.startingHp.opponent[0],
        active: true,
      });
      expect(getPlayerRequest(runtime)).toMatchObject({
        type: "move",
        activeMemberId: "hurt",
      });
      expect(protocolEventsSince(runtime.battle, 0)).toEqual(
        expect.arrayContaining([
          `|switch|p1a: Pikachu|Pikachu, L50|${player.hp}/${player.maxHp}`,
        ]),
      );
      expect(runtime.battle.p1.active).toHaveLength(1);
      expect(runtime.battle.p2.active).toHaveLength(1);
      expect(runtime.battle.p1.activeRequest?.teamPreview).toBeFalsy();
    } finally {
      runtime.battle.destroy();
    }
  });

  it("commits only typed choices and advances deterministic AI to the next player boundary", () => {
    const runtime = startShowdownBattle(
      preparedBattle(
        [member("player", { moves: ["Tackle", "Growl"] })],
        [member("opponent", { moves: ["Splash"] })],
      ),
      FIXED_BATTLE_SEED,
    );
    const ai = aiPrngFromState(FIXED_AI_SEED);

    try {
      const cursor = runtime.battle.log.length;
      applyPlayerAction(runtime, { type: "move", moveIndex: 1 });
      advanceAiUntilPlayerDecision(runtime, ai);

      expect(runtime.battle.inputLog.slice(-2)).toEqual([">p1 move tackle", ">p2 move splash"]);
      expect(getPlayerRequest(runtime)).toMatchObject({ type: "move", activeMemberId: "player" });
      expect(aiPrngState(ai)).not.toBe(FIXED_AI_SEED);
      expect(protocolEventsSince(runtime.battle, cursor)).toEqual(
        expect.arrayContaining([
          expect.stringContaining("|move|p1a: Pikachu|Tackle|"),
          expect.stringContaining("|move|p2a: Pikachu|Splash|"),
        ]),
      );
    } finally {
      runtime.battle.destroy();
    }
  });

  it("reconstructs an identical stable decision from canonical input records", () => {
    const prepared = preparedBattle(
      [member("player", { health: 0.75, moves: ["Tackle"] })],
      [member("opponent", { moves: ["Splash"] })],
    );
    const original = startShowdownBattle(prepared, FIXED_BATTLE_SEED);
    const ai = aiPrngFromState(FIXED_AI_SEED);

    try {
      applyPlayerAction(original, { type: "move", moveIndex: 1 });
      advanceAiUntilPlayerDecision(original, ai);
      const state = {
        schemaVersion: 1,
        apiVersion: "v1",
        engineVersion: "0.11.11",
        formatVersion: "pfr-gen9-singles-v1",
        battleId: "replay-test",
        revision: 1,
        inputLog: [...original.battle.inputLog],
        player: canonicalizeStartRequest(battleBody(
          [member("player", { health: 0.75, moves: ["Tackle"] })],
          [member("opponent", { moves: ["Splash"] })],
        )).player,
        opponent: canonicalizeStartRequest(battleBody(
          [member("player", { health: 0.75, moves: ["Tackle"] })],
          [member("opponent", { moves: ["Splash"] })],
        )).opponent,
        memberIds: { player: ["player"], opponent: ["opponent"] },
        startingHp: original.startingHp,
        aiPrngState: aiPrngState(ai),
      } satisfies BattleTokenState;

      const replayed = replayShowdownBattle(state);
      try {
        expect(replayed.battle.inputLog).toEqual(original.battle.inputLog);
        expect(replayed.battle.prng.getSeed()).toBe(original.battle.prng.getSeed());
        expect(replayed.battle.turn).toBe(original.battle.turn);
        expect(replayed.startingHp).toEqual(original.startingHp);
        expect(getPlayerRequest(replayed)).toEqual(getPlayerRequest(original));
        expect(battleParties(replayed)).toEqual(battleParties(original));
        expect(protocolEventsSince(replayed.battle, 0)).toEqual(protocolEventsSince(original.battle, 0));
      } finally {
        replayed.battle.destroy();
      }
    } finally {
      original.battle.destroy();
    }
  });

  it("filters timestamps and p2-only protocol payloads from player events", () => {
    const runtime = startShowdownBattle(
      preparedBattle(
        [member("public", { nickname: "PublicLead" })],
        [
          member("opponent-lead", { nickname: "VisibleLead" }),
          member("opponent-secret", { species: "Mewtwo", nickname: "SecretBench" }),
        ],
      ),
      FIXED_BATTLE_SEED,
    );

    try {
      runtime.battle.add("t:", 1234567890);
      const events = protocolEventsSince(runtime.battle, 0);
      expect(events.some((line) => line.startsWith("|t:|"))).toBe(false);
      expect(events.join("\n")).not.toContain("SecretBench");
      expect(events.join("\n")).not.toContain("opponent-secret");
      expect(events.join("\n")).not.toContain('"forceSwitch"');
      expect(events.join("\n")).not.toContain('"active"');
    } finally {
      runtime.battle.destroy();
    }
  });

  it("rejects invalid typed actions at the simulator boundary", () => {
    const runtime = startShowdownBattle(
      preparedBattle(
        [member("lead", { moves: ["Splash"] }), member("bench")],
        [member("opponent", { moves: ["Splash"] })],
      ),
      FIXED_BATTLE_SEED,
    );

    try {
      expect(() => applyPlayerAction(runtime, { type: "move", moveIndex: 2 })).toThrowError(
        expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
      );
      expect(() =>
        applyPlayerAction(runtime, { type: "switch", memberId: "not-on-team" }),
      ).toThrowError(
        expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
      );

      const choose = vi.spyOn(runtime.battle, "choose").mockImplementation(() => {
        throw new Error("[Unavailable choice] The selected move became unavailable");
      });
      try {
        expect(() => applyPlayerAction(runtime, { type: "move", moveIndex: 1 })).toThrowError(
          expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
        );
      } finally {
        choose.mockRestore();
      }
    } finally {
      runtime.battle.destroy();
    }
  });

  it("enforces the 500-turn safety boundary for active and ended battles", () => {
    expect(() =>
      assertTurnLimit({ ended: false, turn: MAX_BATTLE_TURNS + 1 } as never),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "battle_turn_limit_exceeded",
      }),
    );
    expect(() =>
      assertTurnLimit({ ended: true, turn: MAX_BATTLE_TURNS + 1 } as never),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "battle_turn_limit_exceeded",
      }),
    );
  });

  it("captures an engine tie independently of trainer names", () => {
    const runtime = startShowdownBattle(preparedBattle(), FIXED_BATTLE_SEED);

    try {
      runtime.battle.tie();
      expect(battleResult(runtime)).toEqual({
        winner: "tie",
        reason: "all_pokemon_fainted",
      });
    } finally {
      runtime.battle.destroy();
    }
  });
});
