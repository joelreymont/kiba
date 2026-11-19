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

- Omarchy 4 (the bar widget is an Omarchy shell plugin), libcurl (the
  `curl` package on Arch, `libcurl4t64` on Ubuntu), and the `claude` and
  `codex` CLIs you already use.
- [Habu](https://github.com/joelreymont/habu), the checked Forth the CLI is
  written in, installed so that `hb` is on `PATH`; see [AGENTS.md](AGENTS.md).

## Install

```sh
./build.sh                                            # builds and installs ~/.local/bin/kiba and the widget
omarchy plugin enable kiba --section right --before omarchy.agents
kiba save                                             # keep the logins you have now
```

To add another account, sign into it at claude.ai or chatgpt.com in your
browser, then use the "+" beside the provider in the widget or run
`kiba add claude` / `kiba add codex`. The terminal first reminds you to sign into the account in
the browser and waits for Enter, because the provider's login page authorizes
whichever account the browser is signed into; kiba saves what comes back
under that account's name and, when you named an account, tells you if a
different one came back.
Adding never touches the live login; switch with `use` or a click. Never run
the providers' logout commands: both revoke the tokens server-side and the
saved copy dies with them.

## Commands

```
kiba status [--json]           live account, saved accounts, and their usage
kiba save [claude|codex]       save the live login(s) under their account names
kiba use <provider> <name>     save back the live login, install <name>
kiba next <provider>           save back the live login, install another account with room
kiba add <provider> [name]     log in to a new (or the named) account, save it
kiba forget <provider> <name>
kiba usage [claude|codex]      probe the rate limits of every saved account
kiba redeem <provider> <name>  spend one of <name>'s limit resets
```

`<name>` is the account's email, or `email #2`, `email #3` for further
logins under the same email. Exit codes: 0 ok, 64 usage, 1 any other failure
with a one-line reason on stderr; `usage` exits 1 once every provider has
run when any of them reported an error. `use` probes the account it
installed and the one it saved back, `next` every account it tried and the
one it saved back, `add` the account it saved, and `redeem` the account it
reset, so the widget shows their figures at once.

`next` tries every saved account but the live one and those whose login is
gone, grouped by their last reading: those with room first, then those with
little room, then the rest, in name order within each group. It probes each
in turn and installs the first whose fresh reading has room, probing each
account at most once. When none has room it exits 1 and the live login is
left as it was.

`status --json` is the snapshot the Claude Code auto-switch mod reads:

```json
{"providers":[{"provider":"claude","live":{"email":"a@x","plan":"max"},"installedAt":1789480000,
  "accounts":[{"name":"a@x","plan":"max","active":true,
    "usage":{"fetchedAt":1789480000,"state":"ok","note":"",
      "limits":[{"label":"Session (5-hour)","percent":56,"left":44,"resetsAt":"2026-09-15T14:00:00Z"}],
      "resets":{"count":2,"expiresAt":"2026-11-24T14:00:00Z","grant":"g-1","program":"cedar_ember"}}}]}, ...]}
```

A provider whose files cannot be read carries an `"error"` string and keeps
its `accounts` list, so the other provider and every saved login stay
usable. `usage` is absent until the account has been probed; `percent` is
the whole number used, `-1` for a window without a reading; `resets` is
absent when the provider said nothing about limit resets, and its
`expiresAt` is when the earliest of the counted resets expires, absent when
the provider names no date. `state` is one of:

| state | meaning |
|-------|---------|
| `ok` | the figures are current |
| `expired` | the token has expired and cannot be renewed now |
| `revoked` | the provider revoked the login; log in again |
| `error` | the check failed; `note` says why, the login is kept |
| `unknown` | never probed, or the stored record is unreadable |
| `unsubscribed` | the login works, but its organization has no plan the CLI may use |
| `throttled` | the provider is rate limiting this login's usage checks |
| `missing` | the saved login holds no token to check or renew with |
| `free` | the organization is on the free plan: no usage to read |

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
  ChatGPT workspace) get separate names in the order they are added: the first
  keeps the bare email, the next are `email #2`, `email #3`. A login is matched
  to its name by organization, never by position.
- **Store**: one SQLite file, `$XDG_DATA_HOME/kiba/kiba.db` (default
  `~/.local/share/kiba`), holding each saved login and the live install
  records and nothing more: kiba records no usage readings or switches, and
  its add never touches the live files, so it keeps no add record. Its
  directory is `0700`; every write is a transaction. A store from a newer kiba
  is refused; an older one loses its history and add record and is compacted
  on its next open.
- **Turns**: every command but `status` holds its provider's turn, a lock
  shared by every kiba process, from start to end, network calls included.
  Waiters take it in the order they arrived and give up after two minutes;
  Claude and Codex commands run side by side.
- **Save-back**: both CLIs rotate tokens while they run, so before installing
  another account `use` first saves the currently live login into its own row.
  A saved copy is therefore never staler than the last switch away from it.
  The Claude install writes two files, so it records a pending install in
  the store before the first and clears it after the second; until a later
  `use` completes an interrupted one, nothing is probed or refreshed. kiba
  also records which login it installed last: if `.claude.json` later names
  another account while the credentials are still byte-for-byte that
  login's, the pair is mixed, save-back leaves it alone, and `save` says so.
- **Live files that are symlinks** stay symlinks on `use` and `save`: the
  write replaces the file the link points at.
- **Login runs in the foreground, in a throwaway home**: `add` forks and
  execs the provider's login with `CLAUDE_CONFIG_DIR` or `CODEX_HOME`
  pointing at the private directory `<store>/login-<provider>`, so the
  login never sees the live login: nothing is read, revoked (`codex login`
  revokes whatever login it finds), or replaced while your sessions are
  working. The new login is read from that directory and saved under its
  name, the directory is removed, and the new account is probed. The child
  stays in the terminal's process group; a child in its own group is stopped
  by SIGTTIN the moment it reads the terminal.

