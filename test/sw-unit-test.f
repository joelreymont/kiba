\ sw-unit-test.f - checked kiba tests.
\ Run through test.sh: HOME, XDG_DATA_HOME, and PATH must point at a scratch tree.
require ../src/kiba.f
require ../src/sw-turn.f
require src/lib/test.f
require src/lib/fs-list.f
require src/lib/fs-lock.f
require src/lib/fd.f
require src/lib/process.f
require src/lib/spawn.f
require src/lib/time.f
require src/lib/test/stderr.f
require src/lib/test/runner.f

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

\ credentials that cannot name a plan leave the config's account, plan empty
: UT-PLAN-UNREADABLE ( -- )
   CFG-A$ s" not json" ID-LIVE CLAUDE-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" a@x.test" T$=
   ID-LIVE ORG$ s" org-a" T$=
   ID-LIVE PLAN$ nip 0 T=
   CFG-A$ CREDS-A$ ID-LIVE CLAUDE-IDENTITY TTRUE
   CFG-A$ s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-g\"}}" ID-LIVE CLAUDE-IDENTITY TTRUE
   ID-LIVE EMAIL$ s" a@x.test" T$=
   ID-LIVE ORG$ s" org-a" T$=
   ID-LIVE PLAN$ nip 0 T= ;

\ claims whose seats object, two objects down, repeats a key
: CLAIMS-R$ ( -- ptr u8 n )
   s\" {\"email\":\"r@x.test\",\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"plus\",\"seats\":{\"n\":1,\"n\":2}}}" ;

: AUTH-R$ ( -- ptr u8 n )
   s\" {\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InJAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsInNlYXRzIjp7Im4iOjEsIm4iOjJ9fX0.c2ln\"}}" ;

\ claims that repeat a key deeper than JSONDoc looks are no login, as
\ fromAuth's JSONFields refuses them
: UT-CLAIMS-REPEAT ( -- )
   AUTH-R$ CHECK-OBJECT
   CLAIMS-R$ CHECK-OBJECT
   [: AUTH-R$ ID-SLOT CODEX-IDENTITY drop ;] E-SW-JSON TTHROWSQ ;

\ an identity field longer than its buffer is an error, never a missing field
: UT-FIELD-LONG ( -- )
   [: CFG-A$ s\" {\"claudeAiOauth\":{\"subscriptionType\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\"}}" ID-SLOT CLAUDE-IDENTITY drop ;]
   E-SW-CAPACITY TTHROWSQ ;

\ an integer spelled as a whole decimal reads as that integer
: UT-WHOLE-EXPIRY ( -- )
   s\" {\"claudeAiOauth\":{\"expiresAt\":4102444800000.0}}" s" claudeAiOauth" s" expiresAt" DOC-INT2
   TTRUE 4102444800000 T= ;

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

: UT-ADDING-KEEP ( n -- ) DB-ADDING UT-N ! 2drop ;

: UT-ADDING? ( n -- bool ) {: p :}
   [: p UT-ADDING-KEEP ;] UT-STORE UT-N @ ;

\ plants an add's record of p's live login a u, as a store a Mac's add
\ left holds one; kiba never writes it
: UT-PLANT-ADDING ( n ptr u8 n -- ) {: p a u :}
   SB-RESET s" INSERT INTO adding (provider, live, service) VALUES ('" SB-APPEND
   p PROVIDER$ SB-APPEND s" ', CAST('" SB-APPEND
   a u SB-APPEND s" ' AS BLOB), '')" SB-APPEND
   SB$ s" test" DB-EXEC ;

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

\ taking Codex's live name leaves the Claude rows a caller listed
: UT-NAME-KEEPS-ROWS ( -- )
   P-CODEX LIVE-IDENTITY TTRUE
   [: P-CLAUDE DB-LIST
      P-CODEX ID-LIVE DB-LIVE-NAME s" d@x.test" T$=
      DB-ROW# 2 T=
      0 DB-ROW-NAME$ s" a@x.test" T$=
      1 DB-ROW-NAME$ s" b@x.test" T$= ;] UT-STORE ;

\ Codex's installed, pending and adding reads answer their records and leave
\ the Claude rows a caller listed
: UT-MARKS-READ ( -- )
   P-CLAUDE DB-LIST
   P-CODEX DB-INSTALLED TTRUE s" d@x.test" T$=
   P-CODEX DB-PENDING TTRUE s" c@x.test" T$=
   P-CODEX DB-ADDING TTRUE AUTH-C9$ T$=
   DB-ROW# 2 T=
   0 DB-ROW-NAME$ s" a@x.test" T$=
   1 DB-ROW-NAME$ s" b@x.test" T$= ;

\ notes the marks, reads them and clears them again in one transaction
: UT-MARKS ( -- )
   P-CODEX s" c@x.test" DB-NOTE-PENDING {: c cu :}
   P-CODEX AUTH-C9$ UT-PLANT-ADDING
   UT-MARKS-READ
   P-CODEX DB-CLEAR-ADDING
   P-CODEX c cu DB-CLEAR-PENDING ;

: UT-READS-KEEP-ROWS ( -- ) [: [: UT-MARKS ;] DB-WRITE ;] UT-STORE ;

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

