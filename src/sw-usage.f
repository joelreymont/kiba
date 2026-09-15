\ sw-usage.f - per-account rate limits, read straight from each provider's
\ usage endpoint with curl.
\
\ Anthropic: GET https://api.anthropic.com/api/oauth/usage with the account's
\ OAuth access token. OpenAI: GET https://chatgpt.com/backend-api/wham/usage
\ with the account's access token and account id. A saved (non-live) account
\ is refreshed once through the provider's token endpoint when its token has
\ expired (Claude) or is rejected (Codex), and the new tokens replace the
\ slot's. The live account is
\ never refreshed here: its CLI owns that token, and rotating it underneath a
\ running session would log the session out.
require ../src/sw-store.f
require ../src/sw-run.f
require lib/time.f
require lib/date.f
require lib/json-write.f

package SW

8 constant LIM-MAX
64 constant LIM-LABEL-CAP
40 constant LIM-RESET-CAP
4096 constant HDR-CAP
20 constant HTTP-TIMEOUT-SEC

create LIM-LABELS LIM-MAX LIM-LABEL-CAP * allot
create LIM-LABEL-U LIM-MAX cells allot
create LIM-RESETS LIM-MAX LIM-RESET-CAP * allot
create LIM-RESET-U LIM-MAX cells allot
create LIM-PCTS LIM-MAX cells allot
variable LIM-N
create NOTE-BUF 256 allot           variable NOTE-U
variable USAGE-AT                   \ epoch seconds of the parsed usage record

create PROBE-BUF FS-PATH-CAP allot  variable PROBE-U   \ <store>/probe
create PSUB-BUF FS-PATH-CAP allot   variable PSUB-U    \ a file inside it
create UFILE-BUF FS-PATH-CAP allot  variable UFILE-U   \ <slot>/usage.json
create HDR-BUF HDR-CAP allot        variable HDR-U     \ one curl -H value
create ACCT-ID-BUF 128 allot        variable ACCT-ID-U
create VAL-BUF 4096 allot           variable VAL-U     \ a decoded response string
create RESET-BUF LIM-RESET-CAP allot
variable OUT-FD
variable HTTP-CODE
variable PROBE-LIVE?                \ bool: the account being probed is the live one
variable PROBE-REVOKED              \ bool: the provider says this login is gone for good

: USAGE-NAME$ ( -- ptr u8 n ) s" usage.json" ;

: LIM-LABEL-SLOT ( n -- ptr u8 ) LIM-LABEL-CAP * LIM-LABELS + ;
: LIM-RESET-SLOT ( n -- ptr u8 ) LIM-RESET-CAP * LIM-RESETS + ;
: LIM-LABEL-U-CELL ( n -- ptr n ) cells LIM-LABEL-U + ;
: LIM-RESET-U-CELL ( n -- ptr n ) cells LIM-RESET-U + ;
: LIM-PCT-CELL ( n -- ptr n ) cells LIM-PCTS + ;

: LIM-RESET ( -- )
   0 LIM-N ! 0 NOTE-U ! -1 USAGE-AT ! ;

: NOTE! ( ptr u8 n -- )
   NOTE-BUF NOTE-U 256 SPAN! ;

: SESSION-LABEL$ ( -- ptr u8 n ) s" Session (5-hour)" ;
: WEEKLY-LABEL$ ( -- ptr u8 n ) s" Weekly (7-day)" ;

\ ---- decimal parsing -----------------------------------------------------------
: DIGIT ( n -- n ) $30 - ;

: DIGIT? ( n -- bool ) dup $30 >= swap $39 <= and ;

variable FP-ACC
variable FP-I
variable FP-MULT
variable FP-GOT

: FP-DIGIT-AT? ( ptr u8 n -- bool ) {: a u :}
   FP-I @ u >= if false exit then
   FP-I @ a + c@ DIGIT? ;

: FP-DIGIT@ ( ptr u8 -- n )
   FP-I @ + c@ DIGIT ;

$E8D4A51000 constant FP-MAX             \ 10^12: no percentage is larger

: FP-INTEGER ( ptr u8 n -- ) {: a u :}
   begin a u FP-DIGIT-AT? while
      FP-ACC @ 10 * a FP-DIGIT@ + FP-ACC !
      FP-ACC @ FP-MAX > if -1 FP-I ! exit then
      1 FP-I +!
   repeat ;

