# switcher

Swap the live Claude Code and Codex CLI logins between saved accounts, from a
terminal or from the Omarchy bar.

## Why

Claude Code and Codex each keep exactly one login on disk. Cycling through
several subscriptions means re-running the browser login every time a limit
hits. `switcher` keeps a private copy of each login and puts the chosen one
back in place, so a switch is one command instead of a browser round trip.

## Model

- **Claude Code**: the login is `~/.claude/.credentials.json` (tokens, plan)
  plus the `oauthAccount` object inside `~/.claude.json` (email, org). A switch
  rewrites the credentials file and splices `oauthAccount` into the existing
  `~/.claude.json`, leaving every other key untouched. Running Claude Code
  sessions pick the new login up on their own. `CLAUDE_CONFIG_DIR` is honored.
- **Codex**: the login is `~/.codex/auth.json`. Email and plan are read from the
  `id_token` claims inside it. A switch rewrites the file; a running Codex TUI
  keeps its old tokens until restarted, new `codex` processes use the new login.
  `CODEX_HOME` is honored. An API-key login has no email; it is saved and
  restored under the fixed name `api-key`.
- **Store**: `$XDG_DATA_HOME/switcher/<provider>/<email>/` (default
  `~/.local/share/switcher`), directories `0700`, files `0600`, every write
  through a same-directory temp file and rename. A `lock` directory serializes
  concurrent switchers.
- **Save-back**: both CLIs rotate tokens while they run, so before installing
  another account `use` first saves the currently live login into its own slot.
  A saved copy is therefore never staler than the last switch away from it.
  The Claude install writes two files; a marker in the store brackets the pair
  so that a switch interrupted between them can never save one account's
  tokens under another account's email. `save` refuses while the marker is
  present and the next `use` clears it.
- **Live files that are symlinks** stay symlinks: the write replaces the file
  the link points at.
- **Never log out**: `codex logout` and `claude auth logout` revoke tokens
  server-side, which would kill the saved copy too. `add` runs the provider's
  login command with the store's copy of the live login refreshed first, then
  saves the new login. No command ever runs a logout.

## Commands

```
switcher status [--json]          live account and saved accounts per provider
switcher save [claude|codex]      copy the live login(s) into the store
switcher use <provider> <email>   save back the live login, install <email>
switcher add <provider>           run the provider login, then save the result
switcher forget <provider> <email>
```

Exit codes: 0 ok, 64 usage, 1 any other failure with a one-line reason on
stderr. `use` and `add` also ask `omarchy-agent-usage-update --limits-only` to
refresh the Omarchy agents widget for that provider when it is on PATH.

`status --json` shape:

```json
{"providers":[{"id":"claude","live":{"email":"a@x","plan":"max"},
  "accounts":[{"email":"a@x","plan":"max","active":true}]}, ...]}
```

`live` is `null` without a login; `plan` is `""` when the file has none. A
provider whose files cannot be read carries an `"error"` string and keeps its
`accounts` list, so the other provider and every saved login stay usable.

## Bar widget

`plugin/joel.switcher` is an Omarchy bar widget. It only runs the CLI: the
panel renders `status --json`, a saved account row runs `use`, "Save current"
runs `save`, and "Add account…" opens a terminal running `add` because the
login needs a browser and a prompt. Install:

```sh
./build.sh                                   # needs a Habu checkout, see AGENTS.md
omarchy plugin enable joel.switcher --section right --before omarchy.agents
```

`build.sh` also copies the widget into `~/.config/omarchy/plugins/`. The
enable is needed once. After a QML change run `omarchy-restart-shell`: the
shell's plugin reload keeps the old compiled component in this Qt build.

## Build and test

`build.sh` compiles `src/switcher.f` with Habu's `tools/hb-build.f --repl` and
installs `~/.local/bin/switcher`. `test.sh` runs the checked test suite inside
a scratch `HOME`; it never reads or writes real credentials. Set `HABU` to the
Habu checkout to use (default `~/Work/habu`).
