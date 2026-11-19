split-str
\ sw-usage.f - per-account rate limits, read from each provider's usage
\ endpoint through libcurl. A probe takes a saved login's document and
\ whether the CLI is using it, and leaves the usage record (sw-db.f), the
\ document in PROBE-DOC$, renewed when a token was, and the plan the provider
\ named. It reads and writes no slot and takes no lock: the caller holds the
\ provider's turn and records the outcome. A reset request (REDEEM) spends
\ one limit reset under the same terms and leaves its outcome and the
\ document.
require ../src/sw-store.f
require ../src/sw-db.f
require ../src/sw-base.f
require ../src/sw-paths.f
require ../src/sw-io.f
require ../src/sw-json.f
require ../src/sw-identity.f
require src/lib/date.f
require src/lib/json.f
require src/lib/byte-buffer.f
require src/lib/decimal.f
require src/lib/fsm.f
require src/lib/fmt.f
require src/lib/entropy.f
require src/lib/adt/option.f
require src/lib/fs-mutate.f
require src/lib/fs.f
require src/lib/net/curl.f
require src/lib/prelude.f
require src/lib/process-argv.f
require src/lib/process-fork.f
require src/lib/process.f
require src/lib/string.f
require src/lib/span.f
require src/lib/vector.f

package SW

120 constant DETAIL-MAX             \ the longest server-supplied text a note carries
20 constant HTTP-TIMEOUT-SEC

create DATE-BUF DATE:TIME-LEN allot   \ the UTC format fixes its length

\ ---- decimal parsing -----------------------------------------------------------
: DIGIT ( n -- n ) $30 - ;

: DIGIT? ( n -- bool ) dup $30 >= swap $39 <= and ;

\ A reading is a JSON number's spelling, -?d+(.d+)?([eE][+-]?d+)?, in percent
\ (12.495 means 12.495%). Its whole percent is rounded once from those decimal
\ digits, half away from zero, never through a binary float.
$7FFFFFFFFFFFFFFF constant INT-MAX

variable MANT-START                 \ the mantissa's first digit
variable MANT-POINT                 \ its decimal point; MANT-END when it has none
variable MANT-END                   \ the index after its last digit
variable EXP-VALUE                  \ the exponent, its magnitude held to a cap

: BYTE-IS? ( ^u8 n n n -- bool ) {: a u at c :}
   at u < if at a + c@ c = else false then ;

\ the first index from at whose byte is not a digit
: DIGIT-RUN ( ^u8 n n -- n ) {: a u at :}
   at begin dup u < if dup a + c@ DIGIT? else false then while 1+ repeat ;

\ the value digits lo..hi-1 spell, held to cap
: DIGIT-VALUE ( ^u8 n n n -- n ) {: a lo hi cap :}
   0 hi lo ?do 10 * a i + c@ DIGIT + cap min loop ;

\ the mantissa from index at; false when a side of its point has no digit
: MANTISSA? ( ^u8 n n -- bool ) {: a u at :}
   at MANT-START !
   a u at DIGIT-RUN {: q :}
   q MANT-POINT ! q MANT-END !
   q at = if false exit then
   a u q $2E BYTE-IS? 0= if true exit then
   a u q 1+ DIGIT-RUN {: m :}
   m MANT-END !
   m q 1+ > ;

\ the exponent at index at, if any, into EXP-VALUE; the index after it, -1
\ when malformed. Its magnitude is held to u + 20: past that a nonzero
\ mantissa is past INT-MAX, or below 0.1, either way.
: EXPONENT-AT ( ^u8 n n -- n ) {: a u at :}
   0 EXP-VALUE !
   a u at $65 BYTE-IS? a u at $45 BYTE-IS? or 0= if at exit then
   a u at 1+ $2D BYTE-IS? {: neg :}
   a u at 1+ $2B BYTE-IS? neg or if at 2 + else at 1+ then {: lo :}
   a u lo DIGIT-RUN {: hi :}
   hi lo = if -1 exit then
   a lo hi u 20 + DIGIT-VALUE neg if negate then EXP-VALUE !
   hi ;

\ mantissa digit k, counting from its first and skipping the point; 0 past its last
: MANT-DIGIT ( ^u8 n -- n ) {: a k :}
   MANT-START @ k + dup MANT-POINT @ >= if 1+ then {: at :}
   at MANT-END @ >= if 0 exit then
   at a + c@ DIGIT ;

\ acc * 10 + d; -1 once past INT-MAX
: SHIFT-DIGIT ( n n -- n ) {: acc d :}
   acc 0 < if -1 exit then
   acc INT-MAX d - 10 / > if -1 exit then
   acc 10 * d + ;

: MANT-ZERO? ( ^u8 -- bool ) {: a :}
   true MANT-END @ MANT-START @ ?do a i + c@ dup $30 = swap $2E = or and loop ;

\ the mantissa rounded to its first p digits, half up; -1 past INT-MAX
: MANT-ROUNDED ( ^u8 n -- n ) {: a p :}
   0 p 0 ?do a i MANT-DIGIT SHIFT-DIGIT loop {: w :}
   w 0 < if -1 exit then
   p 0 < if w exit then
   a p MANT-DIGIT 5 < if w exit then
   w INT-MAX = if -1 exit then
   w 1+ ;

\ the whole percent reading a u spells, rounded half up;
\ -1 when it is malformed, below zero or past INT-MAX
: USED-PERCENT ( ^u8 n -- n ) {: a u :}
   a u 0 $2D BYTE-IS? {: neg :}
   a u neg if 1 else 0 then MANTISSA? 0= if -1 exit then
   a u MANT-END @ EXPONENT-AT u <> if -1 exit then
   neg a MANT-ZERO? 0= and if -1 exit then
   a MANT-POINT @ MANT-START @ - EXP-VALUE @ + MANT-ROUNDED ;

\ ---- one probe -------------------------------------------------------------------
variable PROBE-AT                   \ epoch seconds the probe began: its fetchedAt
variable PROBE-LIVE                 \ bool: the CLI is using this login; it is never refreshed
\ the login probed: the caller's bytes until a renewal points it at SDOC
TYPED-VARIABLE PROBE-DOC-A ^u8   variable PROBE-DOC-U
create PLAN-NAMED PLAN-CAP allot    variable PLAN-NAMED-U   \ -1 when the provider named none
variable HTTP-CODE                  \ the last answer's status, -1 when there was none

: PROBE-DOC! ( ^u8 n -- ) PROBE-DOC-U ! PROBE-DOC-A ! ;
: PROBE-DOC$ ( -- ^u8 n ) PROBE-DOC-A @ PROBE-DOC-U @ ;

\ the probe's outcome: a record of state st and note a u, without limits
: SAY ( usage-state ^u8 n -- ) {: st a u :}
   PROBE-AT @ st a u DB-USAGE! ;

\ ---- requests -------------------------------------------------------------------
\ A request is its header lines, its body and its URL, sent on one libcurl
\ handle that TRANSFER alone holds. Line i of HDR-TEXT ends at HDR-ENDS i.
TYPED-VARIABLE HDR-TEXT ^VEC:vector<u8>
DYNAMIC-BUFFER HDR-ENDS n
variable HDR-N
\ borrowed from the caller until TRANSFER returns; length -1 for a GET
TYPED-VARIABLE REQ-BODY-A ^u8   variable REQ-BODY-U
\ tests reach a local server through URL-BASE; length 0 sends each URL as written
create URL-BASE PATH-CAP allot     variable URL-BASE-U
TYPED-VARIABLE TARGET-TEXT ^VEC:vector<u8>

: SCHEME$ ( -- ^u8 n ) s" https://" ;

: HDR+ ( ^u8 n -- ) HDR-TEXT @ VEC:APPEND ;

: LINE-END ( -- )
   HDR-N @ {: i :}
   i 1+ HDR-ENDS-RESERVE
   HDR-TEXT @ TEXTS-END i HDR-ENDS !
   i 1+ HDR-N ! ;

: HDR ( ^u8 n ^u8 n -- ) {: name nu val vu :}
   name nu HDR+ s" : " HDR+ val vu HDR+ LINE-END ;

: BEARER ( ^u8 n -- ) {: t tu :}
   s" Authorization: Bearer " HDR+ t tu HDR+ LINE-END ;

: HDR-LINE$ ( n -- ^u8 n ) {: i :}
   i 0= if 0 else i 1- HDR-ENDS @ then {: lo :}
   HDR-TEXT @ lo i HDR-ENDS @ lo - TEXTS$ ;

\ Anthropic's token endpoint answers 429 to curl's own User-Agent whatever
\ the grant, so every request names its client
: KIBA-UA$ ( -- ^u8 n ) s" kiba" ;

\ a request that names its client ua
: REQUEST ( ^u8 n -- ) {: ua uu :}
   HDR-TEXT TEXTS-RESET 0 HDR-N !
   -1 REQ-BODY-U !
   s" Accept" s" application/json" HDR
   s" User-Agent" ua uu HDR ;

\ every URL kiba sends begins with SCHEME$, which URL-BASE replaces
: TARGET$ ( ^u8 n -- ^u8 n ) {: url uu :}
   URL-BASE-U @ 0= if url uu exit then
   TARGET-TEXT TEXTS-RESET
   URL-BASE URL-BASE-U @ TARGET-TEXT @ VEC:APPEND
   SCHEME$ nip {: s :}
   url s + uu s - TARGET-TEXT @ VEC:APPEND
   TARGET-TEXT @ VEC:SPAN SPAN:$ ;

: SET? ( CURL:status -- bool )
   MATCH CURL:status
      ok OF true ENDOF
      failed OF drop false ENDOF
   ;MATCH ;

: HEADERS-SET? ( CURL:handle -- bool ) {: h:CURL:handle :}
   HDR-N @ 0 ?do
      h i HDR-LINE$ CURL:HEADER+ SET? 0= if false unloop exit then
   loop true ;

: BODY-SET? ( CURL:handle -- bool ) {: h:CURL:handle :}
   REQ-BODY-U @ 0 < if true exit then
   h REQ-BODY-A @ REQ-BODY-U @ CURL:BODY! SET? ;

\ the answer's status, its body in OBJ-BUF; -1 when the transfer failed,
\ -2 when the body overran OBJ-BUF
: ANSWER ( CURL:fetch-result -- n )
   MATCH CURL:fetch-result
      response OF {: st:CURL:http-status got:len :}
         got LEN>N OBJ-U ! st CURL:HTTP-STATUS>N ENDOF
      truncated OF 2drop -2 ENDOF
      failed OF drop -1 ENDOF
   ;MATCH ;

