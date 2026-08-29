import { MAX_REQUEST_BODY_BYTES } from "@/src/battle/constants";
import {
  normalizeServiceError,
  ServiceError,
  serviceErrorBody,
} from "@/src/battle/errors";

type ApiMethod = "GET" | "POST" | "OPTIONS";
type ApiRoute = "/api/v1/battles" | "/api/v1/battles/actions";

class RequestBodyError extends Error {
  constructor(
    readonly status: 400 | 413,
    readonly code: "invalid_json" | "request_too_large",
    message: string,
  ) {
    super(message);
    this.name = "RequestBodyError";
  }
}

function apiHeaders(allowedMethods: readonly ApiMethod[]): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": allowedMethods.join(", "),
    "Access-Control-Allow-Origin": "*",
    "Cache-Control": "no-store",
  });

  return headers;
}

function tooLargeError(): RequestBodyError {
  return new RequestBodyError(
    413,
    "request_too_large",
    "Request body exceeds 128 KiB.",
  );
}

function safeStackFrames(error: unknown): string {
  if (!(error instanceof Error) || error.stack === undefined) {
    return "Stack unavailable";
  }

  const frames = error.stack
    .split("\n")
    .filter((line) => /^\s+at\s/u.test(line))
    .join("\n");

  return frames || "Stack unavailable";
}

function logInternalError(error: unknown, route: ApiRoute): void {
  const normalized = normalizeServiceError(error);
  console.error({
    route,
    status: normalized.status,
    code: normalized.code,
    stack: safeStackFrames(error),
  });
}

export async function readJsonBody(request: Request): Promise<unknown> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    const declaredBytes = Number(contentLength);
    if (Number.isFinite(declaredBytes) && declaredBytes > MAX_REQUEST_BODY_BYTES) {
      throw tooLargeError();
    }
  }

  if (request.body === null) {
    throw new RequestBodyError(
      400,
      "invalid_json",
      "Request body must contain valid JSON.",
    );
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      totalBytes += value.byteLength;
      if (totalBytes > MAX_REQUEST_BODY_BYTES) {
        await reader.cancel().catch(() => undefined);
        throw tooLargeError();
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof RequestBodyError) {
      throw error;
    }
    throw new RequestBodyError(
      400,
      "invalid_json",
      "Request body must contain valid JSON.",
    );
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(body);
    return JSON.parse(text) as unknown;
  } catch {
    throw new RequestBodyError(
      400,
      "invalid_json",
      "Request body must contain valid JSON.",
    );
  }
}

export function jsonResponse(
  value: unknown,
  allowedMethods: readonly ApiMethod[],
  status = 200,
): Response {
  const headers = apiHeaders(allowedMethods);
  headers.set("Content-Type", "application/json; charset=utf-8");

  return Response.json(value, { headers, status });
}

export function optionsResponse(
  allowedMethods: readonly ApiMethod[],
): Response {
  const headers = apiHeaders(allowedMethods);
  headers.set("Allow", allowedMethods.join(", "));

  return new Response(null, { headers, status: 204 });
}

export function errorResponse(
  error: unknown,
  allowedMethods: readonly ApiMethod[],
  route: ApiRoute,
): Response {
  if (error instanceof RequestBodyError) {
    return jsonResponse(
      {
        error: {
          code: error.code,
          message: error.message,
        },
      },
      allowedMethods,
      error.status,
    );
  }

  if (error instanceof ServiceError) {
    const normalized = serviceErrorBody(error);
    if (normalized.status === 500) {
      logInternalError(error, route);
    }
    return jsonResponse(normalized.body, allowedMethods, normalized.status);
  }

  logInternalError(error, route);

  return jsonResponse(
    {
      error: {
        code: "internal_error",
        message: "Internal server error.",
      },
    },
    allowedMethods,
    500,
  );
}
