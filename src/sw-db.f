\ sw-db.f - the account store: saved logins, the live and in-flight markers
\ and the history, in one SQLite database, plus the usage record's codec.
\ Every read fills the row table, which the next read replaces; every write
\ runs inside DB-WRITE's transaction.
require ../src/sw-sqlite.f
require ../src/sw-identity.f
require src/lib/error.f
require src/lib/entropy.f
require src/lib/ffi-abi.f
require src/lib/fsm.f
require src/lib/fmt.f
require src/lib/json.f

package SW

5 constant DB-VERSION            \ the schema this build writes

\ ---- SQL text ---------------------------------------------------------------
1024 constant SQL-TEXT-CAP
create SQL-TEXT SQL-TEXT-CAP allot   variable SQL-TEXT-U

: SQL-RESET ( -- ) 0 SQL-TEXT-U ! ;
: SQL$ ( -- ptr u8 n ) SQL-TEXT SQL-TEXT-U @ ;

: SQL+ ( ptr u8 n -- ) {: a u :}
   SQL-TEXT-U @ u + SQL-TEXT-CAP > if E-SW-CAPACITY throw then
   a SQL-TEXT SQL-TEXT-U @ + u BYTE-COPY
   SQL-TEXT-U @ u + SQL-TEXT-U ! ;

\ ---- the usage record --------------------------------------------------------
\ What the last probe learned about a saved login: one record, which the
\ setters, DB-USAGE-DECODE and DB-ROW-USAGE fill and the encoder reads.
public
ENUM usage-state ok expired revoked error unknown unsubscribed throttled missing free ;ENUM
private

16 constant REC-LIM-MAX
128 constant REC-LABEL-CAP
64 constant REC-RESET-CAP
1024 constant REC-NOTE-CAP
128 constant REC-WORD-CAP

variable REC-AT                            \ epoch seconds; 0 when never fetched
TYPED-VARIABLE REC-STATE usage-state
create REC-NOTE REC-NOTE-CAP allot         variable REC-NOTE-U
variable REC-LIM-N
create REC-LABELS REC-LIM-MAX REC-LABEL-CAP * allot
create REC-LABEL-US REC-LIM-MAX cells allot
create REC-PCTS REC-LIM-MAX cells allot    \ whole percent used; negative for no reading
create REC-RESETS REC-LIM-MAX REC-RESET-CAP * allot
create REC-RESET-US REC-LIM-MAX cells allot
variable REC-OFFER                         \ 1 when the record holds a reset offer
variable REC-COUNT
create REC-PROGRAM REC-WORD-CAP allot      variable REC-PROGRAM-U
create REC-GRANT REC-WORD-CAP allot        variable REC-GRANT-U

: LABEL-ROW ( n -- ptr u8 ) REC-LABEL-CAP * REC-LABELS + ;
: LABEL-U ( n -- ptr n ) cells REC-LABEL-US + ;
: PCT-CELL ( n -- ptr n ) cells REC-PCTS + ;
: RESET-ROW ( n -- ptr u8 ) REC-RESET-CAP * REC-RESETS + ;
: RESET-U ( n -- ptr n ) cells REC-RESET-US + ;

public

: DB-STATE$ ( usage-state -- ptr u8 n )
   MATCH usage-state
      ok OF s" ok" ENDOF
      expired OF s" expired" ENDOF
      revoked OF s" revoked" ENDOF
      error OF s" error" ENDOF
      unknown OF s" unknown" ENDOF
      unsubscribed OF s" unsubscribed" ENDOF
      throttled OF s" throttled" ENDOF
      missing OF s" missing" ENDOF
      free OF s" free" ENDOF
   ;MATCH ;

\ starts a record: no limits and no reset offer yet
: DB-USAGE! ( n usage-state ptr u8 n -- ) {: at st a u :}
   at REC-AT ! st REC-STATE !
   a u REC-NOTE REC-NOTE-U REC-NOTE-CAP SPAN!
   0 REC-LIM-N ! 0 REC-OFFER ! ;

\ label, percent used, reset instant
: DB-LIMIT+ ( ptr u8 n n ptr u8 n -- ) {: la lu pct ra ru :}
   REC-LIM-N @ {: i :}
   i REC-LIM-MAX >= if E-SW-CAPACITY throw then
   la lu i LABEL-ROW i LABEL-U REC-LABEL-CAP SPAN!
   pct i PCT-CELL !
   ra ru i RESET-ROW i RESET-U REC-RESET-CAP SPAN!
   i 1+ REC-LIM-N ! ;

\ resets available now, program, grant
: DB-RESETS! ( n ptr u8 n ptr u8 n -- ) {: k pa pu ga gu :}
   k REC-COUNT !
   pa pu REC-PROGRAM REC-PROGRAM-U REC-WORD-CAP SPAN!
   ga gu REC-GRANT REC-GRANT-U REC-WORD-CAP SPAN!
   1 REC-OFFER ! ;

: DB-USAGE-AT ( -- n ) REC-AT @ ;
: DB-USAGE-STATE ( -- usage-state ) REC-STATE @ ;
: DB-USAGE-NOTE$ ( -- ptr u8 n ) REC-NOTE REC-NOTE-U @ ;
: DB-LIMIT# ( -- n ) REC-LIM-N @ ;
: DB-LIMIT-LABEL$ ( n -- ptr u8 n ) {: i :} i LABEL-ROW i LABEL-U @ ;
: DB-LIMIT-PERCENT ( n -- n ) PCT-CELL @ ;
: DB-LIMIT-RESETS$ ( n -- ptr u8 n ) {: i :} i RESET-ROW i RESET-U @ ;
: DB-RESETS? ( -- bool ) REC-OFFER @ 0<> ;
: DB-RESETS-COUNT ( -- n ) REC-COUNT @ ;
: DB-RESETS-PROGRAM$ ( -- ptr u8 n ) REC-PROGRAM REC-PROGRAM-U @ ;
: DB-RESETS-GRANT$ ( -- ptr u8 n ) REC-GRANT REC-GRANT-U @ ;

