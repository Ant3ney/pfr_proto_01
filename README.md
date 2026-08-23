# PFR Locomotion Prototype

A Godot prototype for reusable 3D character locomotion, player controls, camera behavior, and NPC navigation.

## AI Context

[`ai_context/`](ai_context/) holds durable, project-specific knowledge that would otherwise be costly for future contributors and AI agents to rediscover. Start at [`ai_context/index.md`](ai_context/index.md), use its task-oriented routing table, and read only the narrowest document relevant to the work. When a route leads to a subject directory, read that directory's `index.md` before selecting a leaf document.

When a verified lesson remains useful beyond the current task, update the closest existing context document and its immediate index. Create a focused leaf only when existing documents do not cover the subject. Introduce a new subject directory only when multiple related documents or a distinct routing layer justify it, and give the directory its own routing `index.md`.

Current code, configuration, tests, and verified runtime behavior take precedence over the documentation. Never put credentials, keys, passwords, cookies, tokens, nonces, private keys, or other secrets in `ai_context/`. See [`AGENTS.md`](AGENTS.md) for the complete agent-facing rules.

## Environment Assets

The New Bouffalant City runtime environment pack, metric asset browser, catalog, and validation instructions are documented in [`art/environments/new_bouffalant_city/README.md`](art/environments/new_bouffalant_city/README.md).
