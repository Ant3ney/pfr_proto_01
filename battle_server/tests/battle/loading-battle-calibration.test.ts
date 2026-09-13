import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { BATTLE_STATE_KEY_ENV } from "../../src/battle/constants";
import { applyBattleAction, startBattle } from "../../src/battle/service";
import type {
  BattleResponse,
  StartBattleRequest,
  TeamMemberInput,
} from "../../src/battle/types";
import { TEST_BATTLE_STATE_KEY, tokenFrom } from "../fixtures";

const ORIGINAL_KEY = process.env[BATTLE_STATE_KEY_ENV];
const STARTERS = ["charmander", "froakie", "treecko"] as const;
type Starter = (typeof STARTERS)[number];
type Tier = "easy" | "medium" | "hard" | "impossible";

const STANDARD_MOVES: Record<Starter, string[]> = {
  charmander: ["Fire Fang", "Scratch", "Smokescreen", "Thunder Punch"],
  froakie: ["Water Pulse", "Quick Attack", "Smokescreen", "Ice Beam"],
  treecko: ["Leaf Blade", "Quick Attack", "Leer", "Rock Tomb"],
};

const EXHIBITION_MOVES: Record<Starter, string[]> = {
  charmander: ["Scratch", "Slash", "Dragon Claw", "Brick Break"],
  froakie: ["Pound", "Quick Attack", "Aerial Ace", "Thief"],
  treecko: ["Pound", "Quick Attack", "Aerial Ace", "Brick Break"],
};

const EASY: Record<Starter, Pick<TeamMemberInput, "species" | "moves">> = {
  charmander: { species: "Treecko", moves: ["Absorb", "Mega Drain", "Pound", "Leer"] },
  froakie: { species: "Charmander", moves: ["Ember", "Fire Spin", "Scratch", "Smokescreen"] },
  treecko: { species: "Froakie", moves: ["Water Gun", "Bubble", "Pound", "Smokescreen"] },
};

const HARD: Record<
  Starter,
  Pick<TeamMemberInput, "species" | "moves"> &
    Partial<Pick<TeamMemberInput, "nature" | "evs" | "item">>
> = {
  charmander: {
    species: "Froakie",
    moves: ["Water Pulse", "Bubble Beam", "Quick Attack", "Smokescreen"],
    nature: "Modest",
    evs: { spa: 84 },
  },
  froakie: {
    species: "Treecko",
    moves: ["Leaf Blade", "Magical Leaf", "Quick Attack", "Leer"],
    evs: { hp: 84, atk: 84, spa: 84, spd: 84 },
    item: "Oran Berry",
  },
  treecko: {
    species: "Charmander",
    moves: ["Fire Fang", "Flame Burst", "Scratch", "Smokescreen"],
  },
};

function titleCase(value: Starter): string {
  return `${value[0].toUpperCase()}${value.slice(1)}`;
}

function body(starter: Starter, tier: Tier): StartBattleRequest {
  let opponent: TeamMemberInput;
  if (tier === "medium") {
    opponent = {
      memberId: "practice-opponent",
      species: "Ditto",
      level: 22,
      health: 0.85,
      moves: ["Transform"],
      ability: "Imposter",
      item: "Leftovers",
    };
  } else if (tier === "impossible") {
    opponent = {
      memberId: "practice-opponent",
      species: "Wobbuffet",
      level: 50,
      health: 1,
      moves: ["Counter"],
      nature: "Sassy",
      ivs: { spe: 0 },
      evs: { spe: 0 },
    };
  } else {
    const authored = tier === "easy" ? EASY[starter] : HARD[starter];
    opponent = {
      memberId: "practice-opponent",
      level: tier === "easy" ? 18 : 22,
      health: 1,
      ...authored,
      moves: [...authored.moves],
    };
  }
  return {
    player: {
      name: "Player",
      team: [{
        memberId: "practice-player",
        species: titleCase(starter),
        level: 20,
        health: 1,
        moves: [...(tier === "impossible" ? EXHIBITION_MOVES : STANDARD_MOVES)[starter]],
      }],
    },
    opponent: { name: "Practice CPU", team: [opponent] },
  };
}

