import {
  API_VERSION,
  ENGINE_VERSION,
  FORMAT_VERSION,
  SERVICE_NAME,
} from "@/src/battle/constants";
import { jsonResponse, optionsResponse } from "@/src/http/responses";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ALLOWED_METHODS = ["GET", "OPTIONS"] as const;

export function GET(): Response {
  return jsonResponse(
    {
      service: SERVICE_NAME,
      apiVersion: API_VERSION,
      engineVersion: ENGINE_VERSION,
      formatVersion: FORMAT_VERSION,
    },
    ALLOWED_METHODS,
  );
}

export function OPTIONS(): Response {
  return optionsResponse(ALLOWED_METHODS);
}
