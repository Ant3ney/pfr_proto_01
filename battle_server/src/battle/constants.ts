export const API_VERSION = "v1" as const;
export const SERVICE_NAME = "pfr-battle-server" as const;
export const ENGINE_VERSION = "0.11.11" as const;
export const FORMAT_VERSION = "pfr-gen9-singles-v1" as const;

export const TOKEN_SCHEMA_VERSION = 1 as const;
export const TOKEN_ENVELOPE_VERSION = 1 as const;
export const TOKEN_PREFIX = `pfr${TOKEN_ENVELOPE_VERSION}` as const;
export const BATTLE_STATE_KEY_ENV = "BATTLE_STATE_KEY" as const;

export const MAX_REQUEST_BODY_BYTES = 128 * 1024;
export const MAX_STATE_TOKEN_BYTES = 128 * 1024;
export const MAX_TOKEN_PAYLOAD_BYTES = 128 * 1024;

export const MAX_BATTLE_TURNS = 500;
export const MAX_REPLAY_RECORDS = MAX_BATTLE_TURNS * 8 + 3;
export const MAX_REPLAY_RECORD_BYTES = 32 * 1024;

export const MIN_TEAM_SIZE = 1;
export const MAX_TEAM_SIZE = 6;
export const MIN_MOVE_COUNT = 1;
export const MAX_MOVE_COUNT = 4;
export const MIN_LEVEL = 1;
export const MAX_LEVEL = 100;
export const MIN_IV = 0;
export const MAX_IV = 31;
export const MIN_EV = 0;
export const MAX_EV = 252;

// Showdown itself truncates caller-controlled protocol names at 18 characters.
// Canonical species-form names used as default display names may be longer.
export const MAX_SHOWDOWN_NAME_LENGTH = 18;
export const MAX_MEMBER_ID_LENGTH = 128;
export const MAX_IDENTIFIER_LENGTH = 128;

export const STAT_NAMES = ["hp", "atk", "def", "spa", "spd", "spe"] as const;
