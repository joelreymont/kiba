split-str
\ sw-base.f - errors, providers, and byte helpers shared by every kiba module.
require src/lib/error.f
require src/lib/string.f
require src/lib/prelude.f
require src/lib/fs.f
require src/lib/fmt.f
require src/lib/adt/option.f

package SW

public

\ kiba error block: -100000..-100099, in Habu's external range (src/lib/error.f)
-100000 constant E-SW-USAGE       \ bad command line
-100001 constant E-SW-PROVIDER    \ unknown provider name
-100002 constant E-SW-NO-LIVE     \ the provider has no live login to save
-100003 constant E-SW-NO-ACCOUNT  \ the named account is not saved
-100004 constant E-SW-NAME        \ an account name carries unsafe bytes
-100006 constant E-SW-JSON        \ a provider file lacks an expected field
-100007 constant E-SW-LOGIN       \ the provider login command failed
-100008 constant E-SW-CAPACITY    \ a fixed buffer is too small
-100009 constant E-SW-NO-CLI      \ a required command is not on PATH
-100011 constant E-SW-ENV         \ HOME is not set
-100013 constant E-SW-MISMATCH    \ a saved login names a different account than its name
-100015 constant E-SW-MIXED       \ the live Claude files name different accounts
-100016 constant E-SW-DB          \ a SQLite call failed
-100017 constant E-SW-DB-VERSION  \ the store is from a newer schema
-100018 constant E-SW-TURN-BUSY   \ another kiba holds the provider's turn
-100021 constant E-SW-ORPHAN-LIVE \ Claude credentials exist without a config naming them
-100022 constant E-SW-UNREPAIRED  \ a switch began and did not finish
-100023 constant E-SW-REPORTED    \ a command printed its failures already
-100024 constant E-SW-NO-RESETS   \ the saved login's last probe offered no limit reset
-100025 constant E-SW-REMOTE      \ a provider did not spend a limit reset; its note says why
-100026 constant E-SW-OUTPUT      \ stdout refused a write
-100027 constant E-SW-NO-ROOM     \ no other saved account has room

0 constant P-CLAUDE
1 constant P-CODEX
2 constant P-COUNT

$3D constant EQUALS
128 constant NAME-CAP           \ longest account name plus its length byte

: PROVIDER$ ( n -- ^u8 n )
   case
     P-CLAUDE of s" claude" endof
     P-CODEX of s" codex" endof
     E-SW-PROVIDER throw
   endcase ;

\ a diagnostic whose refused write must not change the outcome: a degraded
\ result stays one, and a failure keeps its exit code
: ERR-PART ( ^u8 n -- ) {: a u :}
   2 a u write drop ;

: ERR-NOTE ( ^u8 n -- )
   ERR-PART s\" \n" ERR-PART ;

private

256 constant TOO-MANY-CAP
create TOO-MANY-BUF TOO-MANY-CAP allot   variable TOO-MANY-U

public

\ E-SW-CAPACITY, keeping what overflowed, cut to TOO-MANY-CAP, for its
\ reason, in the form "<what> (limit <n>)"
: TOO-MANY ( ^u8 n -- ) {: a u :}
   u TOO-MANY-CAP min {: k :}
   a TOO-MANY-BUF k BYTE-COPY
   k TOO-MANY-U !
   E-SW-CAPACITY throw ;

: TOO-MANY$ ( -- ^u8 n ) TOO-MANY-BUF TOO-MANY-U @ ;

private

: SB-LIMIT ( n -- )
   s"  (limit " SB-APPEND FMT:SB-INT s" )" SB-APPEND ;

\ "<what> (limit <n>)", built in SB
: LIMIT$ ( ^u8 n n -- ^u8 n ) {: a u cap :}
   SB-RESET a u SB-APPEND cap SB-LIMIT SB$ ;

public

\ copy a span into caller storage with an explicit capacity and length cell
: SPAN! ( ^u8 n ^u8 ^n n -- ) {: a u dst up cap :}
   u cap > if s" bytes in a value" cap LIMIT$ TOO-MANY then
   a dst u BYTE-COPY
   u up ! ;

: PATH! ( ^u8 n ^u8 ^n -- )
   PATH-CAP SPAN! ;

: NAME-BYTE? ( n -- bool ) {: c :}
   c $20 < if false exit then
   c $7F = if false exit then
   c FS:SLASH <> ;

\ account names become directory names: no control bytes, no slash, no
\ leading dot; any other byte an email may carry is fine in a path
: NAME-OK? ( ^u8 n -- bool ) {: a u :}
   u 0 <= if false exit then
   u NAME-CAP 1- > if false exit then
   a c@ FS:DOT = if false exit then
   0 begin dup u < while
      dup a + c@ NAME-BYTE? 0= if drop false exit then
      1+
   repeat drop true ;

: CHECK-NAME ( ^u8 n -- )
   NAME-OK? 0= if E-SW-NAME throw then ;

\ the number after "email #", or -1 when the name is not of that form
: NAME-SUFFIX# ( ^u8 n ^u8 n -- n ) {: a u e eu :}
   u eu 2 + <= if -1 exit then
   a eu e eu STR= 0= if -1 exit then
   a eu + 2 s"  #" STR= 0= if -1 exit then
   a eu + 2 + u eu - 2 - STR-DIGITS? 0= if -1 exit then
   a eu + 2 + u eu - 2 - STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

\ a slot name belongs to an email when it is the email or "email #n"
: NAME-FOR-EMAIL? ( ^u8 n ^u8 n -- bool ) {: a u e eu :}
   a u e eu STR= if true exit then
   a u e eu NAME-SUFFIX# 0 > ;

\ the email part of a slot name
: NAME-EMAIL ( ^u8 n -- ^u8 n ) {: a u :}
   a u s"  #" FIND-SUB MATCH option
     none OF a u ENDOF
     some OF IDX>N {: i :} a i ENDOF
   ;MATCH ;

: LAST-SLASH ( ^u8 n -- n ) {: a u :}
   u begin dup 0 > while
      1- dup a + c@ FS:SLASH = if exit then
   repeat
   drop -1 ;

: DIRNAME ( ^u8 n -- ^u8 n ) {: a u :}
   a u LAST-SLASH {: i :}
   i 0 < if a 0 exit then
   i 0= if a 1 exit then
   a i ;

\ the first index from at whose byte is not a digit
: DIGIT-RUN ( ^u8 n n -- n ) {: a u at :}
   at begin
      dup u < if dup a + c@ STR-DIGIT? else false then
   while 1+ repeat ;

;package
