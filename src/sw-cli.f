\ sw-cli.f - the kiba commands: status, usage, save, use, add, forget, redeem.
require ../src/sw-store.f
require ../src/sw-run.f
require ../src/sw-usage.f
require ../src/sw-db.f
require ../src/sw-status.f
require ../src/sw-turn.f
require src/lib/fsm.f
require src/lib/fmt.f

package SW

\ ---- reasons ----------------------------------------------------------------
\ the switch E-SW-UNREPAIRED names: its provider and the name it installs
variable UNREPAIRED-P
create UNREPAIRED-NAME NAME-CAP allot   variable UNREPAIRED-NAME-U
\ the account a redeem was asked to spend a reset of
create REDEEM-NAME NAME-CAP allot   variable REDEEM-NAME-U

public

: UNREPAIRED-REASON$ ( -- ptr u8 n )
   SB-RESET s" kiba: the " SB-APPEND UNREPAIRED-P @ PROVIDER$ SB-APPEND
   s"  switch to " SB-APPEND UNREPAIRED-NAME UNREPAIRED-NAME-U @ SB-APPEND
   s"  did not finish; nothing is probed or refreshed until a switch completes" SB-APPEND SB$ ;

: NO-RESETS-REASON$ ( -- ptr u8 n )
   SB-RESET s" kiba: no limit resets are available for " SB-APPEND
   REDEEM-NAME REDEEM-NAME-U @ SB-APPEND SB$ ;

: REMOTE-REASON$ ( -- ptr u8 n )
   SB-RESET s" kiba: " SB-APPEND REMOTE-NOTE$ SB-APPEND SB$ ;

\ CLAUDE-CONFIG$ builds through the same string builder, so it goes first
: ORPHAN-REASON$ ( -- ptr u8 n )
   CLAUDE-CONFIG$ {: c cu :}
   SB-RESET s" kiba: Claude credentials exist but " SB-APPEND c cu SB-APPEND
   s"  is missing: nothing is probed or switched until it names their account" SB-APPEND SB$ ;

: REASON$ ( n -- ptr u8 n ) {: rc :}
   rc E-SW-PROVIDER = if s" kiba: provider must be claude or codex" exit then
   rc E-SW-NO-LIVE = if s" kiba: no live login to save" exit then
   rc E-SW-NO-ACCOUNT = if s" kiba: no such saved account" exit then
   rc E-SW-NAME = if s" kiba: account name has unsafe characters" exit then
   rc E-SW-JSON = if s" kiba: a login file is missing an expected field" exit then
   rc E-SW-LOGIN = if s" kiba: provider login did not complete" exit then
   rc E-SW-CAPACITY = if SB-RESET s" kiba: too many: " SB-APPEND TOO-MANY$ SB-APPEND SB$ exit then
   rc E-SW-NO-CLI = if s" kiba: provider command is not on PATH" exit then
   rc E-SW-BASE64 = if s" kiba: id_token is not base64url" exit then
   rc E-SW-ENV = if s" kiba: HOME is not set" exit then
   rc E-SW-MISMATCH = if s" kiba: the saved login belongs to a different account than its name" exit then
   rc E-SW-UNRESTORED = if s" kiba: the live login waits to be put back after an add; a new add does it" exit then
   rc E-SW-SUPERSEDED = if s" kiba: another Claude switch began before this one wrote anything; this one changed nothing" exit then
   rc E-SW-ORPHAN-LIVE = if ORPHAN-REASON$ exit then
   rc E-SW-UNREPAIRED = if UNREPAIRED-REASON$ exit then
   rc E-SW-MIXED = if s" kiba: the live Claude files name different accounts; switch to an account to repair them" exit then
   rc E-SW-DB = if SB-RESET s" kiba: the account database refused: " SB-APPEND DB-ERROR$ SB-APPEND SB$ exit then
   rc E-SW-DB-VERSION = if s" kiba: the account store is from a newer kiba; upgrade kiba" exit then
   rc E-SW-TURN-BUSY = if s" kiba: another kiba holds that provider's turn" exit then
   rc E-SW-NO-RESETS = if NO-RESETS-REASON$ exit then
   rc E-SW-REMOTE = if REMOTE-REASON$ exit then
   rc E-JSON-READ-STATE = if s" kiba: a login field is longer than kiba can hold" exit then
   rc E-STR-CAPACITY = if s" kiba: a path or name is too long" exit then
   rc E-FS-OPEN = if s" kiba: cannot open a login file" exit then
   rc E-FS-IO = if s" kiba: a file read, write, or rename failed" exit then
   rc E-FS-CAPACITY = rc E-SPAN-CAPACITY = or rc E-SPAN-RANGE = or if s" kiba: a login file or path is too large" exit then
   rc E-FS-PATH-UNSAFE = if s" kiba: refusing to write through a symlink chain" exit then
   rc E-PROC-SPAWN = if s" kiba: could not start the provider command" exit then
   rc E-JSON-READ-LAST >= rc E-JSON-READ-FIRST <= and if s" kiba: a login file is not valid JSON" exit then
   rc E-FS-LAST >= rc E-FS-FIRST <= and if s" kiba: a file operation failed" exit then
   rc E-PROC-LAST >= rc E-PROC-FIRST <= and if s" kiba: could not run a command" exit then
   SB-RESET s" kiba: error code " SB-APPEND rc FMT:SB-INT SB$ ;

