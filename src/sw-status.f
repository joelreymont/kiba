split-str
\ sw-status.f - what `kiba status` shows: one provider's saved accounts and
\ live login read from the store, and the figures of a usage record.
require ../src/sw-db.f
require ../src/sw-claude.f
require ../src/sw-codex.f
require ../src/sw-base.f
require ../src/sw-identity.f
require ../src/sw-store.f
require ../src/sw-time.f
require src/lib/fmt.f
require src/lib/byte-buffer.f
require src/lib/prelude.f
require src/lib/sort.f
require src/lib/string.f

package SW

\ ---- the provider read --------------------------------------------------------
\ The saved accounts and the last install's time come first, so a broken live
\ login still lists them; then the live identity and the slot it is saved as.
\ A throw ends the read with that step's code and what was read so far.
variable STAT-RC                     \ why the provider could not be read; 0 when it could
variable STAT-ROWS                   \ rows of the table the read lists
variable STAT-AT                     \ epoch seconds of the last install
variable STAT-AT?                    \ whether an install noted its time
create STAT-NAME NAME-CAP allot      \ the slot the live login is saved as
variable STAT-NAME-U                 \ -1 while no live login is known

: LIST-RUN ( n -- ) DB-LIST DB-ROW# STAT-ROWS ! ;

: TIME-RUN ( n -- ) DB-INSTALLED-AT STAT-AT? ! STAT-AT ! ;

: NAME-RUN ( n -- )
   ID-LIVE DB-LIVE-NAME STAT-NAME STAT-NAME-U NAME-CAP SPAN! ;

public

\ reads provider p: its saved accounts into the row table, the last install's
\ time, and its live login into ID-LIVE; valid until the next store read
: STATUS-READ ( n -- ) {: p :}
   0 STAT-RC ! 0 STAT-ROWS ! 0 STAT-AT ! false STAT-AT? ! -1 STAT-NAME-U !
   [: p LIST-RUN p TIME-RUN p LIVE-IDENTITY if p NAME-RUN then ;] catch STAT-RC ! ;

\ the code the read stopped on; 0 when it read everything
: STATUS-ERROR ( -- n ) STAT-RC @ ;

: STATUS-ROWS ( -- n ) STAT-ROWS @ ;

\ epoch seconds of the last install; false when none noted a time
: STATUS-AT ( -- n bool ) STAT-AT @ STAT-AT? @ 0<> ;

\ the live login is known, in ID-LIVE, and so is the slot it is saved as
: STATUS-LIVE? ( -- bool ) STAT-NAME-U @ 0 >= ;

: STATUS-ACTIVE? ( n -- bool ) {: i :}
   STATUS-LIVE? 0= if false exit then
   i DB-ROW-NAME$ STAT-NAME STAT-NAME-U @ STR:= ;

\ ---- figures --------------------------------------------------------------------
\ The panel's reading of the usage record DB-ROW-USAGE last decoded.
private

100 constant LEVEL-FULL
50 constant LEVEL-HALF
3600 constant OLD-AFTER   \ seconds a reading stays current

\ the first window under the label that has a reading; -1 for none
: WINDOW ( ^u8 n -- n ) {: a u :}
   DB-LIMIT# 0 ?do
      i DB-LIMIT-LABEL$ a u STR:= i DB-LIMIT-PERCENT 0 >= and if i unloop exit then
   loop -1 ;

\ each window gives at most one figure, so FIGURES reserves DB-LIMIT# of each
DYNAMIC-BUFFER FIG-LIMS n    \ the window whose label a figure carries
DYNAMIC-BUFFER FIG-LEFTS n   \ whole percent left
variable FIG-N

: FIG-LIM ( n -- ^n ) FIG-LIMS ;
: FIG-LEFT ( n -- ^n ) FIG-LEFTS ;

create FIG-TEXT BUF:HDR-BYTES allot   \ the figures as text, which grows with the record
: FIG-TEXT+ ( ^u8 n -- ) BUF:N>BLEN FIG-TEXT BUF:APPEND-SPAN ;
: FIG-TEXT-RESET ( -- ) FIG-TEXT 64 BUF:N>BLEN BUF:RESET ;
: FIG-TEXT$ ( -- ^u8 n ) FIG-TEXT BUF:SPAN$ BUF:BLEN>N ;

