# Runtime AI Context Index

Read this index first for runtime tasks, then select only the narrow document
needed for the current task. These documents describe verified current behavior;
check the linked implementation before changing its contract.

| Task | Read next | Purpose |
| --- | --- | --- |
| Display a UI template, author dialog data, or implement dialog playback | [`dialog-ui.md`](dialog-ui.md) | Caller ownership, data and template APIs, lifecycle, and current trainer usage |
| Implement a gameplay sequence, disable player movement, or clean up control state | [`sequences.md`](sequences.md) | Current sequence model, movement-control authority, ownership rules, and limitations |
| Add an NPC action, town resident dialog/roaming, change forward target selection, or modify the interaction HUD | [`interaction-hud.md`](interaction-hud.md) | RND target geometry, shared HUD input, behavior dispatch, and trainer/healer/resident modes |
| Change the permanent player menu, Party/PC organization, held items, bag management, or Pokedex browser | [`player-menu.md`](player-menu.md) | Shared HUD entry, modal ownership, collection/inventory APIs, GIF presentation, and regression coverage |
| Add or change evolution levels, eligibility, branching choices, or species mutation | [`evolution.md`](evolution.md) | Level-flattening policy, direct-stage APIs, collection invariants, menu prompt, and battle notification |
| Change first-run starter selection, fresh-profile initialization, or full progress reset | [`starter-selection.md`](starter-selection.md) | Exact starter roster, animated GIF cards, movement ownership, schema-5 profile identity, destructive warnings, and reset lifecycle |
| Change automatic progression saves, collection reload, or overworld pose persistence | [`progression-autosave.md`](progression-autosave.md) | RND save owner, schema, checkpoint triggers, validation, and same-scene restore behavior |
| Change optional cloud saves, Save IDs, offline synchronization, conflict resolution, Atlas, or the Netlify save function | [`cloud-save.md`](cloud-save.md) | Client/server trust boundary, local linkage state, merge policy, reset epochs, deployment secrets, and regression coverage |
| Change level-up learnsets, move replacement, or pending move-choice persistence | [`move-learning.md`](move-learning.md) | Generated PokeAPI policy, queue ownership, four-move choice flow, battle sequencing, save data, and regression coverage |
| Change Stretchman, shops, loot boxes, money rewards, gyms, generated routes, or the Champion run | [`stretch-goals.md`](stretch-goals.md) | RND ownership, economy/catalog rules, GIF shop art, destination encounter data, and existing-trainer reuse |
| Start a battle, pass launch data, change to the battle scene, or adjust battle transition presentation | [`battle-start.md`](battle-start.md) | Verified `startBattle` contract, temporary data handoff, template ownership, scene reveal, and failure behavior |
| Change the Godot battle session, REST validation/retry behavior, collection health/XP writeback, request UI, or event sequencing | [`battle-client.md`](battle-client.md) | Central coordinator ownership, transport/token boundaries, typed inputs, copied presentation state, knockout XP, error policy, party migration, and encounter authoring |
| Build, deploy, upgrade, or diagnose the stateless PvE battle REST service | [`battle-server.md`](battle-server.md) | API boundaries, token replay contract, pinned Showdown integration, HP lifecycle, and deployment checks |
| Regenerate, verify, load, ground, animate, or export battle sprites | [`battle-sprites.md`](battle-sprites.md) | Verified GIF provenance, offline atlas pipeline, exact catalog lookup, lazy loading, presenter motion, and export boundaries |

This directory is limited to verified runtime ownership and lifecycle contracts. Check linked implementation and regression tests before changing a contract, update the narrowest leaf when behavior changes, and add every new runtime leaf to this index.