private

\ rc's reason without its "kiba: " prefix: for a line that already starts
\ with its provider, and for an account's note, as kiba-mac records it
: BARE-REASON$ ( n -- ptr u8 n )
   REASON$ {: a u :}
   s" kiba: " {: k ku :}
   a u k ku STARTS-WITH? 0= if a u exit then
   a ku + u ku - ;

\ ---- status: text -----------------------------------------------------------
\ Each provider is rendered right after its read: the row table, ID-LIVE and
\ the usage record hold that provider until the next store read.
: .PLAN ( ptr u8 n -- ) {: a u :}
   u 0= if exit then
   s"  (" type a u type s" )" type ;

: .FIGURES ( n -- ) {: p :}
   p FIGURES-TEXT {: a u :}
   u 0= if exit then
   s"   " type a u type ;

: .ACCOUNT ( n n -- ) {: p i :}
   i STATUS-ACTIVE? if s"   * " else s"     " then type
   i DB-ROW-NAME$ type
   i DB-ROW-USAGE {: probed :}
   i probed SHOWN-PLAN$ .PLAN
   probed if p .FIGURES then
   cr ;

: .LIVE ( -- )
   STATUS-ERROR 0<> if STATUS-ERROR REASON$ type cr exit then
   STATUS-LIVE? if ID-LIVE EMAIL$ type ID-LIVE PLAN$ .PLAN cr exit then
   s" no live login" type cr ;

: .PROVIDER ( n -- ) {: p :}
   p STATUS-READ
   p PROVIDER$ type s" : " type .LIVE
   STATUS-ROWS 0 ?do p i .ACCOUNT loop ;

: STATUS-TEXT ( -- )
   P-COUNT 0 ?do i .PROVIDER loop ;

\ ---- status: json -----------------------------------------------------------
\ kiba-mac's snapshot as its JSONEncoder writes it, keys sorted, members
\ that are nil left out, and each limit given the percent left its figure
\ shows. It is written with the usage record's encoder words into their
\ buffer, which no store read touches.
: ENC-BOOL ( bool -- )
   if s" true" else s" false" then ENC+ ;

: SNAP-LIMIT ( n -- ) {: k :}
   $7B ENC-C
   s" label" ENC-KEY k DB-LIMIT-LABEL$ ENC-STR ENC-COMMA
   k WINDOW-FIGURE if s" left" ENC-KEY ENC-INT ENC-COMMA else drop then
   s" percent" ENC-KEY k DB-LIMIT-PERCENT ENC-INT ENC-COMMA
   s" resetsAt" ENC-KEY k DB-LIMIT-RESETS$ ENC-STR
   $7D ENC-C ;