\ ---- the encoder ------------------------------------------------------------
\ The bytes kiba-mac's JSONEncoder writes with .sortedKeys: keys in order, no
\ spaces, `/` escaped as `\/`, other control bytes as lowercase \u00xx.
private

DYNAMIC-BUFFER ENC-TEXT u8
variable ENC-U
create ENC-ONE 1 allot

: ENC$ ( -- ptr u8 n ) 0 ENC-TEXT ENC-U @ ;

: ENC+ ( ptr u8 n -- ) {: a u :}
   u 0= if exit then
   ENC-U @ u + ENC-TEXT-RESERVE
   a ENC-U @ ENC-TEXT u BYTE-COPY
   ENC-U @ u + ENC-U ! ;

: ENC-C ( n -- ) ENC-ONE c! ENC-ONE 1 ENC+ ;
: ENC-INT ( n -- ) FMT:INT$ ENC+ ;
: ENC-PAIR ( n -- ) $5C ENC-C ENC-C ;
: HEX-C ( n -- n ) dup 10 < if [char] 0 + exit then 87 + ;   \ lowercase
: ENC-HEX ( n -- ) HEX-C ENC-C ;
: ENC-COMMA ( -- ) $2C ENC-C ;

: ENC-CONTROL ( n -- ) {: c :}
   c $08 = if [char] b ENC-PAIR exit then
   c $0C = if [char] f ENC-PAIR exit then
   c $0A = if [char] n ENC-PAIR exit then
   c $0D = if [char] r ENC-PAIR exit then
   c $09 = if [char] t ENC-PAIR exit then
   s" \u00" ENC+ c 4 rshift ENC-HEX c 15 and ENC-HEX ;

: ENC-BYTE ( n -- ) {: c :}
   c $22 = c $5C = or c $2F = or if c ENC-PAIR exit then
   c $20 < if c ENC-CONTROL exit then
   c ENC-C ;

: ENC-STR ( ptr u8 n -- ) {: a u :}
   $22 ENC-C
   u 0 ?do a i + c@ ENC-BYTE loop
   $22 ENC-C ;

: ENC-KEY ( ptr u8 n -- ) $22 ENC-C ENC+ $22 ENC-C $3A ENC-C ;

\ the share of a window left, null for a window with no reading
: ENC-LEFT ( n -- ) {: pct :}
   s" left" ENC-KEY
   pct 0 < if s" null" ENC+ exit then
   100 pct - 0 max ENC-INT ;

\ history details give each limit its share left as well
: ENC-LIMIT ( n bool -- ) {: i left :}
   $7B ENC-C
   s" label" ENC-KEY i DB-LIMIT-LABEL$ ENC-STR ENC-COMMA
   left if i DB-LIMIT-PERCENT ENC-LEFT ENC-COMMA then
   s" percent" ENC-KEY i DB-LIMIT-PERCENT ENC-INT ENC-COMMA
   s" resetsAt" ENC-KEY i DB-LIMIT-RESETS$ ENC-STR
   $7D ENC-C ;

: ENC-LIMITS ( bool -- ) {: left :}
   s" limits" ENC-KEY $5B ENC-C
   DB-LIMIT# 0 ?do
      i 0 > if ENC-COMMA then
      i left ENC-LIMIT
   loop
   $5D ENC-C ENC-COMMA ;

\ an absent offer writes no key
: ENC-OFFER ( -- )
   DB-RESETS? 0= if exit then
   s" resets" ENC-KEY $7B ENC-C
   s" count" ENC-KEY DB-RESETS-COUNT ENC-INT ENC-COMMA
   s" grant" ENC-KEY DB-RESETS-GRANT$ ENC-STR ENC-COMMA
   s" program" ENC-KEY DB-RESETS-PROGRAM$ ENC-STR
   $7D ENC-C ENC-COMMA ;

: ENC-HEAD ( bool -- ) {: left :}
   0 ENC-U ! $7B ENC-C
   s" fetchedAt" ENC-KEY DB-USAGE-AT ENC-INT ENC-COMMA
   left ENC-LIMITS ;

: ENC-TAIL ( -- )
   s" note" ENC-KEY DB-USAGE-NOTE$ ENC-STR ENC-COMMA
   ENC-OFFER
   s" state" ENC-KEY DB-USAGE-STATE DB-STATE$ ENC-STR
   $7D ENC-C ;

\ a usage event's details: the record plus whether the probe read it live
: ENC-DETAILS ( bool -- ) {: live :}
   true ENC-HEAD
   s" live" ENC-KEY live if s" true" else s" false" then ENC+ ENC-COMMA
   ENC-TAIL ;

public

\ the record's stored form, valid until the next encode
: DB-USAGE-ENCODE ( -- ptr u8 n ) false ENC-HEAD ENC-TAIL ENC$ ;

\ ---- the decoder ------------------------------------------------------------
\ A record that does not decode reads as unreadable, as kiba-mac's does:
\ every required key present with its type, unknown keys skipped.
private

TYPED-VARIABLE DEC-RD JSON:cursor
PTR-VARIABLE DEC-A   variable DEC-U
variable DEC-SEEN                          \ one bit per required key found
create DEC-WORD 16 allot   variable DEC-WORD-U

: SEEN+ ( n -- ) DEC-SEEN @ or DEC-SEEN ! ;

: DEC-NEXT ( JSON:reader n -- JSON:reader ) {: want :}
   JSON:READ-NEXT want <> if E-SW-JSON throw then ;

