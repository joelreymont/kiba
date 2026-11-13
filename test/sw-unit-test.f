\ sw-unit-test.f - checked kiba tests.
\ Run through test.sh: HOME, XDG_DATA_HOME, and PATH must point at a scratch tree.
require ../src/kiba.f
require ../src/sw-turn.f
require src/lib/test.f
require src/lib/fs-list.f
require src/lib/fs-lock.f

package SW-TEST
using SW

create UT-BUF 256 allot
create UT-PID 32 allot

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
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a\",\"refreshToken\":\"r-a\",\"expiresAt\":4102444800000,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\",\"rateLimitTier\":\"default_claude_max_20x\"}}" ;

: CREDS-B$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"refreshTokenExpiresAt\":1,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}" ;

: CREDS-E$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-e\",\"refreshToken\":\"r-e\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

: CREDS-F$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-f\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

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
   CFG-A$ CREDS-A$ ID-LIVE CLAUDE-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" a@x.test" T$=
   ID-LIVE PLAN$ s" max" T$=
   s" {}" CREDS-A$ ID-LIVE CLAUDE-IDENTITY TFALSE
   AUTH-C$ ID-LIVE CODEX-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" c@x.test" T$=
   ID-LIVE PLAN$ s" plus" T$=
   s\" {\"tokens\":{}}" ID-LIVE CODEX-IDENTITY TFALSE
   AUTH-KEY$ ID-LIVE CODEX-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" api-key" T$=
   ID-LIVE PLAN$ s" apikey" T$=
   AUTH-KEY-NULL$ ID-LIVE CODEX-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" api-key" T$=
   CFG-A$ CREDS-NULL-PLAN$ ID-LIVE CLAUDE-IDENTITY TTRUE
   ID-LIVE PLAN$ nip 0 T=
   s\" {\"oauthAccount\":null}" CREDS-A$ ID-LIVE CLAUDE-IDENTITY TFALSE
   CFG-A$ CREDS-A$ ID-LIVE CLAUDE-IDENTITY TTRUE
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE    \ a slot read leaves the live one alone
   ID-SLOT EMAIL$ s" c@x.test" T$=
   ID-LIVE EMAIL$ s" a@x.test" T$=
   ID-LIVE PLAN$ s" max" T$= ;

\ a throw inside a parse must not wedge the reader storage for the next parse
: UT-READER-RECOVERS ( -- )
   [: s\" {\"a\":" s" a" UT-BUF 256 DOC-STR1 drop ;] E-JSON-READ-EOF TTHROWSQ
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
   UT-NESTED
   LOCK$ FS:DIR? TTRUE
   UNLOCK-STORE
   [: UT-LOCKED-BOOM ;] E-SW-JSON TTHROWSQ
   LOCK$ FS:DIR? TFALSE
   E-SW-LOCKED REASON$ s" kiba: another kiba holds the store lock; remove " STARTS-WITH? TTRUE
   E-SW-LOCKED REASON$ s"  if it is stale" ENDS-WITH? TTRUE
   E-SW-LOCKED REASON$ LOCK$ CONTAINS? TTRUE ;

: UT-LIVE-A ( -- )
   CLAUDE-CREDS$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   CODEX-AUTH$ DIRNAME ENSURE-PRIVATE
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE ;

: UT-LIVE-B ( -- )
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-B$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-D$ WRITE-PRIVATE ;

\ ---- saved logins in the account store -------------------------------------
\ save, use and forget open the store themselves; a test opens it only to look
: CREDS-A9$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a9\",\"refreshToken\":\"r-a9\",\"expiresAt\":4102444800000,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

: AUTH-C9$ ( -- ptr u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImNAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsImNoYXRncHRfYWNjb3VudF9pZCI6ImFjY3QifSwiZXhwIjoxfQ.c2ln\",\"access_token\":\"at-c9\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"},\"last_refresh\":\"2026-09-14T07:11:36Z\"}" ;

\ CFG-A with account B spliced in
: CFG-AB$ ( -- ptr u8 n )
   s\" {\"numStartups\":3,\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: CFG-ONLY-A$ ( -- ptr u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" ;

variable UT-N
variable UT-SW0
create UT-LOCKED-BUF 256 allot   variable UT-LOCKED-U
create UT-REAL-BUF 256 allot     variable UT-REAL-U

: UT-STORE ( [ -- ] -- ) {: body :}
   DB-OPEN [: body execute ;] [: DB-CLOSE ;] finally ;

: UT-COUNT-SWITCHES ( n -- ) {: p :}
   s" SELECT count(*) FROM history WHERE provider = ? AND kind = 'switch'" s" test"
   [: p PROVIDER$ DB-TEXT+ ;] [: 0 DB-COL-INT UT-N ! ;] DB-QUERY ;

: UT-SWITCHES ( n -- n ) {: p :}
   0 UT-N ! [: p UT-COUNT-SWITCHES ;] UT-STORE UT-N @ ;

: UT-LOGIN= ( n ptr u8 n ptr u8 n -- ) {: p a u l lu :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-LOGIN$ l lu T$= ;] UT-STORE ;

: UT-FETCH ( n ptr u8 n -- ) {: p a u :} p a u DB-FETCH UT-N ! ;

: UT-ROW? ( n ptr u8 n -- bool ) {: p a u :}
   [: p a u UT-FETCH ;] UT-STORE UT-N @ ;

: UT-INSTALLED= ( n ptr u8 n -- ) {: p a u :}
   [: p DB-INSTALLED TTRUE a u T$= ;] UT-STORE ;

: UT-PENDING-KEEP ( n -- ) DB-PENDING UT-N ! 2drop ;

: UT-PENDING? ( n -- bool ) {: p :}
   [: p UT-PENDING-KEEP ;] UT-STORE UT-N @ ;

: UT-PENDING= ( n ptr u8 n -- ) {: p a u :}
   [: p DB-PENDING TTRUE a u T$= ;] UT-STORE ;

: UT-KEEP-NAME ( n -- ) {: p :}
   p LIVE-IDENTITY TTRUE
   p ID-LIVE DB-LIVE-NAME UT-BUF 256 SPAN-COPY nip UT-N ! ;

\ the name DB-LIVE-NAME gives the live login now
: UT-LIVE-NAME ( n -- ptr u8 n ) {: p :}
   [: p UT-KEEP-NAME ;] UT-STORE UT-BUF UT-N @ ;

: UT-NO-CREDS ( -- ) CLAUDE-CREDS$ FS:REMOVE-FILE ;

: UT-STORE-SAVE ( -- )
   UT-LIVE-A
   P-CLAUDE UT-LIVE-NAME s" a@x.test" T$=
   -1 CMD-SAVE
   P-CLAUDE s" a@x.test" CREDS-A$ UT-LOGIN=
   P-CODEX s" c@x.test" AUTH-C$ UT-LOGIN=
   [: P-CLAUDE s" a@x.test" DB-FETCH TTRUE
      0 DB-ROW-PROFILE$ OAUTH-A$ T$=
      0 DB-ROW-PLAN$ s" max" T$= ;] UT-STORE
   UT-LIVE-B
   P-CLAUDE UT-LIVE-NAME s" b@x.test" T$=
   -1 CMD-SAVE
   P-CLAUDE s" b@x.test" CREDS-B$ UT-LOGIN=
   P-CODEX s" d@x.test" AUTH-D$ UT-LOGIN=
   STORE$ FS:STAT-MODE $1FF and $1C0 T= ;

