import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from "node:crypto";
import { deflateRawSync, inflateRawSync } from "node:zlib";

import { z } from "zod";

import {
  API_VERSION,
  BATTLE_STATE_KEY_ENV,
  ENGINE_VERSION,
  FORMAT_VERSION,
  MAX_EV,
  MAX_IDENTIFIER_LENGTH,
  MAX_IV,
  MAX_LEVEL,
  MAX_MEMBER_ID_LENGTH,
  MAX_MOVE_COUNT,
  MAX_REPLAY_RECORD_BYTES,
  MAX_REPLAY_RECORDS,
  MAX_SHOWDOWN_NAME_LENGTH,
  MAX_STATE_TOKEN_BYTES,
  MAX_TEAM_SIZE,
  MAX_TOKEN_PAYLOAD_BYTES,
  TOKEN_ENVELOPE_VERSION,
  TOKEN_PREFIX,
  TOKEN_SCHEMA_VERSION,
} from "./constants";
import { ServiceError } from "./errors";
import type { BattleTokenState } from "./types";

const IV_BYTES = 12;
const AUTH_TAG_BYTES = 16;
const HEADER_BYTES = 1 + IV_BYTES + AUTH_TAG_BYTES;
const ALGORITHM = "aes-256-gcm";
const AAD = Buffer.from(`pfr-battle-state:${TOKEN_ENVELOPE_VERSION}`, "utf8");

const statTableSchema = z
  .object({
    hp: z.number().int().min(0).max(MAX_EV),
    atk: z.number().int().min(0).max(MAX_EV),
    def: z.number().int().min(0).max(MAX_EV),
    spa: z.number().int().min(0).max(MAX_EV),
    spd: z.number().int().min(0).max(MAX_EV),
    spe: z.number().int().min(0).max(MAX_EV),
  })
  .strict();

const ivTableSchema = z
  .object({
    hp: z.number().int().min(0).max(MAX_IV),
    atk: z.number().int().min(0).max(MAX_IV),
    def: z.number().int().min(0).max(MAX_IV),
    spa: z.number().int().min(0).max(MAX_IV),
    spd: z.number().int().min(0).max(MAX_IV),
    spe: z.number().int().min(0).max(MAX_IV),
  })
  .strict();

const boundedString = z.string().min(1).max(MAX_IDENTIFIER_LENGTH);

const canonicalMemberSchema = z
  .object({
    memberId: z.string().min(1).max(MAX_MEMBER_ID_LENGTH),
    species: boundedString,
    level: z.number().int().min(1).max(MAX_LEVEL),
    health: z.number().finite().min(0).max(1),
    moves: z.array(boundedString).min(1).max(MAX_MOVE_COUNT),
    // Caller-supplied nicknames are capped at Showdown's 18-character limit,
    // but an omitted nickname defaults to the canonical species-form name,
    // which can legitimately be longer (for example Urshifu-Rapid-Strike).
    nickname: z.string().min(1).max(MAX_IDENTIFIER_LENGTH),
    ability: boundedString,
    item: z.string().max(MAX_IDENTIFIER_LENGTH),
    nature: boundedString,
    gender: z.enum(["M", "F", "N", ""]),
    ivs: ivTableSchema,
    evs: statTableSchema,
  })
  .strict();

const canonicalSideSchema = z
  .object({
    name: z.string().min(1).max(MAX_SHOWDOWN_NAME_LENGTH),
    team: z.array(canonicalMemberSchema).min(1).max(MAX_TEAM_SIZE),
  })
  .strict();

const memberIdsSchema = z
  .object({
    player: z.array(z.string().min(1).max(MAX_MEMBER_ID_LENGTH)).min(1).max(MAX_TEAM_SIZE),
    opponent: z.array(z.string().min(1).max(MAX_MEMBER_ID_LENGTH)).min(1).max(MAX_TEAM_SIZE),
  })
  .strict();

