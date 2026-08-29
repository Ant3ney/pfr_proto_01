export type ServiceErrorStatus = 400 | 409 | 413 | 422 | 500;

export interface ServiceErrorOptions {
  cause?: unknown;
  details?: unknown;
  expose?: boolean;
}

export interface ServiceErrorBody {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

/** An HTTP-aware error that does not depend on Next.js response primitives. */
export class ServiceError extends Error {
  readonly status: ServiceErrorStatus;
  readonly code: string;
  readonly details?: unknown;
  readonly expose: boolean;

  constructor(
    status: ServiceErrorStatus,
    code: string,
    message: string,
    options: ServiceErrorOptions = {},
  ) {
    super(message);
    this.name = "ServiceError";
    if (options.cause !== undefined) this.cause = options.cause;
    this.status = status;
    this.code = code;
    this.details = options.details;
    this.expose = status < 500 && (options.expose ?? true);
  }
}

export function isServiceError(error: unknown): error is ServiceError {
  return error instanceof ServiceError;
}

export function normalizeServiceError(error: unknown): ServiceError {
  if (isServiceError(error)) return error;

  return new ServiceError(500, "internal_error", "Internal server error", {
    cause: error,
    expose: false,
  });
}

export function serviceErrorBody(error: unknown): {
  status: ServiceErrorStatus;
  body: ServiceErrorBody;
} {
  const normalized = normalizeServiceError(error);
  const message = normalized.expose ? normalized.message : "Internal server error";
  const details = normalized.expose ? normalized.details : undefined;

  return {
    status: normalized.status,
    body: {
      error: {
        code: normalized.expose ? normalized.code : "internal_error",
        message,
        ...(details === undefined ? {} : { details }),
      },
    },
  };
}
