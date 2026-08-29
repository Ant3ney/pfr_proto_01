import { applyBattleAction } from "@/src/battle/service";
import {
  errorResponse,
  jsonResponse,
  optionsResponse,
  readJsonBody,
} from "@/src/http/responses";

export const runtime = "nodejs";

const ALLOWED_METHODS = ["POST", "OPTIONS"] as const;
const ROUTE = "/api/v1/battles/actions" as const;

export async function POST(request: Request): Promise<Response> {
  try {
    const input = await readJsonBody(request);
    const result = await applyBattleAction(input);
    return jsonResponse(result, ALLOWED_METHODS);
  } catch (error) {
    return errorResponse(error, ALLOWED_METHODS, ROUTE);
  }
}

export function OPTIONS(): Response {
  return optionsResponse(ALLOWED_METHODS);
}
