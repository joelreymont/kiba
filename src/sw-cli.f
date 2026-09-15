\ sw-cli.f - the kiba commands: status, save, use, add, forget.
require ../src/sw-store.f
require ../src/sw-run.f
require ../src/sw-usage.f
require lib/json-write.f
require lib/fmt.f

package SW

create LEMAIL-BUF 256 allot   variable LEMAIL-U
create LNAME-BUF 256 allot    variable LNAME-U
create LPLAN-BUF 64 allot     variable LPLAN-U
create NAME-BUF 256 allot     variable NAME-U
variable CMD-P
variable SCAN-RC                     \ 0, or why the provider could not be read
variable SCAN-LIVE                   \ bool: the provider has a live login
variable ADD-MARKED                  \ bool: a marker already existed before the login

: LEMAIL$ ( -- ptr u8 n ) LEMAIL-BUF LEMAIL-U @ ;
: LNAME$ ( -- ptr u8 n ) LNAME-BUF LNAME-U @ ;
: LPLAN$ ( -- ptr u8 n ) LPLAN-BUF LPLAN-U @ ;
: NAME$ ( -- ptr u8 n ) NAME-BUF NAME-U @ ;

\ the live identity is copied aside because slot reads reuse EMAIL$/PLAN$
: LOAD-LIVE ( n -- bool ) {: p :}
   0 LEMAIL-U ! 0 LPLAN-U ! 0 LNAME-U !
   p LIVE-IDENTITY dup if
      EMAIL$ LEMAIL-BUF LEMAIL-U 256 SPAN!
      PLAN$ LPLAN-BUF LPLAN-U 64 SPAN!
      p LIVE-NAME LNAME-BUF LNAME-U 256 SPAN!
   then ;

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
   SCAN-RC @ 0<> if false SCAN-LIVE ! 0 LEMAIL-U ! 0 LPLAN-U ! 0 LNAME-U ! then ;

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
   rc E-SW-INTERRUPTED = if s" kiba: an earlier switch was interrupted; run `kiba use` to finish it" exit then
   rc E-SW-MISMATCH = if s" kiba: the saved file belongs to a different account than its folder name" exit then
   rc E-SW-ASIDE = if s" kiba: an earlier `add` left a .kiba-aside login file; move it back or remove it" exit then
   rc E-SW-MIXED = if s" kiba: the live Claude files name different accounts; switch to an account to repair them" exit then
   rc E-JR-STATE = if s" kiba: a login field is longer than kiba can hold" exit then
   rc E-STR-CAPACITY = if s" kiba: a path or name is too long" exit then
   rc E-FS-OPEN = if s" kiba: cannot open a login file" exit then
   rc E-FS-IO = if s" kiba: a file read, write, or rename failed" exit then
   rc E-FS-CAPACITY = if s" kiba: a login file or path is too large" exit then
   rc E-FS-PATH-UNSAFE = if s" kiba: refusing to write through a symlink chain" exit then
   rc E-PROC-SPAWN = if s" kiba: could not start the provider command" exit then
   rc E-JR-LAST >= rc E-JR-FIRST <= and if s" kiba: a login file is not valid JSON" exit then
   rc E-FS-LAST >= rc E-FS-FIRST <= and if s" kiba: a file operation failed" exit then
   rc E-PROC-LAST >= rc E-PROC-FIRST <= and if s" kiba: could not run a command" exit then
   SB-RESET s" kiba: error code " SB-APPEND rc FMT:SB-INT SB$ ;

private

\ ---- status: text -----------------------------------------------------------
: .PLAN ( ptr u8 n -- ) {: a u :}
   u 0= if exit then
   s"  (" type a u type s" )" type ;

: .AGE ( -- )
   USAGE-AT@ 0 < if exit then
   TIME:EPOCH-SECONDS USAGE-AT@ - 60 / {: m :}
   s"  (" type m FMT:.U s" m ago)" type ;

: .USAGE ( n n -- ) {: p i :}
   p i ACCT-NAME LOAD-USAGE 0= if exit then
   s"   " type
   LIM#@ 0= if NOTE$ type .AGE exit then
   .LIMITS .AGE ;

