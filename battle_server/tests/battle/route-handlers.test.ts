import { afterAll, beforeEach, describe, expect, it } from "vitest";

import nextConfig from "../../next.config";
import {
  GET as getHealth,
  OPTIONS as optionsHealth,
} from "../../app/api/v1/health/route";
import {
  OPTIONS as optionsBattles,
  POST as postBattle,
} from "../../app/api/v1/battles/route";
import {
  OPTIONS as optionsActions,
  POST as postAction,
} from "../../app/api/v1/battles/actions/route";
import {
  API_VERSION,
  BATTLE_STATE_KEY_ENV,
  ENGINE_VERSION,
  FORMAT_VERSION,
  MAX_REQUEST_BODY_BYTES,
  SERVICE_NAME,
} from "../../src/battle/constants";
import type { BattleResponse } from "../../src/battle/types";
import {
  battleBody,
  member,
  TEST_BATTLE_STATE_KEY,
} from "../fixtures";

const ORIGINAL_KEY = process.env[BATTLE_STATE_KEY_ENV];

function requestWithJson(url: string, value: unknown): Request {
  return new Request(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(value),
  });
}

function expectCommonHeaders(response: Response, methods: string): void {
  expect(response.headers.get("access-control-allow-origin")).toBe("*");
  expect(response.headers.get("access-control-allow-methods")).toBe(methods);
  expect(response.headers.get("access-control-allow-headers")).toBe("Content-Type");
  expect(response.headers.has("access-control-allow-credentials")).toBe(false);
  expect(response.headers.get("cache-control")).toBe("no-store");
}

async function responseBody(response: Response): Promise<Record<string, unknown>> {
  return (await response.json()) as Record<string, unknown>;
}

beforeEach(() => {
  process.env[BATTLE_STATE_KEY_ENV] = TEST_BATTLE_STATE_KEY;
});

afterAll(() => {
  if (ORIGINAL_KEY === undefined) {
    delete process.env[BATTLE_STATE_KEY_ENV];
  } else {
    process.env[BATTLE_STATE_KEY_ENV] = ORIGINAL_KEY;
  }
});