: CFG-Q$ ( -- ptr u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u9\",\"emailAddress\":\"q@x.test\"}}" ;

\ credentials whose claudeAiOauth repeats a key
: CREDS-Q$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-q\",\"subscriptionType\":\"max\",\"subscriptionType\":\"pro\"}}" ;

\ credentials whose claudeAiOauth repeats a key are saved with no plan, as
\ planFromCreds reads them; their row is refused before anything is
\ claimed, as ClaudeLive.prepare's JSONDoc refuses it
: UT-REPEATED-CREDS ( -- )
   CLAUDE-CONFIG$ CFG-Q$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-Q$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" q@x.test" CREDS-Q$ UT-LOGIN=
   [: P-CLAUDE s" q@x.test" DB-FETCH TTRUE
      0 DB-ROW-PLAN$ nip 0 T= ;] UT-STORE
   P-CLAUDE s" a@x.test" CMD-USE
   P-CLAUDE UT-SWITCHES UT-SW0 !
   [: P-CLAUDE s" q@x.test" CMD-USE ;] E-SW-JSON TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE UT-SWITCHES UT-SW0 @ T=
   P-CLAUDE s" q@x.test" CMD-FORGET ;

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

\ a failed write leaves the old file whole and no temp beside it: refused
\ before the temp exists, in a directory nothing can be written in, and
\ after, by a rename onto a directory
: UT-FAILED-WRITE ( -- )
   UT-LOCKED$ ENSURE-PRIVATE
   UT-REAL$ CREDS-A9$ WRITE-PRIVATE
   UT-LOCKED$ $140 FS:CHMOD-MODE
   [: UT-REAL$ CREDS-A$ WRITE-PRIVATE ;] E-FS-OPEN TTHROWSQ
   UT-LOCKED$ $1C0 FS:CHMOD-MODE
   UT-REAL$ READ-FILE$ CREDS-A9$ T$=
   UT-LOCKED$ UT-BUF 256 FS-LIST:NAMES {: n :}
   UT-BUF n s" creds.json" T$=
   UT-REAL$ FS:REMOVE-FILE
   UT-REAL$ ENSURE-PRIVATE
   [: UT-REAL$ CREDS-A$ WRITE-PRIVATE ;] E-FS-IO TTHROWSQ
   UT-REAL$ FS:DIR? TTRUE
   UT-LOCKED$ UT-BUF 256 FS-LIST:NAMES {: n2 :}
   UT-BUF n2 s" creds.json" T$=
   UT-LOCKED$ FS:REMOVE-TREE ;

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

: UT-NOTE-ADDING ( -- ) P-CLAUDE CREDS-A$ UT-PLANT-ADDING ;
: UT-CLEAR-ADDING ( -- ) [: P-CLAUDE DB-CLEAR-ADDING ;] DB-WRITE ;

\ an add's record of the live login stops save and use
: UT-UNRESTORED ( -- )
   [: UT-NOTE-ADDING ;] UT-STORE
   [: P-CLAUDE CMD-SAVE ;] E-SW-UNRESTORED TTHROWSQ
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-SW-UNRESTORED TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   [: UT-CLEAR-ADDING ;] UT-STORE
   E-SW-UNRESTORED REASON$
   s" kiba: the live claude login waits to be put back after an add; a new claude add does it" T$= ;

\ credentials without a config are nobody's: neither saved nor replaced
: UT-ORPHAN ( -- )
   CLAUDE-CONFIG$ FS:REMOVE-FILE
   [: P-CLAUDE CMD-SAVE ;] E-SW-ORPHAN-LIVE TTHROWSQ
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-SW-ORPHAN-LIVE TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   CLAUDE-CONFIG$ FS:FILE? TFALSE
   CLAUDE-CONFIG$ {: c cu :}
   E-SW-ORPHAN-LIVE REASON$ c cu CONTAINS? TTRUE
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE ;

\ leaves no Claude row, so the store tests below start from an empty list
: UT-STORE-FORGET ( -- )
   P-CLAUDE s" b@x.test" CMD-FORGET
   P-CLAUDE s" b@x.test" UT-ROW? TFALSE
   P-CLAUDE s" a@x.test" UT-ROW? TTRUE
   [: P-CLAUDE s" b@x.test" CMD-FORGET ;] E-SW-NO-ACCOUNT TTHROWSQ
   P-CLAUDE s" a@x.test" CMD-FORGET
   [: P-CLAUDE DB-LIST DB-ROW# 0 T= ;] UT-STORE ;

\ live claude a and codex c for the add and usage tests
: UT-LIVE-AC ( -- )
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE ;

: UT-WRITE-SCRIPT ( ptr u8 n ptr u8 n -- ) {: n nu body bu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin" SB-APPEND SB$ ENSURE-PRIVATE
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu body bu FS:WRITE-ALL
   f fu FS:CHMOD-X ;

\ a fake curl: answers each provider URL from the Authorization header it is
\ given, writes the body to the -o file, prints the status, and logs the call
\ and the request body; a Claude reset answers the word after "w-" in its
\ grant id, a Codex one the word after "at-w-" in its token
: UT-FAKE-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=; grant=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\"); echo \"hdrmode $(/usr/bin/stat -c %a \"${2#@}\")\" >> \"$KIBA_TEST_LOG\"; echo \"ua $(/usr/bin/grep ^User-Agent: \"${2#@}\")\" >> \"$KIBA_TEST_LOG\";; *) echo \"argvheader $2\" >> \"$KIBA_TEST_LOG\";; esac; shift;; --data-binary) echo \"data $2\" >> \"$KIBA_TEST_LOG\"; grant=$(/usr/bin/cat \"${2#@}\"); echo \"body $grant\" >> \"$KIBA_TEST_LOG\"; shift;; -X|-m|-w) shift;; *) url=$1;; esac; shift; done\necho \"$url $auth\" >> \"$KIBA_TEST_LOG\"\ncode=200; body='{}'\ncase \"$url\" in\n*api.anthropic.com/api/oauth/usage\\?cedar_ember=1\\&at_wall=1) case \"$auth\" in *sk-a) body='{\"five_hour\":{\"utilization\":56.25,\"resets_at\":\"2026-09-15T14:00:00+00:00\"},\"seven_day\":{\"utilization\":100,\"resets_at\":\"2026-09-21T11:00:00+00:00\"},\"limits\":[{\"kind\":\"session\",\"group\":\"session\",\"scope\":null,\"percent\":56},{\"kind\":\"weekly_scoped\",\"group\":\"weekly\",\"scope\":{\"model\":{\"id\":null,\"display_name\":\"Fable\"},\"surface\":null},\"percent\":48,\"resets_at\":\"2026-09-22T13:00:00+00:00\"}]}';; *sk-b-new) body='{\"five_hour\":{\"utilization\":12.4,\"resets_at\":\"2026-09-15T15:00:00+00:00\"},\"seven_day_oauth_apps\":{\"utilization\":0.5,\"resets_at\":\"\"}}';; *) code=401; body='{\"error\":\"expired\"}';; esac;;\n*platform.claude.com/v1/oauth/token) case \"$grant\" in *r-e*) code=429; body='{\"error\":{\"type\":\"rate_limit_error\"}}';; *) body='{\"access_token\":\"sk-b-new\",\"refresh_token\":\"r-b-new\",\"expires_in\":3600,\"refresh_token_expires_in\":2592000}';; esac;;\n*chatgpt.com/backend-api/wham/usage) case \"$auth\" in *at-c) body='{\"plan_type\":\"pro\",\"rate_limit\":{\"allowed\":false,\"limit_reached\":true,\"primary_window\":{\"used_percent\":100,\"limit_window_seconds\":604800,\"reset_after_seconds\":433078,\"reset_at\":1789904220},\"secondary_window\":null}}';; *at-d2) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000,\"reset_at\":1789489142},\"secondary_window\":{\"used_percent\":40,\"limit_window_seconds\":604800,\"reset_at\":1790075942}}}';; *at-dup) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":18000,\"used_percent\":20}}}';; *at-whole) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":30,\"limit_window_seconds\":6048e2,\"reset_at\":1789904220.0}},\"rate_limit_reset_credits\":{\"available_count\":2.0}}';; *at-long) body='{\"plan_type\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\",\"rate_limit\":{\"primary_window\":{\"used_percent\":30,\"limit_window_seconds\":18000}}}';; *at-w-*) body='{}';; *at-z|*at-y) code=401; body='{\"error\":{\"code\":\"token_revoked\"}}';; *) code=401; body='{\"error\":{\"code\":\"token_expired\"}}';; esac;;\n*auth.openai.com/oauth/token) case \"$grant\" in *rt-z*) code=401; body='{\"error\":\"invalid_grant\"}';; *rt-y*) code=503; body='';; *) body='{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\"}';; esac;;\n*api.anthropic.com/api/organizations/*/reset_rate_limits) case \"$auth\" in *sk-a|*sk-s) code=401; body='{\"error\":\"expired\"}';; *) word=$(printf '%s' \"$grant\" | /usr/bin/sed -n 's/.*\"grant_id\":\"w-\\([a-z_]*\\)\".*/\\1/p'); [ -n \"$word\" ] || word=reset; body='{\"result\":\"'\"$word\"'\"}';; esac;;\n*chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume) case \"$auth\" in *at-w-*) body='{\"code\":\"'\"${auth##*at-w-}\"'\"}';; *at-d2) body='{\"code\":\"reset\"}';; *at-z) code=401; body='{\"error\":{\"code\":\"token_revoked\"}}';; *) code=401; body='{\"error\":{\"code\":\"token_expired\"}}';; esac;;\n*) code=404;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf '%s' \"$code\"\n"
   UT-WRITE-SCRIPT ;

: AUTH-D2$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\",\"account_id\":\"acct\"}}" ;

: AUTH-Y$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-y\",\"refresh_token\":\"rt-y\",\"account_id\":\"acct\"}}" ;

\ a saved Codex login whose access token is at-<t>
: AUTH-AT$ ( ptr u8 n -- ptr u8 n ) {: t tu :}
   SB-RESET s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-" SB-APPEND
   t tu SB-APPEND s\" \",\"refresh_token\":\"rt-n\",\"account_id\":\"acct\"}}" SB-APPEND SB$ ;

: AUTH-Z$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-z\",\"refresh_token\":\"rt-z\",\"account_id\":\"acct\"}}" ;

\ readings in percent, rounded once from their decimal spelling
: UT-PCT ( -- )
   s" 12.495" USED-PERCENT 12 T=
   s" 12.5" USED-PERCENT 13 T=
   s" 0" USED-PERCENT 0 T=
   s" -0.5" USED-PERCENT -1 T=
   s" -3" USED-PERCENT -1 T=
   s" -0.0" USED-PERCENT 0 T=
   s" 99.5" USED-PERCENT 100 T=
   s" 0.4999" USED-PERCENT 0 T=
   s" 1249.5e-2" USED-PERCENT 12 T=
   s" 1.25E+1" USED-PERCENT 13 T=
   s" 0.0049e3" USED-PERCENT 5 T=
   s" 1e-999999999999999999999" USED-PERCENT 0 T=
   s" 0e999999999999999999999" USED-PERCENT 0 T=
   s" 1e999999999999999999999" USED-PERCENT -1 T=
   s" 9223372036854775807" USED-PERCENT $7FFFFFFFFFFFFFFF T=
   s" 9223372036854775807.5" USED-PERCENT -1 T=
   s" 99999999999999999999" USED-PERCENT -1 T=
   s" x" USED-PERCENT -1 T=
   s" ." USED-PERCENT -1 T=
   s" 1." USED-PERCENT -1 T=
   s" .5" USED-PERCENT -1 T=
   s" 0.5.1" USED-PERCENT -1 T=
   s" 1e" USED-PERCENT -1 T=
   s" -" USED-PERCENT -1 T=
   s" " USED-PERCENT -1 T= ;

: LOG$ ( -- ptr u8 n )
   s" KIBA_TEST_LOG" GETENV ;

variable UT-LOG0

: UT-LOG-MARK ( -- ) LOG$ READ-FILE$ nip UT-LOG0 ! ;

\ what the fakes logged since the mark
: UT-LOG-NEW$ ( -- ptr u8 n )
   LOG$ READ-FILE$ {: l lu :}
   l UT-LOG0 @ + lu UT-LOG0 @ - ;

\ ---- usage on the store ------------------------------------------------------
variable UT-C0
variable UT-X0
create UT-HELD 32 allot
create UT-ERR-PATH 256 allot   variable UT-ERR-U

\ the file a usage run's stderr is captured in, under the scratch HOME
: UT-ERR$ ( -- ptr u8 n ) UT-ERR-PATH UT-ERR-U @ ;

: UT-ERR-PATH! ( -- )
   SB-RESET s" HOME" GETENV SB-APPEND s" /usage-stderr" SB-APPEND SB$
   UT-ERR-PATH 256 SPAN-COPY nip UT-ERR-U ! ;

\ usage for p (every provider when p < 0) with stderr captured in UT-ERR$;
\ the run reports an error, so it ends E-SW-REPORTED
: UT-USAGE-ERR ( n -- ) {: p :}
   UT-ERR-PATH!
   UT-ERR$ STDERR:CAPTURE
   [: [: p CMD-USAGE ;] E-SW-REPORTED TTHROWSQ ;] [: STDERR:;CAPTURE ;] finally ;

\ ID-SLOT: email a u, organization o ou (none when empty), no plan
: UT-ID ( ptr u8 n ptr u8 n -- ) {: a u o ou :}
   SB-RESET s\" {\"emailAddress\":\"" SB-APPEND a u SB-APPEND [char] " SB-APPEND-C
   ou 0 > if s\" ,\"organizationUuid\":\"" SB-APPEND o ou SB-APPEND [char] " SB-APPEND-C then
   [char] } SB-APPEND-C
   SB$ ID-SLOT CLAUDE-OAUTH-IDENTITY ;

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

\ a fake curl that answers each usage call with readings to round, chosen by
\ the bearer token
: UT-ROUNDING-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\");; esac; shift;; esac; shift; done\ncase \"$auth\" in\n*sk-r1) body='{\"five_hour\":{\"utilization\":12.495},\"seven_day_oauth_apps\":{\"utilization\":12.5},\"limits\":[{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"A\"}},\"percent\":12.495},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"B\"}},\"percent\":12.5},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"C\"}},\"percent\":0},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"D\"}},\"percent\":-0.5}]}';;\n*sk-r2) body='{\"five_hour\":{\"utilization\":0},\"seven_day_oauth_apps\":{\"utilization\":-1},\"seven_day\":{\"utilization\":-0.4}}';;\n*at-r1) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":12.495,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":12.5,\"limit_window_seconds\":604800}}}';;\n*at-r2) body='{\"rate_limit\":{\"primary_window\":{\"used_percent\":0,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":-2,\"limit_window_seconds\":604800}}}';;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf 200\n"
   UT-WRITE-SCRIPT ;

: UT-LIMIT= ( n ptr u8 n n -- ) {: i a u pct :}
   i DB-LIMIT-LABEL$ a u T$=
   i DB-LIMIT-PERCENT pct T= ;

\ every caller rounds its reading once; a negative one leaves its window out
: UT-PCT-CALLERS ( -- )
   UT-ROUNDING-CURL
   P-CLAUDE s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-r1\"}}" false PROBE
   s" ok" UT-STATE= DB-LIMIT# 5 T=
   0 s" Session (5-hour)" 12 UT-LIMIT= 1 s" Weekly (7-day)" 13 UT-LIMIT=
   2 s" A Weekly" 12 UT-LIMIT= 3 s" B Weekly" 13 UT-LIMIT=
   4 s" C Weekly" 0 UT-LIMIT=
   P-CLAUDE s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-r2\"}}" false PROBE
   s" ok" UT-STATE= DB-LIMIT# 1 T= 0 s" Session (5-hour)" 0 UT-LIMIT=
   P-CODEX s\" {\"tokens\":{\"access_token\":\"at-r1\"}}" false PROBE
   s" ok" UT-STATE= DB-LIMIT# 2 T=
   0 s" Session (5-hour)" 12 UT-LIMIT= 1 s" Weekly (7-day)" 13 UT-LIMIT=
   P-CODEX s\" {\"tokens\":{\"access_token\":\"at-r2\"}}" false PROBE
   s" ok" UT-STATE= DB-LIMIT# 1 T= 0 s" Session (5-hour)" 0 UT-LIMIT= ;

\ a fake curl that logs the Authorization and ChatGPT-Account-Id lines of
\ each call and answers it with one window
: UT-LONG-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) /usr/bin/grep -e ^Authorization: -e ^ChatGPT-Account-Id: \"${2#@}\" >> \"$KIBA_TEST_LOG\";; esac; shift;; esac; shift; done\nprintf '%s' '{\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000}}}' > \"$out\"\nprintf 200\n"
   UT-WRITE-SCRIPT ;

16384 constant UT-LONG-CAP   \ the login and both header lines it sends
create UT-LONG UT-LONG-CAP allot   variable UT-LONG-U

: UT-LONG-ROOM ( n -- )
   UT-LONG-U @ + UT-LONG-CAP > if E-SW-CAPACITY throw then ;

: UT-LONG+ ( ptr u8 n -- ) {: a u :}
   u UT-LONG-ROOM
   a UT-LONG UT-LONG-U @ + u BYTE-COPY
   UT-LONG-U @ u + UT-LONG-U ! ;

\ byte c, n times
: UT-LONG-FILL ( n n -- ) {: c n :}
   n UT-LONG-ROOM
   0 begin dup n < while
      c over UT-LONG UT-LONG-U @ + + c!
      1+
   repeat drop
   UT-LONG-U @ n + UT-LONG-U ! ;

\ UT-LONG from offset o to its end
: UT-LONG$ ( n -- ptr u8 n ) {: o :}
   UT-LONG o + UT-LONG-U @ o - ;

\ a 5000-byte access token and a 200-byte account id
: UT-TOK+ ( -- ) s" at-" UT-LONG+ [char] k 4997 UT-LONG-FILL ;
: UT-ACCT+ ( -- ) s" acct-" UT-LONG+ [char] q 195 UT-LONG-FILL ;

\ a token and an account id are read whole and sent whole
: UT-LONG-TOKEN ( -- )
   UT-LONG-CURL
   0 UT-LONG-U !
   s\" {\"tokens\":{\"access_token\":\"" UT-LONG+ UT-TOK+
   s\" \",\"account_id\":\"" UT-LONG+ UT-ACCT+ s\" \"}}" UT-LONG+
   P-CODEX 0 UT-LONG$ false PROBE
   s" ok" UT-STATE=
   UT-LONG-U @ {: o :}
   s" Authorization: Bearer " UT-LONG+ UT-TOK+ $0A 1 UT-LONG-FILL
   LOG$ READ-FILE$ o UT-LONG$ CONTAINS? TTRUE
   UT-LONG-U @ {: i :}
   s" ChatGPT-Account-Id: " UT-LONG+ UT-ACCT+ $0A 1 UT-LONG-FILL
   LOG$ READ-FILE$ i UT-LONG$ CONTAINS? TTRUE ;

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

\ provider p's scratch files are gone
: UT-SCRATCH-GONE ( n -- ) {: p :}
   p s" /headers.txt" PSUB-PUBLIC$ FS:FILE? TFALSE
   p s" /body.json" PSUB-PUBLIC$ FS:FILE? TFALSE ;

\ curl read provider p's token request from p's own scratch directory
: UT-REQ-LOGGED ( n -- ) {: p :}
   p s" /request.json" PSUB-PUBLIC$ {: q qu :}
   SB-RESET s" data @" SB-APPEND q qu SB-APPEND
   SB$ UT-BUF 256 SPAN-COPY {: r ru :}
   LOG$ READ-FILE$ r ru CONTAINS? TTRUE ;

\ tokens travel in a 0600 header file, never argv; the scratch files go
: UT-USAGE-LOG ( -- )
   P-CLAUDE UT-SCRATCH-GONE
   P-CODEX UT-SCRATCH-GONE
   P-CLAUDE UT-REQ-LOGGED
   P-CODEX UT-REQ-LOGGED
   LOG$ READ-FILE$ {: l lu :}
   l lu s" argvheader Authorization" CONTAINS? TFALSE
   l lu s" hdrmode 600" CONTAINS? TTRUE
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" https://api.anthropic.com/api/oauth/usage?cedar_ember=1&at_wall=1" CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   l lu s" Authorization: Bearer sk-a" CONTAINS? TTRUE
   l lu s" Authorization: Bearer at-y" CONTAINS? TTRUE
   l lu s" ua User-Agent: kiba" CONTAINS? TTRUE
   l lu s" ua User-Agent: codex-cli" CONTAINS? TTRUE
   l lu s" ua User-Agent: claude-cli/2.1.282 (external, cli)" CONTAINS? TTRUE ;

\ each provider's scratch directory is its own: cleaning one, as a probe
\ does before and after its requests, leaves the other's files
: UT-SCRATCH-APART ( -- )
   P-CLAUDE PROBE-PREPARE
   P-CODEX PROBE-PREPARE
   P-CLAUDE s" /body.json" PSUB-PUBLIC$ s" a" FS:WRITE-ALL
   P-CODEX s" /body.json" PSUB-PUBLIC$ s" b" FS:WRITE-ALL
   P-CLAUDE PROBE-CLEANUP
   P-CLAUDE s" /body.json" PSUB-PUBLIC$ FS:FILE? TFALSE
   P-CODEX s" /body.json" PSUB-PUBLIC$ FS:FILE? TTRUE
   P-CODEX PROBE-CLEANUP
   P-CODEX s" /body.json" PSUB-PUBLIC$ FS:FILE? TFALSE ;

\ a saved Claude login whose access token has expired
: CREDS-T$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-t\",\"refreshToken\":\"r-t\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

\ a fake curl that renews any Claude grant to sk-t-new, then answers its
\ usage call with a model name too long to read; every other call gets {}
: UT-RENEW-THROW-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\");; esac; shift;; --data-binary|-X|-m|-w) shift;; -*) ;; *) url=$1;; esac; shift; done\nbody='{}'\ncase \"$url\" in\n*platform.claude.com/v1/oauth/token) body='{\"access_token\":\"sk-t-new\",\"refresh_token\":\"r-t-new\",\"expires_in\":3600}';;\n*api.anthropic.com/api/oauth/usage*) case \"$auth\" in *sk-t-new) body='{\"limits\":[{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}},\"percent\":1}]}';; esac;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf 200\n"
   UT-WRITE-SCRIPT ;

: UT-RENEWED-T ( ptr u8 n -- ) {: c cu :}
   c cu CHECK-OBJECT
   c cu s\" \"accessToken\":\"sk-t-new\"" CONTAINS? TTRUE
   c cu s\" \"refreshToken\":\"r-t-new\"" CONTAINS? TTRUE
   c cu s\" \"expiresAt\":2," CONTAINS? TFALSE ;

\ a probe that throws after renewing the token records its error and keeps
\ the renewed login in the row
: UT-RENEWED-THROWS ( -- )
   UT-RENEW-THROW-CURL
   P-CLAUDE s" t@x.test" CREDS-T$ UT-PUT
   P-CLAUDE CMD-USAGE
   P-CLAUDE s" t@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" too many: bytes in a JSON string (limit 64)" T$=
   P-CLAUDE s" t@x.test" [: UT-RENEWED-T ;] UT-ROW-LOGIN
   P-CLAUDE s" t@x.test" CMD-FORGET ;

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

\ z@x.test's row holds its revoked login and the outcome saying so
: UT-REVOKED-Z ( -- )
   P-CODEX s" z@x.test" UT-RECORD s" revoked" UT-STATE=
   DB-USAGE-NOTE$ s" login revoked by a sign-out at chatgpt.com or in codex; log in again" T$=
   P-CODEX s" z@x.test" AUTH-Z$ UT-LOGIN= ;

\ a login revoked by a sign-out keeps its row, marked revoked
: UT-USAGE-REVOKED ( -- )
   P-CODEX s" z@x.test" AUTH-Z$ UT-PUT
   P-CODEX CMD-USAGE
   UT-REVOKED-Z
   LOG$ READ-FILE$ s" Authorization: Bearer at-z" CONTAINS? TTRUE ;

\ the next usage probes the revoked login again, as it probes every saved
\ login: its refresh grant is posted again and the row stays revoked
: UT-USAGE-REVOKED-AGAIN ( -- )
   UT-LOG-MARK
   P-CODEX CMD-USAGE
   UT-REVOKED-Z
   UT-LOG-NEW$ {: l lu :}
   l lu s" wham/usage Authorization: Bearer at-z" CONTAINS? TTRUE
   l lu s\" \"refresh_token\":\"rt-z\"" CONTAINS? TTRUE
   P-CODEX s" z@x.test" CMD-FORGET ;

create UT-AT-BUF 1024 allot

\ row a u holding the Codex login whose access token is at-<t>
: UT-PUT-AT ( ptr u8 n ptr u8 n -- ) {: a u t tu :}
   t tu AUTH-AT$ UT-AT-BUF 1024 SPAN-COPY {: l lu :}
   P-CODEX a u l lu UT-PUT ;

\ an answer that repeats a key in a nested object is not a JSON object
: UT-ANSWER-REPEATS ( -- )
   P-CODEX s" dup@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" OpenAI's usage endpoint sent an answer that is not a JSON object" T$=
   DB-LIMIT# 0 T= ;

\ integers spelled 6048e2, 1789904220.0 and 2.0 read as those integers
: UT-ANSWER-WHOLE ( -- )
   P-CODEX s" whole@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 1 T=
   0 DB-LIMIT-LABEL$ s" Weekly (7-day)" T$=
   0 DB-LIMIT-PERCENT 30 T=
   0 DB-LIMIT-RESETS$ s" 2026-09-20T11:37:00Z" T$=
   DB-RESETS? TTRUE ;

\ a plan longer than PLAN-CAP is the probe's error, never a missing plan
: UT-ANSWER-LONG ( -- )
   P-CODEX s" long@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" too many: bytes in a JSON string (limit 64)" T$=
   DB-LIMIT# 0 T= ;

\ provider answers read as kiba-mac's JSONFields reads them
: UT-ANSWER-READS ( -- )
   s" dup@x.test" s" dup" UT-PUT-AT
   s" whole@x.test" s" whole" UT-PUT-AT
   s" long@x.test" s" long" UT-PUT-AT
   P-CODEX CMD-USAGE
   UT-ANSWER-REPEATS
   UT-ANSWER-WHOLE
   UT-ANSWER-LONG
   P-CODEX s" dup@x.test" CMD-FORGET
   P-CODEX s" whole@x.test" CMD-FORGET
   P-CODEX s" long@x.test" CMD-FORGET ;

\ ---- Claude probe outcomes ----------------------------------------------------
\ a fake curl for the Claude outcomes: the usage and profile calls answer by
\ the bearer token, the token call by the refresh grant; sk-down's usage
\ call fails to connect as curl does, printing 000 and exiting 7
: UT-CLAUDE-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=; grant=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\");; esac; shift;; --data-binary) grant=$(/usr/bin/cat \"${2#@}\"); shift;; -X|-m|-w) shift;; *) url=$1;; esac; shift; done\ncode=200; body='{}'\ncase \"$url\" in\n*/api/oauth/usage*) case \"$auth\" in *sk-nop) code=403; body='{\"type\":\"error\",\"error\":{\"type\":\"permission_error\",\"message\":\"OAuth authentication is currently not allowed for this organization.\",\"details\":{\"error_code\":\"oauth_not_allowed_for_organization\"}}}';; *sk-paid|*sk-free) code=429; body='{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Number of requests has exceeded your rate limit\"}}';; *sk-rej) code=401; body='{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"Invalid bearer token\"}}';; *sk-down) printf 000; exit 7;; *sk-bad) body='[1]';; esac;;\n*/api/oauth/profile) case \"$auth\" in *sk-free) body='{\"organization\":{\"uuid\":\"org-f\",\"organization_type\":\"claude_free\"}}';; *) body='{\"organization\":{\"uuid\":\"org-p\",\"organization_type\":\"claude_max\"}}';; esac;;\n*/v1/oauth/token) case \"$grant\" in *r-old400*) code=400; body='{\"error\":\"invalid_grant\",\"error_description\":\"Refresh token not found or invalid\"}';; *r-old401*) code=401; body='{\"error\":\"invalid_grant\"}';; *r-hold*) code=403; body='{\"error\":\"access_denied\",\"error_description\":\"account_on_hold\",\"error_uri\":\"https://support.anthropic.com/appeal\"}';; esac;;\n*) code=404;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf '%s' \"$code\"\n"
   UT-WRITE-SCRIPT ;

\ expiresAt of a token still good, and of one long expired
: UT-FAR ( -- n ) 4102444800000 ;
: UT-PAST ( -- n ) 2 ;

\ a saved Claude login holding sk-<t> and r-<t>, expiring at epoch
\ millisecond ms
: CREDS-TOKEN$ ( ptr u8 n n -- ptr u8 n ) {: t tu ms :}
   SB-RESET s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-" SB-APPEND t tu SB-APPEND
   s\" \",\"refreshToken\":\"r-" SB-APPEND t tu SB-APPEND
   s\" \",\"expiresAt\":" SB-APPEND ms FMT:SB-U
   s\" ,\"subscriptionType\":\"max\"}}" SB-APPEND
   SB$ UT-AT-BUF 1024 SPAN-COPY ;

: UT-OUTCOME$ ( -- ptr u8 n ) s" o@x.test" ;

\ usage claude over the saved row o@x.test holding CREDS-TOKEN$ t ms; its record
\ is then in the record readers
: UT-CLAUDE-PROBE ( ptr u8 n n -- ) {: t tu ms :}
   t tu ms CREDS-TOKEN$ {: l lu :}
   P-CLAUDE UT-OUTCOME$ l lu UT-PUT
   P-CLAUDE CMD-USAGE
   P-CLAUDE UT-OUTCOME$ UT-RECORD ;

\ the record reads state s su and note n nu
: UT-OUTCOME= ( ptr u8 n ptr u8 n -- ) {: s su n nu :}
   s su UT-STATE=
   DB-USAGE-NOTE$ n nu T$= ;

: UT-OUTCOME-GONE ( -- ) P-CLAUDE UT-OUTCOME$ CMD-FORGET ;

\ a 403 saying the organization's plan does not allow Claude Code
: UT-CLAUDE-NO-PLAN ( -- )
   s" nop" UT-FAR UT-CLAUDE-PROBE
   s" unsubscribed" s" no plan for Claude Code: Anthropic does not allow this organization's OAuth login" UT-OUTCOME=
   UT-OUTCOME-GONE ;

\ a 429 for a paid organization is a rate limit, in Anthropic's words
: UT-CLAUDE-THROTTLED ( -- )
   s" paid" UT-FAR UT-CLAUDE-PROBE
   s" throttled" s" Anthropic is rate limiting usage checks (Number of requests has exceeded your rate limit); try again later" UT-OUTCOME=
   UT-OUTCOME-GONE ;

\ a 429 for an organization the profile shows unpaid is a free plan
: UT-CLAUDE-FREE ( -- )
   s" free" UT-FAR UT-CLAUDE-PROBE
   s" free" s" free plan: Anthropic's profile shows no paid plan for this organization" UT-OUTCOME=
   UT-OUTCOME-GONE ;

: UT-CLAUDE-REJECTED ( -- )
   s" rej" UT-FAR UT-CLAUDE-PROBE
   s" expired" s" login rejected by Anthropic; log in again" UT-OUTCOME=
   UT-OUTCOME-GONE ;

\ a refresh the token endpoint refuses with 400 or 401, with its detail
: UT-CLAUDE-REFUSED ( -- )
   s" old400" UT-PAST UT-CLAUDE-PROBE
   s" expired" s" access token expired and the refresh was refused (400 invalid_grant: Refresh token not found or invalid); log in again" UT-OUTCOME=
   UT-OUTCOME-GONE
   s" old401" UT-PAST UT-CLAUDE-PROBE
   s" expired" s" access token expired and the refresh was refused (401 invalid_grant); log in again" UT-OUTCOME=
   UT-OUTCOME-GONE ;

\ an account on hold may lift: an error with the appeal page, login kept
: UT-CLAUDE-ON-HOLD ( -- )
   s" hold" UT-PAST UT-CLAUDE-PROBE
   s" error" s" account on hold and cannot use Claude Code; view details or appeal at https://support.anthropic.com/appeal" UT-OUTCOME=
   s" hold" UT-PAST CREDS-TOKEN$ {: l lu :}
   P-CLAUDE UT-OUTCOME$ l lu UT-LOGIN=
   UT-OUTCOME-GONE ;

: UT-CLAUDE-UNREACHED ( -- )
   s" down" UT-FAR UT-CLAUDE-PROBE
   s" error" s" Anthropic's usage endpoint could not be reached" UT-OUTCOME=
   UT-OUTCOME-GONE ;

: UT-CLAUDE-UNREADABLE ( -- )
   s" bad" UT-FAR UT-CLAUDE-PROBE
   s" error" s" Anthropic's usage endpoint sent an answer that is not a JSON object" UT-OUTCOME=
   UT-OUTCOME-GONE ;

\ every outcome of a saved Claude login's probe, as kiba-mac's ClaudeProbe
\ records it; the shared fake curl is back afterwards
: UT-CLAUDE-OUTCOMES ( -- )
   UT-CLAUDE-CURL
   UT-CLAUDE-NO-PLAN
   UT-CLAUDE-THROTTLED
   UT-CLAUDE-FREE
   UT-CLAUDE-REJECTED
   UT-CLAUDE-REFUSED
   UT-CLAUDE-ON-HOLD
   UT-CLAUDE-UNREACHED
   UT-CLAUDE-UNREADABLE
   UT-FAKE-CURL ;

\ the fake `claude` logs its argv and writes account B into CLAUDE_CONFIG_DIR,
\ or exits 3 when HOME holds fail-login
: UT-FAKE-CLAUDE ( -- )
   s" claude"
   s\" #!/bin/sh\necho \"claude $* cfg=$CLAUDE_CONFIG_DIR\" >> \"$KIBA_TEST_LOG\"\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nprintf '%s' '{\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\",\"organizationUuid\":\"org-b\"}}' > \"$CLAUDE_CONFIG_DIR/.claude.json\"\nprintf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}' > \"$CLAUDE_CONFIG_DIR/.credentials.json\"\n"
   UT-WRITE-SCRIPT ;

\ `add` logs in inside a throwaway home: the live login stays where it is,
\ the new login is saved under its name, and the home is gone afterwards;
\ the new row is then probed as saved, its 401 renewing its token.
\ the fake `codex` records where it ran and writes AUTH-D on success, or
\ nothing when HOME holds empty-login
: UT-FAKE-CODEX ( -- )
   s" codex"
   s\" #!/bin/sh\necho \"codexhome $CODEX_HOME\" >> \"$KIBA_TEST_LOG\"\nif [ -e \"$HOME/.codex/auth.json\" ]; then echo present >> \"$KIBA_TEST_LOG\"; else echo absent >> \"$KIBA_TEST_LOG\"; fi\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nif [ -e \"$HOME/empty-login\" ]; then exit 0; fi\nprintf '%s' '{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}' > \"$CODEX_HOME/auth.json\"\n"
   UT-WRITE-SCRIPT ;

\ HOME's file f, made or removed by the test to steer the fake codex
: UT-HOME-FILE$ ( ptr u8 n -- ptr u8 n ) {: f fu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND f fu SB-APPEND SB$ UT-BUF 256 SPAN-COPY ;

: UT-CODEX-ROWS ( -- n )
   0 UT-N ! [: P-CODEX DB-LIST DB-ROW# UT-N ! ;] UT-STORE UT-N @ ;

\ where UT-ADD moves the fake codex aside
create UT-OFF-PATH 256 allot

: UT-ADD ( -- )
   UT-FAKE-CODEX
   UT-FAKE-CURL
   P-CODEX s" d@x.test" CMD-FORGET
   s" /fail-login" UT-HOME-FILE$ {: f fu :}
   f fu s" x" FS:WRITE-ALL
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   [: P-CODEX s" " CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   P-CODEX s" d@x.test" UT-ROW? TFALSE
   f fu FS:REMOVE-FILE
   HOME$ {: h2 h2u :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex" SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: cx cxu :}
   SB-RESET h2 h2u SB-APPEND s" /bin/codex.off" SB-APPEND SB$ UT-OFF-PATH 256 SPAN-COPY {: cxo cxou :}
   cx cxu cxo cxou FS:RENAME-FILE
   [: P-CODEX s" " CMD-ADD ;] E-SW-NO-CLI TTHROWSQ
   CODEX-AUTH$ FS:FILE? TTRUE
   cxo cxou cx cxu FS:RENAME-FILE
   P-CODEX s" " CMD-ADD
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" [: UT-RENEWED-D ;] UT-ROW-LOGIN
   P-CODEX s" d@x.test" UT-RECORD s" ok" UT-STATE=
   P-CODEX s" d@x.test" UT-LAST-LIVE 0 T=
   P-CODEX s" c@x.test" AUTH-C9$ UT-LOGIN=
   P-CODEX LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   LOG$ READ-FILE$ {: l lu :}
   l lu s\" present\nhdrmode 600" CONTAINS? TTRUE
   l lu s" /probe-codex/login/.codex" CONTAINS? TTRUE
   l lu s" absent" CONTAINS? TFALSE ;

\ a login that leaves nothing in the throwaway home saves nothing
: UT-ADD-EMPTY ( -- )
   UT-FAKE-CODEX
   UT-CODEX-ROWS {: n :}
   s" /empty-login" UT-HOME-FILE$ {: f fu :}
   f fu s" x" FS:WRITE-ALL
   [: P-CODEX s" " CMD-ADD ;] E-SW-NO-LIVE TTHROWSQ
   f fu FS:REMOVE-FILE
   UT-CODEX-ROWS n T=
   P-CODEX LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$= ;

\ the new Claude row's login and profile
: UT-CLAUDE-B ( -- )
   P-CLAUDE s" b@x.test" DB-FETCH TTRUE
   0 DB-ROW-LOGIN$ s\" \"accessToken\":\"sk-b" CONTAINS? TTRUE
   0 DB-ROW-PROFILE$ s\" \"organizationUuid\":\"org-b\"" CONTAINS? TTRUE ;

\ a Claude add with an expected account prefills the email and saves under
\ the name that actually came back, saying so when it differs
: UT-ADD-CLAUDE ( -- )
   UT-FAKE-CLAUDE
   P-CLAUDE s" b@x.test" UT-ROW? TFALSE
   P-CLAUDE s" b@x.test" CMD-ADD
   LOG$ READ-FILE$ s" auth login --email b@x.test cfg=" CONTAINS? TTRUE
   LOG$ READ-FILE$ s" /probe-claude/login/.claude" CONTAINS? TTRUE
   [: UT-CLAUDE-B ;] UT-STORE
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE LOGIN-HOME-PUBLIC$ FS:DIR? TFALSE
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   P-CLAUDE s" b@x.test" CMD-FORGET
   P-CLAUDE s" zz@x.test" CMD-ADD
   P-CLAUDE s" zz@x.test" UT-ROW? TFALSE
   [: UT-CLAUDE-B ;] UT-STORE
   P-CLAUDE s" b@x.test" CMD-FORGET ;

\ an add clears a stale add record before its login, so save runs after it
\ whether or not the login completes
: UT-ADD-STALE ( -- )
   UT-FAKE-CLAUDE
   [: P-CLAUDE CREDS-A$ UT-PLANT-ADDING ;] UT-STORE
   P-CLAUDE s" " CMD-ADD
   P-CLAUDE UT-ADDING? TFALSE
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" b@x.test" CMD-FORGET
   [: P-CLAUDE CREDS-A$ UT-PLANT-ADDING ;] UT-STORE
   s" /fail-login" UT-HOME-FILE$ {: f fu :}
   f fu s" x" FS:WRITE-ALL
   [: P-CLAUDE s" " CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   f fu FS:REMOVE-FILE
   P-CLAUDE UT-ADDING? TFALSE
   P-CLAUDE CMD-SAVE ;

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

\ live Claude files mixed over the installed row's expired token: the save-back
\ is reported, and the installed name is probed as live, so its expired token
\ is reported and never refreshed
: UT-MIXED-USAGE ( -- )
   CLAUDE-CREDS$ CREDS-A-OLD$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   P-CLAUDE UT-USAGE-ERR
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: the live Claude files name different accounts; switch to an account to repair them\n" T$=
   P-CLAUDE s" a@x.test" UT-RECORD s" expired" UT-STATE=
   DB-USAGE-NOTE$ s" access token expired; Claude Code refreshes it on its next run" T$=
   P-CLAUDE s" a@x.test" UT-LAST-LIVE 1 T=
   P-CLAUDE s" a@x.test" CREDS-A-OLD$ UT-LOGIN=
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE ;

\ one provider's unreadable live file does not stop the other's probe; the
\ command fails once both have run
: UT-USAGE-ISOLATION ( -- )
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   P-CODEX UT-USAGES UT-X0 !
   -1 UT-USAGE-ERR
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: a login file is not valid JSON\nclaude: a login file is not valid JSON\n" T$=
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
   P-CLAUDE UT-USAGE-ERR
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: the live Claude files name different accounts; switch to an account to repair them\nclaude: the claude switch to b@x.test did not finish; nothing is probed or refreshed until a switch completes\n" T$=
   P-CLAUDE UT-USAGES UT-C0 @ T=
   E-SW-UNREPAIRED REASON$
   s" kiba: the claude switch to b@x.test did not finish; nothing is probed or refreshed until a switch completes" T$=
   [: [: P-CLAUDE UT-HELD 32 DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   P-CLAUDE UT-PENDING? TFALSE ;

\ a record the store refuses is reported under its account's name; the
\ other account is still recorded
: UT-UNRECORDED ( -- )
   [: s" CREATE TRIGGER ut_refuse BEFORE UPDATE OF usage ON account WHEN NEW.name = 'd@x.test' BEGIN SELECT RAISE(ABORT, 'refused by the test'); END" s" test" DB-EXEC ;] UT-STORE
   P-CODEX UT-USAGES UT-X0 !
   P-CODEX UT-USAGE-ERR
   [: s" DROP TRIGGER ut_refuse" s" test" DB-EXEC ;] UT-STORE
   UT-ERR$ READ-FILE$
   s\" codex: d@x.test: usage not recorded: the account database refused: set usage: refused by the test\n" T$=
   P-CODEX UT-USAGES UT-X0 @ 1+ T= ;

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

: OAUTH-N$ ( -- ptr u8 n )
   s\" {\"accountUuid\":\"u3\",\"emailAddress\":\"n@x.test\",\"organizationUuid\":\"org-n\"}" ;

\ a login whose token the fake usage answers ok
: CREDS-N$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-b-new\",\"refreshToken\":\"r-n\",\"expiresAt\":4102444800000,\"subscriptionType\":\"pro\"}}" ;

\ the Claude row n@x.test, with the profile an install splices in
: UT-PUT-N ( -- )
   OAUTH-N$ ID-SLOT CLAUDE-OAUTH-IDENTITY
   [: [: P-CLAUDE s" n@x.test" ID-SLOT CREDS-N$ OAUTH-N$ false DB-PUT ;] DB-WRITE ;] UT-STORE ;

\ a Claude use probes the login it installs as live, then the one it saved
\ back as saved
: UT-USE-PROBES-CLAUDE ( -- )
   UT-PUT-N
   P-CLAUDE UT-USAGES UT-C0 !
   P-CLAUDE s" n@x.test" CMD-USE
   P-CLAUDE UT-USAGES UT-C0 @ 2 + T=
   P-CLAUDE s" n@x.test" UT-LAST-LIVE 1 T=
   P-CLAUDE s" a@x.test" UT-LAST-LIVE 0 T=
   P-CLAUDE s" n@x.test" UT-RECORD s" ok" UT-STATE=
   P-CLAUDE s" a@x.test" UT-RECORD s" ok" UT-STATE=
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   P-CLAUDE s" n@x.test" CMD-FORGET ;

\ ---- redeem ------------------------------------------------------------------
create UT-AUTH-BUF 256 allot

\ row p a u's record replaced by an ok one offering a reset of program g
\ under grant w
: UT-OFFER ( n ptr u8 n ptr u8 n ptr u8 n -- ) {: p a u g gu w wu :}
   SB-RESET s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"resets\":{\"count\":1,\"grant\":\"" SB-APPEND
   w wu SB-APPEND s\" \",\"program\":\"" SB-APPEND g gu SB-APPEND
   s\" \"},\"state\":\"ok\"}" SB-APPEND SB$ DB-USAGE-DECODE
   DB-RESETS? TTRUE
   [: [: p a u UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE ;

: UT-SET-LOGIN ( n ptr u8 n ptr u8 n -- ) {: p a u l lu :}
   [: [: p a u l lu DB-SET-LOGIN ;] DB-WRITE ;] UT-STORE ;

: CREDS-R$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-r\",\"refreshToken\":\"r-r\",\"expiresAt\":4102444800000,\"subscriptionType\":\"max\"}}" ;

\ a Codex login whose token makes the fake reset answer w
: UT-AUTH-W$ ( ptr u8 n -- ptr u8 n ) {: w wu :}
   SB-RESET s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-w-" SB-APPEND
   w wu SB-APPEND
   s\" \",\"refresh_token\":\"rt-w\",\"account_id\":\"acct\"}}" SB-APPEND
   SB$ UT-AUTH-BUF 256 SPAN-COPY ;

\ r@x.test's banked grant w-<word> spent: the answer's word is the outcome
: UT-CLAUDE-WORD ( ptr u8 n ptr u8 n -- ) {: g gu t tu :}
   P-CLAUDE s" r@x.test" s" cedar_ember" g gu UT-OFFER
   P-CLAUDE s" r@x.test" CMD-REDEEM
   s" r@x.test" REDEEMED$ t tu T$= ;

: UT-CODEX-WORD ( ptr u8 n ptr u8 n -- ) {: w wu t tu :}
   w wu UT-AUTH-W$ {: d du :}
   P-CODEX s" w@x.test" d du UT-PUT
   P-CODEX s" w@x.test" s" " s" " UT-OFFER
   P-CODEX s" w@x.test" CMD-REDEEM
   s" w@x.test" REDEEMED$ t tu T$= ;

\ byte i of a request id: a dash at 8, 13, 18 and 23, else an uppercase
\ hex digit
: UT-RID-C ( n n -- bool ) {: c i :}
   i 8 = i 13 = or i 18 = or i 23 = or if c $2D = exit then
   c STR-DIGIT? c [char] A >= c [char] F <= and or ;

\ where the request id starts in the log, -1 when none is logged
: UT-RID-AT ( ptr u8 n -- n ) {: l lu :}
   l lu s\" \"request_id\":\"" FIND-SUB MATCH option
     none OF -1 ENDOF
     some OF IDX>N 14 + ENDOF
   ;MATCH ;

\ the first request id in the log is 36 bytes as UUID().uuidString writes
\ them, then the closing quote
: UT-RID ( ptr u8 n -- ) {: l lu :}
   l lu UT-RID-AT {: at :}
   at 0 >= TTRUE
   at 36 + lu < TTRUE
   l at + 36 + c@ [char] " T=
   36 0 ?do l at + i + c@ i UT-RID-C TTRUE loop ;

\ a saved Claude login's reset is asked of its organization with the
\ offer's grant, then the login is probed again; every word maps to its
\ outcome, and an unknown one is the endpoint's error
: UT-REDEEM-CLAUDE ( -- )
   P-CLAUDE s" r@x.test" s" org-r" CREDS-R$ UT-PUT-ORG
   [: P-CLAUDE s" r@x.test" CMD-REDEEM ;] E-SW-NO-RESETS TTHROWSQ
   E-SW-NO-RESETS REASON$ s" kiba: no limit resets are available for r@x.test" T$=
   P-CLAUDE UT-USAGES UT-C0 !
   UT-LOG-MARK
   s" w-reset" s" Limit reset for r@x.test" UT-CLAUDE-WORD
   P-CLAUDE UT-USAGES UT-C0 @ 1+ T=
   P-CLAUDE s" r@x.test" UT-LAST-LIVE 0 T=
   UT-LOG-NEW$ {: l lu :}
   l lu s" https://api.anthropic.com/api/organizations/org-r/reset_rate_limits Authorization: Bearer sk-r" CONTAINS? TTRUE
   l lu s\" body {\"program\":\"cedar_ember\",\"grant_id\":\"w-reset\",\"request_id\":\"" CONTAINS? TTRUE
   l lu UT-RID
   l lu s" ua User-Agent: claude-cli/2.1.282 (external, cli)" CONTAINS? TTRUE
   s" w-already_used" s" That reset was already used" UT-CLAUDE-WORD
   s" w-not_limited" s" r@x.test is not at a limit; nothing was spent" UT-CLAUDE-WORD
   s" w-cooldown" s" Limit resets are cooling down for r@x.test; try again later" UT-CLAUDE-WORD
   s" w-ineligible" s" r@x.test cannot reset its limit" UT-CLAUDE-WORD
   s" w-unavailable" s" Limit resets are unavailable for r@x.test right now" UT-CLAUDE-WORD
   UT-LOG-MARK
   P-CLAUDE s" r@x.test" s" juniper_tide" s" " UT-OFFER
   P-CLAUDE s" r@x.test" CMD-REDEEM
   s" r@x.test" REDEEMED$ s" Limit reset for r@x.test" T$=
   UT-LOG-NEW$ s\" body {\"program\":\"juniper_tide\"}" CONTAINS? TTRUE
   P-CLAUDE s" r@x.test" s" cedar_ember" s" w-bogus" UT-OFFER
   [: P-CLAUDE s" r@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s\" kiba: Anthropic's reset endpoint sent an unknown result \"bogus\"" T$=
   P-CLAUDE s" r@x.test" CREDS-R$ UT-LOGIN=
   P-CLAUDE s" r@x.test" CMD-FORGET ;

: CREDS-S$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-s\",\"refreshToken\":\"r-s\",\"expiresAt\":4102444800000,\"subscriptionType\":\"pro\"}}" ;

\ a saved Claude login's rejected reset renews its token, which is saved
\ back, and the reset is sent again
: UT-REDEEM-RENEWED ( -- )
   P-CLAUDE s" s@x.test" s" org-s" CREDS-S$ UT-PUT-ORG
   P-CLAUDE s" s@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   UT-LOG-MARK
   P-CLAUDE s" s@x.test" CMD-REDEEM
   s" s@x.test" REDEEMED$ s" Limit reset for s@x.test" T$=
   P-CLAUDE s" s@x.test" [: UT-RENEWED-B ;] UT-ROW-LOGIN
   UT-LOG-NEW$ {: l lu :}
   l lu s" /org-s/reset_rate_limits Authorization: Bearer sk-s" CONTAINS? TTRUE
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" /org-s/reset_rate_limits Authorization: Bearer sk-b-new" CONTAINS? TTRUE
   P-CLAUDE s" s@x.test" CMD-FORGET ;

\ the organization reaches the URL as one path segment, whatever it holds
: UT-REDEEM-SEGMENT ( -- )
   P-CLAUDE s" r@x.test" s" a/b?c" CREDS-R$ UT-PUT-ORG
   P-CLAUDE s" r@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   UT-LOG-MARK
   P-CLAUDE s" r@x.test" CMD-REDEEM
   UT-LOG-NEW$ s" /api/organizations/a%2Fb%3Fc/reset_rate_limits " CONTAINS? TTRUE
   P-CLAUDE s" r@x.test" CMD-FORGET ;

\ the live login's rejected token is its CLI's to refresh: no refresh is
\ asked for and the login is left as it was
: UT-REDEEM-LIVE ( -- )
   P-CLAUDE s" a@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   UT-LOG-MARK
   [: P-CLAUDE s" a@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s" kiba: access token expired; Claude Code refreshes it on its next run" T$=
   UT-LOG-NEW$ {: l lu :}
   l lu s" /reset_rate_limits Authorization: Bearer sk-a" CONTAINS? TTRUE
   l lu s" platform.claude.com" CONTAINS? TFALSE
   P-CLAUDE s" a@x.test" CREDS-A$ UT-LOGIN=
   P-CODEX s" c@x.test" s" " s" " UT-OFFER
   UT-LOG-MARK
   [: P-CODEX s" c@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s" kiba: access token rejected; run codex once to refresh it" T$=
   UT-LOG-NEW$ {: m mu :}
   m mu s" /rate-limit-reset-credits/consume Authorization: Bearer at-c" CONTAINS? TTRUE
   m mu s" auth.openai.com" CONTAINS? TFALSE
   P-CODEX s" c@x.test" AUTH-C$ UT-LOGIN= ;

\ a saved Codex login's 401 renews its token, which is saved back, and the
\ reset is sent again; every word maps to its outcome
: UT-REDEEM-CODEX ( -- )
   P-CODEX s" d@x.test" AUTH-D$ UT-SET-LOGIN
   P-CODEX s" d@x.test" s" " s" " UT-OFFER
   UT-LOG-MARK
   P-CODEX s" d@x.test" CMD-REDEEM
   s" d@x.test" REDEEMED$ s" Limit reset for d@x.test" T$=
   P-CODEX s" d@x.test" [: UT-RENEWED-D ;] UT-ROW-LOGIN
   P-CODEX s" d@x.test" UT-LAST-LIVE 0 T=
   UT-LOG-NEW$ {: l lu :}
   l lu s" /rate-limit-reset-credits/consume Authorization: Bearer at-d" CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   l lu s" /rate-limit-reset-credits/consume Authorization: Bearer at-d2" CONTAINS? TTRUE
   l lu s\" body {\"redeem_request_id\":\"" CONTAINS? TTRUE
   l lu s" ua User-Agent: codex-cli" CONTAINS? TTRUE
   s" reset" s" Limit reset for w@x.test" UT-CODEX-WORD
   s" nothing_to_reset" s" w@x.test is not at a limit; nothing was spent" UT-CODEX-WORD
   s" no_credit" s" No limit resets left for w@x.test" UT-CODEX-WORD
   s" already_redeemed" s" That reset was already used" UT-CODEX-WORD
   P-CODEX s" w@x.test" CMD-FORGET ;

\ a saved Codex login revoked by a sign-out: its reset is rejected and
\ the renewal refused, and the login is left as it was
: UT-REDEEM-REVOKED ( -- )
   P-CODEX s" z@x.test" AUTH-Z$ UT-PUT
   P-CODEX s" z@x.test" s" " s" " UT-OFFER
   UT-LOG-MARK
   [: P-CODEX s" z@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s" kiba: login revoked by a sign-out at chatgpt.com or in codex; log in again" T$=
   UT-LOG-NEW$ {: l lu :}
   l lu s" /rate-limit-reset-credits/consume Authorization: Bearer at-z" CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   P-CODEX s" z@x.test" AUTH-Z$ UT-LOGIN=
   P-CODEX s" z@x.test" CMD-FORGET ;

\ ---- live logins that name no account ---------------------------------------
\ One reader decides the live login for every command, so a live login kiba
\ cannot name stops each one: nothing is probed, refreshed or saved.
create UT-SNAP 8192 allot    variable UT-SNAP-U
create UT-SNAP0 8192 allot
create UT-KEPT 2048 allot
create UT-PATH 256 allot
create UT-REASON 512 allot

\ UT-LOG-MARK where no fake may have logged yet, so the log may not exist
: UT-MARK ( -- )
   LOG$ FS:FILE? 0= if LOG$ s" " FS:WRITE-ALL then
   UT-LOG-MARK ;

: UT-SNAP+ ( ptr u8 n -- ) {: a u :}
   UT-SNAP-U @ u + 8192 > if E-SW-CAPACITY throw then
   a UT-SNAP UT-SNAP-U @ + u BYTE-COPY
   u UT-SNAP-U +! ;

: UT-SNAP-KEEP ( n -- ) {: p :}
   0 UT-SNAP-U !
   p DB-LIST
   DB-ROW# 0 ?do i DB-ROW-NAME$ UT-SNAP+ i DB-ROW-LOGIN$ UT-SNAP+ loop ;

\ every saved row of p, its name then its login
: UT-SNAP$ ( n -- ptr u8 n ) {: p :}
   [: p UT-SNAP-KEEP ;] UT-STORE UT-SNAP UT-SNAP-U @ ;

\ rc's reason as usage prints it on stderr, without the "kiba: " lead
: UT-BARE$ ( n -- ptr u8 n ) REASON$ {: r ru :} r 6 + ru 6 - ;

: UT-JSON-C ( n -- ) {: c :}
   c [char] / = if $5C SB-APPEND-C then
   c SB-APPEND-C ;

\ "error":"<rc's bare reason>" as the snapshot writes it, its slashes escaped
: UT-ERROR-KEY$ ( n -- ptr u8 n )
   UT-BARE$ UT-REASON 512 SPAN-COPY {: r ru :}
   SB-RESET s\" \"error\":\"" SB-APPEND
   ru 0 ?do r i + c@ UT-JSON-C loop
   [char] " SB-APPEND-C SB$ ;

\ the fake `claude` of UT-FAKE-CLAUDE, leaving credentials but no config
: UT-FAKE-CLAUDE-ORPHAN ( -- )
   s" claude"
   s\" #!/bin/sh\necho \"claude $* cfg=$CLAUDE_CONFIG_DIR\" >> \"$KIBA_TEST_LOG\"\nprintf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}' > \"$CLAUDE_CONFIG_DIR/.credentials.json\"\n"
   UT-WRITE-SCRIPT ;

\ usage says why and stops before any request, every saved login unchanged
: UT-ORPHAN-USAGE ( -- )
   P-CLAUDE UT-SNAP$ UT-SNAP0 8192 SPAN-COPY {: s su :}
   su 0 > TTRUE
   UT-MARK
   P-CLAUDE UT-USAGE-ERR
   UT-ERR$ READ-FILE$ E-SW-ORPHAN-LIVE UT-BARE$ CONTAINS? TTRUE
   UT-LOG-NEW$ nip 0 T=
   P-CLAUDE UT-SNAP$ s su T$= ;

\ status shows the reason as Claude's error beside its saved accounts
: UT-ORPHAN-STATUS-KEEP ( -- )
   STATUS-JSON$ {: j ju :}
   j ju E-SW-ORPHAN-LIVE UT-ERROR-KEY$ CONTAINS? TTRUE
   j ju s\" \"name\":\"a@x.test\"" CONTAINS? TTRUE
   j ju s\" \"name\":\"b@x.test\"" CONTAINS? TTRUE ;

: UT-ORPHAN-STATUS ( -- ) [: UT-ORPHAN-STATUS-KEEP ;] UT-STORE ;

: UT-ORPHAN-REDEEM ( -- )
   P-CLAUDE s" a@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   UT-MARK
   [: P-CLAUDE s" a@x.test" CMD-REDEEM ;] E-SW-ORPHAN-LIVE TTHROWSQ
   UT-LOG-NEW$ nip 0 T= ;

\ an add whose login leaves no config names the throwaway home's
: UT-ORPHAN-ADD ( -- )
   UT-FAKE-CLAUDE-ORPHAN
   [: P-CLAUDE s" " CMD-ADD ;] E-SW-ORPHAN-LIVE TTHROWSQ
   CLAUDE-CONFIG$ {: c cu :}
   E-SW-ORPHAN-LIVE REASON$ {: r ru :}
   r ru s" /probe-claude/login/.claude/.claude.json" CONTAINS? TTRUE
   r ru c cu CONTAINS? TFALSE ;

\ Claude credentials without a config stop usage, status, redeem and add
: UT-ORPHAN-STOPS ( -- )
   UT-FAKE-CURL
   CLAUDE-CONFIG$ FS:REMOVE-FILE
   UT-ORPHAN-USAGE
   UT-ORPHAN-STATUS
   UT-ORPHAN-REDEEM
   UT-ORPHAN-ADD
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE ;

: UT-UNNAMED-STATUS ( -- )
   STATUS-JSON$ E-SW-JSON UT-ERROR-KEY$ CONTAINS? TTRUE ;

\ p's live file f made d, which names no account: status shows that as p's
\ error and usage refreshes no saved login; f is put back afterwards
: UT-UNNAMED ( n ptr u8 n ptr u8 n -- ) {: p f fu d du :}
   f fu UT-PATH 256 SPAN-COPY {: g gu :}
   g gu READ-FILE$ UT-KEPT 2048 SPAN-COPY {: k ku :}
   p UT-SNAP$ UT-SNAP0 8192 SPAN-COPY {: s su :}
   su 0 > TTRUE
   UT-FAKE-CURL
   g gu d du WRITE-PRIVATE
   [: UT-UNNAMED-STATUS ;] UT-STORE
   UT-MARK
   p UT-USAGE-ERR
   UT-LOG-NEW$ s" /oauth/token" CONTAINS? TFALSE
   p UT-SNAP$ s su T$=
   g gu k ku WRITE-PRIVATE ;

\ a Codex login with neither an id_token nor an API key
: AUTH-NO-ID$ ( -- ptr u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-c\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"}}" ;

: UT-UNNAMED-CLAUDE ( -- ) P-CLAUDE CLAUDE-CONFIG$ CFG-NOAUTH$ UT-UNNAMED ;
: UT-UNNAMED-CODEX ( -- ) P-CODEX CODEX-AUTH$ AUTH-NO-ID$ UT-UNNAMED ;

\ a saved Claude login whose token has expired is renewed before its reset
\ is sent; the reset then fails, and the renewed login is saved anyway
: UT-REDEEM-EXPIRED ( -- )
   P-CLAUDE s" b@x.test" s" org-b" CREDS-B$ UT-PUT-ORG
   P-CLAUDE s" b@x.test" s" cedar_ember" s" w-bogus" UT-OFFER
   UT-LOG-MARK
   [: P-CLAUDE s" b@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s\" kiba: Anthropic's reset endpoint sent an unknown result \"bogus\"" T$=
   P-CLAUDE s" b@x.test" [: UT-RENEWED-B ;] UT-ROW-LOGIN
   UT-LOG-NEW$ {: l lu :}
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" /org-b/reset_rate_limits Authorization: Bearer sk-b-new" CONTAINS? TTRUE
   l lu s\" Bearer sk-b\n" CONTAINS? TFALSE
   P-CLAUDE s" b@x.test" CMD-FORGET ;

\ an unknown name is refused before any endpoint is called
: UT-REDEEM-UNKNOWN ( -- )
   UT-LOG-MARK
   [: P-CLAUDE s" nobody@x.test" CMD-REDEEM ;] E-SW-NO-ACCOUNT TTHROWSQ
   UT-LOG-NEW$ nip 0 T= ;

\ the redeem of r@x.test's offer stops with e, calling no endpoint
: UT-REDEEM-STOPS ( n -- ) {: e :}
   UT-LOG-MARK
   [: P-CLAUDE s" r@x.test" CMD-REDEEM ;] e TTHROWSQ
   UT-LOG-NEW$ nip 0 T= ;

\ a pending install, or an add's live login waiting to go back, leaves no
\ saved name known not to be live: the redeem stops before it sends
: UT-REDEEM-BLOCKED ( -- )
   P-CLAUDE s" r@x.test" s" org-r" CREDS-R$ UT-PUT-ORG
   P-CLAUDE s" r@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   [: [: P-CLAUDE s" r@x.test" DB-NOTE-PENDING UT-HOLD ;] DB-WRITE ;] UT-STORE
   E-SW-UNREPAIRED UT-REDEEM-STOPS
   [: [: P-CLAUDE UT-HELD 32 DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   [: s" INSERT INTO adding (provider, live, service) VALUES ('claude', NULL, '')" s" test" DB-EXEC ;] UT-STORE
   E-SW-UNRESTORED UT-REDEEM-STOPS
   [: s" DELETE FROM adding WHERE provider = 'claude'" s" test" DB-EXEC ;] UT-STORE
   P-CLAUDE s" r@x.test" CREDS-R$ UT-LOGIN=
   P-CLAUDE s" r@x.test" CMD-FORGET ;

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
   s\" {\"providers\":[{\"accounts\":[{\"active\":false,\"name\":\"a@x.test\",\"plan\":\"max\",\"usage\":{\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}},{\"active\":false,\"name\":\"a@x.test #2\",\"plan\":\"team\"}],\"error\":\"a login file is not valid JSON\",\"installedAt\":1700000500,\"provider\":\"claude\"},{\"accounts\":[{\"active\":true,\"name\":\"c@x.test\",\"plan\":\"plus\"}],\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"},\"provider\":\"codex\"}]}" ;

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

\ live Claude credentials whose plan is one byte past PLAN-CAP
: CREDS-LONG$ ( -- ptr u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-l\",\"subscriptionType\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\"}}" ;

create UT-SQL 2048 allot   variable UT-SQL-U

: UT-SQL+ ( ptr u8 n -- ) {: a u :}
   a UT-SQL UT-SQL-U @ + u BYTE-COPY
   u UT-SQL-U +! ;

\ n@x.test's stored usage note is 1100 bytes, past REC-NOTE-CAP
: UT-LONG-NOTE ( -- )
   0 UT-SQL-U !
   s\" UPDATE account SET usage = '{\"fetchedAt\":1,\"limits\":[],\"note\":\"" UT-SQL+
   1100 0 ?do s" n" UT-SQL+ loop
   s\" \",\"state\":\"ok\"}' WHERE provider = 'claude' AND name = 'n@x.test'" UT-SQL+
   UT-SQL UT-SQL-U @ s" test" DB-EXEC ;

4096 constant UT-OUT-CAP
create UT-OUT UT-OUT-CAP allot   create UT-OUT-ERR UT-OUT-CAP allot
variable UT-OUT-U

\ text status's stdout, run as the command runs it, with its own store open
: UT-STATUS-TEXT$ ( -- ptr u8 n )
   DB-CLOSE
   [: false CMD-STATUS ;] s" HOME" GETENV
   UT-OUT UT-OUT-CAP SPAN:MAKE UT-OUT-ERR UT-OUT-CAP SPAN:MAKE
   GT-CAPTURE-ACTION {: outu:len erru:len rc:n :}
   DB-OPEN
   rc 0 T=
   outu LEN>N UT-OUT-U !
   UT-OUT UT-OUT-U @ ;

\ the live read's reason is the one it stopped on, though decoding a row's
\ usage overflows another buffer before the error is written
: UT-STATUS-REASON ( -- )
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" n@x.test" ID-SLOT CREDS-A$ OAUTH-A$ false DB-PUT ;] DB-WRITE
   UT-LONG-NOTE
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-LONG$ WRITE-PRIVATE
   STATUS-JSON$ s\" \"error\":\"too many: bytes in a JSON string (limit 64)\"" CONTAINS? TTRUE
   UT-STATUS-TEXT$ s\" claude: too many: bytes in a JSON string (limit 64)\n" CONTAINS? TTRUE
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   [: P-CLAUDE s" n@x.test" DB-REMOVE ;] DB-WRITE ;

\ a newer schema is refused and leaves the store closed
: UT-DB-VERSION ( -- )
   s" PRAGMA user_version = 6" s" test" DB-EXEC
   DB-CLOSE
   [: DB-OPEN ;] E-SW-DB-VERSION TTHROWSQ
   [: P-CLAUDE DB-LIST ;] E-SW-DB TTHROWSQ ;

\ a seventeenth limit is E-SW-CAPACITY, whose reason names what overflowed
: UT-DB-TOO-MANY ( -- )
   s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" DB-USAGE-DECODE
   16 0 ?do s" w" 1 s" r" DB-LIMIT+ loop
   [: s" w" 1 s" r" DB-LIMIT+ ;] E-SW-CAPACITY TTHROWSQ
   E-SW-CAPACITY REASON$ s" kiba: too many: limits in a usage record (limit 16)" T$= ;

: UT-DB ( -- )
   UT-DB-OPEN
   UT-DB-PUT
   UT-DB-FETCH
   UT-DB-USAGE
   UT-DB-TOO-MANY
   UT-DB-PENDING
   UT-DB-ROLLBACK
   UT-STATUS-JSON
   UT-STATUS-ERROR
   UT-STATUS-REASON
   UT-DB-VERSION ;

: UT-NAMES ( -- )
   s" a@x.test #2" s" a@x.test" NAME-SUFFIX# 2 T=
   s" a@x.test #10" s" a@x.test" NAME-SUFFIX# 10 T=
   s" a@x.test #foo" s" a@x.test" NAME-SUFFIX# -1 T=
   s" a@x.test #foo" s" a@x.test" NAME-FOR-EMAIL? TFALSE
   s" a@x.test #10" NAME-EMAIL s" a@x.test" T$=
   s" a@x.test" NAME-EMAIL s" a@x.test" T$= ;

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

\ ---- every Codex probe outcome ------------------------------------------------
\ a fake curl for the Codex outcomes: the usage call answers 429 to at-t,
\ 200 to at-d2 and 401 to any other token; the token endpoint refuses
\ rt-x with invalid_grant, answers rt-u without an access token and 503 to
\ anything else; each call is logged with its token and request body
: UT-OUTCOME-CURL ( -- )
   s" curl"
   s\" #!/bin/sh\nout=; auth=; url=; grant=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=$2; shift;; -H) case \"$2\" in @*) auth=$(/usr/bin/grep ^Authorization: \"${2#@}\");; esac; shift;; --data-binary) grant=$(/usr/bin/cat \"${2#@}\"); shift;; -X|-m|-w) shift;; *) url=$1;; esac; shift; done\necho \"$url $auth $grant\" >> \"$KIBA_TEST_LOG\"\ncode=200; body='{}'\ncase \"$url\" in\n*chatgpt.com/backend-api/wham/usage) case \"$auth\" in *at-t) code=429; body='{\"error\":{\"code\":\"rate_limited\"}}';; *at-d2) ;; *) code=401; body='{\"error\":{\"code\":\"token_expired\"}}';; esac;;\n*auth.openai.com/oauth/token) case \"$grant\" in *rt-x*) code=400; body='{\"error\":\"invalid_grant\"}';; *rt-u*) body='{\"refresh_token\":\"rt-u2\"}';; *) code=503; body='';; esac;;\n*) code=404;;\nesac\nprintf '%s' \"$body\" > \"$out\"\nprintf '%s' \"$code\"\n"
   UT-WRITE-SCRIPT ;

\ an API-key login whose tokens hold an access token but no id_token
: AUTH-KEY-AT$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"sk-k\",\"tokens\":{\"access_token\":\"at-k\",\"refresh_token\":\"rt-k\"}}" ;

: AUTH-X$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-x\",\"refresh_token\":\"rt-x\",\"account_id\":\"acct\"}}" ;

\ a ChatGPT login with no refresh token
: AUTH-M$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-m\",\"account_id\":\"acct\"}}" ;

: AUTH-U$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-u\",\"refresh_token\":\"rt-u\",\"account_id\":\"acct\"}}" ;

: AUTH-T$ ( -- ptr u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-t\",\"refresh_token\":\"rt-t\",\"account_id\":\"acct\"}}" ;

\ usage codex run with row a u holding login l lu, the fakes' log marked
\ before it
: UT-OUTCOME-RUN ( ptr u8 n ptr u8 n -- ) {: a u l lu :}
   P-CODEX a u l lu UT-PUT
   UT-LOG-MARK
   P-CODEX CMD-USAGE ;

: UT-NOTE= ( ptr u8 n -- ) {: a u :}
   DB-USAGE-NOTE$ a u T$= ;

\ an API-key login without an id_token has no windows: nothing is called
: UT-CODEX-API-KEY ( -- )
   s" k@x.test" AUTH-KEY-AT$ UT-OUTCOME-RUN
   P-CODEX s" k@x.test" UT-RECORD s" unknown" UT-STATE=
   s" API-key login: no usage windows to read" UT-NOTE=
   UT-LOG-NEW$ s" at-k" CONTAINS? TFALSE
   UT-LOG-NEW$ s" rt-k" CONTAINS? TFALSE
   P-CODEX s" k@x.test" CMD-FORGET ;

\ the live login's 401 is reported, and its token is never refreshed
: UT-CODEX-LIVE-401 ( -- )
   UT-LOG-MARK
   P-CODEX CMD-USAGE
   P-CODEX s" c@x.test" UT-RECORD s" expired" UT-STATE=
   s" access token rejected; run codex once to refresh it" UT-NOTE=
   P-CODEX s" c@x.test" UT-LAST-LIVE 1 T=
   UT-LOG-NEW$ s" Bearer at-c" CONTAINS? TTRUE
   UT-LOG-NEW$ s" auth.openai.com/oauth/token" CONTAINS? TFALSE
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$= ;

\ a refresh refused after a 401 that did not say token_revoked is an
\ expired login, not a revoked one
: UT-CODEX-REFUSED ( -- )
   s" x@x.test" AUTH-X$ UT-OUTCOME-RUN
   P-CODEX s" x@x.test" UT-RECORD s" expired" UT-STATE=
   s" access token rejected and the refresh was refused; log in again"
   UT-NOTE=
   UT-LOG-NEW$ s" rt-x" CONTAINS? TTRUE
   P-CODEX s" x@x.test" CMD-FORGET ;

\ a 401 on a saved login with no refresh token saved posts nothing
: UT-CODEX-NO-GRANT ( -- )
   s" m@x.test" AUTH-M$ UT-OUTCOME-RUN
   P-CODEX s" m@x.test" UT-RECORD s" expired" UT-STATE=
   s" access token rejected and no refresh token is saved; log in again"
   UT-NOTE=
   UT-LOG-NEW$ s" auth.openai.com/oauth/token" CONTAINS? TFALSE
   P-CODEX s" m@x.test" CMD-FORGET ;

\ a refresh answering 200 without an access token is an error; the login
\ is kept as it was
: UT-CODEX-NO-ACCESS ( -- )
   s" u@x.test" AUTH-U$ UT-OUTCOME-RUN
   P-CODEX s" u@x.test" UT-RECORD s" error" UT-STATE=
   s" OpenAI's token endpoint answered 200" UT-NOTE=
   P-CODEX s" u@x.test" AUTH-U$ UT-LOGIN=
   P-CODEX s" u@x.test" CMD-FORGET ;

\ a usage 429 is throttled, and earns no refresh
: UT-CODEX-THROTTLED ( -- )
   s" t@x.test" AUTH-T$ UT-OUTCOME-RUN
   P-CODEX s" t@x.test" UT-RECORD s" throttled" UT-STATE=
   s" OpenAI is rate limiting usage checks; try again later" UT-NOTE=
   UT-LOG-NEW$ s" rt-t" CONTAINS? TFALSE
   P-CODEX s" t@x.test" CMD-FORGET ;

\ each outcome of a Codex probe that the shared fake curl never answers,
\ read as kiba-mac's CodexProbe records it; the live c@x.test answers 401
\ throughout
: UT-CODEX-OUTCOMES ( -- )
   UT-OUTCOME-CURL
   UT-CODEX-API-KEY
   UT-CODEX-LIVE-401
   UT-CODEX-REFUSED
   UT-CODEX-NO-GRANT
   UT-CODEX-NO-ACCESS
   UT-CODEX-THROTTLED
   UT-FAKE-CURL ;

\ ---- the order of the queue -------------------------------------------------
create UT-READY 8 allot

\ a shell that locks the stale entry, says so on fd w and holds the lock
\ until it is killed
: UT-HOLDER ( fd -- pid ) {: w:fd :}
   s" /bin/sh" PROCESS:NEW
   s" -c" PROCESS:ARG
   s\" exec 9<\"$0\" && /usr/bin/flock 9 && echo ready && exec /usr/bin/sleep 600" PROCESS:ARG
   UT-STALE$ PROCESS:ARG
   1 >FD w PROCESS:FD
   PROCESS:SPAWN ;

\ the stale entry, locked by a holder that has said it holds it
: UT-HOLD-ENTRY ( -- pid )
   UT-STALE$ s" " WRITE-PRIVATE
   FD:PIPE-PAIR {: r:fd w:fd :}
   w UT-HOLDER {: pid :}
   w FD>N close
   r FD>N UT-READY 8 read 6 T=
   r FD>N close
   UT-READY 6 s\" ready\n" T$=
   pid ;

: UT-STOP ( pid -- ) {: pid :}
   pid PROCESS:SIGKILL PROCESS:KILL-RAW RC>N 0 T=
   pid PROCESS:WAIT PROCESS:STATUS>RC RC>N 137 T= ;

: UT-TURN-FREE ( -- )
   UT-TURN$ FS:>PATHZ open-rd {: fd :}
   fd >FD FS-LOCK:TRY TTRUE
   fd close ;

\ the turn is free, but the entry ahead is held: the wait runs its whole
\ TURN-WAIT-MS, and only the entry ahead stays queued
: UT-WAIT-BEHIND ( -- )
   UT-TURN-FREE
   300 TURN-WAIT-MS !
   TIME:MONO-NS {: t0 :}
   [: P-CLAUDE TURN-ENTER ;] E-SW-TURN-BUSY TTHROWSQ
   TIME:MONO-NS t0 - 300000000 >= TTRUE
   120000 TURN-WAIT-MS !
   UT-QUEUE-LEN {: n :}
   UT-LIST n s" 00000000000000000000-0000000001-00000000000000000000" T$= ;

\ waiters take the turn in queue order: a held entry ahead keeps
\ TURN-ENTER waiting; once its holder is gone the entry is removed and the
\ turn taken
: UT-TURN-ORDER ( -- )
   UT-HOLD-ENTRY {: pid :}
   [: UT-WAIT-BEHIND ;] [: pid UT-STOP ;] finally
   P-CLAUDE TURN-ENTER
   UT-STALE$ FS:FILE? TFALSE
   P-CLAUDE TURN-LEAVE
   UT-QUEUE-LEN 0 T= ;

\ ---- commands in their turn -------------------------------------------------
create UT-FAKE-PATH PATH-CAP allot   variable UT-FAKE-U
create UT-ANS-PATH PATH-CAP allot    variable UT-ANS-U
create UT-OWN-TURN PATH-CAP allot    variable UT-OWN-TURN-U
create UT-WRAP-BUF 1024 allot

\ provider p's turn file
: UT-TURN-OF$ ( n -- ptr u8 n ) {: p :}
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /turn-" SB-APPEND p PROVIDER$ SB-APPEND
   SB$ UT-OWN-TURN UT-OWN-TURN-U PATH!
   UT-OWN-TURN UT-OWN-TURN-U @ ;

\ the fake script name in the scratch PATH
: UT-FAKE$ ( ptr u8 n -- ptr u8 n ) {: n nu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND
   SB$ UT-FAKE-PATH UT-FAKE-U PATH!
   UT-FAKE-PATH UT-FAKE-U @ ;

\ where the fake name goes once a turn check runs in front of it
: UT-ANSWERS$ ( ptr u8 n -- ptr u8 n ) {: n nu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND
   s" -answers" SB-APPEND
   SB$ UT-ANS-PATH UT-ANS-U PATH!
   UT-ANS-PATH UT-ANS-U @ ;

\ a script that logs "turn held <name>" when provider p's turn is locked as
\ it starts, "turn free <name>" when it is not, then runs the fake name
: UT-WRAP$ ( n ptr u8 n -- ptr u8 n ) {: p n nu :}
   p UT-TURN-OF$ {: t tu :}
   n nu UT-ANSWERS$ {: x xu :}
   SB-RESET s\" #!/bin/sh\n/usr/bin/flock -n -E 9 '" SB-APPEND
   t tu SB-APPEND s\" ' /usr/bin/true\ncase $? in " SB-APPEND
   s\" 0) s=free;; 9) s=held;; *) s=unknown;; esac\n" SB-APPEND
   s\" echo \"turn $s " SB-APPEND n nu SB-APPEND
   s\" \" >> \"$KIBA_TEST_LOG\"\nexec '" SB-APPEND
   x xu SB-APPEND s\" ' \"$@\"\n" SB-APPEND
   SB$ UT-WRAP-BUF 1024 SPAN-COPY ;

\ the fake name, already written, runs behind a check of p's turn
: UT-TURN-WRAP ( n ptr u8 n -- ) {: p n nu :}
   n nu UT-FAKE$ n nu UT-ANSWERS$ FS:RENAME-FILE
   n nu p n nu UT-WRAP$ UT-WRITE-SCRIPT ;

: UT-TURN-LINE$ ( ptr u8 n ptr u8 n -- ptr u8 n ) {: s su n nu :}
   SB-RESET s" turn " SB-APPEND s su SB-APPEND
   STR-SPACE SB-APPEND-C n nu SB-APPEND SB$ ;

\ since the mark, name ran with its provider's turn held, never without
: UT-RAN-HELD ( ptr u8 n -- ) {: n nu :}
   UT-LOG-NEW$ {: l lu :}
   l lu s" held" n nu UT-TURN-LINE$ CONTAINS? TTRUE
   l lu s" free" n nu UT-TURN-LINE$ CONTAINS? TFALSE
   l lu s" unknown" n nu UT-TURN-LINE$ CONTAINS? TFALSE ;

\ usage probes each provider's logins inside that provider's turn
: UT-USAGE-HELD ( -- )
   UT-FAKE-CURL P-CLAUDE s" curl" UT-TURN-WRAP
   UT-LOG-MARK
   P-CLAUDE CMD-USAGE
   s" curl" UT-RAN-HELD
   UT-FAKE-CURL P-CODEX s" curl" UT-TURN-WRAP
   UT-LOG-MARK
   P-CODEX CMD-USAGE
   s" curl" UT-RAN-HELD ;

\ use probes the login it installs and the one it saved back in its turn
: UT-USE-HELD ( -- )
   UT-LOG-MARK
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" c@x.test" CMD-USE
   s" curl" UT-RAN-HELD ;

\ redeem asks for the reset and probes again in its turn
: UT-REDEEM-HELD ( -- )
   UT-LOG-MARK
   s" reset" s" Limit reset for w@x.test" UT-CODEX-WORD
   s" curl" UT-RAN-HELD
   P-CODEX s" w@x.test" CMD-FORGET ;

\ add's login runs in its turn, and so does the probe of the new login
: UT-ADD-HELD ( -- )
   UT-FAKE-CLAUDE P-CLAUDE s" claude" UT-TURN-WRAP
   UT-FAKE-CURL P-CLAUDE s" curl" UT-TURN-WRAP
   UT-LOG-MARK
   P-CLAUDE s" b@x.test" CMD-ADD
   s" claude" UT-RAN-HELD
   s" curl" UT-RAN-HELD
   P-CLAUDE s" b@x.test" CMD-FORGET
   UT-FAKE-CLAUDE ;

\ every command that calls out does so holding its provider's turn
: UT-COMMANDS-HELD ( -- )
   UT-USAGE-HELD
   UT-USE-HELD
   UT-REDEEM-HELD
   UT-ADD-HELD
   UT-FAKE-CURL ;

\ a Claude turn held elsewhere: usage waits TURN-WAIT-MS, reports the busy
\ turn as Claude's error and calls nothing
: UT-USAGE-BUSY ( -- )
   UT-TURN$ FS:>PATHZ open-rd {: fd :}
   fd >FD FS-LOCK:TRY TTRUE
   300 TURN-WAIT-MS !
   P-CLAUDE UT-USAGES UT-C0 !
   UT-LOG-MARK
   P-CLAUDE UT-USAGE-ERR
   120000 TURN-WAIT-MS !
   fd close
   UT-ERR$ READ-FILE$
   s\" claude: another kiba holds that provider's turn\n" T$=
   UT-LOG-NEW$ nip 0 T=
   P-CLAUDE UT-USAGES UT-C0 @ T= ;

: UT-MAIN ( -- )
   T-RESET
   ALLOC-BUFFERS
   UT-B64
   UT-JWT
   UT-DOC
   UT-IDENTITY
   UT-PLAN-UNREADABLE
   UT-STRINGS
   UT-READER-RECOVERS
   UT-CLAIMS-REPEAT
   UT-FIELD-LONG
   UT-WHOLE-EXPIRY
   UT-DOC-CLOSE
   UT-STORE-SAVE
   UT-STORE-USE
   UT-STORE-USE-CODEX
   UT-NAME-KEEPS-ROWS
   UT-READS-KEEP-ROWS
   UT-SAME-EMAIL
   UT-INSTALL-INSERT
   UT-FAILED-FIRST-WRITE
   UT-CREDS-DIR
   UT-RESTORED
   UT-REPAIR-PENDING
   UT-MISMATCH
   UT-DAMAGED-ROW
   UT-REPEATED-CREDS
   UT-API-KEY
   UT-SYMLINK
   UT-FAILED-WRITE
   UT-MIXED-PAIR
   UT-UNRESTORED
   UT-ORPHAN
   UT-ORPHAN-STOPS
   UT-UNNAMED-CLAUDE
   UT-UNNAMED-CODEX
   UT-STORE-FORGET
   UT-LIVE-AC
   UT-ADD
   UT-ADD-EMPTY
   UT-ADD-CLAUDE
   UT-ADD-STALE
   UT-PCT
   UT-PCT-CALLERS
   UT-LONG-TOKEN
   UT-SCRATCH-APART
   UT-RENEWED-THROWS
   UT-USAGE
   UT-USAGE-REFRESHED
   UT-USAGE-REVOKED
   UT-USAGE-REVOKED-AGAIN
   UT-ANSWER-READS
   UT-CLAUDE-OUTCOMES
   UT-CODEX-OUTCOMES
   UT-LIVE-EXPIRED
   UT-MIXED-USAGE
   UT-USAGE-ISOLATION
   UT-DAMAGED-LIVE-SLOT
   UT-DAMAGED-NOT-CLAIMED
   UT-UNREPAIRED
   UT-UNRECORDED
   UT-USAGE-CHECKED
   UT-USE-PROBES
   UT-USE-PROBES-CLAUDE
   UT-COMMANDS-HELD
   UT-USAGE-BUSY
   UT-REDEEM-CLAUDE
   UT-REDEEM-RENEWED
   UT-REDEEM-SEGMENT
   UT-REDEEM-LIVE
   UT-REDEEM-CODEX
   UT-REDEEM-REVOKED
   UT-REDEEM-EXPIRED
   UT-REDEEM-UNKNOWN
   UT-REDEEM-BLOCKED
   UT-NAMES
   UT-DB
   UT-TURN-ROUND
   UT-TURN-STALE
   UT-TURN-BUSY
   UT-TURN-ORDER
   T-REPORT ;

UT-MAIN

;package
