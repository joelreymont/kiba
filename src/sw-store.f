\ sw-store.f - the sorted list of saved slots for one provider, and saved
\ logins moved between the account store and the live files.
require ../src/sw-claude.f
require ../src/sw-codex.f
require ../src/sw-db.f
require src/lib/fmt.f
require src/lib/fsm.f

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
   a u FS:BASENAME LIST-P @ MARKER$ STR= 0= if exit then
   a u DIRNAME DIRNAME LIST-P @ PROVIDER-DIR$ STR= 0= if exit then
   a u DIRNAME FS:BASENAME NAME-OK? 0= if exit then
   a u DIRNAME FS:BASENAME ACCT+ ;

\ the file that names a slot's account
: IDENTITY-FILE$ ( n -- ptr u8 n )
   case
     P-CLAUDE of OAUTH-NAME$ endof
     P-CODEX of AUTH-NAME$ endof
     E-SW-PROVIDER throw
   endcase ;

: SLOT-IDENTITY ( n ptr u8 n -- bool ) {: p a u :}
   p a u p IDENTITY-FILE$ SLOT-FILE$ FS:FILE? 0= if false exit then
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
      p NAME-OUT NAME-OUT-U @ SLOT-DIR$ FS:DIR? 0= if
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

public

EXPORT LIVE-NAME

: LIST-ACCOUNTS ( n -- ) {: p :}
   0 ACCT-N !
   p LIST-P !
   p PROVIDER-DIR$ FS:DIR? 0= if exit then
   p PROVIDER-DIR$ [: NOTE-FILE ;] FS:WALK-FILES
   SORT-ACCOUNTS ;

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

\ ---- saved logins and the live files ---------------------------------------
\ The caller holds the provider's turn; every store change runs in DB-WRITE.
private

create LIVE-ROW NAME-CAP allot   variable LIVE-ROW-U

\ the name PUT-LIVE last saved under; its callers empty it first, so it is
\ empty when there was no login
: LIVE-ROW$ ( -- ptr u8 n ) LIVE-ROW LIVE-ROW-U @ ;

\ identity id from row r's email, org and plan
: ROW-IDENTITY ( n n -- ) {: r id :}
   id NO-IDENTITY
   r DB-ROW-EMAIL$ id EMAIL-ROW id F-EMAIL LEN-CELL EMAIL-CAP SPAN!
   r DB-ROW-ORG$ id ORG-ROW id F-ORG LEN-CELL ORG-CAP SPAN!
   r DB-ROW-PLAN$ id PLAN-ROW id F-PLAN LEN-CELL PLAN-CAP SPAN! ;

\ the live login as one read: its login and profile (length -1 for none),
\ the identity in ID-LIVE; false when there is none
: LIVE-LOGIN ( n -- ptr u8 n ptr u8 n bool )
   case
     P-CLAUDE of CLAUDE-LIVE-LOGIN endof
     P-CODEX of CODEX-LIVE-LOGIN endof
     E-SW-PROVIDER throw
   endcase ;

\ only Claude keeps the account and the tokens in two files that can disagree
: LIVE-MIXED? ( n -- bool )
   P-CLAUDE = if CLAUDE-LIVE-MIXED? exit then
   false ;

\ E-SW-UNRESTORED while the store holds an add's record of the live login:
\ until it goes back, the live files may hold tokens no saved name owns
: REQUIRE-RESTORED ( n -- )
   DB-ADDING nip nip if E-SW-UNRESTORED throw then ;

\ puts the live login under the name DB-LIVE-NAME gives its identity; one
\ read serves both, so a login rewritten meanwhile cannot land under
\ another's name
: PUT-LIVE ( n -- ) {: p :}
   p LIVE-LOGIN {: la lu pa pu got :}
   got 0= if exit then
   p ID-LIVE DB-LIVE-NAME LIVE-ROW LIVE-ROW-U NAME-CAP SPAN!
   p LIVE-ROW$ ID-LIVE la lu pa pu false DB-PUT ;