: SEND-ON ( CURL:handle ^u8 n -- n ) {: h:CURL:handle url uu :}
   h HTTP-TIMEOUT-SEC 1000 * >MS CURL:TIMEOUT! SET? 0= if -1 exit then
   h HEADERS-SET? 0= if -1 exit then
   h BODY-SET? 0= if -1 exit then
   h url uu TARGET$ CURL:URL! SET? 0= if -1 exit then
   h OBJ-BUF BUF-CAP >LEN CURL:PERFORM ANSWER ;

\ the staged request sent to url: ANSWER's status, or -1 when it was not sent;
\ the handle, which holds copies of the bearer token, is freed on a throw too
: TRANSFER ( ^u8 n -- n ) {: url uu :}
   0 OBJ-U !
   CURL:INIT MATCH CURL:init-result
      ready OF {: h:CURL:handle :}
         [: h url uu SEND-ON ;] [: h CURL:CLEANUP ;] finally ENDOF
      failed OF drop -1 ENDOF
   ;MATCH ;

\ TRANSFER, where a body that overran OBJ-BUF throws
: SEND ( ^u8 n -- n )
   TRANSFER dup -2 = if DOC-TOO-BIG then ;

\ the body of the last answer
: ANSWER$ ( -- ^u8 n ) OBJ$ ;

\ the body bytes come from a finished JSON-OPEN chain
: POST-JSON ( ^u8 n ^u8 n -- n ) {: b bu url uu :}
   b REQ-BODY-A ! bu REQ-BODY-U !
   s" Content-Type" s" application/json" HDR
   url uu SEND ;

\ "<what> answered <code>", or "<what> could not be reached" when code < 0
: HTTP-NOTE ( ^u8 n n -- ^u8 n ) {: what wu code :}
   SB-RESET what wu SB-APPEND
   code 0 < if s"  could not be reached" SB-APPEND SB$ exit then
   s"  answered " SB-APPEND code FMT:SB-U SB$ ;

: UNREADABLE-NOTE ( ^u8 n -- ^u8 n ) {: what wu :}
   SB-RESET what wu SB-APPEND s"  sent an answer that is not a JSON object" SB-APPEND SB$ ;

\ a token request answered; its status is in HTTP-CODE
: TOKEN-POST ( ^u8 n ^u8 n -- n ) {: b bu url uu :}
   KIBA-UA$ REQUEST
   b bu url uu POST-JSON
   dup HTTP-CODE ! ;

\ only a token endpoint's 400 or 401 proves a saved login gone
: REFUSED-STATUS? ( n -- bool ) dup 400 = swap 401 = or ;