: DEC-INT ( JSON:reader -- JSON:reader n )
   JSON:T-INT DEC-NEXT JSON:READ-INT ;

: DEC-STR ( JSON:reader ptr u8 ptr n n -- JSON:reader ) {: dst up cap :}
   JSON:T-STR DEC-NEXT dst cap JSON:READ-STR up ! ;

: MEMBER? ( JSON:reader ptr u8 n -- JSON:reader bool ) JSON:READ-STR-EQ? ;

: STATE-IS? ( ptr u8 n -- bool ) DEC-WORD DEC-WORD-U @ STR= ;

: NAMED-STATE ( -- usage-state )
   s" ok" STATE-IS? if construct usage-state ok exit then
   s" expired" STATE-IS? if construct usage-state expired exit then
   s" revoked" STATE-IS? if construct usage-state revoked exit then
   s" error" STATE-IS? if construct usage-state error exit then
   s" unknown" STATE-IS? if construct usage-state unknown exit then
   s" unsubscribed" STATE-IS? if construct usage-state unsubscribed exit then
   s" throttled" STATE-IS? if construct usage-state throttled exit then
   s" missing" STATE-IS? if construct usage-state missing exit then
   s" free" STATE-IS? if construct usage-state free exit then
   E-SW-JSON throw ;

\ the members of an object whose opening brace was read, each key handed to
\ a member word that reads or skips its value
: DEC-MEMBERS ( JSON:reader [ JSON:reader -- JSON:reader ] -- JSON:reader )
   {: member :}
   begin JSON:READ-NEXT dup JSON:T-KEY = while
      drop member execute
   repeat
   JSON:T-OBJ-END <> if E-SW-JSON throw then ;

: SKIP-MEMBER ( JSON:reader -- JSON:reader )
   JSON:READ-NEXT drop JSON:READ-SKIP-VALUE ;

: REQUIRE-SEEN ( n -- ) DEC-SEEN @ <> if E-SW-JSON throw then ;

variable DLIM-PCT
create DLIM-LABEL REC-LABEL-CAP allot   variable DLIM-LABEL-U
create DLIM-RESET REC-RESET-CAP allot   variable DLIM-RESET-U

: LIMIT-MEMBER ( JSON:reader -- JSON:reader )
   s" label" MEMBER? if DLIM-LABEL DLIM-LABEL-U REC-LABEL-CAP DEC-STR 1 SEEN+ exit then
   s" percent" MEMBER? if DEC-INT DLIM-PCT ! 2 SEEN+ exit then
   s" resetsAt" MEMBER? if DLIM-RESET DLIM-RESET-U REC-RESET-CAP DEC-STR 4 SEEN+ exit then
   SKIP-MEMBER ;

: DEC-LIMIT ( JSON:reader -- JSON:reader )
   0 DEC-SEEN !
   [: LIMIT-MEMBER ;] DEC-MEMBERS
   7 REQUIRE-SEEN
   DLIM-LABEL DLIM-LABEL-U @ DLIM-PCT @ DLIM-RESET DLIM-RESET-U @ DB-LIMIT+ ;

: DEC-LIMITS ( JSON:reader -- JSON:reader )
   JSON:T-ARR DEC-NEXT
   begin JSON:READ-NEXT dup JSON:T-OBJ = while
      drop DEC-SEEN @ {: seen :}
      DEC-LIMIT seen DEC-SEEN !
   repeat
   JSON:T-ARR-END <> if E-SW-JSON throw then ;

variable OFFER-COUNT

: OFFER-MEMBER ( JSON:reader -- JSON:reader )
   s" count" MEMBER? if DEC-INT OFFER-COUNT ! 1 SEEN+ exit then
   s" program" MEMBER? if REC-PROGRAM REC-PROGRAM-U REC-WORD-CAP DEC-STR 2 SEEN+ exit then
   s" grant" MEMBER? if REC-GRANT REC-GRANT-U REC-WORD-CAP DEC-STR 4 SEEN+ exit then
   SKIP-MEMBER ;

\ null, like an absent key, is no offer
: DEC-OFFER ( JSON:reader -- JSON:reader )
   0 REC-OFFER !
   JSON:READ-NEXT {: k :}
   k JSON:T-NULL = if exit then
   k JSON:T-OBJ <> if E-SW-JSON throw then
   DEC-SEEN @ {: seen :}
   0 DEC-SEEN !
   [: OFFER-MEMBER ;] DEC-MEMBERS
   7 REQUIRE-SEEN
   OFFER-COUNT @ REC-COUNT ! 1 REC-OFFER !
   seen DEC-SEEN ! ;

: USAGE-MEMBER ( JSON:reader -- JSON:reader )
   s" fetchedAt" MEMBER? if DEC-INT REC-AT ! 1 SEEN+ exit then
   s" state" MEMBER? if
      DEC-WORD DEC-WORD-U 16 DEC-STR NAMED-STATE REC-STATE ! 2 SEEN+ exit
   then
   s" note" MEMBER? if REC-NOTE REC-NOTE-U REC-NOTE-CAP DEC-STR 4 SEEN+ exit then
   s" limits" MEMBER? if DEC-LIMITS 8 SEEN+ exit then
   s" resets" MEMBER? if DEC-OFFER exit then
   SKIP-MEMBER ;

: DEC-RUN ( -- )
   0 DEC-SEEN ! 0 REC-LIM-N ! 0 REC-OFFER !
   DEC-RD DEC-A @ DEC-U @ JSON:READ-INIT
   JSON:T-OBJ DEC-NEXT
   [: USAGE-MEMBER ;] DEC-MEMBERS
   JSON:READ-FINISH
   15 REQUIRE-SEEN ;

