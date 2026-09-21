\ sw-json.f - checked field access over in-memory JSON documents.
require ../src/sw-io.f
require lib/float.f
require lib/json-read.f

package SW

create RD-STATE JR:STORAGE-BYTES allot

: OPEN-DOC ( ptr u8 n -- JR:reader )
   RD-STATE JR:STORAGE-BYTES 2swap JR:INIT ;

: ENTER-OBJECT ( JR:reader -- JR:reader )
   JR:NEXT JR:T-OBJ <> if E-SW-JSON throw then ;

\ position on key's object value; false when the key is absent, null, or
\ of another kind, so a damaged value reads as "no login" rather than failing
: KEY-OBJECT ( JR:reader ptr u8 n -- JR:reader bool ) {: k ku :}
   k ku JR:FIND-KEY 0= if false exit then
   JR:TOKEN JR:T-OBJ = ;

\ decode key's string value into dst; -1 when absent, null, or not a string
: KEY-STR ( JR:reader ptr u8 n ptr u8 n -- JR:reader n ) {: k ku dst cap :}
   k ku JR:FIND-KEY 0= if -1 exit then
   JR:TOKEN JR:T-STR <> if -1 exit then
   dst cap JR:STR ;

public

: DOC-STR1 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k ku dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k ku dst cap KEY-STR
   swap JR:CLOSE ;

: DOC-INT1 ( ptr u8 n ptr u8 n -- n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku JR:FIND-KEY 0= if JR:CLOSE -1 exit then
   JR:TOKEN JR:T-INT <> if JR:CLOSE -1 exit then
   JR:INT swap JR:CLOSE ;

: DOC-INT2 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JR:CLOSE -1 exit then
   k2 k2u JR:FIND-KEY 0= if JR:CLOSE -1 exit then
   JR:TOKEN JR:T-INT <> if JR:CLOSE -1 exit then
   JR:INT swap JR:CLOSE ;

: DOC-STR2 ( ptr u8 n ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k1 k1u k2 k2u dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JR:CLOSE -1 exit then
   k2 k2u dst cap KEY-STR
   swap JR:CLOSE ;

\ offset and length of the current value, whatever its kind: a container
\ runs to its closer, a string includes its quotes, a scalar is its literal
: VALUE-SPAN ( JR:reader ptr u8 -- JR:reader n n ) {: d :}
   JR:TOKEN {: t :}
   t JR:T-OBJ = t JR:T-ARR = or if JR:VALUE-SPAN$ else JR:SPAN$ then {: a u :}
   t JR:T-STR = if a d - 1- u 2 + exit then
   a d - u ;

public

\ offset and length of key's value of any kind; false with zeros when absent
: DOC-VALUE-SPAN? ( ptr u8 n ptr u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku JR:FIND-KEY 0= if JR:CLOSE 0 0 false exit then
   d VALUE-SPAN {: off len :}
   JR:CLOSE
   off len true ;

\ byte offset and length of key's object value; false with zeros when absent
: DOC-OBJ-SPAN? ( ptr u8 n ptr u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JR:CLOSE 0 0 false exit then
   JR:VALUE-SPAN$ {: a u :}
   JR:CLOSE
   a d - u true ;

: DOC-OBJ-SPAN ( ptr u8 n ptr u8 n -- n n )
   DOC-OBJ-SPAN? 0= if E-SW-JSON throw then ;

\ offset of the top-level object's closing brace, and whether it has members
: DOC-CLOSE ( ptr u8 n -- n bool ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   JR:NEXT JR:T-OBJ-END = {: empty :}
   JR:CLOSE
   d du OPEN-DOC ENTER-OBJECT
   JR:VALUE-SPAN$ {: a u :}
   JR:CLOSE
   a d - u + 1- empty 0= ;

\ the whole document must be exactly one object
: CHECK-OBJECT ( ptr u8 n -- )
   OPEN-DOC ENTER-OBJECT
   JR:SKIP-VALUE
   JR:NEXT JR:T-END <> if JR:CLOSE E-SW-JSON throw then
   JR:CLOSE ;

;package
