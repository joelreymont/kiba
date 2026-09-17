# kiba

Switch the live Claude Code and Codex CLI logins between saved accounts, and
see which account still has room, from a terminal or from the Omarchy bar.

## Why

Claude Code and Codex each keep exactly one login on disk. Cycling through
several subscriptions means re-running the browser login every time a limit
hits, and guessing which account to switch to next. kiba keeps a private copy
of each login, puts the chosen one back in place in one command, and asks each
provider how much of every saved account's allowance is left.

## Requirements

- Omarchy 4 (the bar widget is an Omarchy shell plugin), `curl`, and the
  `claude` and `codex` CLIs you already use.
- A checkout of [Habu](https://github.com/joelreymont/habu), the checked
  Forth the CLI is written in; see [AGENTS.md](AGENTS.md).

## Install

```sh
./build.sh                                            # builds and installs ~/.local/bin/kiba and the widget
omarchy plugin enable kiba --section right --before omarchy.agents
kiba save                                             # keep the logins you have now
```

To add another account, sign into it at claude.ai or chatgpt.com in your
browser, then use "Add account…" in the widget or run `kiba add claude` /
`kiba add codex`. The terminal first reminds you to sign into the account in
the browser and waits for Enter, because the provider's login page authorizes
whichever account the browser is signed into; kiba saves what comes back
under that account's name and, when you named an account, tells you if a
different one came back.
Adding never touches the live login; switch with `use` or a click. Never run
the providers' logout commands: both revoke the tokens server-side and the
saved copy dies with them.

## Commands

```
kiba status [--json]          live account, saved accounts, and their usage
kiba save [claude|codex]      copy the live login(s) into the store
kiba use <provider> <name>    save back the live login, install <name>
kiba add <provider> [name]    log in to a new (or the named) account, save it
kiba forget <provider> <name>
kiba usage [claude|codex]     probe the rate limits of every saved account
```

`<name>` is the account's email, or `email #2`, `email #3` for further
logins under the same email. Exit codes: 0 ok, 64 usage, 1 any other failure
with a one-line reason on stderr. `use` and `add` re-probe the account they
touched, so the widget shows its figures at once.

`status --json` shape:

```json
{"providers":[{"id":"claude","live":{"email":"a@x","plan":"max"},
  "accounts":[{"email":"a@x","plan":"max","active":true,
    "usage":{"fetchedAt":1789480000,"note":"",
      "limits":[{"label":"Session (5-hour)","percent":56,"resetsAt":"2026-09-15T14:00:00+00:00"},
                {"label":"Weekly (7-day)","percent":14,"resetsAt":"2026-09-21T11:00:00+00:00"}]}}]}, ...]}
```

`live` is `null` without a login; `plan` is `""` when the file has none. A
provider whose files cannot be read carries an `"error"` string and keeps its
`accounts` list, so the other provider and every saved login stay usable.
`usage` is `null` until the account has been probed; `percent` is the whole
number used, `state` is one of `ok`, `expired`, `revoked`, `error`, or
`unknown`, and `note` explains anything but `ok`.

## How switching works

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
- **Two logins under one email** (a second Claude organization or a second
  ChatGPT workspace) get separate slots in the order they are added: the first
  keeps the bare email, the next are `email #2`, `email #3`. The store matches
  a login to its slot by organization, never by position.
- **Store**: `$XDG_DATA_HOME/kiba/<provider>/<name>/` (default
  `~/.local/share/kiba`), directories `0700`, files `0600`, every write
  through a same-directory temp file and rename. A `lock` directory holding
  the owner's pid serializes concurrent runs; a lock whose owner is dead is
  taken over, and `status` never takes it.
- **Save-back**: both CLIs rotate tokens while they run, so before installing
  another account `use` first saves the currently live login into its own slot.
  A saved copy is therefore never staler than the last switch away from it.
  The Claude install writes two files; a marker in the store brackets the pair
  so that a switch interrupted between them can never save one account's
  tokens under another account's name. `save` refuses while the marker is
  present and the next `use` clears it. kiba also records which slot it
  installed last: if `.claude.json` later names another account while the
  credentials are still byte-for-byte the installed slot's, the pair is
  mixed, save-back leaves it alone, and `save` says so.
- **Live files that are symlinks** stay symlinks on `use` and `save`: the
  write replaces the file the link points at. `add` is the exception: the
  provider's own login creates a fresh regular file, so after an `add` the
  live file is a plain file and the old link target keeps the previous
  account's tokens until you remove it.
- **Login runs in the foreground, in a throwaway home**: `add` forks and
  execs the provider's login with `CLAUDE_CONFIG_DIR` or `CODEX_HOME`
  pointing at a private directory under `<store>/probe/`, so the login never
  sees the live login: nothing is read, revoked (`codex login` revokes
  whatever login it finds), or replaced while your sessions are working. The
  new login is read from that directory, saved under its name, probed, and
  the directory is removed. The child stays in the terminal's process group;
  a child in its own group is stopped by SIGTTIN the moment it reads the
  terminal.

## Usage per account

`kiba usage` answers "which account still has room". For every saved account
it asks the provider's own usage endpoint with that account's saved token,
through `curl`, and keeps the reported windows in `<slot>/usage.json`:

- Claude: `GET https://api.anthropic.com/api/oauth/usage` with the OAuth
  access token. Windows: `Session (5-hour)`, `Weekly (7-day)`, and every
  model-scoped window the payload lists, named after the model, such as
  `Fable Weekly`.
- Codex: `GET https://chatgpt.com/backend-api/wham/usage` with the access
  token and account id. Windows are named from their length: five hours is
  the session, seven days the week.

A saved (non-live) account is refreshed once through the provider's token
endpoint when its token has expired (Claude) or is rejected (Codex), and the
new tokens replace the slot's. The live account is never refreshed by kiba:
its CLI owns that token, and rotating it underneath a running session would
log the session out, so an expired live token is reported as `expired` and
not sent. A Codex login whose refresh grant is refused after the provider
called it revoked has no value left, so its slot is removed; log into the
account again and add it. Any other failure is recorded as that account's
`state` and `note` and the run continues with the next account and the next
provider. Network calls run without the store lock; only the saved-back live
login and each slot write take it. Headers, which carry the token, reach
`curl` through a 0600 file, never through argv; scratch files live under
`<store>/probe/` and are removed after each request. Every request names
`kiba` as its User-Agent (the ChatGPT usage call keeps `codex-cli`):
Anthropic's token endpoint answers 429 to curl's own, whatever the grant.

## Bar widget

`plugin/kiba` renders `kiba status --json` and only ever runs the CLI:
an account row runs `use`, "Save the current login" runs `save`, "Add
account…" opens a terminal running `add` (the login needs a browser and a
prompt), and "Refresh usage" runs `usage`. The panel probes every account
once each time it opens; the rows update as the answers arrive.