\ the live login, its tokens refreshed since it was saved, is saved back
\ before the second account is installed
: UT-STORE-USE ( -- )
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A9$ WRITE-PRIVATE
   P-CLAUDE s" b@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-B$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-AB$ T$=
   CLAUDE-CREDS$ FS:STAT-MODE $1FF and $180 T=
   CLAUDE-CONFIG$ FS:STAT-MODE $1FF and $180 T=
   P-CLAUDE s" a@x.test" CREDS-A9$ UT-LOGIN=
   P-CLAUDE s" b@x.test" UT-INSTALLED=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE UT-SWITCHES 1 T=
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" b@x.test" T$=
   [: P-CLAUDE s" nobody@x" CMD-USE ;] E-SW-NO-ACCOUNT TTHROWSQ
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE UT-SWITCHES 1 T= ;

: UT-STORE-USE-CODEX ( -- )
   CODEX-AUTH$ AUTH-C9$ WRITE-PRIVATE
   P-CODEX s" d@x.test" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   P-CODEX s" c@x.test" AUTH-C9$ UT-LOGIN=
   P-CODEX s" d@x.test" UT-INSTALLED=
   P-CODEX UT-PENDING? TFALSE
   P-CODEX UT-SWITCHES 1 T= ;

\ a second login under the same email but another organization gets its own
\ name, "a@x.test #2"
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
   P-CLAUDE s" a@x.test #2" CREDS-A2$ UT-LOGIN=
   P-CLAUDE s" a@x.test" CREDS-A9$ UT-LOGIN=
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE s" a@x.test #2" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A2$ T$=
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE ORG$ s" org-c" T$=
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ CFG-A3$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A2$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" a@x.test #3" CREDS-A2$ UT-LOGIN=
   [: P-CLAUDE DB-LIST DB-ROW# 4 T= ;] UT-STORE
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE s" a@x.test #2" CMD-FORGET
   P-CLAUDE s" a@x.test #3" CMD-FORGET ;

\ install into a config that has no oauthAccount, an empty one, and none at
\ all; credentials beside a config naming no account are unreadable, so each
\ starts from none
: UT-INSTALL-INSERT ( -- )
   UT-NO-CREDS
   CLAUDE-CONFIG$ CFG-NOAUTH$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"numStartups\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   UT-NO-CREDS
   CLAUDE-CONFIG$ CFG-EMPTY$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   UT-NO-CREDS
   CLAUDE-CONFIG$ FS:REMOVE-FILE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   CLAUDE-CONFIG$ FS:STAT-MODE $1FF and $180 T=
   UT-NO-CREDS
   CLAUDE-CONFIG$ s\" {\"a\":1,\"oauthAccount\":null,\"z\":2}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ s\" {\"a\":1,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"z\":2}" T$=
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   UT-NO-CREDS
   CLAUDE-CONFIG$ s\" {\"oauthAccount\":\"gone\"}" WRITE-PRIVATE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$= ;

\ a config write that fails, with the old config unable to go back, leaves
\ the install pending: save refuses, and the next install clears it
: UT-FAILED-FIRST-WRITE ( -- )
   HOME$ $140 FS:CHMOD-MODE
   [: P-CLAUDE s" a@x.test" CMD-USE ;] E-FS-OPEN TTHROWSQ
   HOME$ $1C0 FS:CHMOD-MODE
   P-CLAUDE s" a@x.test" UT-PENDING=
   [: P-CLAUDE CMD-SAVE ;] E-SW-MIXED TTHROWSQ
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$= ;

\ credentials that cannot be read stop the switch before anything is written
: UT-CREDS-DIR ( -- )
   P-CLAUDE UT-SWITCHES UT-SW0 !
   UT-NO-CREDS
   CLAUDE-CREDS$ ENSURE-PRIVATE
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-FS-IO TTHROWSQ
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE UT-SWITCHES UT-SW0 @ T=
   CLAUDE-CREDS$ FS:REMOVE-DIR
   CLAUDE-CREDS$ CREDS-A9$ WRITE-PRIVATE ;

: UT-LOCKED$ ( -- ptr u8 n )
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /locked" SB-APPEND SB$ UT-LOCKED-BUF 256 SPAN-COPY ;

: UT-REAL$ ( -- ptr u8 n )
   UT-LOCKED$ {: l lu :}
   SB-RESET l lu SB-APPEND s" /creds.json" SB-APPEND SB$ UT-REAL-BUF 256 SPAN-COPY ;

\ live credentials readable through a link into a directory nothing can be
\ written in: the config write succeeds, the credentials write fails
: UT-LINK-CREDS ( -- )
   UT-LOCKED$ ENSURE-PRIVATE
   UT-REAL$ CREDS-A9$ WRITE-PRIVATE
   UT-LOCKED$ $140 FS:CHMOD-MODE
   UT-NO-CREDS
   UT-REAL$ CLAUDE-CREDS$ FS:MAKE-SYMLINK ;

: UT-UNLINK-CREDS ( -- )
   CLAUDE-CREDS$ FS:REMOVE-FILE
   UT-LOCKED$ $1C0 FS:CHMOD-MODE
   UT-LOCKED$ FS:REMOVE-TREE
   CLAUDE-CREDS$ CREDS-A9$ WRITE-PRIVATE ;

\ the failed credentials write puts the old config back; with no install
\ pending before, the files are known to be the pair from before, so the
\ claim is cleared and nothing is recorded
: UT-RESTORED ( -- )
   P-CLAUDE UT-SWITCHES UT-SW0 !
   UT-LINK-CREDS
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-FS-OPEN TTHROWSQ
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   UT-REAL$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE UT-SWITCHES UT-SW0 @ T=
   P-CLAUDE s" a@x.test" UT-INSTALLED=
   UT-UNLINK-CREDS ;

: UT-NOTE-PENDING ( -- )
   [: P-CLAUDE s" a@x.test" DB-NOTE-PENDING 2drop ;] DB-WRITE ;

\ with an install already pending the pair from before is unknown, so the
\ throw between the config and credentials writes leaves the pending row:
\ save refuses until an install completes
: UT-REPAIR-PENDING ( -- )
   [: UT-NOTE-PENDING ;] UT-STORE
   UT-LINK-CREDS
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-FS-OPEN TTHROWSQ
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   P-CLAUDE s" b@x.test" UT-PENDING=
   [: P-CLAUDE CMD-SAVE ;] E-SW-MIXED TTHROWSQ
   UT-UNLINK-CREDS
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE UT-PENDING? TFALSE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$= ;

: UT-PUT-Z ( -- )
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE
   [: P-CODEX s" z@x.test" ID-SLOT AUTH-C$ UT-BUF -1 false DB-PUT ;] DB-WRITE ;

: UT-MISMATCH ( -- )
   [: UT-PUT-Z ;] UT-STORE
   P-CODEX UT-SWITCHES UT-SW0 !
   [: P-CODEX s" z@x.test" CMD-USE ;] E-SW-MISMATCH TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   P-CODEX UT-SWITCHES UT-SW0 @ T=
   P-CODEX s" z@x.test" CMD-FORGET ;

: UT-PUT-BAD ( -- )
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" bad@x.test" ID-SLOT s" garbage" s\" {\"emailAddress\":\"bad@x.test\"}" false DB-PUT ;] DB-WRITE ;

