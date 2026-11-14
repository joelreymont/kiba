\ sw-cli.f - the kiba commands: status, usage, save, use, add, forget, redeem.
require ../src/sw-store.f
require ../src/sw-run.f
require ../src/sw-usage.f
require ../src/sw-db.f
require ../src/sw-status.f
require ../src/sw-turn.f
require ../src/sw-base.f
require ../src/sw-paths.f
require ../src/sw-io.f
require ../src/sw-identity.f
require ../src/sw-sqlite.f
require ../src/sw-claude.f
require src/lib/fsm.f
require src/lib/fmt.f
require src/lib/error.f
require src/lib/fs-mutate.f
require src/lib/fs.f
require src/lib/json.f
require src/lib/prelude.f
require src/lib/string.f

package SW

\ ---- reasons ----------------------------------------------------------------
\ the switch E-SW-UNREPAIRED names: its provider and the name it installs
variable UNREPAIRED-P
create UNREPAIRED-NAME NAME-CAP allot   variable UNREPAIRED-NAME-U
\ the account a redeem was asked to spend a reset of
create REDEEM-NAME NAME-CAP allot   variable REDEEM-NAME-U
\ the reason a builder below assembles: a reason can name a path of any length
create REASON-TEXT BUF:HDR-BYTES allot

: REASON-START ( -- ) REASON-TEXT 64 BUF:N>BLEN BUF:RESET ;
: REASON+ ( ptr u8 n -- ) BUF:N>BLEN REASON-TEXT BUF:APPEND-SPAN ;
: REASON-TEXT$ ( -- ptr u8 n ) REASON-TEXT BUF:SPAN$ BUF:BLEN>N ;

public

: UNREPAIRED-REASON$ ( -- ptr u8 n )
   REASON-START s" kiba: the " REASON+ UNREPAIRED-P @ PROVIDER$ REASON+
   s"  switch to " REASON+ UNREPAIRED-NAME UNREPAIRED-NAME-U @ REASON+
   s"  did not finish; nothing is probed or refreshed until a switch completes" REASON+ REASON-TEXT$ ;

: NO-RESETS-REASON$ ( -- ptr u8 n )
   REASON-START s" kiba: no limit resets are available for " REASON+
   REDEEM-NAME REDEEM-NAME-U @ REASON+ REASON-TEXT$ ;

: REMOTE-REASON$ ( -- ptr u8 n )
   REASON-START s" kiba: " REASON+ REMOTE-NOTE$ REASON+ REASON-TEXT$ ;

: ORPHAN-REASON$ ( -- ptr u8 n )
   REASON-START s" kiba: Claude credentials exist but " REASON+ ORPHAN-CONFIG$ REASON+
   s"  is missing: nothing is probed or switched until it names their account" REASON+ REASON-TEXT$ ;

: REASON$ ( n -- ptr u8 n ) {: rc :}
   rc E-SW-PROVIDER = if s" kiba: provider must be claude or codex" exit then
   rc E-SW-NO-LIVE = if s" kiba: no live login to save" exit then
   rc E-SW-NO-ACCOUNT = if s" kiba: no such saved account" exit then
   rc E-SW-NAME = if s" kiba: account name has unsafe characters" exit then
   rc E-SW-JSON = if s" kiba: a login file is missing an expected field" exit then
   rc E-SW-LOGIN = if s" kiba: provider login did not complete" exit then
   rc E-SW-CAPACITY = if REASON-START s" kiba: too many: " REASON+ TOO-MANY$ REASON+ REASON-TEXT$ exit then
   rc E-SW-NO-CLI = if s" kiba: provider command is not on PATH" exit then
   rc E-BASE64-LAST >= rc E-BASE64-FIRST <= and if s" kiba: id_token is not base64url" exit then
   rc E-SW-ENV = if s" kiba: HOME is not set" exit then
   rc E-SW-MISMATCH = if s" kiba: the saved login belongs to a different account than its name" exit then
   rc E-SW-ORPHAN-LIVE = if ORPHAN-REASON$ exit then
   rc E-SW-UNREPAIRED = if UNREPAIRED-REASON$ exit then
   rc E-SW-MIXED = if s" kiba: the live Claude files name different accounts; switch to an account to repair them" exit then
   rc E-SW-DB = if REASON-START s" kiba: the account database refused: " REASON+ DB-ERROR$ REASON+ REASON-TEXT$ exit then
   rc E-SW-DB-VERSION = if s" kiba: the account store is from a newer kiba; upgrade kiba" exit then
   rc E-SW-TURN-BUSY = if s" kiba: another kiba holds that provider's turn" exit then
   rc E-SW-NO-RESETS = if NO-RESETS-REASON$ exit then
   rc E-SW-REMOTE = if REMOTE-REASON$ exit then
   rc E-SW-OUTPUT = if s" kiba: could not write the output" exit then
   rc E-STR-CAPACITY = if s" kiba: a path or name is too long" exit then
   rc E-FS-OPEN = if s" kiba: cannot open a login file" exit then
   rc E-FS-IO = if s" kiba: a file read, write, or rename failed" exit then
   rc E-FS-CAPACITY = rc E-SPAN-CAPACITY = or rc E-SPAN-RANGE = or if s" kiba: a login file or path is too large" exit then
   rc E-FS-PATH-UNSAFE = if s" kiba: refusing to write through a symlink chain" exit then
   rc E-PROC-SPAWN = if s" kiba: could not start the provider command" exit then
   rc E-JSON-READ-LAST >= rc E-JSON-READ-FIRST <= and if s" kiba: a login file is not valid JSON" exit then
   rc E-FS-LAST >= rc E-FS-FIRST <= and if s" kiba: a file operation failed" exit then
   rc E-PROC-LAST >= rc E-PROC-FIRST <= and if s" kiba: could not run a command" exit then
   REASON-START s" kiba: error code " REASON+ rc FMT:INT$ REASON+ REASON-TEXT$ ;

