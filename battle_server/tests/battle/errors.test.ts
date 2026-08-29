import { describe, expect, it } from "vitest";

import {
  normalizeServiceError,
  ServiceError,
  serviceErrorBody,
} from "../../src/battle/errors";

describe("ServiceError", () => {
  it("preserves stable public status, code, message, and details", () => {
    const error = new ServiceError(422, "invalid_team", "Invalid team", {
      details: { side: "player" },
    });

    expect(serviceErrorBody(error)).toEqual({
      status: 422,
      body: {
        error: {
          code: "invalid_team",
          message: "Invalid team",
          details: { side: "player" },
        },
      },
    });
  });

  it("sanitizes unknown and private 500-level failures", () => {
    const normalized = normalizeServiceError(new Error("database-password-leak"));
    expect(normalized).toMatchObject({ status: 500, code: "internal_error", expose: false });
    expect(serviceErrorBody(normalized)).toEqual({
      status: 500,
      body: { error: { code: "internal_error", message: "Internal server error" } },
    });

    const privateError = new ServiceError(500, "server_configuration_error", "secret detail", {
      expose: false,
    });
    expect(serviceErrorBody(privateError).body.error).toEqual({
      code: "internal_error",
      message: "Internal server error",
    });
  });
});
