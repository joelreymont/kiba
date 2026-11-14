\ sw-sqlite.f - libsqlite3 bindings: one connection per process and one
\ statement at a time, finalized before the word that prepared it returns.
\ A failed call throws E-SW-DB; DB-ERROR$ then holds its operation and
\ sqlite3_errmsg.
require ../src/sw-io.f
require ../src/sw-base.f
require src/lib/ffi-abi.f
require src/lib/fsm.f
require src/lib/fs.f
require src/lib/fs-mutate.f
require src/lib/prelude.f
require src/lib/string.f

package SW

VERSIONED-LIBRARY sqlite3 0
\ Handles are addresses kept as numbers; 0 is no handle.
FUNCTION: SQL-OPEN-CALL sqlite3_open_v2 ( ptr u8 ptr u8 n n -- i32 )
   1 8 WRITES-BYTES
;FUNCTION
FUNCTION: SQL-CLOSE-CALL sqlite3_close_v2 ( n -- i32 ) ;FUNCTION
FUNCTION: SQL-ERRMSG-CALL sqlite3_errmsg ( n -- ptr u8 ) ;FUNCTION
FUNCTION: SQL-ERRSTR-CALL sqlite3_errstr ( n -- ptr u8 ) ;FUNCTION
FUNCTION: SQL-BUSY-CALL sqlite3_busy_timeout ( n n -- i32 ) ;FUNCTION
FUNCTION: SQL-EXEC-CALL sqlite3_exec ( n ptr u8 n n n -- i32 ) ;FUNCTION
FUNCTION: SQL-PREPARE-CALL sqlite3_prepare_v2 ( n ptr u8 n ptr u8 n -- i32 )
   3 8 WRITES-BYTES
;FUNCTION
FUNCTION: SQL-FINALIZE-CALL sqlite3_finalize ( n -- i32 ) ;FUNCTION
FUNCTION: SQL-STEP-CALL sqlite3_step ( n -- i32 ) ;FUNCTION
FUNCTION: SQL-TEXT-CALL sqlite3_bind_text ( n n ptr u8 n n -- i32 ) ;FUNCTION
FUNCTION: SQL-BLOB-CALL sqlite3_bind_blob ( n n ptr u8 n n -- i32 ) ;FUNCTION
FUNCTION: SQL-ZEROBLOB-CALL sqlite3_bind_zeroblob ( n n n -- i32 ) ;FUNCTION
FUNCTION: SQL-INT-CALL sqlite3_bind_int64 ( n n n -- i32 ) ;FUNCTION
FUNCTION: SQL-NULL-CALL sqlite3_bind_null ( n n -- i32 ) ;FUNCTION
FUNCTION: SQL-TYPE-CALL sqlite3_column_type ( n n -- i32 ) ;FUNCTION
FUNCTION: SQL-COLBLOB-CALL sqlite3_column_blob ( n n -- ptr u8 ) ;FUNCTION
FUNCTION: SQL-BYTES-CALL sqlite3_column_bytes ( n n -- i32 ) ;FUNCTION
FUNCTION: SQL-COLINT-CALL sqlite3_column_int64 ( n n -- n ) ;FUNCTION
FUNCTION: SQL-CHANGES-CALL sqlite3_changes ( n -- i32 ) ;FUNCTION
FUNCTION: SQL-AUTOCOMMIT-CALL sqlite3_get_autocommit ( n -- i32 ) ;FUNCTION

\ sqlite3.h
0 constant SQL-OK
100 constant SQL-ROW
101 constant SQL-DONE
5 constant SQL-NULL-TYPE
$2 $4 or $1000000 or constant SQL-FLAGS   \ READWRITE | CREATE | NOFOLLOW
-1 constant SQL-TRANSIENT                 \ SQLite copies a bound value at once
5000 constant SQL-BUSY-MS                 \ how long a call waits for another writer

512 constant SQL-ERR-CAP
4096 constant SQL-Z-CAP

create SQL-ERR-BUF SQL-ERR-CAP allot   variable SQL-ERR-U
create SQL-Z-BUF SQL-Z-CAP allot       \ a NUL-terminated copy of exec's SQL
variable SQL-H                         \ the connection
variable SQL-STMT                      \ the open statement
variable SQL-OUT                       \ the cell an out-parameter fills
variable SQL-ARG                       \ the next parameter's index, from 1
PTR-VARIABLE SQL-OP-A   variable SQL-OP-U   \ what the open statement reports as