private

\ rc's reason without its "kiba: " prefix: for a line that already starts
\ with its provider, and for an account's note and a provider's status
\ error, as kiba-mac records them
: BARE-REASON$ ( n -- ptr u8 n )
   REASON$ {: a u :}
   s" kiba: " {: k ku :}
   a u k ku STARTS-WITH? 0= if a u exit then
   a ku + u ku - ;

\ ---- status: the read -------------------------------------------------------
\ the bare reason the last READ-PROVIDER stopped on, copied as it is caught: a
\ code's reason can name state a later caught error overwrites (TOO-MANY$)
create STAT-REASON BUF:HDR-BYTES allot

\ STATUS-READ of provider p, keeping its reason; empty when it read everything
: READ-PROVIDER ( n -- )
   STATUS-READ
   STAT-REASON 64 BUF:N>BLEN BUF:RESET
   STATUS-ERROR 0= if exit then
   STATUS-ERROR BARE-REASON$ BUF:N>BLEN STAT-REASON BUF:APPEND-SPAN ;

: STAT-REASON$ ( -- ptr u8 n ) STAT-REASON BUF:SPAN$ BUF:BLEN>N ;

\ ---- status: text -----------------------------------------------------------
\ Each provider is rendered right after its read: the row table, ID-LIVE and
\ the usage record hold that provider until the next store read.
: .PLAN ( ptr u8 n -- ) {: a u :}
   u 0= if exit then
   s"  (" .TEXT a u .TEXT s" )" .TEXT ;

: .FIGURES ( n -- ) {: p :}
   p FIGURES-TEXT {: a u :}
   u 0= if exit then
   s"   " .TEXT a u .TEXT ;

: .ACCOUNT ( n n -- ) {: p i :}
   i STATUS-ACTIVE? if s"   * " else s"     " then .TEXT
   i DB-ROW-NAME$ .TEXT
   i DB-ROW-USAGE {: probed :}
   i probed SHOWN-PLAN$ .PLAN
   probed if p .FIGURES then
   .NL ;

: .LIVE ( -- )
   STATUS-ERROR 0<> if STAT-REASON$ .TEXT .NL exit then
   STATUS-LIVE? if ID-LIVE EMAIL$ .TEXT ID-LIVE PLAN$ .PLAN .NL exit then
   s" no live login" .TEXT .NL ;

: .PROVIDER ( n -- ) {: p :}
   p READ-PROVIDER
   p PROVIDER$ .TEXT s" : " .TEXT .LIVE
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
   ENC-COMMA s" error" ENC-KEY STAT-REASON$ ENC-STR ;

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
   p READ-PROVIDER
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
   STATUS-JSON$ .TEXT .NL ;

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
   p PROVIDER$ .TEXT
   LIVE-ROW$ nip 0= if s" : no live login" .TEXT .NL exit then
   s" : saved " .TEXT LIVE-ROW$ .TEXT .NL ;

: SAVE-ONE ( n -- ) {: p :}
   p [: p SAVE-LIVE-ROW ;] STORE-TURN
   p .SAVED ;

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

\ the live files hold the login just saved, so it is the installed one
: BACK-NOTE ( n -- ) {: p :}
   [: p LIVE-ROW$ 0 false DB-NOTE-INSTALLED ;] DB-WRITE ;

