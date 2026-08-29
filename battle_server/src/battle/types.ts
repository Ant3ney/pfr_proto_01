import {
  API_VERSION,
  ENGINE_VERSION,
  FORMAT_VERSION,
  TOKEN_SCHEMA_VERSION,
} from "./constants";

export type ApiVersion = typeof API_VERSION;
export type EngineVersion = typeof ENGINE_VERSION;
export type FormatVersion = typeof FORMAT_VERSION;
export type TokenSchemaVersion = typeof TOKEN_SCHEMA_VERSION;

export type BattleSide = "player" | "opponent";
export type ShowdownSide = "p1" | "p2";
export type Gender = "M" | "F" | "N";
export type StatName = "hp" | "atk" | "def" | "spa" | "spd" | "spe";

export type StatTable = Record<StatName, number>;
export type PartialStatTable = Partial<StatTable>;

export interface TeamMemberInput {
  memberId: string;
  species: string;
  level: number;
  health: number;
  moves: string[];
  nickname?: string;
  ability?: string;
  item?: string;
  nature?: string;
  gender?: Gender;
  ivs?: PartialStatTable;
  evs?: PartialStatTable;
}

export interface BattleSideInput {
  name: string;
  team: TeamMemberInput[];
}

export interface StartBattleRequest {
  player: BattleSideInput;
  opponent: BattleSideInput;
}

export interface MoveAction {
  type: "move";
  moveIndex: number;
}

export interface SwitchAction {
  type: "switch";
  memberId: string;
}

export interface ForfeitAction {
  type: "forfeit";
}

export type BattleAction = MoveAction | SwitchAction | ForfeitAction;

export interface BattleActionRequest {
  stateToken: string;
  action: BattleAction;
}

/** A fully defaulted, identifier-canonicalized Showdown set plus caller state. */
export interface CanonicalTeamMember {
  memberId: string;
  species: string;
  level: number;
  health: number;
  moves: string[];
  nickname: string;
  ability: string;
  item: string;
  nature: string;
  gender: Gender | "";
  ivs: StatTable;
  evs: StatTable;
}

export interface CanonicalBattleSide {
  name: string;
  /** Includes health=0 members, in caller order. */
  team: CanonicalTeamMember[];
}

export interface CanonicalStartBattleRequest {
  player: CanonicalBattleSide;
  opponent: CanonicalBattleSide;
}

/** Structural subset of Showdown's PokemonSet used by the battle constructor. */
export interface CanonicalPokemonSet {
  name: string;
  species: string;
  item: string;
  ability: string;
  moves: string[];
  nature: string;
  gender: Gender | "";
  evs: StatTable;
  ivs: StatTable;
  level: number;
}

export interface PreparedBattleSide {
  name: string;
  /** Canonical roster, including members that began fainted. */
  roster: CanonicalTeamMember[];
  /** Showdown receives only these positive-health sets. */
  team: CanonicalPokemonSet[];
  /** Parallel to team and normalizedHealth. */
  memberIds: string[];
  /** Parallel to team and resolved only after Showdown calculates max HP. */
  normalizedHealth: number[];
}

export interface PreparedBattleTeams {
  player: PreparedBattleSide;
  opponent: PreparedBattleSide;
}

export interface PerSide<T> {
  player: T;
  opponent: T;
}

/**
 * Authenticated, client-carried state at a stable decision boundary.
 *
 * `memberIds[side][i]` and `startingHp[side][i]` refer to the same living
 * Showdown team slot. Zero-health roster members remain in player/opponent.team
 * and intentionally do not appear in those parallel arrays.
 */
export interface BattleTokenState {
  schemaVersion: TokenSchemaVersion;
  apiVersion: ApiVersion;
  engineVersion: EngineVersion;
  formatVersion: FormatVersion;
  battleId: string;
  revision: number;
  inputLog: string[];
  player: CanonicalBattleSide;
  opponent: CanonicalBattleSide;
  memberIds: PerSide<string[]>;
  startingHp: PerSide<number[]>;
  aiPrngState: string;
}

export type BattlePhase = "awaiting_player" | "ended";

export interface PlayerMoveOption {
  moveIndex: number;
  name: string;
  id: string;
  pp: number;
  maxPp: number;
  disabled: boolean;
}

export interface PlayerSwitchOption {
  memberId: string;
}

export type PlayerChoiceRequest =
  | {
      type: "move";
      activeMemberId: string;
      moves: PlayerMoveOption[];
      switchOptions: PlayerSwitchOption[];
    }
  | {
      type: "switch";
      activeMemberId?: string;
      switchOptions: PlayerSwitchOption[];
    };

export interface MemberMoveBattleState {
  moveIndex: number;
  name: string;
  id: string;
  pp: number;
  maxPp: number;
}

export interface MemberBattleState {
  memberId: string;
  species: string;
  nickname: string;
  level: number;
  hp: number;
  maxHp: number;
  normalizedHealth: number;
  fainted: boolean;
  active: boolean;
  status: string | null;
  moves: MemberMoveBattleState[];
}

export interface PublicMemberBattleState {
  memberId: string;
  species: string;
  nickname: string;
  level: number;
  hp: number;
  maxHp: number;
  normalizedHealth: number;
  fainted: boolean;
  active: boolean;
  status: string | null;
}

export interface BattleResult {
  winner: "player" | "opponent" | "tie";
  reason: string;
}

export interface BattleResponse {
  apiVersion: ApiVersion;
  engineVersion: EngineVersion;
  formatVersion: FormatVersion;
  battleId: string;
  revision: number;
  phase: BattlePhase;
  stateToken?: string;
  events: string[];
  request: PlayerChoiceRequest | null;
  parties: {
    player: MemberBattleState[];
    opponent: PublicMemberBattleState[];
  };
  result?: BattleResult;
}