\ a saved login that is not JSON is refused before anything is claimed
: UT-DAMAGED-ROW ( -- )
   [: UT-PUT-BAD ;] UT-STORE
   [: P-CLAUDE s" bad@x.test" CMD-USE ;] E-JSON-READ-MALFORMED TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" bad@x.test" CMD-FORGET ;

\ API-key Codex logins are saved and restored under a fixed name
: UT-API-KEY ( -- )
   CODEX-AUTH$ AUTH-KEY$ WRITE-PRIVATE
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" api-key" AUTH-KEY$ UT-LOGIN=
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   P-CODEX s" api-key" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-KEY$ T$=
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" api-key" CMD-FORGET ;

\ a symlinked live file stays a symlink; its target receives the new bytes
: UT-SYMLINK ( -- )
   CODEX-AUTH$ DIRNAME {: d du :}
   SB-RESET d du SB-APPEND s" /real-auth.json" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: r ru :}
   CODEX-AUTH$ r ru FS:RENAME-FILE
   r ru CODEX-AUTH$ FS:MAKE-SYMLINK
   CODEX-AUTH$ FS:SYMLINK? TTRUE
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ FS:SYMLINK? TTRUE
   r ru READ-FILE$ AUTH-C9$ T$=
   P-CODEX s" d@x.test" CMD-USE
   CODEX-AUTH$ FS:REMOVE-FILE
   r ru CODEX-AUTH$ FS:RENAME-FILE ;

\ a live config naming another account over credentials still identical to
\ the installed row's is a mix: save refuses it, use skips saving it back
: UT-MIXED-PAIR ( -- )
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   [: P-CLAUDE CMD-SAVE ;] E-SW-MIXED TTHROWSQ
   P-CLAUDE s" b@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-B$ T$=
   P-CLAUDE s" b@x.test" CREDS-B$ UT-LOGIN=
   P-CLAUDE s" a@x.test" CREDS-A9$ UT-LOGIN=
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$= ;

: UT-NOTE-ADDING ( -- ) [: P-CLAUDE CREDS-A$ DB-NOTE-ADDING ;] DB-WRITE ;
: UT-CLEAR-ADDING ( -- ) [: P-CLAUDE DB-CLEAR-ADDING ;] DB-WRITE ;

\ an add's record of the live login stops save and use
: UT-UNRESTORED ( -- )
   [: UT-NOTE-ADDING ;] UT-STORE
   [: P-CLAUDE CMD-SAVE ;] E-SW-UNRESTORED TTHROWSQ
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-SW-UNRESTORED TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   [: UT-CLEAR-ADDING ;] UT-STORE
   E-SW-UNRESTORED REASON$ s" kiba: the live login waits" STARTS-WITH? TTRUE ;

\ credentials without a config are nobody's: neither saved nor replaced
: UT-ORPHAN ( -- )
   CLAUDE-CONFIG$ FS:REMOVE-FILE
   [: P-CLAUDE CMD-SAVE ;] E-SW-ORPHAN-LIVE TTHROWSQ
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-SW-ORPHAN-LIVE TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   CLAUDE-CONFIG$ FS:FILE? TFALSE
   E-SW-ORPHAN-LIVE REASON$ CLAUDE-CONFIG$ CONTAINS? TTRUE
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE ;

