\ sw-run.f - provider login commands, run in the foreground inside a
\ throwaway home.
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

\ ---- the child's environment ------------------------------------------------
\ this process's environment with the provider's home variable pointing at
\ the throwaway home; the table ends with a null entry as execve expects
1024 constant ENV-MAX
$1000 constant ENV-STR-CAP
create ENV-TABLE ENV-MAX cells allot
create ENV-STR ENV-STR-CAP allot
variable ENV-N
variable ENV-STR-U

: ENV-SLOT ( n -- ptr ptr u8 ) ENV-TABLE swap ptr-field ;

: ENV-PUSH ( ptr u8 -- ) {: z :}
   ENV-N @ ENV-MAX 1- >= if E-SW-CAPACITY throw then
   z ENV-N @ ENV-SLOT !
   1 ENV-N +! ;

: ENV-DEFINE ( ptr u8 n ptr u8 n -- ) {: name nu val vu :}
   ENV-STR-U @ nu + vu + 2 + ENV-STR-CAP > if E-SW-CAPACITY throw then
   ENV-STR ENV-STR-U @ + {: z :}
   name z nu BYTE-COPY
   EQUALS z nu + c!
   val z nu + 1+ vu BYTE-COPY
   0 z nu + 1+ vu + c!
   ENV-STR-U @ nu + vu + 2 + ENV-STR-U !
   z ENV-PUSH ;

: ENV-NAME= ( ptr u8 ptr u8 n -- bool ) {: z name nu :}
   0 begin dup nu < while
      dup z + c@ over name + c@ <> if drop false exit then
      1+
   repeat drop
   nu z + c@ EQUALS = ;

: ENV-OVERRIDDEN? ( ptr u8 -- bool ) {: z :}
   z s" CLAUDE_CONFIG_DIR" ENV-NAME= if true exit then
   z s" CODEX_HOME" ENV-NAME= ;

: ENV-INHERIT-REST ( -- )
   0 begin dup ENVP 0= 0= while
      dup ENVP ENV-OVERRIDDEN? 0= if dup ENVP ENV-PUSH then
      1+
   repeat drop ;

: PROVIDER-HOME-VAR$ ( n -- ptr u8 n )
   P-CLAUDE = if s" CLAUDE_CONFIG_DIR" exit then
   s" CODEX_HOME" ;

: LOGIN-ENV ( n -- ) {: p :}
   0 ENV-N ! 0 ENV-STR-U !
   p PROVIDER-HOME-VAR$ p LOGIN-DIR$ ENV-DEFINE
   ENV-INHERIT-REST
   NULL$ drop ENV-N @ ENV-SLOT ! ;

\ the child keeps this process's group, terminal, and descriptors: the
\ spawn primitives give a child its own process group, and a login that
\ then reads the terminal is stopped by SIGTTIN
: EXEC-STAGED ( ptr u8 ptr ptr u8 -- ) {: pathz argv :}
   pathz argv ENV-TABLE execve drop
   s" kiba: could not start the provider command" 127 die ;

: RUN-STAGED ( -- n )
   EXE$ >LEN PROC-ARGV-PREPARE {: pathz argv :}
   PROC-FORK:CHECKED {: pid :}
   pid PID>N 0= if pathz argv EXEC-STAGED then
   PROC-ARGV-RESET
   pid PROC-WAIT-RC MATCH result
     ok OF ENDOF
     err OF ENDOF
   ;MATCH ;

public

\ the provider login inside the throwaway home; an expected email is passed
\ on where the login command can prefill it
: CLAUDE-LOGIN ( ptr u8 n -- n ) {: e eu :}
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

: LOGIN ( n ptr u8 n -- n ) {: p e eu :}
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