ENUM decode-step decoding decoded ;ENUM
ENUM decode-input parsed garbled ;ENUM

: DEC-SENSE ( n -- decode-input )
   drop [: DEC-RUN ;] catch {: rc :}
   rc 0= if construct decode-input parsed exit then
   construct decode-input garbled ;

\ the throw abandoned the reader, so its record is released here
: DEC-UNREADABLE ( n -- )
   drop DEC-RD JSON:READ-DISPOSE
   0 construct usage-state unknown
   s" usage record is unreadable; refresh usage" DB-USAGE! ;

FSM:DEFINE DECODING ( n ) decode-step decode-input
   IN decoding DEC-SENSE
      parsed - >decoded
      garbled DEC-UNREADABLE >decoded
   FINAL decoded -
;DEFINE

public

: DB-USAGE-DECODE ( ptr u8 n -- )
   DEC-U ! DEC-A !
   0 construct decode-step decoding DECODING ;

\ ---- the row table ------------------------------------------------------------
\ Each kept row holds ROW-COLS columns, each an offset into ROW-BYTES and a
\ length, -1 for NULL. Growth moves both buffers: spans last until the next read.
private

DYNAMIC-BUFFER ROW-BYTES u8   variable ROW-BYTES-U
DYNAMIC-BUFFER ROW-SPANS n
variable ROW-N
variable ROW-COLS

: ROW-RESET ( n -- )
   ROW-COLS ! 0 ROW-N ! 0 ROW-BYTES-U !
   1 ROW-BYTES-RESERVE ;

: SPAN-AT ( n n -- n ) {: r c :} r ROW-COLS @ * c + 2 * ;

: ROW-BYTES+ ( ptr u8 n -- n ) {: a u :}
   ROW-BYTES-U @ {: off :}
   off u + 1+ ROW-BYTES-RESERVE
   a off ROW-BYTES u BYTE-COPY
   off u + ROW-BYTES-U !
   off ;

: KEEP-COL ( n -- ) {: c :}
   c DB-COL-BYTES {: a u :}
   a u 0 max ROW-BYTES+ ROW-N @ c SPAN-AT ROW-SPANS !
   u ROW-N @ c SPAN-AT 1+ ROW-SPANS ! ;

\ copies the current result row into the table
: ROW-KEEP ( -- )
   ROW-N @ 1+ ROW-COLS @ * 2 * ROW-SPANS-RESERVE
   ROW-COLS @ 0 ?do i KEEP-COL loop
   ROW-N @ 1+ ROW-N ! ;

\ a column as stored; length -1 for NULL
: ROW-SPAN ( n n -- ptr u8 n ) {: r c :}
   r c SPAN-AT ROW-SPANS @ {: off :}
   r c SPAN-AT 1+ ROW-SPANS @ {: u :}
   u 0 < if NULL-PTR BYTE-VIEW -1 exit then
   off ROW-BYTES u ;

\ a NOT NULL column, empty should a hand-written row hold NULL
: ROW-TEXT$ ( n n -- ptr u8 n ) ROW-SPAN 0 max ;

public

: DB-ROW# ( -- n ) ROW-N @ ;
: DB-ROW-NAME$ ( n -- ptr u8 n ) 0 ROW-TEXT$ ;
: DB-ROW-EMAIL$ ( n -- ptr u8 n ) 1 ROW-TEXT$ ;
: DB-ROW-ORG$ ( n -- ptr u8 n ) 2 ROW-TEXT$ ;
: DB-ROW-PLAN$ ( n -- ptr u8 n ) 3 ROW-TEXT$ ;
\ Claude: the credentials.json bytes; Codex: the auth.json bytes
: DB-ROW-LOGIN$ ( n -- ptr u8 n ) 4 ROW-TEXT$ ;
\ Claude: the oauthAccount object's bytes; Codex: length -1, none
: DB-ROW-PROFILE$ ( n -- ptr u8 n ) 5 ROW-SPAN ;

\ decodes the row's usage into the usage record; false before its first probe
: DB-ROW-USAGE ( n -- bool )
   6 ROW-SPAN {: a u :}
   u 0 < if false exit then
   a u DB-USAGE-DECODE true ;

\ ---- schema -------------------------------------------------------------------
private

: SCHEMA-RUN ( -- ) SQL$ s" schema" DB-EXEC ;

: ACCOUNT-TABLE ( -- )
   SQL-RESET s" CREATE TABLE IF NOT EXISTS account (" SQL+
   s" provider TEXT NOT NULL, name TEXT NOT NULL, email TEXT NOT NULL," SQL+
   s" org TEXT NOT NULL, plan TEXT NOT NULL, login BLOB NOT NULL," SQL+
   s" profile BLOB, usage TEXT, PRIMARY KEY (provider, name)" SQL+
   s" ) WITHOUT ROWID" SQL+ SCHEMA-RUN ;

: MARKER-TABLES ( -- )
   SQL-RESET s" CREATE TABLE IF NOT EXISTS live (provider TEXT PRIMARY KEY," SQL+
   s" installed TEXT NOT NULL, installed_at INTEGER) WITHOUT ROWID" SQL+ SCHEMA-RUN
   SQL-RESET s" CREATE TABLE IF NOT EXISTS pending (provider TEXT PRIMARY KEY," SQL+
   s" name TEXT NOT NULL, owner TEXT) WITHOUT ROWID" SQL+ SCHEMA-RUN
   SQL-RESET s" CREATE TABLE IF NOT EXISTS adding (provider TEXT PRIMARY KEY," SQL+
   s" live BLOB, service TEXT NOT NULL) WITHOUT ROWID" SQL+ SCHEMA-RUN ;