\ two fraction digits count; the third rounds, half up
: FP-FRACTION ( ptr u8 n -- ) {: a u :}
   100 FP-MULT ! 0 FP-GOT !
   begin a u FP-DIGIT-AT? while
      FP-MULT @ 10 / FP-MULT !
      FP-MULT @ 0 > if FP-ACC @ FP-MULT @ a FP-DIGIT@ * + FP-ACC ! then
      FP-MULT @ 0= FP-GOT @ 0= and if
         a FP-DIGIT@ 5 >= if 1 FP-ACC +! then
         1 FP-GOT !
      then
      1 FP-I +!
   repeat ;

\ round(x * 100) for a decimal literal such as 0.5625 or 56.25; -1 when malformed
: HUNDREDTHS ( ptr u8 n -- n ) {: a u :}
   0 FP-ACC ! 0 FP-I !
   a u FP-INTEGER
   FP-I @ 0 <= if -1 exit then
   FP-ACC @ 100 * FP-ACC !
   FP-I @ u < if
      FP-I @ a + c@ DOT <> if -1 exit then
      1 FP-I +!
      a u FP-FRACTION
   then
   FP-I @ u <> if -1 exit then
   FP-ACC @ ;

\ ---- limit table ---------------------------------------------------------------
\ windows past the table's capacity are dropped rather than failing the probe
: LIM+ ( ptr u8 n n ptr u8 n -- ) {: l lu pct r ru :}
   LIM-N @ LIM-MAX >= if exit then
   LIM-N @ {: i :}
   l lu i LIM-LABEL-SLOT i LIM-LABEL-U-CELL LIM-LABEL-CAP SPAN!
   r ru i LIM-RESET-SLOT i LIM-RESET-U-CELL LIM-RESET-CAP SPAN!
   pct i LIM-PCT-CELL !
   i 1+ LIM-N ! ;

\ ---- our own usage file --------------------------------------------------------
create KEY-BUF 64 allot

: LIM-FIELD ( JR:reader ptr u8 n n -- JR:reader ) {: k ku i :}
   JR:TOKEN {: t :}
   k ku s" label" STR= t JR:T-STR = and if i LIM-LABEL-SLOT LIM-LABEL-CAP JR:STR i LIM-LABEL-U-CELL ! exit then
   k ku s" resetsAt" STR= t JR:T-STR = and if i LIM-RESET-SLOT LIM-RESET-CAP JR:STR i LIM-RESET-U-CELL ! exit then
   k ku s" percent" STR= t JR:T-INT = and if JR:INT i LIM-PCT-CELL ! exit then
   JR:SKIP-VALUE ;

: LIM-OBJECT ( JR:reader -- JR:reader )
   LIM-N @ LIM-MAX >= if JR:SKIP-VALUE exit then
   s" " -1 s" " LIM+
   LIM-N @ 1- {: i :}
   begin JR:NEXT JR:T-OBJ-END <> while
      JR:TOKEN JR:T-KEY <> if E-SW-JSON throw then
      KEY-BUF 64 JR:STR {: ku :}
      JR:NEXT drop
      KEY-BUF ku i LIM-FIELD
   repeat ;

: LIM-ARRAY ( JR:reader -- JR:reader )
   begin JR:NEXT JR:T-ARR-END <> while
      JR:TOKEN JR:T-OBJ <> if E-SW-JSON throw then
      LIM-OBJECT
   repeat ;

: PARSE-USAGE-FILE ( ptr u8 n -- ) {: d du :}
   0 LIM-N !
   d du OPEN-DOC ENTER-OBJECT
   s" limits" JR:FIND-KEY 0= if JR:CLOSE exit then
   JR:TOKEN JR:T-ARR <> if JR:CLOSE exit then
   LIM-ARRAY
   JR:CLOSE ;

: USAGE-FILE$ ( n ptr u8 n -- ptr u8 n ) {: p a u :}
   p a u USAGE-NAME$ SLOT-FILE$ UFILE-BUF UFILE-U PATH!
   UFILE-BUF UFILE-U @ ;