: .ACCOUNT ( n n -- ) {: p i :}
   p i ACCT-NAME SLOT-PLAN
   i ACTIVE? if s"   * " else s"     " then type
   i ACCT-NAME type PLAN$ .PLAN
   p i .USAGE cr ;

: .LIVE ( -- )
   SCAN-RC @ 0<> if SCAN-RC @ REASON$ type cr exit then
   SCAN-LIVE @ if LEMAIL$ type LPLAN$ .PLAN cr exit then
   s" no live login" type cr ;

: .PROVIDER ( n -- ) {: p :}
   p SCAN-PROVIDER
   p PROVIDER$ type s" : " type .LIVE
   0 begin dup ACCT# < while p over .ACCOUNT 1+ repeat drop ;

: STATUS-TEXT ( -- )
   0 begin dup P-COUNT < while dup .PROVIDER 1+ repeat drop ;

\ ---- status: json -----------------------------------------------------------
: JSON-LIVE ( -- )
   s" live" JSON-WRITE:KEY
   SCAN-LIVE @ 0= if JSON-WRITE:NULL exit then
   JSON-WRITE:OBJECT-START
   s" email" LEMAIL$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" plan" LPLAN$ JSON-WRITE:FIELD-S
   JSON-WRITE:OBJECT-END ;

: JSON-USAGE ( n n -- ) {: p i :}
   s" usage" JSON-WRITE:KEY
   p i ACCT-NAME LOAD-USAGE 0= if JSON-WRITE:NULL exit then
   JSON-WRITE:OBJECT-START
   s" fetchedAt" USAGE-AT@ 0 max JSON-WRITE:FIELD-U JSON-WRITE:COMMA
   s" state" STATE$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" note" NOTE$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" limits" USAGE-LIMITS-RAW$ JSON-WRITE:FIELD-RAW
   JSON-WRITE:OBJECT-END ;

: JSON-ACCOUNT ( n n -- ) {: p i :}
   i 0 > if JSON-WRITE:COMMA then
   JSON-WRITE:OBJECT-START
   s" email" i ACCT-NAME JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   p i ACCT-NAME SLOT-PLAN
   s" plan" PLAN$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" active" i ACTIVE? JSON-WRITE:FIELD-BOOL JSON-WRITE:COMMA
   p i JSON-USAGE
   JSON-WRITE:OBJECT-END ;

: JSON-PROVIDER ( n -- ) {: p :}
   p SCAN-PROVIDER
   p 0 > if JSON-WRITE:COMMA then
   JSON-WRITE:OBJECT-START
   s" id" p PROVIDER$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   JSON-LIVE JSON-WRITE:COMMA
   s" accounts" JSON-WRITE:KEY JSON-WRITE:ARRAY-START
   0 begin dup ACCT# < while p over JSON-ACCOUNT 1+ repeat drop
   JSON-WRITE:ARRAY-END
   SCAN-RC @ 0<> if JSON-WRITE:COMMA s" error" SCAN-RC @ REASON$ JSON-WRITE:FIELD-S then
   JSON-WRITE:OBJECT-END ;

public

: STATUS-JSON$ ( -- ptr u8 n )
   JSON-WRITE:RESET
   JSON-WRITE:OBJECT-START
   s" providers" JSON-WRITE:KEY JSON-WRITE:ARRAY-START
   0 begin dup P-COUNT < while dup JSON-PROVIDER 1+ repeat drop
   JSON-WRITE:ARRAY-END
   JSON-WRITE:OBJECT-END
   JSON-WRITE:$ ;

private

: STATUS-JSON ( -- )
   STATUS-JSON$ type cr ;

\ ---- save / use / add / forget ----------------------------------------------
: .SAVED ( n -- ) {: p :}
   p PROVIDER$ type s" : saved " type SAVED-NAME$ type cr ;

: MIXED-KEEP ( n -- n ) {: p :}
   CLAUDE-MIXED? if 1 exit then
   0 ;

\ a live file that cannot be read is not a mixed pair; the reader that
\ needs it will say what is wrong
: MIXED? ( n -- bool ) {: p :}
   p P-CLAUDE <> if false exit then
   p [: MIXED-KEEP ;] catch {: rc :}
   rc 0<> if drop false exit then
   0 > ;