: HISTORY-TABLE ( -- )
   SQL-RESET s" CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY," SQL+
   s" provider TEXT NOT NULL, kind TEXT NOT NULL, at_us INTEGER NOT NULL," SQL+
   s" name TEXT NOT NULL, email TEXT NOT NULL, org TEXT NOT NULL," SQL+
   s" plan TEXT NOT NULL, details TEXT NOT NULL)" SQL+ SCHEMA-RUN
   s" CREATE INDEX IF NOT EXISTS history_provider ON history(provider, id)"
   s" schema" DB-EXEC ;

variable FOUND-N
variable FOUND-AT

\ whether sql selects a row
: ROW-FOUND? ( ptr u8 n -- bool ) {: a u :}
   0 FOUND-N !
   a u s" schema" [: ;] [: 1 FOUND-N ! ;] DB-QUERY
   FOUND-N @ 0<> ;

: CHECK-VERSION ( -- )
   0 FOUND-N !
   s" PRAGMA user_version" s" schema" [: ;] [: 0 DB-COL-INT FOUND-N ! ;] DB-QUERY
   FOUND-N @ DB-VERSION > if E-SW-DB-VERSION throw then ;

\ adds a column an older store lacks, when the probe finds none
: MIGRATE ( ptr u8 n ptr u8 n -- ) {: pa pu aa au :}
   pa pu ROW-FOUND? if exit then
   aa au s" schema" DB-EXEC ;

\ A version 1 store's pending table lacks owner: its marker is owned by no
\ install. A version 1 or 2 adding table lacks service; '' is the service
\ every Linux item is filed under. Version 1 to 3 live rows lack the
\ install time until the next install notes one.
: MIGRATIONS ( -- )
   s" SELECT 1 FROM pragma_table_info('pending') WHERE name = 'owner'"
   s" ALTER TABLE pending ADD COLUMN owner TEXT" MIGRATE
   s" SELECT 1 FROM pragma_table_info('adding') WHERE name = 'service'"
   s" ALTER TABLE adding ADD COLUMN service TEXT NOT NULL DEFAULT ''" MIGRATE
   s" SELECT 1 FROM pragma_table_info('live') WHERE name = 'installed_at'"
   s" ALTER TABLE live ADD COLUMN installed_at INTEGER" MIGRATE ;

\ a store a newer build wrote is refused untouched
: SCHEMA ( -- )
   CHECK-VERSION
   SQL-RESET s" PRAGMA user_version = " SQL+ DB-VERSION FMT:INT$ SQL+ SCHEMA-RUN
   ACCOUNT-TABLE MARKER-TABLES HISTORY-TABLE
   MIGRATIONS ;

\ ---- the write transaction ---------------------------------------------------
\ BEGIN IMMEDIATE moves idle to open, holding off every other writer; the
\ body returning moves to committing, its throw to rolling-back, which rolls
\ back while SQLite still reports a transaction and rethrows. Write words
\ run only while the state is open.
ENUM tx-state idle open committing rolling-back ;ENUM
ENUM tx-input returned threw ;ENUM
ENUM begin-input begun ;ENUM
ENUM commit-input committed failed ;ENUM
ENUM rollback-input live gone ;ENUM

TYPED-VARIABLE TX-STATE tx-state
variable TX-CODE                     \ what the body or COMMIT threw

: TX-BEGIN ( [ -- ] -- begin-input )
   drop s" BEGIN IMMEDIATE" s" begin" DB-EXEC
   construct begin-input begun ;

: TX-BODY ( [ -- ] -- tx-input )
   catch {: rc :} rc TX-CODE !
   rc 0= if construct tx-input returned exit then
   construct tx-input threw ;

: TX-COMMIT ( [ -- ] -- commit-input )
   drop [: s" COMMIT" s" commit" DB-EXEC ;] catch {: rc :} rc TX-CODE !
   rc 0= if construct commit-input committed exit then
   construct commit-input failed ;

: TX-LIVE ( [ -- ] -- rollback-input )
   drop SQL-IN-TX? if construct rollback-input live exit then
   construct rollback-input gone ;

: TX-RETHROW ( [ -- ] -- ) drop TX-CODE @ throw ;

: TX-ROLLBACK ( [ -- ] -- )
   s" ROLLBACK" s" rollback" DB-EXEC TX-RETHROW ;

FSM:DEFINE WRITE-TX ( [ -- ] ) tx-state tx-input
   IN idle TX-BEGIN ( begin-input )
      begun - >open
   IN open TX-BODY
      returned - >committing
      threw - >rolling-back
   IN committing TX-COMMIT ( commit-input )
      committed - >idle
      failed - >rolling-back
   IN rolling-back TX-LIVE ( rollback-input )
      live TX-ROLLBACK >idle
      gone TX-RETHROW >idle
;DEFINE

: TX-IDLE? ( tx-state -- bool )
   MATCH tx-state
      idle OF true ENDOF
      open OF false ENDOF
      committing OF false ENDOF
      rolling-back OF false ENDOF
   ;MATCH ;

: TX-OPEN? ( -- bool )
   TX-STATE @ MATCH tx-state
      idle OF false ENDOF
      open OF true ENDOF
      committing OF false ENDOF
      rolling-back OF false ENDOF
   ;MATCH ;

\ each step's state is the one write words see
: TX-DRIVE ( [ -- ] -- ) {: body :}
   construct tx-state idle
   begin
      body swap WRITE-TX-STEP drop
      dup TX-STATE ! dup TX-IDLE?
   until drop ;

: TX-CHECK ( ptr u8 n -- ) {: op ou :}
   TX-OPEN? 0= if op ou s" transaction is closed" DB-THROW then ;

\ one statement of the open transaction
: TX-RUN ( ptr u8 n ptr u8 n [ -- ] -- ) {: sql su op ou bind :}
   op ou TX-CHECK
   sql su op ou bind DB-RUN ;

