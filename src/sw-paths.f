\ sw-paths.f - home, store, and provider file locations.
require ../src/sw-base.f
require src/lib/fs.f
require src/lib/fs-mutate.f

package SW

create STORE-BUF PATH-CAP allot   variable STORE-U
create DBFILE-BUF PATH-CAP allot  variable DBFILE-U
create LIVE-BUF PATH-CAP allot    variable LIVE-U
create CONFIG-BUF PATH-CAP allot  variable CONFIG-U
create LROOT-BUF PATH-CAP allot   variable LROOT-U     \ a throwaway home; empty means the real one
create LDIR-BUF PATH-CAP allot    variable LDIR-U

public

: HOME$ ( -- ptr u8 n )
   s" HOME" GETENV dup 0= if E-SW-ENV throw then ;

: STORE$ ( -- ptr u8 n )
   STORE-U @ 0 > if STORE-BUF STORE-U @ exit then
   SB-RESET
   s" XDG_DATA_HOME" GETENV dup 0 > if SB-APPEND else 2drop HOME$ SB-APPEND s" /.local/share" SB-APPEND then
   s" /kiba" SB-APPEND
   SB$ STORE-BUF STORE-U PATH!
   STORE-BUF STORE-U @ ;

\ the account store's SQLite database
: DB-PATH$ ( -- ptr u8 n )
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /kiba.db" SB-APPEND
   SB$ DBFILE-BUF DBFILE-U PATH!
   DBFILE-BUF DBFILE-U @ ;

\ ---- a throwaway home -------------------------------------------------------
\ `add` runs the provider login inside a private home of its own, so the
\ live login is neither read, revoked, nor replaced by it. While the root is
\ set, the provider file words below read from that home instead.
: LOGIN-ROOT! ( ptr u8 n -- ) LROOT-BUF LROOT-U PATH! ;
: LOGIN-ROOT-CLEAR ( -- ) 0 LROOT-U ! ;
: LOGIN-ROOT? ( -- bool ) LROOT-U @ 0 > ;
: LOGIN-ROOT$ ( -- ptr u8 n ) LROOT-BUF LROOT-U @ ;

\ the provider directory inside the throwaway home, as its env var names it
: LOGIN-DIR$ ( n -- ptr u8 n ) {: p :}
   SB-RESET LOGIN-ROOT$ SB-APPEND
   p P-CLAUDE = if s" /.claude" else s" /.codex" then SB-APPEND
   SB$ LDIR-BUF LDIR-U PATH!
   LDIR-BUF LDIR-U @ ;

\ the Claude config directory: the throwaway home's, else CLAUDE_CONFIG_DIR
\ when set, else ~/.claude; true when .claude.json lives inside it
: CLAUDE-DIR>SB ( -- bool )
   LOGIN-ROOT? if LOGIN-ROOT$ SB-APPEND s" /.claude" SB-APPEND true exit then
   s" CLAUDE_CONFIG_DIR" GETENV dup 0 > if SB-APPEND true exit then
   2drop HOME$ SB-APPEND s" /.claude" SB-APPEND false ;

: CLAUDE-CREDS$ ( -- ptr u8 n )
   SB-RESET CLAUDE-DIR>SB drop s" /.credentials.json" SB-APPEND
   SB$ LIVE-BUF LIVE-U PATH!
   LIVE-BUF LIVE-U @ ;

\ .claude.json sits inside an explicit config dir, otherwise directly in HOME
: CLAUDE-CONFIG$ ( -- ptr u8 n )
   SB-RESET CLAUDE-DIR>SB 0= if SB-RESET HOME$ SB-APPEND then
   s" /.claude.json" SB-APPEND
   SB$ CONFIG-BUF CONFIG-U PATH!
   CONFIG-BUF CONFIG-U @ ;

: CODEX-DIR>SB ( -- )
   LOGIN-ROOT? if LOGIN-ROOT$ SB-APPEND s" /.codex" SB-APPEND exit then
   s" CODEX_HOME" GETENV dup 0 > if SB-APPEND exit then
   2drop HOME$ SB-APPEND s" /.codex" SB-APPEND ;

: CODEX-AUTH$ ( -- ptr u8 n )
   SB-RESET CODEX-DIR>SB
   s" /auth.json" SB-APPEND
   SB$ LIVE-BUF LIVE-U PATH!
   LIVE-BUF LIVE-U @ ;

;package
