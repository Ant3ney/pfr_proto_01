# Runtime AI Context Index

Read only the narrow document needed for the current task. These documents
describe verified current behavior; check the linked implementation before
changing its contract.

| Task | Read next | Purpose |
| --- | --- | --- |
| Display a UI template, author dialog data, or implement dialog playback | [`dialog-ui.md`](dialog-ui.md) | Caller ownership, data and template APIs, lifecycle, and current trainer usage |
| Implement a gameplay sequence, disable player movement, or clean up control state | [`sequences.md`](sequences.md) | Current sequence model, movement-control authority, ownership rules, and limitations |
| Start a battle, pass launch data, change to the battle scene, or adjust battle transition presentation | [`battle-start.md`](battle-start.md) | Verified `startBattle` contract, temporary data handoff, template ownership, scene reveal, and failure behavior |

This directory is limited to verified runtime ownership and lifecycle contracts. Check linked implementation and regression tests before changing a contract, update the narrowest leaf when behavior changes, and add every new runtime leaf to this index.