public

\ runs the body in one BEGIN IMMEDIATE transaction and commits; a throw rolls
\ back and rethrows. A throw from the machine itself leaves it idle too.
: DB-WRITE ( [ -- ] -- ) {: body :}
   [: body TX-DRIVE ;]
   [: construct tx-state idle TX-STATE ! ;] finally ;

\ ---- opening ------------------------------------------------------------------
private

ENUM open-state closed ready ;ENUM
ENUM open-input applied refused ;ENUM
variable OPEN-CODE

: OPEN-RUN ( -- )
   STORE$ ENSURE-PRIVATE
   DB-PATH$ SQL-CONNECT
   [: SCHEMA ;] DB-WRITE ;

: OPEN-SENSE ( n -- open-input )
   drop SQL-H @ 0<> if s" open" s" the store is already open" DB-THROW then
   [: OPEN-RUN ;] catch {: rc :} rc OPEN-CODE !
   rc 0= if construct open-input applied exit then
   construct open-input refused ;

: OPEN-REFUSE ( n -- ) drop SQL-DISCONNECT OPEN-CODE @ throw ;

FSM:DEFINE OPENING ( n ) open-state open-input
   IN closed OPEN-SENSE
      applied - >ready
      refused OPEN-REFUSE >closed
   FINAL ready -
;DEFINE

public

\ creates the store directory (0700) and database (0600) when missing and
\ brings the schema to DB-VERSION; a failed open leaves the store closed
: DB-OPEN ( -- ) 0 construct open-state closed OPENING ;

: DB-CLOSE ( -- ) SQL-DISCONNECT ;

\ ---- reads --------------------------------------------------------------------
private

: ACCOUNT-SQL ( -- )
   SQL-RESET s" SELECT name, email, org, plan, login, profile, usage" SQL+
   s"  FROM account WHERE provider = ?" SQL+ ;

\ a name that fails NAME-OK? was written by hand
: ACCOUNT-ROW ( -- ) 0 DB-COL-BYTES CHECK-NAME ROW-KEEP ;

public

\ the provider's saved logins in name order, into the row table
: DB-LIST ( n -- ) {: p :}
   7 ROW-RESET
   ACCOUNT-SQL s"  ORDER BY name" SQL+
   SQL$ s" list" [: p PROVIDER$ DB-TEXT+ ;] [: ACCOUNT-ROW ;] DB-QUERY ;

\ the saved login as row 0; false when there is none
: DB-FETCH ( n ptr u8 n -- bool ) {: p a u :}
   7 ROW-RESET
   ACCOUNT-SQL s"  AND name = ?" SQL+
   SQL$ s" fetch" [: p PROVIDER$ DB-TEXT+ a u DB-TEXT+ ;] [: ACCOUNT-ROW ;] DB-QUERY
   ROW-N @ 0 > ;

private

create QUERY-NAME NAME-CAP allot   variable QUERY-NAME-U

: QUERY-ROW ( -- )
   0 DB-COL-BYTES {: a u :}
   a u CHECK-NAME
   a u QUERY-NAME QUERY-NAME-U NAME-CAP SPAN!
   1 FOUND-N ! ;

\ the name sql selects for the provider, read without touching the row table
\ and lasting until the next such read; false when there is no row
: NAME-QUERY ( n ptr u8 n ptr u8 n -- ptr u8 n bool )
   {: p sql su op ou :}
   0 FOUND-N ! 0 QUERY-NAME-U !
   sql su op ou [: p PROVIDER$ DB-TEXT+ ;] [: QUERY-ROW ;] DB-QUERY
   QUERY-NAME QUERY-NAME-U @ FOUND-N @ 0<> ;

create CAND-BUF NAME-CAP allot
variable HIT-K
variable FREE-K

\ the bare email for 1, else "email #k"; too long to be a name is empty
: CANDIDATE ( n ptr u8 n -- ptr u8 n ) {: k e eu :}
   k 1 = if e eu exit then
   eu 3 + NAME-CAP 1- > if CAND-BUF 0 exit then
   e CAND-BUF eu BYTE-COPY
   s"  #" drop CAND-BUF eu + 2 BYTE-COPY
   [char] 0 k + CAND-BUF eu + 2 + c!
   CAND-BUF eu 3 + ;

9 constant SLOT-TRIES                 \ the bare email, then "email #2" to "email #9"

\ which candidate k the name is; 0 when none
: CANDIDATE# ( ptr u8 n n -- n ) {: a u id :}
   SLOT-TRIES 1+ 1 ?do
      i id EMAIL$ CANDIDATE a u STR= if i unloop exit then
   loop 0 ;

\ bit k of TAKEN marks candidate k as saved, of SAME as saved with the live org
variable TAKEN
variable SAME

: NAME-ROW ( n -- ) {: id :}
   0 DB-COL-BYTES {: a u :}
   a u CHECK-NAME
   a u id CANDIDATE# {: k :}
   k 0= if exit then
   TAKEN @ 1 k lshift or TAKEN !
   1 DB-COL-BYTES id ORG$ STR= if SAME @ 1 k lshift or SAME ! then ;

\ the first candidate saved with the live org, else the first unsaved one
: CANDIDATE-CHECK ( n n -- ) {: k id :}
   k id EMAIL$ CANDIDATE NAME-OK? 0= if exit then
   1 k lshift {: bit :}
   TAKEN @ bit and 0= if FREE-K @ 0= if k FREE-K ! then exit then
   SAME @ bit and 0<> HIT-K @ 0= and if k HIT-K ! then ;

DYNAMIC-BUFFER ADD-LIVE u8   variable ADD-LIVE-U

