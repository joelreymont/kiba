split-str
\ sw-json.f - checked field access over in-memory JSON documents: login
\ documents and provider answers alike, as kiba-mac's JSONDoc and JSONFields
\ read them.
require ../src/sw-io.f
require ../src/sw-base.f
require src/lib/float.f
require src/lib/json.f
require src/lib/byte-buffer.f
require src/lib/decimal.f
require src/lib/hashmap.f
require src/lib/string.f
require src/lib/adt/option.f
require src/lib/prelude.f

package SW

4096 constant TEXT-CAP              \ a string kiba reads from a document or answer

TYPED-VARIABLE RD-STATE JSON:cursor

: OPEN-DOC ( ^u8 n -- JSON:reader )
   RD-STATE -rot JSON:READ-INIT ;

: ENTER-OBJECT ( JSON:reader -- JSON:reader )
   JSON:READ-NEXT JSON:T-OBJ <> if E-SW-JSON throw then ;

\ position on key's object value; false when the key is absent, null, or
\ of another kind, so a damaged value reads as "no login" rather than failing
: KEY-OBJECT ( JSON:reader ^u8 n -- JSON:reader bool ) {: k ku :}
   k ku JSON:READ-FIND-KEY 0= if false exit then
   JSON:READ-TOKEN JSON:T-OBJ = ;

\ a string decoded whole, so TEXT-INTO can tell one its buffer cannot hold
create TEXT-HDR BUF:HDR-BYTES allot

\ the string at the reader decoded into dst; E-SW-CAPACITY when it decodes
\ to more than cap bytes
: TEXT-INTO ( JSON:reader ^u8 n -- JSON:reader n ) {: dst cap :}
   TEXT-HDR TEXT-CAP BUF:N>BLEN BUF:RESET
   TEXT-HDR JSON:READ-STR-APPEND
   TEXT-HDR BUF:SPAN$ BUF:BLEN>N {: a u :}
   u cap > if s" bytes in a JSON string" cap LIMIT$ TOO-MANY then
   a dst u BYTE-COPY u ;

\ key's string decoded into dst; -1 when absent, null, or not a string
: KEY-STR ( JSON:reader ^u8 n ^u8 n -- JSON:reader n ) {: k ku dst cap :}
   k ku JSON:READ-FIND-KEY 0= if -1 exit then
   JSON:READ-TOKEN JSON:T-STR <> if -1 exit then
   dst cap TEXT-INTO ;

: NUMBER-TOKEN? ( n -- bool ) dup JSON:T-INT = swap JSON:T-FLOAT = or ;

\ the number at the reader as JSONFields.int reads it: any spelling of an
\ integer a cell holds (5, 5.0, 5e0); 0 false for any other value
: WHOLE ( JSON:reader -- JSON:reader n bool )
   JSON:READ-TOKEN NUMBER-TOKEN? 0= if 0 false exit then
   JSON:READ-SPAN$ DECIMAL:EXACT MATCH option
     none OF 0 false ENDOF
     some OF true ENDOF
   ;MATCH ;

: OR-ZERO ( n bool -- n ) 0= if drop 0 then ;

: KEY-WHOLE ( JSON:reader ^u8 n -- JSON:reader n bool ) {: k ku :}
   k ku JSON:READ-FIND-KEY 0= if 0 false exit then
   WHOLE ;

\ ---- repeated keys ---------------------------------------------------------
\ JSONDoc refuses a document whose root object, or an object directly under
\ it, repeats a key; JSONFields one in which any object does. REPEATS? reads
\ the document once and keeps each open object's decoded keys: HM:PROBE finds
\ the slot of a hash of the object and the key, and the keys listed under that
\ slot are compared byte for byte. A member takes at least five source bytes
\ ("":0,), so u bytes hold at most u/5 + 1 keys, which decode to at most u
\ bytes, and at most u/2 + 1 containers are open at once.
DYNAMIC-BUFFER KEY-HASHES n   \ HM:PROBE's keys: each slot's hash
DYNAMIC-BUFFER KEY-SLOTS n    \ HM:PROBE's used: the slot's latest key + 1
\ a member's key: link is the slot's earlier key + 1, or 0; off and len place
\ it in KEY-ROOM
STRUCTURE member DERIVE addr
   FIELD link n FIELD object n FIELD off n FIELD len n
