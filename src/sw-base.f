\ sw-base.f - errors, providers, and byte helpers shared by every switcher module.
require lib/errors.f
require lib/string.f
require lib/prelude.f
require lib/fs.f

package SW

public

\ switcher error block: -9900..-9999, outside every lib/errors.f range
-9900 constant E-SW-USAGE       \ bad command line
-9901 constant E-SW-PROVIDER    \ unknown provider name
-9902 constant E-SW-NO-LIVE     \ the provider has no live login to save
-9903 constant E-SW-NO-ACCOUNT  \ the named account is not saved
-9904 constant E-SW-NAME        \ an account name carries unsafe bytes
-9905 constant E-SW-LOCKED      \ another switcher holds the store lock
-9906 constant E-SW-JSON        \ a provider file lacks an expected field
-9907 constant E-SW-LOGIN       \ the provider login command failed
-9908 constant E-SW-CAPACITY    \ a fixed buffer is too small
-9909 constant E-SW-NO-CLI      \ a required command is not on PATH
-9910 constant E-SW-BASE64      \ a JWT segment is not base64url
-9911 constant E-SW-ENV         \ HOME is not set
-9912 constant E-SW-INTERRUPTED \ an earlier switch stopped between its two file writes
-9913 constant E-SW-MISMATCH    \ a saved file names a different account than its slot
-9914 constant E-SW-ASIDE       \ a login file set aside for a login is still there

0 constant P-CLAUDE
1 constant P-CODEX
2 constant P-COUNT

$2F constant SLASH
$2E constant DOT
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
: ERR-NOTE ( ptr u8 n -- ) {: a u :}
   2 a u write drop
   2 s\" \n" write drop ;

\ copy a span into caller storage with an explicit capacity and length cell
: SPAN! ( ptr u8 n ptr u8 ptr n n -- ) {: a u dst up cap :}
   u 0 < if E-SW-CAPACITY throw then
   u cap > if E-SW-CAPACITY throw then
   a dst u BYTE-COPY
   u up ! ;

: PATH! ( ptr u8 n ptr u8 ptr n -- )
   FS-PATH-CAP SPAN! ;

: NAME-BYTE? ( n -- bool ) {: c :}
   c $20 < if false exit then
   c $7F = if false exit then
   c SLASH <> ;

\ account names become directory names: no control bytes, no slash, no
\ leading dot; any other byte an email may carry is fine in a path
: NAME-OK? ( ptr u8 n -- bool ) {: a u :}
   u 0 <= if false exit then
   u NAME-CAP 1- > if false exit then
   a c@ DOT = if false exit then
   0 begin dup u < while
      dup a + c@ NAME-BYTE? 0= if drop false exit then
      1+
   repeat drop true ;

: CHECK-NAME ( ptr u8 n -- )
   NAME-OK? 0= if E-SW-NAME throw then ;

\ a slot name belongs to an email when it is the email or "email (…)"
: NAME-FOR-EMAIL? ( ptr u8 n ptr u8 n -- bool ) {: a u e eu :}
   a u e eu STR= if true exit then
   u eu 2 + <= if false exit then
   a eu e eu STR= 0= if false exit then
   a eu + 2 s"  (" STR= ;

: STR< ( ptr u8 n ptr u8 n -- bool ) {: a u b v :}
   0 begin
      dup u < over v < and
   while
      dup a + c@ over b + c@ <> if
         dup a + c@ swap b + c@ < exit
      then
      1+
   repeat
   drop u v < ;

: LAST-SLASH ( ptr u8 n -- n ) {: a u :}
   u begin dup 0 > while
      1- dup a + c@ SLASH = if exit then
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
   c $5F = c SLASH = or if 63 exit then
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
