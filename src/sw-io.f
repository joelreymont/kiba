\ sw-io.f - runtime buffers, private file writes, and the store lock.
require ../src/sw-paths.f
require src/lib/memory.f
require src/lib/fs-mutate.f
require src/lib/fs-list.f
require src/lib/string.f
require src/lib/fmt.f
require src/lib/json.f
require src/lib/span.f

package SW

$400000 constant BUF-CAP         \ 4 MiB per runtime buffer
$180 constant MODE-PRIVATE-FILE  \ 0600
$A000 constant S-IFLNK           \ the symlink file type in st_mode

\ each *-A cell holds one runtime buffer's base, *-U its byte count
TYPED-VARIABLE CFG-A ptr u8    variable CFG-U     \ the live .claude.json document
TYPED-VARIABLE OUT-A ptr u8    variable OUT-U     \ the spliced .claude.json
TYPED-VARIABLE FILE-A ptr u8   variable FILE-U    \ the live credentials or auth document
TYPED-VARIABLE OBJ-A ptr u8    variable OBJ-U     \ an oauthAccount object or a JWT payload
TYPED-VARIABLE TOK-A ptr u8    variable TOK-U     \ a raw id_token string
TYPED-VARIABLE JSON-A ptr u8                      \ the JSON writer's output
TYPED-VARIABLE SDOC-A ptr u8   variable SDOC-U    \ one saved login's document
TYPED-VARIABLE BACK-A ptr u8   variable BACK-U    \ the credentials read back after a failed install
create LINK-BUF PATH-CAP allot  variable LINK-U
create DEST-BUF PATH-CAP allot  variable DEST-U
8 constant LINK-HOPS

: ALLOC-ONE ( ptr ptr u8 -- )
   BUF-CAP MEM-ALLOC-BYTES drop swap ! ;

\ E-FS-CAPACITY is a semantic refusal: a link that does not fit would be
\ silently truncated.
: READ-LINK ( ptr u8 n SPAN:span<u8> -- n ) {: pa:ptr pu dst :}
   pa pu FS:TRY-LSTAT 0= if E-FS-STAT throw then
   FS:STAT-MODE@ FS:S-IFMT and S-IFLNK <> if E-FS-STAT throw then
   FS:STAT-SIZE@ dst SPAN:LEN > if E-FS-CAPACITY throw then
   pa pu FS:>PATHZ dst SPAN:$ readlink {: n :}
   n 0 < if E-FS-IO throw then
   n ;

\ a relative link target is taken from the link's own directory
: LINK-TARGET ( ptr u8 n -- ptr u8 n ) {: a u :}
   a u LINK-BUF PATH-CAP SPAN:MAKE READ-LINK {: tu :}
   LINK-BUF c@ FS:SLASH = if LINK-BUF tu exit then
   a u DIRNAME {: d du :}
   SB-RESET d du SB-APPEND FS:SLASH SB-APPEND-C LINK-BUF tu SB-APPEND
   SB$ ;

\ the path a write must replace: the file behind any chain of symlinks
: WRITE-TARGET ( ptr u8 n -- ptr u8 n )
   DEST-BUF DEST-U PATH!
   LINK-HOPS begin dup 0 > DEST-BUF DEST-U @ FS:SYMLINK? and while
      DEST-BUF DEST-U @ LINK-TARGET DEST-BUF DEST-U PATH!
      1-
   repeat drop
   DEST-BUF DEST-U @ FS:SYMLINK? if E-FS-PATH-UNSAFE throw then
   DEST-BUF DEST-U @ ;

\ the file is born 0600, so no byte of a secret is ever readable by others
: OPEN-PRIVATE ( ptr u8 n -- n ) {: a u :}
   a u FS:SYMLINK? if E-FS-PATH-UNSAFE throw then
   a u FS:EXISTS? if a u FS:REMOVE-FILE then
   a u FS:>PATHZ FS:O-WRONLY FS:O-CREAT or FS:O-TRUNC or MODE-PRIVATE-FILE open {: fd :}
   fd 0 < if E-FS-OPEN throw then
   fd ;

public

\ mappings are process-local: MAIN allocates them, never build-time top level
: ALLOC-BUFFERS ( -- )
   CFG-A ALLOC-ONE
   OUT-A ALLOC-ONE
   FILE-A ALLOC-ONE
   OBJ-A ALLOC-ONE
   TOK-A ALLOC-ONE
   JSON-A ALLOC-ONE
   SDOC-A ALLOC-ONE
   BACK-A ALLOC-ONE ;

: CFG-BUF ( -- ptr u8 ) CFG-A @ ;
: OUT-BUF ( -- ptr u8 ) OUT-A @ ;
: FILE-BUF ( -- ptr u8 ) FILE-A @ ;
: OBJ-BUF ( -- ptr u8 ) OBJ-A @ ;
: TOK-BUF ( -- ptr u8 ) TOK-A @ ;
: JSON-BUF ( -- ptr u8 ) JSON-A @ ;
: SDOC-BUF ( -- ptr u8 ) SDOC-A @ ;
: BACK-BUF ( -- ptr u8 ) BACK-A @ ;

