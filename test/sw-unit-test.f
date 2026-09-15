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
   s\" {\"numStartups\":3,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: OAUTH-A$ ( -- ptr u8 n )
   s\" {\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}" ;

: CFG-B$ ( -- ptr u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

\ CFG-B with account A spliced back in
: CFG-BA$ ( -- ptr u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

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
   LOCK$ DIR? TFALSE
   E-SW-LOCKED REASON$ s" switcher: another switcher holds the store lock; remove " STARTS-WITH? TTRUE
   E-SW-LOCKED REASON$ s"  if it is stale" ENDS-WITH? TTRUE
   E-SW-LOCKED REASON$ LOCK$ CONTAINS? TTRUE ;

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

\ a second login under the same email but another organization gets its own
\ slot, "a@x.test #2", and the active mark follows the organization
: CFG-A2$ ( -- ptr u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u9\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-c\",\"organizationName\":\"Org C\"}}" ;

\ a third organization whose name only repeats the email
: CFG-A3$ ( -- ptr u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u8\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-d\",\"organizationName\":\"a@x.test's Organization\"}}" ;

: CREDS-A2$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a2\",\"subscriptionType\":\"team\"}}" ;

: UT-SAME-EMAIL ( -- )
   s" a@x.test (Org C)" s" a@x.test" NAME-FOR-EMAIL? TFALSE
   s" a@x.test #2" s" a@x.test" NAME-FOR-EMAIL? TTRUE
   s" a@x.test" s" a@x.test" NAME-FOR-EMAIL? TTRUE
   s" a@x.testx" s" a@x.test" NAME-FOR-EMAIL? TFALSE
   s" b@x.test (Org C)" s" a@x.test" NAME-FOR-EMAIL? TFALSE
   CLAUDE-CONFIG$ CFG-A2$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A2$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE LIST-ACCOUNTS ACCT# 2 T=
   0 ACCT-NAME s" a@x.test" T$=
   1 ACCT-NAME s" a@x.test #2" T$=
   P-CLAUDE s" a@x.test #2" s" credentials.json" SLOT-FILE$ READ-FILE$ CREDS-A2$ T$=
   P-CLAUDE s" a@x.test" s" credentials.json" SLOT-FILE$ READ-FILE$ CREDS-A$ T$=
   STATUS-JSON$ s\" \"email\":\"a@x.test #2\",\"plan\":\"team\",\"active\":true" CONTAINS? TTRUE
   STATUS-JSON$ s\" \"email\":\"a@x.test\",\"plan\":\"max\",\"active\":false" CONTAINS? TTRUE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   STATUS-JSON$ s\" \"email\":\"a@x.test\",\"plan\":\"max\",\"active\":true" CONTAINS? TTRUE
   P-CLAUDE s" a@x.test #2" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A2$ T$=
   P-CLAUDE LIVE-IDENTITY TTRUE ORG$ s" org-c" T$=
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ CFG-A3$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A2$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE CMD-SAVE
   P-CLAUDE LIST-ACCOUNTS ACCT# 3 T=
   1 ACCT-NAME s" a@x.test #2" T$=
   2 ACCT-NAME s" a@x.test #3" T$=
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE s" a@x.test #2" CMD-FORGET
   P-CLAUDE s" a@x.test #3" CMD-FORGET ;

\ install into a config that has no oauthAccount, an empty one, and none at all
: UT-INSTALL-INSERT ( -- )
   CLAUDE-CONFIG$ CFG-NOAUTH$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"numStartups\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE EMAIL$ s" a@x.test" T$=
   CLAUDE-CONFIG$ CFG-EMPTY$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" T$=
   CLAUDE-CONFIG$ REMOVE-FILE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" T$=
   CLAUDE-CONFIG$ STAT-MODE $1FF and $180 T=
   CLAUDE-CONFIG$ s\" {\"a\":1,\"oauthAccount\":null,\"z\":2}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"a\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"z\":2}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE EMAIL$ s" a@x.test" T$=
   CLAUDE-CONFIG$ s\" {\"oauthAccount\":\"gone\"}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" T$= ;

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

\ the usage refresh runs the collector command found on PATH with the
\ provider as its last argument; the fake collector records its argv
: UT-FAKE-COLLECTOR ( -- )
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin" SB-APPEND SB$ ENSURE-PRIVATE
   SB-RESET h hu SB-APPEND s" /bin/omarchy-agent-usage-update" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu s\" #!/bin/sh\nprintf '%s\\n' \"$@\" > \"$HOME/collector.args\"\n" WRITE-ALL
   f fu CHMOD-X ;

: UT-USAGE-REFRESH ( -- )
   UT-FAKE-COLLECTOR
   P-CODEX USAGE-REFRESH
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /collector.args" SB-APPEND SB$ READ-FILE$ s\" --limits-only\ncodex\n" T$= ;

: UT-WRITE-SCRIPT ( ptr u8 n ptr u8 n -- ) {: n nu body bu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu body bu WRITE-ALL
   f fu CHMOD-X ;

\ a fake curl: answers each provider URL from the Authorization header it is
\ given, writes the body to the -o file, prints the status, and logs the call
: UT-FAKE-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in Authorization:*) auth=$2;; esac; shift;; --data-binary) echo \"data $2\" >> \"$SW_TEST_LOG\"; shift;; -X|-m|-w) shift;; *) url=$1;; esac; shift; done\necho \"$url $auth\" >> \"$SW_TEST_LOG\"\ncode=200; body='{}'\ncase \"$url\" in\n*api.anthropic.com/api/oauth/usage) case \"$auth\" in *sk-a) body='{\"five_hour\":{\"utilization\":56.25,\"resets_at\":\"2026-09-15T14:00:00+00:00\"},\"seven_day\":{\"utilization\":100,\"resets_at\":\"2026-09-21T11:00:00+00:00\"}}';; *sk-b-new) body='{\"five_hour\":{\"utilization\":12.4,\"resets_at\":\"2026-09-15T15:00:00+00:00\"},\"seven_day_oauth_apps\":{\"utilization\":0.5,\"resets_at\":\"\"}}';; *) code=401; body='{\"error\":\"expired\"}';; esac;;\n*platform.claude.com/v1/oauth/token) body='{\"access_token\":\"sk-b-new\",\"refresh_token\":\"r-b-new\",\"expires_in\":3600}';;\n*chatgpt.com/backend-api/wham/usage) case \"$auth\" in *at-c) body='{\"plan_type\":\"pro\",\"rate_limit\":{\"allowed\":false,\"limit_reached\":true,\"primary_window\":{\"used_percent\":100,\"limit_window_seconds\":604800,\"reset_after_seconds\":433078,\"reset_at\":1789904220},\"secondary_window\":null}}';; *at-d2) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000,\"reset_at\":1789489142},\"secondary_window\":{\"used_percent\":40,\"limit_window_seconds\":604800,\"reset_at\":1790075942}}}';; *at-z) code=401; body='{\"error\":{\"code\":\"token_revoked\"}}';; *) code=401; body='{\"error\":{\"code\":\"token_expired\"}}';; esac;;\n*auth.openai.com/oauth/token) body='{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\"}';;\n*) code=404;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf '%s' \"$code\"\n"
   UT-WRITE-SCRIPT ;

: AUTH-D2$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\",\"account_id\":\"acct\"}}" ;

: AUTH-Z$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-z\",\"refresh_token\":\"rt-z\",\"account_id\":\"acct\"}}" ;

: UT-PCT ( -- )
   s" 0.5625" HUNDREDTHS 56 T=
   s" 56.25" HUNDREDTHS 5625 T=
   s" 1" HUNDREDTHS 100 T=
   s" 0.145" HUNDREDTHS 15 T=
   s" 0.999" HUNDREDTHS 100 T=
   s" 0" HUNDREDTHS 0 T=
   s" 0.1" HUNDREDTHS 10 T=
   s" x" HUNDREDTHS -1 T=
   s" 0.5.1" HUNDREDTHS -1 T=
   s" 99999999999999999999" HUNDREDTHS -1 T=
   s" ." HUNDREDTHS -1 T= ;

: LOG$ ( -- ptr u8 n )
   s" SW_TEST_LOG" GETENV ;

\ live claude a@x.test (sk-a, expired but live: no refresh) and codex c@x.test;
\ saved b@x.test refreshes its expired token, saved d@x.test refreshes after 401,
\ saved z@x.test is revoked
: UT-USAGE ( -- )
   UT-FAKE-CURL
   P-CLAUDE s" b@x.test" SLOT-DIR$ ENSURE-PRIVATE
   P-CLAUDE s" b@x.test" s" credentials.json" SLOT-FILE$ CREDS-B$ WRITE-PRIVATE
   P-CLAUDE s" b@x.test" s" oauth-account.json" SLOT-FILE$ s\" {\"emailAddress\":\"b@x.test\"}" WRITE-PRIVATE
   P-CODEX s" z@x.test" SLOT-DIR$ ENSURE-PRIVATE
   P-CODEX s" z@x.test" s" auth.json" SLOT-FILE$ AUTH-Z$ WRITE-PRIVATE
   -1 CMD-USAGE
   P-CLAUDE s" a@x.test" LOAD-USAGE TTRUE
   LIM#@ 2 T=
   0 LIM-LABEL$ s" Session (5-hour)" T$=
   0 LIM-PCT@ 56 T=
   1 LIM-PCT@ 100 T=
   1 LIM-RESET$ s" 2026-09-21T11:00:00+00:00" T$=
   USAGE-AT@ 0 > TTRUE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" b@x.test" LOAD-USAGE TTRUE
   LIM#@ 2 T=
   0 LIM-PCT@ 12 T=
   1 LIM-PCT@ 1 T=
   1 LIM-LABEL$ s" Weekly (7-day)" T$=
   P-CLAUDE s" b@x.test" s" credentials.json" SLOT-FILE$ READ-FILE$ {: c cu :}
   c cu s\" \"accessToken\":\"sk-b-new\"" CONTAINS? TTRUE
   c cu s\" \"refreshToken\":\"r-b-new\"" CONTAINS? TTRUE
   c cu s\" \"expiresAt\":2," CONTAINS? TFALSE
   c cu s\" \"subscriptionType\":\"pro\"" CONTAINS? TTRUE
   P-CODEX s" c@x.test" LOAD-USAGE TTRUE
   LIM#@ 1 T=
   0 LIM-LABEL$ s" Weekly (7-day)" T$=
   0 LIM-PCT@ 100 T=
   0 LIM-RESET$ s" 2026-09-20T11:37:00Z" T$=
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" LOAD-USAGE TTRUE
   LIM#@ 2 T=
   0 LIM-LABEL$ s" Session (5-hour)" T$=
   0 LIM-PCT@ 12 T=
   1 LIM-PCT@ 40 T=
   P-CODEX s" d@x.test" s" auth.json" SLOT-FILE$ READ-FILE$ {: d du :}
   d du s\" \"access_token\":\"at-d2\"" CONTAINS? TTRUE
   d du s\" \"refresh_token\":\"rt-d2\"" CONTAINS? TTRUE
   d du s\" \"account_id\":\"acct\"" CONTAINS? TTRUE
   d du CODEX-IDENTITY TTRUE EMAIL$ s" d@x.test" T$=
   P-CODEX s" z@x.test" SLOT-DIR$ DIR? TFALSE
   STATUS-JSON$ s\" \"usage\":{\"fetchedAt\":" CONTAINS? TTRUE
   STATUS-JSON$ s\" \"limits\":[{\"label\":\"Session (5-hour)\",\"percent\":56," CONTAINS? TTRUE
   LOG$ READ-FILE$ {: l lu :}
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   STORE$ {: s su :}
   SB-RESET s" data @" SB-APPEND s su SB-APPEND s" /probe/request.json" SB-APPEND
   l lu SB$ CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   l lu s" Authorization: Bearer sk-a" CONTAINS? TTRUE
   l lu s" Authorization: Bearer at-z" CONTAINS? TTRUE
   s" /body.json" PSUB-PUBLIC$ FILE? TFALSE
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" d@x.test" LOAD-USAGE TTRUE LIM#@ 2 T=
   P-CODEX s" c@x.test" CMD-USE
   P-CLAUDE s" b@x.test" CMD-FORGET ;

\ `add` runs the login with the live file out of the way and restores it on
\ failure; the fake `codex` records what it saw and writes AUTH-D on success
: UT-FAKE-CODEX ( -- )
   s" codex"
   s\" #!/bin/sh\nif [ -e \"$HOME/.codex/auth.json\" ]; then echo present >> \"$SW_TEST_LOG\"; else echo absent >> \"$SW_TEST_LOG\"; fi\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nprintf '%s' '{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}' > \"$HOME/.codex/auth.json\"\n"
   UT-WRITE-SCRIPT ;

: UT-ADD ( -- )
   UT-FAKE-CODEX
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /fail-login" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu s" x" WRITE-ALL
   P-CODEX s" c@x.test" CMD-USE
   [: P-CODEX CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   CODEX-AUTH$ ASIDE-FOR FILE? TFALSE
   f fu REMOVE-FILE
   HOME$ {: h2 h2u :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: cx cxu :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex.off" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: cxo cxou :}
   cx cxu cxo cxou RENAME-FILE
   [: P-CODEX CMD-ADD ;] E-SW-NO-CLI TTHROWSQ
   CODEX-AUTH$ FILE? TTRUE
   CODEX-AUTH$ ASIDE-FOR FILE? TFALSE
   cxo cxou cx cxu RENAME-FILE
   P-CODEX CMD-ADD
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   CODEX-AUTH$ ASIDE-FOR FILE? TFALSE
   P-CODEX s" c@x.test" s" auth.json" SLOT-FILE$ READ-FILE$ AUTH-C$ T$=
   LOG$ READ-FILE$ s\" absent\nabsent\n" ENDS-WITH? TTRUE
   P-CODEX s" c@x.test" CMD-USE ;

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
   UT-SAME-EMAIL
   UT-INSTALL-INSERT
   UT-FAILED-FIRST-WRITE
   UT-INTERRUPTED
   UT-MISMATCH
   UT-DAMAGED-SLOT
   UT-STATUS-ISOLATION
   UT-API-KEY
   UT-SYMLINK
   UT-STRAY-MARKERS
   UT-USAGE-REFRESH
   UT-ADD
   UT-PCT
   UT-USAGE
   T-REPORT ;

UT-MAIN

;package