\ the separator before every figure but the first
: FIG-SEP+ ( n -- ) 0 > if s"  · " FIG-TEXT+ then ;
: FIG-PERCENT+ ( n -- ) FIG-LEFT @ FMT:INT$ FIG-TEXT+ s" %" FIG-TEXT+ ;
: FIG-LABEL+ ( n -- )
   FIG-LIM @ DB-LIMIT-LABEL$ FIG-TEXT+ s"  " FIG-TEXT+ ;

: FIG+ ( n n -- ) {: k left :}
   k FIG-N @ FIG-LIM ! left FIG-N @ FIG-LEFT !
   FIG-N @ 1+ FIG-N ! ;

: WINDOW-LEFT ( n -- n ) DB-LIMIT-PERCENT LEVEL-FULL swap - ;
: WINDOW-FIG+ ( n -- ) dup WINDOW-LEFT FIG+ ;

: USED-UP? ( n -- bool ) {: k :}
   k 0 < if false exit then
   k DB-LIMIT-PERCENT LEVEL-FULL >= ;

\ Claude's session draws from its weekly allowance: a used-up week leaves
\ the session nothing
: SESSION-FIG+ ( n n n -- ) {: p s w :}
   s 0 < if exit then
   p P-CLAUDE = w USED-UP? and if s 0 FIG+ exit then
   s WINDOW-FIG+ ;

: OTHER-FIGS+ ( n n -- ) {: s w :}
   DB-LIMIT# 0 ?do
      i s <> i w <> and i DB-LIMIT-PERCENT 0 >= and if i WINDOW-FIG+ then
   loop ;

: LOW? ( n -- bool ) {: k :}
   k 0 < if false exit then
   k WINDOW-LEFT LEVEL-HALF < ;

\ a window other than the session and the week runs low
: MODEL-LOW? ( n n -- bool ) {: s w :}
   DB-LIMIT# 0 ?do
      i s <> i w <> and if i LOW? if true unloop exit then then
   loop false ;

ENUM row-state fine tight blocked dead unplanned unprobed ;ENUM

\ an expired live token is its CLI's to refresh, so only a saved one is dead
: DEAD? ( bool -- bool ) {: active :}
   DB-USAGE-STATE MATCH usage-state
      ok OF false ENDOF
      expired OF active 0= ENDOF
      revoked OF true ENDOF
      error OF false ENDOF
      unknown OF false ENDOF
      unsubscribed OF false ENDOF
      throttled OF false ENDOF
      missing OF true ENDOF
      free OF false ENDOF
   ;MATCH ;

\ the organization has no plan the CLI may use
: PLANLESS? ( -- bool )
   DB-USAGE-STATE MATCH usage-state
      ok OF false ENDOF
      expired OF false ENDOF
      revoked OF false ENDOF
      error OF false ENDOF
      unknown OF false ENDOF
      unsubscribed OF true ENDOF
      throttled OF false ENDOF
      missing OF false ENDOF
      free OF true ENDOF
   ;MATCH ;

\ the session or the week, or failing both a window not theirs, runs low
: TIGHT? ( n n -- bool ) {: s w :}
   s 0 >= if s else w then LOW? if true exit then
   s w MODEL-LOW? ;

\ how the row reads at a glance; the session and the week decide whether
\ the account can take work
: ROW-STATE ( bool -- row-state ) {: active :}
   active DEAD? if construct row-state dead exit then
   PLANLESS? if construct row-state unplanned exit then
   DB-LIMIT# 0= if construct row-state unprobed exit then
   SESSION-LABEL$ WINDOW WEEKLY-LABEL$ WINDOW {: s w :}
   s USED-UP? w USED-UP? or if construct row-state blocked exit then
   s w TIGHT? if construct row-state tight exit then
   construct row-state fine ;

\ row i's standing: unprobed while it has no record, else the ROW-STATE of
\ its record, which stays decoded
: ROW-STANDING ( n bool -- row-state ) {: i active :}
   i DB-ROW-USAGE 0= if construct row-state unprobed exit then
   active ROW-STATE ;

: BLOCKED? ( row-state -- bool )
   MATCH row-state
      fine OF false ENDOF
      tight OF false ENDOF
      blocked OF true ENDOF
      dead OF false ENDOF
      unplanned OF false ENDOF
      unprobed OF false ENDOF
   ;MATCH ;

public

\ session, weekly, then every other window with a reading, for provider p
: FIGURES ( n -- ) {: p :}
   0 FIG-N !
   DB-LIMIT# dup FIG-LIMS-RESERVE FIG-LEFTS-RESERVE
   SESSION-LABEL$ WINDOW WEEKLY-LABEL$ WINDOW {: s w :}
   p s w SESSION-FIG+
   w 0 >= if w WINDOW-FIG+ then
   s w OTHER-FIGS+ ;

