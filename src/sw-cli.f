\ sw-cli.f - the kiba commands: status, save, use, add, forget.
require ../src/sw-store.f
require ../src/sw-run.f
require ../src/sw-usage.f
require ../src/sw-db.f
require ../src/sw-status.f
require ../src/sw-turn.f
require src/lib/fsm.f
require src/lib/fmt.f

package SW

create LNAME-BUF 256 allot    variable LNAME-U
variable CMD-P
variable SCAN-RC                     \ 0, or why the provider could not be read
variable SCAN-LIVE                   \ bool: the provider has a live login

: LNAME$ ( -- ptr u8 n ) LNAME-BUF LNAME-U @ ;

\ ID-LIVE is who the provider is logged in as; LNAME$ the slot it saves to
: LOAD-LIVE ( n -- bool ) {: p :}
   0 LNAME-U !
   p LIVE-IDENTITY dup if p LIVE-NAME LNAME-BUF LNAME-U 256 SPAN! then ;

\ the saved list comes first so a broken live file still leaves it readable
: SCAN-PROVIDER-RAW ( n -- n ) {: p :}
   p LIST-ACCOUNTS
   p LOAD-LIVE SCAN-LIVE !
   p ;

\ everything that can fail for one provider happens here, before any output
: SCAN-PROVIDER ( n -- ) {: p :}
   false SCAN-LIVE !
   0 ACCT-RESET
   p [: SCAN-PROVIDER-RAW ;] catch SCAN-RC ! drop
   SCAN-RC @ 0<> if false SCAN-LIVE ! ID-LIVE NO-IDENTITY 0 LNAME-U ! then ;

: ACTIVE? ( n -- bool ) {: i :}
   SCAN-LIVE @ 0= if false exit then
   i ACCT-NAME LNAME$ STR= ;

\ ---- reasons ----------------------------------------------------------------
public

\ LOCK$ builds through the same string builder, so it goes first
: LOCKED-REASON$ ( -- ptr u8 n )
   LOCK$ {: l lu :}
   SB-RESET s" kiba: another kiba holds the store lock; remove " SB-APPEND
   l lu SB-APPEND s"  if it is stale" SB-APPEND SB$ ;

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
   rc E-SW-LOCKED = if LOCKED-REASON$ exit then
   rc E-SW-JSON = if s" kiba: a login file is missing an expected field" exit then
   rc E-SW-LOGIN = if s" kiba: provider login did not complete" exit then
   rc E-SW-CAPACITY = if s" kiba: too many saved accounts or a file over 4 MiB" exit then
   rc E-SW-NO-CLI = if s" kiba: provider command is not on PATH" exit then
   rc E-SW-BASE64 = if s" kiba: id_token is not base64url" exit then
   rc E-SW-ENV = if s" kiba: HOME is not set" exit then
   rc E-SW-MISMATCH = if s" kiba: the saved login belongs to a different account than its name" exit then
   rc E-SW-UNRESTORED = if s" kiba: the live login waits to be put back after an add; a new add does it" exit then
   rc E-SW-SUPERSEDED = if s" kiba: another Claude switch began before this one wrote anything; this one changed nothing" exit then
   rc E-SW-ORPHAN-LIVE = if ORPHAN-REASON$ exit then
   rc E-SW-MIXED = if s" kiba: the live Claude files name different accounts; switch to an account to repair them" exit then
   rc E-SW-DB = if SB-RESET s" kiba: the account database refused: " SB-APPEND DB-ERROR$ SB-APPEND SB$ exit then
   rc E-SW-DB-VERSION = if s" kiba: the account store is from a newer kiba; upgrade kiba" exit then
   rc E-SW-TURN-BUSY = if s" kiba: another kiba holds that provider's turn" exit then
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
\ Each opens the account store for itself and holds the provider's turn
\ throughout; both are left on every path.
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

: USE-RUN ( n ptr u8 n -- ) {: p a u :}
   p construct back-state saving SAVE-BACK-ROW
   p a u INSTALL ;

\ usage's folder save-back: the live login goes to its slot so the slot's
\ tokens are fresh before it is probed
: SAVE-BACK ( n -- ) {: p :}
   p LIVE-IDENTITY if p SAVE-LIVE then ;

: .PROBED ( n n -- ) {: p i :}
   p PROVIDER$ type s" : " type i ACCT-NAME type s"   " type
   PROBE-REMOVED? if s" login revoked; removed" type cr exit then
   p i ACCT-NAME LOAD-USAGE drop
   LIM#@ 0= if NOTE$ type cr exit then
   .LIMITS cr ;