\ ENC-TAIL writes the record's note, reset offer and state and closes it
: SNAP-USAGE ( n -- ) {: p :}
   p FIGURES
   s" usage" ENC-KEY $7B ENC-C
   s" fetchedAt" ENC-KEY DB-USAGE-AT ENC-INT ENC-COMMA
   s" limits" ENC-KEY $5B ENC-C
   DB-LIMIT# 0 ?do
      i 0 > if ENC-COMMA then
      i SNAP-LIMIT
   loop
   $5D ENC-C ENC-COMMA
   ENC-TAIL ;

: SNAP-ACCOUNT ( n n -- ) {: p i :}
   i 0 > if ENC-COMMA then
   $7B ENC-C
   s" active" ENC-KEY i STATUS-ACTIVE? ENC-BOOL ENC-COMMA
   s" name" ENC-KEY i DB-ROW-NAME$ ENC-STR ENC-COMMA
   s" plan" ENC-KEY i DB-ROW-PLAN$ ENC-STR
   i DB-ROW-USAGE if ENC-COMMA p SNAP-USAGE then
   $7D ENC-C ;

: SNAP-ERROR ( -- )
   STATUS-ERROR 0= if exit then
   ENC-COMMA s" error" ENC-KEY STATUS-ERROR REASON$ ENC-STR ;

: SNAP-AT ( -- )
   STATUS-AT 0= if drop exit then
   ENC-COMMA s" installedAt" ENC-KEY ENC-INT ;

: SNAP-LIVE ( -- )
   STATUS-LIVE? 0= if exit then
   ENC-COMMA s" live" ENC-KEY $7B ENC-C
   s" email" ENC-KEY ID-LIVE EMAIL$ ENC-STR ENC-COMMA
   s" plan" ENC-KEY ID-LIVE PLAN$ ENC-STR
   $7D ENC-C ;

: SNAP-PROVIDER ( n -- ) {: p :}
   p STATUS-READ
   p 0 > if ENC-COMMA then
   $7B ENC-C
   s" accounts" ENC-KEY $5B ENC-C
   STATUS-ROWS 0 ?do p i SNAP-ACCOUNT loop
   $5D ENC-C
   SNAP-ERROR SNAP-AT SNAP-LIVE
   ENC-COMMA s" provider" ENC-KEY p PROVIDER$ ENC-STR
   $7D ENC-C ;

public

\ the snapshot of every provider, read from the open store
: STATUS-JSON$ ( -- ptr u8 n )
   0 ENC-U !
   $7B ENC-C s" providers" ENC-KEY $5B ENC-C
   P-COUNT 0 ?do i SNAP-PROVIDER loop
   $5D ENC-C $7D ENC-C
   ENC$ ;

private

: STATUS-JSON ( -- )
   STATUS-JSON$ type cr ;

: STATUS-SHOW ( bool -- )
   if STATUS-JSON exit then
   STATUS-TEXT ;

\ ---- save / use / forget ----------------------------------------------------
\ Every command that changes or probes a provider's logins opens the account
\ store for itself and holds the provider's turn throughout; both are left on
\ every path.
: WITH-STORE ( [ -- ] -- ) {: body :}
   DB-OPEN [: body execute ;] [: DB-CLOSE ;] finally ;

: IN-TURN ( n [ -- ] -- ) {: p body :}
   p TURN-ENTER [: body execute ;] [: p TURN-LEAVE ;] finally ;

: STORE-TURN ( n [ -- ] -- ) {: p body :}
   [: p body IN-TURN ;] WITH-STORE ;

: .SAVED ( n -- ) {: p :}
   p PROVIDER$ type
   LIVE-ROW$ nip 0= if s" : no live login" type cr exit then
   s" : saved " type LIVE-ROW$ type cr ;

: SAVE-ONE ( n -- ) {: p :}
   p [: p SAVE-LIVE-ROW ;] STORE-TURN
   p .SAVED ;

\ use's save-back: the live login is saved first so its refreshed tokens are
\ kept, and noted as installed, since the live files hold its login. Mixed
\ live files are left for the install to repair; any other failure stops
\ the switch before anything is written, so no login is overwritten unsaved.
ENUM back-state saving kept stopped ;ENUM
ENUM back-input saved absent mixed refused ;ENUM
variable BACK-RC