## Usage per account

`kiba usage` answers "which account still has room". For every saved account
it asks the provider's own usage endpoint with that account's saved token,
through libcurl, and records the answer and any refreshed tokens in one
transaction:

- Claude: `GET https://api.anthropic.com/api/oauth/usage` with the OAuth
  access token. Windows: `Session (5-hour)`, `Weekly (7-day)`, and every
  model-scoped window the payload lists, named after the model, such as
  `Fable Weekly`, plus the limit resets the account may spend.
- Codex: `GET https://chatgpt.com/backend-api/wham/usage` with the access
  token and account id. Windows are named from their length: five hours is
  the session, seven days the week.

A reset's expiry comes from Claude's next banked grant (its `ends_at`) and,
for Codex, from `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`,
asked only while the account holds a reset: the earliest `expires_at` among
the credits still available. A failed list call leaves the date unknown and
the probe's figures as they are.

A saved (non-live) account is refreshed once through the provider's token
endpoint when its token has expired (Claude) or is rejected (Codex), and the
new tokens replace the saved ones. The live account is never refreshed by
kiba: its CLI owns that token, and rotating it underneath a running session
would log the session out, so an expired live token is reported as
`expired` and not sent. Only a 400 or 401 from a token endpoint means a
saved login is gone; a revoked login keeps its row, marked `revoked`, until
you forget it. Any other failure is recorded as that account's `state` and
`note` and the run continues with the next account. When every saved
account was probed after the run began, because another kiba probed them
while this one waited for the turn, those results are reported and nothing
is probed again.

Requests are made in kiba's own process through libcurl, so a token reaches
no argv, file or other process. No configuration file applies to them; the
proxy environment variables (`https_proxy`, `all_proxy`, `no_proxy`) do, as
libcurl reads them. Requests name `kiba` as their User-Agent, except the
usage and reset calls and Codex's reset-credit list: the ChatGPT ones keep
`codex-cli`, and the Claude ones carry Claude Code's `claude-cli/<version>`,
which alone opens the limit-reset offer. Anthropic's token endpoint answers
429 to curl's own User-Agent, whatever the grant.

`kiba redeem <provider> <name>` spends one limit reset the account's last
probe offered, then probes it again. A saved login's token is refreshed
first when it has expired or is rejected; the live login's never is.

## Bar widget

`plugin/kiba` renders `kiba status --json` and only ever runs the CLI:
an account row runs `use`, "Save the current login" runs `save`, a
provider's "+" opens a terminal running `add` (the login needs a browser
and a prompt), the refresh arrow beside it runs `usage` for that provider,
and "Refresh usage", or a right click on the bar icon, runs `usage` for
every provider. The widget stays busy until the add's terminal closes, then says
which account was added. In the panel, the arrows or h/j/k/l move the
cursor, Return or Space acts on it, Delete or x asks to forget the row,
Ctrl+L logs it in again, Tab and Shift-Tab switch panels, and Esc backs out. Opening the panel reads the saved status and
probes nothing; usage is probed only when you ask, and the rows update once
the probe ends. While any command runs, a probe included, the account rows,
their badges and every button that would start another command are dimmed
and ignore clicks and keys; Dismiss and a confirmation's Keep stay live.

Rows come with room to spare first, then running low, then a model window
used up, then the session used up, then the week, then dead logins and
accounts without a plan, then rows with no data. Limited rows come in the
order their limits reset, soonest first; other ties keep the CLI's order.
Each row carries a dot and what is left of the session, the week, and each
model window, as percentages in that order (the hover text names them),
amber below half. The dot is green while the account can take work, a used
up model window included; red when its session or week is used up (the
figures then read `limit` and the label carries the reset time, as in
`(pro, 5d)`), its login is dead, or it has no plan; grey with no data. A
reading more than an hour old is marked as old: its dot, figures and bars
are drawn faint, its age, as in `2d ago`, ends the bars, and the bar icon draws the live account's old reading as unknown, an empty
outline; rows still sort by it. The figures always fit; the email and the label share the rest, each shortened
in the middle, so a long plan such as Codex's `self_serve_business_prolite`
never hides the email. A red row whose login no longer works says
"log in again" and starts a login for that account when clicked, and so
does the red "!" badge it carries: the terminal first asks you to sign
into it in the browser; the live account's expired token is not a dead
login, its CLI refreshes it. A row's right-click menu offers Forget. Hovering a row
shows every window with what is left and when it resets, and, when the
account holds limit resets, the date the earliest of them expires, as in
`2 limit resets available · first expires Nov 24 at 14:00`; the reset
badge's hover says the same. The widget
refreshes status while the panel is open and after each action, not while
it sits closed.

`build.sh` copies the widget into `~/.config/omarchy/plugins/kiba`. The
enable is needed once. After a QML change run `omarchy-restart-shell`: the
shell's plugin reload keeps the old compiled component in this Qt build.

## Build and test

`build.sh` compiles `src/kiba.f` with Habu's `tools/hb-build.f --repl` and
installs `~/.local/bin/kiba`. `test.sh` runs the checked test suite inside a
scratch `HOME` with an empty environment: an HTTP server in the test process
answers kiba's requests, and fake `claude` and `codex` scripts are on its
PATH. It never reads or writes real credentials. Both use the installed Habu that `hb` on `PATH`
resolves to; to build with another Habu, put its `bin/hb` first on `PATH`.

## License

[MIT](LICENSE).
