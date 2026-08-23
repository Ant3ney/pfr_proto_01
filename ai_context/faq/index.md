# PFR Locomotion Prototype Troubleshooting FAQ

Read this index first when diagnosing a recurring project-specific failure. Choose only the narrowest document that matches the observed behavior.

| Task | Read next | Purpose |
| --- | --- | --- |
| Diagnose a trainer that detects the player and stops player movement but does not move on a baked navigation mesh | [`trainer-navigation-path-height.md`](trainer-navigation-path-height.md) | Recognize a vertical path-offset stall, preserve foot-level character placement, and verify the automatic correction |

This directory is limited to verified, reusable failure modes whose causes are difficult to rediscover. Confirm every diagnosis against current code, scenes, tests, and runtime behavior; update or remove a leaf when implementation changes invalidate it, and add each new FAQ to this index.