;STRUCTURE
DYNAMIC-BUFFER KEY-LIST member
DYNAMIC-BUFFER KEY-ROOM u8    \ the decoded keys, end to end
DYNAMIC-BUFFER OPEN-IDS n     \ per open container, its opening byte's address
variable KEY-CAP   variable ROOM-CAP   variable KEY-N   variable KEY-END
variable OPEN-N

$7FFFFFFFFFFFFFFF constant ANY-DEPTH
$CBF29CE484222325 constant FNV-BASIS
$100000001B3 constant FNV-PRIME

\ the least power of two that is at least twice keys
: TABLE-CAP ( n -- n ) {: keys :}
   1 begin dup keys 2 * < while 2 * repeat ;

: SIZE-TABLE ( n -- ) {: keys :}
   keys TABLE-CAP {: cap :}
   cap KEY-HASHES-RESERVE  cap KEY-SLOTS-RESERVE
   0 KEY-SLOTS cap HM:CLEAR
   cap KEY-CAP !  0 KEY-N ! ;

: SIZE-KEYS ( n -- ) {: du :}
   du 5 / 1+ {: keys :}
   keys SIZE-TABLE  keys KEY-LIST-RESERVE
   du KEY-ROOM-RESERVE  du ROOM-CAP !  0 KEY-END !
   du 2 / 1+ OPEN-IDS-RESERVE  0 OPEN-N ! ;

: FREE-KEYS ( -- )
   KEY-HASHES-RELEASE KEY-SLOTS-RELEASE KEY-LIST-RELEASE
   KEY-ROOM-RELEASE OPEN-IDS-RELEASE ;

\ FNV-1a over a key's bytes, seeded with its object; HM:PROBE mixes it
: KEY-HASH ( n ^u8 n -- n ) {: obj a u :}
   obj HM:HASH64 FNV-BASIS xor
   u 0 ?do a i + c@ xor FNV-PRIME * loop ;

: KEY-AT$ ( n -- ^u8 n ) {: e :}
   e KEY-LIST MEMBER-OFF @ KEY-ROOM  e KEY-LIST MEMBER-LEN @ ;

: SAME-KEY? ( n n ^u8 n -- bool ) {: e obj a u :}
   e KEY-LIST MEMBER-OBJECT @ obj <> if false exit then
   e KEY-AT$ a u STR= ;

\ whether the keys listed from link, a key + 1 or 0, hold obj's key a u
: LISTED? ( n n ^u8 n -- bool ) {: link obj a u :}
   link begin dup 0<> while
      1- dup obj a u SAME-KEY? if drop true exit then
      KEY-LIST MEMBER-LINK @
   repeat drop false ;

\ the key at the reader, decoded after the keys before it
: DECODE-KEY ( JSON:reader -- JSON:reader ^u8 n )
   KEY-END @ {: off :}
   off KEY-ROOM  ROOM-CAP @ off -  JSON:READ-STR {: u :}
   off KEY-ROOM u ;

\ obj's key of u bytes, just decoded, becomes slot's latest key, hashed h
: KEEP-KEY ( n n n n -- ) {: slot h obj u :}
   KEY-N @ {: e :}
   slot KEY-SLOTS @ e KEY-LIST MEMBER-LINK !  obj e KEY-LIST MEMBER-OBJECT !
   KEY-END @ e KEY-LIST MEMBER-OFF !  u e KEY-LIST MEMBER-LEN !
   h slot KEY-HASHES !  e 1+ slot KEY-SLOTS !
   1 KEY-N +!  u KEY-END +! ;

\ whether the key at the reader repeats one of obj's; else obj keeps it
: REPEATED? ( JSON:reader n -- JSON:reader bool ) {: obj :}
   DECODE-KEY {: a u :}
   obj a u KEY-HASH {: h :}
   0 KEY-HASHES 0 KEY-SLOTS KEY-CAP @ h HM:PROBE {: slot :}
   slot KEY-SLOTS @ obj a u LISTED? if true exit then
   slot h obj u KEEP-KEY false ;

: OPEN-TOP ( -- n ) OPEN-N @ 1- OPEN-IDS @ ;

\ the container opened at the reader is entered at depth bound or less and
\ skipped whole deeper; the root is depth 0
: ENTER-AT ( JSON:reader n -- JSON:reader ) {: bound :}
   OPEN-N @ bound > if JSON:READ-SKIP-VALUE exit then
   JSON:READ-SPAN$ drop NULL-PTR - OPEN-N @ OPEN-IDS !
   1 OPEN-N +! ;

