import { afterAll, beforeEach, describe, expect, it } from "vitest";

import {
  API_VERSION,
  BATTLE_STATE_KEY_ENV,
  ENGINE_VERSION,
  FORMAT_VERSION,
  MAX_STATE_TOKEN_BYTES,
} from "../../src/battle/constants";
import { ServiceError } from "../../src/battle/errors";
import {
  applyBattleAction,
  startBattle,
  type BattleStartOptions,
} from "../../src/battle/service";
import { openStateToken, sealStateToken } from "../../src/battle/token";
import type { BattleResponse, StartBattleRequest } from "../../src/battle/types";
import {
  battleBody,
  FIXED_AI_SEED,
  FIXED_BATTLE_ID,
  FIXED_BATTLE_SEED,
  member,
  semanticResponse,
  TEST_BATTLE_STATE_KEY,
  tokenFrom,
} from "../fixtures";

const ORIGINAL_KEY = process.env[BATTLE_STATE_KEY_ENV];
const FIXED_OPTIONS: BattleStartOptions = {
  battleSeed: FIXED_BATTLE_SEED,
  aiSeed: FIXED_AI_SEED,
  battleId: FIXED_BATTLE_ID,
};

function start(input: StartBattleRequest = battleBody()): BattleResponse {
  return startBattle(input, FIXED_OPTIONS);
}

function act(response: BattleResponse, action: unknown): BattleResponse {
  return applyBattleAction({ stateToken: tokenFrom(response), action });
}

beforeEach(() => {
  process.env[BATTLE_STATE_KEY_ENV] = TEST_BATTLE_STATE_KEY;
});

afterAll(() => {
  if (ORIGINAL_KEY === undefined) {
    delete process.env[BATTLE_STATE_KEY_ENV];
  } else {
    process.env[BATTLE_STATE_KEY_ENV] = ORIGINAL_KEY;
  }
});

