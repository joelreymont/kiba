\ sw-io.f - runtime buffers, private file writes, and the store lock.
require ../src/sw-paths.f
require lib/memory.f
require lib/fs-mutate.f

package SW

$400000 constant BUF-CAP         \ 4 MiB per runtime buffer
$180 constant MODE-PRIVATE-FILE  \ 0600
$1C0 constant MODE-PRIVATE-DIR   \ 0700

variable CFG-A   variable CFG-U     \ the live .claude.json document
variable OUT-A   variable OUT-U     \ the spliced .claude.json
variable FILE-A  variable FILE-U    \ one credentials or auth document
variable OBJ-A   variable OBJ-U     \ an oauthAccount object or a JWT payload
variable TOK-A   variable TOK-U     \ a raw id_token string
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
   TOK-A-FIELD ALLOC-ONE ;

: CFG-BUF ( -- ptr u8 ) CFG-A-FIELD @ ;
: OUT-BUF ( -- ptr u8 ) OUT-A-FIELD @ ;
: FILE-BUF ( -- ptr u8 ) FILE-A-FIELD @ ;
: OBJ-BUF ( -- ptr u8 ) OBJ-A-FIELD @ ;
: TOK-BUF ( -- ptr u8 ) TOK-A-FIELD @ ;

: CFG$ ( -- ptr u8 n ) CFG-BUF CFG-U @ ;
: OUT$ ( -- ptr u8 n ) OUT-BUF OUT-U @ ;
: FILE$ ( -- ptr u8 n ) FILE-BUF FILE-U @ ;
: OBJ$ ( -- ptr u8 n ) OBJ-BUF OBJ-U @ ;

: READ-INTO ( ptr u8 n ptr u8 ptr n -- ptr u8 n ) {: pa pu buf up :}
   pa pu buf BUF-CAP READ-ALL up !
   buf up @ ;

: READ-FILE$ ( ptr u8 n -- ptr u8 n )
   FILE-BUF FILE-U READ-INTO ;

: WRITE-PRIVATE ( ptr u8 n ptr u8 n -- ) {: pa pu src su :}
   pa pu WRITE-TARGET {: da du :}
   da du TMP-FOR
   TMP$ OPEN-PRIVATE src su WRITE-FD-ALL
   TMP$ da du RENAME-FILE ;

\ store directories are private at every level the store creates; a
\ sibling process may win the same mkdir, which is not a failure
: ENSURE-PRIVATE ( ptr u8 n -- ) {: a u :}
   a u DIR? if exit then
   a u DIRNAME dup 0 > if RECURSE else 2drop then
   a u FS-PATHZ MODE-PRIVATE-DIR mkdir 0 < if
      a u DIR? 0= if E-FS-IO throw then
   then ;

\ a provider's own directory keeps whatever mode the provider gave it
: ENSURE-DIR ( ptr u8 n -- ) {: a u :}
   a u DIR? if exit then
   a u ENSURE-PRIVATE ;

\ the primitive reports only failure, so an existing lock is told apart by stat
: LOCK-STORE ( -- )
   STORE$ ENSURE-PRIVATE
   LOCK$ FS-PATHZ MODE-PRIVATE-DIR mkdir 0 < if
      LOCK$ DIR? if E-SW-LOCKED throw then
      E-FS-IO throw
   then ;

: UNLOCK-STORE ( -- )
   LOCK$ REMOVE-DIR ;

: RUN-LOCKED ( [ -- ] -- ) {: body :}
   body execute ;

: WITH-LOCK ( [ -- ] -- )
   LOCK-STORE
   [: RUN-LOCKED ;] [: UNLOCK-STORE ;] finally ;

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
