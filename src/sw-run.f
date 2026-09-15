\ sw-run.f - provider login commands and the usage-widget refresh.
require ../src/sw-base.f
require lib/fmt.f
require lib/process.f
require lib/process-argv.f
require lib/process-env.f
require lib/process-fork.f

package SW

create EXE-BUF FS-PATH-CAP allot
variable EXE-U

: EXE$ ( -- ptr u8 n ) EXE-BUF EXE-U @ ;

: FOUND? ( ptr u8 n -- bool )
   >LEN EXE-BUF FIND-EXECUTABLE MATCH option
     none OF false ENDOF
     some OF LEN>N EXE-U ! true ENDOF
   ;MATCH ;

: RESOLVE ( ptr u8 n -- )
   FOUND? 0= if E-SW-NO-CLI throw then ;

: ARG+ ( ptr u8 n -- )
   >LEN PROC-ARGV+ ;

\ the child keeps this process's group, terminal, descriptors, and
\ environment block: the spawn primitives give a child its own process
\ group, and a login that then reads the terminal is stopped by SIGTTIN
: EXEC-STAGED ( ptr u8 ptr ptr u8 -- ) {: pathz argv :}
   pathz argv ENVP-BASE execve drop
   s" switcher: could not start the provider command" 127 die ;

: RUN-INHERIT ( -- n )
   EXE$ >LEN PROC-ARGV-PREPARE {: pathz argv :}
   PROC-FORK:CHECKED {: pid :}
   pid PID>N 0= if pathz argv EXEC-STAGED then
   PROC-ARGV-RESET
   pid PROC-WAIT-RC MATCH result
     ok OF ENDOF
     err OF ENDOF
   ;MATCH ;

: REPORT-RC ( ptr u8 n n -- ) {: a u rc :}
   SB-RESET a u SB-APPEND s"  exited with " SB-APPEND rc FMT:SB-INT
   SB$ ERR-LINE ;

public

: CLAUDE-LOGIN ( -- n )
   s" claude" RESOLVE
   PROC-ARGV-RESET s" auth" ARG+ s" login" ARG+
   RUN-INHERIT ;

: CODEX-LOGIN ( -- n )
   s" codex" RESOLVE
   PROC-ARGV-RESET s" login" ARG+
   RUN-INHERIT ;

: LOGIN ( n -- n )
   case
     P-CLAUDE of CLAUDE-LOGIN endof
     P-CODEX of CODEX-LOGIN endof
     E-SW-PROVIDER throw
   endcase ;

\ the provider command must exist before anything is moved for its sake
: CHECK-LOGIN-CLI ( n -- )
   case
     P-CLAUDE of s" claude" RESOLVE endof
     P-CODEX of s" codex" RESOLVE endof
     E-SW-PROVIDER throw
   endcase ;

\ ask the Omarchy agents widget collector to re-read the provider's limits
: USAGE-REFRESH ( n -- ) {: p :}
   s" omarchy-agent-usage-update" FOUND? 0= if
      s" usage: omarchy-agent-usage-update is not on PATH, widget not refreshed" ERR-LINE exit
   then
   PROC-ARGV-RESET s" --limits-only" ARG+ p PROVIDER$ ARG+
   RUN-INHERIT {: rc :}
   rc 0 <> if s" usage: omarchy-agent-usage-update" rc REPORT-RC then ;

;package
