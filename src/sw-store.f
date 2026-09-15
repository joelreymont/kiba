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
create ID-EMAIL 256 allot           variable ID-EMAIL-U    \ the identity being named
create ID-ORG 128 allot             variable ID-ORG-U
create ID-ORGNAME 128 allot         variable ID-ORGNAME-U
create SLOT-ORG 128 allot           variable SLOT-ORG-U    \ a slot's organization

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
   a u DIRNAME BASENAME NAME-OK? 0= if exit then
   a u DIRNAME BASENAME ACCT+ ;

: ID-EMAIL$ ( -- ptr u8 n ) ID-EMAIL ID-EMAIL-U @ ;
: ID-ORG$ ( -- ptr u8 n ) ID-ORG ID-ORG-U @ ;
: ID-ORGNAME$ ( -- ptr u8 n ) ID-ORGNAME ID-ORGNAME-U @ ;

\ the identity words share buffers with slot reads, so the live one is copied
: ID-TAKE ( -- )
   EMAIL$ ID-EMAIL ID-EMAIL-U 256 SPAN!
   ORG$ ID-ORG ID-ORG-U 128 SPAN!
   ORGNAME$ ID-ORGNAME ID-ORGNAME-U 128 SPAN! ;

\ the organization recorded in a slot; empty when the slot cannot say
: SLOT-ORG-READ ( n ptr u8 n -- ) {: p a u :}
   0 SLOT-ORG-U !
   p P-CLAUDE = if
      p a u s" oauth-account.json" SLOT-FILE$ FILE? 0= if exit then
      p a u s" oauth-account.json" SLOT-FILE$ READ-FILE$ CLAUDE-OAUTH-IDENTITY 0= if exit then
   else
      p a u s" auth.json" SLOT-FILE$ FILE? 0= if exit then
      p a u s" auth.json" SLOT-FILE$ READ-FILE$ CODEX-IDENTITY 0= if exit then
   then
   ORG$ SLOT-ORG SLOT-ORG-U 128 SPAN! ;

: NAME-WITH-ORG ( -- ptr u8 n )
   SB-RESET ID-EMAIL$ SB-APPEND s"  (" SB-APPEND
   ID-ORGNAME-U @ 0 > if ID-ORGNAME$ SB-APPEND else ID-ORG$ 8 min SB-APPEND then
   s" )" SB-APPEND SB$ ;

\ the slot name for the identity in ID-*: the bare email unless another
\ organization already holds that name, then "email (organization)"
: RESOLVE-NAME ( n -- ptr u8 n ) {: p :}
   ID-EMAIL$ NAME-OUT NAME-OUT-U NAME-CAP 1- SPAN!
   p ID-EMAIL$ SLOT-DIR$ DIR? 0= if NAME-OUT NAME-OUT-U @ exit then
   p ID-EMAIL$ SLOT-ORG-READ
   SLOT-ORG-U @ 0= if NAME-OUT NAME-OUT-U @ exit then
   ID-ORG-U @ 0= if NAME-OUT NAME-OUT-U @ exit then
   SLOT-ORG SLOT-ORG-U @ ID-ORG$ STR= if NAME-OUT NAME-OUT-U @ exit then
   NAME-WITH-ORG NAME-OUT NAME-OUT-U NAME-CAP 1- SPAN!
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
   SB-RESET s" switcher: saved account " SB-APPEND a u SB-APPEND
   s"  has an unreadable file (error " SB-APPEND rc FMT:SB-INT s" )" SB-APPEND
   SB$ ERR-NOTE ;

public

\ the slot name the live identity saves to; callers reload the live
\ documents afterwards because slot reads share their buffers
: LIVE-NAME ( n -- ptr u8 n ) {: p :}
   ID-TAKE
   p RESOLVE-NAME ;

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

: SAVE-LIVE ( n -- ) {: p :}
   p LIVE-NAME {: a u :}
   p LIVE-IDENTITY drop
   p case
     P-CLAUDE of a u CLAUDE-SAVE-LIVE endof
     P-CODEX of a u CODEX-SAVE-LIVE endof
     E-SW-PROVIDER throw
   endcase ;

: LIVE-FILE$ ( n -- ptr u8 n )
   case
     P-CLAUDE of CLAUDE-CREDS$ endof
     P-CODEX of CODEX-AUTH$ endof
     E-SW-PROVIDER throw
   endcase ;

\ A provider's login command revokes whatever login it finds before it starts
\ (codex does; claude is not trusted either), which would kill the saved copy
\ of the account being left. The live file therefore steps aside first.
: SET-ASIDE ( n -- ) {: p :}
   p LIVE-FILE$ ASIDE-FOR FILE? if E-SW-ASIDE throw then
   p LIVE-FILE$ FILE? 0= if exit then
   p LIVE-FILE$ p LIVE-FILE$ ASIDE-FOR RENAME-FILE ;

\ after a failed login the user keeps the login they had
: RESTORE-ASIDE ( n -- ) {: p :}
   p LIVE-FILE$ ASIDE-FOR FILE? 0= if exit then
   p LIVE-FILE$ ASIDE-FOR p LIVE-FILE$ RENAME-FILE ;

: DROP-ASIDE ( n -- ) {: p :}
   p LIVE-FILE$ ASIDE-FOR FILE? 0= if exit then
   p LIVE-FILE$ ASIDE-FOR REMOVE-FILE ;

: INSTALL ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-INSTALL endof
     P-CODEX of a u CODEX-INSTALL endof
     E-SW-PROVIDER throw
   endcase ;

;package
