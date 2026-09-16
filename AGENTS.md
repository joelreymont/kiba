# kiba — AI account switcher for Omarchy

kiba swaps the live Claude Code and Codex CLI logins between saved accounts
and reports how much of each saved account's allowance is left. The CLI is a
checked Habu program; a thin Omarchy bar widget runs it.

## Habu code

- Read [Habu's Forth conventions](https://github.com/joelreymont/habu/blob/master/docs/forth.md)
  before writing or changing any `.f` file. Its naming, package, factoring,
  stack-comment, and checker rules apply here unchanged.
- All Forth lives in `package SW`, split one concern per file under `src/`:
  `sw-base.f` errors and byte helpers, `sw-paths.f` file locations, `sw-io.f`
  buffers, private writes, lock and install marker, `sw-json.f` field access
  over in-memory JSON, `sw-identity.f` who a login belongs to, `sw-claude.f`
  and `sw-codex.f` save and install per provider, `sw-store.f` slot naming
  and listing, `sw-run.f` provider commands in the foreground, `sw-usage.f`
  usage probes through `curl`, `sw-cli.f` the commands, `kiba.f` the entry
  and `MAIN`.
- Library words come from a checkout of [Habu](https://github.com/joelreymont/habu)
  named by `HABU` (default `~/Work/habu`). `build.sh` and `test.sh` run
  `bin/hb` from that checkout, so relative `require lib/...` resolves there.
- Errors are named `E-SW-*` constants in `src/sw-base.f`; fallible words throw
  them. `MAIN` maps them to one-line reasons; `status` and `usage` catch per
  provider or per account so one bad file never hides the others.
- The store lock is re-entrant within a process and records its owner's pid;
  network calls in `sw-usage.f` run outside it and every slot write takes it
  through a `WITH-LOCK` quotation that reads its account from module cells.

## Layout

- `src/` checked Habu sources; `test/sw-unit-test.f` the checked test suite,
  which writes fake `curl` and `codex` scripts into the scratch PATH
  (`KIBA_TEST_LOG` collects what they were called with).
- `plugin/kiba/` Omarchy bar widget (QML). It only runs the CLI and
  renders `kiba status --json`; no account logic lives in QML.
- `build.sh` builds the native binary with `tools/hb-build.f --repl`,
  installs it to `~/.local/bin/kiba`, and copies the widget into
  `~/.config/omarchy/plugins/kiba`. QML edits show up only after
  `omarchy-restart-shell`; verify with a `grim` screenshot of the bar.

## Verify

- Tests: `HABU=<checkout> ./test.sh` runs the suite inside a scratch `HOME`;
  it never touches real credentials.
- Widget: `omarchy plugin validate plugin/kiba`, then
  `omarchy-shell kiba open` and check `journalctl --user` for QML
  errors.
- Read-only checks against the real store are fine (`kiba status`,
  `kiba status --json`). Do not run `use`, `add`, `save`, `forget`, or
  `usage` against the real HOME while testing, and never call a provider
  endpoint with a real token by hand: a refresh rotates the token.

## Rules

- Never run `codex logout` or `claude auth logout` from code or tests: both
  revoke tokens server-side and kill every saved copy of that account.
  `codex login` revokes the existing login too, so `add` runs every login
  inside a throwaway home (`LOGIN-ROOT!`) and never touches the live files.
- Never refresh the live account's token, and never probe a saved account
  through `codex app-server` in a copied home: both rotate tokens the running
  CLI still holds.
- Spawn interactive provider commands with fork plus `execve` (see
  `RUN-INHERIT`), never the `spawn-*` primitives: those give the child its own
  process group and a terminal read then stops it with SIGTTIN.
- Credential files and account directories are written `0600`/`0700` and
  replaced atomically.
- VCS is `jj`. One commit per feature or fix.