\ the live login is saved before a switch, so no login is overwritten
\ unsaved; mixed live files are left for the install to repair
: SAVE-BACK ( n -- ) {: p :}
   p BACK-SENSE MATCH back-input
      saved OF p BACK-NOTE ENDOF
      absent OF ENDOF
      mixed OF ENDOF
      refused OF BACK-RC @ throw ENDOF
   ;MATCH ;

\ ---- probing saved logins ----------------------------------------------------
\ The saved names whose tokens the CLI is using: the live identity's, and
\ the installed one's while the live Claude files are mixed
create LIVE-A NAME-CAP allot   variable LIVE-A-U    \ -1 when none
create LIVE-B NAME-CAP allot   variable LIVE-B-U    \ -1 when none

: UNREPAIRED ( n ptr u8 n -- ) {: p a u :}
   p UNREPAIRED-P !
   a u UNREPAIRED-NAME UNREPAIRED-NAME-U NAME-CAP SPAN!
   E-SW-UNREPAIRED throw ;

\ E-SW-UNREPAIRED while an install is pending: a failed repair may have
\ left any saved login's tokens live
: REQUIRE-REPAIRED ( n -- ) {: p :}
   p DB-PENDING {: a u pending :}
   pending if p a u UNREPAIRED then ;

: INSTALLED-LIVE ( n -- )
   DB-INSTALLED {: a u has :}
   has if a u LIVE-B LIVE-B-U NAME-CAP SPAN! then ;

: LIVE-NAMES ( n bool -- ) {: p mixed :}
   -1 LIVE-A-U ! -1 LIVE-B-U !
   p LIVE-IDENTITY if p ID-LIVE DB-LIVE-NAME LIVE-A LIVE-A-U NAME-CAP SPAN! then
   p REQUIRE-REPAIRED
   mixed if p INSTALLED-LIVE then ;

: LIVE-NAME? ( ptr u8 n -- bool ) {: a u :}
   LIVE-A-U @ 0 >= if a u LIVE-A LIVE-A-U @ STR= if true exit then then
   LIVE-B-U @ 0 >= if a u LIVE-B LIVE-B-U @ STR= exit then
   false ;

\ a probe that throws becomes row r's error outcome, not the command's failure
: OUTCOME ( n n bool -- ) {: p r live :}
   [: p r DB-ROW-LOGIN$ live PROBE ;] catch {: rc :}
   rc 0= if exit then
   rc BARE-REASON$ PROBE-FAILED ;

\ the probe of row r left a login other than the row's, byte for byte; the
\ probe's login points into the row table until a renewal, so no store read
\ may come between the probe and this
: LOGIN-CHANGED? ( n -- bool ) {: r :}
   PROBE-DOC$ r DB-ROW-LOGIN$ STR= 0= ;

\ row r's usage record, the plan the provider named and any refreshed login,
\ in one transaction; a login the provider revoked keeps its row
: RECORD ( n n -- ) {: p r :}
   r DB-ROW-NAME$ {: a u :}
   r LOGIN-CHANGED? {: changed :}
   [: p a u PROBED-PLAN$ DB-SET-USAGE
      changed if p a u PROBE-DOC$ DB-SET-LOGIN then ;] DB-WRITE ;

\ probes the saved login a u and records the outcome, for an operation that
\ holds p's turn; E-SW-NO-ACCOUNT when there is no such login
: PROBE-IN-TURN ( n ptr u8 n bool -- ) {: p a u live :}
   p a u DB-FETCH 0= if E-SW-NO-ACCOUNT throw then
   p 0 live OUTCOME
   p 0 RECORD ;

create OLD-NAME NAME-CAP allot   variable OLD-NAME-U

\ after the install the new login is probed as live, then the login saved
\ back as saved: its usage came from a live probe, which never refreshes
: USE-RUN ( n ptr u8 n -- ) {: p a u :}
   p SAVE-BACK
   LIVE-ROW$ OLD-NAME OLD-NAME-U NAME-CAP SPAN!
   p a u INSTALL
   p a u true PROBE-IN-TURN
   OLD-NAME OLD-NAME-U @ {: o ou :}
   ou 0= if exit then
   o ou a u STR= if exit then
   p o ou false PROBE-IN-TURN ;

\ ---- usage --------------------------------------------------------------------
ENUM usage-step checking saving listing listing-mixed probing reported failed ;ENUM
ENUM check-input answered stale threw ;ENUM
ENUM list-input listed threw ;ENUM
ENUM probe-input recorded unrecorded finished ;ENUM
ENUM usage-turn entering left lost ;ENUM
ENUM turn-input ran refused unwritten ;ENUM

