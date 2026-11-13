\ sw-json.f - checked field access over in-memory JSON documents: login
\ documents and provider answers alike, as kiba-mac's JSONDoc and JSONFields
\ read them.
require ../src/sw-io.f
require src/lib/float.f
require src/lib/json.f
require src/lib/byte-buffer.f
require src/lib/decimal.f

package SW

4096 constant TEXT-CAP              \ a string kiba reads from a document or answer

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

\ a string decoded whole, so TEXT-INTO can tell one its buffer cannot hold
create TEXT-HDR BUF:HDR-BYTES allot

\ the string at the reader decoded into dst; E-SW-CAPACITY when it decodes
\ to more than cap bytes
: TEXT-INTO ( JSON:reader ptr u8 n -- JSON:reader n ) {: dst cap :}
   TEXT-HDR TEXT-CAP BUF:N>BLEN BUF:RESET
   TEXT-HDR JSON:READ-STR-APPEND
   TEXT-HDR BUF:SPAN$ BUF:BLEN>N {: a u :}
   u cap > if s" bytes in a JSON string" cap LIMIT$ TOO-MANY then
   a dst u BYTE-COPY u ;

\ key's string decoded into dst; -1 when absent, null, or not a string
: KEY-STR ( JSON:reader ptr u8 n ptr u8 n -- JSON:reader n ) {: k ku dst cap :}
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

: KEY-WHOLE ( JSON:reader ptr u8 n -- JSON:reader n bool ) {: k ku :}
   k ku JSON:READ-FIND-KEY 0= if 0 false exit then
   WHOLE ;

\ ---- repeated keys ---------------------------------------------------------
\ JSONDoc refuses a document whose root object, or an object directly under
\ it, repeats a key; JSONFields one in which any object does.
TYPED-VARIABLE NEST-STATE JSON:cursor

\ the object whose opening brace is at, inside d du, repeats a key
: NEST-REPEATS? ( ptr u8 n ptr u8 -- bool )
   {: d du at :}
   at d - {: off :}
   NEST-STATE at du off - JSON:READ-INIT
   JSON:READ-NEXT drop JSON:READ-VALUE-SPAN$ {: a u :}
   JSON:READ-CLOSE
   a u JSON:READ-REPEATS? ;

: TOKEN-REPEATS? ( JSON:reader ptr u8 n -- JSON:reader bool )
   {: d du :}
   JSON:READ-TOKEN JSON:T-OBJ <> if false exit then
   JSON:READ-SPAN$ drop {: at :}
   d du at NEST-REPEATS? ;

\ whether any object in d du, which is well formed, repeats a key
: REPEATS? ( ptr u8 n -- bool ) {: d du :}
   d du OPEN-DOC
   begin JSON:READ-NEXT JSON:T-END <> while
      d du TOKEN-REPEATS? if JSON:READ-CLOSE true exit then
   repeat
   JSON:READ-CLOSE false ;

: UNIQUE-KEYS ( ptr u8 n -- ) REPEATS? if E-SW-JSON throw then ;

\ whether the root object of d du, which is well formed, or an object
\ directly under it repeats a key
: TOP-REPEATS? ( ptr u8 n -- bool ) {: d du :}
   d du OPEN-DOC
   JSON:READ-NEXT drop
   d du TOKEN-REPEATS? if JSON:READ-CLOSE true exit then
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-NEXT drop
      d du TOKEN-REPEATS? if JSON:READ-CLOSE true exit then
      JSON:READ-SKIP-VALUE
   repeat
   JSON:READ-CLOSE false ;

public

: DOC-STR1 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k ku dst cap :}
   d du OPEN-DOC ENTER-OBJECT
   k ku dst cap KEY-STR
   swap JSON:READ-CLOSE ;

: DOC-INT1 ( ptr u8 n ptr u8 n -- n bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-WHOLE rot JSON:READ-CLOSE ;

: DOC-INT2 ( ptr u8 n ptr u8 n ptr u8 n -- n bool ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE 0 false exit then
   k2 k2u KEY-WHOLE rot JSON:READ-CLOSE ;

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


\ the whole document is exactly one object, as JSONDoc takes one: neither it
\ nor an object directly under it repeats a key
: CHECK-OBJECT ( ptr u8 n -- ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   JSON:READ-SKIP-VALUE
   JSON:READ-NEXT JSON:T-END <> if JSON:READ-CLOSE E-SW-JSON throw then
   JSON:READ-CLOSE
   d du TOP-REPEATS? if E-SW-JSON throw then ;

\ the document is one object as JSONFields takes one: CHECK-OBJECT's, and no
\ object at any depth repeats a key
: CHECK-FIELDS ( ptr u8 n -- ) {: d du :}
   d du CHECK-OBJECT
   d du UNIQUE-KEYS ;

\ the document is one JSONFields reads: CHECK-FIELDS as try? runs it
: FIELDS? ( ptr u8 n -- bool )
   [: 2dup CHECK-FIELDS ;] catch {: rc :} 2drop rc 0= ;

;package
