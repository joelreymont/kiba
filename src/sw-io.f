\ sw-io.f - runtime buffers, private file writes, and the store lock.
require ../src/sw-paths.f
require lib/memory.f
require lib/fs-mutate.f
require lib/time.f
require lib/fmt.f
require lib/json-write.f

package SW

$400000 constant BUF-CAP         \ 4 MiB per runtime buffer
$180 constant MODE-PRIVATE-FILE  \ 0600
$1C0 constant MODE-PRIVATE-DIR   \ 0700

variable CFG-A   variable CFG-U     \ the live .claude.json document
variable OUT-A   variable OUT-U     \ the spliced .claude.json
variable FILE-A  variable FILE-U    \ one credentials or auth document
variable OBJ-A   variable OBJ-U     \ an oauthAccount object or a JWT payload
variable TOK-A   variable TOK-U     \ a raw id_token string
variable JSON-A                     \ the JSON writer's output
create TMP-BUF FS-PATH-CAP allot   variable TMP-U
create MARK-BUF FS-PATH-CAP allot  variable MARK-U
create LINK-BUF FS-PATH-CAP allot  variable LINK-U
create DEST-BUF FS-PATH-CAP allot  variable DEST-U
8 constant LINK-HOPS

: CFG-A-FIELD ( -- ptr ptr u8 ) CFG-A 0 ptr-field ;
: OUT-A-FIELD ( -- ptr ptr u8 ) OUT-A 0 ptr-field ;
: FILE-A-FIELD ( -- ptr ptr u8 ) FILE-A 0 ptr-field ;
: OBJ-A-FIELD ( -- ptr ptr u8 ) OBJ-A 0 ptr-field ;
: TOK-A-FIELD ( -- ptr ptr u8 ) TOK-A 0 ptr-field ;
: JSON-A-FIELD ( -- ptr ptr u8 ) JSON-A 0 ptr-field ;

: ALLOC-ONE ( ptr ptr u8 -- )
   BUF-CAP MEM-ALLOC-BYTES drop swap ! ;

: TMP$ ( -- ptr u8 n ) TMP-BUF TMP-U @ ;

: TMP-FOR ( ptr u8 n -- )
   SB-RESET SB-APPEND s" .tmp" SB-APPEND
   SB$ TMP-BUF TMP-U PATH! ;

\ a relative link target is taken from the link's own directory
: LINK-TARGET ( ptr u8 n -- ptr u8 n ) {: a u :}
   a u LINK-BUF FS-PATH-CAP READ-LINK {: tu :}
   LINK-BUF c@ SLASH = if LINK-BUF tu exit then
   a u DIRNAME {: d du :}
   SB-RESET d du SB-APPEND SLASH SB-APPEND-C LINK-BUF tu SB-APPEND
   SB$ ;

\ the path a write must replace: the file behind any chain of symlinks
: WRITE-TARGET ( ptr u8 n -- ptr u8 n )
   DEST-BUF DEST-U PATH!
   LINK-HOPS begin dup 0 > DEST-BUF DEST-U @ SYMLINK? and while
      DEST-BUF DEST-U @ LINK-TARGET DEST-BUF DEST-U PATH!
      1-
   repeat drop
   DEST-BUF DEST-U @ SYMLINK? if E-FS-PATH-UNSAFE throw then
   DEST-BUF DEST-U @ ;

\ the file is born 0600, so no byte of a secret is ever readable by others
: OPEN-PRIVATE ( ptr u8 n -- n ) {: a u :}
   a u SYMLINK? if E-FS-PATH-UNSAFE throw then
   a u EXISTS? if a u REMOVE-FILE then
   a u FS-PATHZ FS-O-WRONLY FS-O-CREAT or FS-O-TRUNC or MODE-PRIVATE-FILE open {: fd :}
   fd 0 < if E-FS-OPEN throw then
   fd ;

: WRITE-FD-ALL ( n ptr u8 n -- ) {: fd src u :}
   0 begin dup u < while
      {: done :}
      fd src done + u done - write {: n :}
      n 0 <= if fd close E-FS-IO throw then
      done n +
   repeat drop
   fd close ;

public

\ mappings are process-local: MAIN allocates them, never build-time top level
: ALLOC-BUFFERS ( -- )
   CFG-A-FIELD ALLOC-ONE
   OUT-A-FIELD ALLOC-ONE
   FILE-A-FIELD ALLOC-ONE
   OBJ-A-FIELD ALLOC-ONE
   TOK-A-FIELD ALLOC-ONE
   JSON-A-FIELD ALLOC-ONE ;