function seed(index: number, salt: number): string {
  return [
    101 + index * 97 + salt,
    503 + index * 193 + salt * 3,
    907 + index * 389 + salt * 5,
    1301 + index * 769 + salt * 7,
  ].map((value) => value % 65536).join(",");
}

function play(
  starter: Starter,
  tier: Tier,
  matrixIndex: number,
  chooseMove: (response: BattleResponse, turn: number) => number,
): BattleResponse["result"] {
  let response = startBattle(body(starter, tier), {
    battleSeed: seed(matrixIndex, STARTERS.indexOf(starter) + 1),
    aiSeed: seed(matrixIndex, STARTERS.indexOf(starter) + 31),
    battleId: `loading-${tier}-${starter}-${matrixIndex}`,
  });
  let turn = 0;
  while (response.phase !== "ended") {
    if (response.request?.type !== "move") {
      throw new Error(`Unexpected loading-battle request: ${response.request?.type}`);
    }
    response = applyBattleAction({
      stateToken: tokenFrom(response),
      action: { type: "move", moveIndex: chooseMove(response, turn) },
    });
    turn += 1;
    if (turn > 100) throw new Error("Loading battle exceeded 100 player decisions");
  }
  return response.result;
}

const RATE_CACHE = new Map<string, number>();

function winRate(starter: Starter, tier: Exclude<Tier, "impossible">, moveIndex: number): number {
  const cacheKey = `${starter}:${tier}:${moveIndex}`;
  const cached = RATE_CACHE.get(cacheKey);
  if (cached !== undefined) return cached;
  const samples = 40;
  let wins = 0;
  for (let index = 0; index < samples; index += 1) {
    if (play(starter, tier, index, () => moveIndex)?.winner === "player") wins += 1;
  }
  const rate = wins / samples;
  RATE_CACHE.set(cacheKey, rate);
  return rate;
}

beforeAll(() => {
  process.env[BATTLE_STATE_KEY_ENV] = TEST_BATTLE_STATE_KEY;
});

afterAll(() => {
  if (ORIGINAL_KEY === undefined) delete process.env[BATTLE_STATE_KEY_ENV];
  else process.env[BATTLE_STATE_KEY_ENV] = ORIGINAL_KEY;
});

describe("loading battle calibration", () => {
  it("keeps Easy preferred attacks reliably winnable", () => {
    for (const starter of STARTERS) {
      expect(winRate(starter, "easy", 1), starter).toBeGreaterThanOrEqual(0.75);
    }
  }, 30000);

  it("keeps the 85%-health Imposter mirror competitive", () => {
    const preferred: Record<Starter, number> = { charmander: 4, froakie: 1, treecko: 1 };
    for (const starter of STARTERS) {
      const rate = winRate(starter, "medium", preferred[starter]);
      expect(rate, starter).toBeGreaterThanOrEqual(0.35);
      expect(rate, starter).toBeLessThanOrEqual(0.75);
    }
  }, 30000);

  it("keeps Hard coverage wins rare and materially below Medium", () => {
    const mediumPreferred: Record<Starter, number> = { charmander: 4, froakie: 1, treecko: 1 };
    for (const starter of STARTERS) {
      const mediumRate = winRate(starter, "medium", mediumPreferred[starter]);
      const hardRate = winRate(starter, "hard", 4);
      expect(hardRate, starter).toBeGreaterThanOrEqual(0.05);
      expect(hardRate, starter).toBeLessThanOrEqual(0.35);
      expect(mediumRate - hardRate, starter).toBeGreaterThanOrEqual(0.15);
    }
  }, 30000);

  it("makes every fixed and cycling physical exhibition sequence lose", () => {
    const policies = [
      () => 1,
      () => 2,
      () => 3,
      () => 4,
      (_response: BattleResponse, turn: number) => (turn % 4) + 1,
    ];
    for (const starter of STARTERS) {
      for (let matrixIndex = 0; matrixIndex < 16; matrixIndex += 1) {
        for (const policy of policies) {
          expect(play(starter, "impossible", matrixIndex, policy)?.winner, starter).toBe("opponent");
        }
      }
    }
  }, 20000);
});