: LIM-JSON ( n n -- n ) {: i written :}
   written 0 > if JSON-WRITE:COMMA then
   JSON-WRITE:OBJECT-START
   s" label" i LIM-LABEL-SLOT i LIM-LABEL-U-CELL @ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" percent" i LIM-PCT-CELL @ JSON-WRITE:FIELD-U JSON-WRITE:COMMA
   s" resetsAt" i LIM-RESET-SLOT i LIM-RESET-U-CELL @ JSON-WRITE:FIELD-S
   JSON-WRITE:OBJECT-END
   written 1+ ;

\ the table plus a note become the slot's usage.json; a window whose figure
\ could not be read is left out rather than written as zero
: WRITE-USAGE ( n ptr u8 n -- ) {: p a u :}
   JSON-WRITE:RESET
   JSON-WRITE:OBJECT-START
   s" fetchedAt" TIME:EPOCH-SECONDS JSON-WRITE:FIELD-U JSON-WRITE:COMMA
   s" note" NOTE-BUF NOTE-U @ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" limits" JSON-WRITE:KEY JSON-WRITE:ARRAY-START
   0 0 begin over LIM-N @ < while
      over dup LIM-PCT-CELL @ 0 >= if swap LIM-JSON else drop then
      swap 1+ swap
   repeat 2drop
   JSON-WRITE:ARRAY-END
   JSON-WRITE:OBJECT-END
   p a u USAGE-FILE$ JSON-WRITE:$ WRITE-PRIVATE ;

\ ---- scratch files ---------------------------------------------------------------
: PROBE$ ( -- ptr u8 n )
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /probe" SB-APPEND
   SB$ PROBE-BUF PROBE-U PATH!
   PROBE-BUF PROBE-U @ ;

: PSUB$ ( ptr u8 n -- ptr u8 n ) {: a u :}
   PROBE$ 2drop
   SB-RESET PROBE-BUF PROBE-U @ SB-APPEND a u SB-APPEND
   SB$ PSUB-BUF PSUB-U PATH!
   PSUB-BUF PSUB-U @ ;

: BODY$ ( -- ptr u8 n ) s" /body.json" PSUB$ ;
: CODE$ ( -- ptr u8 n ) s" /code.txt" PSUB$ ;
: REQ$ ( -- ptr u8 n ) s" /request.json" PSUB$ ;

: PROBE-CLEANUP ( -- )
   BODY$ FILE? if BODY$ REMOVE-FILE then
   CODE$ FILE? if CODE$ REMOVE-FILE then
   REQ$ FILE? if REQ$ REMOVE-FILE then ;

: PROBE-PREPARE ( -- )
   PROBE$ ENSURE-PRIVATE
   PROBE-CLEANUP ;

\ ---- curl --------------------------------------------------------------------------
\ Every request is one curl process: the body lands in a file, the HTTP status
\ on stdout, which is redirected into a second file before exec.
: HDR ( ptr u8 n ptr u8 n -- ) {: name nu val vu :}
   nu 2 + vu + HDR-CAP > if E-SW-CAPACITY throw then
   name HDR-BUF nu BYTE-COPY
   $3A HDR-BUF nu + c!
   $20 HDR-BUF nu + 1+ c!
   val HDR-BUF nu + 2 + vu BYTE-COPY
   s" -H" ARG+
   HDR-BUF nu 2 + vu + ARG+ ;

create BEARER-BUF HDR-CAP allot

\ the token usually sits in VAL-BUF, so the header value is built elsewhere
: BEARER ( ptr u8 n -- ) {: t tu :}
   tu 7 + HDR-CAP > if E-SW-CAPACITY throw then
   s" Bearer " BEARER-BUF swap BYTE-COPY
   t BEARER-BUF 7 + tu BYTE-COPY
   s" Authorization" BEARER-BUF tu 7 + HDR ;

: CURL-BEGIN ( -- )
   s" curl" RESOLVE
   PROC-ARGV-RESET
   s" -sS" ARG+
   s" -m" ARG+
   SB-RESET HTTP-TIMEOUT-SEC FMT:SB-U SB$ ARG+
   s" -o" ARG+ BODY$ ARG+
   s" -w" ARG+ s" %{http_code}" ARG+
   s" Accept" s" application/json" HDR ;

: EXEC-CURL ( ptr u8 ptr ptr u8 -- ) {: pathz argv :}
   OUT-FD @ 1 dup2 0 < if s" switcher: dup2 failed" 127 die then
   pathz argv ENVP-BASE execve drop
   s" switcher: could not start curl" 127 die ;

