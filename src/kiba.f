split-str
\ kiba.f - entry point: argument dispatch and process exit.
require ../src/sw-cli.f
require ../src/sw-base.f
require ../src/sw-io.f
require src/lib/prelude.f
require src/lib/string.f
require src/lib/fd.f

package SW

: USAGE ( -- )
   s\" usage: kiba status [--json]\n" ERR-PART
   s\"        kiba save [claude|codex]\n" ERR-PART
   s\"        kiba use <claude|codex> <email>\n" ERR-PART
   s\"        kiba next <claude|codex>\n" ERR-PART
   s\"        kiba add <claude|codex> [name]\n" ERR-PART
   s\"        kiba forget <claude|codex> <email>\n" ERR-PART
   s\"        kiba redeem <claude|codex> <email>\n" ERR-PART
   s\"        kiba usage [claude|codex]\n" ERR-PART ;

: ARG$ ( n -- ^u8 n )
   dup SCRIPT-ARGC >= if drop E-SW-USAGE throw then
   SCRIPT-ARGV$ ;

: ARG-COUNT ( n -- )
   SCRIPT-ARGC <> if E-SW-USAGE throw then ;

\ the provider argument n: claude or codex, any other refused
: PROVIDER# ( n -- n )
   ARG$ {: a u :}
   a u s" claude" STR= if P-CLAUDE exit then
   a u s" codex" STR= if P-CODEX exit then
   E-SW-USAGE throw ;

\ the account name argument n, refused unless NAME-OK? takes it
: NAME-ARG$ ( n -- ^u8 n )
   ARG$ {: a u :}
   a u NAME-OK? 0= if E-SW-USAGE throw then
   a u ;

: DISPATCH-STATUS ( -- )
   SCRIPT-ARGC 1 = if false CMD-STATUS exit then
   2 ARG-COUNT
   1 ARG$ s" --json" STR= 0= if E-SW-USAGE throw then
   true CMD-STATUS ;

: DISPATCH-PROVIDERS ( [ n -- ] -- )
   {: cmd :}
   SCRIPT-ARGC 1 = if -1 cmd execute exit then
   2 ARG-COUNT
   1 PROVIDER# cmd execute ;

: DISPATCH-ADD ( -- )
   SCRIPT-ARGC 2 = if 1 PROVIDER# s" " CMD-ADD exit then
   3 ARG-COUNT
   1 PROVIDER# 2 NAME-ARG$ CMD-ADD ;

: DISPATCH ( -- )
   SCRIPT-ARGC 0= if E-SW-USAGE throw then
   0 ARG$ {: c cu :}
   c cu s" status" STR= if DISPATCH-STATUS exit then
   c cu s" save" STR= if [: CMD-SAVE ;] DISPATCH-PROVIDERS exit then
   c cu s" usage" STR= if [: CMD-USAGE ;] DISPATCH-PROVIDERS exit then
   c cu s" use" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-USE exit then
   c cu s" next" STR= if 2 ARG-COUNT 1 PROVIDER# CMD-NEXT exit then
   c cu s" add" STR= if DISPATCH-ADD exit then
   c cu s" forget" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-FORGET exit then
   c cu s" redeem" STR= if 3 ARG-COUNT 1 PROVIDER# 2 NAME-ARG$ CMD-REDEEM exit then
   E-SW-USAGE throw ;

: RUN ( -- )
   ALLOC-BUFFERS
   DISPATCH ;

: FINISH ( n -- ) {: rc :}
   rc 0= if s" " 0 die then
   rc E-SW-USAGE = if USAGE s" " 64 die then
   rc E-SW-REPORTED = if s" " 1 die then
   rc REASON$ ERR-NOTE
   s" " 1 die ;

public

\ SIGPIPE is ignored for the run: a write to a pipe with no reader fails like
\ any other write, and the commands kiba starts inherit the ignore
: MAIN ( -- ) FD:STDERR [: [: RUN ;] catch FINISH ;] FD:WITH-NOSIGPIPE ;

;package

: MAIN ( -- ) SW:MAIN ;
