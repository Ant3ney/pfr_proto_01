import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const PROJECT_DIR = fileURLToPath(new URL("../..", import.meta.url));
const NEXT_BIN = fileURLToPath(
  new URL("../../node_modules/next/dist/bin/next", import.meta.url),
);

let server: ChildProcessWithoutNullStreams;
let baseUrl: string;
let serverOutput = "";

function captureOutput(chunk: Buffer): void {
  serverOutput = `${serverOutput}${chunk.toString("utf8")}`.slice(-40_000);
}

async function availablePort(): Promise<number> {
  const probe = createServer();
  probe.listen(0, "127.0.0.1");
  await once(probe, "listening");
  const address = probe.address();
  if (address === null || typeof address === "string") {
    probe.close();
    throw new Error("Could not allocate a local HTTP test port");
  }

  const { port } = address;
  probe.close();
  await once(probe, "close");
  return port;
}

async function waitUntilReady(): Promise<void> {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) {
      throw new Error(`Next test server exited early.\n${serverOutput}`);
    }

    try {
      const response = await fetch(`${baseUrl}/api/v1/health`);
      if (response.status === 200) return;
    } catch {
      // The socket is expected to refuse connections until Next is ready.
    }

    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  throw new Error(`Next test server did not become ready.\n${serverOutput}`);
}

function expectApiHeaders(response: Response, methods: string): void {
  expect(response.headers.get("access-control-allow-origin")).toBe("*");
  expect(response.headers.get("access-control-allow-methods")).toBe(methods);
  expect(response.headers.get("access-control-allow-headers")).toBe("Content-Type");
  expect(response.headers.has("access-control-allow-credentials")).toBe(false);
  expect(response.headers.get("cache-control")).toBe("no-store");
}

beforeAll(async () => {
  const port = await availablePort();
  baseUrl = `http://127.0.0.1:${port}`;
  server = spawn(
    process.execPath,
    [NEXT_BIN, "dev", "--hostname", "127.0.0.1", "--port", String(port)],
    {
      cwd: PROJECT_DIR,
      env: {
        ...process.env,
        NEXT_TELEMETRY_DISABLED: "1",
        NODE_ENV: "development",
      },
      stdio: "pipe",
    },
  );
  server.stdin.end();
  server.stdout.on("data", captureOutput);
  server.stderr.on("data", captureOutput);
  await waitUntilReady();
}, 30_000);

afterAll(async () => {
  if (server === undefined || server.exitCode !== null) return;

  const exited = once(server, "exit");
  server.kill("SIGTERM");
  let timeoutHandle: NodeJS.Timeout;
  const timeout = new Promise<"timeout">((resolve) => {
    timeoutHandle = setTimeout(() => resolve("timeout"), 5_000);
  });
  if ((await Promise.race([exited, timeout])) === "timeout") {
    server.kill("SIGKILL");
    await exited;
  }
  clearTimeout(timeoutHandle!);
}, 10_000);

describe("actual Next HTTP server", () => {
  it("applies CORS and no-store headers to a successful response", async () => {
    const response = await fetch(`${baseUrl}/api/v1/health`);

    expect(response.status).toBe(200);
    expectApiHeaders(response, "GET, OPTIONS");
  });

  it("applies CORS and no-store headers to an application error", async () => {
    const response = await fetch(`${baseUrl}/api/v1/battles`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{",
    });

    expect(response.status).toBe(400);
    expectApiHeaders(response, "POST, OPTIONS");
    await expect(response.json()).resolves.toEqual({
      error: {
        code: "invalid_json",
        message: "Request body must contain valid JSON.",
      },
    });
  });

  it("applies CORS and no-store headers to an OPTIONS response", async () => {
    const response = await fetch(`${baseUrl}/api/v1/battles`, {
      method: "OPTIONS",
      headers: {
        Origin: "https://example.invalid",
        "Access-Control-Request-Headers": "Content-Type",
        "Access-Control-Request-Method": "POST",
      },
    });

    expect(response.status).toBe(204);
    expect(response.headers.get("allow")).toBe("POST, OPTIONS");
    expectApiHeaders(response, "POST, OPTIONS");
  });

  it("applies API-wide CORS and no-store headers to a framework 405", async () => {
    const response = await fetch(`${baseUrl}/api/v1/battles`, { method: "PUT" });

    expect(response.status).toBe(405);
    expectApiHeaders(response, "POST, OPTIONS");
  });
});
