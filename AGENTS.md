# switcher — AI account switcher for Omarchy

`switcher` swaps the live Claude Code and Codex CLI logins between saved
accounts. The CLI is a checked Habu program; a thin Omarchy bar widget runs it.

## Habu code

- Read [~/Work/habu/docs/forth.md](../habu/docs/forth.md) before writing or
  changing any `.f` file. Its naming, package, factoring, stack-comment, and
  checker rules apply here unchanged.
- All Forth lives in `package SW`, split one concern per file under `src/`.
  `src/switcher.f` is the entry and owns `MAIN`. `src/sw-usage.f` probes
  saved accounts through the providers' usage endpoints with `curl`; the
  fake `curl` and provider commands used by the tests are written by
  `test/sw-unit-test.f` into the scratch PATH.
- Library words come from the Habu checkout named by `HABU` (default
  `~/Work/habu`). `build.sh` and the test commands run `bin/hb` from that
  checkout, so relative `require lib/...` resolves there.
- Errors are named `E-SW-*` constants in `src/sw-base.f`; fallible words throw
  them. Only `MAIN` catches, prints, and exits.

## Layout

- `src/` checked Habu sources; `test/` checked Habu tests.
- `plugin/joel.switcher/` Omarchy bar widget (QML). It only runs the CLI and
  renders `switcher status --json`; no account logic lives in QML.
- `build.sh` builds the native binary with `tools/hb-build.f --repl`,
  installs it to `~/.local/bin/switcher`, and copies the widget into
  `~/.config/omarchy/plugins/joel.switcher`. QML edits show up only after
  `omarchy-restart-shell`; verify with a `grim` screenshot of the bar.

## Verify

- Tests: `HABU=<checkout> ./test.sh` runs `test/sw-unit-test.f` (unit words
  plus the full save/use/forget flow) inside a scratch `HOME`; it never
  touches real credentials.
- Widget: `omarchy plugin validate plugin/joel.switcher`, then
  `omarchy-shell joel.switcher open` and check `journalctl --user` for QML
  errors.

## Rules

- Never run `codex logout` or `claude auth logout` from code or tests: both
  revoke tokens server-side and kill every saved copy of that account.
  `codex login` revokes the existing login too, so `add` moves the live file
  aside before running it.
- Never run a provider's token refresh for the live account, and never probe
  a saved account through `codex app-server` in a copied home: both rotate
  tokens the running CLI still holds.
- Spawn interactive provider commands with fork plus `execve` (see
  `RUN-INHERIT`), never the `spawn-*` primitives: those give the child its own
  process group and a terminal read then stops it with SIGTTIN.
- Credential files and account directories are written `0600`/`0700` and
  replaced atomically.
- VCS is `jj`. One commit per feature or fix.
