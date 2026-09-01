# pfr_proto_01 Troubleshooting FAQ

Read this index first when diagnosing a recurring project-specific failure. Choose only the narrowest document that matches the observed behavior.

| Task | Read next | Purpose |
| --- | --- | --- |
| Diagnose a trainer that detects the player and stops player movement but does not move on a baked navigation mesh | [`trainer-navigation-path-height.md`](trainer-navigation-path-height.md) | Recognize a vertical path-offset stall, preserve foot-level character placement, and verify the automatic correction |
| Diagnose trainers that stop noticing or accepting interaction after earlier battles, but recover after restarting the game | [`trainer-interaction-state-leak.md`](trainer-interaction-state-leak.md) | Recognize shared resource state, preserve instance-local trainer behavior, and avoid empty battle configuration after duplication |
| Diagnose trainers that are inert only in a release/web export while generated routes, gyms, and the League contain no opponents | [`web-export-trainer-behavior.md`](web-export-trainer-behavior.md) | Recognize an exported null trainer behavior, preserve both repair boundaries, and verify the packaged PCK rather than only source scenes |
| Diagnose a Netlify web build that downloads the large game pack again on repeat visits, or update its browser-cache behavior | [`web-export-browser-cache.md`](web-export-browser-cache.md) | Preserve the content-versioned service-worker contract, understand first-load and storage limits, and verify repeat loads without stale exports |
| Diagnose an Exp. Share holder that appears not to gain levels after several battles | [`xp-share-level-progress.md`](xp-share-level-progress.md) | Distinguish a missing reward from slow in-level growth, verify held-item awards, and preserve visible XP progress feedback |

This directory is limited to verified, reusable failure modes whose causes are difficult to rediscover. Confirm every diagnosis against current code, scenes, tests, and runtime behavior; update or remove a leaf when implementation changes invalidate it, and add each new FAQ to this index.
