import { isDeepStrictEqual } from "node:util";

export const CLOUD_SAVE_PROTOCOL_VERSION = 1;
export const CLOUD_SAVE_SECTIONS = Object.freeze([
  "profile",
  "collection",
  "move_learning",
  "economy",
  "inventory",
  "challenge_progression",
  "world",
]);

const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;
const MAX_COLLECTION_SIZE = 5000;

function copy(value) {
  return structuredClone(value);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function normalizedTimestamp(value, nowMs) {
  if (!isNonNegativeInteger(value)) return 0;
  return Math.min(value, nowMs + MAX_CLOCK_SKEW_MS);
}

function sectionTimestamp(payload, section, nowMs) {
  return normalizedTimestamp(
    payload?.save_meta?.section_updated_at_ms?.[section],
    nowMs,
  );
}

function orderedUnique(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const key = `${typeof value}:${String(value)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(copy(value));
  }
  return result;
}

function mergeCompletedRoutes(first, second) {
  const completed = new Set(
    [...first, ...second].filter(
      (value) => Number.isInteger(value) && value >= 0 && value < 40,
    ),
  );
  const result = [];
  for (let route = 0; route < 40 && completed.has(route); route += 1) {
    result.push(route);
  }
  return result;
}

function pcStorageCopy(pcl) {
  const result = copy(pcl);
  result.party = { inParty: false, slot: null };
  return result;
}

function mergePokemonRecord(preferred, other) {
  const result = copy(preferred);
  if (!isPlainObject(result.instanceStats)) result.instanceStats = {};
  const otherStats = isPlainObject(other.instanceStats) ? other.instanceStats : {};
  const preferredXp = Number(result.instanceStats.currentXp);
  const otherXp = Number(otherStats.currentXp);
  if (
    Number.isFinite(otherXp)
    && (!Number.isFinite(preferredXp) || otherXp > preferredXp)
  ) {
    result.instanceStats.currentXp = otherXp;
    result.instanceStats.level = otherStats.level;
  } else if (
    otherXp === preferredXp
    && Number(otherStats.level) > Number(result.instanceStats.level)
  ) {
    result.instanceStats.level = otherStats.level;
  }
  return result;
}

function mergeCollection(cloudValue, incomingValue, preferIncoming) {
  const preferred = preferIncoming ? incomingValue : cloudValue;
  const other = preferIncoming ? cloudValue : incomingValue;
  const result = copy(preferred);
  const indices = new Map();
  for (let index = 0; index < result.length; index += 1) {
    const pclId = String(result[index]?.pclID ?? "");
    if (pclId) indices.set(pclId, index);
  }
  for (const pcl of other) {
    const pclId = String(pcl?.pclID ?? "");
    if (!pclId) continue;
    const existingIndex = indices.get(pclId);
    if (existingIndex === undefined) {
      indices.set(pclId, result.length);
      result.push(pcStorageCopy(pcl));
      continue;
    }
    result[existingIndex] = mergePokemonRecord(result[existingIndex], pcl);
  }
  return result.slice(0, MAX_COLLECTION_SIZE);
}

function sameActiveRun(first, second) {
  return (
    Number(first?.run_id ?? -1) === Number(second?.run_id ?? -2)
    && String(first?.active_area_id ?? "")
      === String(second?.active_area_id ?? "__different__")
  );
}

function mergeInventory(cloudValue, incomingValue, preferIncoming) {
  const preferred = preferIncoming ? incomingValue : cloudValue;
  const other = preferIncoming ? cloudValue : incomingValue;
  const result = copy(preferred);
  result.claimed_gifts = orderedUnique([
    ...(Array.isArray(preferred.claimed_gifts) ? preferred.claimed_gifts : []),
    ...(Array.isArray(other.claimed_gifts) ? other.claimed_gifts : []),
  ]);
  return result;
}

function mergeChallengeProgression(cloudValue, incomingValue, preferIncoming) {
  const preferred = preferIncoming ? incomingValue : cloudValue;
  const other = preferIncoming ? cloudValue : incomingValue;
  const result = copy(preferred);
  result.earned_badges = orderedUnique([
    ...(Array.isArray(preferred.earned_badges) ? preferred.earned_badges : []),
    ...(Array.isArray(other.earned_badges) ? other.earned_badges : []),
  ]);
  result.completed_routes = mergeCompletedRoutes(
    Array.isArray(preferred.completed_routes) ? preferred.completed_routes : [],
    Array.isArray(other.completed_routes) ? other.completed_routes : [],
  );
  result.champion_completed = Boolean(
    preferred.champion_completed || other.champion_completed,
  );
  if (sameActiveRun(preferred, other)) {
    result.run_defeated_ids = orderedUnique([
      ...(Array.isArray(preferred.run_defeated_ids) ? preferred.run_defeated_ids : []),
      ...(Array.isArray(other.run_defeated_ids) ? other.run_defeated_ids : []),
    ]);
  }
  return result;
}

function mergeSection(section, cloudValue, incomingValue, preferIncoming) {
  if (section === "collection") {
    return mergeCollection(cloudValue, incomingValue, preferIncoming);
  }
  if (section === "inventory") {
    return mergeInventory(cloudValue, incomingValue, preferIncoming);
  }
  if (section === "challenge_progression") {
    return mergeChallengeProgression(cloudValue, incomingValue, preferIncoming);
  }
  return copy(preferIncoming ? incomingValue : cloudValue);
}

function payloadWithMetadata(payload, sectionTimestamps, savedAtMs) {
  const result = copy(payload);
  result.save_meta = {
    saved_at_ms: savedAtMs,
    section_updated_at_ms: copy(sectionTimestamps),
  };
  return result;
}

function cloudResult(existing, outcome) {
  return {
    shouldWrite: false,
    outcome,
    revision: existing.revision,
    epoch: existing.epoch,
    payload: copy(existing.payload),
    sectionRevisions: copy(existing.sectionRevisions),
    sectionUpdatedAtMs: copy(existing.sectionUpdatedAtMs),
  };
}

function freshDocument(incoming, nowMs, revision, outcome) {
  const sectionTimestamps = {};
  const sectionRevisions = {};
  for (const section of CLOUD_SAVE_SECTIONS) {
    sectionTimestamps[section] = (
      sectionTimestamp(incoming.payload, section, nowMs) || nowMs
    );
    sectionRevisions[section] = revision;
  }
  return {
    shouldWrite: true,
    outcome,
    revision,
    epoch: incoming.epoch,
    payload: payloadWithMetadata(incoming.payload, sectionTimestamps, nowMs),
    sectionRevisions,
    sectionUpdatedAtMs: sectionTimestamps,
  };
}

export function resolveCloudSave(existing, incoming, nowMs = Date.now()) {
  if (!existing) return freshDocument(incoming, nowMs, 1, "created");
  if (incoming.epoch < existing.epoch) {
    return cloudResult(existing, "cloud_reset_newer");
  }
  if (incoming.epoch > existing.epoch) {
    return freshDocument(
      incoming,
      nowMs,
      existing.revision + 1,
      "reset_epoch_applied",
    );
  }
  if (incoming.base_revision <= 0 || incoming.base_revision > existing.revision) {
    return cloudResult(existing, "cloud_linked");
  }

  const changedSections = new Set(incoming.changed_sections);
  const forcedConflicts = new Set(incoming.conflict_sections ?? []);
  const nextPayload = copy(existing.payload);
  const nextSectionRevisions = copy(existing.sectionRevisions);
  const nextSectionTimestamps = copy(existing.sectionUpdatedAtMs);
  const nextRevision = existing.revision + 1;
  let mergedConflict = false;
  let contentChanged = false;

  for (const section of CLOUD_SAVE_SECTIONS) {
    const clientChanged = changedSections.has(section);
    const cloudChanged = (
      Number(existing.sectionRevisions?.[section] ?? 0) > incoming.base_revision
      || forcedConflicts.has(section)
    );
    if (!clientChanged) continue;

    const incomingTimestamp = sectionTimestamp(incoming.payload, section, nowMs);
    const cloudTimestamp = normalizedTimestamp(
      existing.sectionUpdatedAtMs?.[section],
      nowMs,
    );
    let candidate;
    let candidateTimestamp;
    if (!cloudChanged) {
      candidate = copy(incoming.payload[section]);
      candidateTimestamp = incomingTimestamp || nowMs;
    } else {
      const preferIncoming = (
        incomingTimestamp > cloudTimestamp
        || (
          incomingTimestamp === cloudTimestamp
          && String(incoming.device_id) > String(existing.lastDeviceId ?? "")
        )
      );
      candidate = mergeSection(
        section,
        existing.payload[section],
        incoming.payload[section],
        preferIncoming,
      );
      candidateTimestamp = nowMs;
      mergedConflict = true;
    }

    if (!isDeepStrictEqual(candidate, existing.payload[section])) {
      nextPayload[section] = candidate;
      nextSectionRevisions[section] = nextRevision;
      nextSectionTimestamps[section] = candidateTimestamp;
      contentChanged = true;
    }
  }

  if (!contentChanged) return cloudResult(existing, "up_to_date");
  return {
    shouldWrite: true,
    outcome: mergedConflict ? "merged" : "client_saved",
    revision: nextRevision,
    epoch: existing.epoch,
    payload: payloadWithMetadata(nextPayload, nextSectionTimestamps, nowMs),
    sectionRevisions: nextSectionRevisions,
    sectionUpdatedAtMs: nextSectionTimestamps,
  };
}

export function validateCloudSaveRequest(value) {
  if (!isPlainObject(value)) return "The request body must be a JSON object.";
  if (value.protocol_version !== CLOUD_SAVE_PROTOCOL_VERSION) {
    return "Unsupported cloud-save protocol version.";
  }
  if (typeof value.save_id !== "string") return "A Save ID is required.";
  const saveId = value.save_id.trim();
  if (
    saveId.length < 12
    || saveId.length > 128
    || /[\u0000-\u001f\u007f]/u.test(saveId)
  ) {
    return "Save ID must contain 12–128 printable characters.";
  }
  if (
    typeof value.device_id !== "string"
    || !/^[a-f0-9]{32}$/u.test(value.device_id)
  ) {
    return "The device ID is invalid.";
  }
  if (!isNonNegativeInteger(value.epoch) || value.epoch > 2_147_483_647) {
    return "The save epoch is invalid.";
  }
  if (!isNonNegativeInteger(value.base_revision)) {
    return "The base revision is invalid.";
  }
  if (!Array.isArray(value.changed_sections)) {
    return "Changed sections must be an array.";
  }
  const changed = new Set(value.changed_sections);
  if (changed.size !== value.changed_sections.length) {
    return "Changed sections contain duplicates.";
  }
  for (const section of changed) {
    if (!CLOUD_SAVE_SECTIONS.includes(section)) {
      return "Changed sections contain an unknown name.";
    }
  }
  const conflictsValue = value.conflict_sections ?? [];
  if (!Array.isArray(conflictsValue)) {
    return "Conflict sections must be an array.";
  }
  const conflicts = new Set(conflictsValue);
  if (conflicts.size !== conflictsValue.length) {
    return "Conflict sections contain duplicates.";
  }
  for (const section of conflicts) {
    if (!CLOUD_SAVE_SECTIONS.includes(section) || !changed.has(section)) {
      return "Conflict sections must also be changed sections.";
    }
  }
  if (!isPlainObject(value.payload) || value.payload.schema_version !== 6) {
    return "Cloud sync requires a schema-6 progression payload.";
  }
  if (
    !isPlainObject(value.payload.profile)
    || !Array.isArray(value.payload.collection)
  ) {
    return "The progression profile or collection is invalid.";
  }
  if (
    value.payload.collection.length < 1
    || value.payload.collection.length > MAX_COLLECTION_SIZE
  ) {
    return "The progression collection size is invalid.";
  }
  for (const section of [
    "move_learning",
    "economy",
    "inventory",
    "challenge_progression",
    "world",
    "save_meta",
  ]) {
    if (!isPlainObject(value.payload[section])) {
      return `The ${section} section is invalid.`;
    }
  }
  if (!isNonNegativeInteger(value.payload.save_meta.saved_at_ms)) {
    return "The save timestamp is invalid.";
  }
  const timestamps = value.payload.save_meta.section_updated_at_ms;
  if (!isPlainObject(timestamps)) return "The save timestamp map is invalid.";
  for (const section of CLOUD_SAVE_SECTIONS) {
    if (!isNonNegativeInteger(timestamps[section])) {
      return `The ${section} timestamp is invalid.`;
    }
  }
  return "";
}
