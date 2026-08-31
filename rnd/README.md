# RND Runtime Systems

New experimental runtime systems live here during the current RND phase.

- `interaction/PlayerInteractionDetector.gd` selects one visible character in
  front of the shared player and dispatches its behavior through the GameUI
  interaction button.
- `player_menu/` owns the permanent shared-GameUI menu button and the modal
  Party/PC organizer, persistent bag manager, and complete owned/missing
  Pokedex. Pokemon lists reuse the generated battle GIF catalog for still icons
  and animated previews.
- `move_learning/` derives level-up learnsets from the committed PokeAPI data,
  queues moves earned on real level changes, and owns the four-slot
  replace-or-keep modal while `CollectionSystem` remains the move-set owner.
- `save/ProgressionAutosave.gd` owns automatic collection and overworld-pose
  persistence.
- `stretch/` owns Stretchman's experimental economy and hub: complete item and
  default-Pokemon catalogs, fuzzy shop search and filters, GIF-derived Pokemon
  icons/previews, tiered loot-box reels, eight gyms, eight trainer routes, and
  the Elite Four/Champion run. Generated opponents configure the project's
  existing authored trainer scenes and `TrainerBehavior`; there is no RND
  trainer implementation.
- `TallGrassEncounterZone.gd` owns the existing experimental wild encounter
  trigger.
- `tests/` contains focused headless regression scenes for the RND systems.

Durable behavior contracts and test commands are routed through
[`ai_context/runtime/index.md`](../ai_context/runtime/index.md).
