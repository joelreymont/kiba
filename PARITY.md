# Parity with kiba-mac

The goal (AGENTS.md): kiba does on Linux everything kiba-mac does, and
kiba-mac's `DESIGN.md` is the contract. This file holds what exists and
what is settled. It does not restate kiba-mac's behaviour; `DESIGN.md`
holds that.

## What exists

- **kiba-mac** (`~/Work/kiba-mac`): Swift.
  - `KibaCore` holds the store, providers, probes and switching; with
    `KibaCLI` it is about 5,700 lines.
  - The `kiba` CLI has `status --json`, `usage` and `use`
    (`Sources/KibaCLI/main.swift:17`). The Claude Code auto-switch mod
    calls it (`~/Work/Dotfiles/.skills/claude/kiba/hooks/register.ts`).
  - The menu-bar app holds every other action.
  - The store is one SQLite file, schema 5 (`Sources/KibaCore/Store.swift:48`).
  - Platform-bound parts:
    - the Keychain (`SecretStore.swift`);
    - Terminal.app for logins (`LoginRunner.swift`);
    - `O_EXLOCK` and `F_FULLFSYNC` (`PrivateFS.swift`, `Switcher.swift`);
    - `CryptoKit` and `os`;
    - `URLSession` (`HTTP.swift`).
- **kiba** (this repository): a Habu Forth CLI (`src/`, about 4,700 lines)
  and the Omarchy widget (`plugin/kiba/`).
  - Commands: `status`, `save`, `usage`, `use`, `add`, `forget`, `redeem`
    (`src/kiba.f:46-52`).
  - The store is kiba-mac's SQLite file, history included (`src/sw-db.f`),
    through kiba's own libsqlite3 binding over Habu's FFI
    (`src/sw-sqlite.f`).
  - Every command but `status` holds its provider's turn across network
    calls (`src/sw-turn.f`).
  - `usage` records kiba-mac's nine states and the limit-reset offer, and
    `redeem` spends a reset (`src/sw-usage.f`).
  - It builds on current Habu master. The turn, the store's transactions,
    the status read, installs, save-back, probes and `usage` are
    `FSM:DEFINE` machines.
  - Missing against kiba-mac, all in the widget:
    - model-only limits that leave the account usable (`plugin/kiba/Panel.qml:155`);
    - the `status --json` shape the CLI now prints: the widget still reads
      the old one (`plugin/kiba/Status.qml`);
    - Log In Again;
    - queued row actions.
- **spark**: Ubuntu 24.04 on aarch64 with GNOME, used over ssh.
  - The widget cannot run there: it has no Hyprland and no Omarchy shell.
  - `claude` and `codex` are in `~/.local/bin`.
  - The auto-switch mod is in `~/Work/Dotfiles/.skills/claude/kiba` and
    calls the `kiba` in `~/.local/bin`.
  - Habu's `bin/hb` is built. There is no Swift toolchain, and SQLite has
    its runtime library but no headers.
  - A snapshot of the Mac's store is at `~/.local/share/kiba/kiba.db`.

## Settled

- **Language**: the user's choice (2026-11-13). kiba stays a Habu Forth
  program, and kiba-mac's behaviour is ported into it. Habu first needs an
  SQLite binding, which it does not have. The Omarchy widget stays in QML
  and runs the CLI; Qt holds no account logic
  (`plugin/kiba/Status.qml:98-120`).
- **Store**: one SQLite file at `$XDG_DATA_HOME/kiba/kiba.db`, in
  kiba-mac's schema. There is no folder layout and no converter.
- **CLI**: kiba-mac's contract, whose `status --json` the mod reads. On the
  spark the CLI is the only front end, so it also carries every account
  action the app has: `save`, `add` (which also logs a row in again),
  `forget` and `redeem`.
- **Logins on Linux**:
  - Claude keeps its credentials in a file, so there is no Keychain.
  - `add` runs the provider's login in the calling terminal, as kiba does
    today.
- **The copied store**: the final copy is taken once kiba-mac, Claude and
  Codex on the Mac have quit. It keeps its accounts and history and loses
  its Mac-only install records (`live`, `pending`, `adding`). The Mac's
  store is untouched.
  - Whether its saved logins survive the move is proven once, the user's
    choice (2026-11-13): on the spark, one saved account that is not the
    live login is refreshed once, and its new tokens are saved into its row.
  - A 200 keeps the copied logins. A 400 or 401 means a login refreshed on
    one machine dies on the other (both CLIs and kiba's probes rotate
    tokens, README, Save-back): the copy then loses its saved logins, and
    each account is logged in again on the spark.
- **Habu and state machines**: the user's choice (2026-11-13). kiba is
  brought up to current Habu master and its features, and rebuilt on Habu's
  state machine library: every state kiba handles is an `FSM:DEFINE` table
  (AGENTS.md, Rules).
- **Widget**: the user's choice (2026-11-13). It is brought to parity with
  kiba-mac's app for machines that run Omarchy; on the spark the CLI is the
  only front end.
- **Not part of parity**: a `usage --json` report, finding the login shell's
  PATH (a CLI run from a shell already has it), and any history command,
  daemon or background switcher. The mod already schedules and picks.