\ keeps column 0 in ADD-LIVE; length -1 for NULL
: ADDING-ROW ( -- )
   0 DB-COL-BYTES {: a u :}
   u 0 max {: size :}
   size 1+ ADD-LIVE-RESERVE
   a 0 ADD-LIVE size BYTE-COPY
   u ADD-LIVE-U ! 1 FOUND-N ! ;

public

\ the slot the identity's login saves to, read without touching the row
\ table; E-SW-CAPACITY when every candidate holds another org
: DB-LIVE-NAME ( n n -- ptr u8 n ) {: p id :}
   id EMAIL$ CHECK-NAME
   0 TAKEN ! 0 SAME !
   s" SELECT name, org FROM account WHERE provider = ?" s" live name"
   [: p PROVIDER$ DB-TEXT+ ;] [: id NAME-ROW ;] DB-QUERY
   0 HIT-K ! 0 FREE-K !
   SLOT-TRIES 1+ 1 ?do i id CANDIDATE-CHECK loop
   HIT-K @ 0= if FREE-K @ HIT-K ! then
   HIT-K @ 0= if E-SW-CAPACITY throw then
   HIT-K @ id EMAIL$ CANDIDATE ;

\ the name installed last; false before the first install
: DB-INSTALLED ( n -- ptr u8 n bool )
   s" SELECT installed FROM live WHERE provider = ?" s" installed" NAME-QUERY ;

\ the name whose install began and has not finished
: DB-PENDING ( n -- ptr u8 n bool )
   s" SELECT name FROM pending WHERE provider = ?" s" pending" NAME-QUERY ;

\ epoch seconds of the last install; false before one noted a time
: DB-INSTALLED-AT ( n -- n bool ) {: p :}
   0 FOUND-N ! 0 FOUND-AT !
   SQL-RESET s" SELECT installed_at FROM live" SQL+
   s"  WHERE provider = ? AND installed_at IS NOT NULL" SQL+
   SQL$ s" installed at" [: p PROVIDER$ DB-TEXT+ ;]
   [: 0 DB-COL-INT FOUND-AT ! 1 FOUND-N ! ;] DB-QUERY
   FOUND-AT @ FOUND-N @ 0<> ;

\ the live item an add's login may overwrite, as it was before the login ran
\ (length -1 when there was none), read without touching the row table and
\ lasting until the next DB-ADDING; false when no add is in flight
: DB-ADDING ( n -- ptr u8 n bool )
   {: p :}
   0 FOUND-N ! 0 ADD-LIVE-U ! 1 ADD-LIVE-RESERVE
   s" SELECT live FROM adding WHERE provider = ?" s" adding"
   [: p PROVIDER$ DB-TEXT+ ;] [: ADDING-ROW ;] DB-QUERY
   0 ADD-LIVE ADD-LIVE-U @ FOUND-N @ 0<> ;

\ ---- writes, inside DB-WRITE ---------------------------------------------------
private

: IDENTITY+ ( n -- ) {: id :}
   id EMAIL$ DB-TEXT+ id ORG$ DB-TEXT+ id PLAN$ DB-TEXT+ ;

: PUT-SQL ( -- )
   SQL-RESET s" INSERT INTO account" SQL+
   s"  (provider, name, email, org, plan, login, profile, usage)" SQL+
   s"  VALUES (?, ?, ?, ?, ?, ?, ?, ?)" SQL+
   s"  ON CONFLICT (provider, name) DO UPDATE SET" SQL+
   s"  email = excluded.email, org = excluded.org, plan = excluded.plan," SQL+
   s"  login = excluded.login, profile = excluded.profile," SQL+
   s"  usage = coalesce(excluded.usage, account.usage)" SQL+ ;

: USAGE+ ( bool -- )
   if DB-USAGE-ENCODE DB-TEXT+ exit then
   DB-NULL+ ;

: NO-ACCOUNT ( -- ) DB-CHANGES 0= if E-SW-NO-ACCOUNT throw then ;

create CLAIM-RAW 16 allot
create CLAIM-BUF 32 allot

\ 128 random bits as lowercase hex
: NEW-CLAIM ( -- ptr u8 n )
   CLAIM-RAW 16 ENTROPY:FILL
   16 0 ?do
      CLAIM-RAW i + c@ {: b :}
      b 4 rshift HEX-C CLAIM-BUF i 2 * + c!
      b 15 and HEX-C CLAIM-BUF i 2 * 1+ + c!
   loop
   CLAIM-BUF 32 ;

public

\ inserts or replaces the row: identity id's email, org and plan, the login
\ and profile (length -1 for none), and the usage record when with is true;
\ an existing row keeps its usage otherwise
: DB-PUT ( n ptr u8 n n ptr u8 n ptr u8 n bool -- )
   {: p a u id la lu pa pu with :}
   PUT-SQL SQL$ s" put" [:
      p PROVIDER$ DB-TEXT+ a u DB-TEXT+ id IDENTITY+
      la lu DB-BLOB+ pa pu DB-BLOB+ with USAGE+
   ;] TX-RUN ;

\ E-SW-NO-ACCOUNT when there is no such row
: DB-SET-LOGIN ( n ptr u8 n ptr u8 n -- ) {: p a u d du :}
   s" UPDATE account SET login = ? WHERE provider = ? AND name = ?" s" set login"
   [: d du DB-BLOB+ p PROVIDER$ DB-TEXT+ a u DB-TEXT+ ;] TX-RUN
   NO-ACCOUNT ;

