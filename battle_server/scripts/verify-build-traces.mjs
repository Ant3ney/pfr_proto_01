import { statSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const MEBIBYTE = 1024 * 1024;
const MAX_FUNCTION_BYTES = 250 * MEBIBYTE;
const TRACE_PATHS = [
  ".next/server/app/api/v1/battles/route.js.nft.json",
  ".next/server/app/api/v1/battles/actions/route.js.nft.json",
];
const REQUIRED_SHOWDOWN_PATHS = [
  /\/node_modules\/pokemon-showdown\/package\.json$/u,
  /\/node_modules\/pokemon-showdown\/dist\/sim\/[^/]+\.js$/u,
  /\/node_modules\/pokemon-showdown\/dist\/lib\/.*\.js$/u,
  /\/node_modules\/pokemon-showdown\/dist\/config\/formats\.js$/u,
  /\/node_modules\/pokemon-showdown\/dist\/data\/.*\.js$/u,
];
const FORBIDDEN_SHOWDOWN_PATHS = [
  /\/node_modules\/pokemon-showdown\/dist\/(?:server|tools|translations)\//u,
  /\/node_modules\/pokemon-showdown\/dist\/sim\/(?:examples|tools)\//u,
];

function readTrace(tracePath) {
  let trace;
  try {
    trace = JSON.parse(readFileSync(tracePath, "utf8"));
  } catch (error) {
    throw new Error(`Build trace is missing or invalid: ${tracePath}`, { cause: error });
  }

  if (!Array.isArray(trace.files) || trace.files.some((file) => typeof file !== "string")) {
    throw new Error(`Build trace has an invalid files array: ${tracePath}`);
  }
  return trace.files;
}

function verifyTrace(tracePath) {
  const traceDirectory = dirname(resolve(tracePath));
  const files = [
    ...new Set(readTrace(tracePath).map((file) => resolve(traceDirectory, file))),
  ];
  let totalBytes = 0;
  let sourceMapBytes = 0;
  let sourceMapCount = 0;

  for (const file of files) {
    let size;
    try {
      size = statSync(file).size;
    } catch (error) {
      throw new Error(`Traced runtime file is missing: ${file}`, { cause: error });
    }
    totalBytes += size;
    if (file.endsWith(".map")) {
      sourceMapBytes += size;
      sourceMapCount += 1;
    }
  }

  for (const required of REQUIRED_SHOWDOWN_PATHS) {
    if (!files.some((file) => required.test(file))) {
      throw new Error(`Required Pokemon Showdown runtime path is absent: ${required}`);
    }
  }

  const forbidden = files.filter((file) =>
    FORBIDDEN_SHOWDOWN_PATHS.some((pattern) => pattern.test(file)),
  );
  if (forbidden.length > 0) {
    throw new Error(`Forbidden Pokemon Showdown paths were traced: ${forbidden.join(", ")}`);
  }

  if (totalBytes >= MAX_FUNCTION_BYTES) {
    throw new Error(
      `Uncompressed trace is ${(totalBytes / MEBIBYTE).toFixed(2)} MiB; ` +
        `the limit is ${MAX_FUNCTION_BYTES / MEBIBYTE} MiB`,
    );
  }

  console.log(
    `${tracePath}: ${files.length} unique files, ` +
      `${(totalBytes / MEBIBYTE).toFixed(2)} MiB uncompressed, ` +
      `${sourceMapCount} source maps (${(sourceMapBytes / MEBIBYTE).toFixed(2)} MiB)`,
  );
}

for (const tracePath of TRACE_PATHS) {
  verifyTrace(tracePath);
}
