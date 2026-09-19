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
create NAME-OUT NAME-CAP allot      variable NAME-OUT-U
variable SLOT-DAMAGED               \ bool: the slot's identity file is missing or unreadable
create SAVED-NAME NAME-CAP allot    variable SAVED-NAME-U  \ the slot the last save went to

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

\ "email #2" sorts before "email #10": same-email names order by number
: ACCT< ( n n -- bool ) {: i j :}
   i ACCT-NAME NAME-EMAIL j ACCT-NAME NAME-EMAIL STR= 0= if
      i ACCT-NAME j ACCT-NAME STR< exit
   then
   i ACCT-NAME 2dup NAME-EMAIL NAME-SUFFIX# 1 max
   j ACCT-NAME 2dup NAME-EMAIL NAME-SUFFIX# 1 max < ;

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
   a u DIRNAME BASENAME NAME-OK? 0= if exit then
   a u DIRNAME BASENAME ACCT+ ;

\ the file that names a slot's account
: IDENTITY-FILE$ ( n -- ptr u8 n )
   case
     P-CLAUDE of OAUTH-NAME$ endof
     P-CODEX of AUTH-NAME$ endof
     E-SW-PROVIDER throw
   endcase ;

: SLOT-IDENTITY ( n ptr u8 n -- bool ) {: p a u :}
   p a u p IDENTITY-FILE$ SLOT-FILE$ FILE? 0= if false exit then
   p a u p IDENTITY-FILE$ SLOT-FILE$ READ-SLOT$
   p P-CLAUDE = if ID-SLOT CLAUDE-OAUTH-IDENTITY exit then
   ID-SLOT CODEX-IDENTITY ;

: SLOT-IDENTITY-KEEP ( n ptr u8 n -- n ptr u8 n ) {: p a u :}
   p a u SLOT-IDENTITY 0= if true SLOT-DAMAGED ! then
   p a u ;

\ ID-SLOT holds who a slot belongs to, empty where the slot cannot say. A
\ slot whose identity file is missing or unreadable is damaged: it must not
\ hide the live login, and it may be overwritten by a good one.
: SLOT-IDENTITY-READ ( n ptr u8 n -- ) {: p a u :}
   ID-SLOT NO-IDENTITY
   false SLOT-DAMAGED !
   p a u [: SLOT-IDENTITY-KEEP ;] catch {: rc :} 2drop drop
   rc 0<> if true SLOT-DAMAGED ! then ;

9 constant NAME-TRIES

\ candidate n: the bare email, then "email #2", "email #3", ...
: NAME-CANDIDATE ( n -- ptr u8 n ) {: n :}
   n 1 = if ID-LIVE EMAIL$ exit then
   SB-RESET ID-LIVE EMAIL$ SB-APPEND s"  #" SB-APPEND n FMT:SB-U SB$ ;

variable NAME-FREE                  \ first candidate that is free or damaged; 0 when none

\ does the slot named by NAME-OUT hold exactly the live login's organization?
: SLOT-HOLDS-LIVE? ( n -- bool ) {: p :}
   p NAME-OUT NAME-OUT-U @ SLOT-IDENTITY-READ
   SLOT-DAMAGED @ if false exit then
   ID-SLOT ORG$ nip 0= if ID-LIVE ORG$ nip 0= exit then
   ID-LIVE ORG$ nip 0= if false exit then
   ID-SLOT ORG$ ID-LIVE ORG$ STR= ;

: NAME-CANDIDATE! ( n -- )
   NAME-CANDIDATE NAME-OUT NAME-OUT-U NAME-CAP 1- SPAN! ;

\ the slot name for the live login: the candidate that already holds this
\ organization wins over every other; otherwise the first free or damaged
\ candidate, so a damaged slot is repaired only by a login no other slot
\ claims
: LIVE-NAME ( n -- ptr u8 n ) {: p :}
   0 NAME-FREE !
   1 begin dup NAME-TRIES <= while
      dup NAME-CANDIDATE!
      p NAME-OUT NAME-OUT-U @ SLOT-DIR$ DIR? 0= if
         NAME-FREE @ 0= if dup NAME-FREE ! then
      else
         p SLOT-HOLDS-LIVE? if drop NAME-OUT NAME-OUT-U @ exit then
         SLOT-DAMAGED @ NAME-FREE @ 0= and if dup NAME-FREE ! then
      then
      1+
   repeat drop
   NAME-FREE @ 0= if E-SW-CAPACITY throw then
   NAME-FREE @ NAME-CANDIDATE!
   NAME-OUT NAME-OUT-U @ ;

: SLOT-PLAN-RAW ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-SLOT-PLAN endof
     P-CODEX of a u CODEX-SLOT-PLAN endof
     E-SW-PROVIDER throw
   endcase ;

: SLOT-PLAN-KEEP ( n ptr u8 n -- n ptr u8 n ) {: p a u :}
   p a u SLOT-PLAN-RAW p a u ;

: WARN-SLOT ( ptr u8 n n -- ) {: a u rc :}
   SB-RESET s" kiba: saved account " SB-APPEND a u SB-APPEND
   s"  has an unreadable file (error " SB-APPEND rc FMT:SB-INT s" )" SB-APPEND
   SB$ ERR-NOTE ;

public

\ The live pair is only trusted to belong together while it is what kiba
\ installed, or while both files have changed since. A config naming another
\ account over credentials still byte-identical to the installed slot's is
\ a mix, and saving it would file one account's tokens under another's name.
\ does the live config name the installed slot's account? By email first;
\ two organizations under one email are told apart when both are known.
: CONFIG-NAMES-INSTALLED? ( ptr u8 n -- bool ) {: a u :}
   ID-LIVE EMAIL$ a u NAME-EMAIL STR= 0= if false exit then
   ID-LIVE ORG$ nip 0= if true exit then
   P-CLAUDE a u SLOT-IDENTITY-READ
   ID-SLOT ORG$ nip 0= if true exit then
   ID-SLOT ORG$ ID-LIVE ORG$ STR= ;

: CLAUDE-MIXED? ( -- bool )
   P-CLAUDE INSTALLED$ {: a u :}
   u 0= if false exit then
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ FILE? 0= if false exit then
   CLAUDE-LIVE-IDENTITY 0= if false exit then
   a u CONFIG-NAMES-INSTALLED? if false exit then
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ READ-SLOT$
   CLAUDE-CREDS$ READ-FILE$ STR= ;

EXPORT LIVE-NAME

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
   ID-SLOT NO-IDENTITY
   a u rc WARN-SLOT ;

: LIVE-IDENTITY ( n -- bool )
   case
     P-CLAUDE of CLAUDE-LIVE-IDENTITY endof
     P-CODEX of CODEX-LIVE-IDENTITY endof
     E-SW-PROVIDER throw
   endcase ;

: SAVED-NAME$ ( -- ptr u8 n ) SAVED-NAME SAVED-NAME-U @ ;

: SAVE-LIVE ( n -- ) {: p :}
   p LIVE-NAME SAVED-NAME SAVED-NAME-U NAME-CAP 1- SPAN!
   SAVED-NAME$ {: a u :}
   p case
     P-CLAUDE of a u CLAUDE-SAVE-LIVE endof
     P-CODEX of a u CODEX-SAVE-LIVE endof
     E-SW-PROVIDER throw
   endcase ;

: INSTALL ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-INSTALL endof
     P-CODEX of a u CODEX-INSTALL endof
     E-SW-PROVIDER throw
   endcase ;

;package
