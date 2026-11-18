# kiba — AI account switcher for Omarchy

kiba swaps the live Claude Code and Codex CLI logins between saved accounts
and reports how much of each saved account's allowance is left. The CLI is a
checked Habu program; a thin Omarchy bar widget runs it.

## Goal

- kiba does on Linux everything kiba-mac does (`~/Work/kiba-mac`, whose
  `DESIGN.md` is its contract), suited to Linux rather than copied from the
  Mac: where kiba-mac's behaviour comes from macOS, the widget follows the
  Omarchy shell (the user, 2026-11-14).
- Unlike kiba-mac, the widget holds no click for later: while a command
  runs, a usage probe included, every control that would start another,
  account rows and their badges included, is disabled and looks it (the
  user, 2026-11-15).
- Unlike kiba-mac, opening the panel probes no usage: it reads the status
  alone, and usage is probed only when asked, per provider from the
  refresh arrow before its "+" or for every provider from "Refresh usage"
  and a right click on the bar icon (the user, 2026-11-15).
- Since usage is probed only when asked, a reading more than an hour old
  is marked as old: its row dims the reading and shows its age, and the bar
  icon shows that provider's usage as unknown (the user, 2026-11-18).
- Unlike kiba-mac, a row's hover says when the earliest of its counted
  limit resets expires, so none is lost: Claude's next grant's `ends_at`,
  Codex's earliest available credit's `expires_at` from its credit list,
  asked only while the count is above 0 (the user, 2026-11-18).
- Out of scope: a `usage --json` report, finding the login shell's `PATH`
  (a CLI run from a shell already has it), and any daemon or background
  switcher; the auto-switch mod schedules and picks.

## Habu code

- Read [Habu's Forth card](https://github.com/joelreymont/habu/blob/master/docs/forth-card.md)
  before writing or changing any `.f` file, and open the section of
  [forth.md](https://github.com/joelreymont/habu/blob/master/docs/forth.md)
  it points to when a rule needs detail. Its naming, package, factoring,
  stack-comment, and checker rules apply here unchanged.
- All Forth lives in `package SW`, split one concern per file under `src/`:
  `sw-base.f` errors and byte helpers, `sw-paths.f` file locations, `sw-io.f`
  buffers, the JSON writer, private writes and stdout writes, `sw-json.f`
  field access over in-memory JSON, `sw-identity.f` who a login belongs to,
  `sw-claude.f` and `sw-codex.f` the live files per provider, `sw-sqlite.f`
  the SQLite binding, `sw-db.f` the account store, `sw-turn.f` the
  per-provider turn, `sw-store.f` saving, installing and forgetting through
  the store, `sw-status.f` the status read, `sw-run.f` provider commands in
  the foreground, `sw-usage.f` usage probes and limit resets through Habu's
  `CURL` (libcurl), `sw-cli.f` the commands, `kiba.f` the entry and `MAIN`.
- Library words come from the installed [Habu](https://github.com/joelreymont/habu),
  the one `hb` on `PATH` resolves to. `build.sh` and `test.sh` run its
  `bin/hb` from its root, so relative `require src/lib/...` resolves there. To
  build with another Habu, put its `bin/hb` first on `PATH`.
- Errors are named `E-SW-*` constants in `src/sw-base.f`; fallible words throw
  them. `MAIN` maps them to one-line reasons; `status` and `usage` catch per
  provider or per account so one bad file never hides the others.
- Every identity read names the record it fills: `ID-LIVE` is the login the
  provider is running, `ID-SLOT` the saved login under examination, so
  reading a saved login never disturbs the live one and nothing is copied
  aside.
- Every command but `status` opens the store itself and holds its
  provider's turn (`STORE-TURN`) from start to end, network calls included;
  each store write is one `DB-WRITE` transaction.

## Layout

- `src/` checked Habu sources; `test/sw-unit-test.f` the checked test suite.
  It answers kiba's requests from an HTTP server in the test process and
  writes fake `claude` and `codex` scripts into the scratch PATH;
  `KIBA_TEST_LOG` collects what each request carried and what the scripts
  were called with.
- `plugin/kiba/` Omarchy bar widget (QML). It only runs the CLI and
  renders `kiba status --json`; no account logic lives in QML.
- `build.sh` builds the native binary with `tools/hb-build.f --repl`,
  installs it to `~/.local/bin/kiba`, and copies the widget into
  `~/.config/omarchy/plugins/kiba`. QML edits show up only after
  `omarchy-restart-shell`; verify with a `grim` screenshot of the bar.

## Verify

- Tests: `./test.sh` runs the suite inside a scratch `HOME` with an empty
  environment; it never touches real credentials.
- Widget: `omarchy plugin validate plugin/kiba`, then
  `omarchy-shell kiba open` and check `journalctl --user` for QML
  errors.
- Read-only checks against the real store are fine (`kiba status`,
  `kiba status --json`). Do not run `use`, `add`, `save`, `forget`, or
  `usage` against the real HOME while testing, and never call a provider
  endpoint with a real token by hand: a refresh rotates the token.

## Rules

- kiba builds with the current Habu, the installed one, and never pins a
  Habu revision in scripts, tests or docs. It uses Habu's libraries for what
  they provide; a kiba word that a Habu library now covers gives way to it.
- Code whose outcomes cannot all be seen in one place is an `FSM:DEFINE`
  table from Habu's `src/lib/fsm.f` (`docs/forth.md`, "State machines"):
  steps that repeat or retry, phases, a half-done change to undo, an
  exchange with a provider. One call whose outcome picks one action, a loop
  over rows, or a run of steps that each go on or stop is plain code.
- Never run `codex logout` or `claude auth logout` from code or tests: both
  revoke tokens server-side and kill every saved copy of that account.
  `codex login` revokes the existing login too, so `add` runs every login
  inside a throwaway home (`LOGIN-ROOT!`) and never touches the live files.
- Never refresh the live account's token, and never probe a saved account
  through `codex app-server` in a copied home: both rotate tokens the running
  CLI still holds.
- Spawn interactive provider commands with fork plus `execve` (see
  `RUN-STAGED`), never the `spawn-*` primitives: those give the child its own
  process group and a terminal read then stops it with SIGTTIN.
- Credential files and account directories are written `0600`/`0700` and
  replaced atomically.
- kiba keeps no history: the store holds saved logins and the live and
  in-flight markers, nothing that grows with each probe or switch.
- Every request names its client: `KIBA-UA$`, except the usage, reset
  and reset-credit-list calls, where the ChatGPT ones keep `codex-cli` and
  the Claude ones carry Claude Code's `claude-cli/<version>`
  (`CLAUDE-UA$`), which alone opens the limit-reset surface. Anthropic's
  token endpoint answers 429 to curl's own User-Agent whatever the grant.
  Only a 400 or 401 from a token endpoint means a saved login is gone; any
  other answer is an `error` state, never `expired`.