: SAVE-BACK-KEEP ( n -- n ) {: p :}
   p SAVE-BACK p ;

\ the live login is saved first, under the lock, so its slot is fresh and
\ so a login saved by this very run is probed by it; a live login that
\ cannot be read is reported and the saved accounts are still probed
: USAGE-PREPARE-LOCKED ( -- )
   CMD-P @ [: SAVE-BACK-KEEP ;] catch {: rc :} drop
   rc 0<> if
      CMD-P @ PROVIDER$ ERR-PART s" : live login not saved: " ERR-PART rc REASON$ ERR-NOTE
   then
   CMD-P @ SCAN-PROVIDER ;

\ every saved account of one provider, probed without the lock; a provider
\ that cannot be read is reported and the others still run
: USAGE-PROVIDER ( n -- ) {: p :}
   p CMD-P !
   [: USAGE-PREPARE-LOCKED ;] WITH-LOCK
   SCAN-RC @ 0<> if p PROVIDER$ type s" : " type SCAN-RC @ REASON$ type cr exit then
   0 begin dup ACCT# < while
      {: i :}
      p i ACCT-NAME i ACTIVE? PROBE-SLOT
      p i .PROBED
      i 1+
   repeat drop ;

: USAGE-RUN ( n -- )
   dup 0 < if drop 0 begin dup P-COUNT < while dup USAGE-PROVIDER 1+ repeat drop exit then
   USAGE-PROVIDER ;

public

: CMD-STATUS ( bool -- ) {: json :}
   [: json STATUS-SHOW ;] WITH-STORE ;

\ p < 0 probes every provider
: CMD-USAGE ( n -- )
   USAGE-RUN ;

\ p < 0 saves every provider
: CMD-SAVE ( n -- )
   dup 0 < if drop 0 begin dup P-COUNT < while dup SAVE-ONE 1+ repeat drop exit then
   SAVE-ONE ;

\ saves the live login back, then makes the saved login live
: CMD-USE ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p [: p a u USE-RUN ;] STORE-TURN
   p PROVIDER$ type s" : now " type a u type cr ;

\ ---- add: the provider login inside a throwaway home ------------------------------
\ The login command never sees the live login: it runs with its home
\ variable pointing at a private directory under the store, so nothing is
\ read, revoked, or replaced while a session is working. The new login is
\ then saved under its own name; switching to it is a separate `use`.
: LOGIN-HOME$ ( n -- ptr u8 n )
   P-CLAUDE = if s" /login-claude" else s" /login-codex" then PSUB$ ;

: SITE$ ( n -- ptr u8 n )
   P-CLAUDE = if s" claude.ai" exit then
   s" chatgpt.com" ;

create LINE-BUF 256 allot
variable LOGIN-RC

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

: LOGIN-KEEP ( n ptr u8 n -- n ptr u8 n ) {: p e eu :}
   p e eu NAME-EMAIL LOGIN LOGIN-RC !
   p e eu ;

\ the new login is read from the throwaway home and saved under its name
: ADD-SAVE-LOCKED ( -- )
   CMD-P @ LIVE-IDENTITY 0= if E-SW-NO-LIVE throw then
   CMD-P @ SAVE-LIVE ;

: ADD-SAVE ( -- )
   [: ADD-SAVE-LOCKED ;] WITH-LOCK ;

: .ADDED ( n ptr u8 n -- ) {: p e eu :}
   p PROVIDER$ type s" : saved " type SAVED-NAME$ type
   eu 0 > SAVED-NAME$ e eu STR= 0= and if
      s"  (you signed in to a different account than " type e eu type s" )" type
   then
   cr ;

: CMD-ADD ( n ptr u8 n -- ) {: p e eu :}
   p CHECK-LOGIN-CLI
   p CMD-P !
   p ADD-BEGIN
   p e eu ADD-PAUSE
   p e eu [: LOGIN-KEEP ;] catch {: rc :} drop 2drop
   rc 0<> if p ADD-END rc throw then
   LOGIN-RC @ 0<> if p ADD-END E-SW-LOGIN throw then
   [: ADD-SAVE ;] catch {: src :}
   src 0<> if p ADD-END src throw then
   p ADD-END
   p e eu .ADDED
   p SAVED-NAME$ false PROBE-SLOT ;

: LOGIN-HOME-PUBLIC$ ( n -- ptr u8 n ) LOGIN-HOME$ ;

: CMD-FORGET ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p [: p a u FORGET-ROW ;] STORE-TURN
   p PROVIDER$ type s" : forgot " type a u type cr ;

;package
