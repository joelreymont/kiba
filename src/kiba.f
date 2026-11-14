\ kiba.f - entry point: argument dispatch and process exit.
require ../src/sw-cli.f
require ../src/sw-base.f
require ../src/sw-io.f
require src/lib/prelude.f
require src/lib/string.f

package SW

: USAGE ( -- )
   s\" usage: kiba status [--json]\n" ERR-TYPE
   s\"        kiba save [claude|codex]\n" ERR-TYPE
   s\"        kiba use <claude|codex> <email>\n" ERR-TYPE
   s\"        kiba add <claude|codex> [name]\n" ERR-TYPE
   s\"        kiba forget <claude|codex> <email>\n" ERR-TYPE
   s\"        kiba redeem <claude|codex> <email>\n" ERR-TYPE
   s\"        kiba usage [claude|codex]\n" ERR-TYPE ;

: ARG$ ( n -- ptr u8 n )
   dup SCRIPT-ARGC >= if drop E-SW-USAGE throw then
   SCRIPT-ARGV$ ;

: ARG-COUNT ( n -- )
   SCRIPT-ARGC <> if E-SW-USAGE throw then ;

\ the provider argument n; kiba-mac's command line refuses any other
: PROVIDER# ( n -- n )
   ARG$ {: a u :}
   a u s" claude" STR= if P-CLAUDE exit then
   a u s" codex" STR= if P-CODEX exit then
   E-SW-USAGE throw ;

\ the account name argument n, refused as kiba-mac refuses a bad SlotName
: NAME-ARG$ ( n -- ptr u8 n )
   ARG$ {: a u :}
   a u NAME-OK? 0= if E-SW-USAGE throw then
   a u ;

: DISPATCH-STATUS ( -- )
   SCRIPT-ARGC 1 = if false CMD-STATUS exit then
   2 ARG-COUNT
   1 ARG$ s" --json" STR= 0= if E-SW-USAGE throw then
   true CMD-STATUS ;

: DISPATCH-SAVE ( -- )
   SCRIPT-ARGC 1 = if -1 CMD-SAVE exit then
   2 ARG-COUNT
   1 PROVIDER# CMD-SAVE ;

: DISPATCH-USAGE ( -- )
   SCRIPT-ARGC 1 = if -1 CMD-USAGE exit then
   2 ARG-COUNT
   1 PROVIDER# CMD-USAGE ;

: DISPATCH-ADD ( -- )
   SCRIPT-ARGC 2 = if 1 PROVIDER# s" " CMD-ADD exit then
   3 ARG-COUNT
   1 PROVIDER# 2 NAME-ARG$ CMD-ADD ;

: DISPATCH ( -- )
   SCRIPT-ARGC 0= if E-SW-USAGE throw then
   0 ARG$ {: c cu :}
   c cu s" status" STR= if DISPATCH-STATUS exit then
   c cu s" save" STR= if DISPATCH-SAVE exit then
   c cu s" usage" STR= if DISPATCH-USAGE exit then
   c cu s" use" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-USE exit then
   c cu s" add" STR= if DISPATCH-ADD exit then
   c cu s" forget" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-FORGET exit then
   c cu s" redeem" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-REDEEM exit then
   E-SW-USAGE throw ;

: RUN ( -- )
   ALLOC-BUFFERS
   DISPATCH ;

public

: MAIN ( -- )
   [: RUN ;] catch {: rc :}
   rc 0= if s" " 0 die then
   rc E-SW-USAGE = if USAGE s" " 64 die then
   rc E-SW-REPORTED = if s" " 1 die then
   rc REASON$ ERR-LINE
   s" " 1 die ;

;package

: MAIN ( -- ) SW:MAIN ;