: OPENER? ( n -- bool ) dup JSON:T-OBJ = swap JSON:T-ARR = or ;
: CLOSER? ( n -- bool ) dup JSON:T-OBJ-END = swap JSON:T-ARR-END = or ;

\ whether the token of this kind is a key that repeats one of its object's
: VISIT ( JSON:reader n n -- JSON:reader bool ) {: kind bound :}
   kind JSON:T-KEY = if OPEN-TOP REPEATED? exit then
   kind OPENER? if bound ENTER-AT false exit then
   kind CLOSER? if -1 OPEN-N +! then
   false ;

: WALK ( ^u8 n n -- bool ) {: d du bound :}
   du SIZE-KEYS
   d du OPEN-DOC
   begin JSON:READ-NEXT dup JSON:T-END <> while
      bound VISIT if JSON:READ-CLOSE true exit then
   repeat
   drop JSON:READ-CLOSE false ;

\ whether an object at depth bound or less in d du, which is well formed,
\ repeats a key
: REPEATS? ( ^u8 n n -- bool ) {: d du bound :}
   [: d du bound WALK ;] [: FREE-KEYS ;] finally ;

: UNIQUE-KEYS ( ^u8 n -- )
   ANY-DEPTH REPEATS? if E-SW-JSON throw then ;

\ the whole document is exactly one object
: ONE-OBJECT ( ^u8 n -- )
   OPEN-DOC ENTER-OBJECT
   JSON:READ-SKIP-VALUE
   JSON:READ-NEXT JSON:T-END <> if JSON:READ-CLOSE E-SW-JSON throw then
   JSON:READ-CLOSE ;

public

: DOC-STR1 ( ^u8 n ^u8 n ^u8 n -- n ) {: d du k ku dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k ku dst cap KEY-STR
   swap JSON:READ-CLOSE ;

: DOC-INT1 ( ^u8 n ^u8 n -- n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-WHOLE rot JSON:READ-CLOSE ;

: DOC-INT2 ( ^u8 n ^u8 n ^u8 n -- n bool ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE 0 false exit then
   k2 k2u KEY-WHOLE rot JSON:READ-CLOSE ;

: DOC-STR2 ( ^u8 n ^u8 n ^u8 n ^u8 n -- n ) {: d du k1 k1u k2 k2u dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE -1 exit then
   k2 k2u dst cap KEY-STR
   swap JSON:READ-CLOSE ;

public

\ offset and length of key's value of any kind; false with zeros when absent
: DOC-VALUE-SPAN? ( ^u8 n ^u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE 0 0 false exit then
   JSON:READ-ANY-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u true ;

\ byte offset and length of key's object value; false with zeros when absent
: DOC-OBJ-SPAN? ( ^u8 n ^u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JSON:READ-CLOSE 0 0 false exit then
   JSON:READ-VALUE-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u true ;

: DOC-OBJ-SPAN ( ^u8 n ^u8 n -- n n )
   DOC-OBJ-SPAN? 0= if E-SW-JSON throw then ;

\ offset of the top-level object's closing brace, and whether it has members
: DOC-CLOSE ( ^u8 n -- n bool ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   JSON:READ-NEXT JSON:T-OBJ-END = {: empty :}
   JSON:READ-CLOSE
   d du OPEN-DOC ENTER-OBJECT
   JSON:READ-VALUE-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u + 1- empty 0= ;


\ the whole document is exactly one object, as JSONDoc takes one: neither it
\ nor an object directly under it repeats a key
: CHECK-OBJECT ( ^u8 n -- ) {: d du :}
   d du ONE-OBJECT
   d du 1 REPEATS? if E-SW-JSON throw then ;

\ the document is one object as JSONFields takes one: CHECK-OBJECT's, and no
\ object at any depth repeats a key
: CHECK-FIELDS ( ^u8 n -- ) {: d du :}
   d du ONE-OBJECT
   d du UNIQUE-KEYS ;

\ the document is one JSONFields reads: CHECK-FIELDS as try? runs it
: FIELDS? ( ^u8 n -- bool )
   [: 2dup CHECK-FIELDS ;] catch {: rc :} 2drop rc 0= ;

;package