\ saves the live login under its name. E-SW-UNRESTORED or E-SW-MIXED, with
\ nothing saved, while an add's record of the live login waits or the live
\ Claude files name different accounts. The checks and the read run in the
\ transaction that saves, so no half of another install is saved.
: SAVE-LIVE-ROW ( n -- ) {: p :}
   0 LIVE-ROW-U !
   [: p REQUIRE-RESTORED
      p LIVE-MIXED? if E-SW-MIXED throw then
      p PUT-LIVE ;] DB-WRITE ;

\ E-SW-NO-ACCOUNT when there is no such saved login
: FORGET-ROW ( n ptr u8 n -- ) {: p a u :}
   [: p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
      p a u DB-REMOVE ;] DB-WRITE ;

\ ---- installing a saved login ----------------------------------------------
create SWAP-NAME NAME-CAP allot   variable SWAP-NAME-U
create HELD-CLAIM 32 allot        variable HELD-CLAIM-U
variable SWAP-SETTLED             \ bool: no install was pending before this one
variable SWAP-RC                  \ what the failed live write threw

: SWAP$ ( -- ptr u8 n ) SWAP-NAME SWAP-NAME-U @ ;
: CLAIM$ ( -- ptr u8 n ) HELD-CLAIM HELD-CLAIM-U @ ;

\ the completed install of the name, whose row's identity is in ID-SLOT, at
\ the clock's time once the live files are written
: NOTE-SWITCH ( n ptr u8 n -- ) {: p a u :}
   DB-NOW-US {: at :}
   p a u ID-SLOT at DB-APPEND-SWITCH
   p a u at 1000000 / true DB-NOTE-INSTALLED ;

\ the row's profile into OBJ and login into SDOC, both checked, and its
\ identity into ID-SLOT
: CLAUDE-ROW ( -- )
   P-CLAUDE SWAP$ DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   0 DB-ROW-PROFILE$ {: pa pu :}
   pu 0 < if E-SW-MISMATCH throw then
   pa pu OBJ-BUF OBJ-U BUF-CAP SPAN!
   OBJ$ CHECK-OBJECT
   SWAP$ CHECK-SLOT-EMAIL
   0 DB-ROW-LOGIN$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   SDOC$ CHECK-CREDS
   0 ID-SLOT ROW-IDENTITY ;

\ what installing SWAP$ writes, and the live state it replaces: the config
\ in CFG and the credentials in FILE (length -1 for none), whether an
\ install was pending, and the spliced config in OUT
: CLAUDE-PREPARE ( -- )
   CLAUDE-ROW
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-OPT 2drop
   CLAUDE-CREDS$ FILE-BUF FILE-U READ-OPT 2drop
   P-CLAUDE DB-PENDING nip nip 0= SWAP-SETTLED !
   CLAUDE-SPLICED ;

\ The live writes run in one transaction that first checks the claim is
\ still this install's. A failed write puts the earlier config back; the
\ claim is cleared only when the live files are known to be the pair from
\ before, and the write's throw comes once the transaction commits.
ENUM swap-state owning configuring crediting restoring swapped broken ;ENUM
ENUM own-input mine theirs ;ENUM
ENUM put-input wrote refused ;ENUM
ENUM restore-input known unknown ;ENUM

: SWAP-OWN ( n -- own-input ) {: p :}
   p CLAIM$ DB-OWNS? if construct own-input mine exit then
   construct own-input theirs ;

: SWAP-SUPERSEDED ( n -- ) drop E-SW-SUPERSEDED throw ;

: AFTER-TRY ( n put-input -- n put-input )
   drop OUT$ PUT-CONFIG construct put-input wrote ;

: SWAP-AFTER ( n -- put-input )
   construct put-input refused [: AFTER-TRY ;] catch
   dup 0= if drop nip exit then
   SWAP-RC ! 2drop construct put-input refused ;

: LOGIN-TRY ( n put-input -- n put-input )
   drop SDOC$ PUT-CREDS construct put-input wrote ;

: SWAP-LOGIN ( n -- put-input )
   construct put-input refused [: LOGIN-TRY ;] catch
   dup 0= if drop nip exit then
   SWAP-RC ! 2drop construct put-input refused ;

: RESTORE-TRY ( n restore-input -- n restore-input )
   drop CFG$ PUT-CONFIG
   SWAP-SETTLED @ 0= if construct restore-input unknown exit then
   CREDS-BACK? if construct restore-input known exit then
   construct restore-input unknown ;

