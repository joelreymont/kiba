\ sw-store.f - saved logins moved between the account store and the live
\ files.
require ../src/sw-claude.f
require ../src/sw-codex.f
require ../src/sw-db.f
require ../src/sw-base.f
require ../src/sw-paths.f
require ../src/sw-io.f
require ../src/sw-json.f
require ../src/sw-identity.f
require src/lib/fsm.f
require src/lib/prelude.f

package SW

\ ---- saved logins and the live files ---------------------------------------
\ The caller holds the provider's turn; every store change runs in DB-WRITE.
private

create LIVE-ROW NAME-CAP allot   variable LIVE-ROW-U

\ the name PUT-LIVE last saved under; its callers empty it first, so it is
\ empty when there was no login
: LIVE-ROW$ ( -- ptr u8 n ) LIVE-ROW LIVE-ROW-U @ ;

\ the live login as one read: its login and profile (length -1 for none),
\ the identity in ID-LIVE; false when there is none
: LIVE-LOGIN ( n -- ptr u8 n ptr u8 n bool )
   case
     P-CLAUDE of CLAUDE-LIVE-LOGIN endof
     P-CODEX of CODEX-LIVE-LOGIN endof
     E-SW-PROVIDER throw
   endcase ;

public

\ LIVE-LOGIN's answer alone: the identity in ID-LIVE; false when there is none
: LIVE-IDENTITY ( n -- bool )
   LIVE-LOGIN {: la lu pa pu got :} got ;

private

\ only Claude keeps the account and the tokens in two files that can disagree
: LIVE-MIXED? ( n -- bool )
   P-CLAUDE = if CLAUDE-LIVE-MIXED? exit then
   false ;

\ puts the live login under the name DB-LIVE-NAME gives its identity; one
\ read serves both, so a login rewritten meanwhile cannot land under
\ another's name
: PUT-LIVE ( n -- ) {: p :}
   p LIVE-LOGIN {: la lu pa pu got :}
   got 0= if exit then
   p ID-LIVE DB-LIVE-NAME LIVE-ROW LIVE-ROW-U NAME-CAP SPAN!
   p LIVE-ROW$ ID-LIVE la lu pa pu false DB-PUT ;

\ E-SW-MIXED, saving nothing, while the live Claude files name different
\ accounts; checked and read in the saving transaction, never mid-install
: SAVE-LIVE-ROW ( n -- ) {: p :}
   0 LIVE-ROW-U !
   [: p LIVE-MIXED? if E-SW-MIXED throw then
      p PUT-LIVE ;] DB-WRITE ;

\ E-SW-NO-ACCOUNT when there is no such saved login
: FORGET-ROW ( n ptr u8 n -- ) {: p a u :}
   [: p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
      p a u DB-REMOVE ;] DB-WRITE ;

\ ---- installing a saved login ----------------------------------------------
create SWAP-NAME NAME-CAP allot   variable SWAP-NAME-U
variable SWAP-SETTLED             \ bool: no install was pending before this one
variable SWAP-RC                  \ what the failed live write threw

: SWAP$ ( -- ptr u8 n ) SWAP-NAME SWAP-NAME-U @ ;

\ the completed install of the name, noted at the clock's time once the
\ live files are written
: NOTE-SWITCH ( n ptr u8 n -- ) {: p a u :}
   p a u epoch-seconds true DB-NOTE-INSTALLED ;

\ the row's profile into OBJ and login into SDOC, both checked
: CLAUDE-ROW ( -- )
   P-CLAUDE SWAP$ DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   0 DB-ROW-PROFILE$ {: pa pu :}
   pu 0 < if E-SW-MISMATCH throw then
   pa pu OBJ-BUF OBJ-U BUF-CAP SPAN!
   OBJ$ CHECK-OBJECT
   SWAP$ CHECK-SLOT-EMAIL
   0 DB-ROW-LOGIN$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   SDOC$ CHECK-CREDS ;

\ what installing SWAP$ writes, and the live state it replaces: the config
\ in CFG and the credentials in FILE (length -1 for none), whether an
\ install was pending, and the spliced config in OUT
: CLAUDE-PREPARE ( -- )
   CLAUDE-ROW
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-OPT 2drop
   CLAUDE-CREDS$ FILE-BUF FILE-U READ-OPT 2drop
   P-CLAUDE DB-PENDING nip nip 0= SWAP-SETTLED !
   CLAUDE-SPLICED ;

\ A failed live write puts the earlier config back, clears the marker only
\ when the pair from before is known, and is rethrown after the commit
ENUM swap-state configuring crediting restoring swapped broken ;ENUM
ENUM put-input wrote refused ;ENUM
ENUM restore-input known unknown ;ENUM

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

\ the installed name and time and the marker's end commit together
: SWAP-RECORD ( n -- ) {: p :}
   p SWAP$ NOTE-SWITCH
   p DB-CLEAR-PENDING ;

FSM:DEFINE SWAPPING ( n ) swap-state put-input
   IN configuring SWAP-AFTER
      wrote   -                >crediting
      refused -                >restoring
   IN crediting SWAP-LOGIN
      wrote   -                >swapped
      refused -                >restoring
   IN restoring SWAP-RESTORE ( restore-input )
      known   DB-CLEAR-PENDING >broken
      unknown -                >broken
   FINAL swapped SWAP-RECORD
   FINAL broken  -
;DEFINE

\ The checks, the reads of what the install replaces and the splice end in
\ the pending marker, committed before either live file changes.
ENUM install-state noting swapping installed failed ;ENUM
ENUM note-input noted ;ENUM
ENUM swap-input done broke ;ENUM

: SWAP-NOTE ( n -- note-input ) {: p :}
   [: CLAUDE-PREPARE
      p SWAP$ DB-NOTE-PENDING ;] DB-WRITE
   construct note-input noted ;

: SWAP-WRITE ( n -- swap-input ) {: p :}
   0 SWAP-RC !
   [: p construct swap-state configuring SWAPPING ;] DB-WRITE
   SWAP-RC @ 0= if construct swap-input done exit then
   construct swap-input broke ;

: SWAP-RETHROW ( n -- ) drop SWAP-RC @ throw ;

FSM:DEFINE INSTALLING ( n ) install-state swap-input
   IN noting SWAP-NOTE ( note-input )
      noted -             >swapping
   IN swapping SWAP-WRITE
      done    -             >installed
      broke   -             >failed
   FINAL installed -
   FINAL failed    SWAP-RETHROW
;DEFINE

\ E-SW-NO-ACCOUNT, E-SW-MISMATCH or E-SW-JSON for a row unfit to install;
\ once noted, any throw but a failed live write's leaves the marker pending
: CLAUDE-INSTALL ( ptr u8 n -- )
   SWAP-NAME SWAP-NAME-U NAME-CAP SPAN!
   P-CLAUDE construct install-state noting INSTALLING ;

\ one transaction, so the row read is the row installed: it must exist
\ (E-SW-NO-ACCOUNT) and name an email the name belongs to (E-SW-MISMATCH)
: CODEX-SWITCH ( ptr u8 n -- ) {: a u :}
   P-CODEX a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   0 DB-ROW-LOGIN$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   SDOC$ ID-SLOT CODEX-IDENTITY 0= if E-SW-JSON throw then
   a u ID-SLOT EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then
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
