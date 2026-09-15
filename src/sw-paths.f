\ sw-paths.f - home, store, and provider file locations.
require ../src/sw-base.f
require lib/fs.f
require lib/fs-mutate.f

package SW

create STORE-BUF FS-PATH-CAP allot   variable STORE-U
create PDIR-BUF FS-PATH-CAP allot    variable PDIR-U
create SLOT-BUF FS-PATH-CAP allot    variable SLOT-U
create SFILE-BUF FS-PATH-CAP allot   variable SFILE-U
create LIVE-BUF FS-PATH-CAP allot    variable LIVE-U
create CONFIG-BUF FS-PATH-CAP allot  variable CONFIG-U
create LOCK-BUF FS-PATH-CAP allot    variable LOCK-U

public

: HOME$ ( -- ptr u8 n )
   s" HOME" GETENV dup 0= if E-SW-ENV throw then ;

: STORE$ ( -- ptr u8 n )
   STORE-U @ 0 > if STORE-BUF STORE-U @ exit then
   SB-RESET
   s" XDG_DATA_HOME" GETENV dup 0 > if SB-APPEND else 2drop HOME$ SB-APPEND s" /.local/share" SB-APPEND then
   s" /switcher" SB-APPEND
   SB$ STORE-BUF STORE-U PATH!
   STORE-BUF STORE-U @ ;

: LOCK$ ( -- ptr u8 n )
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /lock" SB-APPEND
   SB$ LOCK-BUF LOCK-U PATH!
   LOCK-BUF LOCK-U @ ;

: PROVIDER-DIR$ ( n -- ptr u8 n ) {: p :}
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND SLASH SB-APPEND-C p PROVIDER$ SB-APPEND
   SB$ PDIR-BUF PDIR-U PATH!
   PDIR-BUF PDIR-U @ ;

: SLOT-DIR$ ( n ptr u8 n -- ptr u8 n ) {: p a u :}
   a u CHECK-NAME
   p PROVIDER-DIR$ {: d du :}
   SB-RESET d du SB-APPEND SLASH SB-APPEND-C a u SB-APPEND
   SB$ SLOT-BUF SLOT-U PATH!
   SLOT-BUF SLOT-U @ ;

: SLOT-FILE$ ( n ptr u8 n ptr u8 n -- ptr u8 n ) {: p a u f fu :}
   p a u SLOT-DIR$ {: d du :}
   SB-RESET d du SB-APPEND SLASH SB-APPEND-C f fu SB-APPEND
   SB$ SFILE-BUF SFILE-U PATH!
   SFILE-BUF SFILE-U @ ;

\ the Claude config directory: CLAUDE_CONFIG_DIR when set, else ~/.claude
: CLAUDE-DIR>SB ( -- bool )
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

: CODEX-AUTH$ ( -- ptr u8 n )
   SB-RESET
   s" CODEX_HOME" GETENV dup 0 > if SB-APPEND else 2drop HOME$ SB-APPEND s" /.codex" SB-APPEND then
   s" /auth.json" SB-APPEND
   SB$ LIVE-BUF LIVE-U PATH!
   LIVE-BUF LIVE-U @ ;

;package
