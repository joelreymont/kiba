\ sw-status.f - what `kiba status` shows: one provider's saved accounts and
\ live login read from the store, and the figures of a usage record.
require ../src/sw-db.f
require ../src/sw-claude.f
require ../src/sw-codex.f
require ../src/sw-base.f
require ../src/sw-identity.f
require ../src/sw-store.f
require src/lib/fmt.f
require src/lib/byte-buffer.f
require src/lib/prelude.f
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
   i DB-ROW-NAME$ STAT-NAME STAT-NAME-U @ STR= ;

\ ---- figures --------------------------------------------------------------------
\ The panel's reading of the usage record DB-ROW-USAGE last decoded.
private

100 constant LEVEL-FULL
50 constant LEVEL-HALF

\ the first window under the label that has a reading; -1 for none
: WINDOW ( ptr u8 n -- n ) {: a u :}
   DB-LIMIT# 0 ?do
      i DB-LIMIT-LABEL$ a u STR= i DB-LIMIT-PERCENT 0 >= and if i unloop exit then
   loop -1 ;

\ each window gives at most one figure, so FIGURES reserves DB-LIMIT# of each
DYNAMIC-BUFFER FIG-LIMS n    \ the window whose label a figure carries
DYNAMIC-BUFFER FIG-LEFTS n   \ whole percent left
variable FIG-N

: FIG-LIM ( n -- ptr n ) FIG-LIMS ;
: FIG-LEFT ( n -- ptr n ) FIG-LEFTS ;

create FIG-TEXT BUF:HDR-BYTES allot   \ FIGURES-TEXT's answer, which grows with the record
: FIG-TEXT+ ( ptr u8 n -- ) BUF:N>BLEN FIG-TEXT BUF:APPEND-SPAN ;

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

\ the percent left the first figure under window k's label gives; false
\ when no figure carries that label
: WINDOW-FIGURE ( n -- n bool ) {: k :}
   FIG-N @ 0 ?do
      i FIG-LIM @ DB-LIMIT-LABEL$ k DB-LIMIT-LABEL$ STR= if
         i FIG-LEFT @ true unloop exit
      then
   loop 0 false ;

\ "72% · 40% · 9%", or "limit" while the session or the week is used up
: FIGURES-TEXT ( n -- ptr u8 n ) {: p :}
   false ROW-STATE BLOCKED? if s" limit" exit then
   p FIGURES
   FIG-TEXT 64 BUF:N>BLEN BUF:RESET
   FIG-N @ 0 ?do
      i 0 > if s"  · " FIG-TEXT+ then
      i FIG-LEFT @ FMT:INT$ FIG-TEXT+ s" %" FIG-TEXT+
   loop
   FIG-TEXT BUF:SPAN$ BUF:BLEN>N ;

\ row i's plan as the panel shows it; probed when its usage is decoded
: SHOWN-PLAN$ ( n bool -- ptr u8 n ) {: i probed :}
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

;package