: CFG$ ( -- ptr u8 n ) CFG-BUF CFG-U @ ;
: OUT$ ( -- ptr u8 n ) OUT-BUF OUT-U @ ;
: FILE$ ( -- ptr u8 n ) FILE-BUF FILE-U @ ;
: OBJ$ ( -- ptr u8 n ) OBJ-BUF OBJ-U @ ;
: SDOC$ ( -- ptr u8 n ) SDOC-BUF SDOC-U @ ;
: BACK$ ( -- ptr u8 n ) BACK-BUF BACK-U @ ;

\ every JSON document kiba emits is built in JSON-BUF through one writer:
\ JSON-OPEN starts a document and JSON:WRITTEN$ ends its chain with the bytes
TYPED-VARIABLE JSON-W JSON:writer

: JSON-OPEN ( -- ptr JSON:writer )
   JSON-W JSON-BUF BUF-CAP JSON:WRITE-OPEN ;

: READ-INTO ( ptr u8 n ptr u8 ptr n -- ptr u8 n ) {: pa pu buf up :}
   pa pu buf BUF-CAP FS:READ-ALL up !
   buf up @ ;

\ READ-INTO for a file that may be missing: length -1 when nothing is there;
\ anything else that cannot be read throws
: READ-OPT ( ptr u8 n ptr u8 ptr n -- ptr u8 n ) {: pa pu buf up :}
   pa pu FS:EXISTS? 0= if -1 up ! buf -1 exit then
   pa pu buf up READ-INTO ;

\ two documents READ-OPT read, either of which may be missing
: SAME-OPT? ( ptr u8 n ptr u8 n -- bool ) {: a u b v :}
   u 0 < v 0 < or if u v = exit then
   a u b v STR= ;

: READ-FILE$ ( ptr u8 n -- ptr u8 n )
   FILE-BUF FILE-U READ-INTO ;

\ FILE-BUF holds only live documents; a saved slot's document is read here,
\ so no slot read replaces what a live read left behind
: READ-SLOT$ ( ptr u8 n -- ptr u8 n )
   SDOC-BUF SDOC-U READ-INTO ;

\ returns once the new 0600 file and its name are on permanent storage; a
\ failed write leaves the old file and no temp. WRITE-TARGET resolves the
\ chain first, since Habu refuses a link whose target is missing.
: WRITE-PRIVATE ( ptr u8 n ptr u8 n -- ) {: pa pu src su :}
   pa pu WRITE-TARGET src su FS:ATOMIC-WRITE-PRIVATE ;

\ directories the store creates are private at every level; an existing
\ directory, whoever made it, is left as it is
: ENSURE-PRIVATE ( ptr u8 n -- ) {: a u :}
   a u FS:DIR? if exit then
   a u DIRNAME dup 0 > if RECURSE else 2drop then
   a u FS:>PATHZ FS:MODE-PRIVATE-DIR mkdir 0 < if
      a u FS:DIR? 0= if E-FS-IO throw then
   then ;

\ ---- the store lock -----------------------------------------------------------
\ mkdir is the mutex; the holder's pid inside it lets a later run tell a
\ crashed holder from a live one, since nothing releases the lock on death.
create LOCKPID-BUF PATH-CAP allot   variable LOCKPID-U
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
   LOCKPID$ FS:FILE? 0= if -1 exit then
   LOCKPID$ READ-FILE$ STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

: LOCK-AGE ( -- n )
   LOCK$ FS:TRY-STAT 0= if 0 exit then
   epoch-seconds FS:STAT-MTIME-SEC@ - ;

: LOCK-STALE? ( -- bool )
   LOCK-HOLDER {: pid :}
   pid 0 > if pid PID-ALIVE? 0= exit then
   LOCK-AGE LOCK-GRACE-SEC > ;

: TRY-LOCK ( -- bool )
   LOCK$ FS:>PATHZ FS:MODE-PRIVATE-DIR mkdir 0 >= if true exit then
   LOCK$ FS:DIR? 0= if E-FS-IO throw then
   false ;

\ a holder that died mid-write leaves WRITE-PRIVATE's sibling of its pid
\ file, named `.tmp-<seed>-<attempt>` by Habu, in the lock directory
: SWEEP-TEMP ( ptr u8 n -- ) {: a u :}
   a u s" .tmp-" STARTS-WITH? 0= if exit then
   LOCK$ {: l lu :}
   SB-RESET l lu SB-APPEND FS:SLASH SB-APPEND-C a u SB-APPEND
   SB$ FS:ATOMIC-CLEAN-TEMP ;

: BREAK-LOCK ( -- )
   LOCKPID$ FS:FILE? if LOCKPID$ FS:REMOVE-FILE then
   LOCK$ [: SWEEP-TEMP ;] FS-LIST:EACH
   LOCK$ FS:REMOVE-DIR ;

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

;package