\ run the staged curl; the parsed status code, or -1 when curl itself failed
: CURL-RUN ( ptr u8 n -- n ) {: url uu :}
   url uu ARG+
   EXE$ >LEN PROC-ARGV-PREPARE {: pathz argv :}
   CODE$ OPEN-PRIVATE OUT-FD !
   PROC-FORK:CHECKED {: pid :}
   pid PID>N 0= if pathz argv EXEC-CURL then
   PROC-ARGV-RESET
   OUT-FD @ close
   pid PROC-WAIT-RC MATCH result
     ok OF ENDOF
     err OF ENDOF
   ;MATCH {: rc :}
   rc 0<> if -1 exit then
   CODE$ FILE? 0= if -1 exit then
   CODE$ OBJ-BUF OBJ-U READ-INTO STR>NUMBER? MATCH option
     none OF -1 ENDOF
     some OF ENDOF
   ;MATCH ;

: BODY-READ ( -- ptr u8 n )
   BODY$ FILE? 0= if OBJ-BUF 0 exit then
   BODY$ OBJ-BUF OBJ-U READ-INTO ;

: POST-JSON ( ptr u8 n -- n ) {: url uu :}
   REQ$ {: r ru :}
   r ru JSON-WRITE:$ WRITE-PRIVATE
   s" -X" ARG+ s" POST" ARG+
   s" Content-Type" s" application/json" HDR
   s" --data-binary" ARG+
   SB-RESET $40 SB-APPEND-C r ru SB-APPEND SB$ ARG+
   url uu CURL-RUN ;

: HTTP-NOTE ( ptr u8 n n -- ) {: what wu code :}
   SB-RESET what wu SB-APPEND
   code 0 < if s"  could not be reached" SB-APPEND else
      s"  answered " SB-APPEND code FMT:SB-U
   then
   SB$ NOTE! ;

\ ---- rewriting a login file -----------------------------------------------------------
\ CFG holds the document; each replacement splices OUT and copies it back.
: SPLICE-CFG ( n n ptr u8 n -- ) {: off len v vu :}
   0 OUT-U !
   off vu + CFG-U @ off len + - + BUF-CAP > if E-SW-CAPACITY throw then
   CFG-BUF OUT-BUF off BYTE-COPY
   v OUT-BUF off + vu BYTE-COPY
   CFG-BUF off len + + OUT-BUF off vu + + CFG-U @ off len + - BYTE-COPY
   off vu + CFG-U @ off len + - + OUT-U !
   OUT-BUF CFG-BUF OUT-U @ BYTE-COPY
   OUT-U @ CFG-U ! ;

\ replace the top-level key's value with a JSON literal; absent keys stay absent
: CFG-REPLACE ( ptr u8 n ptr u8 n -- ) {: k ku v vu :}
   CFG$ k ku DOC-VALUE-SPAN? 0= if 2drop exit then
   v vu SPLICE-CFG ;

\ the same one level down, inside the object at k1
: CFG-REPLACE2 ( ptr u8 n ptr u8 n ptr u8 n -- ) {: k1 k1u k2 k2u v vu :}
   CFG$ k1 k1u DOC-OBJ-SPAN? 0= if 2drop exit then
   {: off1 len1 :}
   CFG-BUF off1 + len1 k2 k2u DOC-VALUE-SPAN? 0= if 2drop exit then
   {: off2 len2 :}
   off1 off2 + len2 v vu SPLICE-CFG ;

\ a decoded string as a JSON string literal, in the writer buffer
: LITERAL$ ( ptr u8 n -- ptr u8 n )
   JSON-WRITE:RESET JSON-WRITE:STRING JSON-WRITE:$ ;

: NUMBER$ ( n -- ptr u8 n )
   SB-RESET FMT:SB-INT SB$ ;

\ ---- Anthropic -----------------------------------------------------------------------
: CLAUDE-USAGE-URL$ ( -- ptr u8 n ) s" https://api.anthropic.com/api/oauth/usage" ;
: CLAUDE-TOKEN-URL$ ( -- ptr u8 n ) s" https://platform.claude.com/v1/oauth/token" ;
: CLAUDE-CLIENT-ID$ ( -- ptr u8 n ) s" 9d1c250a-e61b-44d9-88ed-5944d1962f5e" ;
: CREDS-KEY$ ( -- ptr u8 n ) s" claudeAiOauth" ;