: BACK-TRY ( n back-input -- n back-input )
   drop dup SAVE-LIVE-ROW
   LIVE-ROW$ nip 0= if construct back-input absent exit then
   construct back-input saved ;

: BACK-SENSE ( n -- back-input )
   construct back-input refused [: BACK-TRY ;] catch
   dup 0= if drop nip exit then
   dup E-SW-MIXED = if drop 2drop construct back-input mixed exit then
   BACK-RC ! 2drop construct back-input refused ;

: BACK-NOTE ( n -- ) {: p :}
   [: p LIVE-ROW$ 0 false DB-NOTE-INSTALLED ;] DB-WRITE ;

: BACK-RETHROW ( n -- ) drop BACK-RC @ throw ;

FSM:DEFINE SAVE-BACK-ROW ( n ) back-state back-input
   IN saving BACK-SENSE
      saved   BACK-NOTE  >kept
      absent  -          >kept
      mixed   -          >kept
      refused -          >stopped
   FINAL kept    -
   FINAL stopped BACK-RETHROW
;DEFINE

\ ---- probing saved logins ----------------------------------------------------
\ The saved names whose tokens the CLI is using: the live identity's name
\ and, while the live Claude files are mixed, the installed name, whose
\ tokens are still the live credentials. E-SW-UNRESTORED while an add's
\ record of the live login waits; E-SW-UNREPAIRED while an install is
\ pending: a failed repair may have left any saved login's tokens live, so
\ no saved name is known not to be live until a switch completes.
create LIVE-A NAME-CAP allot   variable LIVE-A-U    \ -1 when none
create LIVE-B NAME-CAP allot   variable LIVE-B-U    \ -1 when none

: UNREPAIRED ( n ptr u8 n -- ) {: p a u :}
   p UNREPAIRED-P !
   a u UNREPAIRED-NAME UNREPAIRED-NAME-U NAME-CAP SPAN!
   E-SW-UNREPAIRED throw ;

: REQUIRE-REPAIRED ( n -- ) {: p :}
   p DB-PENDING {: a u pending :}
   pending if p a u UNREPAIRED then ;

: INSTALLED-LIVE ( n -- )
   DB-INSTALLED {: a u has :}
   has if a u LIVE-B LIVE-B-U NAME-CAP SPAN! then ;

: LIVE-NAMES ( n bool -- ) {: p mixed :}
   -1 LIVE-A-U ! -1 LIVE-B-U !
   p REQUIRE-RESTORED
   p LIVE-IDENTITY if p ID-LIVE DB-LIVE-NAME LIVE-A LIVE-A-U NAME-CAP SPAN! then
   p REQUIRE-REPAIRED
   mixed if p INSTALLED-LIVE then ;

: LIVE-NAME? ( ptr u8 n -- bool ) {: a u :}
   LIVE-A-U @ 0 >= if a u LIVE-A LIVE-A-U @ STR= if true exit then then
   LIVE-B-U @ 0 >= if a u LIVE-B LIVE-B-U @ STR= exit then
   false ;

: PROBE-KEEP ( n n bool -- n n bool ) {: p r live :}
   p r DB-ROW-LOGIN$ live PROBE
   p r live ;

\ row r probed; a probe that throws is the account's error outcome
: OUTCOME ( n n bool -- ) {: p r live :}
   p r live [: PROBE-KEEP ;] catch {: rc :} 2drop drop
   rc 0<> if rc BARE-REASON$ PROBE-FAILED then ;

: LOGIN-CHANGED? ( n -- bool ) {: r :}
   PROBE-RENEWED? 0= if false exit then
   SDOC$ r DB-ROW-LOGIN$ STR= 0= ;

\ ID-SLOT carries the plan the provider named, when it named one
: PLAN-OVER ( -- )
   PROBED-PLAN$ {: a u :}
   u 0 < if exit then
   a u ID-SLOT PLAN-ROW ID-SLOT F-PLAN LEN-CELL PLAN-CAP SPAN! ;

