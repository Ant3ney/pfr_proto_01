# PFR Locomotion Prototype Troubleshooting FAQ

Read this index first when diagnosing a recurring project-specific failure. Choose only the narrowest document that matches the observed behavior.

| Task | Read next | Purpose |
| --- | --- | --- |
| Diagnose a trainer that detects the player and stops player movement but does not move on a baked navigation mesh | [`trainer-navigation-path-height.md`](trainer-navigation-path-height.md) | Recognize a vertical path-offset stall, preserve foot-level character placement, and verify the automatic correction |
| Diagnose trainers that stop noticing or accepting interaction after earlier battles, but recover after restarting the game | [`trainer-interaction-state-leak.md`](trainer-interaction-state-leak.md) | Recognize shared resource state, preserve instance-local trainer behavior, and avoid empty battle configuration after duplication |
| Diagnose trainers that are inert only in a release/web export while generated routes, gyms, and the League contain no opponents | [`web-export-trainer-behavior.md`](web-export-trainer-behavior.md) | Recognize an exported null trainer behavior, preserve both repair boundaries, and verify the packaged PCK rather than only source scenes |

This directory is limited to verified, reusable failure modes whose causes are difficult to rediscover. Confirm every diagnosis against current code, scenes, tests, and runtime behavior; update or remove a leaf when implementation changes invalidate it, and add each new FAQ to this index.
