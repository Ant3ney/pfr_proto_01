# Exp. Share Appears Not to Gain Levels

Use this note when a party Pokemon visibly holds the Exp. Share but appears to
remain at the same level through several battles.

## Verified behavior

`BattleSystem` remembers every party member that entered the current battle.
Each opponent knockout gives those participants their normal local XP award. A
party member that did not enter but holds `exp-share` receives half of the award
calculated from its own level; a participating holder receives the normal full
award without doubling it. `CollectionSystem.apply_battle_health_and_experience()`
commits health and all XP recipients atomically.

Remaining at one level does not prove the award is missing. Gible uses the slow
growth curve: Lv. 5 begins at 156 cumulative XP and Lv. 6 begins at 270, a
114-XP interval. A Gible at 184 cumulative XP has gained 28 XP and still needs
86. The player-menu row now exposes this as `XP 28/114`, its detail panel shows
the remaining amount, and each battle XP message reports the current level,
in-level progress, and XP remaining. For example, `Lv. 7 progress: 173/212 XP
(39 XP to Lv. 8)` is not a level-up notice. A trainer with two Pokemon produces
two legitimate Exp. Share gain messages, one after each knockout. Only text
that explicitly says `grew to Lv. 8` announces that the level was reached.

`BattleSystem` also keeps a per-session high-water mark for announced levels.
Even if a repeated upstream level flag reaches presentation, the same Pokemon
cannot announce the same reached level twice in one battle.

## Verification

Confirm the PCL is in the current party, its `heldItem` is exactly `exp-share`,
and its cumulative `currentXp` rises after a knockout. The focused battle test
replaces Party Slot 2 with a near-threshold Lv. 7 Gible, gives it the Exp.
Share, keeps it out while another member battles, and verifies the exact half
awards across two knockouts, one and only one Lv. 8 announcement, readable
remaining-XP progress, retry safety, and duplicate-callback safety:

```bash
godot --headless --path . --scene res://tests/integration/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/scenes/player_menu_hud_smoke_test.tscn
```

Do not diagnose a failure from the displayed level alone. If cumulative XP does
not change after a validated opponent knockout, inspect the accepted snapshot's
faint transition and the generated `experience` presentation event.