\ a config that cannot go back, or credentials that cannot be read, leave
\ the live files unknown, whatever was thrown
: SWAP-RESTORE ( n -- restore-input )
   construct restore-input unknown [: RESTORE-TRY ;] catch
   dup 0= if drop nip exit then
   drop 2drop construct restore-input unknown ;

: SWAP-CLEAR ( n -- ) CLAIM$ DB-CLEAR-PENDING ;

\ the switch, the installed name and time, and the claim's end commit together
: SWAP-RECORD ( n -- ) {: p :}
   p SWAP$ NOTE-SWITCH
   p CLAIM$ DB-CLEAR-PENDING ;

FSM:DEFINE SWAPPING ( n ) swap-state put-input
   IN owning SWAP-OWN ( own-input )
      mine    -                >configuring
      theirs  SWAP-SUPERSEDED  >broken
   IN configuring SWAP-AFTER
      wrote   -                >crediting
      refused -                >restoring
   IN crediting SWAP-LOGIN
      wrote   -                >swapped
      refused -                >restoring
   IN restoring SWAP-RESTORE ( restore-input )
      known   SWAP-CLEAR       >broken
      unknown -                >broken
   FINAL swapped SWAP-RECORD
   FINAL broken  -
;DEFINE

\ The checks, the reads of what the install replaces and the splice end in
\ the pending claim, committed before either live file changes.
ENUM install-state claiming swapping installed failed ;ENUM
ENUM claim-input claimed ;ENUM
ENUM swap-input done broke ;ENUM

: SWAP-NOTE ( n -- claim-input ) {: p :}
   [: CLAUDE-PREPARE
      p SWAP$ DB-NOTE-PENDING HELD-CLAIM HELD-CLAIM-U 32 SPAN! ;] DB-WRITE
   construct claim-input claimed ;

: SWAP-WRITE ( n -- swap-input ) {: p :}
   0 SWAP-RC !
   [: p construct swap-state owning SWAPPING ;] DB-WRITE
   SWAP-RC @ 0= if construct swap-input done exit then
   construct swap-input broke ;

: SWAP-RETHROW ( n -- ) drop SWAP-RC @ throw ;

FSM:DEFINE INSTALLING ( n ) install-state swap-input
   IN claiming SWAP-NOTE ( claim-input )
      claimed -             >swapping
   IN swapping SWAP-WRITE
      done    -             >installed
      broke   -             >failed
   FINAL installed -
   FINAL failed    SWAP-RETHROW
;DEFINE

\ The row must exist (E-SW-NO-ACCOUNT), its profile name an email the name
\ belongs to (E-SW-MISMATCH) and its login hold a claudeAiOauth object
\ (E-SW-JSON). Any throw but a failed live write's, once the claim is noted,
\ leaves it pending, which CLAUDE-LIVE-MIXED? then reports.
: CLAUDE-INSTALL ( ptr u8 n -- )
   SWAP-NAME SWAP-NAME-U NAME-CAP SPAN!
   P-CLAUDE construct install-state claiming INSTALLING ;

\ one transaction, so the row read is the row installed: it must exist
\ (E-SW-NO-ACCOUNT) and name an email the name belongs to (E-SW-MISMATCH)
: CODEX-SWITCH ( ptr u8 n -- ) {: a u :}
   P-CODEX a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   0 DB-ROW-LOGIN$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   SDOC$ ID-SLOT CODEX-IDENTITY 0= if E-SW-JSON throw then
   a u ID-SLOT EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then
   0 ID-SLOT ROW-IDENTITY
   SDOC$ PUT-AUTH
   P-CODEX a u NOTE-SWITCH ;

: CODEX-INSTALL ( ptr u8 n -- ) {: a u :}
   [: a u CODEX-SWITCH ;] DB-WRITE ;

\ makes the saved login live and records the switch
: INSTALL ( n ptr u8 n -- ) {: p a u :}
   p case
     P-CLAUDE of a u CLAUDE-INSTALL endof
     P-CODEX of a u CODEX-INSTALL endof
     E-SW-PROVIDER throw
   endcase ;

;package