\ leaves no Claude row, so the store tests below start from an empty list
: UT-STORE-FORGET ( -- )
   P-CLAUDE s" b@x.test" CMD-FORGET
   P-CLAUDE s" b@x.test" UT-ROW? TFALSE
   P-CLAUDE s" a@x.test" UT-ROW? TTRUE
   [: P-CLAUDE s" b@x.test" CMD-FORGET ;] E-SW-NO-ACCOUNT TTHROWSQ
   P-CLAUDE s" a@x.test" CMD-FORGET
   [: P-CLAUDE DB-LIST DB-ROW# 0 T= ;] UT-STORE ;

\ usage and add still keep slot folders: claude a; codex c and d,
\ with A and C live
: UT-SLOT ( n -- ) dup LIVE-IDENTITY TTRUE SAVE-LIVE ;

: UT-SEED-SLOTS ( -- )
   UT-LIVE-B
   P-CODEX UT-SLOT
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   P-CLAUDE UT-SLOT
   P-CODEX UT-SLOT ;

\ a damaged slot still lists
: UT-DAMAGED-SLOT ( -- )
   P-CLAUDE s" bad@x.test" SLOT-DIR$ ENSURE-PRIVATE
   P-CLAUDE s" bad@x.test" s" credentials.json" SLOT-FILE$ s" garbage" WRITE-PRIVATE
   P-CLAUDE s" bad@x.test" s" oauth-account.json" SLOT-FILE$ s\" {\"emailAddress\":\"bad@x.test\"}" WRITE-PRIVATE
   P-CLAUDE LIST-ACCOUNTS ACCT# 2 T=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" bad@x.test" SLOT-DIR$ FS:REMOVE-TREE ;

: UT-WRITE-SCRIPT ( ptr u8 n ptr u8 n -- ) {: n nu body bu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin" SB-APPEND SB$ ENSURE-PRIVATE
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu body bu FS:WRITE-ALL
   f fu FS:CHMOD-X ;

\ a fake curl: answers each provider URL from the Authorization header it is
\ given, writes the body to the -o file, prints the status, and logs the call
: UT-FAKE-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=; grant=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\"); echo \"hdrmode $(/usr/bin/stat -c %a \"${2#@}\")\" >> \"$KIBA_TEST_LOG\"; echo \"ua $(/usr/bin/grep ^User-Agent: \"${2#@}\")\" >> \"$KIBA_TEST_LOG\";; *) echo \"argvheader $2\" >> \"$KIBA_TEST_LOG\";; esac; shift;; --data-binary) echo \"data $2\" >> \"$KIBA_TEST_LOG\"; grant=$(/usr/bin/cat \"${2#@}\"); shift;; -X|-m|-w) shift;; *) url=$1;; esac; shift; done\necho \"$url $auth\" >> \"$KIBA_TEST_LOG\"\ncode=200; body='{}'\ncase \"$url\" in\n*api.anthropic.com/api/oauth/usage\\?cedar_ember=1\\&at_wall=1) case \"$auth\" in *sk-a) body='{\"five_hour\":{\"utilization\":56.25,\"resets_at\":\"2026-09-15T14:00:00+00:00\"},\"seven_day\":{\"utilization\":100,\"resets_at\":\"2026-09-21T11:00:00+00:00\"},\"limits\":[{\"kind\":\"session\",\"group\":\"session\",\"scope\":null,\"percent\":56},{\"kind\":\"weekly_scoped\",\"group\":\"weekly\",\"scope\":{\"model\":{\"id\":null,\"display_name\":\"Fable\"},\"surface\":null},\"percent\":48,\"resets_at\":\"2026-09-22T13:00:00+00:00\"}]}';; *sk-b-new) body='{\"five_hour\":{\"utilization\":12.4,\"resets_at\":\"2026-09-15T15:00:00+00:00\"},\"seven_day_oauth_apps\":{\"utilization\":0.5,\"resets_at\":\"\"}}';; *) code=401; body='{\"error\":\"expired\"}';; esac;;\n*platform.claude.com/v1/oauth/token) case \"$grant\" in *r-e*) code=429; body='{\"error\":{\"type\":\"rate_limit_error\"}}';; *) body='{\"access_token\":\"sk-b-new\",\"refresh_token\":\"r-b-new\",\"expires_in\":3600,\"refresh_token_expires_in\":2592000}';; esac;;\n*chatgpt.com/backend-api/wham/usage) case \"$auth\" in *at-c) body='{\"plan_type\":\"pro\",\"rate_limit\":{\"allowed\":false,\"limit_reached\":true,\"primary_window\":{\"used_percent\":100,\"limit_window_seconds\":604800,\"reset_after_seconds\":433078,\"reset_at\":1789904220},\"secondary_window\":null}}';; *at-d2) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000,\"reset_at\":1789489142},\"secondary_window\":{\"used_percent\":40,\"limit_window_seconds\":604800,\"reset_at\":1790075942}}}';; *at-z|*at-y) code=401; body='{\"error\":{\"code\":\"token_revoked\"}}';; *) code=401; body='{\"error\":{\"code\":\"token_expired\"}}';; esac;;\n*auth.openai.com/oauth/token) case \"$grant\" in *rt-z*) code=401; body='{\"error\":\"invalid_grant\"}';; *rt-y*) code=503; body='';; *) body='{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\"}';; esac;;\n*) code=404;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf '%s' \"$code\"\n"
   UT-WRITE-SCRIPT ;

: AUTH-D2$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\",\"account_id\":\"acct\"}}" ;

: AUTH-Y$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-y\",\"refresh_token\":\"rt-y\",\"account_id\":\"acct\"}}" ;

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
   s" KIBA_TEST_LOG" GETENV ;

\ ---- usage on the store ------------------------------------------------------
variable UT-C0
variable UT-X0
create UT-HELD 32 allot

\ ID-SLOT: email a u, organization o ou (none when empty), no plan
: UT-ID ( ptr u8 n ptr u8 n -- ) {: a u o ou :}
   SB-RESET s\" {\"emailAddress\":\"" SB-APPEND a u SB-APPEND [char] " SB-APPEND-C
   ou 0 > if s\" ,\"organizationUuid\":\"" SB-APPEND o ou SB-APPEND [char] " SB-APPEND-C then
   [char] } SB-APPEND-C
   SB$ ID-SLOT CLAUDE-OAUTH-IDENTITY TTRUE ;

: UT-PUT-RAW ( n ptr u8 n ptr u8 n -- ) {: p a u l lu :}
   [: p a u ID-SLOT l lu UT-BUF -1 false DB-PUT ;] DB-WRITE ;

\ the row p a u holding login l lu, for email a u in organization o ou
: UT-PUT-ORG ( n ptr u8 n ptr u8 n ptr u8 n -- ) {: p a u o ou l lu :}
   a u o ou UT-ID
   [: p a u l lu UT-PUT-RAW ;] UT-STORE ;

: UT-PUT ( n ptr u8 n ptr u8 n -- ) {: p a u l lu :}
   p a u s" " l lu UT-PUT-ORG ;

: UT-RECORD-KEEP ( n ptr u8 n -- ) DB-FETCH TTRUE 0 DB-ROW-USAGE TTRUE ;

\ row p a u's usage record, in the record readers
: UT-RECORD ( n ptr u8 n -- ) {: p a u :}
   [: p a u UT-RECORD-KEEP ;] UT-STORE ;

: UT-STATE= ( ptr u8 n -- ) {: a u :}
   DB-USAGE-STATE DB-STATE$ a u T$= ;

: UT-PLAN= ( n ptr u8 n ptr u8 n -- ) {: p a u l lu :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-PLAN$ l lu T$= ;] UT-STORE ;

: UT-ROW-LOGIN ( n ptr u8 n [ ptr u8 n -- ] -- ) {: p a u check :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-LOGIN$ check execute ;] UT-STORE ;

: UT-COUNT-USAGES ( n -- ) {: p :}
   s" SELECT count(*) FROM history WHERE provider = ? AND kind = 'usage'" s" test"
   [: p PROVIDER$ DB-TEXT+ ;] [: 0 DB-COL-INT UT-N ! ;] DB-QUERY ;

\ the usage events provider p has recorded
: UT-USAGES ( n -- n ) {: p :}
   0 UT-N ! [: p UT-COUNT-USAGES ;] UT-STORE UT-N @ ;

: UT-QUERY-LIVE ( n ptr u8 n -- ) {: p a u :}
   s\" SELECT instr(details, '\"live\":true') > 0 FROM history WHERE provider = ? AND kind = 'usage' AND name = ? ORDER BY id DESC LIMIT 1" s" test"
   [: p PROVIDER$ DB-TEXT+ a u DB-TEXT+ ;] [: 0 DB-COL-INT UT-N ! ;] DB-QUERY ;

\ 1 when row p a u's last usage event was read live, 0 when not, -1 when
\ it has none
: UT-LAST-LIVE ( n ptr u8 n -- n ) {: p a u :}
   -1 UT-N ! [: p a u UT-QUERY-LIVE ;] UT-STORE UT-N @ ;

\ row p a u's record replaced by an ok one fetched at epoch second at
: UT-SET-AT ( n ptr u8 n n -- ) {: p a u at :}
   SB-RESET s\" {\"fetchedAt\":" SB-APPEND at FMT:SB-U
   s\" ,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" SB-APPEND SB$ DB-USAGE-DECODE
   DB-USAGE-AT at T=
   [: [: p a u UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE ;

: UT-USAGE-CLAUDE ( -- )
   P-CLAUDE s" a@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 3 T=
   0 DB-LIMIT-LABEL$ s" Session (5-hour)" T$=
   0 DB-LIMIT-PERCENT 56 T=
   1 DB-LIMIT-PERCENT 100 T=
   1 DB-LIMIT-RESETS$ s" 2026-09-21T11:00:00+00:00" T$=
   2 DB-LIMIT-LABEL$ s" Fable Weekly" T$=
   2 DB-LIMIT-PERCENT 48 T=
   2 DB-LIMIT-RESETS$ s" 2026-09-22T13:00:00+00:00" T$=
   DB-USAGE-AT 0 > TTRUE
   DB-RESETS? TFALSE
   P-CLAUDE s" a@x.test" UT-LAST-LIVE 1 T=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" a@x.test" CREDS-A$ UT-LOGIN=
   P-CLAUDE s" b@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 2 T=
   0 DB-LIMIT-PERCENT 12 T=
   1 DB-LIMIT-PERCENT 1 T=
   1 DB-LIMIT-LABEL$ s" Weekly (7-day)" T$=
   P-CLAUDE s" b@x.test" UT-LAST-LIVE 0 T=
   P-CLAUDE s" e@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" Anthropic's token endpoint answered 429" T$=
   P-CLAUDE s" e@x.test" CREDS-E$ UT-LOGIN=
   P-CLAUDE s" f@x.test" UT-RECORD s" missing" UT-STATE=
   DB-USAGE-NOTE$ s" access token expired and no refresh token is saved; log in again" T$= ;

: UT-USAGE-CODEX ( -- )
   P-CODEX s" c@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 1 T=
   0 DB-LIMIT-LABEL$ s" Weekly (7-day)" T$=
   0 DB-LIMIT-PERCENT 100 T=
   0 DB-LIMIT-RESETS$ s" 2026-09-20T11:37:00Z" T$=
   P-CODEX s" c@x.test" s" pro" UT-PLAN=
   P-CODEX s" c@x.test" UT-LAST-LIVE 1 T=
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 2 T=
   0 DB-LIMIT-LABEL$ s" Session (5-hour)" T$=
   0 DB-LIMIT-PERCENT 12 T=
   1 DB-LIMIT-PERCENT 40 T=
   P-CODEX s" y@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" OpenAI's token endpoint answered 503" T$=
   P-CODEX s" y@x.test" AUTH-Y$ UT-LOGIN= ;

\ tokens travel in a 0600 header file, never argv; the scratch files go
: UT-USAGE-LOG ( -- )
   s" /headers.txt" PSUB-PUBLIC$ FS:FILE? TFALSE
   s" /body.json" PSUB-PUBLIC$ FS:FILE? TFALSE
   STORE$ {: s su :}
   SB-RESET s" data @" SB-APPEND s su SB-APPEND s" /probe/request.json" SB-APPEND
   SB$ UT-BUF 256 SPAN-COPY {: r ru :}
   LOG$ READ-FILE$ {: l lu :}
   l lu s" argvheader Authorization" CONTAINS? TFALSE
   l lu s" hdrmode 600" CONTAINS? TTRUE
   l lu r ru CONTAINS? TTRUE
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" https://api.anthropic.com/api/oauth/usage?cedar_ember=1&at_wall=1" CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   l lu s" Authorization: Bearer sk-a" CONTAINS? TTRUE
   l lu s" Authorization: Bearer at-y" CONTAINS? TTRUE
   l lu s" ua User-Agent: kiba" CONTAINS? TTRUE
   l lu s" ua User-Agent: codex-cli" CONTAINS? TTRUE
   l lu s" ua User-Agent: claude-cli/2.1.282 (external, cli)" CONTAINS? TTRUE ;

\ live claude a@x.test (sk-a) and codex c@x.test, saved back first; saved
\ b@x.test refreshes its expired token, e@x.test's refresh is rate limited
\ (an error, not a dead login), f@x.test has no refresh token; saved
\ d@x.test refreshes after a 401, y@x.test's refresh meets a 503. Each
\ account's error stays its own: the command succeeds.
: UT-USAGE ( -- )
   UT-FAKE-CURL
   P-CLAUDE s" b@x.test" CREDS-B$ UT-PUT
   P-CLAUDE s" e@x.test" CREDS-E$ UT-PUT
   P-CLAUDE s" f@x.test" CREDS-F$ UT-PUT
   P-CODEX s" y@x.test" AUTH-Y$ UT-PUT
   P-CLAUDE UT-USAGES UT-C0 !
   P-CODEX UT-USAGES UT-X0 !
   -1 CMD-USAGE
   P-CLAUDE UT-USAGES UT-C0 @ 4 + T=
   P-CODEX UT-USAGES UT-X0 @ 3 + T=
   UT-USAGE-CLAUDE
   UT-USAGE-CODEX
   UT-USAGE-LOG
   P-CLAUDE s" e@x.test" CMD-FORGET
   P-CLAUDE s" f@x.test" CMD-FORGET
   P-CODEX s" y@x.test" CMD-FORGET ;

: UT-RENEWED-B ( ptr u8 n -- ) {: c cu :}
   c cu CHECK-OBJECT
   c cu s\" \"accessToken\":\"sk-b-new\"" CONTAINS? TTRUE
   c cu s\" \"refreshToken\":\"r-b-new\"" CONTAINS? TTRUE
   c cu s\" \"expiresAt\":2," CONTAINS? TFALSE
   c cu s\" \"refreshTokenExpiresAt\":1," CONTAINS? TFALSE
   c cu s\" \"refreshTokenExpiresAt\":" CONTAINS? TTRUE
   c cu s\" \"subscriptionType\":\"pro\"" CONTAINS? TTRUE ;

: UT-RENEWED-D ( ptr u8 n -- ) {: d du :}
   d du CHECK-OBJECT
   d du s\" \"access_token\":\"at-d2\"" CONTAINS? TTRUE
   d du s\" \"refresh_token\":\"rt-d2\"" CONTAINS? TTRUE
   d du s\" \"account_id\":\"acct\"" CONTAINS? TTRUE
   d du s\" \"last_refresh\":\"" CONTAINS? TTRUE
   d du ID-SLOT CODEX-IDENTITY TTRUE ID-SLOT EMAIL$ s" d@x.test" T$= ;

\ a renewed token is saved back into its row: Claude's members replaced,
\ Codex's last_refresh added
: UT-USAGE-REFRESHED ( -- )
   P-CLAUDE s" b@x.test" [: UT-RENEWED-B ;] UT-ROW-LOGIN
   P-CODEX s" d@x.test" [: UT-RENEWED-D ;] UT-ROW-LOGIN
   P-CLAUDE s" b@x.test" CMD-FORGET ;

\ a login revoked by a sign-out keeps its row, marked revoked
: UT-USAGE-REVOKED ( -- )
   P-CODEX s" z@x.test" AUTH-Z$ UT-PUT
   P-CODEX CMD-USAGE
   P-CODEX s" z@x.test" UT-RECORD s" revoked" UT-STATE=
   DB-USAGE-NOTE$ s" login revoked by a sign-out at chatgpt.com or in codex; log in again" T$=
   P-CODEX s" z@x.test" AUTH-Z$ UT-LOGIN=
   LOG$ READ-FILE$ s" Authorization: Bearer at-z" CONTAINS? TTRUE
   P-CODEX s" z@x.test" CMD-FORGET ;

\ the fake `claude` logs its argv and writes account B into CLAUDE_CONFIG_DIR
: UT-FAKE-CLAUDE ( -- )
   s" claude"
   s\" #!/bin/sh\necho \"claude $* cfg=$CLAUDE_CONFIG_DIR\" >> \"$KIBA_TEST_LOG\"\nprintf '%s' '{\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\",\"organizationUuid\":\"org-b\"}}' > \"$CLAUDE_CONFIG_DIR/.claude.json\"\nprintf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}' > \"$CLAUDE_CONFIG_DIR/.credentials.json\"\n"
   UT-WRITE-SCRIPT ;

\ `add` logs in inside a throwaway home: the live login stays where it is,
\ the new login is saved under its name, and the home is gone afterwards.
\ the fake `codex` records where it ran and writes AUTH-D on success
: UT-FAKE-CODEX ( -- )
   s" codex"
   s\" #!/bin/sh\necho \"codexhome $CODEX_HOME\" >> \"$KIBA_TEST_LOG\"\nif [ -e \"$HOME/.codex/auth.json\" ]; then echo present >> \"$KIBA_TEST_LOG\"; else echo absent >> \"$KIBA_TEST_LOG\"; fi\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nprintf '%s' '{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}' > \"$CODEX_HOME/auth.json\"\n"
   UT-WRITE-SCRIPT ;

: UT-ADD ( -- )
   UT-FAKE-CODEX
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /fail-login" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu s" x" FS:WRITE-ALL
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   [: P-CODEX s" " CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   f fu FS:REMOVE-FILE
   HOME$ {: h2 h2u :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: cx cxu :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex.off" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: cxo cxou :}
   cx cxu cxo cxou FS:RENAME-FILE
   [: P-CODEX s" " CMD-ADD ;] E-SW-NO-CLI TTHROWSQ
   CODEX-AUTH$ FS:FILE? TTRUE
   cxo cxou cx cxu FS:RENAME-FILE
   P-CODEX s" " CMD-ADD
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" s" auth.json" SLOT-FILE$ READ-FILE$ AUTH-D$ T$=
   P-CODEX s" c@x.test" s" auth.json" SLOT-FILE$ READ-FILE$ AUTH-C$ T$=
   P-CODEX LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   LOG$ READ-FILE$ {: l lu :}
   l lu s\" present\n" ENDS-WITH? TTRUE
   l lu s" /probe/login-codex/.codex" CONTAINS? TTRUE
   l lu s" absent" CONTAINS? TFALSE ;

\ a Claude add with an expected account prefills the email and saves under
\ the name that actually came back, saying so when it differs
: UT-ADD-CLAUDE ( -- )
   UT-FAKE-CLAUDE
   P-CLAUDE s" b@x.test" CMD-ADD
   LOG$ READ-FILE$ s" auth login --email b@x.test cfg=" CONTAINS? TTRUE
   LOG$ READ-FILE$ s" /probe/login-claude/.claude" CONTAINS? TTRUE
   P-CLAUDE s" b@x.test" s" credentials.json" SLOT-FILE$ READ-FILE$ s\" \"accessToken\":\"sk-b" CONTAINS? TTRUE
   P-CLAUDE s" b@x.test" s" oauth-account.json" SLOT-FILE$ READ-FILE$ s\" \"organizationUuid\":\"org-b\"" CONTAINS? TTRUE
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   P-CLAUDE s" zz@x.test" CMD-ADD
   SAVED-NAME$ s" b@x.test" T$=
   P-CLAUDE s" b@x.test" SLOT-DIR$ FS:REMOVE-TREE ;

\ the live account's expired token is reported, never sent
: CREDS-A-OLD$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a-old\",\"refreshToken\":\"r-a\",\"expiresAt\":1,\"subscriptionType\":\"max\"}}" ;

: UT-LIVE-EXPIRED ( -- )
   CLAUDE-CREDS$ CREDS-A-OLD$ WRITE-PRIVATE
   P-CLAUDE CMD-USAGE
   P-CLAUDE s" a@x.test" UT-RECORD s" expired" UT-STATE=
   DB-USAGE-NOTE$ s" access token expired; Claude Code refreshes it on its next run" T$=
   DB-LIMIT# 0 T=
   LOG$ READ-FILE$ s" Bearer sk-a-old" CONTAINS? TFALSE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A-OLD$ T$=
   P-CLAUDE s" a@x.test" CREDS-A-OLD$ UT-LOGIN=
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   P-CLAUDE CMD-USAGE
   P-CLAUDE s" a@x.test" UT-RECORD s" ok" UT-STATE= ;

\ one provider's unreadable live file does not stop the other's probe; the
\ command fails once both have run
: UT-USAGE-ISOLATION ( -- )
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   P-CODEX UT-USAGES UT-X0 !
   [: -1 CMD-USAGE ;] E-SW-REPORTED TTHROWSQ
   P-CODEX UT-USAGES UT-X0 @ 2 + T=
   P-CODEX s" c@x.test" UT-RECORD s" ok" UT-STATE=
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE ;

: UT-PUT-C-GARBAGE ( -- )
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE
   [: P-CODEX s" c@x.test" ID-SLOT s" garbage" UT-BUF -1 false DB-PUT ;] DB-WRITE ;

\ a damaged row with the live account's name does not block saving the
\ live login over it
: UT-DAMAGED-LIVE-SLOT ( -- )
   [: UT-PUT-C-GARBAGE ;] UT-STORE
   P-CODEX CMD-USAGE
   P-CODEX s" c@x.test" AUTH-C$ UT-LOGIN=
   P-CODEX s" c@x.test" UT-RECORD s" ok" UT-STATE= ;

\ a damaged bare row is not claimed by a login whose organization another
\ row already holds: that row keeps the name, the damaged one stays put
: UT-DAMAGED-NOT-CLAIMED ( -- )
   P-CLAUDE s" a@x.test" s" org-z" s" garbage" UT-PUT-ORG
   P-CLAUDE s" a@x.test #2" s" org-a" CREDS-A$ UT-PUT-ORG
   P-CLAUDE UT-LIVE-NAME s" a@x.test #2" T$=
   P-CLAUDE CMD-USAGE
   P-CLAUDE s" a@x.test" s" garbage" UT-LOGIN=
   P-CLAUDE s" a@x.test" UT-RECORD s" missing" UT-STATE=
   DB-USAGE-NOTE$ s" no access token saved; log in again" T$=
   P-CLAUDE s" a@x.test #2" UT-RECORD s" ok" UT-STATE=
   P-CLAUDE s" a@x.test #2" UT-LAST-LIVE 1 T=
   P-CLAUDE s" a@x.test" CMD-FORGET
   P-CLAUDE s" a@x.test #2" CMD-FORGET
   P-CLAUDE UT-LIVE-NAME s" a@x.test" T$=
   P-CLAUDE CMD-SAVE ;

: UT-HOLD ( ptr u8 n -- ) {: c cu :}
   cu 32 T= c UT-HELD 32 BYTE-COPY ;

\ a pending install stops the probe before anything is probed or refreshed
: UT-UNREPAIRED ( -- )
   [: [: P-CLAUDE s" b@x.test" DB-NOTE-PENDING UT-HOLD ;] DB-WRITE ;] UT-STORE
   P-CLAUDE UT-USAGES UT-C0 !
   [: P-CLAUDE CMD-USAGE ;] E-SW-REPORTED TTHROWSQ
   P-CLAUDE UT-USAGES UT-C0 @ T=
   E-SW-UNREPAIRED REASON$
   s" kiba: the claude switch to b@x.test did not finish; nothing is probed or refreshed until a switch completes" T$=
   [: [: P-CLAUDE UT-HELD 32 DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   P-CLAUDE UT-PENDING? TFALSE ;

\ when every saved login was probed after the run began, the recorded
\ outcomes are reported and nothing is probed
: UT-USAGE-CHECKED ( -- )
   [: P-CODEX DB-LIST DB-ROW# 2 T= ;] UT-STORE
   epoch-seconds 100000 + {: later :}
   P-CODEX s" c@x.test" later UT-SET-AT
   P-CODEX s" d@x.test" later UT-SET-AT
   P-CODEX UT-USAGES UT-X0 !
   LOG$ READ-FILE$ nip {: lu :}
   P-CODEX CMD-USAGE
   P-CODEX UT-USAGES UT-X0 @ T=
   LOG$ READ-FILE$ nip lu T=
   P-CODEX s" c@x.test" UT-RECORD DB-USAGE-AT later T=
   P-CODEX s" c@x.test" 1 UT-SET-AT
   P-CODEX s" d@x.test" 1 UT-SET-AT ;

\ use probes the login it installs as live, then the one it saved back as
\ saved
: UT-USE-PROBES ( -- )
   P-CODEX UT-USAGES UT-X0 !
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX UT-USAGES UT-X0 @ 2 + T=
   P-CODEX s" d@x.test" UT-LAST-LIVE 1 T=
   P-CODEX s" c@x.test" UT-LAST-LIVE 0 T=
   P-CODEX s" d@x.test" UT-RECORD s" ok" UT-STATE=
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$= ;

\ a lock left by a dead process is taken over; a live holder is respected
: UT-STALE-LOCK ( -- )
   LOCK$ ENSURE-PRIVATE
   LOCK$ {: l lu :}
   SB-RESET l lu SB-APPEND s" /pid" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu s" 999999999" WRITE-PRIVATE
   UT-NESTED
   LOCK$ FS:DIR? TFALSE
   LOCK$ ENSURE-PRIVATE
   SB-RESET getpid FMT:SB-U SB$ UT-PID 32 SPAN-COPY {: pt ptu :}
   f fu pt ptu WRITE-PRIVATE
   f fu READ-FILE$ pt ptu T$=
   [: UT-NESTED ;] E-SW-LOCKED TTHROWSQ
   f fu FS:REMOVE-FILE
   LOCK$ FS:REMOVE-DIR ;

\ ---- the SQLite store -------------------------------------------------------
create UT-NUL 3 allot                 \ a login blob holding a NUL byte
create UT-CLAIM 32 allot
variable UT-V

\ kiba-mac's JSONEncoder (.sortedKeys) bytes for one usage record
: USAGE-LIT$ ( -- ptr u8 n )
   s\" {\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}" ;

: UT-DB-OPEN ( -- )
   $61 UT-NUL c! 0 UT-NUL 1+ c! $62 UT-NUL 2 + c!
   DB-OPEN
   0 UT-V !
   s" PRAGMA user_version" s" test" [: ;] [: 0 DB-COL-INT UT-V ! ;] DB-QUERY
   UT-V @ 5 T= ;

: UT-DB-PUT ( -- )
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" b@x.test" ID-SLOT UT-NUL 3 UT-NUL -1 false DB-PUT
      P-CLAUDE s" a@x.test" ID-SLOT CREDS-A$ OAUTH-A$ false DB-PUT ;] DB-WRITE
   P-CLAUDE DB-LIST DB-ROW# 2 T=
   0 DB-ROW-NAME$ s" a@x.test" T$=
   1 DB-ROW-NAME$ s" b@x.test" T$= ;

: UT-DB-FETCH ( -- )
   P-CLAUDE s" b@x.test" DB-FETCH TTRUE DB-ROW# 1 T=
   0 DB-ROW-NAME$ s" b@x.test" T$=
   0 DB-ROW-EMAIL$ s" a@x.test" T$=
   0 DB-ROW-ORG$ s" org-a" T$=
   0 DB-ROW-PLAN$ s" max" T$=
   0 DB-ROW-LOGIN$ UT-NUL 3 T$=
   0 DB-ROW-PROFILE$ nip -1 T=
   0 DB-ROW-USAGE TFALSE
   P-CLAUDE s" a@x.test" DB-FETCH TTRUE
   0 DB-ROW-LOGIN$ CREDS-A$ T$=
   0 DB-ROW-PROFILE$ OAUTH-A$ T$= ;

\ the record survives the store byte for byte, plan coalesce included
: UT-DB-USAGE ( -- )
   USAGE-LIT$ DB-USAGE-DECODE
   DB-USAGE-ENCODE USAGE-LIT$ T$=
   DB-USAGE-AT 1700000000 T=
   DB-USAGE-STATE DB-STATE$ s" throttled" T$=
   DB-USAGE-NOTE$ s\" a/b \"q\"\n" T$=
   DB-LIMIT# 2 T=
   1 DB-LIMIT-LABEL$ s" Weekly / Opus" T$=
   1 DB-LIMIT-PERCENT -1 T=
   DB-RESETS? TTRUE DB-RESETS-COUNT 2 T=
   [: P-CLAUDE s" a@x.test" s" pro" DB-SET-USAGE ;] DB-WRITE
   s" {}" DB-USAGE-DECODE
   DB-USAGE-NOTE$ s" usage record is unreadable; refresh usage" T$=
   P-CLAUDE s" a@x.test" DB-FETCH TTRUE
   0 DB-ROW-PLAN$ s" pro" T$=
   0 DB-ROW-USAGE TTRUE
   DB-USAGE-ENCODE USAGE-LIT$ T$= ;

: KEEP-CLAIM ( ptr u8 n -- ) {: c cu :}
   cu 32 T= c UT-CLAIM 32 BYTE-COPY ;

: UT-DB-PENDING ( -- )
   [: P-CLAUDE s" a@x.test" DB-NOTE-PENDING KEEP-CLAIM
      P-CLAUDE UT-CLAIM 32 DB-OWNS? TTRUE ;] DB-WRITE
   [: P-CLAUDE s" b@x.test" DB-NOTE-PENDING 2drop
      P-CLAUDE UT-CLAIM 32 DB-OWNS? TFALSE
      P-CLAUDE UT-CLAIM 32 DB-CLEAR-PENDING ;] DB-WRITE
   P-CLAUDE DB-PENDING TTRUE s" b@x.test" T$= ;

: UT-DB-ROLLBACK ( -- )
   [: [: P-CLAUDE s" c@x.test" ID-SLOT CREDS-A$ UT-NUL -1 false DB-PUT
         E-SW-LOGIN throw ;] DB-WRITE ;] E-SW-LOGIN TTHROWSQ
   P-CLAUDE s" c@x.test" DB-FETCH TFALSE ;

\ kiba-mac's snapshot bytes: two saved Claude logins under one email, the
\ live one in the second organization, and a live Codex login never saved
: SNAP-LIT$ ( -- ptr u8 n )
   s\" {\"providers\":[{\"accounts\":[{\"active\":false,\"name\":\"a@x.test\",\"plan\":\"max\",\"usage\":{\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}},{\"active\":true,\"name\":\"a@x.test #2\",\"plan\":\"team\"}],\"installedAt\":1700000500,\"live\":{\"email\":\"a@x.test\",\"plan\":\"team\"},\"provider\":\"claude\"},{\"accounts\":[],\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"},\"provider\":\"codex\"}]}" ;

\ the same store once the Claude config is not JSON and c@x.test is saved
: SNAP-ERROR-LIT$ ( -- ptr u8 n )
   s\" {\"providers\":[{\"accounts\":[{\"active\":false,\"name\":\"a@x.test\",\"plan\":\"max\",\"usage\":{\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}},{\"active\":false,\"name\":\"a@x.test #2\",\"plan\":\"team\"}],\"error\":\"kiba: a login file is not valid JSON\",\"installedAt\":1700000500,\"provider\":\"claude\"},{\"accounts\":[{\"active\":true,\"name\":\"c@x.test\",\"plan\":\"plus\"}],\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"},\"provider\":\"codex\"}]}" ;

: UT-STATUS-ROWS ( -- )
   s" DELETE FROM account" s" test" DB-EXEC
   s" DELETE FROM live" s" test" DB-EXEC
   USAGE-LIT$ DB-USAGE-DECODE
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" a@x.test" ID-SLOT CREDS-A$ OAUTH-A$ true DB-PUT ;] DB-WRITE
   CFG-A2$ CREDS-A2$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" a@x.test #2" ID-SLOT CREDS-A2$ UT-NUL -1 false DB-PUT
      P-CLAUDE s" a@x.test #2" 1700000500 true DB-NOTE-INSTALLED ;] DB-WRITE ;

\ the active mark follows the live organization
: UT-STATUS-JSON ( -- )
   UT-STATUS-ROWS
   CLAUDE-CONFIG$ CFG-A2$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A2$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   STATUS-JSON$ SNAP-LIT$ T$=
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   STATUS-JSON$ s\" {\"active\":true,\"name\":\"a@x.test\",\"plan\":\"max\"" CONTAINS? TTRUE
   STATUS-JSON$ s\" {\"active\":false,\"name\":\"a@x.test #2\"" CONTAINS? TTRUE ;

\ an unreadable Claude login is Claude's error alone: its saved accounts and
\ install time still show, and Codex reads as before
: UT-STATUS-ERROR ( -- )
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE
   [: P-CODEX s" c@x.test" ID-SLOT AUTH-C$ UT-NUL -1 false DB-PUT ;] DB-WRITE
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   STATUS-JSON$ SNAP-ERROR-LIT$ T$= ;

\ a newer schema is refused and leaves the store closed
: UT-DB-VERSION ( -- )
   s" PRAGMA user_version = 6" s" test" DB-EXEC
   DB-CLOSE
   [: DB-OPEN ;] E-SW-DB-VERSION TTHROWSQ
   [: P-CLAUDE DB-LIST ;] E-SW-DB TTHROWSQ ;

: UT-DB ( -- )
   UT-DB-OPEN
   UT-DB-PUT
   UT-DB-FETCH
   UT-DB-USAGE
   UT-DB-PENDING
   UT-DB-ROLLBACK
   UT-STATUS-JSON
   UT-STATUS-ERROR
   UT-DB-VERSION ;

: UT-NAMES ( -- )
   s" a@x.test #2" s" a@x.test" NAME-SUFFIX# 2 T=
   s" a@x.test #10" s" a@x.test" NAME-SUFFIX# 10 T=
   s" a@x.test #foo" s" a@x.test" NAME-SUFFIX# -1 T=
   s" a@x.test #foo" s" a@x.test" NAME-FOR-EMAIL? TFALSE
   s" a@x.test #10" NAME-EMAIL s" a@x.test" T$=
   s" a@x.test" NAME-EMAIL s" a@x.test" T$= ;

\ marker files outside <provider>/<name>/ are not accounts
: UT-STRAY-MARKERS ( -- )
   P-CODEX PROVIDER-DIR$ {: d du :}
   SB-RESET d du SB-APPEND s" /auth.json" SB-APPEND SB$ s" {}" WRITE-PRIVATE
   P-CODEX s" c@x.test" s" sub" SLOT-FILE$ ENSURE-PRIVATE
   P-CODEX s" c@x.test" s" sub/auth.json" SLOT-FILE$ s" {}" WRITE-PRIVATE
   P-CODEX LIST-ACCOUNTS ACCT# 2 T=
   0 ACCT-NAME s" c@x.test" T$=
   1 ACCT-NAME s" d@x.test" T$=
   SB-RESET d du SB-APPEND s" /auth.json" SB-APPEND SB$ FS:REMOVE-FILE
   P-CODEX s" c@x.test" s" sub" SLOT-FILE$ FS:REMOVE-TREE ;

\ ---- the per-provider turn ---------------------------------------------------
create UT-QUEUE PATH-CAP allot   variable UT-QUEUE-U
create UT-TURN PATH-CAP allot    variable UT-TURN-U
create UT-STALE PATH-CAP allot   variable UT-STALE-U
1024 constant UT-LIST-CAP
create UT-LIST UT-LIST-CAP allot

: UT-TURN$ ( -- ptr u8 n )
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /turn-claude" SB-APPEND
   SB$ UT-TURN UT-TURN-U PATH!
   UT-TURN UT-TURN-U @ ;

: UT-QUEUE$ ( -- ptr u8 n )
   UT-TURN$ {: t tu :}
   SB-RESET t tu SB-APPEND s" .queue" SB-APPEND
   SB$ UT-QUEUE UT-QUEUE-U PATH!
   UT-QUEUE UT-QUEUE-U @ ;

\ an entry no waiter holds, sorting before any a waiter makes
: UT-STALE$ ( -- ptr u8 n )
   UT-QUEUE$ {: q qu :}
   SB-RESET q qu SB-APPEND
   s" /00000000000000000000-0000000001-00000000000000000000" SB-APPEND
   SB$ UT-STALE UT-STALE-U PATH!
   UT-STALE UT-STALE-U @ ;

: UT-QUEUE-LEN ( -- n )
   UT-QUEUE$ UT-LIST UT-LIST-CAP FS-LIST:NAMES ;

: UT-TURN-ROUND ( -- )
   P-CLAUDE TURN-ENTER
   UT-QUEUE-LEN 0 T<>
   P-CLAUDE TURN-LEAVE
   UT-QUEUE-LEN 0 T= ;

: UT-TURN-STALE ( -- )
   UT-STALE$ s" " WRITE-PRIVATE
   UT-STALE$ FS:FILE? TTRUE
   P-CLAUDE TURN-ENTER
   UT-STALE$ FS:FILE? TFALSE
   P-CLAUDE TURN-LEAVE
   UT-QUEUE-LEN 0 T= ;

\ flock locks belong to the open file description, so a second open of the
\ turn file in this process holds it against TURN-ENTER
: UT-TURN-BUSY ( -- )
   UT-TURN$ FS:>PATHZ open-rd {: fd :}
   fd >FD FS-LOCK:TRY TTRUE
   300 TURN-WAIT-MS !
   [: P-CLAUDE TURN-ENTER ;] E-SW-TURN-BUSY TTHROWSQ
   120000 TURN-WAIT-MS !
   fd close
   UT-QUEUE-LEN 0 T= ;

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
   UT-STORE-SAVE
   UT-STORE-USE
   UT-STORE-USE-CODEX
   UT-SAME-EMAIL
   UT-INSTALL-INSERT
   UT-FAILED-FIRST-WRITE
   UT-CREDS-DIR
   UT-RESTORED
   UT-REPAIR-PENDING
   UT-MISMATCH
   UT-DAMAGED-ROW
   UT-API-KEY
   UT-SYMLINK
   UT-MIXED-PAIR
   UT-UNRESTORED
   UT-ORPHAN
   UT-STORE-FORGET
   UT-SEED-SLOTS
   UT-DAMAGED-SLOT
   UT-STRAY-MARKERS
   UT-ADD
   UT-ADD-CLAUDE
   UT-PCT
   UT-USAGE
   UT-USAGE-REFRESHED
   UT-USAGE-REVOKED
   UT-LIVE-EXPIRED
   UT-USAGE-ISOLATION
   UT-DAMAGED-LIVE-SLOT
   UT-DAMAGED-NOT-CLAIMED
   UT-UNREPAIRED
   UT-USAGE-CHECKED
   UT-USE-PROBES
   UT-STALE-LOCK
   UT-NAMES
   UT-DB
   UT-TURN-ROUND
   UT-TURN-STALE
   UT-TURN-BUSY
   T-REPORT ;

UT-MAIN

;package