Rows are ordered by color, green first, then yellow, red, and grey. Red rows
come in the order their limits reset, soonest first, with dead logins last;
within any other color rows keep their name order. Each row carries a dot
and what is left of the session, the week, and each model window, as three
percentages in that order (the hover text names them): green with at least
half of the session and of every weekly window left, yellow below that, red
once any window is used up (the figures then read `limit` and the label
carries the reset time, as in `(pro, 5d)`), grey with no data. The label
and the figures always fit: a long email is shortened in the middle to make
room. A red row whose login no longer works says
"log in again" and starts a login for that account when clicked: the
terminal first asks you to sign into it in the browser; the live account's
expired token is not a dead login, its CLI refreshes it. Hovering a row
shows every window with what is left and when it resets. The widget
refreshes status while the panel is open and after each action, not while
it sits closed.

`build.sh` copies the widget into `~/.config/omarchy/plugins/kiba`. The
enable is needed once. After a QML change run `omarchy-restart-shell`: the
shell's plugin reload keeps the old compiled component in this Qt build.

## Build and test

`build.sh` compiles `src/kiba.f` with Habu's `tools/hb-build.f --repl` and
installs `~/.local/bin/kiba`. `test.sh` runs the checked test suite inside a
scratch `HOME` with fake `curl` and `codex` scripts on its PATH; it never reads
or writes real credentials. Set `HABU` to the Habu checkout to use (default
`~/Work/habu`).

## License

[MIT](LICENSE).
