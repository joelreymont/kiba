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
  - The store is kiba-mac's SQLite file without its history or its add
    record (`src/sw-db.f`),
    through kiba's own libsqlite3 binding over Habu's FFI
    (`src/sw-sqlite.f`).
  - Every command but `status` holds its provider's turn across network
    calls (`src/sw-turn.f`).
  - `usage` records kiba-mac's nine states and the limit-reset offer, and
    `redeem` spends a reset (`src/sw-usage.f`).
  - It builds on current Habu master. The turn, opening the store, its
    transactions, installs, the provider exchanges and `usage` are
    `FSM:DEFINE` machines; the status read and save-back are plain code.
  - The widget matches kiba-mac's app, and its bar icon is kiba-mac's gauge
    (`plugin/kiba/Gauge.qml`).
- **spark**: Ubuntu 24.04 on aarch64 with GNOME, used over ssh.
  - The widget cannot run there: it has no Hyprland and no Omarchy shell.
  - `claude` and `codex` are in `~/.local/bin`.
  - The auto-switch mod is in `~/Work/Dotfiles/.skills/claude/kiba` and
    calls the `kiba` in `~/.local/bin`.
  - Habu's `bin/hb` is built. There is no Swift toolchain, and SQLite has
    its runtime library but no headers.
  - libcurl 8.5.0 (`libcurl4t64`) is installed.
  - The store, the Mac's last snapshot, is at `~/.local/share/kiba/kiba.db`.

## Settled

- **Language**: the user's choice (2026-11-13). kiba stays a Habu Forth
  program, and kiba-mac's behaviour is ported into it. Habu first needs an
  SQLite binding, which it does not have. The Omarchy widget stays in QML
  and runs the CLI; Qt holds no account logic
  (`plugin/kiba/Status.qml:98-120`).
- **Store**: one SQLite file at `$XDG_DATA_HOME/kiba/kiba.db`, in
  kiba-mac's schema without its history or its add record; an older store
  loses them and is compacted on its next open. Linux's add never touches
  the live files, and the turn keeps installs from overlapping, so the
  store keeps no add record and no install claim. There is no folder
  layout and no converter.
- **History**: the user's choice (2026-11-13). kiba records no usage
  readings and no switches: nothing on Linux read them, and they were 95%
  of the store. Opening a store that holds kiba-mac's `history` table drops
  it and compacts the file.
- **CLI**: kiba-mac's contract, whose `status --json` the mod reads. On the
  spark the CLI is the only front end, so it also carries every account
  action the app has: `save`, `add` (which also logs a row in again),
  `forget` and `redeem`.
- **Logins on Linux**:
  - Claude keeps its credentials in a file, so there is no Keychain.
  - `add` runs the provider's login in the calling terminal, as kiba does
    today.
- **The copied store**: the user's choice (2026-11-13). There is no Mac
  any more. The spark's store, copied to neubau at the same path, is the
  Mac's last snapshot: its accounts stay. Saved logins are
  shared across machines; each one whose refresh is refused is logged in
  again on the Omarchy machine (`kiba add`), and the logins are then used
  everywhere.
- **Habu and state machines**: the user's choice (2026-11-13). kiba is
  brought up to current Habu master and its features, and rebuilt on Habu's
  state machine library: code whose outcomes cannot all be seen in one place
  is an `FSM:DEFINE` table, and one call's outcome, a loop over rows or a
  straight run of steps is plain code (the user's choice, 2026-11-13;
  AGENTS.md, Rules).
- **Widget**: the user's choice (2026-11-13). It is brought to parity with
  kiba-mac's app for machines that run Omarchy; on the spark the CLI is the
  only front end. It is to suit Linux, not copy the Mac (the user,
  2026-11-14), so where kiba-mac's behaviour comes from macOS it follows the
  Omarchy shell instead:
  - Tab and Shift-Tab switch panels, h/j/k/l move the cursor, Delete or x
    asks to forget, and Ctrl+L stands for ⌘L. Backspace does nothing: the
    Mac asks on ⌫ only because that is its delete key.
  - A right click on the bar icon refreshes usage, in place of the Mac's
    menu, as the shell's own panels give a right click a direct action.
  - The green and amber follow the theme's light or dark background.
  - The panel grows to the screen's height, as the shell fits it.
  - Add runs `kiba add` through `plugin/kiba/add.sh` in the terminal
    `xdg-terminal-exec` opens; `script(1)` keeps kiba's lines for the panel.
  - Quit, Start at login and the macOS accessibility settings have no
    counterpart.
- **Base64url**: the id_token payload is decoded with Habu's
  `BASE64:DECODE-URL` (AGENTS.md, Rules), which also refuses unused low bits
  that are not zero; kiba-mac's decoder accepts them. RFC 4648 section 3.5
  requires conforming encoders to write them as zero, so a conforming id_token
  decodes the same on both.
- **Not part of parity**: a `usage --json` report, finding the login shell's
  PATH (a CLI run from a shell already has it), and any daemon or
  background switcher. The mod already schedules and picks.
