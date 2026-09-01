# Cloud save function

`cloud-save.mjs` is the server-only Atlas boundary for the optional in-game
cloud save. The browser sends a player-chosen Save ID over HTTPS; the function
HMACs that ID before using it as a MongoDB document key. Neither the raw Save ID
nor the Atlas URI is stored in the cloud-save document.

Before deploying, create these production Netlify site environment variables.
Mark the URI and pepper as secrets, and select Functions-only scope when the
site plan supports granular environment scopes:

- `MONGODB_URI`: the rotated Atlas connection string.
- `MONGODB_DATABASE`: optional database name; defaults to `pfr_locomotion`.
- `CLOUD_SAVE_PEPPER`: at least 32 random characters, generated independently
  from the database password and kept stable for the lifetime of the saves.

Do not put any of these values in `netlify.toml`, Godot project settings, source
files, or the published Web build. Atlas must also allow connections from the
Netlify function runtime and the database user should have read/write access
only to the chosen game-save database.

On Netlify plans without granular scopes, secret values are also available to
the site's build/runtime processes. This project's build does not read them;
retain the post-export credential scan whenever the deployment pipeline changes.

Run the deterministic resolver tests with:

```bash
npm run test:cloud-save
```