\ row r's outcome in one transaction: the usage record and the plan the
\ provider named, any refreshed login, and the usage event under the plan
\ committed with it; live is whether the probe read the login as live. A
\ login the provider revoked keeps its row, listed until it is forgotten.
: RECORD ( n n bool -- ) {: p r live :}
   r ID-SLOT ROW-IDENTITY
   PLAN-OVER
   DB-NOW-US {: at :}
   r DB-ROW-NAME$ {: a u :}
   r LOGIN-CHANGED? {: changed :}
   [: p a u PROBED-PLAN$ DB-SET-USAGE
      changed if p a u SDOC$ DB-SET-LOGIN then
      p a u ID-SLOT live at DB-APPEND-USAGE ;] DB-WRITE ;

\ probes the saved login a u and records the outcome, for an operation that
\ holds p's turn; E-SW-NO-ACCOUNT when there is no such login
: PROBE-IN-TURN ( n ptr u8 n bool -- ) {: p a u live :}
   p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   p 0 live OUTCOME
   p 0 live RECORD ;

create OLD-NAME NAME-CAP allot   variable OLD-NAME-U

\ after the install the new login is probed as live, then the login saved
\ back as saved: its usage came from a live probe, which never refreshes
: USE-RUN ( n ptr u8 n -- ) {: p a u :}
   p construct back-state saving SAVE-BACK-ROW
   LIVE-ROW$ OLD-NAME OLD-NAME-U NAME-CAP SPAN!
   p a u INSTALL
   p a u true PROBE-IN-TURN
   OLD-NAME OLD-NAME-U @ {: o ou :}
   ou 0= if exit then
   o ou a u STR= if exit then
   p o ou false PROBE-IN-TURN ;

\ ---- usage --------------------------------------------------------------------
\ Every saved login of one provider probed and recorded, inside its turn. A
\ save-back failure is reported and the probe goes on; a provider whose turn
\ cannot be taken, whose logins cannot be read, whose install is pending or
\ whose add's live login waits to go back is not probed at all. The live
\ login is probed as live, so its tokens are never refreshed; no outcome
\ removes a login. When every saved login was probed after the second the
\ run began, another holder's probe answered it while this one waited.
ENUM usage-step checking saving listing probing reported failed ;ENUM
ENUM check-input answered stale threw ;ENUM
ENUM list-input listed threw ;ENUM
ENUM probe-input recorded unrecorded finished ;ENUM
ENUM usage-turn entering left ;ENUM
ENUM turn-input ran refused ;ENUM

variable USAGE-ASKED                \ epoch second the run began
variable USAGE-MIXED                \ bool: the save-back found the live Claude files mixed
variable USAGE-ROW                  \ the row being probed
variable USAGE-RC                   \ what the last failed step threw
variable USAGE-FAILED               \ bool: a provider reported an error
create BACK-ERR 1024 allot   variable BACK-ERR-U   \ the save-back error; empty when none
DYNAMIC-BUFFER FAULTS u8     variable FAULTS-U     \ the provider error; empty when none

: FAULTS$ ( -- ptr u8 n ) 0 FAULTS FAULTS-U @ ;

: FAULTS-RESET ( -- ) 0 FAULTS-U ! 1 FAULTS-RESERVE ;

: FAULT+ ( ptr u8 n -- ) {: a u :}
   u 0= if exit then
   FAULTS-U @ u + FAULTS-RESERVE
   a FAULTS-U @ FAULTS u BYTE-COPY
   FAULTS-U @ u + FAULTS-U ! ;

: FAULT-NEXT ( -- ) FAULTS-U @ 0 > if s" ; " FAULT+ then ;

\ provider p's account: its name, then its windows, or its note when none
: .USAGE ( n ptr u8 n -- ) {: p a u :}
   p PROVIDER$ type s" : " type a u type s"   " type
   DB-LIMIT# 0= if DB-USAGE-NOTE$ type cr exit then
   .LIMITS cr ;