describe("Route Handlers", () => {
  it("adds API-wide CORS and no-store headers to framework-generated responses", async () => {
    expect(nextConfig.headers).toBeTypeOf("function");
    const rules = await nextConfig.headers?.();

    expect(rules).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          source: "/api/v1/:path*",
          headers: expect.arrayContaining([
            { key: "Access-Control-Allow-Headers", value: "Content-Type" },
            { key: "Access-Control-Allow-Origin", value: "*" },
            { key: "Cache-Control", value: "no-store" },
          ]),
        }),
      ]),
    );
  });

  it("serves versioned health with wildcard CORS and no-store", async () => {
    const response = getHealth();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expectCommonHeaders(response, "GET, OPTIONS");
    await expect(response.json()).resolves.toEqual({
      service: SERVICE_NAME,
      apiVersion: API_VERSION,
      engineVersion: ENGINE_VERSION,
      formatVersion: FORMAT_VERSION,
    });
  });

  it.each([
    ["health", optionsHealth, "GET, OPTIONS"],
    ["battle start", optionsBattles, "POST, OPTIONS"],
    ["battle actions", optionsActions, "POST, OPTIONS"],
  ] as const)("handles %s preflight without credentials", async (_name, handler, methods) => {
    const response = handler();

    expect(response.status).toBe(204);
    expect(response.headers.get("allow")).toBe(methods);
    expectCommonHeaders(response, methods);
    expect(await response.text()).toBe("");
  });

  it("starts a battle and accepts a typed action through native Request/Response APIs", async () => {
    const startResponse = await postBattle(
      requestWithJson(
        "http://localhost/api/v1/battles",
        battleBody(
          [member("player", { moves: ["Splash"] })],
          [member("opponent", { moves: ["Splash"] })],
        ),
      ),
    );
    expect(startResponse.status).toBe(200);
    expectCommonHeaders(startResponse, "POST, OPTIONS");
    const started = (await startResponse.json()) as BattleResponse;
    expect(started).toMatchObject({
      apiVersion: API_VERSION,
      revision: 0,
      phase: "awaiting_player",
      request: { type: "move", activeMemberId: "player" },
    });

    const actionResponse = await postAction(
      requestWithJson("http://localhost/api/v1/battles/actions", {
        stateToken: started.stateToken,
        action: { type: "forfeit" },
      }),
    );
    expect(actionResponse.status).toBe(200);
    expectCommonHeaders(actionResponse, "POST, OPTIONS");
    await expect(actionResponse.json()).resolves.toMatchObject({
      battleId: started.battleId,
      revision: 1,
      phase: "ended",
      request: null,
      result: { winner: "opponent", reason: "forfeit" },
    });
  });

  it.each([
    ["truncated JSON", '{"player":', "invalid_json"],
    ["empty JSON", "", "invalid_json"],
  ])("maps %s to a stable 400", async (_name, body, code) => {
    const response = await postBattle(
      new Request("http://localhost/api/v1/battles", { method: "POST", body }),
    );

    expect(response.status).toBe(400);
    expectCommonHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toMatchObject({ error: { code } });
  });

  it("distinguishes malformed envelopes from invalid teams and actions", async () => {
    const malformed = await postBattle(
      requestWithJson("http://localhost/api/v1/battles", { player: battleBody().player }),
    );
    expect(malformed.status).toBe(400);
    await expect(responseBody(malformed)).resolves.toMatchObject({
      error: { code: "invalid_request" },
    });

    const unknownSpecies = battleBody();
    unknownSpecies.player.team[0].species = "Definitely-Not-A-Pokemon";
    const invalidTeam = await postBattle(
      requestWithJson("http://localhost/api/v1/battles", unknownSpecies),
    );
    expect(invalidTeam.status).toBe(422);
    await expect(responseBody(invalidTeam)).resolves.toMatchObject({
      error: { code: "invalid_team" },
    });

    const invalidAction = await postAction(
      requestWithJson("http://localhost/api/v1/battles/actions", {
        stateToken: "opaque",
        action: { type: "move", moveIndex: 0 },
      }),
    );
    expect(invalidAction.status).toBe(422);
    expectCommonHeaders(invalidAction, "POST, OPTIONS");
    await expect(responseBody(invalidAction)).resolves.toMatchObject({
      error: { code: "invalid_action" },
    });
  });

  it("maps a corrupt state token to 400 at the action route", async () => {
    const response = await postAction(
      requestWithJson("http://localhost/api/v1/battles/actions", {
        stateToken: "not-a-token",
        action: { type: "forfeit" },
      }),
    );

    expect(response.status).toBe(400);
    expectCommonHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toEqual({
      error: { code: "invalid_state_token", message: "Invalid state token" },
    });
  });

  it("rejects an oversized declared body before reading it", async () => {
    const response = await postBattle(
      new Request("http://localhost/api/v1/battles", {
        method: "POST",
        headers: { "content-length": String(MAX_REQUEST_BODY_BYTES + 1) },
        body: "{}",
      }),
    );

    expect(response.status).toBe(413);
    expectCommonHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toEqual({
      error: {
        code: "request_too_large",
        message: "Request body exceeds 128 KiB.",
      },
    });
  });

  it("rejects an oversized streaming body without relying on Content-Length", async () => {
    const chunk = new Uint8Array(70 * 1024).fill(0x20);
    let emitted = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (emitted < 2) {
          controller.enqueue(chunk);
          emitted += 1;
        } else {
          controller.close();
        }
      },
    });
    const init = {
      method: "POST",
      body,
      duplex: "half",
    } as RequestInit & { duplex: "half" };

    const response = await postBattle(
      new Request("http://localhost/api/v1/battles", init),
    );

    expect(response.status).toBe(413);
    expectCommonHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "request_too_large" },
    });
  });

  it("sanitizes internal service errors", async () => {
    delete process.env[BATTLE_STATE_KEY_ENV];
    const response = await postBattle(
      requestWithJson("http://localhost/api/v1/battles", battleBody()),
    );

    expect(response.status).toBe(500);
    expectCommonHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toEqual({
      error: { code: "internal_error", message: "Internal server error" },
    });
  });
});