: CFG-BUF ( -- ptr u8 ) CFG-A-FIELD @ ;
: OUT-BUF ( -- ptr u8 ) OUT-A-FIELD @ ;
: FILE-BUF ( -- ptr u8 ) FILE-A-FIELD @ ;
: OBJ-BUF ( -- ptr u8 ) OBJ-A-FIELD @ ;
: TOK-BUF ( -- ptr u8 ) TOK-A-FIELD @ ;
: JSON-BUF ( -- ptr u8 ) JSON-A-FIELD @ ;

: CFG$ ( -- ptr u8 n ) CFG-BUF CFG-U @ ;
: OUT$ ( -- ptr u8 n ) OUT-BUF OUT-U @ ;
: FILE$ ( -- ptr u8 n ) FILE-BUF FILE-U @ ;
: OBJ$ ( -- ptr u8 n ) OBJ-BUF OBJ-U @ ;

\ every JSON document kiba emits is built in JSON-BUF through one writer:
\ JSON-OPEN starts a document and JSON-WRITE:$ ends its chain with the bytes
TYPED-VARIABLE JSON-W JSON-WRITE:writer

: JSON-OPEN ( -- ptr JSON-WRITE:writer )
   JSON-W JSON-BUF BUF-CAP JSON-WRITE:OPEN ;

: READ-INTO ( ptr u8 n ptr u8 ptr n -- ptr u8 n ) {: pa pu buf up :}
   pa pu buf BUF-CAP READ-ALL up !
   buf up @ ;

: READ-FILE$ ( ptr u8 n -- ptr u8 n )
   FILE-BUF FILE-U READ-INTO ;

: WRITE-TMP ( ptr u8 n -- )
   TMP$ OPEN-PRIVATE -rot WRITE-FD-ALL ;

: WRITE-TMP-KEEP ( ptr u8 n -- ptr u8 n ) {: src su :}
   src su WRITE-TMP src su ;

: RENAME-TMP-KEEP ( ptr u8 n -- ptr u8 n ) {: da du :}
   TMP$ da du RENAME-FILE da du ;

: DROP-TMP ( -- )
   TMP$ FILE? if TMP$ REMOVE-FILE then ;

\ a failed write or rename must not leave a secret behind as <file>.tmp
: WRITE-PRIVATE ( ptr u8 n ptr u8 n -- ) {: pa pu src su :}
   pa pu WRITE-TARGET {: da du :}
   da du TMP-FOR
   src su [: WRITE-TMP-KEEP ;] catch {: rc :} 2drop
   rc 0<> if DROP-TMP rc throw then
   da du [: RENAME-TMP-KEEP ;] catch {: rc2 :} 2drop
   rc2 0<> if DROP-TMP rc2 throw then ;

\ the temp twin of any file, for sweeping a crashed write
: ASIDE-TMP ( ptr u8 n -- ptr u8 n )
   TMP-FOR TMP$ ;

\ directories the store creates are private at every level; an existing
\ directory, whoever made it, is left as it is
: ENSURE-PRIVATE ( ptr u8 n -- ) {: a u :}
   a u DIR? if exit then
   a u DIRNAME dup 0 > if RECURSE else 2drop then
   a u FS-PATHZ MODE-PRIVATE-DIR mkdir 0 < if
      a u DIR? 0= if E-FS-IO throw then
   then ;

\ ---- the store lock -----------------------------------------------------------
\ mkdir is the mutex; the holder's pid inside it lets a later run tell a
\ crashed holder from a live one, since nothing releases the lock on death.
create LOCKPID-BUF FS-PATH-CAP allot   variable LOCKPID-U
create PIDTXT-BUF 32 allot             variable PIDTXT-U
60 constant LOCK-GRACE-SEC              \ a pid-less lock older than this is dead

: LOCKPID$ ( -- ptr u8 n )
   LOCK$ {: l lu :}
   SB-RESET l lu SB-APPEND s" /pid" SB-APPEND
   SB$ LOCKPID-BUF LOCKPID-U PATH!
   LOCKPID-BUF LOCKPID-U @ ;

: PID-ALIVE? ( n -- bool )
   0 kill-errno 0= ;

: LOCK-HOLDER ( -- n )
   LOCKPID$ FILE? 0= if -1 exit then
   LOCKPID$ READ-FILE$ STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

: LOCK-AGE ( -- n )
   LOCK$ FS-TRY-STAT 0= if 0 exit then
   TIME:EPOCH-SECONDS FS-STAT-MTIME-SEC@ - ;