\ every saved row holds a record fetched after the run began
: ALL-PROBED? ( -- bool )
   DB-ROW# 0= if false exit then
   DB-ROW# 0 ?do
      i DB-ROW-USAGE 0= if false unloop exit then
      DB-USAGE-AT USAGE-ASKED @ <= if false unloop exit then
   loop
   true ;

\ 1 when the recorded outcomes answer the run; the live names and the list
\ are read again for them
: CHECK-RUN ( n -- n ) {: p :}
   p DB-LIST
   ALL-PROBED? 0= if 0 exit then
   p p LIVE-MIXED? LIVE-NAMES
   p DB-LIST
   1 ;

: CHECK-SENSE ( n -- check-input )
   [: CHECK-RUN ;] catch {: rc :}
   rc 0<> if drop rc USAGE-RC ! construct check-input threw exit then
   0<> if construct check-input answered exit then
   construct check-input stale ;

: ROWS-RUN ( n -- n ) {: p :}
   p USAGE-MIXED @ LIVE-NAMES
   p DB-LIST
   0 USAGE-ROW !
   p ;

: ROWS-SENSE ( n -- list-input )
   [: ROWS-RUN ;] catch {: rc :} drop
   rc 0= if construct list-input listed exit then
   rc USAGE-RC ! construct list-input threw ;

: ROW-RUN ( n -- n ) {: p :}
   USAGE-ROW @ {: r :}
   r DB-ROW-NAME$ LIVE-NAME? {: live :}
   p r live OUTCOME
   p r live RECORD
   p ;

: ROW-SENSE ( n -- probe-input )
   USAGE-ROW @ DB-ROW# >= if drop construct probe-input finished exit then
   [: ROW-RUN ;] catch {: rc :} drop
   rc 0= if construct probe-input recorded exit then
   rc USAGE-RC ! construct probe-input unrecorded ;

: .RECORDED ( n -- ) {: p :}
   DB-ROW# 0 ?do
      i DB-ROW-USAGE drop
      p i DB-ROW-NAME$ .USAGE
   loop ;

: NOTE-BACK ( n -- ) drop
   BACK-RC @ BARE-REASON$ BACK-ERR BACK-ERR-U 1024 SPAN! ;

: NOTE-MIXED ( n -- )
   true USAGE-MIXED !
   E-SW-MIXED BACK-RC !
   NOTE-BACK ;

: NOTE-FAILURE ( n -- ) drop
   FAULT-NEXT USAGE-RC @ BARE-REASON$ FAULT+ ;

: .ROW ( n -- ) {: p :}
   p USAGE-ROW @ DB-ROW-NAME$ .USAGE
   1 USAGE-ROW +! ;

: NOTE-UNRECORDED ( n -- ) drop
   FAULT-NEXT
   USAGE-ROW @ DB-ROW-NAME$ FAULT+ s" : usage not recorded: " FAULT+
   USAGE-RC @ BARE-REASON$ FAULT+
   1 USAGE-ROW +! ;

FSM:DEFINE USAGE-STEPS ( n ) usage-step check-input
   IN checking CHECK-SENSE
      answered    .RECORDED        >reported
      stale       -                >saving
      threw       NOTE-FAILURE     >failed
   IN saving BACK-SENSE ( back-input )
      saved       -                >listing
      absent      -                >listing
      mixed       NOTE-MIXED       >listing
      refused     NOTE-BACK        >listing
   IN listing ROWS-SENSE ( list-input )
      listed      -                >probing
      threw       NOTE-FAILURE     >failed
   IN probing ROW-SENSE ( probe-input )
      recorded    .ROW             >probing
      unrecorded  NOTE-UNRECORDED  >probing
      finished    -                >reported
   FINAL reported -
   FINAL failed -
;DEFINE

: USAGE-IN-TURN ( n -- n ) {: p :}
   p [: p construct usage-step checking USAGE-STEPS ;] STORE-TURN
   p ;

: USAGE-TURN-SENSE ( n -- turn-input )
   [: USAGE-IN-TURN ;] catch {: rc :} drop
   rc 0= if construct turn-input ran exit then
   rc USAGE-RC ! construct turn-input refused ;

