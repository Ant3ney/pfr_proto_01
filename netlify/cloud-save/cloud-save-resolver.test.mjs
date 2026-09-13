import test from "node:test";
import assert from "node:assert/strict";
import {
  CLOUD_SAVE_SECTIONS,
  resolveCloudSave,
  validateCloudSaveRequest,
} from "./cloud-save-resolver.mjs";

const NOW = 2_000_000;

function pokemon(pclID, currentXp, level = 5) {
  return {
    pokemonId: 25,
    pclID,
    party: {
      inParty: pclID === "starter",
      slot: pclID === "starter" ? 1 : null,
    },
    instanceStats: { health: 1, currentXp, level },
    battleProfile: {
      species: "Pikachu",
      spriteId: "pikachu",
      moves: ["growl"],
    },
  };
}

function payload(timestamp = 1000) {
  return {
    schema_version: 6,
    profile: { starter_pokemon_id: 4 },
    collection: [pokemon("starter", 100)],
    move_learning: { pending: [] },
    economy: {
      version: 2,
      balance: 50,
      last_battle_reward: {},
    },
    inventory: {
      item_quantities: {},
      claimed_gifts: [],
    },
    challenge_progression: {
      earned_badges: [],
      champion_completed: false,
      completed_routes: [],
      active_area_id: "",
      run_defeated_ids: [],
      run_id: 0,
    },
    world: {
      scene_path: "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn",
    },
    save_meta: {
      saved_at_ms: timestamp,
      section_updated_at_ms: Object.fromEntries(
        CLOUD_SAVE_SECTIONS.map((section) => [section, timestamp]),
      ),
    },
  };
}

function incoming(overrides = {}) {
  return {
    protocol_version: 1,
    save_id: "a-private-save-id",
    device_id: "0123456789abcdef0123456789abcdef",
    epoch: 0,
    base_revision: 0,
    changed_sections: [...CLOUD_SAVE_SECTIONS],
    conflict_sections: [],
    payload: payload(),
    ...overrides,
  };
}

function documentFrom(
  resolution,
  deviceId = "00000000000000000000000000000000",
) {
  return {
    revision: resolution.revision,
    epoch: resolution.epoch,
    payload: resolution.payload,
    sectionRevisions: resolution.sectionRevisions,
    sectionUpdatedAtMs: resolution.sectionUpdatedAtMs,
    lastDeviceId: deviceId,
  };
}

test("validates schema 6 without accepting short Save IDs", () => {
  assert.equal(validateCloudSaveRequest(incoming()), "");
  assert.match(
    validateCloudSaveRequest(incoming({ save_id: "too-short" })),
    /12–128/,
  );
  const invalidClock = incoming();
  invalidClock.payload.save_meta.saved_at_ms = -1;
  assert.match(validateCloudSaveRequest(invalidClock), /timestamp/);
  assert.match(
    validateCloudSaveRequest(incoming({
      changed_sections: ["profile"],
      conflict_sections: ["collection"],
    })),
    /also be changed/,
  );
});

test("creates a cloud document and first-time links pull cloud", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  assert.equal(created.outcome, "created");
  assert.equal(created.revision, 1);
  const cloud = documentFrom(created);
  const differentLocal = incoming();
  differentLocal.payload.economy.balance = 9999;
  const linked = resolveCloudSave(cloud, differentLocal, NOW + 100);
  assert.equal(linked.outcome, "cloud_linked");
  assert.equal(linked.payload.economy.balance, 50);
});

test("a causal local section change advances the revision", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  const cloud = documentFrom(created);
  const next = incoming({
    base_revision: 1,
    changed_sections: ["collection"],
  });
  next.payload.collection[0].instanceStats.currentXp = 250;
  next.payload.save_meta.section_updated_at_ms.collection = NOW + 50;
  const saved = resolveCloudSave(cloud, next, NOW + 100);
  assert.equal(saved.outcome, "client_saved");
  assert.equal(saved.revision, 2);
  assert.equal(saved.payload.collection[0].instanceStats.currentXp, 250);
  assert.equal(saved.payload.economy.balance, 50);
});

test("an in-flight first-link edit can force a smart section conflict", () => {
  const cloudRequest = incoming();
  cloudRequest.payload.collection.push(pokemon("cloud-catch", 30));
  const created = resolveCloudSave(null, cloudRequest, NOW);
  const local = incoming({
    base_revision: 1,
    changed_sections: ["collection"],
    conflict_sections: ["collection"],
  });
  local.payload.collection.push(pokemon("local-catch", 45));
  local.payload.save_meta.section_updated_at_ms.collection = NOW + 20;
  const merged = resolveCloudSave(documentFrom(created), local, NOW + 30);
  assert.equal(merged.outcome, "merged");
  assert.deepEqual(
    new Set(merged.payload.collection.map((entry) => entry.pclID)),
    new Set(["starter", "cloud-catch", "local-catch"]),
  );
});

