import { createHmac } from "node:crypto";
import { MongoClient, ServerApiVersion } from "mongodb";
import {
  CLOUD_SAVE_PROTOCOL_VERSION,
  resolveCloudSave,
  validateCloudSaveRequest,
} from "../cloud-save/cloud-save-resolver.mjs";

const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
const MAX_CAS_ATTEMPTS = 5;
let clientPromise;

function jsonResponse(status, value) {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function configuration() {
  const uri = process.env.MONGODB_URI ?? "";
  const pepper = process.env.CLOUD_SAVE_PEPPER ?? "";
  if (!uri || pepper.length < 32) return null;
  return {
    uri,
    pepper,
    database: process.env.MONGODB_DATABASE || "pfr_locomotion",
  };
}

async function savesCollection(config) {
  if (!clientPromise) {
    const client = new MongoClient(config.uri, {
      maxPoolSize: 5,
      serverSelectionTimeoutMS: 7000,
      serverApi: {
        version: ServerApiVersion.v1,
        strict: true,
        deprecationErrors: true,
      },
    });
    clientPromise = client.connect().catch((error) => {
      clientPromise = undefined;
      throw error;
    });
  }
  const client = await clientPromise;
  return client.db(config.database).collection("cloud_saves");
}

function lookupKey(saveId, pepper) {
  return createHmac("sha256", pepper).update(saveId, "utf8").digest("hex");
}

function responseFromResolution(resolution, nowMs) {
  return {
    ok: true,
    protocol_version: CLOUD_SAVE_PROTOCOL_VERSION,
    outcome: resolution.outcome,
    revision: resolution.revision,
    epoch: resolution.epoch,
    synced_at_ms: nowMs,
    payload: resolution.payload,
  };
}

export default async function cloudSave(request) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "method_not_allowed" });
  }

  const config = configuration();
  if (!config) {
    return jsonResponse(503, {
      ok: false,
      error: "cloud_save_not_configured",
    });
  }

  const contentType = (
    request.headers.get("content-type")?.split(";", 1)[0] ?? ""
  ).trim().toLowerCase();
  if (contentType !== "application/json") {
    return jsonResponse(415, {
      ok: false,
      error: "json_content_type_required",
    });
  }

  const source = await request.text();
  if (new TextEncoder().encode(source).byteLength > MAX_REQUEST_BYTES) {
    return jsonResponse(413, { ok: false, error: "save_too_large" });
  }
  let body;
  try {
    body = JSON.parse(source);
  } catch {
    return jsonResponse(400, { ok: false, error: "invalid_json" });
  }
  const validationError = validateCloudSaveRequest(body);
  if (validationError) {
    return jsonResponse(400, {
      ok: false,
      error: "invalid_save_request",
      message: validationError,
    });
  }

  const saveKey = lookupKey(body.save_id.trim(), config.pepper);
  try {
    const collection = await savesCollection(config);
    for (let attempt = 0; attempt < MAX_CAS_ATTEMPTS; attempt += 1) {
      const nowMs = Date.now();
      const existing = await collection.findOne({ _id: saveKey });
      const resolution = resolveCloudSave(existing, body, nowMs);
      if (!resolution.shouldWrite) {
        return jsonResponse(200, responseFromResolution(resolution, nowMs));
      }
      const document = {
        _id: saveKey,
        protocolVersion: CLOUD_SAVE_PROTOCOL_VERSION,
        revision: resolution.revision,
        epoch: resolution.epoch,
        payload: resolution.payload,
        sectionRevisions: resolution.sectionRevisions,
        sectionUpdatedAtMs: resolution.sectionUpdatedAtMs,
        lastDeviceId: body.device_id,
        updatedAt: new Date(nowMs),
      };
      if (!existing) {
        document.createdAt = new Date(nowMs);
        try {
          await collection.insertOne(document);
          return jsonResponse(200, responseFromResolution(resolution, nowMs));
        } catch (error) {
          if (error?.code === 11000) continue;
          throw error;
        }
      }
      const updateResult = await collection.replaceOne(
        { _id: saveKey, revision: existing.revision },
        { ...document, createdAt: existing.createdAt ?? new Date(nowMs) },
      );
      if (updateResult.modifiedCount === 1) {
        return jsonResponse(200, responseFromResolution(resolution, nowMs));
      }
    }
    return jsonResponse(409, { ok: false, error: "concurrent_sync_retry" });
  } catch {
    return jsonResponse(503, { ok: false, error: "cloud_save_unavailable" });
  }
}

export const config = {
  path: "/api/cloud-save",
  rateLimit: {
    windowLimit: 60,
    windowSize: 60,
    aggregateBy: ["ip", "domain"],
  },
};
