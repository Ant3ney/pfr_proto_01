import { z } from "zod";

import {
  MAX_EV,
  MAX_IDENTIFIER_LENGTH,
  MAX_IV,
  MAX_LEVEL,
  MAX_MEMBER_ID_LENGTH,
  MAX_MOVE_COUNT,
  MAX_SHOWDOWN_NAME_LENGTH,
  MAX_STATE_TOKEN_BYTES,
  MAX_TEAM_SIZE,
  MIN_EV,
  MIN_IV,
  MIN_LEVEL,
  MIN_MOVE_COUNT,
  MIN_TEAM_SIZE,
} from "./constants";
import { ServiceError } from "./errors";
import type { BattleActionRequest, StartBattleRequest } from "./types";

const identifierSchema = z.string().trim().min(1).max(MAX_IDENTIFIER_LENGTH);

const showdownNameSchema = z
  .string()
  .trim()
  .min(1)
  .max(MAX_SHOWDOWN_NAME_LENGTH)
  .refine((value) => !/[|,\[\]\u202e]|[^\S ]| {2}/u.test(value), {
    message: "Contains characters that are unsafe in Showdown protocol names",
  });

const statSchema = (minimum: number, maximum: number) =>
  z.number().int().min(minimum).max(maximum);

export const ivsSchema = z
  .object({
    hp: statSchema(MIN_IV, MAX_IV).optional(),
    atk: statSchema(MIN_IV, MAX_IV).optional(),
    def: statSchema(MIN_IV, MAX_IV).optional(),
    spa: statSchema(MIN_IV, MAX_IV).optional(),
    spd: statSchema(MIN_IV, MAX_IV).optional(),
    spe: statSchema(MIN_IV, MAX_IV).optional(),
  })
  .strict();

export const evsSchema = z
  .object({
    hp: statSchema(MIN_EV, MAX_EV).optional(),
    atk: statSchema(MIN_EV, MAX_EV).optional(),
    def: statSchema(MIN_EV, MAX_EV).optional(),
    spa: statSchema(MIN_EV, MAX_EV).optional(),
    spd: statSchema(MIN_EV, MAX_EV).optional(),
    spe: statSchema(MIN_EV, MAX_EV).optional(),
  })
  .strict();

export const teamMemberSchema = z
  .object({
    memberId: z.string().trim().min(1).max(MAX_MEMBER_ID_LENGTH),
    species: identifierSchema.refine((value) => !/^\d+$/u.test(value), {
      message: "Species must be a name, not a numeric PokéAPI ID",
    }),
    level: z.number().int().min(MIN_LEVEL).max(MAX_LEVEL),
    health: z.number().finite().min(0).max(1),
    moves: z.array(identifierSchema).min(MIN_MOVE_COUNT).max(MAX_MOVE_COUNT),
    nickname: showdownNameSchema.optional(),
    ability: identifierSchema.optional(),
    item: z.string().trim().max(MAX_IDENTIFIER_LENGTH).optional(),
    nature: identifierSchema.optional(),
    gender: z.enum(["M", "F", "N"]).optional(),
    ivs: ivsSchema.optional(),
    evs: evsSchema.optional(),
  })
  .strict();

export const battleSideSchema = z
  .object({
    name: showdownNameSchema,
    team: z
      .array(teamMemberSchema)
      .min(MIN_TEAM_SIZE)
      .max(MAX_TEAM_SIZE)
      .superRefine((members, context) => {
        const seen = new Set<string>();
        for (const [index, member] of members.entries()) {
          if (seen.has(member.memberId)) {
            context.addIssue({
              code: "custom",
              message: "memberId values must be unique within a team",
              path: [index, "memberId"],
            });
          }
          seen.add(member.memberId);
        }
      }),
  })
  .strict();

export const startBattleRequestSchema = z
  .object({
    player: battleSideSchema,
    opponent: battleSideSchema,
  })
  .strict();

export const moveActionSchema = z
  .object({
    type: z.literal("move"),
    moveIndex: z.number().int().min(1).max(MAX_MOVE_COUNT),
  })
  .strict();

export const switchActionSchema = z
  .object({
    type: z.literal("switch"),
    memberId: z.string().trim().min(1).max(MAX_MEMBER_ID_LENGTH),
  })
  .strict();

export const forfeitActionSchema = z.object({ type: z.literal("forfeit") }).strict();

export const battleActionSchema = z.discriminatedUnion("type", [
  moveActionSchema,
  switchActionSchema,
  forfeitActionSchema,
]);

export const battleActionRequestSchema = z
  .object({
    stateToken: z.string().min(1).max(MAX_STATE_TOKEN_BYTES),
    action: battleActionSchema,
  })
  .strict();

function issueDetails(error: z.ZodError): unknown {
  return error.issues.map((issue) => ({
    path: issue.path.join("."),
    message: issue.message,
  }));
}

export function parseStartBattleRequest(value: unknown): StartBattleRequest {
  const result = startBattleRequestSchema.safeParse(value);
  if (!result.success) {
    const isTeamError = result.error.issues.some(
      (issue) =>
        (issue.path[0] === "player" || issue.path[0] === "opponent") && issue.path.length >= 2,
    );
    throw new ServiceError(
      isTeamError ? 422 : 400,
      isTeamError ? "invalid_team" : "invalid_request",
      isTeamError ? "Invalid team" : "Invalid battle request",
      {
        details: issueDetails(result.error),
      },
    );
  }
  return result.data;
}

export function parseBattleActionRequest(value: unknown): BattleActionRequest {
  if (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    typeof (value as Record<string, unknown>).stateToken === "string" &&
    Buffer.byteLength((value as Record<string, unknown>).stateToken as string, "utf8") >
      MAX_STATE_TOKEN_BYTES
  ) {
    throw new ServiceError(413, "state_token_too_large", "State token exceeds 128 KiB");
  }

  const result = battleActionRequestSchema.safeParse(value);
  if (!result.success) {
    const isActionError = result.error.issues.some((issue) => issue.path[0] === "action");
    throw new ServiceError(
      isActionError ? 422 : 400,
      isActionError ? "invalid_action" : "invalid_request",
      isActionError ? "Invalid battle action" : "Invalid action request",
      { details: issueDetails(result.error) },
    );
  }
  return result.data;
}