\ the percent left window k's figure gives; false when it gives none
: WINDOW-FIGURE ( n -- n bool ) {: k :}
   FIG-N @ 0 ?do
      i FIG-LIM @ k = if i FIG-LEFT @ true unloop exit then
   loop 0 false ;

: FIGURE# ( -- n ) FIG-N @ ;

\ figure j's window label, percent left and whether that is below half;
\ valid after FIGURES
: FIGURE ( n -- ^u8 n n bool ) {: j :}
   j FIG-LIM @ DB-LIMIT-LABEL$
   j FIG-LEFT @ dup LEVEL-HALF < ;

: ROW-STATE$ ( row-state -- ^u8 n )
   MATCH row-state
      fine OF s" fine" ENDOF
      tight OF s" tight" ENDOF
      blocked OF s" blocked" ENDOF
      dead OF s" dead" ENDOF
      unplanned OF s" unplanned" ENDOF
      unprobed OF s" unprobed" ENDOF
   ;MATCH ;

\ a click on the row logs in again rather than switches: a saved login
\ that is dead or whose usage checks are rate limited
: RELOGIN? ( bool -- bool ) {: active :}
   active if false exit then
   DB-USAGE-STATE MATCH usage-state
      ok OF false ENDOF
      expired OF true ENDOF
      revoked OF true ENDOF
      error OF false ENDOF
      unknown OF false ENDOF
      unsubscribed OF false ENDOF
      throttled OF true ENDOF
      missing OF true ENDOF
      free OF false ENDOF
   ;MATCH ;

\ what the probe that wrote the record came to; the live login's expired
\ token waits for its CLI to refresh it
: PROBE-OUTCOME$ ( bool -- ^u8 n ) {: active :}
   DB-USAGE-STATE MATCH usage-state
      ok OF s" answered" ENDOF
      expired OF active if s" waiting" else s" answered" then ENDOF
      revoked OF s" answered" ENDOF
      error OF s" failed" ENDOF
      unknown OF s" answered" ENDOF
      unsubscribed OF s" answered" ENDOF
      throttled OF s" failed" ENDOF
      missing OF s" answered" ENDOF
      free OF s" answered" ENDOF
   ;MATCH ;

\ epoch seconds at which the record's reading counts as old; false when it
\ has no limits or no fetch time
: OLD-AT ( -- n bool )
   DB-LIMIT# 0= DB-USAGE-AT 0 <= or if 0 false exit then
   DB-USAGE-AT OLD-AFTER + true ;

\ "72% · 40% · 9%", or "limit" while the session or the week is used up
: FIGURES-TEXT ( n -- ^u8 n ) {: p :}
   false ROW-STATE BLOCKED? if s" limit" exit then
   p FIGURES FIG-TEXT-RESET
   FIG-N @ 0 ?do i FIG-SEP+ i FIG-PERCENT+ loop
   FIG-TEXT$ ;

\ "Session (5-hour) 72% left · Weekly (7-day) 40% left", the figures
\ FIGURES-TEXT gives, each under its window's label; empty when none
: LEFT-TEXT ( n -- ^u8 n ) {: p :}
   p FIGURES FIG-TEXT-RESET
   FIG-N @ 0 ?do
      i FIG-SEP+ i FIG-LABEL+ i FIG-PERCENT+ s"  left" FIG-TEXT+
   loop
   FIG-TEXT$ ;

\ row i's plan as the panel shows it; probed when its usage is decoded
: SHOWN-PLAN$ ( n bool -- ^u8 n ) {: i probed :}
   probed 0= if i DB-ROW-PLAN$ exit then
   DB-USAGE-STATE MATCH usage-state
      ok OF i DB-ROW-PLAN$ ENDOF
      expired OF i DB-ROW-PLAN$ ENDOF
      revoked OF i DB-ROW-PLAN$ ENDOF
      error OF i DB-ROW-PLAN$ ENDOF
      unknown OF i DB-ROW-PLAN$ ENDOF
      unsubscribed OF s" no plan" ENDOF
      throttled OF i DB-ROW-PLAN$ ENDOF
      missing OF i DB-ROW-PLAN$ ENDOF
      free OF s" free" ENDOF
   ;MATCH ;

