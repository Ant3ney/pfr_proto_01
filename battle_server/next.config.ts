import type { NextConfig } from "next";

const showdownRuntimeFiles = [
  "./node_modules/pokemon-showdown/package.json",
  "./node_modules/pokemon-showdown/dist/sim/*.js",
  "./node_modules/pokemon-showdown/dist/lib/**/*.js",
  "./node_modules/pokemon-showdown/dist/config/formats.js",
  "./node_modules/pokemon-showdown/dist/data/**/*.js",
  "./node_modules/pokemon-showdown/dist/data/**/*.json",
];

const excludedShowdownFiles = [
  "./node_modules/pokemon-showdown/dist/**/*.map",
  "./node_modules/pokemon-showdown/dist/server/**/*",
  "./node_modules/pokemon-showdown/dist/tools/**/*",
  "./node_modules/pokemon-showdown/dist/translations/**/*",
  "./node_modules/pokemon-showdown/dist/sim/examples/**/*",
  "./node_modules/pokemon-showdown/dist/sim/tools/**/*",
];

const apiHeaders = [
  { key: "Access-Control-Allow-Headers", value: "Content-Type" },
  { key: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS" },
  { key: "Access-Control-Allow-Origin", value: "*" },
  { key: "Cache-Control", value: "no-store" },
];

const nextConfig: NextConfig = {
  serverExternalPackages: ["pokemon-showdown"],
  outputFileTracingIncludes: {
    "/api/v1/battles": showdownRuntimeFiles,
    "/api/v1/battles/actions": showdownRuntimeFiles,
  },
  outputFileTracingExcludes: {
    "/api/v1/battles": excludedShowdownFiles,
    "/api/v1/battles/actions": excludedShowdownFiles,
  },
  async headers() {
    return [
      {
        source: "/api/v1/:path*",
        headers: apiHeaders,
      },
      {
        source: "/api/v1/health",
        headers: [{ key: "Access-Control-Allow-Methods", value: "GET, OPTIONS" }],
      },
      {
        source: "/api/v1/battles",
        headers: [{ key: "Access-Control-Allow-Methods", value: "POST, OPTIONS" }],
      },
      {
        source: "/api/v1/battles/actions",
        headers: [{ key: "Access-Control-Allow-Methods", value: "POST, OPTIONS" }],
      },
    ];
  },
};

export default nextConfig;
