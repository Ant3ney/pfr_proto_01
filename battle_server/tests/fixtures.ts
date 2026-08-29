import type {
  BattleResponse,
  StartBattleRequest,
  TeamMemberInput,
} from "../src/battle/types";

export const TEST_BATTLE_STATE_KEY = Buffer.alloc(32, 0x2a).toString("base64");
export const FIXED_BATTLE_SEED = "1,2,3,4";
export const FIXED_AI_SEED = "5,6,7,8";
export const FIXED_BATTLE_ID = "00000000-0000-4000-8000-000000000001";

export function member(
  memberId: string,
  overrides: Partial<TeamMemberInput> = {},
): TeamMemberInput {
  return {
    memberId,
    species: "Pikachu",
    level: 50,
    health: 1,
    moves: ["Tackle"],
    ...overrides,
  };
}

export function battleBody(
  playerTeam: TeamMemberInput[] = [member("player-1")],
  opponentTeam: TeamMemberInput[] = [member("opponent-1")],
): StartBattleRequest {
  return {
    player: { name: "Player", team: playerTeam },
    opponent: { name: "CPU", team: opponentTeam },
  };
}

export function tokenFrom(response: BattleResponse): string {
  if (!response.stateToken) {
    throw new Error("Expected an awaiting-player response with a state token");
  }
  return response.stateToken;
}

export function semanticResponse(response: BattleResponse): Omit<BattleResponse, "stateToken"> {
  const { stateToken: _randomizedEnvelope, ...semantic } = response;
  void _randomizedEnvelope;
  return semantic;
}
