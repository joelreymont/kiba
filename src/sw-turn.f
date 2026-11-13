\ sw-turn.f - one provider's turn, shared by every kiba process: an exclusive
\ flock on <store>/turn-<provider>, polled so a wait is bounded. Each holder
\ opens the turn file afresh, and a flock lock belongs to the open file
\ description, so two holders in one process exclude each other as two
\ processes do; the kernel releases the lock of a holder that dies.
\ Waiters take the turn in the order they began waiting: each first creates
\ and locks an entry in <store>/turn-<provider>.queue, named by its monotonic
\ nanosecond, pid and a per-process count, and tries the turn file only while
\ no entry sorting before its own is locked. An unlocked entry's owner is
\ gone, so the waiter that finds it removes it. Linux has no O_EXLOCK, so an
\ entry's name appears before its lock and a waiter behind can lock and
\ unlink it first; its creator then finds the lock busy or no link left, and
\ joins again.
require ../src/sw-io.f
require src/lib/fs.f
require src/lib/fs-list.f
require src/lib/fs-lock.f
require src/lib/ffi-abi.f
require src/lib/fsm.f
require src/lib/task.f
require src/lib/time.f
require src/lib/fmt.f
require src/lib/string.f

package SW

public

variable TURN-WAIT-MS            \ how long TURN-ENTER waits before E-SW-TURN-BUSY
120000 TURN-WAIT-MS !

private

100 constant TURN-POLL-MS
2 constant TURN-ENOENT           \ both targets' errno.h
20 constant STAMP-DIGITS
10 constant PID-DIGITS
20 constant COUNT-DIGITS
STAMP-DIGITS PID-DIGITS + COUNT-DIGITS + 2 + constant ENTRY-LEN
$10000 constant LIST-CAP         \ the queue's names, one line each

\ Linux's open flags, include/uapi/asm-generic/fcntl.h; arm64's
\ arch/arm64 asm/fcntl.h moves O_NOFOLLOW to $8000.
$40 constant LINUX-O-CREAT
$80 constant LINUX-O-EXCL
$80000 constant LINUX-O-CLOEXEC

: O-NOFOLLOW ( -- n )
   HB-TARGET-LINUX-X86-64? if $20000 exit then
   HB-TARGET-LINUX? if $8000 exit then
   E-FS-OPEN throw ;

\ The turn file holds no data: O_RDONLY, created 0600, never through a link,
\ never inherited by a child.
: TURN-FLAGS ( -- n )
   O-NOFOLLOW LINUX-O-CLOEXEC or LINUX-O-CREAT or ;

\ A queue entry's name is new: its open creates it.
: ENTRY-FLAGS ( -- n )
   TURN-FLAGS LINUX-O-EXCL or ;

\ An entry ahead is opened only to try its lock.
: PEEK-FLAGS ( -- n )
   O-NOFOLLOW LINUX-O-CLOEXEC or ;

\ Habu's portable `open` carries neither O_EXCL, O_NOFOLLOW nor O_CLOEXEC.
PROCESS-SYMBOLS
FUNCTION: TURN-OPEN-CALL open ( ptr u8 n n -- i32 ) 2 VARIADIC ;FUNCTION
FUNCTION: TURN-UNLINK-CALL unlink ( ptr u8 -- i32 ) ;FUNCTION

LIST-CAP SCRATCH-BUFFER: LIST-BUF
create TURN-BUF PATH-CAP allot    variable TURN-U
create QUEUE-BUF PATH-CAP allot   variable QUEUE-U
create QPATH-BUF PATH-CAP allot   variable QPATH-U

\ The ticket, per provider: the turn file and the waiter's locked queue
\ entry, each -1 while not open, and the entry's name.
P-COUNT TYPED-BUFFER TURN-FD n
P-COUNT TYPED-BUFFER ENTRY-FD n
create ENTRY-NAMES P-COUNT ENTRY-LEN * allot

variable ENTRY-COUNT             \ entries this process has created
variable TURN-DEADLINE           \ MONO-NS when the wait gives up
variable TURN-RC                 \ what a wait that left throws