const startingHpSchema = z
  .object({
    player: z.array(z.number().int().positive()).min(1).max(MAX_TEAM_SIZE),
    opponent: z.array(z.number().int().positive()).min(1).max(MAX_TEAM_SIZE),
  })
  .strict();

export const battleTokenStateSchema = z
  .object({
    schemaVersion: z.literal(TOKEN_SCHEMA_VERSION),
    apiVersion: z.literal(API_VERSION),
    engineVersion: z.literal(ENGINE_VERSION),
    formatVersion: z.literal(FORMAT_VERSION),
    battleId: z.string().min(1).max(128),
    revision: z.number().int().nonnegative().safe(),
    inputLog: z
      .array(z.string().min(1).max(MAX_REPLAY_RECORD_BYTES))
      .min(3)
      .max(MAX_REPLAY_RECORDS),
    player: canonicalSideSchema,
    opponent: canonicalSideSchema,
    memberIds: memberIdsSchema,
    startingHp: startingHpSchema,
    aiPrngState: z.string().min(1).max(256),
  })
  .strict()
  .superRefine((state, context) => {
    for (const side of ["player", "opponent"] as const) {
      const expectedIds = state[side].team
        .filter((member) => member.health > 0)
        .map((member) => member.memberId);
      const actualIds = state.memberIds[side];
      if (
        expectedIds.length !== actualIds.length ||
        expectedIds.some((memberId, index) => memberId !== actualIds[index])
      ) {
        context.addIssue({
          code: "custom",
          path: ["memberIds", side],
          message: "Living memberIds must match the canonical roster order",
        });
      }
      if (state.startingHp[side].length !== actualIds.length) {
        context.addIssue({
          code: "custom",
          path: ["startingHp", side],
          message: "startingHp must be parallel to memberIds",
        });
      }
      if (new Set(state[side].team.map((member) => member.memberId)).size !== state[side].team.length) {
        context.addIssue({
          code: "custom",
          path: [side, "team"],
          message: "memberId values must be unique within a team",
        });
      }
    }
  });

function configurationError(message: string): never {
  throw new ServiceError(500, "server_configuration_error", message, {
    expose: false,
  });
}

function readEncryptionKey(): Buffer {
  const encoded = process.env[BATTLE_STATE_KEY_ENV];
  if (!encoded) {
    configurationError(`${BATTLE_STATE_KEY_ENV} is not configured`);
  }

  const standardBase64 = /^[A-Za-z0-9+/]{43}=$/u.test(encoded);
  const urlBase64 = /^[A-Za-z0-9_-]{43}=?$/u.test(encoded);
  if (!standardBase64 && !urlBase64) {
    configurationError(`${BATTLE_STATE_KEY_ENV} must be a base64-encoded 32-byte key`);
  }

  const key = Buffer.from(encoded, urlBase64 ? "base64url" : "base64");
  if (key.length !== 32) {
    configurationError(`${BATTLE_STATE_KEY_ENV} must decode to exactly 32 bytes`);
  }
  return key;
}

function invalidToken(message = "Invalid state token", cause?: unknown): ServiceError {
  return new ServiceError(400, "invalid_state_token", message, { cause });
}

function incompatibleToken(message: string): ServiceError {
  return new ServiceError(409, "incompatible_state_token", message);
}

function assertCompatibleVersionFields(value: unknown): void {
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  const record = value as Record<string, unknown>;

  if (
    (record.schemaVersion !== undefined && record.schemaVersion !== TOKEN_SCHEMA_VERSION) ||
    (record.apiVersion !== undefined && record.apiVersion !== API_VERSION) ||
    (record.engineVersion !== undefined && record.engineVersion !== ENGINE_VERSION) ||
    (record.formatVersion !== undefined && record.formatVersion !== FORMAT_VERSION)
  ) {
    throw incompatibleToken("State token version is not compatible with this service");
  }
}