variable USAGE-ASKED                \ epoch second the run began
variable USAGE-ROW                  \ the row being probed
variable USAGE-RC                   \ what the last failed step threw
create BACK-ERR BUF:HDR-BYTES allot   \ the save-back error; empty when none
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
   p PROVIDER$ .TEXT s" : " .TEXT a u .TEXT s"   " .TEXT
   DB-LIMIT# 0= if DB-USAGE-NOTE$ .TEXT .NL exit then
   .LIMITS .NL ;

\ every saved row holds a record fetched after the run began
: ALL-PROBED? ( -- bool )
   DB-ROW# 0= if false exit then
   DB-ROW# 0 ?do
      i DB-ROW-USAGE 0= if false unloop exit then
      DB-USAGE-AT USAGE-ASKED @ <= if false unloop exit then
   loop
   true ;

\ 1 when another kiba probed every row while this one waited for the turn;
\ the live names and the list are read again for its records
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

: ROWS-RUN ( n bool -- n bool ) {: p mixed :}
   p mixed LIVE-NAMES
   p DB-LIST
   0 USAGE-ROW !
   p mixed ;

\ the rows listed; mixed when the installed name's tokens are still live
: ROWS-LIST ( n bool -- list-input )
   [: ROWS-RUN ;] catch {: rc :} 2drop
   rc 0= if construct list-input listed exit then
   rc USAGE-RC ! construct list-input threw ;

: ROWS-SENSE ( n -- list-input ) false ROWS-LIST ;

: ROWS-MIXED-SENSE ( n -- list-input ) true ROWS-LIST ;

: ROW-RUN ( n -- n ) {: p :}
   USAGE-ROW @ {: r :}
   r DB-ROW-NAME$ LIVE-NAME? {: live :}
   p r live OUTCOME
   p r RECORD
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
   BACK-ERR 64 BUF:N>BLEN BUF:RESET
   BACK-RC @ BARE-REASON$ BUF:N>BLEN BACK-ERR BUF:APPEND-SPAN ;

: NOTE-MIXED ( n -- )
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
      mixed       NOTE-MIXED       >listing-mixed
      refused     NOTE-BACK        >listing
   IN listing ROWS-SENSE ( list-input )
      listed      -                >probing
      threw       NOTE-FAILURE     >failed
   IN listing-mixed ROWS-MIXED-SENSE ( list-input )
      listed      -                >probing
      threw       NOTE-FAILURE     >failed
   IN probing ROW-SENSE ( probe-input )
      recorded    .ROW             >probing
      unrecorded  NOTE-UNRECORDED  >probing
      finished    -                >reported
   FINAL reported -
   FINAL failed -
;DEFINE

\ the save-back error and the provider error each go to stderr as one line
\ that starts with the provider; true when either did
: .FAULTS ( n -- bool ) {: p :}
   BACK-ERR BUF:SPAN$ BUF:BLEN>N {: ba bu :}
   bu 0 > {: back :}
   FAULTS-U @ 0 > {: faults :}
   back if p PROVIDER$ ERR-PART s" : live login not saved: " ERR-PART ba bu ERR-NOTE then
   faults if p PROVIDER$ ERR-PART s" : " ERR-PART FAULTS$ ERR-NOTE then
   back faults or ;

: USAGE-IN-TURN ( n -- n ) {: p :}
   p [: p construct usage-step checking USAGE-STEPS ;] STORE-TURN
   p ;

: USAGE-TURN-SENSE ( n -- turn-input )
   [: USAGE-IN-TURN ;] catch {: rc :} drop
   rc 0= if construct turn-input ran exit then
   rc E-SW-OUTPUT = if construct turn-input unwritten exit then
   rc USAGE-RC ! construct turn-input refused ;

\ when stdout refused the report, stderr still gets what provider p collected
: OUTPUT-LOST ( n -- )
   .FAULTS drop E-SW-OUTPUT throw ;

FSM:DEFINE USAGE-TURN ( n ) usage-turn turn-input
   IN entering USAGE-TURN-SENSE
      ran         -                >left
      refused     NOTE-FAILURE     >left
      unwritten   -                >lost
   FINAL left -
   FINAL lost OUTPUT-LOST
;DEFINE

\ true when provider p reported an error
: USAGE-PROVIDER ( n -- bool ) {: p :}
   epoch-seconds USAGE-ASKED !
   BACK-ERR 64 BUF:N>BLEN BUF:RESET FAULTS-RESET
   p construct usage-turn entering USAGE-TURN
   p .FAULTS ;