: SQL-ERR+ ( ptr u8 n -- ) {: a u :}
   SQL-ERR-CAP SQL-ERR-U @ - u min {: k :}
   a SQL-ERR-BUF SQL-ERR-U @ + k BYTE-COPY
   SQL-ERR-U @ k + SQL-ERR-U ! ;

: SQL-CSTR$ ( ptr u8 -- ptr u8 n ) dup ZLEN ;

public

\ the operation and SQLite's message behind the last E-SW-DB
: DB-ERROR$ ( -- ptr u8 n ) SQL-ERR-BUF SQL-ERR-U @ ;

: DB-THROW ( ptr u8 n ptr u8 n -- ) {: op ou msg mu :}
   0 SQL-ERR-U !
   op ou SQL-ERR+ s" : " SQL-ERR+ msg mu SQL-ERR+
   E-SW-DB throw ;

private

: SQL-FAIL ( ptr u8 n -- )
   SQL-H @ SQL-ERRMSG-CALL SQL-CSTR$ DB-THROW ;

: SQL-CONN ( -- n )
   SQL-H @ {: h :}
   h 0= if s" store" s" the store is not open" DB-THROW then
   h ;

: SQL-OP$ ( -- ptr u8 n ) SQL-OP-A @ SQL-OP-U @ ;

: SQL-CHECK ( n -- )
   SQL-OK <> if SQL-OP$ SQL-FAIL then ;

: SQL-Z ( ptr u8 n -- ptr u8 ) {: a u :}
   u SQL-Z-CAP >= if
      s" bytes in an SQL script" SQL-Z-CAP 1- LIMIT$ TOO-MANY
   then
   a SQL-Z-BUF u BYTE-COPY
   0 SQL-Z-BUF u + c!
   SQL-Z-BUF ;

public

: DB-EXEC ( ptr u8 n ptr u8 n -- ) {: sql su op ou :}
   SQL-CONN sql su SQL-Z 0 0 0 SQL-EXEC-CALL
   SQL-OK <> if op ou SQL-FAIL then ;

private

\ ---- the connection ---------------------------------------------------------
\ A handle that failed to open holds only its message: errstr when none.
: SQL-OPEN-FAIL ( ptr u8 n n n -- ) {: a u rc h :}
   SB-RESET s" open " SB-APPEND a u SB-APPEND SB$
   h 0= if rc SQL-ERRSTR-CALL else h SQL-ERRMSG-CALL then SQL-CSTR$
   h SQL-CLOSE-CALL drop
   DB-THROW ;

\ the fresh file goes 0600 before WAL mode makes -wal and -shm, which copy
\ the database's mode
: SQL-SETUP ( ptr u8 n bool -- ) {: a u fresh :}
   fresh if a u MODE-PRIVATE-FILE FS:CHMOD-MODE then
   SQL-H @ SQL-BUSY-MS SQL-BUSY-CALL SQL-OK <> if s" busy timeout" SQL-FAIL then
   s" PRAGMA journal_mode = WAL" s" journal mode" DB-EXEC ;

\ opens the database at the path, creating it 0600 when missing, in WAL mode
: SQL-CONNECT ( ptr u8 n -- ) {: a u :}
   a u FS:FILE? 0= {: fresh :}
   0 SQL-OUT !
   a u FS:>PATHZ SQL-OUT BYTE-VIEW SQL-FLAGS 0 SQL-OPEN-CALL {: rc :}
   rc SQL-OK <> if a u rc SQL-OUT @ SQL-OPEN-FAIL then
   SQL-OUT @ SQL-H !
   a u fresh SQL-SETUP ;

\ every statement is finalized before its word returns, so closing cannot
\ fail; an open transaction is rolled back. Closing no connection is a no-op.
: SQL-DISCONNECT ( -- )
   SQL-H @ SQL-CLOSE-CALL drop
   0 SQL-H ! ;

: SQL-IN-TX? ( -- bool ) SQL-CONN SQL-AUTOCOMMIT-CALL 0= ;

public

\ rows the last statement changed
: DB-CHANGES ( -- n ) SQL-CONN SQL-CHANGES-CALL ;