: SAVE-ONE ( n -- ) {: p :}
   p INSTALLING? if E-SW-INTERRUPTED throw then
   p MIXED? if E-SW-MIXED throw then
   p LIVE-IDENTITY 0= if p PROVIDER$ type s" : no live login" type cr exit then
   p SAVE-LIVE p .SAVED ;

: SAVE-LOCKED ( -- )
   CMD-P @ 0 < if
      0 begin dup P-COUNT < while dup SAVE-ONE 1+ repeat drop exit
   then
   CMD-P @ SAVE-ONE ;

\ the live login is saved back first so refreshed tokens are never lost;
\ after an interrupted install, or when the live files disagree about the
\ account, the pair is left alone: the next install repairs it
: SAVE-BACK ( n -- ) {: p :}
   p INSTALLING? if exit then
   p MIXED? if s" kiba: the live Claude files name different accounts; not saving them" ERR-NOTE exit then
   p LIVE-IDENTITY if p SAVE-LIVE then ;

\ the account just installed is probed at once so its figures are current
: USE-LOCKED ( -- )
   CMD-P @ SAVE-BACK
   CMD-P @ NAME$ INSTALL
   CMD-P @ NAME$ true PROBE-SLOT ;

: ADD-LOCKED ( -- )
   CMD-P @ INSTALLING? ADD-MARKED !
   CMD-P @ SAVE-BACK
   CMD-P @ SET-ASIDE ;

: ADD-RESTORE-LOCKED ( -- )
   CMD-P @ RESTORE-ASIDE ;

\ a completed login rewrote every live file, so a marker from before it is
\ stale; one that appeared while the lock was released belongs to another
\ kiba's interrupted install and the live pair cannot be trusted
: ADD-SAVE-LOCKED ( -- )
   CMD-P @ INSTALLING? ADD-MARKED @ 0= and if E-SW-INTERRUPTED throw then
   CMD-P @ LIVE-IDENTITY 0= if E-SW-NO-LIVE throw then
   CMD-P @ CLEAR-MARK
   CMD-P @ SAVE-LIVE
   CMD-P @ DROP-ASIDE
   CMD-P @ SAVED-NAME$ true PROBE-SLOT ;

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
      SB-RESET CMD-P @ PROVIDER$ SB-APPEND s" : live login not saved: " SB-APPEND rc REASON$ SB-APPEND
      SB$ ERR-NOTE
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

: FORGET-LOCKED ( -- )
   CMD-P @ NAME$ SLOT-DIR$ DIR? 0= if E-SW-NO-ACCOUNT throw then
   CMD-P @ NAME$ SLOT-DIR$ REMOVE-TREE ;

public

: MIXED-PUBLIC? ( n -- bool ) MIXED? ;

: CMD-STATUS ( bool -- )
   if STATUS-JSON exit then
   STATUS-TEXT ;

\ p < 0 probes every provider
: CMD-USAGE ( n -- )
   USAGE-RUN ;

\ p < 0 saves every provider
: CMD-SAVE ( n -- )
   CMD-P !
   [: SAVE-LOCKED ;] WITH-LOCK ;

: CMD-USE ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p CMD-P !  a u NAME-BUF NAME-U 256 SPAN!
   [: USE-LOCKED ;] WITH-LOCK
   p PROVIDER$ type s" : now " type a u type cr
   p USAGE-REFRESH ;

: CMD-ADD ( n -- ) {: p :}
   p CHECK-LOGIN-CLI
   p CMD-P !
   [: ADD-LOCKED ;] WITH-LOCK
   p [: LOGIN ;] catch {: rc :}
   rc 0<> if drop [: ADD-RESTORE-LOCKED ;] WITH-LOCK rc throw then
   0 <> if [: ADD-RESTORE-LOCKED ;] WITH-LOCK E-SW-LOGIN throw then
   [: ADD-SAVE-LOCKED ;] WITH-LOCK
   p PROVIDER$ type s" : added " type SAVED-NAME$ type cr
   p USAGE-REFRESH ;

: CMD-FORGET ( n ptr u8 n -- ) {: p a u :}
   a u CHECK-NAME
   p CMD-P !  a u NAME-BUF NAME-U 256 SPAN!
   [: FORGET-LOCKED ;] WITH-LOCK
   p PROVIDER$ type s" : forgot " type a u type cr ;

;package