FSM:DEFINE USAGE-TURN ( n ) usage-turn turn-input
   IN entering USAGE-TURN-SENSE
      ran         -                >left
      refused     NOTE-FAILURE     >left
   FINAL left -
;DEFINE

\ the save-back error and the provider error each go to stderr as one line
\ that starts with the provider
: .FAULTS ( n -- ) {: p :}
   BACK-ERR-U @ 0 > if
      p PROVIDER$ ERR-PART s" : live login not saved: " ERR-PART BACK-ERR BACK-ERR-U @ ERR-NOTE
      true USAGE-FAILED !
   then
   FAULTS-U @ 0 > if
      p PROVIDER$ ERR-PART s" : " ERR-PART FAULTS$ ERR-NOTE
      true USAGE-FAILED !
   then ;

: USAGE-PROVIDER ( n -- ) {: p :}
   epoch-seconds USAGE-ASKED !
   false USAGE-MIXED ! 0 BACK-ERR-U ! FAULTS-RESET
   p construct usage-turn entering USAGE-TURN
   p .FAULTS ;

public

: CMD-STATUS ( bool -- ) {: json :}
   [: json STATUS-SHOW ;] WITH-STORE ;

\ p < 0 probes every provider; once each has run, E-SW-REPORTED when any
\ reported an error
: CMD-USAGE ( n -- )
   false USAGE-FAILED !
   dup 0 < if drop P-COUNT 0 ?do i USAGE-PROVIDER loop else USAGE-PROVIDER then
   USAGE-FAILED @ if E-SW-REPORTED throw then ;

\ p < 0 saves every provider
: CMD-SAVE ( n -- )
   dup 0 < if drop 0 begin dup P-COUNT < while dup SAVE-ONE 1+ repeat drop exit then
   SAVE-ONE ;

\ saves the live login back, then makes the saved login live
: CMD-USE ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p [: p a u USE-RUN ;] STORE-TURN
   p PROVIDER$ type s" : now " type a u type cr ;

\ ---- redeem ---------------------------------------------------------------------
\ One limit reset of a saved login is spent, then the login is probed again
\ so its usage and offer show the result. Its name is live as usage decides
\ it, so a live login's token is never refreshed; a refreshed one is saved
\ whatever the request came to, since the refresh spent the old grant.
: OFFERED? ( n -- bool )
   DB-ROW-USAGE 0= if false exit then
   DB-RESETS? 0= if false exit then
   DB-RESETS-COUNT 0 > ;

: REDEEM-SAVE ( n n -- ) {: p r :}
   r LOGIN-CHANGED? 0= if exit then
   r DB-ROW-NAME$ {: a u :}
   [: p a u SDOC$ DB-SET-LOGIN ;] DB-WRITE ;

: REDEEM-SPEND ( n n bool -- ) {: p r live :}
   [: p r live REDEEM ;] [: p r REDEEM-SAVE ;] finally ;

\ the live names are read over the row table, so the row is fetched again
: REDEEM-RUN ( n ptr u8 n -- ) {: p a u :}
   p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   0 OFFERED? 0= if E-SW-NO-RESETS throw then
   p p LIVE-MIXED? LIVE-NAMES
   a u LIVE-NAME? {: live :}
   p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   p 0 live REDEEM-SPEND
   p a u live PROBE-IN-TURN ;

\ ---- add: the provider login inside a throwaway home ------------------------------
\ The login command never sees the live login: it runs with its home
\ variable pointing at a private directory under the store, so nothing is
\ read, revoked, or replaced while a session is working. The new login is
\ then saved under its own name and, once the throwaway home is gone, probed
\ as a saved login; switching to it is a separate `use`.
: LOGIN-HOME$ ( n -- ptr u8 n ) s" /login" PSUB$ ;

: SITE$ ( n -- ptr u8 n )
   P-CLAUDE = if s" claude.ai" exit then
   s" chatgpt.com" ;

create LINE-BUF 256 allot

