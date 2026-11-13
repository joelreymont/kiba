\ sw-json.f - checked field access over in-memory JSON documents.
require ../src/sw-io.f
require src/lib/float.f
require src/lib/json.f

package SW

TYPED-VARIABLE RD-STATE JSON:cursor

: OPEN-DOC ( ptr u8 n -- JSON:reader )
   RD-STATE -rot JSON:READ-INIT ;

: ENTER-OBJECT ( JSON:reader -- JSON:reader )
   JSON:READ-NEXT JSON:T-OBJ <> if E-SW-JSON throw then ;

\ position on key's object value; false when the key is absent, null, or
\ of another kind, so a damaged value reads as "no login" rather than failing
: KEY-OBJECT ( JSON:reader ptr u8 n -- JSON:reader bool ) {: k ku :}
   k ku JSON:READ-FIND-KEY 0= if false exit then
   JSON:READ-TOKEN JSON:T-OBJ = ;

\ decode key's string value into dst; -1 when absent, null, or not a string
: KEY-STR ( JSON:reader ptr u8 n ptr u8 n -- JSON:reader n ) {: k ku dst cap :}
   k ku JSON:READ-FIND-KEY 0= if -1 exit then
   JSON:READ-TOKEN JSON:T-STR <> if -1 exit then
   dst cap JSON:READ-STR ;

public

: DOC-STR1 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k ku dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k ku dst cap KEY-STR
   swap JSON:READ-CLOSE ;

: DOC-INT1 ( ptr u8 n ptr u8 n -- n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE -1 exit then
   JSON:READ-TOKEN JSON:T-INT <> if JSON:READ-CLOSE -1 exit then
   JSON:READ-INT swap JSON:READ-CLOSE ;

: DOC-INT2 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE -1 exit then
   k2 k2u JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE -1 exit then
   JSON:READ-TOKEN JSON:T-INT <> if JSON:READ-CLOSE -1 exit then
   JSON:READ-INT swap JSON:READ-CLOSE ;

: DOC-STR2 ( ptr u8 n ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k1 k1u k2 k2u dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE -1 exit then
   k2 k2u dst cap KEY-STR
   swap JSON:READ-CLOSE ;

public

\ offset and length of key's value of any kind; false with zeros when absent
: DOC-VALUE-SPAN? ( ptr u8 n ptr u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE 0 0 false exit then
   JSON:READ-ANY-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u true ;

\ byte offset and length of key's object value; false with zeros when absent
: DOC-OBJ-SPAN? ( ptr u8 n ptr u8 n -- n n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JSON:READ-CLOSE 0 0 false exit then
   JSON:READ-VALUE-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u true ;

: DOC-OBJ-SPAN ( ptr u8 n ptr u8 n -- n n )
   DOC-OBJ-SPAN? 0= if E-SW-JSON throw then ;

\ offset of the top-level object's closing brace, and whether it has members
: DOC-CLOSE ( ptr u8 n -- n bool ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   JSON:READ-NEXT JSON:T-OBJ-END = {: empty :}
   JSON:READ-CLOSE
   d du OPEN-DOC ENTER-OBJECT
   JSON:READ-VALUE-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a d - u + 1- empty 0= ;

\ the whole document must be exactly one object
: CHECK-OBJECT ( ptr u8 n -- )
   OPEN-DOC ENTER-OBJECT
   JSON:READ-SKIP-VALUE
   JSON:READ-NEXT JSON:T-END <> if JSON:READ-CLOSE E-SW-JSON throw then
   JSON:READ-CLOSE ;

;package
