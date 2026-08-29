# PFR Locomotion Prototype AI Context Index

Read this index first. Use the table to load only the context needed for the current task.

| Task | Read next | Purpose |
| --- | --- | --- |
| Define or review the overall game vision, audience, gameplay, audio, story, or art goals | [`game-design.md`](game-design.md) | High-level game design direction for Pokémon Fracture and Revolt |
| Review the planned battle, overworld, interaction, collection, progression, or save architecture | [`technical-design.md`](technical-design.md) | Technical design intentions that must be checked against the current implementation |
| Implement or change battle starts, the battle REST service, dialogs, UI template callbacks, sequences, or player movement locks | [`runtime/index.md`](runtime/index.md) | Verified runtime ownership and lifecycle contracts for battle launch, the stateless battle API, dialog/UI, and sequences |
| Work on the central narrative, player journey, rival, or Team Bastion conflict | [`story-overview.md`](story-overview.md) | Focused synopsis of the game's main story |
| Choose the region's visual mood, civic imagery, version colors, environment style, or presentation tone | [`art-direction.md`](art-direction.md) | Project-specific art direction and visual identity |
| Set overworld geometry, texture, material, lighting, composition, character-art, or asset-budget constraints | [`overworld-art-framework.md`](overworld-art-framework.md) | Handheld-era visual and technical production envelope for overworld assets |
| Model or place modular terrain, choose scale and snapping values, or build the first ground kit | [`modular-ground-scale-guide.md`](modular-ground-scale-guide.md) | Player-relative measurements, module sizes, Blender setup, seam rules, and Godot placement guidance |
| Browse, place, transfer, troubleshoot, or validate New Bouffalant City environment assets | [`new-bouffalant-city-assets.md`](new-bouffalant-city-assets.md) | Runtime pack layout, placement contracts, Vulkan-safe import exceptions, provenance, and validation commands |
| Diagnose a recurring project-specific failure or surprising runtime behavior | [`faq/index.md`](faq/index.md) | Route to verified failure signatures, causes, fixes, and regression checks |
| Add or maintain durable project context | [`../AGENTS.md`](../AGENTS.md) | Follow the authoritative rules for verifying, organizing, linking, and validating AI Context |

These documents include design intent, production guidance, and verified runtime contracts, but none overrides current implementation. Verify relevant claims against the current code, configuration, assets, scenes, tests, and runtime before acting. Update the narrowest existing document when durable knowledge changes, and create a subject directory only when multiple related documents or a separate routing layer justify it. Never store secrets here.
