split-str
\ sw-time.f - RFC 3339 date-times as epoch seconds.
require ../src/sw-base.f
require src/lib/date.f
require src/lib/adt/option.f
require src/lib/string.f
require src/lib/prelude.f

package SW

DATE:LEN 1+ constant RFC-HOUR-POS     \ HH after YYYY-MM-DD and its separator
RFC-HOUR-POS 8 + constant RFC-CLOCK-END   \ just past HH:MM:SS

\ the two digits at pos when they are at most top, else -1
: RFC-PART ( ^u8 n n -- n )
   {: a pos top :}
   a pos 2 DATE:N MATCH option
     none OF -1 ENDOF
     some OF dup top > if drop -1 then ENDOF
   ;MATCH ;

\ the seconds of HH:MM at pos, HH to 23 and MM to 59, else -1
: RFC-HM ( ^u8 n -- n )
   {: a pos :}
   a pos + 2 + c@ [char] : <> if -1 exit then
   a pos 23 RFC-PART {: h :}
   a pos 3 + 59 RFC-PART {: m :}
   h 0 < m 0 < or if -1 exit then
   h 3600 * m 60 * + ;

\ the seconds into the day of HH:MM:SS, a leap second 60 read as 59;
\ -1 when malformed
: RFC-CLOCK ( ^u8 -- n )
   {: a :}
   a RFC-HOUR-POS RFC-HM {: hm :}
   a RFC-HOUR-POS + 5 + c@ [char] : <> if -1 exit then
   a RFC-HOUR-POS 6 + 60 RFC-PART {: sec :}
   hm 0 < sec 0 < or if -1 exit then
   hm sec 59 min + ;

\ T, t or a space, which parts the date from the time
: RFC-SEP? ( n -- bool )
   {: c :}
   c [char] T =  c [char] t = or  c STR:SPACE = or ;

\ the epoch seconds of the date and time as if they were UTC
: RFC-LOCAL ( ^u8 -- option<n> )
   {: a :}
   a DATE:LEN + c@ RFC-SEP? 0= if OPTION:NONE exit then
   a RFC-CLOCK {: secs :}
   secs 0 < if OPTION:NONE exit then
   a DATE:LEN DATE:PARSE-YMD MATCH option
     none OF OPTION:NONE ENDOF
     some OF DATE:SECONDS-DAY * secs + OPTION:SOME ENDOF
   ;MATCH ;

\ the index past the time's fraction, if any; -1 for a dot without digits
: RFC-FRACTION ( ^u8 n -- n )
   {: a u :}
   a RFC-CLOCK-END + c@ [char] . <> if RFC-CLOCK-END exit then
   a u RFC-CLOCK-END 1+ DIGIT-RUN {: end :}
   end RFC-CLOCK-END 1+ = if -1 exit then
   end ;

\ Z or z, which names UTC itself
: UTC-ZONE? ( n -- bool )
   {: c :}
   c [char] Z =  c [char] z = or ;

\ 1 for +, -1 for -, 0 for any other byte
: OFFSET-SIGN ( n -- n )
   {: c :}
   c [char] + = if 1 exit then
   c [char] - = if -1 exit then
   0 ;

\ the seconds east of UTC that Z, z or +HH:MM or -HH:MM names
: RFC-OFFSET ( ^u8 n -- option<n> )
   {: z zu :}
   zu 1 = if z c@ UTC-ZONE? if 0 OPTION:SOME exit then then
   zu 6 <> if OPTION:NONE exit then
   z c@ OFFSET-SIGN {: sign :}
   z 1 RFC-HM {: off :}
   sign 0= off 0 < or if OPTION:NONE exit then
   sign off * OPTION:SOME ;

\ the zone's offset after the time and its fraction, the text's last bytes
: RFC-ZONE ( ^u8 n -- option<n> )
   {: a u :}
   a u RFC-FRACTION {: pos :}
   pos 0 < if OPTION:NONE exit then
   a pos + u pos - RFC-OFFSET ;

\ the epoch seconds of local seconds t in the text's zone, -1 when the
\ zone is malformed or the instant is before 1970
: RFC-UTC ( n ^u8 n -- n )
   {: t a u :}
   a u RFC-ZONE MATCH option
     none OF -1 ENDOF
     some OF t swap - dup 0 < if drop -1 then ENDOF
   ;MATCH ;

public

\ the epoch seconds of an RFC 3339 date-time, -1 when malformed or before 1970
: RFC3339>EPOCH ( ^u8 n -- n )
   {: a u :}
   u RFC-CLOCK-END <= if -1 exit then
   a RFC-LOCAL MATCH option
     none OF -1 ENDOF
     some OF a u RFC-UTC ENDOF
   ;MATCH ;

;package