\ stores the usage record, and the plan unless its length is -1;
\ E-SW-NO-ACCOUNT when there is no such row
: DB-SET-USAGE ( n ptr u8 n ptr u8 n -- ) {: p a u pl plu :}
   SQL-RESET s" UPDATE account SET usage = ?, plan = coalesce(?, plan)" SQL+
   s"  WHERE provider = ? AND name = ?" SQL+
   SQL$ s" set usage" [:
      true USAGE+ pl plu DB-TEXT+ p PROVIDER$ DB-TEXT+ a u DB-TEXT+
   ;] TX-RUN
   NO-ACCOUNT ;

: DB-REMOVE ( n ptr u8 n -- ) {: p a u :}
   s" DELETE FROM account WHERE provider = ? AND name = ?" s" remove"
   [: p PROVIDER$ DB-TEXT+ a u DB-TEXT+ ;] TX-RUN ;

\ notes the installed name, installed at epoch seconds; false keeps the time
\ already noted
: DB-NOTE-INSTALLED ( n ptr u8 n n bool -- ) {: p a u at has :}
   SQL-RESET s" INSERT INTO live (provider, installed, installed_at)" SQL+
   s"  VALUES (?, ?, ?) ON CONFLICT (provider) DO UPDATE SET" SQL+
   s"  installed = excluded.installed," SQL+
   s"  installed_at = coalesce(excluded.installed_at, live.installed_at)" SQL+
   SQL$ s" note installed" [:
      p PROVIDER$ DB-TEXT+ a u DB-TEXT+
      has if at DB-INT+ else DB-NULL+ then
   ;] TX-RUN ;

\ records an install of the name as begun under a new claim, replacing any
\ earlier marker; the claim lasts until the next one
: DB-NOTE-PENDING ( n ptr u8 n -- ptr u8 n ) {: p a u :}
   NEW-CLAIM {: c cu :}
   SQL-RESET s" INSERT INTO pending (provider, name, owner) VALUES (?, ?, ?)" SQL+
   s"  ON CONFLICT (provider) DO UPDATE SET" SQL+
   s"  name = excluded.name, owner = excluded.owner" SQL+
   SQL$ s" note pending" [:
      p PROVIDER$ DB-TEXT+ a u DB-TEXT+ c cu DB-TEXT+
   ;] TX-RUN
   c cu ;

\ whether the pending marker is still the one the claim noted
: DB-OWNS? ( n ptr u8 n -- bool ) {: p c cu :}
   s" owns pending" TX-CHECK
   0 FOUND-N !
   s" SELECT 1 FROM pending WHERE provider = ? AND owner = ?" s" owns pending"
   [: p PROVIDER$ DB-TEXT+ c cu DB-TEXT+ ;] [: 1 FOUND-N ! ;] DB-QUERY
   FOUND-N @ 0<> ;

\ clears the claim's marker; nothing to do once another install replaced it
: DB-CLEAR-PENDING ( n ptr u8 n -- ) {: p c cu :}
   s" DELETE FROM pending WHERE provider = ? AND owner = ?" s" clear pending"
   [: p PROVIDER$ DB-TEXT+ c cu DB-TEXT+ ;] TX-RUN ;

\ records an add's login as begun with the live item it must leave as it
\ found (length -1 for none); Linux files no item under a service
: DB-NOTE-ADDING ( n ptr u8 n -- ) {: p a u :}
   SQL-RESET s" INSERT INTO adding (provider, live, service) VALUES (?, ?, ?)" SQL+
   s"  ON CONFLICT (provider) DO UPDATE SET" SQL+
   s"  live = excluded.live, service = excluded.service" SQL+
   SQL$ s" note adding" [:
      p PROVIDER$ DB-TEXT+ a u DB-BLOB+ s" " DB-TEXT+
   ;] TX-RUN ;

: DB-CLEAR-ADDING ( n -- ) {: p :}
   s" DELETE FROM adding WHERE provider = ?" s" clear adding"
   [: p PROVIDER$ DB-TEXT+ ;] TX-RUN ;

\ ---- history: append-only events; identity and usage, never login bytes ----------
private

PROCESS-SYMBOLS
FUNCTION: NOW-CALL clock_gettime ( n ptr u8 -- i32 )
   1 16 WRITES-BYTES
;FUNCTION

0 constant CLOCK-REALTIME
create NOW-SPEC 16 allot                  \ struct timespec: tv_sec, tv_nsec

: HISTORY-SQL ( -- )
   SQL-RESET s" INSERT INTO history" SQL+
   s"  (provider, kind, at_us, name, email, org, plan, details)" SQL+
   s"  VALUES (?, ?, ?, ?, ?, ?, ?, ?)" SQL+ ;

public

\ microseconds since the Unix epoch
: DB-NOW-US ( -- n )
   CLOCK-REALTIME NOW-SPEC NOW-CALL 0<> if E-TIME-CLOCK throw then
   NOW-SPEC @ 1000000 * NOW-SPEC 8 + @ 1000 / + ;

\ a probe's outcome for the saved login: identity id carries the plan
\ committed with it, live whether the probe read the login as live, at the
\ instant in epoch microseconds; the details are the usage record
: DB-APPEND-USAGE ( n ptr u8 n n bool n -- ) {: p a u id live at :}
   live ENC-DETAILS
   HISTORY-SQL SQL$ s" append usage" [:
      p PROVIDER$ DB-TEXT+ s" usage" DB-TEXT+ at DB-INT+
      a u DB-TEXT+ id IDENTITY+ ENC$ DB-TEXT+
   ;] TX-RUN ;

\ the completed install of the saved login, whose row holds identity id
: DB-APPEND-SWITCH ( n ptr u8 n n n -- ) {: p a u id at :}
   HISTORY-SQL SQL$ s" append switch" [:
      p PROVIDER$ DB-TEXT+ s" switch" DB-TEXT+ at DB-INT+
      a u DB-TEXT+ id IDENTITY+ s" {}" DB-TEXT+
   ;] TX-RUN ;

;package
