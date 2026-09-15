\ sw-store.f - the sorted list of saved accounts for one provider.
require ../src/sw-claude.f
require ../src/sw-codex.f
require lib/fmt.f

package SW

256 constant ACCT-MAX

\ one slot per account: a length byte followed by the name bytes
create ACCT-NAMES ACCT-MAX NAME-CAP * allot
create ACCT-TMP NAME-CAP allot
variable ACCT-N
variable LIST-P

: ACCT-SLOT ( n -- ptr u8 )
   ACCT-NAMES swap NAME-CAP * + ;

: ACCT-SWAP ( n n -- ) {: i j :}
   i ACCT-SLOT ACCT-TMP NAME-CAP BYTE-COPY
   j ACCT-SLOT i ACCT-SLOT NAME-CAP BYTE-COPY
   ACCT-TMP j ACCT-SLOT NAME-CAP BYTE-COPY ;

: MARKER$ ( n -- ptr u8 n )
   case
     P-CLAUDE of s" credentials.json" endof
     P-CODEX of s" auth.json" endof
     E-SW-PROVIDER throw
   endcase ;

public

: ACCT-NAME ( n -- ptr u8 n )
   ACCT-SLOT dup 1+ swap c@ ;

: ACCT# ( -- n ) ACCT-N @ ;

: ACCT-RESET ( n -- ) ACCT-N ! ;

: ACCT+ ( ptr u8 n -- ) {: a u :}
   ACCT-N @ ACCT-MAX >= if E-SW-CAPACITY throw then
   u NAME-CAP 1- > if E-SW-NAME throw then
   ACCT-N @ ACCT-SLOT {: s :}
   u s c!
   a s 1+ u BYTE-COPY
   1 ACCT-N +! ;

private

: ACCT< ( n n -- bool ) {: i j :}
   i ACCT-NAME j ACCT-NAME STR< ;

: OUT-OF-ORDER? ( n -- bool ) {: j :}
   j 0 <= if false exit then
   j j 1- ACCT< ;

: SORT-ACCOUNTS ( -- )
   1 begin dup ACCT-N @ < while
      dup begin dup OUT-OF-ORDER? while dup dup 1- ACCT-SWAP 1- repeat drop
      1+
   repeat drop ;

: NOTE-FILE ( ptr u8 n -- ) {: a u :}
   a u BASENAME LIST-P @ MARKER$ STR= 0= if exit then
   a u DIRNAME DIRNAME LIST-P @ PROVIDER-DIR$ STR= 0= if exit then
   a u DIRNAME BASENAME ACCT+ ;

: SLOT-PLAN-RAW ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-SLOT-PLAN endof
     P-CODEX of a u CODEX-SLOT-PLAN endof
     E-SW-PROVIDER throw
   endcase ;

: SLOT-PLAN-KEEP ( n ptr u8 n -- n ptr u8 n ) {: p a u :}
   p a u SLOT-PLAN-RAW p a u ;

: WARN-SLOT ( ptr u8 n n -- ) {: a u rc :}
   SB-RESET s" switcher: saved account " SB-APPEND a u SB-APPEND
   s"  has an unreadable file (error " SB-APPEND rc FMT:SB-INT s" )" SB-APPEND
   SB$ ERR-NOTE ;

public

: LIST-ACCOUNTS ( n -- ) {: p :}
   0 ACCT-N !
   p LIST-P !
   p PROVIDER-DIR$ DIR? 0= if exit then
   p PROVIDER-DIR$ [: NOTE-FILE ;] WALK-FILES
   SORT-ACCOUNTS ;

\ a slot with a damaged file still lists; only its plan is unknown.
\ catch keeps only the depth, so the cells under the code are dropped unread.
: SLOT-PLAN ( n ptr u8 n -- ) {: p a u :}
   p a u [: SLOT-PLAN-KEEP ;] catch {: rc :} 2drop drop
   rc 0= if exit then
   0 PLAN-U !
   a u rc WARN-SLOT ;

: LIVE-IDENTITY ( n -- bool )
   case
     P-CLAUDE of CLAUDE-LIVE-IDENTITY endof
     P-CODEX of CODEX-LIVE-IDENTITY endof
     E-SW-PROVIDER throw
   endcase ;

: SAVE-LIVE ( n -- )
   case
     P-CLAUDE of CLAUDE-SAVE-LIVE endof
     P-CODEX of CODEX-SAVE-LIVE endof
     E-SW-PROVIDER throw
   endcase ;

: INSTALL ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-INSTALL endof
     P-CODEX of a u CODEX-INSTALL endof
     E-SW-PROVIDER throw
   endcase ;

;package
