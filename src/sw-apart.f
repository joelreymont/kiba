split-str
\ sw-apart.f - a command run apart from its caller, in a process of its own:
\ the runner, in another session and process group and no descendant of the
\ caller, so neither a signal to the caller's group, session or process tree nor
\ the end of its terminal reaches it.
\ The caller forks the middle process, which forks the waiter and ends. The
\ waiter is no descendant of the caller once the middle process has ended; the
\ caller, having seen it end, says so down the lifeline, and only then does the
\ waiter fork the runner, which starts its own session. So no single listing of
\ the caller's tree, not even one taken while the middle process was alive,
\ names the runner.
require ../src/sw-base.f
require src/lib/fd.f
require src/lib/ffi-abi.f
require src/lib/process.f
require src/lib/process-fork.f
require src/lib/span.f
require src/lib/prelude.f

package SW

PROCESS-SYMBOLS
FUNCTION: SETSID-CALL setsid ( -- i32 ) ;FUNCTION

variable LIFE-FD                 \ the runner's end of the caller's lifeline
-1 LIFE-FD !                     \ -1: nothing runs apart here
1 BUFFER: CODE-BYTE
1 BUFFER: LIFE-BYTE              \ its value says nothing

: SHUT-FD ( fd -- ) FD>N close ;

\ ---- the runner ---------------------------------------------------------------
: RUN-BODY ( [ -- n ] fd -- ) {: body w:fd :}
   body execute CODE-BYTE c!
   w CODE-BYTE 1 FD:WRITE-FULL ;

\ false: the caller ended before it saw the middle process end
: LET-GO? ( -- bool )
   LIFE-FD @ >FD LIFE-BYTE 1 SPAN:MAKE FD:READ-EXACT MATCH FD:fill
      full OF true ENDOF
      eof OF drop false ENDOF
   ;MATCH ;

: AWAIT-END ( [ -- n ] fd -- ) {: body w:fd :}
   LET-GO? 0= if exit then
   PROC-FORK:CHECKED PID>N 0= if
      SETSID-CALL 0 < if E-SW-APART throw then
      body w RUN-BODY
   then ;

\ the middle process ends at once, so the waiter is reparented
: SPLIT ( [ -- n ] fd -- ) {: body w:fd :}
   PROC-FORK:CHECKED PID>N 0= if body w AWAIT-END then ;

\ a throw ends the process here: it must not unwind into the caller's copy
: CHILD ( [ -- n ] fd fd -- ) {: body w:fd life:fd :}
   life FD>N LIFE-FD !
   [: body w SPLIT ;] catch 0= if s" " 0 die then
   s" " 1 die ;

\ ---- the caller ---------------------------------------------------------------
: READ-CODE ( fd -- n )
   CODE-BYTE 1 SPAN:MAKE FD:READ-EXACT MATCH FD:fill
      full OF CODE-BYTE c@ ENDOF
      eof OF E-SW-APART throw ENDOF
   ;MATCH ;

\ a byte with no waiter to read it is dropped: the code pipe then just ends
: AWAIT-CODE ( pid fd fd -- n ) {: pid:pid r:fd hold:fd :}
   pid PROCESS:WAIT drop
   hold LIFE-BYTE 1 FD:TRY-WRITE-FULL drop
   r READ-CODE ;

public

\ the body's exit code, 0 to 255, from a process of its own; E-SW-APART when
\ that process did not start or ended without one. What the body opens is
\ the runner's alone
: APART ( [ -- n ] -- n ) {: body :}
   FD:PIPE {: r:fd w:fd :}
   FD:PIPE {: life:fd hold:fd :}
   PROC-FORK:RAW {: pid:pid :}
   pid PID>N 0 < if E-SW-APART throw then
   pid PID>N 0= if r SHUT-FD hold SHUT-FD body w life CHILD then
   w SHUT-FD life SHUT-FD
   [: pid r hold AWAIT-CODE ;] [: r SHUT-FD hold SHUT-FD ;] finally ;

\ true in a runner whose caller has gone; the lifeline carries no bytes once
\ the body runs, so it is ready only once its write end is closed
: CALLER-GONE? ( -- bool )
   LIFE-FD @ {: fd :}
   fd 0 < if false exit then
   fd >FD 0 >MS PROCESS:POLL-IN COUNT>N 0 > ;

;package