test("divergent collections retain captures and greatest earned XP", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  const cloudChange = incoming({
    base_revision: 1,
    changed_sections: ["collection"],
  });
  cloudChange.payload.collection.push(pokemon("cloud-catch", 30));
  cloudChange.payload.collection[0].instanceStats.currentXp = 180;
  cloudChange.payload.save_meta.section_updated_at_ms.collection = NOW + 10;
  const cloudSaved = resolveCloudSave(
    documentFrom(created),
    cloudChange,
    NOW + 20,
  );

  const offline = incoming({
    base_revision: 1,
    changed_sections: ["collection"],
  });
  offline.payload.collection.push(pokemon("offline-catch", 40));
  offline.payload.collection[0].instanceStats.currentXp = 300;
  offline.payload.save_meta.section_updated_at_ms.collection = NOW + 30;
  const merged = resolveCloudSave(documentFrom(cloudSaved), offline, NOW + 40);
  assert.equal(merged.outcome, "merged");
  assert.deepEqual(
    new Set(merged.payload.collection.map((entry) => entry.pclID)),
    new Set(["starter", "cloud-catch", "offline-catch"]),
  );
  assert.equal(
    merged.payload.collection[0].instanceStats.currentXp,
    300,
  );
  assert.equal(
    merged.payload.collection.find(
      (entry) => entry.pclID === "cloud-catch",
    ).party.inParty,
    false,
  );
});

test("domain conflicts preserve achievements, gifts, and newer economy", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  const cloudChange = incoming({
    base_revision: 1,
    changed_sections: ["economy", "inventory", "challenge_progression"],
  });
  cloudChange.payload.economy.balance = 25;
  cloudChange.payload.inventory.claimed_gifts = ["cloud-gift"];
  cloudChange.payload.challenge_progression.completed_routes = [0, 1];
  cloudChange.payload.challenge_progression.earned_badges = [1];
  for (const section of ["economy", "inventory", "challenge_progression"]) {
    cloudChange.payload.save_meta.section_updated_at_ms[section] = NOW + 10;
  }
  const cloudSaved = resolveCloudSave(
    documentFrom(created),
    cloudChange,
    NOW + 20,
  );

  const offline = incoming({
    base_revision: 1,
    changed_sections: ["economy", "inventory", "challenge_progression"],
  });
  offline.payload.economy.balance = 400;
  offline.payload.challenge_progression.completed_routes = [0, 1, 2];
  offline.payload.inventory.claimed_gifts = ["exp-share-gift"];
  for (const section of ["economy", "inventory", "challenge_progression"]) {
    offline.payload.save_meta.section_updated_at_ms[section] = NOW + 30;
  }
  const merged = resolveCloudSave(documentFrom(cloudSaved), offline, NOW + 40);
  assert.equal(merged.payload.economy.balance, 400);
  assert.deepEqual(merged.payload.challenge_progression.completed_routes, [0, 1, 2]);
  assert.deepEqual(merged.payload.challenge_progression.earned_badges, [1]);
  assert.deepEqual(
    new Set(merged.payload.inventory.claimed_gifts),
    new Set(["cloud-gift", "exp-share-gift"]),
  );
});

test("concurrent route achievements retain Route 40 and reject out-of-range routes", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  const cloudChange = incoming({
    base_revision: 1,
    changed_sections: ["challenge_progression"],
  });
  cloudChange.payload.challenge_progression.completed_routes = Array.from({ length: 40 }, (_, i) => i);
  cloudChange.payload.save_meta.section_updated_at_ms.challenge_progression = NOW + 10;
  const cloudSaved = resolveCloudSave(documentFrom(created), cloudChange, NOW + 20);
  const offline = incoming({
    base_revision: 1,
    changed_sections: ["challenge_progression"],
  });
  offline.payload.challenge_progression.completed_routes = [40, 41, -1];
  offline.payload.save_meta.section_updated_at_ms.challenge_progression = NOW + 30;
  const merged = resolveCloudSave(documentFrom(cloudSaved), offline, NOW + 40);
  assert.deepEqual(
    merged.payload.challenge_progression.completed_routes,
    Array.from({ length: 41 }, (_, i) => i),
  );
});

test("a reset epoch replaces old data and old devices cannot undo it", () => {
  const created = resolveCloudSave(null, incoming(), NOW);
  const resetRequest = incoming({ epoch: 1, base_revision: 1 });
  resetRequest.payload.collection = [pokemon("new-starter", 0)];
  const reset = resolveCloudSave(
    documentFrom(created),
    resetRequest,
    NOW + 50,
  );
  assert.equal(reset.outcome, "reset_epoch_applied");
  assert.equal(reset.epoch, 1);
  const stale = resolveCloudSave(
    documentFrom(reset),
    incoming({ base_revision: 1 }),
    NOW + 100,
  );
  assert.equal(stale.outcome, "cloud_reset_newer");
  assert.equal(stale.payload.collection[0].pclID, "new-starter");
});
