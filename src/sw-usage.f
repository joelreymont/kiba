\ sw-usage.f - per-account rate limits, read from each provider's usage
\ endpoint with curl, as kiba-mac's ClaudeProbe and CodexProbe read them. A
\ probe takes a saved login's document and whether the CLI is using it, and
\ leaves the usage record (sw-db.f), the document in SDOC refreshed when a
\ token was renewed, and the plan the provider named. It reads and writes no
\ slot and takes no lock: the caller holds the provider's turn and records
\ the outcome. A reset request (REDEEM) spends one limit reset under the same
\ terms and leaves its outcome and the document.
require ../src/sw-store.f
require ../src/sw-run.f
require ../src/sw-db.f
require src/lib/date.f
require src/lib/json.f
require src/lib/byte-buffer.f
require src/lib/decimal.f
require src/lib/fsm.f
require src/lib/entropy.f

package SW

$0A constant LF
64 constant RESET-CAP               \ a window's reset instant, as the record holds it
4096 constant HDR-CAP
120 constant DETAIL-MAX             \ the longest server-supplied text a note carries
20 constant HTTP-TIMEOUT-SEC

create PROBE-BUF PATH-CAP allot  variable PROBE-U   \ <store>/probe-<provider>
create PSUB-BUF PATH-CAP allot   variable PSUB-U    \ a file inside it
create HDR-BUF HDR-CAP allot        variable HDR-U     \ one curl -H value
create ACCT-ID-BUF 128 allot        variable ACCT-ID-U
create VAL-BUF 4096 allot           variable VAL-U     \ a decoded token
create RESET-BUF RESET-CAP allot
variable OUT-FD

: SESSION-LABEL$ ( -- ptr u8 n ) s" Session (5-hour)" ;
: WEEKLY-LABEL$ ( -- ptr u8 n ) s" Weekly (7-day)" ;

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

: BYTE-IS? ( ptr u8 n n n -- bool ) {: a u at c :}
   at u < if at a + c@ c = else false then ;

\ the first index from at whose byte is not a digit
: DIGIT-RUN ( ptr u8 n n -- n ) {: a u at :}
   at begin dup u < if dup a + c@ DIGIT? else false then while 1+ repeat ;

\ the value digits lo..hi-1 spell, held to cap
: DIGIT-VALUE ( ptr u8 n n n -- n ) {: a lo hi cap :}
   0 hi lo ?do 10 * a i + c@ DIGIT + cap min loop ;

\ the mantissa from index at; false when a side of its point has no digit
: MANTISSA? ( ptr u8 n n -- bool ) {: a u at :}
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
: EXPONENT-AT ( ptr u8 n n -- n ) {: a u at :}
   0 EXP-VALUE !
   a u at $65 BYTE-IS? a u at $45 BYTE-IS? or 0= if at exit then
   a u at 1+ $2D BYTE-IS? {: neg :}
   a u at 1+ $2B BYTE-IS? neg or if at 2 + else at 1+ then {: lo :}
   a u lo DIGIT-RUN {: hi :}
   hi lo = if -1 exit then
   a lo hi u 20 + DIGIT-VALUE neg if negate then EXP-VALUE !
   hi ;

\ mantissa digit k, counting from its first and skipping the point; 0 past its last
: MANT-DIGIT ( ptr u8 n -- n ) {: a k :}
   MANT-START @ k + dup MANT-POINT @ >= if 1+ then {: at :}
   at MANT-END @ >= if 0 exit then
   at a + c@ DIGIT ;

\ acc * 10 + d; -1 once past INT-MAX
: SHIFT-DIGIT ( n n -- n ) {: acc d :}
   acc 0 < if -1 exit then
   acc INT-MAX d - 10 / > if -1 exit then
   acc 10 * d + ;

: MANT-ZERO? ( ptr u8 -- bool ) {: a :}
   true MANT-END @ MANT-START @ ?do a i + c@ dup $30 = swap $2E = or and loop ;

\ the mantissa rounded to its first p digits, half up; -1 past INT-MAX
: MANT-ROUNDED ( ptr u8 n -- n ) {: a p :}
   0 p 0 ?do a i MANT-DIGIT SHIFT-DIGIT loop {: w :}
   w 0 < if -1 exit then
   p 0 < if w exit then
   a p MANT-DIGIT 5 < if w exit then
   w INT-MAX = if -1 exit then
   w 1+ ;

\ the whole percent reading a u spells, as kiba-mac's usedPercent gives it;
\ -1 when it is malformed, below zero or past INT-MAX
: USED-PERCENT ( ptr u8 n -- n ) {: a u :}
   a u 0 $2D BYTE-IS? {: neg :}
   a u neg if 1 else 0 then MANTISSA? 0= if -1 exit then
   a u MANT-END @ EXPONENT-AT u <> if -1 exit then
   neg a MANT-ZERO? 0= and if -1 exit then
   a MANT-POINT @ MANT-START @ - EXP-VALUE @ + MANT-ROUNDED ;

\ ---- one probe -------------------------------------------------------------------
variable PROBE-AT                   \ epoch seconds the probe began: its fetchedAt
variable PROBE-LIVE                 \ bool: the CLI is using this login; it is never refreshed
variable DOC-NEW                    \ bool: SDOC holds the login with a renewed token
create PLAN-NAMED PLAN-CAP allot    variable PLAN-NAMED-U   \ -1 when the provider named none
variable HTTP-CODE                  \ the last answer's status, -1 when there was none

\ the probe's outcome: a record of state st and note a u, without limits
: SAY ( usage-state ptr u8 n -- ) {: st a u :}
   PROBE-AT @ st a u DB-USAGE! ;

\ ---- scratch files ---------------------------------------------------------------
: PROBE$ ( n -- ptr u8 n ) {: p :}
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /probe-" SB-APPEND p PROVIDER$ SB-APPEND
   SB$ PROBE-BUF PROBE-U PATH!
   PROBE-BUF PROBE-U @ ;

: PSUB$ ( n ptr u8 n -- ptr u8 n ) {: p a u :}
   p PROBE$ 2drop
   SB-RESET PROBE-BUF PROBE-U @ SB-APPEND a u SB-APPEND
   SB$ PSUB-BUF PSUB-U PATH!
   PSUB-BUF PSUB-U @ ;

: BODY$ ( n -- ptr u8 n ) s" /body.json" PSUB$ ;
: CODE$ ( n -- ptr u8 n ) s" /code.txt" PSUB$ ;
: REQ$ ( n -- ptr u8 n ) s" /request.json" PSUB$ ;
: HEADERS$ ( n -- ptr u8 n ) s" /headers.txt" PSUB$ ;

: PROBE-CLEANUP ( n -- ) {: p :}
   p BODY$ FS:FILE? if p BODY$ FS:REMOVE-FILE then
   p CODE$ FS:FILE? if p CODE$ FS:REMOVE-FILE then
   p REQ$ FS:FILE? if p REQ$ FS:REMOVE-FILE then
   p HEADERS$ FS:FILE? if p HEADERS$ FS:REMOVE-FILE then ;

: PROBE-PREPARE ( n -- ) {: p :}
   p PROBE$ ENSURE-PRIVATE
   p PROBE-CLEANUP ;

\ ---- curl --------------------------------------------------------------------------
\ Every request is one curl process. Headers, which carry the bearer token,
\ go through a 0600 file (`-H @file`) rather than argv, which every local
\ user can read from /proc; the body lands in a file and the HTTP status on
\ stdout, redirected into a second file before exec.
\ E-SW-CAPACITY unless n more bytes fit
: HDR-ROOM ( n -- )
   HDR-U @ + HDR-CAP > if
      s" bytes in a request's headers" HDR-CAP LIMIT$ TOO-MANY
   then ;