\ ---- reading answers -------------------------------------------------------------
\ A document or answer is read field by field only once it is known to be
\ one JSON object in which no object, nested ones included, repeats a key
\ (FIELDS?); a field of another kind reads as absent.
: KEY-OBJ? ( ^u8 n ^u8 n -- bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT swap JSON:READ-CLOSE ;

\ the token kind of the member k2 of the object at k1; JSON:T-END when absent
: KIND2 ( ^u8 n ^u8 n ^u8 n -- n ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE JSON:T-END exit then
   k2 k2u JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE JSON:T-END exit then
   JSON:READ-TOKEN swap JSON:READ-CLOSE ;

: TRUE2? ( ^u8 n ^u8 n ^u8 n -- bool ) KIND2 JSON:T-TRUE = ;

\ the member k2 of the object at k1 is the string w
: STR2-IS? ( ^u8 n ^u8 n ^u8 n ^u8 n -- bool ) {: d du k1 k1u k2 k2u w wu :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   k2 k2u JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE false exit then
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-CLOSE false exit then
   w wu JSON:READ-STR-EQ? swap JSON:READ-CLOSE ;

\ ---- one line of server text ------------------------------------------------------
\ Each run of whitespace and control characters becomes one space, and the
\ line is cut to DETAIL-MAX Unicode scalars ending in an ellipsis, so combining
\ marks cannot stack past the bound.
create LINE-OUT DETAIL-MAX 4 * allot   variable LINE-U
variable LINE-N                     \ scalars in the line, counted past the cut
variable LINE-CUT                   \ bytes of its first DETAIL-MAX - 1 scalars
variable LINE-GAP                   \ bool: a separator run waits for the next scalar

: SCALAR-LEN ( n -- n ) {: c :}
   c $C0 < if 1 exit then
   c $E0 < if 2 exit then
   c $F0 < if 3 exit then
   4 ;

\ the code point of the UTF-8 sequence of len bytes at a
: SCALAR@ ( ^u8 n -- n ) {: a len :}
   a c@ len 1 = if exit then
   $7F len rshift and
   len 1 ?do 6 lshift a i + c@ $3F and or loop ;

\ White_Space or a control character
: SEPARATOR? ( n -- bool ) {: c :}
   c $20 <= if true exit then
   c $7F >= c $A0 <= and if true exit then
   c $2000 >= c $200A <= and if true exit then
   c $1680 = c $2028 = or c $2029 = or c $202F = or c $205F = or c $3000 = or ;

: LINE-COPY ( ^u8 n -- ) {: a len :}
   a LINE-OUT LINE-U @ + len BYTE-COPY
   len LINE-U +! ;

: LINE-SCALAR ( ^u8 n -- ) {: a len :}
   1 LINE-N +!
   LINE-N @ DETAIL-MAX <= if a len LINE-COPY then
   LINE-N @ DETAIL-MAX 1- = if LINE-U @ LINE-CUT ! then ;

: LINE-STEP ( ^u8 n -- ) {: a len :}
   a len SCALAR@ SEPARATOR? if LINE-N @ 0 > LINE-GAP ! exit then
   LINE-GAP @ if false LINE-GAP ! s"  " LINE-SCALAR then
   a len LINE-SCALAR ;

: ONE-LINE ( ^u8 n -- ^u8 n ) {: a u :}
   0 LINE-U ! 0 LINE-N ! 0 LINE-CUT ! false LINE-GAP !
   0 begin dup u < while
      {: i :}
      a i + c@ SCALAR-LEN u i - min {: len :}
      a i + len LINE-STEP
      i len +
   repeat drop
   LINE-N @ DETAIL-MAX > if LINE-CUT @ LINE-U ! s" …" LINE-COPY then
   LINE-OUT LINE-U @ ;

\ ---- rewriting a login document ----------------------------------------------------------
\ CFG holds the document; each change splices OUT and copies it back.
: SPLICE-CFG ( n n ^u8 n -- ) {: off len v vu :}
   0 OUT-U !
   off vu + CFG-U @ off len + - + BUF-CAP > if DOC-TOO-BIG then
   CFG-BUF OUT-BUF off BYTE-COPY
   v OUT-BUF off + vu BYTE-COPY
   CFG-BUF off len + + OUT-BUF off vu + + CFG-U @ off len + - BYTE-COPY
   off vu + CFG-U @ off len + - + OUT-U !
   OUT-BUF CFG-BUF OUT-U @ BYTE-COPY
   OUT-U @ CFG-U ! ;

\ the member "k":v inserted at the closing brace at, after a comma when its
\ object has members; v is in place before the builder makes the prefix
: CFG-ADD ( n bool ^u8 n ^u8 n -- ) {: at members k ku v vu :}
   at 0 v vu SPLICE-CFG
   SB-RESET members if $2C SB-APPEND-C then
   $22 SB-APPEND-C k ku SB-APPEND $22 SB-APPEND-C $3A SB-APPEND-C
   at 0 SB$ SPLICE-CFG ;

\ the top-level key's value set to a JSON literal, added at the end when absent
: CFG-SET ( ^u8 n ^u8 n -- ) {: k ku v vu :}
   CFG$ k ku DOC-VALUE-SPAN? {: off len found :}
   found if off len v vu SPLICE-CFG exit then
   CFG$ DOC-CLOSE k ku v vu CFG-ADD ;

\ the same one level down, inside the object at k1, which must be there
: CFG-SET2 ( ^u8 n ^u8 n ^u8 n -- ) {: k1 k1u k2 k2u v vu :}
   CFG$ k1 k1u DOC-OBJ-SPAN {: off1 len1 :}
   CFG-BUF off1 + len1 k2 k2u DOC-VALUE-SPAN? {: off2 len2 found :}
   found if off1 off2 + len2 v vu SPLICE-CFG exit then
   CFG-BUF off1 + len1 DOC-CLOSE {: at members :}
   off1 at + members k2 k2u v vu CFG-ADD ;

\ a decoded string as a JSON string literal, in the writer buffer
: LITERAL$ ( ^u8 n -- ^u8 n ) {: a u :}
   JSON-OPEN a u JSON:WRITE-STRING JSON:WRITTEN$ ;

: NUMBER$ ( n -- ^u8 n )
   SB-RESET FMT:SB-INT SB$ ;

\ a refresh splices a copy of the login, which replaces it only when whole
: SPLICE-BEGIN ( -- ) PROBE-DOC$ CFG-BUF CFG-U BUF-CAP SPAN! ;

: SPLICE-END ( -- )
   CFG$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   SDOC$ PROBE-DOC! ;

\ ---- Anthropic -----------------------------------------------------------------------
\ The usage flags ask for both reset blocks, as Claude Code does. The usage
\ endpoint offers limit resets only to Claude Code's own User-Agent, so the
\ usage call carries it, with the CLI version the check was made against.
: CLAUDE-USAGE-URL$ ( -- ^u8 n ) s" https://api.anthropic.com/api/oauth/usage?cedar_ember=1&at_wall=1" ;
: CLAUDE-TOKEN-URL$ ( -- ^u8 n ) s" https://platform.claude.com/v1/oauth/token" ;
: CLAUDE-PROFILE-URL$ ( -- ^u8 n ) s" https://api.anthropic.com/api/oauth/profile" ;
: CLAUDE-CLIENT-ID$ ( -- ^u8 n ) s" 9d1c250a-e61b-44d9-88ed-5944d1962f5e" ;
: CLAUDE-UA$ ( -- ^u8 n ) s" claude-cli/2.1.282 (external, cli)" ;
: CREDS-KEY$ ( -- ^u8 n ) s" claudeAiOauth" ;

\ the answer's strings; each read resets it once what it held was recorded
TYPED-VARIABLE SCAN-TEXT ^VEC:vector<u8>

: SCAN-RESET ( -- ) SCAN-TEXT TEXTS-RESET ;
: SCAN$ ( n n -- ^u8 n ) {: off u :} SCAN-TEXT @ off u TEXTS$ ;
: SCAN-C ( n -- ) SCAN-TEXT @ VEC:PUSH c! ;

: BUCKET-PCT ( JSON:reader -- JSON:reader n )
   JSON:READ-TOKEN NUMBER-TOKEN? 0= if -1 exit then
   JSON:READ-SPAN$ USED-PERCENT ;

: BUCKET-RESET ( JSON:reader -- JSON:reader n n )
   JSON:READ-TOKEN JSON:T-STR <> if 0 0 exit then
   SCAN-TEXT @ TEXTS-READ ;

\ one bucket object {utilization, resets_at} at key; whole percent, and the
\ reset text's offset and length in SCAN-TEXT
: CLAUDE-BUCKET ( ^u8 n ^u8 n -- n n n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JSON:READ-CLOSE -1 0 0 exit then
   s" utilization" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE -1 0 0 exit then
   BUCKET-PCT {: h :}
   JSON:READ-CLOSE
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT drop
   s" resets_at" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE h 0 0 exit then
   BUCKET-RESET {: r ru :}
   JSON:READ-CLOSE
   h r ru ;

\ ---- model-scoped windows -------------------------------------------------------
\ the payload's `limits` list also carries per-model windows such as Fable's
\ weekly allowance: {kind: weekly_scoped, scope: {model: {display_name}}}
variable SC-NAME-AT    variable SC-NAME-U
variable SC-RESET-AT   variable SC-RESET-U
TYPED-VARIABLE SC-WIN-A ^u8   variable SC-WIN-U   \ the window word the kind names
variable SC-PCT

: SC-ENTRY-RESET ( -- )
   SCAN-RESET
   0 SC-NAME-U ! 0 SC-RESET-U ! s" " SC-WIN-U ! SC-WIN-A ! -1 SC-PCT ! ;

\ a string member's value onto SCAN-TEXT, named in atp and up; else skipped
: SC-STR ( JSON:reader ^n ^n -- JSON:reader ) {: atp up :}
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-SKIP-VALUE exit then
   SCAN-TEXT @ TEXTS-READ up ! atp ! ;

\ on the model object's opening brace: its display name
: SC-MODEL ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
      s" display_name" JSON:READ-STR-EQ? {: named :}
      JSON:READ-NEXT drop
      named if SC-NAME-AT SC-NAME-U SC-STR else JSON:READ-SKIP-VALUE then
   repeat ;

\ on the scope value: an object with a model, or null
: SC-SCOPE ( JSON:reader -- JSON:reader )
   JSON:READ-TOKEN JSON:T-OBJ <> if JSON:READ-SKIP-VALUE exit then
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
      s" model" JSON:READ-STR-EQ? {: modelkey :}
      JSON:READ-NEXT drop
      JSON:READ-TOKEN JSON:T-OBJ = modelkey and if SC-MODEL else JSON:READ-SKIP-VALUE then
   repeat ;

: SC-PERCENT ( JSON:reader -- JSON:reader )
   BUCKET-PCT SC-PCT ! JSON:READ-SKIP-VALUE ;

\ the window word a kind names
: SC-WINDOW$ ( ^u8 n -- ^u8 n ) {: a u :}
   a u s" weekly" STARTS-WITH? if s" Weekly" exit then
   a u s" five_hour" STARTS-WITH? if s" Session" exit then
   a u s" session" STARTS-WITH? if s" Session" exit then
   s" " ;

\ on the kind's value: the window word it names; else skipped
: SC-WINDOW-READ ( JSON:reader -- JSON:reader )
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-SKIP-VALUE exit then
   SCAN-TEXT @ TEXTS-READ SCAN$ SC-WINDOW$ SC-WIN-U ! SC-WIN-A ! ;

\ on a limits entry's key: the member it names, read
: SC-MEMBER ( JSON:reader -- JSON:reader )
   s" kind" JSON:READ-STR-EQ? {: kind :}
   s" resets_at" JSON:READ-STR-EQ? {: reset :}
   s" percent" JSON:READ-STR-EQ? {: pct :}
   s" scope" JSON:READ-STR-EQ? {: scope :}
   JSON:READ-NEXT drop
   kind if SC-WINDOW-READ exit then
   reset if SC-RESET-AT SC-RESET-U SC-STR exit then
   pct if SC-PERCENT exit then
   scope if SC-SCOPE exit then
   JSON:READ-SKIP-VALUE ;

\ a window with a model becomes "<Model> Weekly"; unscoped ones are the
\ session and weekly buckets already taken
: SC-ENTRY+ ( -- )
   SC-NAME-U @ 0= if exit then
   SC-PCT @ 0 < if exit then
   SC-NAME-AT @ SC-NAME-U @ SCAN$ SCAN-TEXT @ TEXTS-PUT drop {: lo :}
   SC-WIN-A @ SC-WIN-U @ dup 0 > if $20 SCAN-C SCAN-TEXT @ TEXTS-PUT 2drop else 2drop then
   lo SCAN-TEXT @ TEXTS-END lo - SCAN$ SC-PCT @ SC-RESET-AT @ SC-RESET-U @ SCAN$ DB-LIMIT+ ;

: SC-OBJECT ( JSON:reader -- JSON:reader )
   SC-ENTRY-RESET
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
      SC-MEMBER
   repeat
   SC-ENTRY+ ;

: SC-ARRAY ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-ARR-END <> while
      JSON:READ-TOKEN JSON:T-OBJ = if SC-OBJECT else JSON:READ-SKIP-VALUE then
   repeat ;

: CLAUDE-SCOPED ( ^u8 n -- ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   s" limits" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE exit then
   JSON:READ-TOKEN JSON:T-ARR <> if JSON:READ-CLOSE exit then
   SC-ARRAY
   JSON:READ-CLOSE ;

\ Session, then Weekly (seven_day_oauth_apps, else seven_day), then every
\ model-scoped window; a window without a reading is left out
: CLAUDE-LIMITS ( ^u8 n -- ) {: d du :}
   SCAN-RESET
   d du s" five_hour" CLAUDE-BUCKET {: sh so su :}
   d du s" seven_day_oauth_apps" CLAUDE-BUCKET {: wh0 r0 r0u :}
   wh0 0 < if d du s" seven_day" CLAUDE-BUCKET else wh0 r0 r0u then {: wh wo wu :}
   sh 0 >= if SESSION-LABEL$ sh so su SCAN$ DB-LIMIT+ then
   wh 0 >= if WEEKLY-LABEL$ wh wo wu SCAN$ DB-LIMIT+ then
   d du CLAUDE-SCOPED ;

\ ---- instants --------------------------------------------------------------------
: EPOCH>RESET$ ( n -- ^u8 n )
   dup 0 <= if drop DATE-BUF 0 exit then
   DATE-BUF DATE:TIME-LEN DATE:FORMAT-EPOCH-UTC ;

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
   c [char] T =  c [char] t = or  c STR-SPACE = or ;

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

\ the epoch seconds of an RFC 3339 date-time, -1 when malformed or before 1970
: RFC3339>EPOCH ( ^u8 n -- n )
   {: a u :}
   u RFC-CLOCK-END <= if -1 exit then
   a RFC-LOCAL MATCH option
     none OF -1 ENDOF
     some OF a u RFC-UTC ENDOF
   ;MATCH ;

\ records epoch seconds n as the reset expiry; n below 0 records nothing
: EXPIRY! ( n -- )
   dup 0 < if drop exit then
   EPOCH>RESET$ DB-RESETS-EXPIRY! ;

\ ---- the reset offer -------------------------------------------------------------
\ cedar_ember banks grants: the one named next_grant_id, its resets_left and
\ its ends_at; else juniper_tide offers one reset a week while one is available
variable GRANT-NEXT-AT   variable GRANT-NEXT-U   \ in SCAN-TEXT
variable GRANT-SEEN                 \ bool: the grant named next was found
variable GRANT-IS                   \ bool: the grant in hand is the one named next
variable GRANT-HAS-LEFT             \ bool: the grant in hand says how many resets are left
variable GRANT-LEFT
\ the grant in hand's ends_at, in SCAN-TEXT; empty when absent, null or not
\ a string
variable GRANT-ENDS-AT   variable GRANT-ENDS-U

: GRANT-NEXT$ ( -- ^u8 n ) GRANT-NEXT-AT @ GRANT-NEXT-U @ SCAN$ ;
: GRANT-ENDS$ ( -- ^u8 n ) GRANT-ENDS-AT @ GRANT-ENDS-U @ SCAN$ ;

\ cedar_ember's next_grant_id onto SCAN-TEXT; false when absent, null or not a string
: GRANT-NEXT-READ ( ^u8 n -- bool ) {: d du :}
   SCAN-RESET
   d du OPEN-DOC ENTER-OBJECT
   s" cedar_ember" KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   s" next_grant_id" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE false exit then
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-CLOSE false exit then
   SCAN-TEXT @ TEXTS-READ GRANT-NEXT-U ! GRANT-NEXT-AT !
   JSON:READ-CLOSE true ;

: GRANT-MEMBER ( JSON:reader -- JSON:reader )
   JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
   s" id" JSON:READ-STR-EQ? {: idk :}
   s" resets_left" JSON:READ-STR-EQ? {: leftk :}
   s" ends_at" JSON:READ-STR-EQ? {: endk :}
   JSON:READ-NEXT drop
   JSON:READ-TOKEN {: t :}
   idk t JSON:T-STR = and if GRANT-NEXT$ JSON:READ-STR-EQ? GRANT-IS ! exit then
   leftk t NUMBER-TOKEN? and if WHOLE GRANT-HAS-LEFT ! GRANT-LEFT ! exit then
   endk if GRANT-ENDS-AT GRANT-ENDS-U SC-STR exit then
   JSON:READ-SKIP-VALUE ;

: GRANT-OBJECT ( JSON:reader -- JSON:reader )
   false GRANT-IS ! false GRANT-HAS-LEFT !
   0 GRANT-ENDS-AT ! 0 GRANT-ENDS-U !
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while GRANT-MEMBER repeat
   GRANT-IS @ GRANT-SEEN ! ;

\ the first grant object with the id named next decides
: GRANT-ARRAY ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-ARR-END <> while
      JSON:READ-TOKEN JSON:T-OBJ = GRANT-SEEN @ 0= and if GRANT-OBJECT else JSON:READ-SKIP-VALUE then
   repeat ;

: GRANTS-SCAN ( ^u8 n -- ) {: d du :}
   false GRANT-SEEN ! false GRANT-HAS-LEFT !
   d du OPEN-DOC ENTER-OBJECT
   s" cedar_ember" KEY-OBJECT drop
   s" grants" JSON:READ-FIND-KEY if
      JSON:READ-TOKEN JSON:T-ARR = if GRANT-ARRAY then
   then
   JSON:READ-CLOSE ;

: BANKED? ( ^u8 n -- bool ) {: d du :}
   d du s" cedar_ember" s" eligible" TRUE2? 0= if false exit then
   d du GRANT-NEXT-READ 0= if false exit then
   d du GRANTS-SCAN
   GRANT-SEEN @ 0<> GRANT-HAS-LEFT @ 0<> and ;

: CLAUDE-RESETS ( ^u8 n -- ) {: d du :}
   d du BANKED? if
      GRANT-LEFT @ s" cedar_ember" GRANT-NEXT$ DB-RESETS!
      GRANT-ENDS$ RFC3339>EPOCH EXPIRY! exit
   then
   d du s" juniper_tide" s" eligible" TRUE2? 0= if exit then
   d du s" juniper_tide" s" available" TRUE2? if 1 else 0 then
   s" juniper_tide" s" " DB-RESETS! ;

\ ---- Anthropic's refusals -----------------------------------------------------------
\ A token endpoint's error answer as Claude Code reads it: error when it is a
\ string, else error.type; error_description; error_uri.
create REF-CODE TEXT-CAP allot   variable REF-CODE-U
create REF-DESC TEXT-CAP allot   variable REF-DESC-U
create REF-URI TEXT-CAP allot    variable REF-URI-U    \ -1 when the answer names none

: REF-CODE$ ( -- ^u8 n ) REF-CODE REF-CODE-U @ ;
: REF-DESC$ ( -- ^u8 n ) REF-DESC REF-DESC-U @ ;

: REF-CODE-READ ( ^u8 n -- ) {: b bu :}
   b bu s" error" REF-CODE TEXT-CAP DOC-STR1 dup 0 >= if REF-CODE-U ! exit then
   drop b bu s" error" s" type" REF-CODE TEXT-CAP DOC-STR2 0 max REF-CODE-U ! ;

: REFUSAL-READ ( ^u8 n -- ) {: b bu :}
   0 REF-CODE-U ! 0 REF-DESC-U ! -1 REF-URI-U !
   b bu FIELDS? 0= if exit then
   b bu REF-CODE-READ
   b bu s" error_description" REF-DESC TEXT-CAP DOC-STR1 0 max REF-DESC-U !
   b bu s" error_uri" REF-URI TEXT-CAP DOC-STR1 REF-URI-U ! ;

\ Anthropic's on-hold refusal, as Claude Code 2.1.285 reads it
: ON-HOLD? ( n -- bool ) {: code :}
   code REFUSED-STATUS? code 403 = or
   REF-CODE$ s" invalid_grant" STR= REF-CODE$ s" access_denied" STR= or and
   REF-DESC$ s" account_on_hold" STR= and ;

create DETAIL-RAW TEXT-CAP 2 * 32 + allot   variable DETAIL-RAW-U

: RAW+ ( ^u8 n -- ) {: a u :}
   a DETAIL-RAW DETAIL-RAW-U @ + u BYTE-COPY
   u DETAIL-RAW-U +! ;

\ "<status> <code>: <description>" on one line, absent parts left out
: DETAIL$ ( n -- ^u8 n ) {: code :}
   0 DETAIL-RAW-U !
   code FMT:INT$ RAW+
   REF-CODE-U @ 0 > if s"  " RAW+ REF-CODE$ RAW+ then
   REF-DESC-U @ 0 > if s" : " RAW+ REF-DESC$ RAW+ then
   DETAIL-RAW DETAIL-RAW-U @ ONE-LINE ;

\ An appeal page is trusted when it is a plain https page on Anthropic's own
\ hosts: no user, port or fragment, no trailing . or ?, at most DETAIL-MAX
\ characters; else Claude Code's fallback page.
create HOST-BUF DETAIL-MAX allot    variable HOST-U

: RESTRICTED$ ( -- ^u8 n ) s" https://claude.ai/restricted" ;

: LOWER? ( n -- bool ) dup $61 >= swap $7A <= and ;
: UPPER? ( n -- bool ) dup $41 >= swap $5A <= and ;

: URI-CHAR? ( n -- bool ) {: c :}
   c LOWER? c UPPER? or c DIGIT? or if true exit then
   c $2F = c $2E = or c $5F = or c $7E = or c $25 = or
   c $2D = or c $3F = or c $3D = or c $26 = or ;

: HOST-CHAR? ( n -- bool ) {: c :}
   c LOWER? c DIGIT? or c $2E = or c $2D = or ;

: ALL? ( ^u8 n [ n -- bool ] -- bool ) {: a u ok :}
   u 0 ?do a i + c@ ok execute 0= if false unloop exit then loop
   true ;

: HOST-END? ( n -- bool ) dup $2F = swap $3F = or ;

: LOWERED ( n -- n ) dup UPPER? if $20 + then ;

\ the host of the URI after its scheme, lowercased into HOST-BUF
: HOST! ( ^u8 n -- ) {: a u :}
   0 HOST-U !
   u 0 ?do
      a i + c@ HOST-END? if unloop exit then
      a i + c@ LOWERED HOST-BUF HOST-U @ + c!
      1 HOST-U +!
   loop ;

\ the host is d or a subdomain of it
: DOMAIN? ( ^u8 n ^u8 n -- bool ) {: h hu d du :}
   h hu d du STR= if true exit then
   hu du 1+ < if false exit then
   h hu du - + du d du STR= 0= if false exit then
   h hu du - 1- + c@ $2E = ;

: HOST-OURS? ( -- bool )
   HOST-U @ 0= if false exit then
   HOST-BUF HOST-U @ [: HOST-CHAR? ;] ALL? 0= if false exit then
   HOST-BUF HOST-U @ s" claude.ai" DOMAIN? if true exit then
   HOST-BUF HOST-U @ s" anthropic.com" DOMAIN? ;

: APPEAL-OK? ( ^u8 n -- bool ) {: a u :}
   u DETAIL-MAX > if false exit then
   a u SCHEME$ STARTS-WITH? 0= if false exit then
   a u + 1- c@ dup $2E = swap $3F = or if false exit then
   SCHEME$ nip {: s :}
   a s + u s - [: URI-CHAR? ;] ALL? 0= if false exit then
   a s + u s - HOST!
   HOST-OURS? ;

: APPEAL$ ( -- ^u8 n )
   REF-URI-U @ 0 < if RESTRICTED$ exit then
   REF-URI REF-URI-U @ APPEAL-OK? 0= if RESTRICTED$ exit then
   REF-URI REF-URI-U @ ;

\ The usage endpoint's 403 for an organization whose plan does not allow
\ Claude Code's OAuth: a lapsed subscription answers so, while the token
\ document still claims the old plan.
: NO-PLAN? ( ^u8 n -- bool ) {: b bu :}
   b bu FIELDS? 0= if false exit then
   b bu OPEN-DOC ENTER-OBJECT
   s" error" KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   s" details" KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   s" error_code" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE false exit then
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-CLOSE false exit then
   s" oauth_not_allowed_for_organization" JSON:READ-STR-EQ? swap JSON:READ-CLOSE ;

\ an API error answer's error.message on one line; empty when absent
create MSG-BUF DETAIL-MAX 4 * allot   variable MSG-U

: MESSAGE! ( ^u8 n -- ) {: b bu :}
   0 MSG-U !
   b bu FIELDS? 0= if exit then
   b bu s" error" s" message" DETAIL-RAW TEXT-CAP DOC-STR2 {: mu :}
   mu 0 <= if exit then
   DETAIL-RAW mu ONE-LINE MSG-BUF MSG-U DETAIL-MAX 4 * SPAN! ;

\ Anthropic answers a free organization's usage check with the 429 of a
\ rate limit; its profile tells the two apart: free only when it names the
\ organization and a type Claude Code maps to no plan
: PAID? ( ^u8 n -- bool ) {: a u :}
   a u s" claude_max" STR= a u s" claude_pro" STR= or
   a u s" claude_team" STR= or a u s" claude_enterprise" STR= or ;

: FREE-PLAN? ( ^u8 n -- bool ) {: b bu :}
   b bu FIELDS? 0= if false exit then
   b bu s" organization" KEY-OBJ? 0= if false exit then
   b bu s" organization" s" organization_type" DETAIL-RAW TEXT-CAP DOC-STR2 0 max
   DETAIL-RAW swap PAID? 0= ;

\ ---- Anthropic's exchange ------------------------------------------------------------
\ A saved login's expired token is refreshed first; the live login's belongs
\ to Claude Code, which refreshes it on its next run, so it is reported, not
\ sent. Only the token endpoint's 400 or 401 means the login is gone.
ENUM claude-step fresh renewing asking profiling recorded ;ENUM
ENUM fresh-input current stale-live stale-saved ;ENUM
ENUM renew-input renewed no-grant unreachable unusable on-hold refused answered ;ENUM
ENUM ask-input no-token unreachable fine unreadable rejected no-plan throttled other ;ENUM
ENUM profile-input free limited ;ENUM

\ the claudeAiOauth token k in VAL-BUF; its length, -1 when absent or "", as
\ in a document whose tokens were blanked
: CLAUDE-TOKEN ( ^u8 n -- n ) {: k ku :}
   PROBE-DOC$ FIELDS? 0= if -1 exit then
   PROBE-DOC$ CREDS-KEY$ k ku VAL-BUF BUF-CAP DOC-STR2 dup 0 > if dup VAL-U ! exit then
   drop -1 ;

\ expiresAt in epoch milliseconds; -1 when absent
: CLAUDE-EXPIRES ( -- n )
   PROBE-DOC$ FIELDS? 0= if -1 exit then
   PROBE-DOC$ CREDS-KEY$ s" expiresAt" DOC-INT2 0= if drop -1 then ;

\ a token this close to expiring, a minute, counts as expired
: CLAUDE-FRESH ( n -- fresh-input ) drop
   CLAUDE-EXPIRES {: ms :}
   ms 0 <= if construct fresh-input current exit then
   ms 1000 / PROBE-AT @ 60 + >= if construct fresh-input current exit then
   PROBE-LIVE @ if construct fresh-input stale-live exit then
   construct fresh-input stale-saved ;

: CLAUDE-GRANT-BODY ( -- ^u8 n )
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" grant_type" s" refresh_token" JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" client_id" CLAUDE-CLIENT-ID$ JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END JSON:WRITTEN$ ;

\ epoch milliseconds secs after the probe began, at claudeAiOauth.k, when
\ the answer gave secs
: EXPIRY-SET ( n bool ^u8 n -- ) {: secs given k ku :}
   given 0= secs 0 <= or if exit then
   CREDS-KEY$ k ku PROBE-AT @ secs + 1000 * NUMBER$ CFG-SET2 ;

\ the answer b's tokens spliced in; its access token is in VAL-BUF
: CLAUDE-SPLICE ( ^u8 n -- ) {: b bu :}
   SPLICE-BEGIN
   CREDS-KEY$ s" accessToken" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   b bu s" refresh_token" VAL-BUF BUF-CAP DOC-STR1 dup 0 >= if
      VAL-U ! CREDS-KEY$ s" refreshToken" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   else drop then
   b bu s" expires_in" DOC-INT1 s" expiresAt" EXPIRY-SET
   b bu s" refresh_token_expires_in" DOC-INT1 s" refreshTokenExpiresAt" EXPIRY-SET
   SPLICE-END ;

: CLAUDE-RENEWED ( -- renew-input )
   ANSWER$ {: b bu :}
   b bu FIELDS? 0= if construct renew-input unusable exit then
   b bu s" access_token" VAL-BUF BUF-CAP DOC-STR1 dup 0 < if drop construct renew-input unusable exit then
   VAL-U !
   b bu CLAUDE-SPLICE
   construct renew-input renewed ;

: CLAUDE-DENIED ( n -- renew-input ) {: code :}
   ANSWER$ REFUSAL-READ
   code ON-HOLD? if construct renew-input on-hold exit then
   code REFUSED-STATUS? if construct renew-input refused exit then
   construct renew-input answered ;

: CLAUDE-RENEW ( n -- renew-input ) drop
   s" refreshToken" CLAUDE-TOKEN 0 < if construct renew-input no-grant exit then
   CLAUDE-GRANT-BODY CLAUDE-TOKEN-URL$ TOKEN-POST {: code :}
   code 0 < if construct renew-input unreachable exit then
   code 200 = if CLAUDE-RENEWED exit then
   code CLAUDE-DENIED ;

: CLAUDE-GET ( -- n )
   CLAUDE-UA$ REQUEST
   VAL-BUF VAL-U @ BEARER
   s" anthropic-beta" s" oauth-2025-04-20" HDR
   CLAUDE-USAGE-URL$ SEND dup HTTP-CODE ! ;

: CLAUDE-ANSWERED ( -- ask-input )
   ANSWER$ FIELDS? if construct ask-input fine exit then
   construct ask-input unreadable ;

: CLAUDE-ASK ( n -- ask-input ) drop
   s" accessToken" CLAUDE-TOKEN 0 < if construct ask-input no-token exit then
   CLAUDE-GET {: code :}
   code 0 < if construct ask-input unreachable exit then
   code 200 = if CLAUDE-ANSWERED exit then
   code 401 = if construct ask-input rejected exit then
   code 403 = ANSWER$ NO-PLAN? and if construct ask-input no-plan exit then
   code 429 = if construct ask-input throttled exit then
   construct ask-input other ;

\ the profile is read with the token CLAUDE-ASK left in VAL-BUF
: CLAUDE-PROFILE ( n -- profile-input ) drop
   KIBA-UA$ REQUEST
   VAL-BUF VAL-U @ BEARER
   CLAUDE-PROFILE-URL$ SEND 200 <> if construct profile-input limited exit then
   ANSWER$ FREE-PLAN? if construct profile-input free exit then
   construct profile-input limited ;

: CLAUDE-LIVE-STALE$ ( -- ^u8 n )
   s" access token expired; Claude Code refreshes it on its next run" ;

: CLAUDE-NO-GRANT$ ( -- ^u8 n )
   s" access token expired and no refresh token is saved; log in again" ;

: CLAUDE-TOKEN-NOTE$ ( -- ^u8 n )
   s" Anthropic's token endpoint" HTTP-CODE @ HTTP-NOTE ;

: CLAUDE-ON-HOLD$ ( -- ^u8 n )
   APPEAL$ {: a u :}
   SB-RESET s" account on hold and cannot use Claude Code; view details or appeal at " SB-APPEND
   a u SB-APPEND SB$ ;

: CLAUDE-REFUSED$ ( -- ^u8 n )
   HTTP-CODE @ DETAIL$ {: a u :}
   SB-RESET s" access token expired and the refresh was refused (" SB-APPEND
   a u SB-APPEND s" ); log in again" SB-APPEND SB$ ;

: CLAUDE-REJECTED$ ( -- ^u8 n ) s" login rejected by Anthropic; log in again" ;

: CLAUDE-LIVE-STALE ( n -- ) drop
   construct usage-state expired CLAUDE-LIVE-STALE$ SAY ;

: CLAUDE-NO-GRANT ( n -- ) drop
   construct usage-state missing CLAUDE-NO-GRANT$ SAY ;

: CLAUDE-TOKEN-ANSWER ( n -- ) drop
   construct usage-state error CLAUDE-TOKEN-NOTE$ SAY ;

: CLAUDE-ON-HOLD ( n -- ) drop
   construct usage-state error CLAUDE-ON-HOLD$ SAY ;

: CLAUDE-REFUSED ( n -- ) drop
   construct usage-state expired CLAUDE-REFUSED$ SAY ;

: CLAUDE-NO-TOKEN ( n -- ) drop
   construct usage-state missing s" no access token saved; log in again" SAY ;

: CLAUDE-USAGE-ANSWER ( n -- ) drop
   construct usage-state error s" Anthropic's usage endpoint" HTTP-CODE @ HTTP-NOTE SAY ;

: CLAUDE-FINE ( n -- ) drop
   construct usage-state ok s" " SAY
   ANSWER$ {: b bu :}
   b bu CLAUDE-LIMITS
   b bu CLAUDE-RESETS ;

: CLAUDE-UNREADABLE ( n -- ) drop
   construct usage-state error s" Anthropic's usage endpoint" UNREADABLE-NOTE SAY ;

: CLAUDE-REJECTED ( n -- ) drop
   construct usage-state expired CLAUDE-REJECTED$ SAY ;

: CLAUDE-NO-PLAN ( n -- ) drop
   construct usage-state unsubscribed
   s" no plan for Claude Code: Anthropic does not allow this organization's OAuth login" SAY ;

\ Anthropic's own words, when its answer gives them, say which limit hit
: CLAUDE-THROTTLE-READ ( n -- ) drop ANSWER$ MESSAGE! ;

: CLAUDE-FREE ( n -- ) drop
   construct usage-state free s" free plan: Anthropic's profile shows no paid plan for this organization" SAY ;

: CLAUDE-THROTTLED ( n -- ) drop
   MSG-U @ 0= if
      construct usage-state throttled s" Anthropic is rate limiting usage checks; try again later" SAY exit
   then
   SB-RESET s" Anthropic is rate limiting usage checks (" SB-APPEND
   MSG-BUF MSG-U @ SB-APPEND s" ); try again later" SB-APPEND
   construct usage-state throttled SB$ SAY ;

FSM:DEFINE CLAUDE-EXCHANGE ( n ) claude-step fresh-input
   IN fresh CLAUDE-FRESH
      current      -                    >asking
      stale-live   CLAUDE-LIVE-STALE    >recorded
      stale-saved  -                    >renewing
   IN renewing CLAUDE-RENEW ( renew-input )
      renewed      -                    >asking
      no-grant     CLAUDE-NO-GRANT      >recorded
      unreachable  CLAUDE-TOKEN-ANSWER  >recorded
      unusable     CLAUDE-TOKEN-ANSWER  >recorded
      on-hold      CLAUDE-ON-HOLD       >recorded
      refused      CLAUDE-REFUSED       >recorded
      answered     CLAUDE-TOKEN-ANSWER  >recorded
   IN asking CLAUDE-ASK ( ask-input )
      no-token     CLAUDE-NO-TOKEN      >recorded
      unreachable  CLAUDE-USAGE-ANSWER  >recorded
      fine         CLAUDE-FINE          >recorded
      unreadable   CLAUDE-UNREADABLE    >recorded
      rejected     CLAUDE-REJECTED      >recorded
      no-plan      CLAUDE-NO-PLAN       >recorded
      throttled    CLAUDE-THROTTLE-READ >profiling
      other        CLAUDE-USAGE-ANSWER  >recorded
   IN profiling CLAUDE-PROFILE ( profile-input )
      free         CLAUDE-FREE          >recorded
      limited      CLAUDE-THROTTLED     >recorded
   FINAL recorded -
;DEFINE

\ ---- OpenAI ------------------------------------------------------------------------------
: CODEX-USAGE-URL$ ( -- ^u8 n ) s" https://chatgpt.com/backend-api/wham/usage" ;
: CODEX-CREDITS-URL$ ( -- ^u8 n )
   s" https://chatgpt.com/backend-api/wham/rate-limit-reset-credits" ;
: CODEX-TOKEN-URL$ ( -- ^u8 n ) s" https://auth.openai.com/oauth/token" ;
: CODEX-CLIENT-ID$ ( -- ^u8 n ) s" app_EMoamEEZ73f0CkXaXp7hrann" ;
: TOKENS-KEY$ ( -- ^u8 n ) s" tokens" ;

\ the integer member f of the window at k, which CODEX-WINDOW found; 0 when
\ absent or not an integer
: WINDOW-INT ( ^u8 n ^u8 n ^u8 n -- n ) {: d du k ku f fu :}
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT drop
   k ku KEY-OBJECT drop
   f fu KEY-WHOLE OR-ZERO swap JSON:READ-CLOSE ;

\ the window at key inside rate_limit: used percent, window seconds, reset epoch
: CODEX-WINDOW ( ^u8 n ^u8 n -- n n n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT 0= if JSON:READ-CLOSE -1 0 0 exit then
   k ku KEY-OBJECT 0= if JSON:READ-CLOSE -1 0 0 exit then
   s" used_percent" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE -1 0 0 exit then
   BUCKET-PCT {: h :}
   JSON:READ-CLOSE
   d du k ku s" limit_window_seconds" WINDOW-INT {: secs :}
   d du k ku s" reset_at" WINDOW-INT {: at :}
   h secs at ;

\ the longest window, six hours, still called a session
: WINDOW-LABEL$ ( n -- ^u8 n )
   21600 <= if SESSION-LABEL$ exit then
   WEEKLY-LABEL$ ;

: CODEX-WINDOW+ ( ^u8 n ^u8 n -- ) {: d du k ku :}
   d du k ku CODEX-WINDOW {: h secs at :}
   h 0 < if exit then
   secs WINDOW-LABEL$ h at EPOCH>RESET$ DB-LIMIT+ ;

: CODEX-LIMITS ( ^u8 n -- ) {: d du :}
   d du s" primary_window" CODEX-WINDOW+
   d du s" secondary_window" CODEX-WINDOW+ ;

\ the limit-reset credits the answer reports, when it says anything of them
: CODEX-RESETS ( ^u8 n -- ) {: d du :}
   d du s" rate_limit_reset_credits" s" available_count" DOC-INT2 0= if drop exit then
   s" " s" " DB-RESETS! ;

\ ---- the reset credits' expiry -----------------------------------------------------
\ the credit list names each credit's status and expires_at; an available
\ credit's expires_at, read as an instant, counts
variable CREDIT-OPEN     \ bool: the credit in hand's status is available
\ the credit in hand's expires_at in epoch seconds; -1 when absent, null,
\ not a string or malformed
variable CREDIT-ENDS
variable CREDITS-FIRST   \ the earliest counted end so far; -1 for none

\ expires_at's instant in epoch seconds; -1 when it is not one
: CREDIT-END ( JSON:reader -- JSON:reader n )
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-SKIP-VALUE -1 exit then
   SCAN-TEXT @ TEXTS-READ SCAN$ RFC3339>EPOCH ;

: CREDIT-MEMBER ( JSON:reader -- JSON:reader )
   JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
   s" status" JSON:READ-STR-EQ? {: statk :}
   s" expires_at" JSON:READ-STR-EQ? {: endk :}
   JSON:READ-NEXT drop
   JSON:READ-TOKEN JSON:T-STR = statk and if
      s" available" JSON:READ-STR-EQ? CREDIT-OPEN ! exit
   then
   endk if CREDIT-END CREDIT-ENDS ! exit then
   JSON:READ-SKIP-VALUE ;

: CREDIT-OBJECT ( JSON:reader -- JSON:reader )
   false CREDIT-OPEN ! -1 CREDIT-ENDS !
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while CREDIT-MEMBER repeat
   CREDIT-ENDS @ CREDITS-FIRST @ {: e f :}
   CREDIT-OPEN @ 0= e 0 < or if exit then
   f 0 < e f < or if e CREDITS-FIRST ! then ;

: CREDIT-ARRAY ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-ARR-END <> while
      JSON:READ-TOKEN JSON:T-OBJ = if CREDIT-OBJECT else JSON:READ-SKIP-VALUE then
   repeat ;

\ the earliest available credit's end in epoch seconds; -1 for none
: CODEX-EARLIEST ( ^u8 n -- n )
   {: d du :}
   SCAN-RESET -1 CREDITS-FIRST !
   d du OPEN-DOC ENTER-OBJECT
   s" credits" JSON:READ-FIND-KEY if
      JSON:READ-TOKEN JSON:T-ARR = if CREDIT-ARRAY then
   then
   JSON:READ-CLOSE CREDITS-FIRST @ ;

\ the account's current plan, which the login's id_token only knew at sign-in
: CODEX-PLAN ( ^u8 n -- ) {: d du :}
   d du s" plan_type" PLAN-NAMED PLAN-CAP DOC-STR1 PLAN-NAMED-U ! ;

\ ---- OpenAI's exchange ------------------------------------------------------------------
\ A 401 on a saved login earns one refresh, then one more usage call; the
\ live login's tokens belong to the running codex and are never refreshed.
\ A refused refresh after a 401 that called the token revoked means a
\ sign-out revoked the login.
ENUM codex-step keyed asking renewing renewing-revoked retrying recorded ;ENUM
ENUM key-input api-key tokens ;ENUM
ENUM first-input no-token unreachable fine unreadable rejected-live rejected-saved rejected-revoked throttled other ;ENUM
ENUM codex-renew-input renewed no-grant unreachable unusable refused answered ;ENUM
ENUM retry-input no-token unreachable fine unreadable rejected throttled other ;ENUM

\ the tokens member k in VAL-BUF; its length, -1 when absent
: CODEX-TOKEN ( ^u8 n -- n ) {: k ku :}
   PROBE-DOC$ FIELDS? 0= if -1 exit then
   PROBE-DOC$ TOKENS-KEY$ k ku VAL-BUF BUF-CAP DOC-STR2 dup 0 >= if dup VAL-U ! then ;

\ an API-key login without an id_token has no usage windows
: CODEX-KEYED ( n -- key-input ) drop
   PROBE-DOC$ FIELDS? 0= if construct key-input tokens exit then
   PROBE-DOC$ CODEX-API-KEY? 0= if construct key-input tokens exit then
   PROBE-DOC$ TOKENS-KEY$ s" id_token" KIND2 JSON:T-STR = if construct key-input tokens exit then
   construct key-input api-key ;

\ every ChatGPT call carries codex-cli's User-Agent, the bearer in VAL-BUF
\ and the login's account id
: CODEX-REQUEST ( -- )
   PROBE-DOC$ TOKENS-KEY$ s" account_id" ACCT-ID-BUF BUF-CAP DOC-STR2 0 max ACCT-ID-U !
   s" codex-cli" REQUEST
   VAL-BUF VAL-U @ BEARER
   ACCT-ID-U @ 0 > if s" ChatGPT-Account-Id" ACCT-ID-BUF ACCT-ID-U @ HDR then ;

\ the usage call with the access token CODEX-TOKEN left in VAL-BUF
: CODEX-GET ( -- n ) CODEX-REQUEST CODEX-USAGE-URL$ SEND dup HTTP-CODE ! ;

\ the earliest available credit's expiry; a list that fails or reads wrong
\ records nothing and leaves the usage answer's state and note
: CODEX-CREDITS ( -- )
   CODEX-REQUEST CODEX-CREDITS-URL$ TRANSFER 200 <> if exit then
   ANSWER$ FIELDS? 0= if exit then
   ANSWER$ CODEX-EARLIEST EXPIRY! ;

: CODEX-ANSWERED? ( -- bool ) ANSWER$ FIELDS? ;

: CODEX-REJECTED-FIRST ( -- first-input )
   PROBE-LIVE @ if construct first-input rejected-live exit then
   ANSWER$ {: b bu :}
   b bu FIELDS? 0= if construct first-input rejected-saved exit then
   b bu s" error" s" code" s" token_revoked" STR2-IS? if construct first-input rejected-revoked exit then
   construct first-input rejected-saved ;

: CODEX-ANSWERED-FIRST ( -- first-input )
   CODEX-ANSWERED? if construct first-input fine exit then
   construct first-input unreadable ;

: CODEX-FIRST ( n -- first-input ) drop
   s" access_token" CODEX-TOKEN 0 < if construct first-input no-token exit then
   CODEX-GET {: code :}
   code 0 < if construct first-input unreachable exit then
   code 200 = if CODEX-ANSWERED-FIRST exit then
   code 401 = if CODEX-REJECTED-FIRST exit then
   code 429 = if construct first-input throttled exit then
   construct first-input other ;

: CODEX-GRANT-BODY ( -- ^u8 n )
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" client_id" CODEX-CLIENT-ID$ JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" grant_type" s" refresh_token" JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END JSON:WRITTEN$ ;

\ the answer b's tokens and the refresh time spliced in; its access token is
\ in VAL-BUF
: CODEX-SPLICE ( ^u8 n -- ) {: b bu :}
   SPLICE-BEGIN
   TOKENS-KEY$ s" access_token" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   b bu s" refresh_token" VAL-BUF BUF-CAP DOC-STR1 dup 0 >= if
      VAL-U ! TOKENS-KEY$ s" refresh_token" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   else drop then
   b bu s" id_token" TOK-BUF BUF-CAP DOC-STR1 dup 0 >= if
      TOK-U ! TOKENS-KEY$ s" id_token" TOK-BUF TOK-U @ LITERAL$ CFG-SET2
   else drop then
   s" last_refresh" PROBE-AT @ DATE-BUF DATE:TIME-LEN DATE:FORMAT-EPOCH-UTC LITERAL$ CFG-SET
   SPLICE-END ;

: CODEX-RENEWED ( -- codex-renew-input )
   ANSWER$ {: b bu :}
   b bu FIELDS? 0= if construct codex-renew-input unusable exit then
   b bu s" access_token" VAL-BUF BUF-CAP DOC-STR1 dup 0 < if drop construct codex-renew-input unusable exit then
   VAL-U !
   b bu CODEX-SPLICE
   construct codex-renew-input renewed ;

: CODEX-RENEW ( n -- codex-renew-input ) drop
   s" refresh_token" CODEX-TOKEN 0 < if construct codex-renew-input no-grant exit then
   CODEX-GRANT-BODY CODEX-TOKEN-URL$ TOKEN-POST {: code :}
   code 0 < if construct codex-renew-input unreachable exit then
   code 200 = if CODEX-RENEWED exit then
   code REFUSED-STATUS? if construct codex-renew-input refused exit then
   construct codex-renew-input answered ;

: CODEX-ANSWERED-AGAIN ( -- retry-input )
   CODEX-ANSWERED? if construct retry-input fine exit then
   construct retry-input unreadable ;

: CODEX-RETRY ( n -- retry-input ) drop
   s" access_token" CODEX-TOKEN 0 < if construct retry-input no-token exit then
   CODEX-GET {: code :}
   code 0 < if construct retry-input unreachable exit then
   code 200 = if CODEX-ANSWERED-AGAIN exit then
   code 401 = if construct retry-input rejected exit then
   code 429 = if construct retry-input throttled exit then
   construct retry-input other ;

: NO-ACCESS$ ( -- ^u8 n ) s" no access token saved" ;
: CODEX-LIVE-REJECTED$ ( -- ^u8 n ) s" access token rejected; run codex once to refresh it" ;
: CODEX-REJECTED$ ( -- ^u8 n ) s" login rejected by OpenAI; log in again" ;
: CODEX-TOKEN-NOTE$ ( -- ^u8 n ) s" OpenAI's token endpoint" HTTP-CODE @ HTTP-NOTE ;

: CODEX-NO-GRANT$ ( -- ^u8 n )
   s" access token rejected and no refresh token is saved; log in again" ;

: CODEX-REFUSED$ ( -- ^u8 n )
   s" access token rejected and the refresh was refused; log in again" ;

: CODEX-REVOKED$ ( -- ^u8 n )
   s" login revoked by a sign-out at chatgpt.com or in codex; log in again" ;

: CODEX-API-KEY-NOTE ( n -- ) drop
   construct usage-state unknown s" API-key login: no usage windows to read" SAY ;

: CODEX-NO-TOKEN ( n -- ) drop
   construct usage-state error NO-ACCESS$ SAY ;

: CODEX-USAGE-ANSWER ( n -- ) drop
   construct usage-state error s" OpenAI's usage endpoint" HTTP-CODE @ HTTP-NOTE SAY ;

: CODEX-FINE ( n -- ) drop
   construct usage-state ok s" " SAY
   ANSWER$ {: b bu :}
   b bu CODEX-LIMITS
   b bu CODEX-RESETS
   b bu CODEX-PLAN
   \ the list call reuses the answer buffer, so it comes last; it is asked
   \ only while the account holds a reset
   DB-RESETS? DB-RESETS-COUNT 0 > and if CODEX-CREDITS then ;

: CODEX-UNREADABLE ( n -- ) drop
   construct usage-state error s" OpenAI's usage endpoint" UNREADABLE-NOTE SAY ;

: CODEX-LIVE-REJECTED ( n -- ) drop
   construct usage-state expired CODEX-LIVE-REJECTED$ SAY ;

: CODEX-REJECTED ( n -- ) drop
   construct usage-state expired CODEX-REJECTED$ SAY ;

: CODEX-THROTTLED ( n -- ) drop
   construct usage-state throttled s" OpenAI is rate limiting usage checks; try again later" SAY ;

: CODEX-NO-GRANT ( n -- ) drop
   construct usage-state expired CODEX-NO-GRANT$ SAY ;

: CODEX-TOKEN-ANSWER ( n -- ) drop
   construct usage-state error CODEX-TOKEN-NOTE$ SAY ;

: CODEX-REFUSED ( n -- ) drop
   construct usage-state expired CODEX-REFUSED$ SAY ;

: CODEX-REVOKED ( n -- ) drop
   construct usage-state revoked CODEX-REVOKED$ SAY ;

FSM:DEFINE CODEX-EXCHANGE ( n ) codex-step key-input
   IN keyed CODEX-KEYED
      api-key           CODEX-API-KEY-NOTE   >recorded
      tokens            -                    >asking
   IN asking CODEX-FIRST ( first-input )
      no-token          CODEX-NO-TOKEN       >recorded
      unreachable       CODEX-USAGE-ANSWER   >recorded
      fine              CODEX-FINE           >recorded
      unreadable        CODEX-UNREADABLE     >recorded
      rejected-live     CODEX-LIVE-REJECTED  >recorded
      rejected-saved    -                    >renewing
      rejected-revoked  -                    >renewing-revoked
      throttled         CODEX-THROTTLED      >recorded
      other             CODEX-USAGE-ANSWER   >recorded
   IN renewing CODEX-RENEW ( codex-renew-input )
      renewed           -                    >retrying
      no-grant          CODEX-NO-GRANT       >recorded
      unreachable       CODEX-TOKEN-ANSWER   >recorded
      unusable          CODEX-TOKEN-ANSWER   >recorded
      refused           CODEX-REFUSED        >recorded
      answered          CODEX-TOKEN-ANSWER   >recorded
   IN renewing-revoked CODEX-RENEW ( codex-renew-input )
      renewed           -                    >retrying
      no-grant          CODEX-NO-GRANT       >recorded
      unreachable       CODEX-TOKEN-ANSWER   >recorded
      unusable          CODEX-TOKEN-ANSWER   >recorded
      refused           CODEX-REVOKED        >recorded
      answered          CODEX-TOKEN-ANSWER   >recorded
   IN retrying CODEX-RETRY ( retry-input )
      no-token          CODEX-NO-TOKEN       >recorded
      unreachable       CODEX-USAGE-ANSWER   >recorded
      fine              CODEX-FINE           >recorded
      unreadable        CODEX-UNREADABLE     >recorded
      rejected          CODEX-REJECTED       >recorded
      throttled         CODEX-THROTTLED      >recorded
      other             CODEX-USAGE-ANSWER   >recorded
   FINAL recorded -
;DEFINE

\ ---- one probe -------------------------------------------------------------------
: PROBE-BEGIN ( ^u8 n bool -- ) {: d du live :}
   d du PROBE-DOC!
   epoch-seconds PROBE-AT !
   live PROBE-LIVE !
   -1 PLAN-NAMED-U ! -1 HTTP-CODE ! ;

: PROBE-RUN ( n -- ) {: p :}
   p case
     P-CLAUDE of p construct claude-step fresh CLAUDE-EXCHANGE endof
     P-CODEX of p construct codex-step keyed CODEX-EXCHANGE endof
     E-SW-PROVIDER throw
   endcase ;

\ ---- limit resets ---------------------------------------------------------------
\ One reset of a saved login's offer is spent.
\ A saved login's token is refreshed when it has expired (Claude), or once
\ when the first send is rejected; the live login's never is. The answer's
\ word is the outcome; any other answer fails with E-SW-REMOTE and a note.
: CLAUDE-ORGS-URL$ ( -- ^u8 n ) s" https://api.anthropic.com/api/organizations/" ;
: CLAUDE-RESET-PATH$ ( -- ^u8 n ) s" /reset_rate_limits" ;
: CODEX-CONSUME-URL$ ( -- ^u8 n ) s" https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume" ;

public
ENUM reset-outcome reset not-limited already-used no-credit cooldown ineligible unavailable ;ENUM
private

ENUM claude-reset-step freshening sending renewing resending answered failed ;ENUM
ENUM codex-reset-step sending renewing renewing-revoked resending answered failed ;ENUM
ENUM reset-reply no-token unreachable fine unknown unreadable rejected-live rejected-saved rejected-revoked throttled other ;ENUM

TYPED-VARIABLE RESET-GOT reset-outcome
create RESET-URL PATH-CAP allot              variable RESET-URL-U
create RESET-BODY BUF:HDR-BYTES allot
create RESET-WORD TEXT-CAP allot             variable RESET-WORD-U
create REMOTE-NOTE TEXT-CAP allot            variable REMOTE-NOTE-U
create RID-RAW 16 allot
create RID-BUF 36 allot

: RESET-URL$ ( -- ^u8 n ) RESET-URL RESET-URL-U @ ;
: RESET-BODY$ ( -- ^u8 n ) RESET-BODY BUF:SPAN$ BUF:BLEN>N ;
: RESET-WORD$ ( -- ^u8 n ) RESET-WORD RESET-WORD-U @ ;
: REMOTE! ( ^u8 n -- ) REMOTE-NOTE REMOTE-NOTE-U TEXT-CAP SPAN! ;

\ byte i of the id as two uppercase digits, after a dash before bytes 4,
\ 6, 8 and 10
: RID-BYTE ( n -- ) {: i :}
   i 4 = i 6 = or i 8 = or i 10 = or if $2D SB-APPEND-C then
   RID-RAW i + c@ 2 FMT:SB-HEX-WIDTH ;

\ a random version 4 UUID, uppercase 8-4-4-4-12 hex:
\ each request is told apart by it
: REQUEST-ID$ ( -- ^u8 n )
   RID-RAW 16 ENTROPY:FILL
   RID-RAW 6 + c@ $0F and $40 or RID-RAW 6 + c!
   RID-RAW 8 + c@ $3F and $80 or RID-RAW 8 + c!
   SB-RESET 16 0 ?do i RID-BYTE loop
   SB$ {: s su :}
   s RID-BUF su BYTE-COPY
   RID-BUF su ;

\ the writer's text kept as the request body, which a refresh's own body
\ would overwrite in the writer
: BODY! ( ^JSON:writer -- )
   JSON:WRITTEN$ {: a u :}
   RESET-BODY 64 BUF:N>BLEN BUF:RESET
   a u BUF:N>BLEN RESET-BODY BUF:APPEND-SPAN ;

: BANKED-BODY ( ^u8 n -- ) {: g gu :}
   REQUEST-ID$ {: id idu :}
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" program" s" cedar_ember" JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" grant_id" g gu JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" request_id" id idu JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END BODY! ;

: WEEKLY-BODY ( -- )
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" program" s" juniper_tide" JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END BODY! ;

\ the request for the offer's program; E-SW-NO-RESETS for one kiba does not know
: CLAUDE-RESET-BODY ( -- )
   DB-RESETS-PROGRAM$ s" cedar_ember" STR= if DB-RESETS-GRANT$ BANKED-BODY exit then
   DB-RESETS-PROGRAM$ s" juniper_tide" STR= if WEEKLY-BODY exit then
   E-SW-NO-RESETS throw ;

: CODEX-RESET-BODY ( -- )
   REQUEST-ID$ {: id idu :}
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" redeem_request_id" id idu JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END BODY! ;

\ RFC 3986's unreserved bytes, which a path segment carries as they are
: UNRESERVED? ( n -- bool ) {: c :}
   c ASCII-UPPER {: up :}
   up [char] A >= up [char] Z <= and
   c STR-DIGIT? or
   c [char] - = or c [char] . = or
   c [char] _ = or c [char] ~ = or ;

: SB-SEGMENT-C ( n -- ) {: c :}
   c UNRESERVED? if c SB-APPEND-C exit then
   $25 SB-APPEND-C c 2 FMT:SB-HEX-WIDTH ;

\ the text appended as one URL path segment, as appending(component:)
\ writes it: every other byte as %XX, so none can end the segment
: SB-SEGMENT ( ^u8 n -- ) {: s su :}
   su 0 ?do s i + c@ SB-SEGMENT-C loop ;

\ the reset is asked of row r's organization; E-SW-JSON when it names none
: CLAUDE-RESET-PREPARE ( n -- ) {: r :}
   r DB-ROW-ORG$ {: o ou :}
   ou 0= if E-SW-JSON throw then
   r DB-ROW-USAGE drop
   CLAUDE-RESET-BODY
   SB-RESET CLAUDE-ORGS-URL$ SB-APPEND
   o ou SB-SEGMENT CLAUDE-RESET-PATH$ SB-APPEND
   SB$ RESET-URL RESET-URL-U PATH! ;

: CODEX-RESET-PREPARE ( -- )
   CODEX-RESET-BODY
   CODEX-CONSUME-URL$ RESET-URL RESET-URL-U PATH! ;

: RESET-PREPARE ( n n -- ) {: p r :}
   p P-CLAUDE = if r CLAUDE-RESET-PREPARE exit then
   CODEX-RESET-PREPARE ;

\ the endpoint as notes name it
: RESET-WHAT$ ( n -- ^u8 n )
   P-CLAUDE = if s" Anthropic's reset endpoint" exit then
   s" OpenAI's reset endpoint" ;

\ the member of a 200 answer that holds the result word
: RESET-FIELD$ ( n -- ^u8 n )
   P-CLAUDE = if s" result" exit then
   s" code" ;

\ the access token in VAL-BUF; its length, -1 when there is none
: RESET-TOKEN ( n -- n )
   P-CLAUDE = if s" accessToken" CLAUDE-TOKEN exit then
   s" access_token" CODEX-TOKEN ;

: RESET-POST ( ^u8 n -- n ) {: url uu :}
   RESET-BODY$ url uu POST-JSON
   dup HTTP-CODE ! ;

: CLAUDE-RESET-SEND ( -- n )
   CLAUDE-UA$ REQUEST
   VAL-BUF VAL-U @ BEARER
   s" anthropic-beta" s" oauth-2025-04-20" HDR
   RESET-URL$ RESET-POST ;

: CODEX-RESET-SEND ( -- n ) CODEX-REQUEST RESET-URL$ RESET-POST ;

: RESET-SEND ( n -- n )
   P-CLAUDE = if CLAUDE-RESET-SEND exit then
   CODEX-RESET-SEND ;

: GOT ( reset-outcome -- bool ) RESET-GOT ! true ;
: WORD-IS? ( ^u8 n -- bool ) RESET-WORD$ STR= ;

: CLAUDE-WORD? ( -- bool )
   s" reset" WORD-IS? if construct reset-outcome reset GOT exit then
   s" already_used" WORD-IS? if construct reset-outcome already-used GOT exit then
   s" not_limited" WORD-IS? if construct reset-outcome not-limited GOT exit then
   s" cooldown" WORD-IS? if construct reset-outcome cooldown GOT exit then
   s" ineligible" WORD-IS? if construct reset-outcome ineligible GOT exit then
   s" unavailable" WORD-IS? if construct reset-outcome unavailable GOT exit then
   false ;

: CODEX-WORD? ( -- bool )
   s" reset" WORD-IS? if construct reset-outcome reset GOT exit then
   s" nothing_to_reset" WORD-IS? if construct reset-outcome not-limited GOT exit then
   s" no_credit" WORD-IS? if construct reset-outcome no-credit GOT exit then
   s" already_redeemed" WORD-IS? if construct reset-outcome already-used GOT exit then
   false ;

\ the word a 200 answer names, as RESET-GOT when the provider's words hold it
: RESET-ANSWERED ( n -- reset-reply ) {: p :}
   ANSWER$ {: b bu :}
   b bu FIELDS? 0= if construct reset-reply unreadable exit then
   b bu p RESET-FIELD$ RESET-WORD TEXT-CAP DOC-STR1 0 max RESET-WORD-U !
   p P-CLAUDE = if CLAUDE-WORD? else CODEX-WORD? then
   if construct reset-reply fine exit then
   construct reset-reply unknown ;

\ a 401: the live login's token is its CLI's to renew; a saved one's is
\ renewed, and a refused renewal after a revoked token means a sign-out
: REJECTION ( -- reset-reply )
   PROBE-LIVE @ if construct reset-reply rejected-live exit then
   ANSWER$ {: b bu :}
   b bu FIELDS? 0= if construct reset-reply rejected-saved exit then
   b bu s" error" s" code" s" token_revoked" STR2-IS? if construct reset-reply rejected-revoked exit then
   construct reset-reply rejected-saved ;

: RESET-SENSE ( n -- reset-reply ) {: p :}
   p RESET-TOKEN 0 < if construct reset-reply no-token exit then
   p RESET-SEND {: code :}
   code 0 < if construct reset-reply unreachable exit then
   code 200 = if p RESET-ANSWERED exit then
   code 401 = if REJECTION exit then
   code 429 = if construct reset-reply throttled exit then
   construct reset-reply other ;

: RESET-NO-ACCESS ( n -- ) drop NO-ACCESS$ REMOTE! ;

: RESET-ANSWER ( n -- ) RESET-WHAT$ HTTP-CODE @ HTTP-NOTE REMOTE! ;

: RESET-UNREADABLE ( n -- ) RESET-WHAT$ UNREADABLE-NOTE REMOTE! ;

: RESET-UNKNOWN ( n -- ) {: p :}
   RESET-WORD$ ONE-LINE {: w wu :}
   SB-RESET p RESET-WHAT$ SB-APPEND s"  sent an unknown result " SB-APPEND
   $22 SB-APPEND-C w wu SB-APPEND $22 SB-APPEND-C SB$ REMOTE! ;

: RESET-THROTTLED ( n -- )
   P-CLAUDE = if s" Anthropic is rate limiting limit resets; try again later" REMOTE! exit then
   s" OpenAI is rate limiting limit resets; try again later" REMOTE! ;

: RESET-REJECTED ( n -- )
   P-CLAUDE = if CLAUDE-REJECTED$ REMOTE! exit then
   CODEX-REJECTED$ REMOTE! ;

: RESET-FAIL ( n -- ) drop E-SW-REMOTE throw ;

: CLAUDE-RESET-STALE ( n -- ) drop CLAUDE-LIVE-STALE$ REMOTE! ;
: CLAUDE-RESET-NO-GRANT ( n -- ) drop CLAUDE-NO-GRANT$ REMOTE! ;
: CLAUDE-RESET-TOKEN ( n -- ) drop CLAUDE-TOKEN-NOTE$ REMOTE! ;
: CLAUDE-RESET-ON-HOLD ( n -- ) drop CLAUDE-ON-HOLD$ REMOTE! ;
: CLAUDE-RESET-REFUSED ( n -- ) drop CLAUDE-REFUSED$ REMOTE! ;

FSM:DEFINE CLAUDE-RESET ( n ) claude-reset-step fresh-input
   IN freshening CLAUDE-FRESH
      current           -                      >sending
      stale-live        CLAUDE-RESET-STALE     >failed
      stale-saved       -                      >renewing
   IN sending RESET-SENSE ( reset-reply )
      no-token          RESET-NO-ACCESS        >failed
      unreachable       RESET-ANSWER           >failed
      fine              -                      >answered
      unknown           RESET-UNKNOWN          >failed
      unreadable        RESET-UNREADABLE       >failed
      rejected-live     CLAUDE-RESET-STALE     >failed
      rejected-saved    -                      >renewing
      rejected-revoked  -                      >renewing
      throttled         RESET-THROTTLED        >failed
      other             RESET-ANSWER           >failed
   IN renewing CLAUDE-RENEW ( renew-input )
      renewed           -                      >resending
      no-grant          CLAUDE-RESET-NO-GRANT  >failed
      unreachable       CLAUDE-RESET-TOKEN     >failed
      unusable          CLAUDE-RESET-TOKEN     >failed
      on-hold           CLAUDE-RESET-ON-HOLD   >failed
      refused           CLAUDE-RESET-REFUSED   >failed
      answered          CLAUDE-RESET-TOKEN     >failed
   IN resending RESET-SENSE ( reset-reply )
      no-token          RESET-NO-ACCESS        >failed
      unreachable       RESET-ANSWER           >failed
      fine              -                      >answered
      unknown           RESET-UNKNOWN          >failed
      unreadable        RESET-UNREADABLE       >failed
      rejected-live     RESET-REJECTED         >failed
      rejected-saved    RESET-REJECTED         >failed
      rejected-revoked  RESET-REJECTED         >failed
      throttled         RESET-THROTTLED        >failed
      other             RESET-ANSWER           >failed
   FINAL answered -
   FINAL failed RESET-FAIL
;DEFINE

: CODEX-RESET-LIVE ( n -- ) drop CODEX-LIVE-REJECTED$ REMOTE! ;
: CODEX-RESET-NO-GRANT ( n -- ) drop CODEX-NO-GRANT$ REMOTE! ;
: CODEX-RESET-TOKEN ( n -- ) drop CODEX-TOKEN-NOTE$ REMOTE! ;
: CODEX-RESET-REFUSED ( n -- ) drop CODEX-REFUSED$ REMOTE! ;
: CODEX-RESET-REVOKED ( n -- ) drop CODEX-REVOKED$ REMOTE! ;

FSM:DEFINE CODEX-RESET ( n ) codex-reset-step reset-reply
   IN sending RESET-SENSE
      no-token          RESET-NO-ACCESS        >failed
      unreachable       RESET-ANSWER           >failed
      fine              -                      >answered
      unknown           RESET-UNKNOWN          >failed
      unreadable        RESET-UNREADABLE       >failed
      rejected-live     CODEX-RESET-LIVE       >failed
      rejected-saved    -                      >renewing
      rejected-revoked  -                      >renewing-revoked
      throttled         RESET-THROTTLED        >failed
      other             RESET-ANSWER           >failed
   IN renewing CODEX-RENEW ( codex-renew-input )
      renewed           -                      >resending
      no-grant          CODEX-RESET-NO-GRANT   >failed
      unreachable       CODEX-RESET-TOKEN      >failed
      unusable          CODEX-RESET-TOKEN      >failed
      refused           CODEX-RESET-REFUSED    >failed
      answered          CODEX-RESET-TOKEN      >failed
   IN renewing-revoked CODEX-RENEW ( codex-renew-input )
      renewed           -                      >resending
      no-grant          CODEX-RESET-NO-GRANT   >failed
      unreachable       CODEX-RESET-TOKEN      >failed
      unusable          CODEX-RESET-TOKEN      >failed
      refused           CODEX-RESET-REVOKED    >failed
      answered          CODEX-RESET-TOKEN      >failed
   IN resending RESET-SENSE
      no-token          RESET-NO-ACCESS        >failed
      unreachable       RESET-ANSWER           >failed
      fine              -                      >answered
      unknown           RESET-UNKNOWN          >failed
      unreadable        RESET-UNREADABLE       >failed
      rejected-live     RESET-REJECTED         >failed
      rejected-saved    RESET-REJECTED         >failed
      rejected-revoked  RESET-REJECTED         >failed
      throttled         RESET-THROTTLED        >failed
      other             RESET-ANSWER           >failed
   FINAL answered -
   FINAL failed RESET-FAIL
;DEFINE

: RESET-RUN ( n -- ) {: p :}
   p case
     P-CLAUDE of p construct claude-reset-step freshening CLAUDE-RESET endof
     P-CODEX of p construct codex-reset-step sending CODEX-RESET endof
     E-SW-PROVIDER throw
   endcase ;

public

EXPORT USED-PERCENT

\ probes provider p's login document d du, live when the CLI is using it:
\ the outcome is the usage record, PROBE-DOC$ with the login (renewed
\ when a token was) and PROBED-PLAN$
: PROBE ( n ^u8 n bool -- ) {: p d du live :}
   d du live PROBE-BEGIN
   p PROBE-RUN ;

\ the outcome of a probe that threw: an error with the reason as its note;
\ a login renewed before the throw is kept
: PROBE-FAILED ( ^u8 n -- ) {: a u :}
   -1 PLAN-NAMED-U !
   construct usage-state error a u SAY ;

\ the login the last probe or reset request read, renewed when a token was;
\ until a renewal these are the caller's bytes, so they last as long
EXPORT PROBE-DOC$

\ the plan the provider named; length -1 when it named none
: PROBED-PLAN$ ( -- ^u8 n ) PLAN-NAMED PLAN-NAMED-U @ ;

\ spends one limit reset of provider p's saved row r, whose usage holds the
\ offer, live when the CLI is using it: RESET-OUTCOME is what the provider
\ made of it and PROBE-DOC$ the login (renewed when a token was). E-SW-REMOTE
\ with REMOTE-NOTE$ when the provider spent none, E-SW-NO-RESETS for a
\ program kiba does not know, E-SW-JSON for a Claude row with no organization
: REDEEM ( n n bool -- ) {: p r live :}
   r DB-ROW-LOGIN$ live PROBE-BEGIN
   p r RESET-PREPARE
   p RESET-RUN ;

: RESET-OUTCOME ( -- reset-outcome ) RESET-GOT @ ;

\ why the last reset request spent nothing
: REMOTE-NOTE$ ( -- ^u8 n ) REMOTE-NOTE REMOTE-NOTE-U @ ;

;package
