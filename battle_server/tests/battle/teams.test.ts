import { describe, expect, it } from "vitest";

import { ServiceError } from "../../src/battle/errors";
import {
  calculateMemberMaxHp,
  canonicalizeStartRequest,
  prepareBattleTeams,
  resolveStartingHp,
  toShowdownTeam,
} from "../../src/battle/teams";

function member(memberId: string, overrides: Record<string, unknown> = {}) {
  return {
    memberId,
    species: "Pikachu",
    level: 50,
    health: 1,
    moves: ["thunderbolt"],
    ...overrides,
  };
}

function startBody(playerTeam = [member("p1")], opponentTeam = [member("o1")]) {
  return {
    player: { name: "Player", team: playerTeam },
    opponent: { name: "CPU", team: opponentTeam },
  };
}

describe("team canonicalization", () => {
  it("canonicalizes identifiers and fills every documented default", () => {
    const canonical = canonicalizeStartRequest(startBody());
    const pokemon = canonical.player.team[0];

    expect(pokemon).toEqual({
      memberId: "p1",
      species: "Pikachu",
      level: 50,
      health: 1,
      moves: ["Thunderbolt"],
      nickname: "Pikachu",
      ability: "Static",
      item: "",
      nature: "Serious",
      gender: "",
      ivs: { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 },
      evs: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 },
    });
  });

  it("honors optional fields and fills omitted stat entries", () => {
    const canonical = canonicalizeStartRequest(
      startBody([
        member("p1", {
          nickname: "Sparky",
          ability: "Lightning Rod",
          item: "lightball",
          nature: "timid",
          gender: "F",
          ivs: { atk: 0 },
          evs: { spe: 252 },
        }),
      ]),
    );

    expect(canonical.player.team[0]).toMatchObject({
      nickname: "Sparky",
      ability: "Lightning Rod",
      item: "Light Ball",
      nature: "Timid",
      gender: "F",
      ivs: { hp: 31, atk: 0, def: 31, spa: 31, spd: 31, spe: 31 },
      evs: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 252 },
    });
  });

  it("accepts a long alternate-form name when nickname is omitted", () => {
    const canonical = canonicalizeStartRequest(
      startBody([
        member("rapid-strike", {
          species: "Urshifu-Rapid-Strike",
          moves: ["Surging Strikes"],
        }),
      ]),
    );

    expect(canonical.player.team[0]).toMatchObject({
      species: "Urshifu-Rapid-Strike",
      nickname: "Urshifu-Rapid-Strike",
      ability: "Unseen Fist",
    });
  });

  it("validates identifier existence without enforcing learnsets or species legality", () => {
    const canonical = canonicalizeStartRequest(
      startBody([
        member("p1", {
          moves: ["Roar of Time"],
          ability: "Levitate",
        }),
      ]),
    );
    expect(canonical.player.team[0]).toMatchObject({
      moves: ["Roar of Time"],
      ability: "Levitate",
    });

    for (const overrides of [
      { species: "Missingno-Definitely-Unknown" },
      { moves: ["Definitely Not A Move"] },
      { ability: "Definitely Not An Ability" },
      { item: "Definitely Not An Item" },
      { nature: "Definitely Not A Nature" },
    ]) {
      expect(() => canonicalizeStartRequest(startBody([member("p1", overrides)]))).toThrowError(
        expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_team" }),
      );
    }
  });

  it("retains zero-health roster members but excludes them from simulation", () => {
    const canonical = canonicalizeStartRequest(
      startBody([
        member("fainted", { species: "Bulbasaur", health: 0, moves: ["Tackle"] }),
        member("living", { health: 0.25 }),
      ]),
    );
    const prepared = prepareBattleTeams(canonical);

    expect(prepared.player.roster.map((entry) => entry.memberId)).toEqual(["fainted", "living"]);
    expect(prepared.player.memberIds).toEqual(["living"]);
    expect(prepared.player.normalizedHealth).toEqual([0.25]);
    expect(prepared.player.team).toHaveLength(1);
    expect(prepared.player.team[0]).not.toHaveProperty("memberId");
  });

  it("rejects either side when all members begin fainted", () => {
    expect(() => canonicalizeStartRequest(startBody([member("p1", { health: 0 })]))).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 422, code: "invalid_team" }),
    );
    expect(() =>
      canonicalizeStartRequest(startBody(undefined, [member("o1", { health: 0 })])),
    ).toThrowError(expect.objectContaining<Partial<ServiceError>>({ status: 422 }));
  });

  it("returns deep-cloned living Showdown sets in original order", () => {
    const canonical = canonicalizeStartRequest(
      startBody([
        member("p1", { health: 0.75 }),
        member("p2", { health: 0 }),
        member("p3", { species: "Bulbasaur", moves: ["Tackle"] }),
      ]),
    );

    const first = toShowdownTeam(canonical.player);
    expect(first.map((set) => set.species)).toEqual(["Pikachu", "Bulbasaur"]);
    first[0].moves[0] = "Growl";
    first[0].ivs.hp = 0;

    const second = toShowdownTeam(canonical.player);
    expect(second[0].moves).toEqual(["Thunderbolt"]);
    expect(second[0].ivs.hp).toBe(31);
  });

  it("allows the same memberId on different sides", () => {
    expect(() => canonicalizeStartRequest(startBody([member("same")], [member("same")]))).not.toThrow();
  });
});

describe("HP helpers", () => {
  it.each([
    [100, 0, 0],
    [100, 0.001, 1],
    [301, 0.5, 151],
    [301, 1, 301],
  ])("resolves maxHp=%i normalized=%f to %i", (maxHp, normalized, expected) => {
    expect(resolveStartingHp(maxHp, normalized)).toBe(expected);
  });

  it("rejects invalid max HP and normalized input", () => {
    expect(() => resolveStartingHp(0, 1)).toThrow(RangeError);
    expect(() => resolveStartingHp(100.5, 1)).toThrow(RangeError);
    expect(() => resolveStartingHp(100, -0.1)).toThrow(RangeError);
    expect(() => resolveStartingHp(100, Number.NaN)).toThrow(RangeError);
  });

  it("calculates Gen 9 max HP, including Shedinja's special case", () => {
    const pikachu = canonicalizeStartRequest(startBody()).player.team[0];
    expect(calculateMemberMaxHp(pikachu)).toBe(110);

    const shedinja = canonicalizeStartRequest(
      startBody([member("shed", { species: "Shedinja", moves: ["Scratch"] })]),
    ).player.team[0];
    expect(calculateMemberMaxHp(shedinja)).toBe(1);
  });
});