: HDR-LINE+ ( ptr u8 n -- ) {: a u :}
   u 1+ HDR-ROOM
   a HDR-BUF HDR-U @ + u BYTE-COPY
   LF HDR-BUF HDR-U @ + u + c!
   HDR-U @ u + 1+ HDR-U ! ;

: HDR ( ptr u8 n ptr u8 n -- ) {: name nu val vu :}
   nu 2 + vu + 1+ HDR-ROOM
   name HDR-BUF HDR-U @ + nu BYTE-COPY
   $3A HDR-BUF HDR-U @ + nu + c!
   $20 HDR-BUF HDR-U @ + nu + 1+ c!
   HDR-U @ nu + 2 + HDR-U !
   val vu HDR-LINE+ ;

: BEARER ( ptr u8 n -- ) {: t tu :}
   22 tu + 1+ HDR-ROOM
   s" Authorization: Bearer " HDR-BUF HDR-U @ + swap BYTE-COPY
   HDR-U @ 22 + HDR-U !
   t tu HDR-LINE+ ;

\ Anthropic's token endpoint answers 429 to curl's own User-Agent whatever
\ the grant, so every request names its client
: KIBA-UA$ ( -- ptr u8 n ) s" kiba" ;

: CURL-BEGIN ( n ptr u8 n -- ) {: p ua uu :}
   s" curl" RESOLVE
   PROC-ARGV-RESET
   0 HDR-U !
   s" -sS" ARG+
   s" -m" ARG+
   SB-RESET HTTP-TIMEOUT-SEC FMT:SB-U SB$ ARG+
   s" -o" ARG+ p BODY$ ARG+
   s" -w" ARG+ s" %{http_code}" ARG+
   s" Accept" s" application/json" HDR
   s" User-Agent" ua uu HDR ;

\ the header file is written and named just before the run
: HEADERS-STAGE ( n -- )
   HEADERS$ {: h hu :}
   h hu HDR-BUF HDR-U @ WRITE-PRIVATE
   s" -H" ARG+
   SB-RESET $40 SB-APPEND-C h hu SB-APPEND SB$ ARG+ ;

: EXEC-CURL ( ptr u8 ptr ptr u8 -- ) {: pathz argv :}
   OUT-FD @ 1 dup2 0 < if s" kiba: dup2 failed" 127 die then
   pathz argv ENVP-BASE execve drop
   s" kiba: could not start curl" 127 die ;

\ run the staged curl; the parsed status code, or -1 when curl itself failed.
\ curl truncates the body file rather than creating it, so it is born 0600
: CURL-RUN ( n ptr u8 n -- n ) {: p url uu :}
   p HEADERS-STAGE
   p BODY$ OPEN-PRIVATE close
   url uu ARG+
   EXE$ >LEN PROC-ARGV-PREPARE {: pathz argv :}
   p CODE$ OPEN-PRIVATE OUT-FD !
   PROC-FORK:CHECKED {: pid :}
   pid PID>N 0= if pathz argv EXEC-CURL then
   PROC-ARGV-RESET
   OUT-FD @ close
   pid PROCESS:WAIT PROCESS:STATUS>RC RC>N {: rc :}
   rc 0<> if -1 exit then
   p CODE$ FS:FILE? 0= if -1 exit then
   p CODE$ OBJ-BUF OBJ-U READ-INTO STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

: BODY-READ ( n -- ptr u8 n ) {: p :}
   p BODY$ FS:FILE? 0= if OBJ-BUF 0 exit then
   p BODY$ OBJ-BUF OBJ-U READ-INTO ;

\ the body bytes come from a finished JSON-OPEN chain
: POST-JSON ( n ptr u8 n ptr u8 n -- n ) {: p b bu url uu :}
   p REQ$ {: r ru :}
   r ru b bu WRITE-PRIVATE
   s" -X" ARG+ s" POST" ARG+
   s" Content-Type" s" application/json" HDR
   s" --data-binary" ARG+
   SB-RESET $40 SB-APPEND-C r ru SB-APPEND SB$ ARG+
   p url uu CURL-RUN ;


\ "<what> answered <code>", or "<what> could not be reached" when code < 0
: HTTP-NOTE ( ptr u8 n n -- ptr u8 n ) {: what wu code :}
   SB-RESET what wu SB-APPEND
   code 0 < if s"  could not be reached" SB-APPEND SB$ exit then
   s"  answered " SB-APPEND code FMT:SB-U SB$ ;

: UNREADABLE-NOTE ( ptr u8 n -- ptr u8 n ) {: what wu :}
   SB-RESET what wu SB-APPEND s"  sent an answer that is not a JSON object" SB-APPEND SB$ ;

\ a token request answered; its status is in HTTP-CODE
: TOKEN-POST ( n ptr u8 n ptr u8 n -- n ) {: p b bu url uu :}
   p KIBA-UA$ CURL-BEGIN
   p b bu url uu POST-JSON
   p REQ$ FS:REMOVE-FILE
   dup HTTP-CODE ! ;

\ only a token endpoint's 400 or 401 proves a saved login gone
: REFUSED-STATUS? ( n -- bool ) dup 400 = swap 401 = or ;

\ ---- reading answers -------------------------------------------------------------
\ A document or answer is read field by field only once it is known to be
\ one JSON object in which no object, nested ones included, repeats a key,
\ as JSONFields reads one; a field of another kind reads as absent.
: OBJECT-KEEP ( ptr u8 n -- ptr u8 n )
   2dup CHECK-FIELDS ;

: OBJECT? ( ptr u8 n -- bool )
   [: OBJECT-KEEP ;] catch {: rc :} 2drop rc 0= ;

: KEY-OBJ? ( ptr u8 n ptr u8 n -- bool ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT swap JSON:READ-CLOSE ;

\ the token kind of the member k2 of the object at k1; JSON:T-END when absent
: KIND2 ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k1 k1u k2 k2u :}
   d du OPEN-DOC ENTER-OBJECT
   k1 k1u KEY-OBJECT 0= if JSON:READ-CLOSE JSON:T-END exit then
   k2 k2u JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE JSON:T-END exit then
   JSON:READ-TOKEN swap JSON:READ-CLOSE ;

: TRUE2? ( ptr u8 n ptr u8 n ptr u8 n -- bool ) KIND2 JSON:T-TRUE = ;

\ the member k2 of the object at k1 is the string w
: STR2-IS? ( ptr u8 n ptr u8 n ptr u8 n ptr u8 n -- bool ) {: d du k1 k1u k2 k2u w wu :}
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
: SCALAR@ ( ptr u8 n -- n ) {: a len :}
   a c@ len 1 = if exit then
   $7F len rshift and
   len 1 ?do 6 lshift a i + c@ $3F and or loop ;

\ White_Space or a control character
: SEPARATOR? ( n -- bool ) {: c :}
   c $20 <= if true exit then
   c $7F >= c $A0 <= and if true exit then
   c $2000 >= c $200A <= and if true exit then
   c $1680 = c $2028 = or c $2029 = or c $202F = or c $205F = or c $3000 = or ;

: LINE-COPY ( ptr u8 n -- ) {: a len :}
   a LINE-OUT LINE-U @ + len BYTE-COPY
   len LINE-U +! ;

