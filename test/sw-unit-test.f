\ sw-unit-test.f - checked switcher tests.
\ Run through test.sh: HOME, XDG_DATA_HOME, and PATH must point at a scratch tree.
require ../src/switcher.f
require lib/test.f

package SW-TEST
using SW

create UT-BUF 256 allot

: SPAN-COPY ( ptr u8 n ptr u8 n -- ptr u8 n ) {: a u dst cap :}
   u cap > if E-SW-CAPACITY throw then
   a dst u BYTE-COPY
   dst u ;

: CFG-A$ ( -- ptr u8 n )
   s\" {\"numStartups\":3,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: OAUTH-A$ ( -- ptr u8 n )
   s\" {\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"}" ;

: CFG-B$ ( -- ptr u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

\ CFG-B with account A spliced back in
: CFG-BA$ ( -- ptr u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: CREDS-A$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a\",\"refreshToken\":\"r-a\",\"expiresAt\":1,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\",\"rateLimitTier\":\"default_claude_max_20x\"}}" ;

: CREDS-B$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}" ;

: AUTH-C$ ( -- ptr u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImNAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsImNoYXRncHRfYWNjb3VudF9pZCI6ImFjY3QifSwiZXhwIjoxfQ.c2ln\",\"access_token\":\"at-c\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"},\"last_refresh\":\"2026-09-14T07:11:36Z\"}" ;

: AUTH-D$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}" ;

: AUTH-KEY$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"sk-x\"}" ;

: AUTH-KEY-NULL$ ( -- ptr u8 n )
   s\" {\"OPENAI_API_KEY\":\"sk-x\",\"tokens\":null,\"last_refresh\":null}" ;

: CREDS-NULL-PLAN$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-n\",\"subscriptionType\":null}}" ;

: CFG-EMPTY$ ( -- ptr u8 n ) s\" {}" ;
: CFG-NOAUTH$ ( -- ptr u8 n ) s\" {\"numStartups\":1}" ;

: UT-B64 ( -- )
   s" aGVsbG8" UT-BUF 256 B64URL-DECODE 5 T=
   s" aGk" UT-BUF 256 B64URL-DECODE 2 T=
   [: s" aGVsbG8hY" UT-BUF 256 B64URL-DECODE drop ;] E-SW-BASE64 TTHROWSQ
   UT-BUF 5 s" hello" T$=
   s" aGVsbG8=" UT-BUF 256 B64URL-DECODE 5 T=
   s" -_8" UT-BUF 256 B64URL-DECODE 2 T=
   UT-BUF c@ $FB T=
   UT-BUF 1+ c@ $FF T=
   [: s" a!b" UT-BUF 256 B64URL-DECODE drop ;] E-SW-BASE64 TTHROWSQ ;

: UT-JWT ( -- )
   s" aaa.bbb.ccc" JWT-PAYLOAD s" bbb" T$=
   [: s" nodots" JWT-PAYLOAD 2drop ;] E-SW-JSON TTHROWSQ ;

: UT-DOC ( -- )
   CFG-A$ s" oauthAccount" s" emailAddress" UT-BUF 256 DOC-STR2 8 T=
   UT-BUF 8 s" a@x.test" T$=
   CFG-A$ s" oauthAccount" s" missing" UT-BUF 256 DOC-STR2 -1 T=
   CFG-A$ s" nope" s" x" UT-BUF 256 DOC-STR2 -1 T=
   CFG-A$ s" numStartups" UT-BUF 256 DOC-STR1 -1 T=
   CFG-A$ s" numStartups" s" x" UT-BUF 256 DOC-STR2 -1 T=
   CFG-A$ s" oauthAccount" DOC-OBJ-SPAN {: off len :}
   CFG-A$ drop off + len OAUTH-A$ T$=
   OAUTH-A$ CHECK-OBJECT
   [: s" [1]" CHECK-OBJECT ;] E-SW-JSON TTHROWSQ ;

