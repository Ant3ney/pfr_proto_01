# Repository Agent Instructions

These instructions apply to the entire repository.

## AI Context workflow

The `ai_context/` directory contains durable, project-specific knowledge for future AI agents. It uses progressive disclosure so agents load only the context needed for the current task.

1. Always read [`ai_context/index.md`](ai_context/index.md) before reading another AI Context document.
2. Use the index's `Task | Read next | Purpose` table to choose only the context relevant to the current task.
3. When a row points to a directory, read that directory's `index.md`, then select the narrowest applicable leaf document.
4. Do not automatically load the entire directory. If several subjects genuinely apply, follow each route through its index.
5. Inspect the current code, configuration, tests, and runtime behavior before acting. Verified current behavior overrides stale documentation.

## Adding and maintaining AI Context

Store information in `ai_context/` only when it is verified, reusable, project-specific, and expensive or difficult to rediscover.

1. Prefer updating an existing document over creating overlapping documentation.
2. Keep one primary subject per leaf document.
3. Use descriptive lowercase Markdown filenames consistent with neighboring files.
4. Use relative Markdown links.
5. Add every new document to its immediate parent index.
6. Add a row to the root index only when introducing a genuinely broad category.
7. Create a subdirectory only when multiple related documents or a separate routing layer justify it. Every such directory must have an `index.md` that routes to its narrower documents.
8. Update or remove context invalidated by implementation changes in the same change.
9. Validate all links and run `git diff --check` before completing work.

Do not store speculation, temporary debugging output, transient machine paths, or facts that are more reliably discovered from the repository. Never store credentials, API keys, passwords, cookies, tokens, nonces, private keys, or any other secrets in AI Context.