: LINE-SCALAR ( ptr u8 n -- ) {: a len :}
   1 LINE-N +!
   LINE-N @ DETAIL-MAX <= if a len LINE-COPY then
   LINE-N @ DETAIL-MAX 1- = if LINE-U @ LINE-CUT ! then ;

: LINE-STEP ( ptr u8 n -- ) {: a len :}
   a len SCALAR@ SEPARATOR? if LINE-N @ 0 > LINE-GAP ! exit then
   LINE-GAP @ if false LINE-GAP ! s"  " LINE-SCALAR then
   a len LINE-SCALAR ;

: ONE-LINE ( ptr u8 n -- ptr u8 n ) {: a u :}
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
: SPLICE-CFG ( n n ptr u8 n -- ) {: off len v vu :}
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
: CFG-ADD ( n bool ptr u8 n ptr u8 n -- ) {: at members k ku v vu :}
   at 0 v vu SPLICE-CFG
   SB-RESET members if $2C SB-APPEND-C then
   $22 SB-APPEND-C k ku SB-APPEND $22 SB-APPEND-C $3A SB-APPEND-C
   at 0 SB$ SPLICE-CFG ;

\ the top-level key's value set to a JSON literal, added at the end when absent
: CFG-SET ( ptr u8 n ptr u8 n -- ) {: k ku v vu :}
   CFG$ k ku DOC-VALUE-SPAN? {: off len found :}
   found if off len v vu SPLICE-CFG exit then
   CFG$ DOC-CLOSE k ku v vu CFG-ADD ;

\ the same one level down, inside the object at k1, which must be there
: CFG-SET2 ( ptr u8 n ptr u8 n ptr u8 n -- ) {: k1 k1u k2 k2u v vu :}
   CFG$ k1 k1u DOC-OBJ-SPAN {: off1 len1 :}
   CFG-BUF off1 + len1 k2 k2u DOC-VALUE-SPAN? {: off2 len2 found :}
   found if off1 off2 + len2 v vu SPLICE-CFG exit then
   CFG-BUF off1 + len1 DOC-CLOSE {: at members :}
   off1 at + members k2 k2u v vu CFG-ADD ;

\ a decoded string as a JSON string literal, in the writer buffer
: LITERAL$ ( ptr u8 n -- ptr u8 n ) {: a u :}
   JSON-OPEN a u JSON:WRITE-STRING JSON:WRITTEN$ ;

: NUMBER$ ( n -- ptr u8 n )
   SB-RESET FMT:SB-INT SB$ ;

\ a refresh splices a copy of the login, which replaces it only when whole
: SPLICE-BEGIN ( -- ) SDOC$ CFG-BUF CFG-U BUF-CAP SPAN! ;

: SPLICE-END ( -- )
   CFG$ SDOC-BUF SDOC-U BUF-CAP SPAN!
   true DOC-NEW ! ;

\ ---- Anthropic -----------------------------------------------------------------------
\ The usage flags ask for both reset blocks, as Claude Code does. The usage
\ endpoint offers limit resets only to Claude Code's own User-Agent, so the
\ usage call carries it, with the CLI version the check was made against.
: CLAUDE-USAGE-URL$ ( -- ptr u8 n ) s" https://api.anthropic.com/api/oauth/usage?cedar_ember=1&at_wall=1" ;
: CLAUDE-TOKEN-URL$ ( -- ptr u8 n ) s" https://platform.claude.com/v1/oauth/token" ;
: CLAUDE-PROFILE-URL$ ( -- ptr u8 n ) s" https://api.anthropic.com/api/oauth/profile" ;
: CLAUDE-CLIENT-ID$ ( -- ptr u8 n ) s" 9d1c250a-e61b-44d9-88ed-5944d1962f5e" ;
: CLAUDE-UA$ ( -- ptr u8 n ) s" claude-cli/2.1.282 (external, cli)" ;
: CREDS-KEY$ ( -- ptr u8 n ) s" claudeAiOauth" ;

: BUCKET-PCT ( JSON:reader -- JSON:reader n )
   JSON:READ-TOKEN NUMBER-TOKEN? 0= if -1 exit then
   JSON:READ-SPAN$ USED-PERCENT ;

: BUCKET-RESET ( JSON:reader -- JSON:reader ptr u8 n )
   JSON:READ-TOKEN JSON:T-STR <> if RESET-BUF 0 exit then
   RESET-BUF RESET-CAP TEXT-INTO RESET-BUF swap ;