: UT-IDENTITY ( -- )
   CFG-A$ CREDS-A$ CLAUDE-IDENTITY TTRUE
   EMAIL$ s" a@x.test" T$=
   PLAN$ s" max" T$=
   s" {}" CREDS-A$ CLAUDE-IDENTITY TFALSE
   AUTH-C$ CODEX-IDENTITY TTRUE
   EMAIL$ s" c@x.test" T$=
   PLAN$ s" plus" T$=
   s\" {\"tokens\":{}}" CODEX-IDENTITY TFALSE
   AUTH-KEY$ CODEX-IDENTITY TTRUE
   EMAIL$ s" api-key" T$=
   PLAN$ s" apikey" T$=
   AUTH-KEY-NULL$ CODEX-IDENTITY TTRUE
   EMAIL$ s" api-key" T$=
   CFG-A$ CREDS-NULL-PLAN$ CLAUDE-IDENTITY TTRUE
   PLAN$ nip 0 T=
   s\" {\"oauthAccount\":null}" CREDS-A$ CLAUDE-IDENTITY TFALSE ;

\ a throw inside a parse must not wedge the reader storage for the next parse
: UT-READER-RECOVERS ( -- )
   [: s\" {\"a\":" s" a" UT-BUF 256 DOC-STR1 drop ;] E-JR-EOF TTHROWSQ
   CFG-A$ s" oauthAccount" s" emailAddress" UT-BUF 256 DOC-STR2 8 T= ;

: UT-DOC-CLOSE ( -- )
   CFG-EMPTY$ DOC-CLOSE TFALSE 1 T=
   CFG-NOAUTH$ DOC-CLOSE TTRUE 16 T=
   s\" { \"a\" : {} }" DOC-CLOSE TTRUE 11 T=
   s\" {\"a\":1,\"oauthAccount\":{\"x\":1}}" s" oauthAccount" DOC-OBJ-SPAN? TTRUE 7 T= 22 T=
   s\" {\"a\":1}" s" oauthAccount" DOC-OBJ-SPAN? TFALSE 0 T= 0 T=
   s\" {\"k\":null}" s" k" DOC-VALUE-SPAN? TTRUE 4 T= 5 T=
   s\" {\"k\":\"v\"}" s" k" DOC-VALUE-SPAN? TTRUE 3 T= 5 T=
   s\" {\"k\":[1,{}]}" s" k" DOC-VALUE-SPAN? TTRUE 6 T= 5 T=
   s\" {\"k\":12}" s" z" DOC-VALUE-SPAN? TFALSE 0 T= 0 T= ;

: UT-STRINGS ( -- )
   s" a@x" s" b@x" STR< TTRUE
   s" b" s" a" STR< TFALSE
   s" a" s" ab" STR< TTRUE
   s" ab" s" ab" STR< TFALSE
   s" a.b@x_y+z-1" CHECK-NAME
   s" first last@x.test" CHECK-NAME
   s" caf\xC3\xA9@x.test" CHECK-NAME
   [: s" a/b" CHECK-NAME ;] E-SW-NAME TTHROWSQ
   [: s\" a\tb" CHECK-NAME ;] E-SW-NAME TTHROWSQ
   [: s" .a" CHECK-NAME ;] E-SW-NAME TTHROWSQ
   [: s" " CHECK-NAME ;] E-SW-NAME TTHROWSQ
   s" /a/b/c" DIRNAME s" /a/b" T$=
   s" /x" DIRNAME s" /" T$=
   s" x" DIRNAME nip 0 T= ;

: UT-NOOP ( -- ) ;
: UT-NESTED ( -- ) [: UT-NOOP ;] WITH-LOCK ;
: UT-BOOM ( -- ) E-SW-JSON throw ;
: UT-LOCKED-BOOM ( -- ) [: UT-BOOM ;] WITH-LOCK ;

: UT-LOCK ( -- )
   LOCK-STORE
   [: UT-NESTED ;] E-SW-LOCKED TTHROWSQ
   UNLOCK-STORE
   [: UT-LOCKED-BOOM ;] E-SW-JSON TTHROWSQ
   LOCK$ DIR? TFALSE ;

: UT-LIVE-A ( -- )
   CLAUDE-CREDS$ DIRNAME ENSURE-DIR
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   CODEX-AUTH$ DIRNAME ENSURE-DIR
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE ;

: UT-LIVE-B ( -- )
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-B$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-D$ WRITE-PRIVATE ;

: UT-SAVED-NAMES ( -- )
   P-CLAUDE LIST-ACCOUNTS ACCT# 2 T=
   0 ACCT-NAME s" a@x.test" T$=
   1 ACCT-NAME s" b@x.test" T$=
   P-CODEX LIST-ACCOUNTS ACCT# 2 T=
   0 ACCT-NAME s" c@x.test" T$=
   1 ACCT-NAME s" d@x.test" T$= ;

