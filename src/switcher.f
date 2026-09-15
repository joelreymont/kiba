\ switcher.f - entry point: argument dispatch and process exit.
require ../src/sw-cli.f

package SW

: USAGE ( -- )
   s\" usage: switcher status [--json]\n" ERR-TYPE
   s\"        switcher save [claude|codex]\n" ERR-TYPE
   s\"        switcher use <claude|codex> <email>\n" ERR-TYPE
   s\"        switcher add <claude|codex>\n" ERR-TYPE
   s\"        switcher forget <claude|codex> <email>\n" ERR-TYPE ;

: ARG$ ( n -- ptr u8 n )
   dup SCRIPT-ARGC >= if drop E-SW-USAGE throw then
   SCRIPT-ARGV$ ;

: ARG-COUNT ( n -- )
   SCRIPT-ARGC <> if E-SW-USAGE throw then ;

: DISPATCH-STATUS ( -- )
   SCRIPT-ARGC 1 = if false CMD-STATUS exit then
   2 ARG-COUNT
   1 ARG$ s" --json" STR= 0= if E-SW-USAGE throw then
   true CMD-STATUS ;

: DISPATCH-SAVE ( -- )
   SCRIPT-ARGC 1 = if -1 CMD-SAVE exit then
   2 ARG-COUNT
   1 ARG$ PROVIDER# CMD-SAVE ;

: DISPATCH ( -- )
   SCRIPT-ARGC 0= if E-SW-USAGE throw then
   0 ARG$ {: c cu :}
   c cu s" status" STR= if DISPATCH-STATUS exit then
   c cu s" save" STR= if DISPATCH-SAVE exit then
   c cu s" use" STR= if 3 ARG-COUNT 1 ARG$ PROVIDER# 2 ARG$ CMD-USE exit then
   c cu s" add" STR= if 2 ARG-COUNT 1 ARG$ PROVIDER# CMD-ADD exit then
   c cu s" forget" STR= if 3 ARG-COUNT 1 ARG$ PROVIDER# 2 ARG$ CMD-FORGET exit then
   E-SW-USAGE throw ;

: RUN ( -- )
   ALLOC-BUFFERS
   DISPATCH ;

public

: MAIN ( -- )
   [: RUN ;] catch {: rc :}
   rc 0= if s" " 0 die then
   rc E-SW-USAGE = if USAGE s" " 64 die then
   rc REASON$ ERR-LINE
   s" " 1 die ;

;package

: MAIN ( -- ) SW:MAIN ;