\ ---- room order -----------------------------------------------------------------
\ The order the saved accounts are offered in: by class, a blocked row then
\ by when it reopens, soonest first, then by table row.
private

\ a window other than the session and the week is used up
: MODEL-OUT? ( n n -- bool ) {: s w :}
   DB-LIMIT# 0 ?do
      i s <> i w <> and if i USED-UP? if true unloop exit then then
   loop false ;

\ the session's and the week's windows; -1 for one with no reading
: DECIDING ( -- n n ) SESSION-LABEL$ WINDOW WEEKLY-LABEL$ WINDOW ;

\ epoch seconds window k reopens; -1 when its reset does not parse
: RESET-EPOCH ( n -- n ) DB-LIMIT-RESETS$ RFC3339>EPOCH ;

\ of the session and the week that are used up, the one that reopens last,
\ the session unless the week's reset parses later; -1 when neither is
: BLOCKING ( n n -- n ) {: s w :}
   s USED-UP? 0= if w USED-UP? if w else -1 then exit then
   w USED-UP? 0= if s exit then
   w RESET-EPOCH {: wt :}
   wt 0 < if s exit then
   wt s RESET-EPOCH > if w else s then ;

: TIGHT-CLASS ( -- n ) DECIDING MODEL-OUT? if 2 else 1 then ;
: BLOCKED-CLASS ( -- n ) DECIDING nip USED-UP? if 4 else 3 then ;

\ a standing's class over the decoded record: 0 fine, 1 tight, 2 tight with
\ a model window used up, 3 session used up, 4 week used up, 5 dead or
\ unplanned, 6 unprobed
: ROOM-CLASS ( row-state -- n )
   MATCH row-state
      fine OF 0 ENDOF
      tight OF TIGHT-CLASS ENDOF
      blocked OF BLOCKED-CLASS ENDOF
      dead OF 5 ENDOF
      unplanned OF 5 ENDOF
      unprobed OF 6 ENDOF
   ;MATCH ;

STR:MAX-I64 constant REOPENS-NEVER   \ after every epoch second

\ ROOM-SORT reserves DB-ROW# of each
DYNAMIC-BUFFER ROOM-ROWS n      \ the row at each place
DYNAMIC-BUFFER ROOM-PLACES n    \ the place of each row
DYNAMIC-BUFFER ROOM-CLASSES n   \ each row's class
DYNAMIC-BUFFER ROOM-KEYS n      \ when a blocked row reopens; REOPENS-NEVER else

\ epoch seconds the decoded record's blocking window reopens
: REOPENS-KEY ( -- n )
   DECIDING BLOCKING RESET-EPOCH
   dup 0 < if drop REOPENS-NEVER then ;

: ROOM-RATE ( n bool -- ) {: i active :}
   i active ROW-STANDING {: st :}
   st ROOM-CLASS i ROOM-CLASSES !
   st BLOCKED? if REOPENS-KEY else REOPENS-NEVER then i ROOM-KEYS ! ;

\ row a goes before row b
: ROOM-BEFORE? ( n n -- bool ) {: a b :}
   a ROOM-CLASSES @ b ROOM-CLASSES @ {: ca cb :}
   ca cb <> if ca cb < exit then
   a ROOM-KEYS @ b ROOM-KEYS @ {: ka kb :}
   ka kb <> if ka kb < exit then
   a b < ;

: ROOM-RESERVE ( n -- )
   dup ROOM-ROWS-RESERVE dup ROOM-PLACES-RESERVE
   dup ROOM-CLASSES-RESERVE ROOM-KEYS-RESERVE ;

public

\ the table's rows in room order, row r read as the active login's (-1:
\ none); holds until the next store read and leaves some record decoded
: ROOM-SORT ( n -- ) {: r :}
   DB-ROW# {: n :}
   n 0= if exit then
   n ROOM-RESERVE
   n 0 ?do i i r = ROOM-RATE i i ROOM-ROWS ! loop
   0 ROOM-ROWS n [: ROOM-BEFORE? ;] SORT:SORT!
   n 0 ?do i i ROOM-ROWS @ ROOM-PLACES ! loop ;

\ the row at place k, and row i's place
: ROOM-AT ( n -- n ) ROOM-ROWS @ ;
: ROOM-PLACE ( n -- n ) ROOM-PLACES @ ;

\ when a blocked record can take work again: the resetsAt of its blocking
\ window
: REOPENS-AT$ ( -- ^u8 n ) DECIDING BLOCKING DB-LIMIT-RESETS$ ;

;package
