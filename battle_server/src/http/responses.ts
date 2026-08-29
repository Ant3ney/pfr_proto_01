import { MAX_REQUEST_BODY_BYTES } from "@/src/battle/constants";
import { ServiceError, serviceErrorBody } from "@/src/battle/errors";

type ApiMethod = "GET" | "POST" | "OPTIONS";

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
    return jsonResponse(normalized.body, allowedMethods, normalized.status);
  }

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
