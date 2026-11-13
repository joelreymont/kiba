\ sw-base.f - errors, providers, and byte helpers shared by every kiba module.
require src/lib/error.f
require src/lib/string.f
require src/lib/prelude.f
require src/lib/fs.f

package SW

public

\ kiba error block: -100000..-100099, in Habu's external range (src/lib/error.f)
-100000 constant E-SW-FIRST
-100099 constant E-SW-LAST
-100000 constant E-SW-USAGE       \ bad command line
-100001 constant E-SW-PROVIDER    \ unknown provider name
-100002 constant E-SW-NO-LIVE     \ the provider has no live login to save
-100003 constant E-SW-NO-ACCOUNT  \ the named account is not saved
-100004 constant E-SW-NAME        \ an account name carries unsafe bytes
-100006 constant E-SW-JSON        \ a provider file lacks an expected field
-100007 constant E-SW-LOGIN       \ the provider login command failed
-100008 constant E-SW-CAPACITY    \ a fixed buffer is too small
-100009 constant E-SW-NO-CLI      \ a required command is not on PATH
-100010 constant E-SW-BASE64      \ a JWT segment is not base64url
-100011 constant E-SW-ENV         \ HOME is not set
-100013 constant E-SW-MISMATCH    \ a saved login names a different account than its name
-100015 constant E-SW-MIXED       \ the live Claude files name different accounts
-100016 constant E-SW-DB          \ a SQLite call failed
-100017 constant E-SW-DB-VERSION  \ the store is from a newer schema
-100018 constant E-SW-TURN-BUSY   \ another kiba holds the provider's turn
-100019 constant E-SW-UNRESTORED  \ an add's record of the live login waits to be put back
-100020 constant E-SW-SUPERSEDED  \ another install claimed the pending marker first
-100021 constant E-SW-ORPHAN-LIVE \ Claude credentials exist without a config naming them
-100022 constant E-SW-UNREPAIRED  \ a switch began and did not finish
-100023 constant E-SW-REPORTED    \ a command printed its failures already

0 constant P-CLAUDE
1 constant P-CODEX
2 constant P-COUNT

$3D constant EQUALS
128 constant NAME-CAP           \ longest account name plus its length byte

: PROVIDER$ ( n -- ptr u8 n )
   case
     P-CLAUDE of s" claude" endof
     P-CODEX of s" codex" endof
     E-SW-PROVIDER throw
   endcase ;

: PROVIDER# ( ptr u8 n -- n ) {: a u :}
   a u s" claude" STR= if P-CLAUDE exit then
   a u s" codex" STR= if P-CODEX exit then
   E-SW-PROVIDER throw ;

: ERR-TYPE ( ptr u8 n -- ) {: a u :}
   2 a u write u <> if E-FS-IO throw then ;

: ERR-LINE ( ptr u8 n -- )
   ERR-TYPE s\" \n" ERR-TYPE ;

\ a diagnostic that must not turn a degraded result into a failure
: ERR-PART ( ptr u8 n -- ) {: a u :}
   2 a u write drop ;

: ERR-NOTE ( ptr u8 n -- )
   ERR-PART s\" \n" ERR-PART ;

\ copy a span into caller storage with an explicit capacity and length cell
: SPAN! ( ptr u8 n ptr u8 ptr n n -- ) {: a u dst up cap :}
   u 0 < if E-SW-CAPACITY throw then
   u cap > if E-SW-CAPACITY throw then
   a dst u BYTE-COPY
   u up ! ;

: PATH! ( ptr u8 n ptr u8 ptr n -- )
   PATH-CAP SPAN! ;

: NAME-BYTE? ( n -- bool ) {: c :}
   c $20 < if false exit then
   c $7F = if false exit then
   c FS:SLASH <> ;

\ account names become directory names: no control bytes, no slash, no
\ leading dot; any other byte an email may carry is fine in a path
: NAME-OK? ( ptr u8 n -- bool ) {: a u :}
   u 0 <= if false exit then
   u NAME-CAP 1- > if false exit then
   a c@ FS:DOT = if false exit then
   0 begin dup u < while
      dup a + c@ NAME-BYTE? 0= if drop false exit then
      1+
   repeat drop true ;

: CHECK-NAME ( ptr u8 n -- )
   NAME-OK? 0= if E-SW-NAME throw then ;

\ the number after "email #", or -1 when the name is not of that form
: NAME-SUFFIX# ( ptr u8 n ptr u8 n -- n ) {: a u e eu :}
   u eu 2 + <= if -1 exit then
   a eu e eu STR= 0= if -1 exit then
   a eu + 2 s"  #" STR= 0= if -1 exit then
   a eu + 2 + u eu - 2 - STR-DIGITS? 0= if -1 exit then
   a eu + 2 + u eu - 2 - STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

\ a slot name belongs to an email when it is the email or "email #n"
: NAME-FOR-EMAIL? ( ptr u8 n ptr u8 n -- bool ) {: a u e eu :}
   a u e eu STR= if true exit then
   a u e eu NAME-SUFFIX# 0 > ;

\ the email part of a slot name
: NAME-EMAIL ( ptr u8 n -- ptr u8 n ) {: a u :}
   a u s"  #" FIND-SUB MATCH option
     none OF a u ENDOF
     some OF IDX>N {: i :} a i ENDOF
   ;MATCH ;

: LAST-SLASH ( ptr u8 n -- n ) {: a u :}
   u begin dup 0 > while
      1- dup a + c@ FS:SLASH = if exit then
   repeat
   drop -1 ;

: DIRNAME ( ptr u8 n -- ptr u8 n ) {: a u :}
   a u LAST-SLASH {: i :}
   i 0 < if a 0 exit then
   i 0= if a 1 exit then
   a i ;

\ ---- base64url ------------------------------------------------------------
-1 constant B64-END             \ '=' padding: the payload is complete
-2 constant B64-BAD

: B64-VALUE ( n -- n ) {: c :}
   c $41 >= c $5A <= and if c $41 - exit then
   c $61 >= c $7A <= and if c $61 - 26 + exit then
   c $30 >= c $39 <= and if c $30 - 52 + exit then
   c $2D = c $2B = or if 62 exit then
   c $5F = c $2F = or if 63 exit then
   c EQUALS = if B64-END exit then
   B64-BAD ;

variable B64-ACC
variable B64-BITS
variable B64-OUT

\ six leftover bits mean one dangling character: no group has that length
: B64-FINISH ( -- n )
   B64-BITS @ 6 >= if E-SW-BASE64 throw then
   B64-OUT @ ;

: B64-PUSH ( n ptr u8 n -- ) {: v dst cap :}
   B64-ACC @ $3FFFFFF and 6 lshift v or B64-ACC !
   B64-BITS @ 6 + B64-BITS !
   B64-BITS @ 8 >= if
      B64-BITS @ 8 - B64-BITS !
      B64-OUT @ cap >= if E-SW-CAPACITY throw then
      B64-ACC @ B64-BITS @ rshift $FF and dst B64-OUT @ + c!
      1 B64-OUT +!
   then ;

: B64URL-DECODE ( ptr u8 n ptr u8 n -- n ) {: src u dst cap :}
   0 B64-ACC ! 0 B64-BITS ! 0 B64-OUT !
   0 begin dup u < while
      dup src + c@ B64-VALUE {: v :}
      v B64-END = if drop B64-FINISH exit then
      v B64-BAD = if E-SW-BASE64 throw then
      v dst cap B64-PUSH
      1+
   repeat drop
   B64-FINISH ;

;package