\ one bucket object {utilization, resets_at} at key; whole percent and reset text
: CLAUDE-BUCKET ( ptr u8 n ptr u8 n -- n ptr u8 n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JSON:READ-CLOSE -1 RESET-BUF 0 exit then
   s" utilization" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE -1 RESET-BUF 0 exit then
   BUCKET-PCT {: h :}
   JSON:READ-CLOSE
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT drop
   s" resets_at" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE h RESET-BUF 0 exit then
   BUCKET-RESET {: r ru :}
   JSON:READ-CLOSE
   h r ru ;

create SESSION-RESET RESET-CAP allot   variable SESSION-RESET-U
create WEEKLY-RESET RESET-CAP allot    variable WEEKLY-RESET-U

\ ---- model-scoped windows -------------------------------------------------------
\ the payload's `limits` list also carries per-model windows such as Fable's
\ weekly allowance: {kind: weekly_scoped, scope: {model: {display_name}}}
create SC-NAME 64 allot            variable SC-NAME-U
create SC-KIND 32 allot            variable SC-KIND-U
create SC-RESET RESET-CAP allot variable SC-RESET-U
variable SC-PCT

: SC-ENTRY-RESET ( -- )
   0 SC-NAME-U ! 0 SC-KIND-U ! 0 SC-RESET-U ! -1 SC-PCT ! ;

\ a string member's value into dst, its length into up; else skipped
: SC-STR ( JSON:reader ptr u8 ptr n n -- JSON:reader ) {: dst up cap :}
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-SKIP-VALUE exit then
   dst cap TEXT-INTO up ! ;

\ on the model object's opening brace: its display name
: SC-MODEL ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
      s" display_name" JSON:READ-STR-EQ? {: named :}
      JSON:READ-NEXT drop
      named if SC-NAME SC-NAME-U 64 SC-STR else JSON:READ-SKIP-VALUE then
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

\ on a limits entry's key: the member it names, read
: SC-MEMBER ( JSON:reader -- JSON:reader )
   s" kind" JSON:READ-STR-EQ? {: kind :}
   s" resets_at" JSON:READ-STR-EQ? {: reset :}
   s" percent" JSON:READ-STR-EQ? {: pct :}
   s" scope" JSON:READ-STR-EQ? {: scope :}
   JSON:READ-NEXT drop
   kind if SC-KIND SC-KIND-U 32 SC-STR exit then
   reset if SC-RESET SC-RESET-U RESET-CAP SC-STR exit then
   pct if SC-PERCENT exit then
   scope if SC-SCOPE exit then
   JSON:READ-SKIP-VALUE ;

: SC-WINDOW$ ( -- ptr u8 n )
   SC-KIND SC-KIND-U @ s" weekly" STARTS-WITH? if s" Weekly" exit then
   SC-KIND SC-KIND-U @ s" five_hour" STARTS-WITH? if s" Session" exit then
   SC-KIND SC-KIND-U @ s" session" STARTS-WITH? if s" Session" exit then
   s" " ;

\ a window with a model becomes "<Model> Weekly"; unscoped ones are the
\ session and weekly buckets already taken
: SC-ENTRY+ ( -- )
   SC-NAME-U @ 0= if exit then
   SC-PCT @ 0 < if exit then
   SB-RESET SC-NAME SC-NAME-U @ SB-APPEND
   SC-WINDOW$ dup 0 > if $20 SB-APPEND-C SB-APPEND else 2drop then
   SB$ SC-PCT @ SC-RESET SC-RESET-U @ DB-LIMIT+ ;

: SC-OBJECT ( JSON:reader -- JSON:reader )
   SC-ENTRY-RESET
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while
      JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
      SC-MEMBER
   repeat
   SC-ENTRY+ ;

: SC-ARRAY ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-ARR-END <> while
      JSON:READ-TOKEN JSON:T-OBJ <> if E-SW-JSON throw then
      SC-OBJECT
   repeat ;

: CLAUDE-SCOPED ( ptr u8 n -- ) {: d du :}
   d du OPEN-DOC ENTER-OBJECT
   s" limits" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE exit then
   JSON:READ-TOKEN JSON:T-ARR <> if JSON:READ-CLOSE exit then
   SC-ARRAY
   JSON:READ-CLOSE ;

\ Session, then Weekly (seven_day_oauth_apps, else seven_day), then every
\ model-scoped window; a window without a reading is left out
: CLAUDE-LIMITS ( ptr u8 n -- ) {: d du :}
   d du s" five_hour" CLAUDE-BUCKET SESSION-RESET SESSION-RESET-U RESET-CAP SPAN! {: sh :}
   d du s" seven_day_oauth_apps" CLAUDE-BUCKET {: wh0 r0 r0u :}
   wh0 0 < if d du s" seven_day" CLAUDE-BUCKET else wh0 r0 r0u then
   WEEKLY-RESET WEEKLY-RESET-U RESET-CAP SPAN! {: wh :}
   sh 0 >= if SESSION-LABEL$ sh SESSION-RESET SESSION-RESET-U @ DB-LIMIT+ then
   wh 0 >= if WEEKLY-LABEL$ wh WEEKLY-RESET WEEKLY-RESET-U @ DB-LIMIT+ then
   d du CLAUDE-SCOPED ;

\ ---- the reset offer -------------------------------------------------------------
\ cedar_ember banks grants: the one named next_grant_id and its resets_left;
\ else juniper_tide offers one reset a week while one is available
create GRANT-NEXT REC-WORD-CAP allot   variable GRANT-NEXT-U
variable GRANT-SEEN                 \ bool: the grant named next was found
variable GRANT-IS                   \ bool: the grant in hand is the one named next
variable GRANT-HAS-LEFT             \ bool: the grant in hand says how many resets are left
variable GRANT-LEFT

: GRANT-MEMBER ( JSON:reader -- JSON:reader )
   JSON:READ-TOKEN JSON:T-KEY <> if E-SW-JSON throw then
   s" id" JSON:READ-STR-EQ? {: idk :}
   s" resets_left" JSON:READ-STR-EQ? {: leftk :}
   JSON:READ-NEXT drop
   JSON:READ-TOKEN {: t :}
   idk t JSON:T-STR = and if GRANT-NEXT GRANT-NEXT-U @ JSON:READ-STR-EQ? GRANT-IS ! exit then
   leftk t NUMBER-TOKEN? and if WHOLE GRANT-HAS-LEFT ! GRANT-LEFT ! exit then
   JSON:READ-SKIP-VALUE ;

: GRANT-OBJECT ( JSON:reader -- JSON:reader )
   false GRANT-IS ! false GRANT-HAS-LEFT !
   begin JSON:READ-NEXT JSON:T-OBJ-END <> while GRANT-MEMBER repeat
   GRANT-IS @ GRANT-SEEN ! ;

\ the first grant object with the id named next decides
: GRANT-ARRAY ( JSON:reader -- JSON:reader )
   begin JSON:READ-NEXT JSON:T-ARR-END <> while
      JSON:READ-TOKEN JSON:T-OBJ = GRANT-SEEN @ 0= and if GRANT-OBJECT else JSON:READ-SKIP-VALUE then
   repeat ;

: GRANTS-SCAN ( ptr u8 n -- ) {: d du :}
   false GRANT-SEEN ! false GRANT-HAS-LEFT !
   d du OPEN-DOC ENTER-OBJECT
   s" cedar_ember" KEY-OBJECT drop
   s" grants" JSON:READ-FIND-KEY if
      JSON:READ-TOKEN JSON:T-ARR = if GRANT-ARRAY then
   then
   JSON:READ-CLOSE ;

: BANKED? ( ptr u8 n -- bool ) {: d du :}
   d du s" cedar_ember" s" eligible" TRUE2? 0= if false exit then
   d du s" cedar_ember" s" next_grant_id" GRANT-NEXT REC-WORD-CAP DOC-STR2
   dup 0 < if drop false exit then
   GRANT-NEXT-U !
   d du GRANTS-SCAN
   GRANT-SEEN @ 0<> GRANT-HAS-LEFT @ 0<> and ;

: CLAUDE-RESETS ( ptr u8 n -- ) {: d du :}
   d du BANKED? if GRANT-LEFT @ s" cedar_ember" GRANT-NEXT GRANT-NEXT-U @ DB-RESETS! exit then
   d du s" juniper_tide" s" eligible" TRUE2? 0= if exit then
   d du s" juniper_tide" s" available" TRUE2? if 1 else 0 then
   s" juniper_tide" s" " DB-RESETS! ;

\ ---- Anthropic's refusals -----------------------------------------------------------
\ A token endpoint's error answer as Claude Code reads it: error when it is a
\ string, else error.type; error_description; error_uri.
create REF-CODE TEXT-CAP allot   variable REF-CODE-U
create REF-DESC TEXT-CAP allot   variable REF-DESC-U
create REF-URI TEXT-CAP allot    variable REF-URI-U    \ -1 when the answer names none

: REF-CODE$ ( -- ptr u8 n ) REF-CODE REF-CODE-U @ ;
: REF-DESC$ ( -- ptr u8 n ) REF-DESC REF-DESC-U @ ;

: REF-CODE-READ ( ptr u8 n -- ) {: b bu :}
   b bu s" error" REF-CODE TEXT-CAP DOC-STR1 dup 0 >= if REF-CODE-U ! exit then
   drop b bu s" error" s" type" REF-CODE TEXT-CAP DOC-STR2 0 max REF-CODE-U ! ;

: REFUSAL-READ ( ptr u8 n -- ) {: b bu :}
   0 REF-CODE-U ! 0 REF-DESC-U ! -1 REF-URI-U !
   b bu OBJECT? 0= if exit then
   b bu REF-CODE-READ
   b bu s" error_description" REF-DESC TEXT-CAP DOC-STR1 0 max REF-DESC-U !
   b bu s" error_uri" REF-URI TEXT-CAP DOC-STR1 REF-URI-U ! ;

\ Anthropic's on-hold refusal, as Claude Code 2.1.285 reads it
: ON-HOLD? ( n -- bool ) {: code :}
   code REFUSED-STATUS? code 403 = or
   REF-CODE$ s" invalid_grant" STR= REF-CODE$ s" access_denied" STR= or and
   REF-DESC$ s" account_on_hold" STR= and ;

create DETAIL-RAW TEXT-CAP 2 * 32 + allot   variable DETAIL-RAW-U

: RAW+ ( ptr u8 n -- ) {: a u :}
   a DETAIL-RAW DETAIL-RAW-U @ + u BYTE-COPY
   u DETAIL-RAW-U +! ;

\ "<status> <code>: <description>" on one line, absent parts left out
: DETAIL$ ( n -- ptr u8 n ) {: code :}
   0 DETAIL-RAW-U !
   code FMT:INT$ RAW+
   REF-CODE-U @ 0 > if s"  " RAW+ REF-CODE$ RAW+ then
   REF-DESC-U @ 0 > if s" : " RAW+ REF-DESC$ RAW+ then
   DETAIL-RAW DETAIL-RAW-U @ ONE-LINE ;

\ An appeal page is trusted when it is a plain https page on Anthropic's own
\ hosts: no user, port or fragment, no trailing . or ?, at most DETAIL-MAX
\ characters; else Claude Code's fallback page.
create HOST-BUF DETAIL-MAX allot    variable HOST-U

: SCHEME$ ( -- ptr u8 n ) s" https://" ;
: RESTRICTED$ ( -- ptr u8 n ) s" https://claude.ai/restricted" ;

: LOWER? ( n -- bool ) dup $61 >= swap $7A <= and ;
: UPPER? ( n -- bool ) dup $41 >= swap $5A <= and ;

: URI-CHAR? ( n -- bool ) {: c :}
   c LOWER? c UPPER? or c DIGIT? or if true exit then
   c $2F = c $2E = or c $5F = or c $7E = or c $25 = or
   c $2D = or c $3F = or c $3D = or c $26 = or ;

: HOST-CHAR? ( n -- bool ) {: c :}
   c LOWER? c DIGIT? or c $2E = or c $2D = or ;

: ALL? ( ptr u8 n [ n -- bool ] -- bool ) {: a u ok :}
   u 0 ?do a i + c@ ok execute 0= if false unloop exit then loop
   true ;

: HOST-END? ( n -- bool ) dup $2F = swap $3F = or ;

: LOWERED ( n -- n ) dup UPPER? if $20 + then ;

\ the host of the URI after its scheme, lowercased into HOST-BUF
: HOST! ( ptr u8 n -- ) {: a u :}
   0 HOST-U !
   u 0 ?do
      a i + c@ HOST-END? if unloop exit then
      a i + c@ LOWERED HOST-BUF HOST-U @ + c!
      1 HOST-U +!
   loop ;

\ the host is d or a subdomain of it
: DOMAIN? ( ptr u8 n ptr u8 n -- bool ) {: h hu d du :}
   h hu d du STR= if true exit then
   hu du 1+ < if false exit then
   h hu du - + du d du STR= 0= if false exit then
   h hu du - 1- + c@ $2E = ;

: HOST-OURS? ( -- bool )
   HOST-U @ 0= if false exit then
   HOST-BUF HOST-U @ [: HOST-CHAR? ;] ALL? 0= if false exit then
   HOST-BUF HOST-U @ s" claude.ai" DOMAIN? if true exit then
   HOST-BUF HOST-U @ s" anthropic.com" DOMAIN? ;

: APPEAL-OK? ( ptr u8 n -- bool ) {: a u :}
   u DETAIL-MAX > if false exit then
   a u SCHEME$ STARTS-WITH? 0= if false exit then
   a u + 1- c@ dup $2E = swap $3F = or if false exit then
   SCHEME$ nip {: s :}
   a s + u s - [: URI-CHAR? ;] ALL? 0= if false exit then
   a s + u s - HOST!
   HOST-OURS? ;

: APPEAL$ ( -- ptr u8 n )
   REF-URI-U @ 0 < if RESTRICTED$ exit then
   REF-URI REF-URI-U @ APPEAL-OK? 0= if RESTRICTED$ exit then
   REF-URI REF-URI-U @ ;

\ The usage endpoint's 403 for an organization whose plan does not allow
\ Claude Code's OAuth: a lapsed subscription answers so, while the token
\ document still claims the old plan.
: NO-PLAN? ( ptr u8 n -- bool ) {: b bu :}
   b bu OBJECT? 0= if false exit then
   b bu OPEN-DOC ENTER-OBJECT
   s" error" KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   s" details" KEY-OBJECT 0= if JSON:READ-CLOSE false exit then
   s" error_code" JSON:READ-FIND-KEY 0= if JSON:READ-CLOSE false exit then
   JSON:READ-TOKEN JSON:T-STR <> if JSON:READ-CLOSE false exit then
   s" oauth_not_allowed_for_organization" JSON:READ-STR-EQ? swap JSON:READ-CLOSE ;

\ an API error answer's error.message on one line; empty when absent
create MSG-BUF DETAIL-MAX 4 * allot   variable MSG-U

: MESSAGE! ( ptr u8 n -- ) {: b bu :}
   0 MSG-U !
   b bu OBJECT? 0= if exit then
   b bu s" error" s" message" DETAIL-RAW TEXT-CAP DOC-STR2 {: mu :}
   mu 0 <= if exit then
   DETAIL-RAW mu ONE-LINE MSG-BUF MSG-U DETAIL-MAX 4 * SPAN! ;

\ Anthropic answers a free organization's usage check with the 429 of a
\ rate limit; its profile tells the two apart: free only when it names the
\ organization and a type Claude Code maps to no plan
: PAID? ( ptr u8 n -- bool ) {: a u :}
   a u s" claude_max" STR= a u s" claude_pro" STR= or
   a u s" claude_team" STR= or a u s" claude_enterprise" STR= or ;

: FREE-PLAN? ( ptr u8 n -- bool ) {: b bu :}
   b bu OBJECT? 0= if false exit then
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
: CLAUDE-TOKEN ( ptr u8 n -- n ) {: k ku :}
   SDOC$ OBJECT? 0= if -1 exit then
   SDOC$ CREDS-KEY$ k ku VAL-BUF 4096 DOC-STR2 dup 0 > if dup VAL-U ! exit then
   drop -1 ;

\ expiresAt in epoch milliseconds; -1 when absent
: CLAUDE-EXPIRES ( -- n )
   SDOC$ OBJECT? 0= if -1 exit then
   SDOC$ CREDS-KEY$ s" expiresAt" DOC-INT2 0= if drop -1 then ;

\ a token this close to expiring, a minute, counts as expired
: CLAUDE-FRESH ( n -- fresh-input ) drop
   CLAUDE-EXPIRES {: ms :}
   ms 0 <= if construct fresh-input current exit then
   ms 1000 / PROBE-AT @ 60 + >= if construct fresh-input current exit then
   PROBE-LIVE @ if construct fresh-input stale-live exit then
   construct fresh-input stale-saved ;

: CLAUDE-GRANT-BODY ( -- ptr u8 n )
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" grant_type" s" refresh_token" JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" client_id" CLAUDE-CLIENT-ID$ JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END JSON:WRITTEN$ ;

\ epoch milliseconds secs after the probe began, at claudeAiOauth.k, when
\ the answer gave secs
: EXPIRY-SET ( n bool ptr u8 n -- ) {: secs given k ku :}
   given 0= secs 0 <= or if exit then
   CREDS-KEY$ k ku PROBE-AT @ secs + 1000 * NUMBER$ CFG-SET2 ;

\ the answer b's tokens spliced in; its access token is in VAL-BUF
: CLAUDE-SPLICE ( ptr u8 n -- ) {: b bu :}
   SPLICE-BEGIN
   CREDS-KEY$ s" accessToken" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   b bu s" refresh_token" VAL-BUF 4096 DOC-STR1 dup 0 >= if
      VAL-U ! CREDS-KEY$ s" refreshToken" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   else drop then
   b bu s" expires_in" DOC-INT1 s" expiresAt" EXPIRY-SET
   b bu s" refresh_token_expires_in" DOC-INT1 s" refreshTokenExpiresAt" EXPIRY-SET
   SPLICE-END ;

: CLAUDE-RENEWED ( n -- renew-input )
   BODY-READ {: b bu :}
   b bu OBJECT? 0= if construct renew-input unusable exit then
   b bu s" access_token" VAL-BUF 4096 DOC-STR1 dup 0 < if drop construct renew-input unusable exit then
   VAL-U !
   b bu CLAUDE-SPLICE
   construct renew-input renewed ;

: CLAUDE-DENIED ( n n -- renew-input ) {: p code :}
   p BODY-READ REFUSAL-READ
   code ON-HOLD? if construct renew-input on-hold exit then
   code REFUSED-STATUS? if construct renew-input refused exit then
   construct renew-input answered ;

: CLAUDE-RENEW ( n -- renew-input ) {: p :}
   s" refreshToken" CLAUDE-TOKEN 0 < if construct renew-input no-grant exit then
   p CLAUDE-GRANT-BODY CLAUDE-TOKEN-URL$ TOKEN-POST {: code :}
   code 0 < if construct renew-input unreachable exit then
   code 200 = if p CLAUDE-RENEWED exit then
   p code CLAUDE-DENIED ;

: CLAUDE-GET ( n -- n ) {: p :}
   p CLAUDE-UA$ CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   s" anthropic-beta" s" oauth-2025-04-20" HDR
   p CLAUDE-USAGE-URL$ CURL-RUN dup HTTP-CODE ! ;

: CLAUDE-ANSWERED ( n -- ask-input )
   BODY-READ OBJECT? if construct ask-input fine exit then
   construct ask-input unreadable ;

: CLAUDE-ASK ( n -- ask-input ) {: p :}
   s" accessToken" CLAUDE-TOKEN 0 < if construct ask-input no-token exit then
   p CLAUDE-GET {: code :}
   code 0 < if construct ask-input unreachable exit then
   code 200 = if p CLAUDE-ANSWERED exit then
   code 401 = if construct ask-input rejected exit then
   code 403 = p BODY-READ NO-PLAN? and if construct ask-input no-plan exit then
   code 429 = if construct ask-input throttled exit then
   construct ask-input other ;

\ the profile is read with the token CLAUDE-ASK left in VAL-BUF
: CLAUDE-PROFILE ( n -- profile-input ) {: p :}
   p KIBA-UA$ CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   p CLAUDE-PROFILE-URL$ CURL-RUN 200 <> if construct profile-input limited exit then
   p BODY-READ FREE-PLAN? if construct profile-input free exit then
   construct profile-input limited ;

: CLAUDE-LIVE-STALE$ ( -- ptr u8 n )
   s" access token expired; Claude Code refreshes it on its next run" ;

: CLAUDE-NO-GRANT$ ( -- ptr u8 n )
   s" access token expired and no refresh token is saved; log in again" ;

: CLAUDE-TOKEN-NOTE$ ( -- ptr u8 n )
   s" Anthropic's token endpoint" HTTP-CODE @ HTTP-NOTE ;

: CLAUDE-ON-HOLD$ ( -- ptr u8 n )
   APPEAL$ {: a u :}
   SB-RESET s" account on hold and cannot use Claude Code; view details or appeal at " SB-APPEND
   a u SB-APPEND SB$ ;

: CLAUDE-REFUSED$ ( -- ptr u8 n )
   HTTP-CODE @ DETAIL$ {: a u :}
   SB-RESET s" access token expired and the refresh was refused (" SB-APPEND
   a u SB-APPEND s" ); log in again" SB-APPEND SB$ ;

: CLAUDE-REJECTED$ ( -- ptr u8 n ) s" login rejected by Anthropic; log in again" ;

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

: CLAUDE-FINE ( n -- ) {: p :}
   construct usage-state ok s" " SAY
   p BODY-READ {: b bu :}
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
: CLAUDE-THROTTLE-READ ( n -- ) BODY-READ MESSAGE! ;

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
: CODEX-USAGE-URL$ ( -- ptr u8 n ) s" https://chatgpt.com/backend-api/wham/usage" ;
: CODEX-TOKEN-URL$ ( -- ptr u8 n ) s" https://auth.openai.com/oauth/token" ;
: CODEX-CLIENT-ID$ ( -- ptr u8 n ) s" app_EMoamEEZ73f0CkXaXp7hrann" ;
: TOKENS-KEY$ ( -- ptr u8 n ) s" tokens" ;

\ the integer member f of the window at k, which CODEX-WINDOW found; 0 when
\ absent or not an integer
: WINDOW-INT ( ptr u8 n ptr u8 n ptr u8 n -- n ) {: d du k ku f fu :}
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT drop
   k ku KEY-OBJECT drop
   f fu KEY-WHOLE OR-ZERO swap JSON:READ-CLOSE ;

\ the window at key inside rate_limit: used percent, window seconds, reset epoch
: CODEX-WINDOW ( ptr u8 n ptr u8 n -- n n n ) {: d du k ku :}
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
: WINDOW-LABEL$ ( n -- ptr u8 n )
   21600 <= if SESSION-LABEL$ exit then
   WEEKLY-LABEL$ ;

: EPOCH>RESET$ ( n -- ptr u8 n )
   dup 0 <= if drop RESET-BUF 0 exit then
   RESET-BUF RESET-CAP DATE:FORMAT-EPOCH-UTC ;

: CODEX-WINDOW+ ( ptr u8 n ptr u8 n -- ) {: d du k ku :}
   d du k ku CODEX-WINDOW {: h secs at :}
   h 0 < if exit then
   secs WINDOW-LABEL$ h at EPOCH>RESET$ DB-LIMIT+ ;

: CODEX-LIMITS ( ptr u8 n -- ) {: d du :}
   d du s" primary_window" CODEX-WINDOW+
   d du s" secondary_window" CODEX-WINDOW+ ;

\ the limit-reset credits the answer reports, when it says anything of them
: CODEX-RESETS ( ptr u8 n -- ) {: d du :}
   d du s" rate_limit_reset_credits" s" available_count" DOC-INT2 0= if drop exit then
   s" " s" " DB-RESETS! ;

\ the account's current plan, which the login's id_token only knew at sign-in
: CODEX-PLAN ( ptr u8 n -- ) {: d du :}
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
: CODEX-TOKEN ( ptr u8 n -- n ) {: k ku :}
   SDOC$ OBJECT? 0= if -1 exit then
   SDOC$ TOKENS-KEY$ k ku VAL-BUF 4096 DOC-STR2 dup 0 >= if dup VAL-U ! then ;

\ an API-key login without an id_token has no usage windows
: CODEX-KEYED ( n -- key-input ) drop
   SDOC$ OBJECT? 0= if construct key-input tokens exit then
   SDOC$ CODEX-API-KEY? 0= if construct key-input tokens exit then
   SDOC$ TOKENS-KEY$ s" id_token" KIND2 JSON:T-STR = if construct key-input tokens exit then
   construct key-input api-key ;

\ the usage call with the access token CODEX-TOKEN left in VAL-BUF
: CODEX-GET ( n -- n ) {: p :}
   SDOC$ TOKENS-KEY$ s" account_id" ACCT-ID-BUF 128 DOC-STR2 0 max ACCT-ID-U !
   p s" codex-cli" CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   ACCT-ID-U @ 0 > if s" ChatGPT-Account-Id" ACCT-ID-BUF ACCT-ID-U @ HDR then
   p CODEX-USAGE-URL$ CURL-RUN dup HTTP-CODE ! ;

: CODEX-ANSWERED? ( n -- bool ) BODY-READ OBJECT? ;

: CODEX-REJECTED-FIRST ( n -- first-input ) {: p :}
   PROBE-LIVE @ if construct first-input rejected-live exit then
   p BODY-READ {: b bu :}
   b bu OBJECT? 0= if construct first-input rejected-saved exit then
   b bu s" error" s" code" s" token_revoked" STR2-IS? if construct first-input rejected-revoked exit then
   construct first-input rejected-saved ;

: CODEX-ANSWERED-FIRST ( n -- first-input )
   CODEX-ANSWERED? if construct first-input fine exit then
   construct first-input unreadable ;

: CODEX-FIRST ( n -- first-input ) {: p :}
   s" access_token" CODEX-TOKEN 0 < if construct first-input no-token exit then
   p CODEX-GET {: code :}
   code 0 < if construct first-input unreachable exit then
   code 200 = if p CODEX-ANSWERED-FIRST exit then
   code 401 = if p CODEX-REJECTED-FIRST exit then
   code 429 = if construct first-input throttled exit then
   construct first-input other ;

: CODEX-GRANT-BODY ( -- ptr u8 n )
   JSON-OPEN
   JSON:WRITE-OBJECT-START
   s" client_id" CODEX-CLIENT-ID$ JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" grant_type" s" refresh_token" JSON:WRITE-FIELD-S JSON:WRITE-COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON:WRITE-FIELD-S
   JSON:WRITE-OBJECT-END JSON:WRITTEN$ ;

\ the answer b's tokens and the refresh time spliced in; its access token is
\ in VAL-BUF
: CODEX-SPLICE ( ptr u8 n -- ) {: b bu :}
   SPLICE-BEGIN
   TOKENS-KEY$ s" access_token" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   b bu s" refresh_token" VAL-BUF 4096 DOC-STR1 dup 0 >= if
      VAL-U ! TOKENS-KEY$ s" refresh_token" VAL-BUF VAL-U @ LITERAL$ CFG-SET2
   else drop then
   b bu s" id_token" TOK-BUF BUF-CAP DOC-STR1 dup 0 >= if
      TOK-U ! TOKENS-KEY$ s" id_token" TOK-BUF TOK-U @ LITERAL$ CFG-SET2
   else drop then
   s" last_refresh" PROBE-AT @ RESET-BUF RESET-CAP DATE:FORMAT-EPOCH-UTC LITERAL$ CFG-SET
   SPLICE-END ;

: CODEX-RENEWED ( n -- codex-renew-input )
   BODY-READ {: b bu :}
   b bu OBJECT? 0= if construct codex-renew-input unusable exit then
   b bu s" access_token" VAL-BUF 4096 DOC-STR1 dup 0 < if drop construct codex-renew-input unusable exit then
   VAL-U !
   b bu CODEX-SPLICE
   construct codex-renew-input renewed ;

: CODEX-RENEW ( n -- codex-renew-input ) {: p :}
   s" refresh_token" CODEX-TOKEN 0 < if construct codex-renew-input no-grant exit then
   p CODEX-GRANT-BODY CODEX-TOKEN-URL$ TOKEN-POST {: code :}
   code 0 < if construct codex-renew-input unreachable exit then
   code 200 = if p CODEX-RENEWED exit then
   code REFUSED-STATUS? if construct codex-renew-input refused exit then
   construct codex-renew-input answered ;

: CODEX-ANSWERED-AGAIN ( n -- retry-input )
   CODEX-ANSWERED? if construct retry-input fine exit then
   construct retry-input unreadable ;

: CODEX-RETRY ( n -- retry-input ) {: p :}
   s" access_token" CODEX-TOKEN 0 < if construct retry-input no-token exit then
   p CODEX-GET {: code :}
   code 0 < if construct retry-input unreachable exit then
   code 200 = if p CODEX-ANSWERED-AGAIN exit then
   code 401 = if construct retry-input rejected exit then
   code 429 = if construct retry-input throttled exit then
   construct retry-input other ;

: NO-ACCESS$ ( -- ptr u8 n ) s" no access token saved" ;
: CODEX-LIVE-REJECTED$ ( -- ptr u8 n ) s" access token rejected; run codex once to refresh it" ;
: CODEX-REJECTED$ ( -- ptr u8 n ) s" login rejected by OpenAI; log in again" ;
: CODEX-TOKEN-NOTE$ ( -- ptr u8 n ) s" OpenAI's token endpoint" HTTP-CODE @ HTTP-NOTE ;

: CODEX-NO-GRANT$ ( -- ptr u8 n )
   s" access token rejected and no refresh token is saved; log in again" ;

: CODEX-REFUSED$ ( -- ptr u8 n )
   s" access token rejected and the refresh was refused; log in again" ;

: CODEX-REVOKED$ ( -- ptr u8 n )
   s" login revoked by a sign-out at chatgpt.com or in codex; log in again" ;

: CODEX-API-KEY-NOTE ( n -- ) drop
   construct usage-state unknown s" API-key login: no usage windows to read" SAY ;

: CODEX-NO-TOKEN ( n -- ) drop
   construct usage-state error NO-ACCESS$ SAY ;

: CODEX-USAGE-ANSWER ( n -- ) drop
   construct usage-state error s" OpenAI's usage endpoint" HTTP-CODE @ HTTP-NOTE SAY ;

: CODEX-FINE ( n -- ) {: p :}
   construct usage-state ok s" " SAY
   p BODY-READ {: b bu :}
   b bu CODEX-LIMITS
   b bu CODEX-RESETS
   b bu CODEX-PLAN ;

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
: PROBE-BEGIN ( ptr u8 n bool -- ) {: d du live :}
   epoch-seconds PROBE-AT !
   live PROBE-LIVE !
   false DOC-NEW ! -1 PLAN-NAMED-U ! -1 HTTP-CODE !
   d du SDOC-BUF SDOC-U BUF-CAP SPAN! ;

: PROBE-RUN ( n -- ) {: p :}
   p case
     P-CLAUDE of p construct claude-step fresh CLAUDE-EXCHANGE endof
     P-CODEX of p construct codex-step keyed CODEX-EXCHANGE endof
     E-SW-PROVIDER throw
   endcase ;

\ ---- limit resets ---------------------------------------------------------------
\ One reset of a saved login's offer is spent, as kiba-mac's redeem spends it.
\ A saved login's token is refreshed when it has expired (Claude), or once
\ when the first send is rejected; the live login's never is. The answer's
\ word is the outcome; any other answer fails with E-SW-REMOTE and a note.
: CLAUDE-ORGS-URL$ ( -- ptr u8 n ) s" https://api.anthropic.com/api/organizations/" ;
: CLAUDE-RESET-PATH$ ( -- ptr u8 n ) s" /reset_rate_limits" ;
: CODEX-CONSUME-URL$ ( -- ptr u8 n ) s" https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume" ;

public
ENUM reset-outcome reset not-limited already-used no-credit cooldown ineligible unavailable ;ENUM
private

ENUM claude-reset-step freshening sending renewing resending answered failed ;ENUM
ENUM codex-reset-step sending renewing renewing-revoked resending answered failed ;ENUM
ENUM reset-reply no-token unreachable fine unknown unreadable rejected-live rejected-saved rejected-revoked throttled other ;ENUM

1024 constant RESET-BODY-CAP
TYPED-VARIABLE RESET-GOT reset-outcome
create RESET-URL PATH-CAP allot              variable RESET-URL-U
create RESET-BODY RESET-BODY-CAP allot       variable RESET-BODY-U
create RESET-WORD TEXT-CAP allot             variable RESET-WORD-U
create REMOTE-NOTE TEXT-CAP allot            variable REMOTE-NOTE-U
create RID-RAW 16 allot
create RID-BUF 36 allot

: RESET-URL$ ( -- ptr u8 n ) RESET-URL RESET-URL-U @ ;
: RESET-BODY$ ( -- ptr u8 n ) RESET-BODY RESET-BODY-U @ ;
: RESET-WORD$ ( -- ptr u8 n ) RESET-WORD RESET-WORD-U @ ;
: REMOTE! ( ptr u8 n -- ) REMOTE-NOTE REMOTE-NOTE-U TEXT-CAP SPAN! ;

\ byte i of the id as two uppercase digits, after a dash before bytes 4,
\ 6, 8 and 10
: RID-BYTE ( n -- ) {: i :}
   i 4 = i 6 = or i 8 = or i 10 = or if $2D SB-APPEND-C then
   RID-RAW i + c@ 2 FMT:SB-HEX-WIDTH ;

\ a random version 4 UUID in uppercase, as UUID().uuidString writes it:
\ each request is told apart by it
: REQUEST-ID$ ( -- ptr u8 n )
   RID-RAW 16 ENTROPY:FILL
   RID-RAW 6 + c@ $0F and $40 or RID-RAW 6 + c!
   RID-RAW 8 + c@ $3F and $80 or RID-RAW 8 + c!
   SB-RESET 16 0 ?do i RID-BYTE loop
   SB$ {: s su :}
   s RID-BUF su BYTE-COPY
   RID-BUF su ;

\ the writer's text kept as the request body, which a refresh's own body
\ would overwrite in the writer
: BODY! ( ptr JSON:writer -- )
   JSON:WRITTEN$ RESET-BODY RESET-BODY-U RESET-BODY-CAP SPAN! ;

: BANKED-BODY ( ptr u8 n -- ) {: g gu :}
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
: SB-SEGMENT ( ptr u8 n -- ) {: s su :}
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
: RESET-WHAT$ ( n -- ptr u8 n )
   P-CLAUDE = if s" Anthropic's reset endpoint" exit then
   s" OpenAI's reset endpoint" ;

\ the member of a 200 answer that holds the result word
: RESET-FIELD$ ( n -- ptr u8 n )
   P-CLAUDE = if s" result" exit then
   s" code" ;

\ the access token in VAL-BUF; its length, -1 when there is none
: RESET-TOKEN ( n -- n )
   P-CLAUDE = if s" accessToken" CLAUDE-TOKEN exit then
   s" access_token" CODEX-TOKEN ;

: RESET-POST ( n ptr u8 n -- n ) {: p url uu :}
   p RESET-BODY$ url uu POST-JSON
   p REQ$ FS:REMOVE-FILE
   dup HTTP-CODE ! ;

: CLAUDE-RESET-SEND ( -- n )
   P-CLAUDE CLAUDE-UA$ CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   s" anthropic-beta" s" oauth-2025-04-20" HDR
   P-CLAUDE RESET-URL$ RESET-POST ;

: CODEX-RESET-SEND ( -- n )
   SDOC$ TOKENS-KEY$ s" account_id" ACCT-ID-BUF 128 DOC-STR2 0 max ACCT-ID-U !
   P-CODEX s" codex-cli" CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   ACCT-ID-U @ 0 > if s" ChatGPT-Account-Id" ACCT-ID-BUF ACCT-ID-U @ HDR then
   P-CODEX RESET-URL$ RESET-POST ;

: RESET-SEND ( n -- n )
   P-CLAUDE = if CLAUDE-RESET-SEND exit then
   CODEX-RESET-SEND ;

: GOT ( reset-outcome -- bool ) RESET-GOT ! true ;
: WORD-IS? ( ptr u8 n -- bool ) RESET-WORD$ STR= ;

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
   p BODY-READ {: b bu :}
   b bu OBJECT? 0= if construct reset-reply unreadable exit then
   b bu p RESET-FIELD$ RESET-WORD TEXT-CAP DOC-STR1 0 max RESET-WORD-U !
   p P-CLAUDE = if CLAUDE-WORD? else CODEX-WORD? then
   if construct reset-reply fine exit then
   construct reset-reply unknown ;

\ a 401: the live login's token is its CLI's to renew; a saved one's is
\ renewed, and a refused renewal after a revoked token means a sign-out
: REJECTION ( n -- reset-reply ) {: p :}
   PROBE-LIVE @ if construct reset-reply rejected-live exit then
   p BODY-READ {: b bu :}
   b bu OBJECT? 0= if construct reset-reply rejected-saved exit then
   b bu s" error" s" code" s" token_revoked" STR2-IS? if construct reset-reply rejected-revoked exit then
   construct reset-reply rejected-saved ;

: RESET-SENSE ( n -- reset-reply ) {: p :}
   p RESET-TOKEN 0 < if construct reset-reply no-token exit then
   p RESET-SEND {: code :}
   code 0 < if construct reset-reply unreachable exit then
   code 200 = if p RESET-ANSWERED exit then
   code 401 = if p REJECTION exit then
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

\ the usage record's windows on one line
: .LIMITS ( -- )
   DB-LIMIT# 0 ?do
      i 0 > if s"  · " type then
      i DB-LIMIT-LABEL$ type s"  " type
      i DB-LIMIT-PERCENT FMT:.U s" %" type
   loop ;

\ a scratch path, for tests that check what is left on disk
: PSUB-PUBLIC$ ( n ptr u8 n -- ptr u8 n ) PSUB$ ;

EXPORT PROBE-PREPARE
EXPORT PROBE-CLEANUP

\ probes provider p's login document d du, live when the CLI is using it:
\ the outcome is the usage record, SDOC with the login (renewed when
\ PROBE-RENEWED?) and PROBED-PLAN$
: PROBE ( n ptr u8 n bool -- ) {: p d du live :}
   d du live PROBE-BEGIN
   p PROBE-PREPARE
   [: p PROBE-RUN ;] [: p PROBE-CLEANUP ;] finally ;

\ the outcome of a probe that threw: an error with the reason as its note;
\ a login renewed before the throw is kept
: PROBE-FAILED ( ptr u8 n -- ) {: a u :}
   -1 PLAN-NAMED-U !
   construct usage-state error a u SAY ;

: PROBE-RENEWED? ( -- bool ) DOC-NEW @ ;

\ the plan the provider named; length -1 when it named none
: PROBED-PLAN$ ( -- ptr u8 n ) PLAN-NAMED PLAN-NAMED-U @ ;

\ spends one limit reset of provider p's saved row r, whose usage holds the
\ offer, live when the CLI is using it: RESET-OUTCOME is what the provider
\ made of it and SDOC the login (renewed when PROBE-RENEWED?). E-SW-REMOTE
\ with REMOTE-NOTE$ when the provider spent none, E-SW-NO-RESETS for a
\ program kiba does not know, E-SW-JSON for a Claude row with no organization
: REDEEM ( n n bool -- ) {: p r live :}
   r DB-ROW-LOGIN$ live PROBE-BEGIN
   p r RESET-PREPARE
   p PROBE-PREPARE
   [: p RESET-RUN ;] [: p PROBE-CLEANUP ;] finally ;

: RESET-OUTCOME ( -- reset-outcome ) RESET-GOT @ ;

\ why the last reset request spent nothing
: REMOTE-NOTE$ ( -- ptr u8 n ) REMOTE-NOTE REMOTE-NOTE-U @ ;

;package
