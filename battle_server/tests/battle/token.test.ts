import { createCipheriv } from "node:crypto";
import { deflateRawSync } from "node:zlib";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  API_VERSION,
  BATTLE_STATE_KEY_ENV,
  ENGINE_VERSION,
  FORMAT_VERSION,
  MAX_REPLAY_RECORDS,
  MAX_STATE_TOKEN_BYTES,
  TOKEN_ENVELOPE_VERSION,
  TOKEN_SCHEMA_VERSION,
} from "../../src/battle/constants";
import { ServiceError } from "../../src/battle/errors";
import { canonicalizeStartRequest } from "../../src/battle/teams";
import {
  battleTokenStateSchema,
  openStateToken,
  sealStateToken,
} from "../../src/battle/token";
import type { BattleTokenState } from "../../src/battle/types";

const TEST_KEY = Buffer.alloc(32, 7);
const ORIGINAL_KEY = process.env[BATTLE_STATE_KEY_ENV];

function state(): BattleTokenState {
  const canonical = canonicalizeStartRequest({
    player: {
      name: "Player",
      team: [
        {
          memberId: "p-fainted",
          species: "Bulbasaur",
          level: 25,
          health: 0,
          moves: ["Tackle"],
        },
        {
          memberId: "p-live",
          species: "Pikachu",
          level: 50,
          health: 0.5,
          moves: ["Thunderbolt"],
        },
      ],
    },
    opponent: {
      name: "CPU",
      team: [
        {
          memberId: "o-live",
          species: "Squirtle",
          level: 50,
          health: 1,
          moves: ["Water Gun"],
        },
      ],
    },
  });

  return {
    schemaVersion: TOKEN_SCHEMA_VERSION,
    apiVersion: API_VERSION,
    engineVersion: ENGINE_VERSION,
    formatVersion: FORMAT_VERSION,
    battleId: "de305d54-75b4-431b-adb2-eb6b9e546014",
    revision: 3,
    inputLog: [
      '>start {"formatid":"pfrgen9singlesv1","seed":"1,2,3,4"}',
      '>player p1 {"name":"Player","team":"packed-player"}',
      '>player p2 {"name":"CPU","team":"packed-opponent"}',
      ">p1 move 1",
      ">p2 move 1",
    ],
    player: canonical.player,
    opponent: canonical.opponent,
    memberIds: { player: ["p-live"], opponent: ["o-live"] },
    startingHp: { player: [55], opponent: [120] },
    aiPrngState: "1,2,3,4",
  };
}

function rawToken(value: unknown): string {
  const plaintext = Buffer.from(JSON.stringify(value), "utf8");
  const compressed = deflateRawSync(plaintext, { level: 9 });
  const iv = Buffer.alloc(12, 4);
  const cipher = createCipheriv("aes-256-gcm", TEST_KEY, iv);
  cipher.setAAD(Buffer.from(`pfr-battle-state:${TOKEN_ENVELOPE_VERSION}`, "utf8"));
  const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
  const envelope = Buffer.concat([
    Buffer.from([TOKEN_ENVELOPE_VERSION]),
    iv,
    cipher.getAuthTag(),
    ciphertext,
  ]);
  return `pfr${TOKEN_ENVELOPE_VERSION}.${envelope.toString("base64url")}`;
}

beforeEach(() => {
  process.env[BATTLE_STATE_KEY_ENV] = TEST_KEY.toString("base64");
});

afterEach(() => {
  if (ORIGINAL_KEY === undefined) {
    delete process.env[BATTLE_STATE_KEY_ENV];
  } else {
    process.env[BATTLE_STATE_KEY_ENV] = ORIGINAL_KEY;
  }
});

describe("battle state tokens", () => {
  it("round-trips compressed authenticated state without losing replay or PRNG data", () => {
    const original = state();
    const token = sealStateToken(original);

    expect(token).toMatch(/^pfr1\.[A-Za-z0-9_-]+$/u);
    expect(Buffer.byteLength(token)).toBeLessThanOrEqual(MAX_STATE_TOKEN_BYTES);
    expect(openStateToken(token)).toEqual(original);
  });

  it("uses a fresh GCM nonce for identical state", () => {
    const current = state();
    expect(sealStateToken(current)).not.toBe(sealStateToken(current));
  });

  it("rejects token corruption and the wrong key as malformed token errors", () => {
    const token = sealStateToken(state());
    const finalCharacter = token.at(-1) === "A" ? "B" : "A";
    const corrupted = `${token.slice(0, -1)}${finalCharacter}`;
    expect(() => openStateToken(corrupted)).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_state_token" }),
    );

    process.env[BATTLE_STATE_KEY_ENV] = Buffer.alloc(32, 8).toString("base64");
    expect(() => openStateToken(token)).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_state_token" }),
    );
  });

  it.each([
    ["schemaVersion", 2],
    ["apiVersion", "v2"],
    ["engineVersion", "0.11.12"],
    ["formatVersion", "pfr-gen9-singles-v2"],
  ])("maps incompatible %s to 409", (field, value) => {
    const incompatible = { ...state(), [field]: value };
    expect(() => openStateToken(rawToken(incompatible))).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 409,
        code: "incompatible_state_token",
      }),
    );
  });

  it("maps unsupported outer envelope versions to 409", () => {
    const token = sealStateToken(state());
    expect(() => openStateToken(token.replace(/^pfr1\./u, "pfr2."))).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 409 }),
    );
  });

  it("rejects authenticated but structurally invalid payloads", () => {
    const invalid = { ...state(), memberIds: { player: ["wrong"], opponent: ["o-live"] } };
    expect(() => openStateToken(rawToken(invalid))).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 400, code: "invalid_state_token" }),
    );
  });

  it("requires aligned resolved HP and live member mappings", () => {
    const invalid = { ...state(), startingHp: { player: [], opponent: [120] } };
    expect(battleTokenStateSchema.safeParse(invalid).success).toBe(false);
  });

  it("caps replay records using the 500-turn safety budget", () => {
    const oversizedLog = {
      ...state(),
      inputLog: Array.from({ length: MAX_REPLAY_RECORDS + 1 }, () => ">p1 move 1"),
    };
    expect(battleTokenStateSchema.safeParse(oversizedLog).success).toBe(false);
  });

  it("returns 413 for encoded and decoded state over 128 KiB", () => {
    expect(() => openStateToken("x".repeat(MAX_STATE_TOKEN_BYTES + 1))).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 413 }),
    );

    const decompressionBomb = rawToken({ ...state(), padding: "x".repeat(140 * 1024) });
    expect(() => openStateToken(decompressionBomb)).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 413 }),
    );
  });

  it("fails closed when the single configured key is absent or not 256 bits", () => {
    delete process.env[BATTLE_STATE_KEY_ENV];
    expect(() => sealStateToken(state())).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({
        status: 500,
        code: "server_configuration_error",
      }),
    );

    process.env[BATTLE_STATE_KEY_ENV] = Buffer.alloc(16).toString("base64");
    expect(() => sealStateToken(state())).toThrowError(
      expect.objectContaining<Partial<ServiceError>>({ status: 500 }),
    );
  });

  it("accepts padded base64 and unpadded base64url encodings of a 256-bit key", () => {
    const base64Token = sealStateToken(state());
    expect(openStateToken(base64Token)).toEqual(state());

    process.env[BATTLE_STATE_KEY_ENV] = TEST_KEY.toString("base64url");
    const base64urlToken = sealStateToken(state());
    expect(openStateToken(base64urlToken)).toEqual(state());
  });
});