: TICKETS-SHUT ( -- )
   P-COUNT 0 ?do -1 i TURN-FD ! -1 i ENTRY-FD ! loop ;
TICKETS-SHUT

\ ---- paths ------------------------------------------------------------------
: TURN$ ( n -- ptr u8 n ) {: p :}
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /turn-" SB-APPEND p PROVIDER$ SB-APPEND
   SB$ TURN-BUF TURN-U PATH!
   TURN-BUF TURN-U @ ;

: QUEUE$ ( n -- ptr u8 n )
   TURN$ {: t tu :}
   SB-RESET t tu SB-APPEND s" .queue" SB-APPEND
   SB$ QUEUE-BUF QUEUE-U PATH!
   QUEUE-BUF QUEUE-U @ ;

\ the path of the queue entry named by the span
: QUEUED$ ( n ptr u8 n -- ptr u8 n ) {: p a u :}
   p QUEUE$ {: q qu :}
   SB-RESET q qu SB-APPEND FS:SLASH SB-APPEND-C a u SB-APPEND
   SB$ QPATH-BUF QPATH-U PATH!
   QPATH-BUF QPATH-U @ ;

: ENTRY-NAME$ ( n -- ptr u8 n )
   ENTRY-LEN * ENTRY-NAMES + ENTRY-LEN ;

: ENTRY$ ( n -- ptr u8 n )
   dup ENTRY-NAME$ QUEUED$ ;

\ the value in decimal, zero-padded to the width, so names sort as numbers do
: SB-PADDED ( n n -- ) {: v w :}
   v FMT:INT$ {: a u :}
   w u - 0 ?do STR-ZERO SB-APPEND-C loop
   a u SB-APPEND ;

: NAME-NEXT ( n -- ) {: p :}
   SB-RESET
   TIME:MONO-NS STAMP-DIGITS SB-PADDED STR-MINUS SB-APPEND-C
   getpid PID-DIGITS SB-PADDED STR-MINUS SB-APPEND-C
   ENTRY-COUNT @ COUNT-DIGITS SB-PADDED
   1 ENTRY-COUNT +!
   SB$ drop p ENTRY-NAME$ BYTE-COPY ;

\ ---- descriptors ------------------------------------------------------------
: OPEN-AT ( ptr u8 n n -- n ) {: a u flags :}
   a u FS:>PATHZ flags MODE-PRIVATE-FILE TURN-OPEN-CALL ;

: OPEN-FILE ( ptr u8 n n -- n )
   OPEN-AT {: fd :}
   fd 0 < if E-FS-OPEN throw then
   fd ;

\ -1 when nothing is there
: OPEN-IF-THERE ( ptr u8 n n -- n )
   OPEN-AT {: fd :}
   fd 0 >= if fd exit then
   FFI:ERRNO TURN-ENOENT = if -1 exit then
   E-FS-OPEN throw ;

: LINKED? ( n -- bool )
   >FD FS:FD-LINKS 0 > ;

: SHUT ( ptr n -- ) {: cell:ptr :}
   cell @ 0 >= if cell @ close then
   -1 cell ! ;

\ ---- the queue --------------------------------------------------------------
\ An entry ahead that nobody holds: its owner is gone. A peer that removed
\ it first is fine.
: REMOVE-STALE ( ptr u8 n -- )
   FS:>PATHZ TURN-UNLINK-CALL 0= if exit then
   FFI:ERRNO TURN-ENOENT <> if E-FS-IO throw then ;

: HELD? ( n ptr u8 n -- bool ) {: fd a u :}
   fd >FD FS-LOCK:TRY 0= if true exit then
   a u REMOVE-STALE false ;

\ true while the entry's owner holds its lock; one nobody holds is removed
: LIVE? ( n ptr u8 n -- bool ) {: p a u :}
   p a u QUEUED$ PEEK-FLAGS OPEN-IF-THERE {: fd :}
   fd 0 < if false exit then
   [: fd p a u QUEUED$ HELD? ;] [: fd close ;] finally ;