describe("battle service", () => {
  it("starts alternate forms whose default display name exceeds nickname limits", () => {
    const response = start(
      battleBody(
        [
          member("rapid-strike", {
            species: "Urshifu-Rapid-Strike",
            moves: ["Surging Strikes"],
          }),
        ],
        [member("opponent", { moves: ["Splash"] })],
      ),
    );

    expect(response).toMatchObject({
      phase: "awaiting_player",
      request: { type: "move", activeMemberId: "rapid-strike" },
      parties: {
        player: [
          {
            memberId: "rapid-strike",
            species: "Urshifu-Rapid-Strike",
            nickname: "Urshifu-Rapid-Strike",
          },
        ],
      },
    });
    expect(openStateToken(tokenFrom(response)).player.team[0].nickname).toBe(
      "Urshifu-Rapid-Strike",
    );
  });

  it("starts at a stable player boundary with rounded HP and retained fainted members", () => {
    const response = start(
      battleBody(
        [
          member("already-fainted", {
            species: "Bulbasaur",
            health: 0,
            moves: ["Tackle"],
          }),
          member("hurt-lead", { health: 0.503, moves: ["Tackle", "Growl"] }),
          member("healthy-bench", { species: "Charmander", moves: ["Ember"] }),
        ],
        [
          member("visible-opponent", { nickname: "VisibleLead", moves: ["Splash"] }),
          member("private-opponent", {
            species: "Mewtwo",
            nickname: "SecretBench",
            moves: ["Psychic"],
          }),
        ],
      ),
    );

    expect(response).toMatchObject({
      apiVersion: API_VERSION,
      engineVersion: ENGINE_VERSION,
      formatVersion: FORMAT_VERSION,
      battleId: FIXED_BATTLE_ID,
      revision: 0,
      phase: "awaiting_player",
      request: { type: "move", activeMemberId: "hurt-lead" },
    });
    expect(response.stateToken).toBeTypeOf("string");
    expect(response.result).toBeUndefined();
    expect(response.parties.player.map((pokemon) => pokemon.memberId)).toEqual([
      "already-fainted",
      "hurt-lead",
      "healthy-bench",
    ]);
    expect(response.parties.player[0]).toMatchObject({ hp: 0, fainted: true, active: false });

    const lead = response.parties.player[1];
    expect(lead.hp).toBe(Math.round(lead.maxHp * 0.503));
    expect(lead.active).toBe(true);
    expect(response.request?.switchOptions).toEqual([{ memberId: "healthy-bench" }]);

    const state = openStateToken(tokenFrom(response));
    expect(state).toMatchObject({
      battleId: FIXED_BATTLE_ID,
      revision: 0,
      memberIds: {
        player: ["hurt-lead", "healthy-bench"],
        opponent: ["visible-opponent", "private-opponent"],
      },
      aiPrngState: FIXED_AI_SEED,
    });
    expect(state.startingHp.player).toEqual([
      lead.hp,
      response.parties.player[2].hp,
    ]);
    expect(response.events.every((line) => !line.startsWith("|t:|"))).toBe(true);
    expect(response.events.join("\n")).not.toContain("SecretBench");
    expect(response.events.join("\n")).not.toContain("private-opponent");
  });

  it("reconstructs from the token and returns deterministic semantics and AI state on retries", () => {
    const initial = start(
      battleBody(
        [member("player", { moves: ["Tackle", "Growl"] })],
        [member("opponent", { moves: ["Splash"] })],
      ),
    );

    const first = act(initial, { type: "move", moveIndex: 1 });
    const retry = act(initial, { type: "move", moveIndex: 1 });

    expect(first.stateToken).not.toBe(retry.stateToken);
    expect(semanticResponse(first)).toEqual(semanticResponse(retry));
    expect(openStateToken(tokenFrom(first))).toEqual(openStateToken(tokenFrom(retry)));

    const firstState = openStateToken(tokenFrom(first));
    expect(firstState.revision).toBe(1);
    expect(firstState.aiPrngState).not.toBe(FIXED_AI_SEED);
    expect(firstState.inputLog.slice(-2)).toEqual([">p1 move tackle", ">p2 move splash"]);
    expect(first.events).toEqual(
      expect.arrayContaining([
        expect.stringContaining("|move|p1a: Pikachu|Tackle|"),
        expect.stringContaining("|move|p2a: Pikachu|Splash|"),
      ]),
    );
    expect(first.parties.player[0].moves[0].pp).toBeLessThan(
      initial.parties.player[0].moves[0].pp,
    );

    const next = act(first, { type: "move", moveIndex: 2 });
    const nextRetry = act(first, { type: "move", moveIndex: 2 });
    expect(semanticResponse(next)).toEqual(semanticResponse(nextRetry));
    expect(openStateToken(tokenFrom(next))).toEqual(openStateToken(tokenFrom(nextRetry)));
  });

  it("explicitly permits old-token forks while keeping branch histories independent", () => {
    const initial = start(
      battleBody(
        [member("player", { moves: ["Tackle", "Growl"] })],
        [member("opponent", { moves: ["Splash"] })],
      ),
    );

    const damageBranch = act(initial, { type: "move", moveIndex: 1 });
    const statusBranch = act(initial, { type: "move", moveIndex: 2 });
    const originalRetry = act(initial, { type: "move", moveIndex: 1 });

    expect(damageBranch).toMatchObject({ battleId: FIXED_BATTLE_ID, revision: 1 });
    expect(statusBranch).toMatchObject({ battleId: FIXED_BATTLE_ID, revision: 1 });
    expect(semanticResponse(originalRetry)).toEqual(semanticResponse(damageBranch));
    expect(openStateToken(tokenFrom(damageBranch)).inputLog).not.toEqual(
      openStateToken(tokenFrom(statusBranch)).inputLog,
    );
  });

  it("preserves caller member identity and roster order across voluntary Showdown reordering", () => {
    const initial = start(
      battleBody(
        [
          member("lead", { species: "Pikachu", moves: ["Splash"] }),
          member("middle", { species: "Bulbasaur", moves: ["Splash"] }),
          member("target", { species: "Charmander", moves: ["Splash"] }),
        ],
        [member("opponent", { moves: ["Splash"] })],
      ),
    );

    const switched = act(initial, { type: "switch", memberId: "target" });
    expect(switched.parties.player.map((pokemon) => pokemon.memberId)).toEqual([
      "lead",
      "middle",
      "target",
    ]);
    expect(switched.parties.player.find((pokemon) => pokemon.active)?.memberId).toBe("target");
    expect(switched.request).toMatchObject({ type: "move", activeMemberId: "target" });
    expect(switched.request?.switchOptions.map((option) => option.memberId).sort()).toEqual([
      "lead",
      "middle",
    ]);
    expect(openStateToken(tokenFrom(switched)).inputLog).toContain(">p1 switch 3");

    const switchedBack = act(switched, { type: "switch", memberId: "lead" });
    expect(switchedBack.parties.player.map((pokemon) => pokemon.memberId)).toEqual([
      "lead",
      "middle",
      "target",
    ]);
    expect(switchedBack.request).toMatchObject({ type: "move", activeMemberId: "lead" });
  });

  it("stops for a forced player replacement after an AI knockout", () => {
    const initial = start(
      battleBody(
        [
          member("fragile", { species: "Magikarp", level: 1, moves: ["Splash"] }),
          member("replacement", { species: "Blissey", level: 100, moves: ["Splash"] }),
        ],
        [member("attacker", { species: "Mewtwo", level: 100, moves: ["Psychic"] })],
      ),
    );

    const knockedOut = act(initial, { type: "move", moveIndex: 1 });
    expect(knockedOut.phase).toBe("awaiting_player");
    expect(knockedOut.request).toEqual({
      type: "switch",
      activeMemberId: "fragile",
      switchOptions: [{ memberId: "replacement" }],
    });
    expect(knockedOut.parties.player[0]).toMatchObject({
      memberId: "fragile",
      hp: 0,
      fainted: true,
    });
    expect(() => act(knockedOut, { type: "move", moveIndex: 1 })).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
    );

    const replaced = act(knockedOut, { type: "switch", memberId: "replacement" });
    expect(replaced.request).toMatchObject({ type: "move", activeMemberId: "replacement" });
    expect(replaced.parties.player.find((pokemon) => pokemon.active)?.memberId).toBe("replacement");
  });

  it("handles simultaneous replacements by waiting for p1, then committing the AI replacement", () => {
    const initial = start(
      battleBody(
        [
          member("player-bomber", {
            species: "Snorlax",
            level: 100,
            moves: ["Explosion"],
          }),
          member("player-backup", { species: "Pikachu", moves: ["Splash"] }),
        ],
        [
          member("ai-target", { species: "Magikarp", level: 1, moves: ["Splash"] }),
          member("ai-backup", { species: "Bulbasaur", moves: ["Splash"] }),
        ],
      ),
    );

    const doubleKnockout = act(initial, { type: "move", moveIndex: 1 });
    expect(doubleKnockout.request).toEqual({
      type: "switch",
      activeMemberId: "player-bomber",
      switchOptions: [{ memberId: "player-backup" }],
    });
    expect(doubleKnockout.parties.player[0]).toMatchObject({ hp: 0, fainted: true });
    expect(doubleKnockout.parties.opponent[0]).toMatchObject({ hp: 0, fainted: true });
    expect(doubleKnockout.parties.opponent[1].active).toBe(false);

    const replacements = act(doubleKnockout, {
      type: "switch",
      memberId: "player-backup",
    });
    expect(replacements.request).toMatchObject({ type: "move", activeMemberId: "player-backup" });
    expect(replacements.parties.player.find((pokemon) => pokemon.active)?.memberId).toBe(
      "player-backup",
    );
    expect(replacements.parties.opponent.find((pokemon) => pokemon.active)?.memberId).toBe(
      "ai-backup",
    );
  });

  it("returns an ended response without a token for forfeit", () => {
    const ended = act(start(), { type: "forfeit" });

    expect(ended).toMatchObject({
      battleId: FIXED_BATTLE_ID,
      revision: 1,
      phase: "ended",
      request: null,
      result: { winner: "opponent", reason: "forfeit" },
    });
    expect(ended.stateToken).toBeUndefined();
  });

  it("plays a deterministic battle through natural completion", () => {
    const initial = start(
      battleBody(
        [member("sweeper", { species: "Mewtwo", level: 100, moves: ["Psychic"] })],
        [member("target", { species: "Magikarp", level: 1, moves: ["Splash"] })],
      ),
    );

    const ended = act(initial, { type: "move", moveIndex: 1 });
    const endedRetry = act(initial, { type: "move", moveIndex: 1 });
    expect(ended).toMatchObject({
      revision: 1,
      phase: "ended",
      request: null,
      result: { winner: "player", reason: "all_pokemon_fainted" },
    });
    expect(ended.stateToken).toBeUndefined();
    expect(ended.parties.opponent[0]).toMatchObject({ hp: 0, fainted: true });
    expect(ended.events).toEqual(expect.arrayContaining([expect.stringContaining("|win|Player")]));
    expect(endedRetry).toEqual(ended);
  });

  it("uses Showdown's winning side for a simultaneous self-knockout", () => {
    const input = battleBody(
      [member("self-ko", { species: "Snorlax", level: 100, moves: ["Explosion"] })],
      [member("target", { species: "Magikarp", level: 1, moves: ["Splash"] })],
    );
    input.player.name = "Same Name";
    input.opponent.name = "Same Name";

    const ended = act(start(input), { type: "move", moveIndex: 1 });
    expect(ended).toMatchObject({
      phase: "ended",
      result: { winner: "opponent", reason: "all_pokemon_fainted" },
    });
    expect(ended.parties.player[0].fainted).toBe(true);
    expect(ended.parties.opponent[0].fainted).toBe(true);
  });

  it("maps malformed, corrupt, incompatible, and replay-invalid tokens to stable errors", () => {
    expect(() =>
      applyBattleAction({ stateToken: "not-a-token", action: { type: "forfeit" } }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_state_token" }),
    );

    const initial = start();
    const token = tokenFrom(initial);
    const last = token.at(-1) === "A" ? "B" : "A";
    expect(() =>
      applyBattleAction({
        stateToken: `${token.slice(0, -1)}${last}`,
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_state_token" }),
    );
    expect(() =>
      applyBattleAction({
        stateToken: token.replace(/^pfr1\./u, "pfr2."),
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );

    const state = openStateToken(token);
    state.inputLog.push(">p1 raw-untrusted-command");
    const replayInvalid = sealStateToken(state);
    expect(() =>
      applyBattleAction({ stateToken: replayInvalid, action: { type: "forfeit" } }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );

    const validGrammarButInvalidChoice = openStateToken(token);
    validGrammarButInvalidChoice.inputLog.push(">p1 switch 6");
    expect(() =>
      applyBattleAction({
        stateToken: sealStateToken(validGrammarButInvalidChoice),
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );
  });

  it("maps incompatible simulator and AI PRNG state to 409", () => {
    const initial = start();

    const invalidBattleSeed = openStateToken(tokenFrom(initial));
    invalidBattleSeed.inputLog[0] =
      '>start {"formatid":"pfrgen9singlesv1","seed":"not-a-prng-seed"}';
    expect(() =>
      applyBattleAction({
        stateToken: sealStateToken(invalidBattleSeed),
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );

    const invalidAiSeed = openStateToken(tokenFrom(initial));
    invalidAiSeed.aiPrngState = "not-a-prng-seed";
    expect(() =>
      applyBattleAction({
        stateToken: sealStateToken(invalidAiSeed),
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );
  });

  it("returns 413 when an action carries a state token larger than 128 KiB", () => {
    expect(() =>
      applyBattleAction({
        stateToken: "x".repeat(MAX_STATE_TOKEN_BYTES + 1),
        action: { type: "forfeit" },
      }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 413,
        code: "state_token_too_large",
      }),
    );
  });

  it("rejects unavailable and mixed action shapes as 422", () => {
    const initial = start(
      battleBody(
        [member("player", { moves: ["Splash"] }), member("bench")],
        [member("opponent", { moves: ["Splash"] })],
      ),
    );
    for (const action of [
      { type: "move", moveIndex: 2 },
      { type: "switch", memberId: "missing" },
      { type: "move", moveIndex: 1, memberId: "bench" },
    ]) {
      expect(() => act(initial, action)).toThrowError(
        expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
      );
    }
  });
});
