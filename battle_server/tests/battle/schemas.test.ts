import { describe, expect, it } from "vitest";

import { MAX_STATE_TOKEN_BYTES } from "../../src/battle/constants";
import { ServiceError } from "../../src/battle/errors";
import {
  battleActionRequestSchema,
  parseBattleActionRequest,
  parseStartBattleRequest,
  startBattleRequestSchema,
} from "../../src/battle/schemas";

function member(memberId = "player-1") {
  return {
    memberId,
    species: "Pikachu",
    level: 50,
    health: 1,
    moves: ["Thunderbolt"],
  };
}

function startBody() {
  return {
    player: { name: "Player", team: [member()] },
    opponent: { name: "CPU", team: [member("opponent-1")] },
  };
}

describe("startBattleRequestSchema", () => {
  it("accepts the complete bounded DTO and strips nothing", () => {
    const body = startBody();
    Object.assign(body.player.team[0], {
      nickname: "Sparky",
      ability: "Static",
      item: "Light Ball",
      nature: "Timid",
      gender: "F",
      ivs: { hp: 0, spe: 31 },
      evs: { spa: 252, spe: 252 },
    });

    expect(startBattleRequestSchema.parse(body)).toEqual(body);
  });

  it("rejects numeric and numeric-string species identifiers", () => {
    const numeric = startBody();
    numeric.player.team[0].species = 25 as unknown as string;
    expect(startBattleRequestSchema.safeParse(numeric).success).toBe(false);

    const numericString = startBody();
    numericString.player.team[0].species = "25";
    expect(startBattleRequestSchema.safeParse(numericString).success).toBe(false);
  });

  it("rejects duplicate and blank memberIds within a side", () => {
    const duplicate = startBody();
    duplicate.player.team.push(member());
    expect(startBattleRequestSchema.safeParse(duplicate).success).toBe(false);

    const blank = startBody();
    blank.player.team[0].memberId = "   ";
    expect(startBattleRequestSchema.safeParse(blank).success).toBe(false);
  });

  it.each([
    ["level below range", { level: 0 }],
    ["level above range", { level: 101 }],
    ["negative health", { health: -0.01 }],
    ["health above one", { health: 1.01 }],
    ["no moves", { moves: [] }],
    ["too many moves", { moves: ["Tackle", "Growl", "Protect", "Rest", "Sleep Talk"] }],
    ["IV above range", { ivs: { hp: 32 } }],
    ["EV above range", { evs: { hp: 253 } }],
    ["invalid gender", { gender: "X" }],
  ])("rejects %s", (_label, replacement) => {
    const body = startBody();
    Object.assign(body.player.team[0], replacement);
    expect(startBattleRequestSchema.safeParse(body).success).toBe(false);
  });

  it("rejects teams outside 1-6 and unknown object fields", () => {
    const empty = startBody();
    empty.player.team = [];
    expect(startBattleRequestSchema.safeParse(empty).success).toBe(false);

    const oversized = startBody();
    oversized.player.team = Array.from({ length: 7 }, (_, index) => member(`p-${index}`));
    expect(startBattleRequestSchema.safeParse(oversized).success).toBe(false);

    const extra = { ...startBody(), rawInputLog: [">p1 move 1"] };
    expect(startBattleRequestSchema.safeParse(extra).success).toBe(false);
  });

  it("maps malformed envelopes to 400 and well-formed invalid teams to 422", () => {
    expect(() => parseStartBattleRequest({ player: startBody().player })).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_request" }),
    );

    const invalidTeam = startBody();
    invalidTeam.player.team[0].level = 101;
    expect(() => parseStartBattleRequest(invalidTeam)).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_team" }),
    );
  });
});

describe("battleActionRequestSchema", () => {
  const stateToken = "opaque-token";

  it.each([
    { stateToken, action: { type: "move", moveIndex: 1 } },
    { stateToken, action: { type: "switch", memberId: "player-2" } },
    { stateToken, action: { type: "forfeit" } },
  ])("accepts exactly one typed action", (body) => {
    expect(battleActionRequestSchema.parse(body)).toEqual(body);
  });

  it.each([
    { stateToken, action: { type: "move", moveIndex: 0 } },
    { stateToken, action: { type: "move", moveIndex: 1, memberId: "p2" } },
    { stateToken, action: { type: "switch", memberId: "p2", moveIndex: 1 } },
    { stateToken, action: { type: "forfeit", moveIndex: 1 } },
    { stateToken, action: { type: "run" } },
    { stateToken, type: "forfeit" },
  ])("rejects malformed or mixed actions", (body) => {
    expect(battleActionRequestSchema.safeParse(body).success).toBe(false);
  });

  it("maps action validation to a stable 422 error", () => {
    expect(() =>
      parseBattleActionRequest({ stateToken, action: { type: "move", moveIndex: 5 } }),
    ).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_action" }),
    );
  });

  it("caps state tokens at 128 KiB", () => {
    const result = battleActionRequestSchema.safeParse({
      stateToken: "x".repeat(MAX_STATE_TOKEN_BYTES + 1),
      action: { type: "forfeit" },
    });
    expect(result.success).toBe(false);
  });
});