public

: CMD-STATUS ( bool -- ) {: json :}
   [: json STATUS-SHOW ;] WITH-STORE ;

\ p < 0 probes every provider; once each has run, E-SW-REPORTED when any
\ reported an error. A refused stdout write ends the run with E-SW-OUTPUT
: CMD-USAGE ( n -- )
   dup 0 < if drop false P-COUNT 0 ?do i USAGE-PROVIDER or loop else USAGE-PROVIDER then
   if E-SW-REPORTED throw then ;

\ p < 0 saves every provider
: CMD-SAVE ( n -- )
   dup 0 < if drop 0 begin dup P-COUNT < while dup SAVE-ONE 1+ repeat drop exit then
   SAVE-ONE ;

\ saves the live login back, then makes the saved login live
: CMD-USE ( n ptr u8 n -- ) {: p a u :}
   p [: p a u USE-RUN ;] STORE-TURN
   p PROVIDER$ .TEXT s" : now " .TEXT a u .TEXT .NL ;

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
   [: p a u PROBE-DOC$ DB-SET-LOGIN ;] DB-WRITE ;

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
   s" Sign in to " .TEXT
   eu 0 > if e eu NAME-EMAIL .TEXT else s" the account to add" .TEXT then
   s"  at " .TEXT p SITE$ .TEXT
   s"  in your browser, then press Enter to continue: " .TEXT
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

\ The login runs, then the new login is read from the throwaway home, which
\ LOGIN-ROOT names, and saved under its name. E-SW-LOGIN when the login
\ fails; E-SW-NO-LIVE when it left no login.
ENUM add-state signing importing added ;ENUM
ENUM sign-input signed-in failed ;ENUM
ENUM import-input saved none ;ENUM
\ the account the user is asked to sign in to; empty when none was named
create ADD-EMAIL NAME-CAP allot   variable ADD-EMAIL-U

: ADD-EMAIL$ ( -- ptr u8 n ) ADD-EMAIL ADD-EMAIL-U @ ;

\ the login's exit status
: ADD-LOGIN ( n -- n ) ADD-EMAIL$ NAME-EMAIL LOGIN ;

: ADD-SIGN ( n -- sign-input ) {: p :}
   p ADD-EMAIL$ ADD-PAUSE
   p ADD-LOGIN 0= if construct sign-input signed-in exit then
   construct sign-input failed ;

: ADD-IMPORT ( n -- import-input ) {: p :}
   0 LIVE-ROW-U !
   [: p PUT-LIVE ;] DB-WRITE
   LIVE-ROW$ nip 0= if construct import-input none exit then
   construct import-input saved ;

: LOGIN-FAILED ( n -- ) drop E-SW-LOGIN throw ;

: NO-LOGIN ( n -- ) drop E-SW-NO-LIVE throw ;

FSM:DEFINE ADD-STEPS ( n ) add-state sign-input
   IN signing ADD-SIGN
      signed-in -             >importing
      failed    LOGIN-FAILED  >added
   IN importing ADD-IMPORT ( import-input )
      saved     -             >added
      none      NO-LOGIN      >added
   FINAL added -
;DEFINE

: ADD-RUN ( n ptr u8 n -- ) {: p e eu :}
   e eu ADD-EMAIL ADD-EMAIL-U NAME-CAP SPAN!
   p ADD-BEGIN
   p construct add-state signing ADD-STEPS ;

: ADD-TURN ( n ptr u8 n -- ) {: p e eu :}
   [: p e eu ADD-RUN ;] [: p ADD-END ;] finally ;

: .ADDED ( n ptr u8 n -- ) {: p e eu :}
   p PROVIDER$ .TEXT s" : saved " .TEXT LIVE-ROW$ .TEXT
   eu 0 > LIVE-ROW$ e eu STR= 0= and if
      s"  (you signed in to a different account than " .TEXT e eu .TEXT s" )" .TEXT
   then
   .NL ;

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
   a u REDEEM-NAME REDEEM-NAME-U NAME-CAP SPAN!
   p [: p a u REDEEM-RUN ;] STORE-TURN
   p PROVIDER$ .TEXT s" : " .TEXT a u REDEEMED$ .TEXT .NL ;

: CMD-FORGET ( n ptr u8 n -- ) {: p a u :}
   p [: p a u FORGET-ROW ;] STORE-TURN
   p PROVIDER$ .TEXT s" : forgot " .TEXT a u .TEXT .NL ;

;package