: UT-FLOW ( -- )
   UT-LIVE-A
   P-CLAUDE LIVE-IDENTITY TTRUE
   EMAIL$ s" a@x.test" T$=
   -1 CMD-SAVE
   P-CLAUDE LIST-ACCOUNTS ACCT# 1 T=
   0 ACCT-NAME s" a@x.test" T$=
   UT-LIVE-B
   -1 CMD-SAVE
   UT-SAVED-NAMES
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   CLAUDE-CREDS$ STAT-MODE $1FF and $180 T=
   STORE$ STAT-MODE $1FF and $1C0 T=
   P-CLAUDE PROVIDER-DIR$ STAT-MODE $1FF and $1C0 T=
   P-CLAUDE s" a@x.test" SLOT-DIR$ STAT-MODE $1FF and $1C0 T=
   P-CLAUDE s" a@x.test" s" oauth-account.json" SLOT-FILE$ STAT-MODE $1FF and $180 T=
   P-CLAUDE LIVE-IDENTITY TTRUE
   EMAIL$ s" a@x.test" T$=
   PLAN$ s" max" T$=
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX LIVE-IDENTITY TTRUE
   EMAIL$ s" c@x.test" T$=
   P-CLAUDE s" b@x.test" s" credentials.json" SLOT-FILE$ READ-FILE$ CREDS-B$ T$=
   P-CODEX s" d@x.test" s" auth.json" SLOT-FILE$ READ-FILE$ AUTH-D$ T$=
   [: P-CLAUDE s" nobody@x" CMD-USE ;] E-SW-NO-ACCOUNT TTHROWSQ
   P-CLAUDE s" b@x.test" CMD-FORGET
   P-CLAUDE LIST-ACCOUNTS ACCT# 1 T=
   [: P-CLAUDE s" b@x.test" CMD-FORGET ;] E-SW-NO-ACCOUNT TTHROWSQ
   LOCK$ DIR? TFALSE ;

\ install into a config that has no oauthAccount, an empty one, and none at all
: UT-INSTALL-INSERT ( -- )
   CLAUDE-CONFIG$ CFG-NOAUTH$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"numStartups\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"}}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE EMAIL$ s" a@x.test" T$=
   CLAUDE-CONFIG$ CFG-EMPTY$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"}}" T$=
   CLAUDE-CONFIG$ REMOVE-FILE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"}}" T$=
   CLAUDE-CONFIG$ STAT-MODE $1FF and $180 T=
   CLAUDE-CONFIG$ s\" {\"a\":1,\"oauthAccount\":null,\"z\":2}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"a\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"},\"z\":2}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE EMAIL$ s" a@x.test" T$=
   CLAUDE-CONFIG$ s\" {\"oauthAccount\":\"gone\"}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationName\":\"Org A\"}}" T$= ;

\ a config write that fails before its rename leaves no marker behind
: UT-FAILED-FIRST-WRITE ( -- )
   HOME$ $140 CHMOD-MODE
   [: P-CLAUDE s" a@x.test" CMD-USE ;] E-FS-OPEN TTHROWSQ
   HOME$ $1C0 CHMOD-MODE
   P-CLAUDE INSTALLING? TFALSE
   P-CLAUDE LIVE-IDENTITY TTRUE EMAIL$ s" a@x.test" T$= ;

\ an interrupted install: config already names B, credentials are still A's
: UT-INTERRUPTED ( -- )
   P-CLAUDE s" b@x.test" MARK-INSTALL
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   [: -1 CMD-SAVE ;] E-SW-INTERRUPTED TTHROWSQ
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE INSTALLING? TFALSE
   P-CLAUDE s" b@x.test" s" credentials.json" SLOT-FILE$ FILE? TFALSE
   P-CLAUDE s" a@x.test" s" credentials.json" SLOT-FILE$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$= ;

: UT-MISMATCH ( -- )
   P-CODEX s" z@x.test" SLOT-DIR$ ENSURE-PRIVATE
   P-CODEX s" z@x.test" s" auth.json" SLOT-FILE$ AUTH-C$ WRITE-PRIVATE
   [: P-CODEX s" z@x.test" CMD-USE ;] E-SW-MISMATCH TTHROWSQ
   P-CODEX LIVE-IDENTITY TTRUE EMAIL$ s" c@x.test" T$=
   P-CODEX s" z@x.test" CMD-FORGET ;

