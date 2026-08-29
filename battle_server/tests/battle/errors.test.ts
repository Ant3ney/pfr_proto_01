import { describe, expect, it, vi } from "vitest";

import {
  normalizeServiceError,
  ServiceError,
  serviceErrorBody,
} from "../../src/battle/errors";
import { errorResponse } from "../../src/http/responses";

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

    const incorrectlyExposed = new ServiceError(
      500,
      "server_configuration_error",
      "must remain private",
      { details: { secret: true }, expose: true },
    );
    expect(incorrectlyExposed.expose).toBe(false);
    expect(serviceErrorBody(incorrectlyExposed).body.error).toEqual({
      code: "internal_error",
      message: "Internal server error",
    });
  });

  it("omits an unknown error message from the safe diagnostic", async () => {
    const privateValue = "opaque-token-and-team-data";
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);

    try {
      const response = errorResponse(
        new Error(privateValue),
        ["POST", "OPTIONS"],
        "/api/v1/battles/actions",
      );

      expect(response.status).toBe(500);
      await expect(response.json()).resolves.toEqual({
        error: { code: "internal_error", message: "Internal server error." },
      });
      expect(log).toHaveBeenCalledOnce();
      expect(log.mock.calls[0][0]).toEqual({
        route: "/api/v1/battles/actions",
        status: 500,
        code: "internal_error",
        stack: expect.any(String),
      });
      expect(JSON.stringify(log.mock.calls)).not.toContain(privateValue);
    } finally {
      log.mockRestore();
    }
  });
});