\ whether a live waiter's entry sorts before the provider's own; the listing
\ is in byte order, so the scan stops at the first name not before it
: AHEAD? ( n -- bool ) {: p :}
   p QUEUE$ LIST-BUF LIST-CAP FS-LIST:NAMES {: len :}
   0 begin dup len < while
      {: at :}
      LIST-BUF len STR-LF at SPLIT-NEXT drop {: a u next :}
      a u p ENTRY-NAME$ STR< 0= if false exit then
      p a u LIVE? if true exit then
      next
   repeat drop false ;

public

\ Ends the turn TURN-ENTER gave, or a wait that gave up: closing the turn
\ file releases its lock, then the entry goes. Neither holds data, so a
\ failed close or unlink is dropped; an entry left behind is unlocked once
\ closed, so the next waiter removes it.
: TURN-LEAVE ( n -- ) {: p :}
   p PROVIDER$ 2drop
   p TURN-FD SHUT
   p ENTRY-FD @ 0 >= if p ENTRY$ FS:>PATHZ TURN-UNLINK-CALL drop then
   p ENTRY-FD SHUT ;

private

\ ---- the wait ---------------------------------------------------------------
ENUM turn-state joining waiting holding left ;ENUM
ENUM join-input created taken error ;ENUM
ENUM wait-input poll locked expired error ;ENUM

: KEPT? ( n -- bool ) {: p :}
   p ENTRY-FD @ >FD FS-LOCK:TRY 0= if false exit then
   p ENTRY-FD @ LINKED? ;

: JOIN-TRY ( n join-input -- n join-input )
   drop {: p :}
   p QUEUE$ ENSURE-PRIVATE
   p NAME-NEXT
   p ENTRY$ ENTRY-FLAGS OPEN-FILE p ENTRY-FD !
   p KEPT? 0= if p construct join-input taken exit then
   p TURN$ TURN-FLAGS OPEN-FILE p TURN-FD !
   p construct join-input created ;

: JOIN ( n -- join-input )
   construct join-input error [: JOIN-TRY ;] catch
   dup 0= if drop nip exit then
   TURN-RC ! 2drop construct join-input error ;

: TAKEN? ( n -- bool ) {: p :}
   p AHEAD? if false exit then
   p TURN-FD @ >FD FS-LOCK:TRY ;

: TAKE-TRY ( n wait-input -- n wait-input )
   drop {: p :}
   p p TAKEN? if construct wait-input locked exit then
   TIME:MONO-NS TURN-DEADLINE @ >= if construct wait-input expired exit then
   construct wait-input poll ;

: TAKE ( n -- wait-input )
   construct wait-input error [: TAKE-TRY ;] catch
   dup 0= if drop nip exit then
   TURN-RC ! 2drop construct wait-input error ;

: START-CLOCK ( n -- )
   drop TIME:MONO-NS TURN-WAIT-MS @ 1000000 * + TURN-DEADLINE ! ;

: SHUT-ENTRY ( n -- ) ENTRY-FD SHUT ;

: NAP ( n -- ) drop TURN-POLL-MS >MS TASK:SLEEP ;

: BUSY ( n -- ) drop E-SW-TURN-BUSY TURN-RC ! ;

: GIVE-UP ( n -- ) TURN-LEAVE TURN-RC @ throw ;

FSM:DEFINE WAIT-TURN ( n ) turn-state join-input
   IN joining  JOIN
      created  START-CLOCK  >waiting
      taken    SHUT-ENTRY   >joining
      error    -            >left
   IN waiting  TAKE ( wait-input )
      poll     NAP          >waiting
      locked   -            >holding
      expired  BUSY         >left
      error    -            >left
   FINAL holding  -
   FINAL left     GIVE-UP
;DEFINE

public

\ Waits until the caller holds provider n's turn, at most TURN-WAIT-MS;
\ TURN-LEAVE ends it. A wait that fails leaves the queue, then throws.
: TURN-ENTER ( n -- )
   dup PROVIDER$ 2drop
   construct turn-state joining WAIT-TURN ;

;package