\ the browser decides the account, so the user is told which one to be
\ signed into, or reminded to pick one, and given the moment to arrange it
: ADD-PAUSE ( n ptr u8 n -- ) {: p e eu :}
   s" Sign in to " type
   eu 0 > if e eu NAME-EMAIL type else s" the account to add" type then
   s"  at " type p SITE$ type
   s"  in your browser, then press Enter to continue: " type
   0 LINE-BUF 256 read drop ;

: ADD-BEGIN ( n -- ) {: p :}
   p LOGIN-HOME$ FS:DIR? if p LOGIN-HOME$ FS:REMOVE-TREE then
   p LOGIN-HOME$ ENSURE-PRIVATE
   p LOGIN-HOME$ LOGIN-ROOT!
   p LOGIN-DIR$ ENSURE-PRIVATE ;

\ the throwaway home holds a login's tokens until they are saved; it never
\ outlives the command
: ADD-END ( n -- ) {: p :}
   LOGIN-ROOT-CLEAR
   p LOGIN-HOME$ FS:DIR? if p LOGIN-HOME$ FS:REMOVE-TREE then ;

\ the new login is read from the throwaway home, which LOGIN-ROOT names,
\ and saved under its name; E-SW-NO-LIVE when the login left none
: ADD-IMPORT ( n -- ) {: p :}
   0 LIVE-ROW-U !
   [: p PUT-LIVE ;] DB-WRITE
   LIVE-ROW$ nip 0= if E-SW-NO-LIVE throw then ;

: ADD-RUN ( n ptr u8 n -- ) {: p e eu :}
   p ADD-BEGIN
   p e eu ADD-PAUSE
   p e eu NAME-EMAIL LOGIN 0<> if E-SW-LOGIN throw then
   p ADD-IMPORT ;

: ADD-TURN ( n ptr u8 n -- ) {: p e eu :}
   [: p e eu ADD-RUN ;] [: p ADD-END ;] finally ;

: .ADDED ( n ptr u8 n -- ) {: p e eu :}
   p PROVIDER$ type s" : saved " type LIVE-ROW$ type
   eu 0 > LIVE-ROW$ e eu STR= 0= and if
      s"  (you signed in to a different account than " type e eu type s" )" type
   then
   cr ;

: CMD-ADD ( n ptr u8 n -- ) {: p e eu :}
   p CHECK-LOGIN-CLI
   p [: p e eu ADD-TURN
      p LIVE-ROW$ false PROBE-IN-TURN ;] STORE-TURN
   p e eu .ADDED ;

: LOGIN-HOME-PUBLIC$ ( n -- ptr u8 n ) LOGIN-HOME$ ;

\ what the last redeem came to, for the account a u
: REDEEMED$ ( ptr u8 n -- ptr u8 n ) {: a u :}
   SB-RESET
   RESET-OUTCOME MATCH reset-outcome
      reset OF s" Limit reset for " SB-APPEND a u SB-APPEND ENDOF
      not-limited OF a u SB-APPEND s"  is not at a limit; nothing was spent" SB-APPEND ENDOF
      already-used OF s" That reset was already used" SB-APPEND ENDOF
      no-credit OF s" No limit resets left for " SB-APPEND a u SB-APPEND ENDOF
      cooldown OF
         s" Limit resets are cooling down for " SB-APPEND a u SB-APPEND
         s" ; try again later" SB-APPEND
      ENDOF
      ineligible OF a u SB-APPEND s"  cannot reset its limit" SB-APPEND ENDOF
      unavailable OF
         s" Limit resets are unavailable for " SB-APPEND a u SB-APPEND
         s"  right now" SB-APPEND
      ENDOF
   ;MATCH
   SB$ ;

\ spends one limit reset of the saved login a u
: CMD-REDEEM ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   a u REDEEM-NAME REDEEM-NAME-U NAME-CAP SPAN!
   p [: p a u REDEEM-RUN ;] STORE-TURN
   p PROVIDER$ type s" : " type a u REDEEMED$ type cr ;

: CMD-FORGET ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p [: p a u FORGET-ROW ;] STORE-TURN
   p PROVIDER$ type s" : forgot " type a u type cr ;

;package
