split-str
\ sw-run.f - provider login commands, run in the foreground inside a
\ throwaway home.
require ../src/sw-base.f
require ../src/sw-paths.f
require src/lib/fmt.f
require src/lib/process.f
require src/lib/process-argv.f
require src/lib/process-env.f
require src/lib/process-fork.f
require src/lib/adt/option.f
require src/lib/prelude.f

package SW

create EXE-BUF PATH-CAP allot
variable EXE-U

: EXE$ ( -- ^u8 n ) EXE-BUF EXE-U @ ;

: FOUND? ( ^u8 n -- bool )
   >LEN EXE-BUF FIND-EXECUTABLE MATCH option
     none OF false ENDOF
     some OF LEN>N EXE-U ! true ENDOF
   ;MATCH ;

: RESOLVE ( ^u8 n -- )
   FOUND? 0= if E-SW-NO-CLI throw then ;

: ARG+ ( ^u8 n -- )
   >LEN PROC-ARGV+ ;

\ ---- the child's environment ------------------------------------------------
: PROVIDER-HOME-VAR$ ( n -- ^u8 n )
   P-CLAUDE = if s" CLAUDE_CONFIG_DIR" exit then
   s" CODEX_HOME" ;

\ this process's environment with the provider's home variable naming the
\ throwaway home; a real one of that name never reaches the child, since
\ PROC-ENV-INHERIT-MISSING skips a name already set
: LOGIN-ENV ( n -- ) {: p :}
   PROC-ENV-RESET
   p PROVIDER-HOME-VAR$ >LEN p LOGIN-DIR$ >LEN PROC-ENV-SET
   PROC-ENV-INHERIT-MISSING ;

\ the child keeps this process's group, terminal, and descriptors: the
\ spawn primitives give a child its own process group, and a login that
\ then reads the terminal is stopped by SIGTTIN
: EXEC-STAGED ( ^u8 ^^u8 ^^u8 -- ) {: pathz argv envp :}
   pathz argv envp execve drop
   s" kiba: could not start the provider command" 127 die ;

: RUN-STAGED ( -- n )
   EXE$ >LEN PROC-ARGV-PREPARE PROC-ENV-PREPARE {: pathz argv envp :}
   PROC-FORK:CHECKED {: pid :}
   pid PID>N 0= if pathz argv envp EXEC-STAGED then
   PROC-ARGV-ENV-RESET
   pid PROCESS:WAIT PROCESS:STATUS>RC RC>N ;

public

\ the provider login inside the throwaway home; an expected email is passed
\ on where the login command can prefill it
: CLAUDE-LOGIN ( ^u8 n -- n ) {: e eu :}
   s" claude" RESOLVE
   PROC-ARGV-RESET s" auth" ARG+ s" login" ARG+
   eu 0 > if s" --email" ARG+ e eu ARG+ then
   P-CLAUDE LOGIN-ENV
   RUN-STAGED ;

: CODEX-LOGIN ( -- n )
   s" codex" RESOLVE
   PROC-ARGV-RESET s" login" ARG+
   P-CODEX LOGIN-ENV
   RUN-STAGED ;

: LOGIN ( n ^u8 n -- n ) {: p e eu :}
   p case
     P-CLAUDE of e eu CLAUDE-LOGIN endof
     P-CODEX of CODEX-LOGIN endof
     E-SW-PROVIDER throw
   endcase ;

\ the provider command must exist before the throwaway home is made
: CHECK-LOGIN-CLI ( n -- )
   case
     P-CLAUDE of s" claude" RESOLVE endof
     P-CODEX of s" codex" RESOLVE endof
     E-SW-PROVIDER throw
   endcase ;


;package