\ ---- binding: in order, a negative length binds NULL -------------------------
private

: SQL-NEXT-ARG ( -- n n )
   SQL-STMT @ SQL-ARG @ dup 1+ SQL-ARG ! ;

\ SQLite binds NULL for a null address, so an empty value gets a real one
: SQL-SOME ( ptr u8 n -- ptr u8 n ) {: a u :}
   u 0= if SQL-Z-BUF 0 exit then
   a u ;

public

: DB-NULL+ ( -- ) SQL-NEXT-ARG SQL-NULL-CALL SQL-CHECK ;

: DB-INT+ ( n -- ) {: v :} SQL-NEXT-ARG v SQL-INT-CALL SQL-CHECK ;

: DB-TEXT+ ( ptr u8 n -- ) {: a u :}
   u 0 < if DB-NULL+ exit then
   SQL-NEXT-ARG {: s i :}
   s i a u SQL-SOME SQL-TRANSIENT SQL-TEXT-CALL SQL-CHECK ;

: DB-BLOB+ ( ptr u8 n -- ) {: a u :}
   u 0 < if DB-NULL+ exit then
   SQL-NEXT-ARG {: s i :}
   u 0= if s i 0 SQL-ZEROBLOB-CALL SQL-CHECK exit then
   s i a u SQL-TRANSIENT SQL-BLOB-CALL SQL-CHECK ;

\ ---- columns of the current row: valid until the next step --------------------
: DB-COL-NULL? ( n -- bool ) {: c :}
   SQL-STMT @ c SQL-TYPE-CALL SQL-NULL-TYPE = ;

\ a value's bytes, text or blob alike; length -1 for NULL
: DB-COL-BYTES ( n -- ptr u8 n ) {: c :}
   c DB-COL-NULL? if NULL-PTR BYTE-VIEW -1 exit then
   SQL-STMT @ c SQL-COLBLOB-CALL
   SQL-STMT @ c SQL-BYTES-CALL ;

: DB-COL-INT ( n -- n ) {: c :} SQL-STMT @ c SQL-COLINT-CALL ;

\ ---- stepping ---------------------------------------------------------------
private

\ A statement steps until SQLite reports it done; each row runs the row
\ quotation, the machine's context.
ENUM step-state stepping stepped ;ENUM
ENUM step-input row done failed ;ENUM

: SQL-STEP-SENSE ( [ -- ] -- step-input )
   drop SQL-STMT @ SQL-STEP-CALL {: rc :}
   rc SQL-ROW = if construct step-input row exit then
   rc SQL-DONE = if construct step-input done exit then
   construct step-input failed ;

: SQL-ON-ROW ( [ -- ] -- ) execute ;
: SQL-ON-FAIL ( [ -- ] -- ) drop SQL-OP$ SQL-FAIL ;

FSM:DEFINE SQL-STEPS ( [ -- ] ) step-state step-input
   IN stepping SQL-STEP-SENSE
      row SQL-ON-ROW >stepping
      done - >stepped
      failed SQL-ON-FAIL >stepped
   FINAL stepped -
;DEFINE

: SQL-FINALIZE ( -- )
   SQL-STMT @ SQL-FINALIZE-CALL drop
   0 SQL-STMT ! ;

: SQL-PREPARE ( ptr u8 n -- ) {: sql su :}
   0 SQL-OUT !
   SQL-CONN sql su SQL-OUT BYTE-VIEW 0 SQL-PREPARE-CALL SQL-CHECK
   SQL-OUT @ SQL-STMT !
   1 SQL-ARG ! ;

public

\ prepares sql, runs the binder, then the row quotation once per result row;
\ op names the statement in an error
: DB-QUERY ( ptr u8 n ptr u8 n [ -- ] [ -- ] -- ) {: sql su op ou bind each :}
   SQL-STMT @ 0<> if op ou s" a statement is open" DB-THROW then
   op SQL-OP-A ! ou SQL-OP-U !
   sql su SQL-PREPARE
   [: bind execute each construct step-state stepping SQL-STEPS ;]
   [: SQL-FINALIZE ;] finally ;

\ a statement that returns no rows
: DB-RUN ( ptr u8 n ptr u8 n [ -- ] -- ) {: sql su op ou bind :}
   sql su op ou bind [: ;] DB-QUERY ;

;package