\ a damaged slot still lists; installing it is refused
: UT-DAMAGED-SLOT ( -- )
   P-CLAUDE s" bad@x.test" SLOT-DIR$ ENSURE-PRIVATE
   P-CLAUDE s" bad@x.test" s" credentials.json" SLOT-FILE$ s" garbage" WRITE-PRIVATE
   P-CLAUDE s" bad@x.test" s" oauth-account.json" SLOT-FILE$ s\" {\"emailAddress\":\"bad@x.test\"}" WRITE-PRIVATE
   P-CLAUDE LIST-ACCOUNTS ACCT# 2 T=
   P-CLAUDE 1 ACCT-NAME SLOT-PLAN PLAN$ nip 0 T=
   STATUS-JSON$ s\" \"email\":\"bad@x.test\",\"plan\":\"\",\"active\":false" CONTAINS? TTRUE
   [: P-CLAUDE s" bad@x.test" CMD-USE ;] E-JR-MALFORMED TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" bad@x.test" CMD-FORGET ;

\ one provider's broken live file leaves the other provider's status intact
: UT-STATUS-ISOLATION ( -- )
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   STATUS-JSON$ s\" \"id\":\"claude\",\"live\":null,\"accounts\":[{\"email\":\"a@x.test\"" CONTAINS? TTRUE
   STATUS-JSON$ s\" \"error\":\"switcher: a login file is not valid JSON\"" CONTAINS? TTRUE
   STATUS-JSON$ s\" \"id\":\"codex\",\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"}" CONTAINS? TTRUE
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE ;

\ API-key Codex logins are saved and restored under a fixed slot name
: UT-API-KEY ( -- )
   CODEX-AUTH$ AUTH-KEY$ WRITE-PRIVATE
   P-CODEX s" c@x.test" CMD-USE
   P-CODEX s" api-key" s" auth.json" SLOT-FILE$ READ-FILE$ AUTH-KEY$ T$=
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" api-key" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-KEY$ T$=
   P-CODEX s" c@x.test" CMD-USE
   P-CODEX s" api-key" CMD-FORGET ;

\ a symlinked live file stays a symlink; its target receives the new bytes
: UT-SYMLINK ( -- )
   CODEX-AUTH$ DIRNAME {: d du :}
   SB-RESET d du SB-APPEND s" /real-auth.json" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: r ru :}
   CODEX-AUTH$ r ru RENAME-FILE
   r ru CODEX-AUTH$ MAKE-SYMLINK
   CODEX-AUTH$ SYMLINK? TTRUE
   P-CODEX s" d@x.test" CMD-USE
   CODEX-AUTH$ SYMLINK? TTRUE
   r ru READ-FILE$ AUTH-D$ T$=
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ REMOVE-FILE
   r ru CODEX-AUTH$ RENAME-FILE ;

\ marker files outside <provider>/<name>/ are not accounts
: UT-STRAY-MARKERS ( -- )
   P-CODEX PROVIDER-DIR$ {: d du :}
   SB-RESET d du SB-APPEND s" /auth.json" SB-APPEND SB$ s" {}" WRITE-PRIVATE
   P-CODEX s" c@x.test" s" sub" SLOT-FILE$ ENSURE-PRIVATE
   P-CODEX s" c@x.test" s" sub/auth.json" SLOT-FILE$ s" {}" WRITE-PRIVATE
   P-CODEX LIST-ACCOUNTS ACCT# 2 T=
   0 ACCT-NAME s" c@x.test" T$=
   1 ACCT-NAME s" d@x.test" T$=
   SB-RESET d du SB-APPEND s" /auth.json" SB-APPEND SB$ REMOVE-FILE
   P-CODEX s" c@x.test" s" sub" SLOT-FILE$ REMOVE-TREE ;

: UT-MAIN ( -- )
   T-RESET
   ALLOC-BUFFERS
   UT-B64
   UT-JWT
   UT-DOC
   UT-IDENTITY
   UT-STRINGS
   UT-READER-RECOVERS
   UT-DOC-CLOSE
   UT-LOCK
   UT-FLOW
   UT-INSTALL-INSERT
   UT-FAILED-FIRST-WRITE
   UT-INTERRUPTED
   UT-MISMATCH
   UT-DAMAGED-SLOT
   UT-STATUS-ISOLATION
   UT-API-KEY
   UT-SYMLINK
   UT-STRAY-MARKERS
   T-REPORT ;

UT-MAIN

;package