: LOCK-STALE? ( -- bool )
   LOCK-HOLDER {: pid :}
   pid 0 > if pid PID-ALIVE? 0= exit then
   LOCK-AGE LOCK-GRACE-SEC > ;

: TRY-LOCK ( -- bool )
   LOCK$ FS-PATHZ MODE-PRIVATE-DIR mkdir 0 >= if true exit then
   LOCK$ DIR? 0= if E-FS-IO throw then
   false ;

: BREAK-LOCK ( -- )
   LOCKPID$ FILE? if LOCKPID$ REMOVE-FILE then
   LOCKPID$ ASIDE-TMP FILE? if LOCKPID$ ASIDE-TMP REMOVE-FILE then
   LOCK$ REMOVE-DIR ;

: PIDTXT$ ( -- ptr u8 n )
   SB-RESET getpid FMT:SB-U SB$ PIDTXT-BUF PIDTXT-U 32 SPAN!
   PIDTXT-BUF PIDTXT-U @ ;

: WRITE-PID-KEEP ( ptr u8 n -- ptr u8 n ) {: l lu :}
   l lu PIDTXT$ WRITE-PRIVATE l lu ;

variable LOCK-DEPTH                     \ nested WITH-LOCK in one process

: LOCK-STORE ( -- )
   LOCK-DEPTH @ 0 > if 1 LOCK-DEPTH +! exit then
   STORE$ ENSURE-PRIVATE
   TRY-LOCK 0= if
      LOCK-STALE? 0= if E-SW-LOCKED throw then
      BREAK-LOCK
      TRY-LOCK 0= if E-SW-LOCKED throw then
   then
   LOCKPID$ [: WRITE-PID-KEEP ;] catch {: rc :} 2drop
   rc 0<> if BREAK-LOCK rc throw then
   1 LOCK-DEPTH ! ;

: UNLOCK-STORE ( -- )
   LOCK-DEPTH @ 1 > if -1 LOCK-DEPTH +! exit then
   0 LOCK-DEPTH !
   BREAK-LOCK ;

: RUN-LOCKED ( [ -- ] -- ) {: body :}
   body execute ;

: WITH-LOCK ( [ -- ] -- )
   LOCK-STORE
   [: RUN-LOCKED ;] [: UNLOCK-STORE ;] finally ;

\ ---- what kiba installed last ------------------------------------------------
\ <provider dir>/.installed names the slot whose files are live
create INST-BUF FS-PATH-CAP allot   variable INST-U
create INSTNAME NAME-CAP allot      variable INSTNAME-U

: INSTALLED-FILE$ ( n -- ptr u8 n )
   PROVIDER-DIR$ {: d du :}
   SB-RESET d du SB-APPEND s" /.installed" SB-APPEND
   SB$ INST-BUF INST-U PATH!
   INST-BUF INST-U @ ;

: NOTE-INSTALLED ( n ptr u8 n -- ) {: p a u :}
   p PROVIDER-DIR$ ENSURE-PRIVATE
   p INSTALLED-FILE$ a u WRITE-PRIVATE ;

: INSTALLED$ ( n -- ptr u8 n ) {: p :}
   0 INSTNAME-U !
   p INSTALLED-FILE$ FILE? 0= if INSTNAME 0 exit then
   p INSTALLED-FILE$ READ-FILE$ INSTNAME INSTNAME-U NAME-CAP 1- SPAN!
   INSTNAME INSTNAME-U @ ;

\ ---- install marker ---------------------------------------------------------
\ A two-file install that stops between its writes leaves a live email and live
\ tokens from different accounts. The marker names the account being installed
\ so a later save-back does not copy one account's tokens into another's slot.
: MARK-FILE$ ( n -- ptr u8 n )
   PROVIDER-DIR$ {: d du :}
   SB-RESET d du SB-APPEND s" /.installing" SB-APPEND
   SB$ MARK-BUF MARK-U PATH!
   MARK-BUF MARK-U @ ;

: INSTALLING? ( n -- bool )
   MARK-FILE$ FILE? ;

: MARK-INSTALL ( n ptr u8 n -- ) {: p a u :}
   p PROVIDER-DIR$ ENSURE-PRIVATE
   p MARK-FILE$ a u WRITE-PRIVATE ;

: CLEAR-MARK ( n -- ) {: p :}
   p INSTALLING? if p MARK-FILE$ REMOVE-FILE then ;

;package