: BUCKET-PCT ( JR:reader -- JR:reader n )
   JR:TOKEN dup JR:T-INT = swap JR:T-FLOAT = or 0= if -1 exit then
   JR:SPAN$ HUNDREDTHS ;

: BUCKET-RESET ( JR:reader -- JR:reader ptr u8 n )
   JR:TOKEN JR:T-STR <> if RESET-BUF 0 exit then
   RESET-BUF LIM-RESET-CAP JR:STR RESET-BUF swap ;

\ one bucket object {utilization, resets_at} at key; hundredths and reset text
: CLAUDE-BUCKET ( ptr u8 n ptr u8 n -- n ptr u8 n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT 0= if JR:CLOSE -1 RESET-BUF 0 exit then
   s" utilization" JR:FIND-KEY 0= if JR:CLOSE -1 RESET-BUF 0 exit then
   BUCKET-PCT {: h :}
   JR:CLOSE
   d du OPEN-DOC ENTER-OBJECT
   k ku KEY-OBJECT drop
   s" resets_at" JR:FIND-KEY 0= if JR:CLOSE h RESET-BUF 0 exit then
   BUCKET-RESET {: r ru :}
   JR:CLOSE
   h r ru ;

\ utilization is a percentage (37.0 means 37%); hundredths round half up
: SCALED ( n -- n ) {: h :}
   h 0 < if -1 exit then
   h 50 + 100 / ;

create SESSION-RESET LIM-RESET-CAP allot   variable SESSION-RESET-U
create WEEKLY-RESET LIM-RESET-CAP allot    variable WEEKLY-RESET-U

: CLAUDE-LIMITS ( ptr u8 n -- ) {: d du :}
   0 LIM-N !
   d du s" five_hour" CLAUDE-BUCKET SESSION-RESET SESSION-RESET-U LIM-RESET-CAP SPAN! {: sh :}
   d du s" seven_day_oauth_apps" CLAUDE-BUCKET {: wh0 r0 r0u :}
   wh0 0 < if d du s" seven_day" CLAUDE-BUCKET else wh0 r0 r0u then
   WEEKLY-RESET WEEKLY-RESET-U LIM-RESET-CAP SPAN! {: wh :}
   sh 0 >= if SESSION-LABEL$ sh SCALED SESSION-RESET SESSION-RESET-U @ LIM+ then
   wh 0 >= if WEEKLY-LABEL$ wh SCALED WEEKLY-RESET WEEKLY-RESET-U @ LIM+ then ;

: CLAUDE-EXPIRED? ( -- bool )
   CFG$ CREDS-KEY$ s" expiresAt" DOC-INT2 {: ms :}
   ms 0 <= if false exit then
   ms 1000 / TIME:EPOCH-SECONDS 60 + < ;

\ a fresh token pair from the refresh grant, written into CFG
: CLAUDE-REFRESH ( -- bool )
   CFG$ CREDS-KEY$ s" refreshToken" VAL-BUF 4096 DOC-STR2 dup 0 < if drop false exit then VAL-U !
   JSON-WRITE:RESET
   JSON-WRITE:OBJECT-START
   s" grant_type" s" refresh_token" JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" client_id" CLAUDE-CLIENT-ID$ JSON-WRITE:FIELD-S
   JSON-WRITE:OBJECT-END
   CURL-BEGIN
   CLAUDE-TOKEN-URL$ POST-JSON {: code :}
   REQ$ REMOVE-FILE
   code 200 <> if false exit then
   BODY-READ {: b bu :}
   b bu s" access_token" VAL-BUF 4096 DOC-STR1 dup 0 < if drop false exit then VAL-U !
   CREDS-KEY$ s" accessToken" VAL-BUF VAL-U @ LITERAL$ CFG-REPLACE2
   b bu s" refresh_token" VAL-BUF 4096 DOC-STR1 dup 0 >= if
      VAL-U ! CREDS-KEY$ s" refreshToken" VAL-BUF VAL-U @ LITERAL$ CFG-REPLACE2
   else drop then
   b bu s" expires_in" DOC-INT1 {: secs :}
   secs 0 > if CREDS-KEY$ s" expiresAt" TIME:EPOCH-SECONDS secs + 1000 * NUMBER$ CFG-REPLACE2 then
   true ;

: CLAUDE-GET ( -- n )
   CFG$ CREDS-KEY$ s" accessToken" VAL-BUF 4096 DOC-STR2 dup 0 < if drop -2 exit then VAL-U !
   CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   s" anthropic-beta" s" oauth-2025-04-20" HDR
   CLAUDE-USAGE-URL$ CURL-RUN ;

\ the slot's credentials are in CFG; a refreshed pair is written back when live? is false
: CLAUDE-PROBE ( n ptr u8 n -- ) {: p a u :}
   LIM-RESET
   PROBE-LIVE? @ 0= CLAUDE-EXPIRED? and if
      CLAUDE-REFRESH if p a u CREDS-NAME$ SLOT-FILE$ CFG$ WRITE-PRIVATE then
   then
   CLAUDE-GET {: code :}
   code -2 = if s" no access token saved" NOTE! exit then
   code 200 = if BODY-READ CLAUDE-LIMITS exit then
   code 401 = if s" login expired or revoked: switch to it once, or add it again" NOTE! exit then
   code 429 = if s" Anthropic is rate limiting usage checks; try again later" NOTE! exit then
   s" Anthropic's usage endpoint" code HTTP-NOTE ;

\ ---- OpenAI ------------------------------------------------------------------------------
: CODEX-USAGE-URL$ ( -- ptr u8 n ) s" https://chatgpt.com/backend-api/wham/usage" ;
: CODEX-TOKEN-URL$ ( -- ptr u8 n ) s" https://auth.openai.com/oauth/token" ;
: CODEX-CLIENT-ID$ ( -- ptr u8 n ) s" app_EMoamEEZ73f0CkXaXp7hrann" ;
: TOKENS-KEY$ ( -- ptr u8 n ) s" tokens" ;

\ the window at key inside rate_limit: used percent, window seconds, reset epoch
: CODEX-WINDOW ( ptr u8 n ptr u8 n -- n n n ) {: d du k ku :}
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT 0= if JR:CLOSE -1 0 0 exit then
   k ku KEY-OBJECT 0= if JR:CLOSE -1 0 0 exit then
   s" used_percent" JR:FIND-KEY 0= if JR:CLOSE -1 0 0 exit then
   BUCKET-PCT {: h :}
   JR:CLOSE
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT drop
   k ku KEY-OBJECT drop
   s" limit_window_seconds" JR:FIND-KEY 0= if JR:CLOSE h 0 0 exit then
   JR:TOKEN JR:T-INT <> if JR:CLOSE h 0 0 exit then
   JR:INT {: secs :}
   JR:CLOSE
   d du OPEN-DOC ENTER-OBJECT
   s" rate_limit" KEY-OBJECT drop
   k ku KEY-OBJECT drop
   s" reset_at" JR:FIND-KEY 0= if JR:CLOSE h secs 0 exit then
   JR:TOKEN JR:T-INT <> if JR:CLOSE h secs 0 exit then
   JR:INT swap JR:CLOSE
   h secs rot ;

: WINDOW-LABEL$ ( n -- ptr u8 n )
   21600 <= if SESSION-LABEL$ exit then
   WEEKLY-LABEL$ ;

: EPOCH>RESET$ ( n -- ptr u8 n )
   dup 0 <= if drop RESET-BUF 0 exit then
   RESET-BUF LIM-RESET-CAP DATE:FORMAT-EPOCH-UTC ;

: CODEX-WINDOW+ ( ptr u8 n ptr u8 n -- ) {: d du k ku :}
   d du k ku CODEX-WINDOW {: h secs at :}
   h 0 < if exit then
   secs WINDOW-LABEL$ h 50 + 100 / at EPOCH>RESET$ LIM+ ;

: CODEX-LIMITS ( ptr u8 n -- ) {: d du :}
   0 LIM-N !
   d du s" primary_window" CODEX-WINDOW+
   d du s" secondary_window" CODEX-WINDOW+ ;

: CODEX-REVOKED? ( -- bool )
   BODY-READ s" error" s" code" VAL-BUF 4096 DOC-STR2 dup 0 < if drop false exit then
   VAL-BUF swap s" token_revoked" STR= ;

: CODEX-REFRESH ( -- bool )
   CFG$ TOKENS-KEY$ s" refresh_token" VAL-BUF 4096 DOC-STR2 dup 0 < if drop false exit then VAL-U !
   JSON-WRITE:RESET
   JSON-WRITE:OBJECT-START
   s" client_id" CODEX-CLIENT-ID$ JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" grant_type" s" refresh_token" JSON-WRITE:FIELD-S JSON-WRITE:COMMA
   s" refresh_token" VAL-BUF VAL-U @ JSON-WRITE:FIELD-S
   JSON-WRITE:OBJECT-END
   CURL-BEGIN
   CODEX-TOKEN-URL$ POST-JSON {: code :}
   REQ$ REMOVE-FILE
   code 200 <> if false exit then
   BODY-READ {: b bu :}
   b bu s" access_token" VAL-BUF 4096 DOC-STR1 dup 0 < if drop false exit then VAL-U !
   TOKENS-KEY$ s" access_token" VAL-BUF VAL-U @ LITERAL$ CFG-REPLACE2
   b bu s" refresh_token" VAL-BUF 4096 DOC-STR1 dup 0 >= if
      VAL-U ! TOKENS-KEY$ s" refresh_token" VAL-BUF VAL-U @ LITERAL$ CFG-REPLACE2
   else drop then
   b bu s" id_token" TOK-BUF BUF-CAP DOC-STR1 dup 0 >= if
      TOK-U ! TOKENS-KEY$ s" id_token" TOK-BUF TOK-U @ LITERAL$ CFG-REPLACE2
   else drop then
   TIME:EPOCH-SECONDS RESET-BUF LIM-RESET-CAP DATE:FORMAT-EPOCH-UTC LITERAL$ s" last_refresh" 2swap CFG-REPLACE
   true ;

: CODEX-GET ( -- n )
   CFG$ TOKENS-KEY$ s" access_token" VAL-BUF 4096 DOC-STR2 dup 0 < if drop -2 exit then VAL-U !
   CFG$ TOKENS-KEY$ s" account_id" ACCT-ID-BUF 128 DOC-STR2 dup 0 < if drop 0 then ACCT-ID-U !
   CURL-BEGIN
   VAL-BUF VAL-U @ BEARER
   ACCT-ID-U @ 0 > if s" ChatGPT-Account-Id" ACCT-ID-BUF ACCT-ID-U @ HDR then
   s" User-Agent" s" codex-cli" HDR
   CODEX-USAGE-URL$ CURL-RUN ;

: CODEX-NOTE ( n -- ) {: code :}
   code 401 = if s" login expired or revoked: switch to it once, or add it again" NOTE! exit then
   code 429 = if s" OpenAI is rate limiting usage checks; try again later" NOTE! exit then
   s" OpenAI's usage endpoint" code HTTP-NOTE ;

\ the slot's auth.json is in CFG; a 401 on a saved account earns one refresh
: CODEX-PROBE ( n ptr u8 n -- ) {: p a u :}
   LIM-RESET
   CFG$ CODEX-API-KEY? if s" API-key login: no usage windows to read" NOTE! exit then
   CODEX-GET {: code :}
   code -2 = if s" no access token saved" NOTE! exit then
   code 200 = if BODY-READ CODEX-LIMITS exit then
   code 401 = if
      CODEX-REVOKED? if
         true PROBE-REVOKED !
         s" login revoked by a later `codex login`" NOTE! exit
      then
      PROBE-LIVE? @ 0= if
         CODEX-REFRESH if
            p a u AUTH-NAME$ SLOT-FILE$ CFG$ WRITE-PRIVATE
            CODEX-GET {: again :}
            again 200 = if BODY-READ CODEX-LIMITS exit then
            again CODEX-NOTE exit
         then
      then
   then
   code CODEX-NOTE ;

public

EXPORT HUNDREDTHS

: .LIMITS ( -- )
   0 begin dup LIM-N @ < while
      dup 0 > if s"  · " type then
      dup LIM-LABEL-SLOT over LIM-LABEL-U-CELL @ type s"  " type
      dup LIM-PCT-CELL @ dup 0 < if drop s" ?" type else FMT:.U s" %" type then
      1+
   repeat drop ;

\ load a slot's usage file into the limit table; false when there is none
: LOAD-USAGE-RAW ( n ptr u8 n -- bool ) {: p a u :}
   LIM-RESET
   p a u USAGE-FILE$ FILE? 0= if false exit then
   p a u USAGE-FILE$ OBJ-BUF OBJ-U READ-INTO {: d du :}
   d du PARSE-USAGE-FILE
   d du s" note" NOTE-BUF 256 DOC-STR1 dup 0 < if drop 0 then NOTE-U !
   d du s" fetchedAt" DOC-INT1 USAGE-AT !
   true ;

\ a caught quotation keeps its stack shape, so the answer rides in the
\ length slot: 1 for a loaded record, 0 for none
: LOAD-USAGE-KEEP ( n ptr u8 n -- n ptr u8 n ) {: p a u :}
   p a u LOAD-USAGE-RAW if p a 1 exit then
   p a 0 ;

\ a damaged usage file reads as a note, never as a failed status
: LOAD-USAGE ( n ptr u8 n -- bool ) {: p a u :}
   p a u [: LOAD-USAGE-KEEP ;] catch {: rc :}
   rc 0= if nip nip 0 > exit then
   2drop drop
   LIM-RESET
   0 OBJ-U !
   s" usage record is unreadable; refresh usage" NOTE!
   true ;

: USAGE-AT@ ( -- n ) USAGE-AT @ ;
: NOTE$ ( -- ptr u8 n ) NOTE-BUF NOTE-U @ ;
: LIM#@ ( -- n ) LIM-N @ ;
: LIM-LABEL$ ( n -- ptr u8 n ) dup LIM-LABEL-SLOT swap LIM-LABEL-U-CELL @ ;
: LIM-RESET$ ( n -- ptr u8 n ) dup LIM-RESET-SLOT swap LIM-RESET-U-CELL @ ;
: LIM-PCT@ ( n -- n ) LIM-PCT-CELL @ ;

\ the raw limits array of a loaded usage file, for embedding in status JSON
: USAGE-LIMITS-RAW$ ( -- ptr u8 n )
   OBJ-U @ 0= if s" []" exit then
   OBJ$ s" limits" DOC-VALUE-SPAN? 0= if 2drop s" []" exit then
   {: off len :}
   len 0= if s" []" exit then
   OBJ-BUF off + c@ $5B <> if s" []" exit then
   OBJ-BUF off + len ;

\ a scratch path, for tests that check the scratch is cleaned up
: PSUB-PUBLIC$ ( ptr u8 n -- ptr u8 n ) PSUB$ ;

\ probe one saved account and fill the limit table
: PROBE-RAW ( n ptr u8 n bool -- ) {: p a u live :}
   live PROBE-LIVE? !
   false PROBE-REVOKED !
   PROBE-PREPARE
   p a u p MARKER$ SLOT-FILE$ CFG-BUF CFG-U READ-INTO 2drop
   p case
     P-CLAUDE of p a u CLAUDE-PROBE endof
     P-CODEX of p a u CODEX-PROBE endof
     E-SW-PROVIDER throw
   endcase ;

: PROBE-KEEP ( n ptr u8 n bool -- n ptr u8 n bool ) {: p a u live :}
   p a u live PROBE-RAW p a u live ;

: PROBE-FAILED-NOTE ( n -- )
   SB-RESET s" probe failed (error " SB-APPEND FMT:SB-INT s" )" SB-APPEND SB$ NOTE! ;

\ probe one saved account and record the outcome in its usage file; a failure
\ becomes that account's note and the run moves on to the next account. A
\ saved login the provider has revoked is useless, so its slot is removed;
\ the live account keeps its slot, because the live files are what to fix.
: PROBE-SLOT ( n ptr u8 n bool -- ) {: p a u live :}
   p a u live [: PROBE-KEEP ;] catch {: rc :} 2drop 2drop
   rc 0<> if LIM-RESET rc PROBE-FAILED-NOTE then
   PROBE-REVOKED @ live 0= and if p a u SLOT-DIR$ REMOVE-TREE PROBE-CLEANUP exit then
   p a u WRITE-USAGE
   PROBE-CLEANUP ;

: PROBE-REMOVED? ( -- bool )
   PROBE-REVOKED @ PROBE-LIVE? @ 0= and ;

;package