function encodedPayload(token: string): string {
  if (Buffer.byteLength(token, "utf8") > MAX_STATE_TOKEN_BYTES) {
    throw new ServiceError(413, "state_token_too_large", "State token exceeds 128 KiB");
  }

  const match = /^pfr(\d+)\.([A-Za-z0-9_-]+)$/u.exec(token);
  if (!match) throw invalidToken();
  if (Number(match[1]) !== TOKEN_ENVELOPE_VERSION) {
    throw incompatibleToken("State token envelope version is not supported");
  }
  return match[2];
}

function decodeEnvelope(encoded: string): Buffer {
  let envelope: Buffer;
  try {
    envelope = Buffer.from(encoded, "base64url");
  } catch (error) {
    throw invalidToken(undefined, error);
  }

  if (envelope.toString("base64url") !== encoded || envelope.length <= HEADER_BYTES) {
    throw invalidToken();
  }
  if (envelope[0] !== TOKEN_ENVELOPE_VERSION) {
    throw incompatibleToken("State token envelope version is not supported");
  }
  return envelope;
}

function parseDecryptedState(compressed: Buffer): BattleTokenState {
  let plaintext: Buffer;
  try {
    plaintext = inflateRawSync(compressed, { maxOutputLength: MAX_TOKEN_PAYLOAD_BYTES });
  } catch (error) {
    const code = (error as NodeJS.ErrnoException | undefined)?.code;
    if (code === "ERR_BUFFER_TOO_LARGE") {
      throw new ServiceError(413, "state_token_too_large", "Decoded state exceeds 128 KiB", {
        cause: error,
      });
    }
    throw invalidToken(undefined, error);
  }

  if (plaintext.length > MAX_TOKEN_PAYLOAD_BYTES) {
    throw new ServiceError(413, "state_token_too_large", "Decoded state exceeds 128 KiB");
  }

  let value: unknown;
  try {
    value = JSON.parse(plaintext.toString("utf8"));
  } catch (error) {
    throw invalidToken(undefined, error);
  }

  assertCompatibleVersionFields(value);
  const result = battleTokenStateSchema.safeParse(value);
  if (!result.success) {
    throw invalidToken();
  }
  return result.data;
}

export function sealStateToken(state: BattleTokenState): string {
  assertCompatibleVersionFields(state);
  const parsed = battleTokenStateSchema.safeParse(state);
  if (!parsed.success) {
    throw new ServiceError(500, "invalid_battle_state", "Cannot encode invalid battle state", {
      cause: parsed.error,
      expose: false,
    });
  }

  const plaintext = Buffer.from(JSON.stringify(parsed.data), "utf8");
  if (plaintext.length > MAX_TOKEN_PAYLOAD_BYTES) {
    throw new ServiceError(413, "state_token_too_large", "Battle state exceeds 128 KiB");
  }

  const compressed = deflateRawSync(plaintext, { level: 9 });
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, readEncryptionKey(), iv);
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
  const envelope = Buffer.concat([
    Buffer.from([TOKEN_ENVELOPE_VERSION]),
    iv,
    cipher.getAuthTag(),
    ciphertext,
  ]);
  const token = `${TOKEN_PREFIX}.${envelope.toString("base64url")}`;

  if (Buffer.byteLength(token, "utf8") > MAX_STATE_TOKEN_BYTES) {
    throw new ServiceError(413, "state_token_too_large", "State token exceeds 128 KiB");
  }
  return token;
}

export function openStateToken(token: string): BattleTokenState {
  if (typeof token !== "string") throw invalidToken();

  const envelope = decodeEnvelope(encodedPayload(token));
  const iv = envelope.subarray(1, 1 + IV_BYTES);
  const tag = envelope.subarray(1 + IV_BYTES, HEADER_BYTES);
  const ciphertext = envelope.subarray(HEADER_BYTES);

  let compressed: Buffer;
  try {
    const decipher = createDecipheriv(ALGORITHM, readEncryptionKey(), iv);
    decipher.setAAD(AAD);
    decipher.setAuthTag(tag);
    compressed = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch (error) {
    if (error instanceof ServiceError) throw error;
    throw invalidToken(undefined, error);
  }

  return parseDecryptedState(compressed);
}
