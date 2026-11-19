split-str
\ sw-unit-test.f - checked kiba tests.
\ Run through test.sh: HOME, XDG_DATA_HOME, and PATH must point at a scratch tree.
\ kiba's requests reach a server in this process, which answers them from
\ fixture rows and logs what each one carried.
require ../src/kiba.f
require ../src/sw-turn.f
require ../src/sw-base.f
require ../src/sw-paths.f
require ../src/sw-io.f
require ../src/sw-json.f
require ../src/sw-identity.f
require ../src/sw-sqlite.f
require ../src/sw-db.f
require ../src/sw-store.f
require ../src/sw-time.f
require ../src/sw-usage.f
require ../src/sw-cli.f
require src/lib/test.f
require src/lib/fs-list.f
require src/lib/fs-lock.f
require src/lib/fd.f
require src/lib/process.f
require src/lib/spawn.f
require src/lib/time.f
require src/lib/test/stderr.f
require src/lib/test/runner.f
require src/lib/adt/option.f
require src/lib/error.f
require src/lib/fmt.f
require src/lib/fs-mutate.f
require src/lib/fs.f
require src/lib/json.f
require src/lib/prelude.f
require src/lib/span.f
require src/lib/string.f
require src/lib/aio.f
require src/lib/net/tcp4.f
require src/lib/net/http.f

\ White-box: reopens SW for sw-usage.f's private URL-BASE; SW-TEST: words
\ land in SW-TEST, the rest in SW.
package SW

\ every request goes to b u followed by its URL after the https://
: SW-TEST:UT-SERVE-AT ( ^u8 n -- ) URL-BASE URL-BASE-U PATH! ;

;package

package SW-TEST
using SW

create UT-BUF 256 allot

: SPAN-COPY ( ^u8 n ^u8 n -- ^u8 n ) {: a u dst cap :}
   u cap > if E-SW-CAPACITY throw then
   a dst u BYTE-COPY
   dst u ;

: CFG-A$ ( -- ^u8 n )
   s\" {\"numStartups\":3,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: OAUTH-A$ ( -- ^u8 n )
   s\" {\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}" ;

: CFG-B$ ( -- ^u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

\ CFG-B with account A spliced back in
: CFG-BA$ ( -- ^u8 n )
   s\" {\"numStartups\":4,\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: CREDS-A$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a\",\"refreshToken\":\"r-a\",\"expiresAt\":4102444800000,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\",\"rateLimitTier\":\"default_claude_max_20x\"}}" ;

: CREDS-B$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"refreshTokenExpiresAt\":1,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}" ;

: CREDS-E$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-e\",\"refreshToken\":\"r-e\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

: CREDS-F$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-f\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

: AUTH-C$ ( -- ^u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImNAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsImNoYXRncHRfYWNjb3VudF9pZCI6ImFjY3QifSwiZXhwIjoxfQ.c2ln\",\"access_token\":\"at-c\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"},\"last_refresh\":\"2026-09-14T07:11:36Z\"}" ;

: AUTH-D$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}" ;

: AUTH-KEY$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"sk-x\"}" ;

: AUTH-KEY-NULL$ ( -- ^u8 n )
   s\" {\"OPENAI_API_KEY\":\"sk-x\",\"tokens\":null,\"last_refresh\":null}" ;

: CREDS-NULL-PLAN$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-n\",\"subscriptionType\":null}}" ;

: CFG-EMPTY$ ( -- ^u8 n ) s\" {}" ;
: CFG-NOAUTH$ ( -- ^u8 n ) s\" {\"numStartups\":1}" ;

: UT-PAYLOAD= ( ^u8 n ^u8 n -- ) {: a u w wu :}
   a u DECODE-PAYLOAD OBJ$ w wu T$= ;

: UT-PAYLOAD-BAD ( ^u8 n n -- ) {: a u code :}
   [: a u DECODE-PAYLOAD ;] code TTHROWSQ ;

: UT-B64 ( -- )
   s" aGVsbG8" s" hello" UT-PAYLOAD=
   s" aGk" s" hi" UT-PAYLOAD=
   s" aGVsbG8=" s" hello" UT-PAYLOAD=
   s" aGk==" s" hi" UT-PAYLOAD=
   s" -_8" DECODE-PAYLOAD OBJ$ nip 2 T=
   OBJ-BUF c@ $FB T=
   OBJ-BUF 1+ c@ $FF T=
   s" aGVsbG8hY" E-BASE64-LENGTH UT-PAYLOAD-BAD
   s" a!b" E-BASE64-CHAR UT-PAYLOAD-BAD
   s" +_8" E-BASE64-CHAR UT-PAYLOAD-BAD
   s" -/8" E-BASE64-CHAR UT-PAYLOAD-BAD
   s" aGk=x" E-BASE64-LENGTH UT-PAYLOAD-BAD
   s" aGk=aGk" E-BASE64-PAD UT-PAYLOAD-BAD
   s" aGk===" E-BASE64-PAD UT-PAYLOAD-BAD
   E-BASE64-LENGTH REASON$ s" kiba: id_token is not base64url" T$= ;

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
: CLAIMS-R$ ( -- ^u8 n )
   s\" {\"email\":\"r@x.test\",\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"plus\",\"seats\":{\"n\":1,\"n\":2}}}" ;

: AUTH-R$ ( -- ^u8 n )
   s\" {\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InJAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsInNlYXRzIjp7Im4iOjEsIm4iOjJ9fX0.c2ln\"}}" ;

\ claims that repeat a key deeper than CHECK-OBJECT looks are no login:
\ CODEX-IDENTITY's CHECK-FIELDS refuses them
: UT-CLAIMS-REPEAT ( -- )
   AUTH-R$ CHECK-OBJECT
   CLAIMS-R$ CHECK-OBJECT
   [: AUTH-R$ ID-SLOT CODEX-IDENTITY drop ;] E-SW-JSON TTHROWSQ ;

\ a key repeated four objects deep, once escaped: FIELDS? refuses it, and
\ CHECK-OBJECT, which looks only at the root and the objects directly under
\ it, takes it
: UT-DEEP-REPEAT ( -- )
   s\" {\"a\":{\"b\":{\"c\":{\"d\":{\"x\":1,\"\\u0078\":2}}}}}" {: d du :}
   d du FIELDS? TFALSE
   d du CHECK-OBJECT ;

DYNAMIC-BUFFER UT-BIG u8   variable UT-BIG-U
8000 constant UT-DEPTH
100000 constant UT-KEYS

: BIG-C+ ( n -- ) UT-BIG-U @ UT-BIG c!  1 UT-BIG-U +! ;

: BIG+ ( ^u8 n -- ) {: a u :}
   a UT-BIG-U @ UT-BIG u BYTE-COPY  u UT-BIG-U +! ;

: BIG$ ( -- ^u8 n ) 0 UT-BIG UT-BIG-U @ ;

\ an object nested UT-DEPTH deep, six bytes a level
: UT-NESTED$ ( -- ^u8 n )
   UT-DEPTH 6 * 2 + UT-BIG-RESERVE  0 UT-BIG-U !
   UT-DEPTH 0 ?do s\" {\"a\":" BIG+ loop
   s" {}" BIG+
   UT-DEPTH 0 ?do s" }" BIG+ loop
   BIG$ ;

\ member n of a wide object: its key spells n in four letters
: UT-MEMBER+ ( n -- )
   s\" \"" BIG+
   4 0 ?do 26 /mod swap [char] a + BIG-C+ loop drop
   s\" \":0," BIG+ ;

\ one object of UT-KEYS keys, nine bytes a member
: UT-WIDE$ ( -- ^u8 n )
   UT-KEYS 9 * 2 + UT-BIG-RESERVE  0 UT-BIG-U !
   s" {" BIG+
   UT-KEYS 0 ?do i UT-MEMBER+ loop
   -1 UT-BIG-U +!  s" }" BIG+
   BIG$ ;

\ FIELDS? takes d du in under a second
: FAST-FIELDS ( ^u8 n -- ) {: d du :}
   TIME:MONO-NS {: t0 :}
   d du FIELDS? TTRUE
   TIME:MONO-NS t0 - 1000000000 < TTRUE ;

\ the repeated-key check is linear in the document's bytes and keys
: UT-REPEATS-FAST ( -- )
   UT-NESTED$ FAST-FIELDS
   UT-WIDE$ FAST-FIELDS
   UT-BIG-RELEASE ;

\ an identity field longer than its buffer is an error, never a missing field
: UT-FIELD-LONG ( -- )
   [: CFG-A$ s\" {\"claudeAiOauth\":{\"subscriptionType\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\"}}" ID-SLOT CLAUDE-IDENTITY drop ;]
   E-SW-CAPACITY TTHROWSQ ;

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
: CREDS-A9$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a9\",\"refreshToken\":\"r-a9\",\"expiresAt\":4102444800000,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

: AUTH-C9$ ( -- ^u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImNAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicGx1cyIsImNoYXRncHRfYWNjb3VudF9pZCI6ImFjY3QifSwiZXhwIjoxfQ.c2ln\",\"access_token\":\"at-c9\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"},\"last_refresh\":\"2026-09-14T07:11:36Z\"}" ;

\ CFG-A with account B spliced in
: CFG-AB$ ( -- ^u8 n )
   s\" {\"numStartups\":3,\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\"},\"projects\":{\"/x\":{\"allowedTools\":[]}}}" ;

: CFG-ONLY-A$ ( -- ^u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u1\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-a\",\"organizationName\":\"Org A\"}}" ;

variable UT-N
create UT-LOCKED-BUF 256 allot   variable UT-LOCKED-U
create UT-REAL-BUF 256 allot     variable UT-REAL-U

: UT-STORE ( [ -- ] -- ) {: body :}
   DB-OPEN [: body execute ;] [: DB-CLOSE ;] finally ;

: UT-LOGIN= ( n ^u8 n ^u8 n -- ) {: p a u l lu :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-LOGIN$ l lu T$= ;] UT-STORE ;

: UT-FETCH ( n ^u8 n -- ) {: p a u :} p a u DB-FETCH UT-N ! ;

: UT-ROW? ( n ^u8 n -- bool ) {: p a u :}
   [: p a u UT-FETCH ;] UT-STORE UT-N @ ;

: UT-INSTALLED= ( n ^u8 n -- ) {: p a u :}
   [: p DB-INSTALLED TTRUE a u T$= ;] UT-STORE ;

: UT-PENDING-KEEP ( n -- ) DB-PENDING UT-N ! 2drop ;

: UT-PENDING? ( n -- bool ) {: p :}
   [: p UT-PENDING-KEEP ;] UT-STORE UT-N @ ;

: UT-PENDING= ( n ^u8 n -- ) {: p a u :}
   [: p DB-PENDING TTRUE a u T$= ;] UT-STORE ;

: UT-KEEP-NAME ( n -- ) {: p :}
   p LIVE-IDENTITY TTRUE
   p ID-LIVE DB-LIVE-NAME UT-BUF 256 SPAN-COPY nip UT-N ! ;

\ the name DB-LIVE-NAME gives the live login now
: UT-LIVE-NAME ( n -- ^u8 n ) {: p :}
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
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" b@x.test" T$=
   [: P-CLAUDE s" nobody@x" CMD-USE ;] E-SW-NO-ACCOUNT TTHROWSQ
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" b@x.test" UT-INSTALLED= ;

: UT-STORE-USE-CODEX ( -- )
   CODEX-AUTH$ AUTH-C9$ WRITE-PRIVATE
   P-CODEX s" d@x.test" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   P-CODEX s" c@x.test" AUTH-C9$ UT-LOGIN=
   P-CODEX s" d@x.test" UT-INSTALLED=
   P-CODEX UT-PENDING? TFALSE ;

\ taking Codex's live name leaves the Claude rows a caller listed
: UT-NAME-KEEPS-ROWS ( -- )
   P-CODEX LIVE-IDENTITY TTRUE
   [: P-CLAUDE DB-LIST
      P-CODEX ID-LIVE DB-LIVE-NAME s" d@x.test" T$=
      DB-ROW# 2 T=
      0 DB-ROW-NAME$ s" a@x.test" T$=
      1 DB-ROW-NAME$ s" b@x.test" T$= ;] UT-STORE ;

\ Codex's installed and pending reads answer their records and leave the
\ Claude rows a caller listed
: UT-MARKS-READ ( -- )
   P-CLAUDE DB-LIST
   P-CODEX DB-INSTALLED TTRUE s" d@x.test" T$=
   P-CODEX DB-PENDING TTRUE s" c@x.test" T$=
   DB-ROW# 2 T=
   0 DB-ROW-NAME$ s" a@x.test" T$=
   1 DB-ROW-NAME$ s" b@x.test" T$= ;

\ notes the marks, reads them and clears them again in one transaction
: UT-MARKS ( -- )
   P-CODEX s" c@x.test" DB-NOTE-PENDING
   UT-MARKS-READ
   P-CODEX DB-CLEAR-PENDING ;

: UT-READS-KEEP-ROWS ( -- ) [: [: UT-MARKS ;] DB-WRITE ;] UT-STORE ;

\ a second login under the same email but another organization gets its own
\ name, "a@x.test #2"
: CFG-A2$ ( -- ^u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u9\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-c\",\"organizationName\":\"Org C\"}}" ;

\ a third organization whose name only repeats the email
: CFG-A3$ ( -- ^u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u8\",\"emailAddress\":\"a@x.test\",\"organizationUuid\":\"org-d\",\"organizationName\":\"a@x.test's Organization\"}}" ;

: CREDS-A2$ ( -- ^u8 n )
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
   UT-NO-CREDS
   CLAUDE-CREDS$ ENSURE-PRIVATE
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-FS-IO TTHROWSQ
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" a@x.test" UT-INSTALLED=
   CLAUDE-CREDS$ FS:REMOVE-DIR
   CLAUDE-CREDS$ CREDS-A9$ WRITE-PRIVATE ;

create UT-INNER-BUF 256 allot

: UT-INNER$ ( -- ^u8 n )
   CLAUDE-CONFIG$ {: c cu :}
   SB-RESET c cu SB-APPEND s" /keep.json" SB-APPEND SB$ UT-INNER-BUF 256 SPAN-COPY ;

\ removing the config refuses a directory at its path and deletes nothing
: UT-CONFIG-DIR ( -- )
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   CLAUDE-CONFIG$ FS:REMOVE-FILE
   CLAUDE-CONFIG$ ENSURE-PRIVATE
   UT-INNER$ CFG-A$ WRITE-PRIVATE
   [: UT-BUF -1 PUT-CONFIG ;] E-FS-IO TTHROWSQ
   CLAUDE-CONFIG$ FS:DIR? TTRUE
   UT-INNER$ READ-FILE$ CFG-A$ T$=
   CLAUDE-CONFIG$ FS:REMOVE-TREE
   CLAUDE-CONFIG$ CFG-ONLY-A$ WRITE-PRIVATE ;

: UT-LOCKED$ ( -- ^u8 n )
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /locked" SB-APPEND SB$ UT-LOCKED-BUF 256 SPAN-COPY ;

: UT-REAL$ ( -- ^u8 n )
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

\ a failed credentials write puts the old config back; with no install
\ pending before, the pair is known: the marker is cleared, nothing recorded
: UT-RESTORED ( -- )
   UT-LINK-CREDS
   [: P-CLAUDE s" b@x.test" CMD-USE ;] E-FS-OPEN TTHROWSQ
   CLAUDE-CONFIG$ READ-FILE$ CFG-ONLY-A$ T$=
   UT-REAL$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" a@x.test" UT-INSTALLED=
   UT-UNLINK-CREDS ;

: UT-NOTE-PENDING ( -- )
   [: P-CLAUDE s" a@x.test" DB-NOTE-PENDING ;] DB-WRITE ;

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
   [: P-CODEX s" z@x.test" CMD-USE ;] E-SW-MISMATCH TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-D$ T$=
   P-CODEX s" d@x.test" UT-INSTALLED=
   P-CODEX s" z@x.test" CMD-FORGET ;

: UT-PUT-BAD ( -- )
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" bad@x.test" ID-SLOT s" garbage" s\" {\"emailAddress\":\"bad@x.test\"}" false DB-PUT ;] DB-WRITE ;

\ a saved login that is not JSON is refused before the install is noted
: UT-DAMAGED-ROW ( -- )
   [: UT-PUT-BAD ;] UT-STORE
   [: P-CLAUDE s" bad@x.test" CMD-USE ;] E-JSON-READ-MALFORMED TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" bad@x.test" CMD-FORGET ;

: CFG-Q$ ( -- ^u8 n )
   s\" {\"oauthAccount\":{\"accountUuid\":\"u9\",\"emailAddress\":\"q@x.test\"}}" ;

\ credentials whose claudeAiOauth repeats a key
: CREDS-Q$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-q\",\"subscriptionType\":\"max\",\"subscriptionType\":\"pro\"}}" ;

\ a claudeAiOauth that repeats a key saves with no plan (PLAN-READ?) and
\ is refused before the install is noted (CHECK-CREDS's CHECK-OBJECT)
: UT-REPEATED-CREDS ( -- )
   CLAUDE-CONFIG$ CFG-Q$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-Q$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" q@x.test" CREDS-Q$ UT-LOGIN=
   [: P-CLAUDE s" q@x.test" DB-FETCH TTRUE
      0 DB-ROW-PLAN$ nip 0 T= ;] UT-STORE
   P-CLAUDE s" a@x.test" CMD-USE
   [: P-CLAUDE s" q@x.test" CMD-USE ;] E-SW-JSON TTHROWSQ
   CLAUDE-CREDS$ READ-FILE$ CREDS-A9$ T$=
   P-CLAUDE UT-PENDING? TFALSE
   P-CLAUDE s" a@x.test" UT-INSTALLED=
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

create UT-REL-BUF PATH-CAP allot
create UT-LINK-TEXT PATH-CAP allot
4096 constant UT-CFG0-CAP
create UT-CFG0 UT-CFG0-CAP allot   variable UT-CFG0-U

\ where a relative link at p whose text is f points
: UT-SIBLING$ ( ^u8 n ^u8 n -- ^u8 n )
   {: p pu f fu :}
   p pu DIRNAME {: d du :}
   SB-RESET d du SB-APPEND s" /" SB-APPEND f fu SB-APPEND
   SB$ UT-REL-BUF PATH-CAP SPAN-COPY ;

: UT-LINK$ ( ^u8 n -- ^u8 n )
   FS:>PATHZ UT-LINK-TEXT PATH-CAP readlink {: n :}
   n 0 < if E-FS-IO throw then
   UT-LINK-TEXT n ;

\ live file p moved to where text f points from p's directory, and p made
\ a link whose text is f
: UT-REL-LINK ( ^u8 n ^u8 n -- )
   {: p pu f fu :}
   p pu f fu UT-SIBLING$ {: r ru :}
   r ru DIRNAME ENSURE-PRIVATE
   p pu r ru FS:RENAME-FILE
   f fu p pu FS:MAKE-SYMLINK ;

\ p is still a link whose text is f, and the file f names holds w
: UT-REL-HOLDS ( ^u8 n ^u8 n ^u8 n -- )
   {: p pu f fu w wu :}
   p pu FS:SYMLINK? TTRUE
   p pu UT-LINK$ f fu T$=
   p pu f fu UT-SIBLING$ READ-FILE$ w wu T$= ;

: UT-REL-UNLINK ( ^u8 n ^u8 n -- )
   {: p pu f fu :}
   p pu FS:REMOVE-FILE
   p pu f fu UT-SIBLING$ p pu FS:RENAME-FILE ;

: UT-REL-CODEX ( -- )
   CODEX-AUTH$ s" real-auth.json" UT-REL-LINK
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ s" real-auth.json" AUTH-C9$ UT-REL-HOLDS
   P-CODEX s" d@x.test" CMD-USE
   CODEX-AUTH$ s" real-auth.json" AUTH-D$ UT-REL-HOLDS
   CODEX-AUTH$ s" real-auth.json" UT-REL-UNLINK ;

\ the config before the test is put back afterwards
: UT-REL-CLAUDE ( -- )
   CLAUDE-CONFIG$ READ-FILE$ UT-CFG0 UT-CFG0-CAP SPAN-COPY UT-CFG0-U ! drop
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CONFIG$ s" kiba-dots/claude.json" UT-REL-LINK
   P-CLAUDE s" b@x.test" CMD-USE
   CLAUDE-CONFIG$ s" kiba-dots/claude.json" CFG-AB$ UT-REL-HOLDS
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CONFIG$ s" kiba-dots/claude.json" CFG-A$ UT-REL-HOLDS
   CLAUDE-CONFIG$ s" kiba-dots/claude.json" UT-REL-UNLINK
   CLAUDE-CONFIG$ s" kiba-dots" UT-SIBLING$ FS:REMOVE-DIR
   CLAUDE-CONFIG$ UT-CFG0 UT-CFG0-U @ WRITE-PRIVATE ;

\ a live file that is a relative symlink stays one, its text as it was: a
\ switch writes the file the text names from the link's own directory
: UT-REL-SYMLINK ( -- )
   UT-REL-CODEX
   UT-REL-CLAUDE ;

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

create UT-DEEP 1024 allot
create UT-WANT 16384 allot   variable UT-WANT-U

\ a root under HOME whose .claude.json path is 1010 bytes; a slash every 200
\ bytes keeps each name under NAME_MAX
: UT-DEEP-ROOT$ ( -- ^u8 n )
   SB-RESET HOME$ SB-APPEND
   989 HOME$ nip - 0 ?do i 200 mod 0= if [char] / else [char] a then SB-APPEND-C loop
   SB$ UT-DEEP 1024 SPAN-COPY ;

: UT-WANT+ ( ^u8 n -- ) {: a u :}
   a UT-WANT UT-WANT-U @ + u BYTE-COPY
   u UT-WANT-U +! ;

: UT-WANT$ ( -- ^u8 n ) UT-WANT UT-WANT-U @ ;

\ the orphan reason, longer than SB holds, names a 1010-byte config path whole
: UT-ORPHAN-LONG ( -- )
   UT-DEEP-ROOT$ {: r ru :}
   r ru LOGIN-ROOT!
   CLAUDE-CONFIG$ nip 1010 T=
   CLAUDE-CREDS$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CREDS$ CREDS-A9$ WRITE-PRIVATE
   [: P-CLAUDE LIVE-IDENTITY drop ;] E-SW-ORPHAN-LIVE TTHROWSQ
   LOGIN-ROOT-CLEAR
   0 UT-WANT-U !
   s" kiba: Claude credentials exist but " UT-WANT+ r ru UT-WANT+ s" /.claude/.claude.json" UT-WANT+
   s"  is missing: nothing is probed or switched until it names their account" UT-WANT+
   E-SW-ORPHAN-LIVE REASON$ UT-WANT$ T$=
   r HOME$ nip 200 + FS:REMOVE-TREE ;

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

: UT-WRITE-SCRIPT ( ^u8 n ^u8 n -- ) {: n nu body bu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin" SB-APPEND SB$ ENSURE-PRIVATE
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND SB$ UT-BUF 256 SPAN-COPY {: f fu :}
   f fu body bu FS:WRITE-ALL
   f fu FS:CHMOD-X ;

: AUTH-D2$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\",\"account_id\":\"acct\"}}" ;

: AUTH-Y$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-y\",\"refresh_token\":\"rt-y\",\"account_id\":\"acct\"}}" ;

\ the login AUTH-AT$ or CREDS-TOKEN$ built last, kept past the next use of SB
create UT-AT-BUF 1024 allot

\ a saved Codex login whose access token is at-<t>
: AUTH-AT$ ( ^u8 n -- ^u8 n ) {: t tu :}
   SB-RESET s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-" SB-APPEND
   t tu SB-APPEND s\" \",\"refresh_token\":\"rt-n\",\"account_id\":\"acct\"}}" SB-APPEND
   SB$ UT-AT-BUF 1024 SPAN-COPY ;

: AUTH-Z$ ( -- ^u8 n )
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

\ RFC 3339 instants as epoch seconds, -1 when malformed or before 1970
: UT-RFC3339 ( -- )
   s" 2026-11-24T14:00:00Z" RFC3339>EPOCH 1795528800 T=
   s" 2026-11-24T16:00:00.123456+02:00" RFC3339>EPOCH 1795528800 T=
   s" 2026-11-24t14:00:00z" RFC3339>EPOCH 1795528800 T=
   s" 2026-11-24 09:30:00-04:30" RFC3339>EPOCH 1795528800 T=
   s" 2026-11-24T15:00:00+02:00" RFC3339>EPOCH 1795525200 T=
   s" 1970-01-01T00:00:00Z" RFC3339>EPOCH 0 T=
   s" 2026-11-24T23:59:60Z" RFC3339>EPOCH 1795564799 T=
   s" 2026-11-24T14:00:00" RFC3339>EPOCH -1 T=
   s" 2026-11-24T14:00:00.Z" RFC3339>EPOCH -1 T=
   s" 2026-13-01T00:00:00Z" RFC3339>EPOCH -1 T=
   s" 2026-11-24T24:00:00Z" RFC3339>EPOCH -1 T=
   s" 2026-11-24T14:60:00Z" RFC3339>EPOCH -1 T=
   s" 2026-11-24T14:00:00+0200" RFC3339>EPOCH -1 T=
   s" 2026-11-24T14:00:00+24:00" RFC3339>EPOCH -1 T=
   s" 1969-12-31T23:59:59Z" RFC3339>EPOCH -1 T=
   s" 2026-11-24T14:00:00Zx" RFC3339>EPOCH -1 T=
   s" " RFC3339>EPOCH -1 T= ;

: LOG$ ( -- ^u8 n )
   s" KIBA_TEST_LOG" GETENV ;

variable UT-LOG0

: UT-LOG-MARK ( -- ) LOG$ READ-FILE$ nip UT-LOG0 ! ;

\ what the fakes and the server logged since the mark
: UT-LOG-NEW$ ( -- ^u8 n )
   LOG$ READ-FILE$ {: l lu :}
   l UT-LOG0 @ + lu UT-LOG0 @ - ;

\ ---- the provider server -----------------------------------------------------
\ One route per endpoint, its host the first path segment. A worker task runs
\ the handler while the main task waits in CURL:PERFORM, so the main task
\ changes the rows only between requests.
$7F000001 constant UT-LOOPBACK
2 constant UT-WORKERS        \ a worker lingers on a connection it answered
500 constant UT-IDLE-MS
64 constant UT-ROW-MAX
$500000 constant UT-ARENA-CAP   \ the rows' bytes: one body past BUF-CAP and the rest

\ a row's cells: its route, key, body, file and file bytes as arena offset
\ and length, and its status
0 constant UT-F-ROUTE
2 constant UT-F-KEY
4 constant UT-F-STATUS
5 constant UT-F-BODY
7 constant UT-F-FILE
9 constant UT-F-BYTES
11 constant UT-ROW-CELLS
UT-ROW-MAX UT-ROW-CELLS * constant UT-CELL-MAX

UT-CELL-MAX TYPED-BUFFER UT-ROWS n
TYPED-VARIABLE UT-ARENA-A ^u8   variable UT-ARENA-U
variable UT-ROW-N                  \ the rows a worker may read, published with atomic!
create UT-LOG-PATH PATH-CAP allot     variable UT-LOG-PATH-U
create UT-CLAUDE-TURN PATH-CAP allot  variable UT-CLAUDE-TURN-U
create UT-CODEX-TURN PATH-CAP allot   variable UT-CODEX-TURN-U

: UT-ARENA ( -- ^u8 ) UT-ARENA-A @ ;
: UT-ROW-CELL ( n n -- ^n ) swap UT-ROW-CELLS * + UT-ROWS ;

\ field f of row i, a span in the arena
: UT-ROW$ ( n n -- ^u8 n ) {: i f :}
   UT-ARENA i f UT-ROW-CELL @ + i f 1+ UT-ROW-CELL @ ;

: UT-ARENA-ROOM ( n -- )
   UT-ARENA-U @ + UT-ARENA-CAP > if E-SW-CAPACITY throw then ;

: UT-ARENA+ ( ^u8 n -- ) {: a u :}
   u UT-ARENA-ROOM
   a UT-ARENA UT-ARENA-U @ + u BYTE-COPY
   u UT-ARENA-U +! ;

\ field f of row i becomes a copy of a u
: UT-FIELD! ( ^u8 n n n -- ) {: a u i f :}
   UT-ARENA-U @ i f UT-ROW-CELL !
   u i f 1+ UT-ROW-CELL !
   a u UT-ARENA+ ;

\ the row being written, which no worker reads until UT-ANSWER-CLOSE
: UT-NEXT-ROW ( -- n ) UT-ROW-N atomic@ ;

\ a row for route r ru: a request whose key is k ku, or any request when
\ k ku is empty, gets status st and the body UT-BODY+ and UT-BODY-FILL
\ append; status 0 closes the connection without an answer
: UT-ANSWER-OPEN ( ^u8 n ^u8 n n -- ) {: r ru k ku st :}
   UT-NEXT-ROW {: i :}
   i UT-ROW-MAX >= if E-SW-CAPACITY throw then
   r ru i UT-F-ROUTE UT-FIELD!
   k ku i UT-F-KEY UT-FIELD!
   st i UT-F-STATUS UT-ROW-CELL !
   UT-ARENA 0 i UT-F-FILE UT-FIELD!
   UT-ARENA 0 i UT-F-BYTES UT-FIELD!
   UT-ARENA 0 i UT-F-BODY UT-FIELD! ;

: UT-BODY+ ( ^u8 n -- ) {: a u :}
   a u UT-ARENA+
   u UT-NEXT-ROW UT-F-BODY 1+ UT-ROW-CELL +! ;

\ byte c, n times
: UT-BODY-FILL ( n n -- ) {: c n :}
   n UT-ARENA-ROOM
   n 0 ?do c UT-ARENA UT-ARENA-U @ + i + c! loop
   n UT-ARENA-U +!
   n UT-NEXT-ROW UT-F-BODY 1+ UT-ROW-CELL +! ;

: UT-ANSWER-CLOSE ( -- ) UT-NEXT-ROW 1+ UT-ROW-N atomic! ;

\ closes the row being written, which replaces file f fu with b bu before it answers
: UT-ANSWER-CLOSE-WRITING ( ^u8 n ^u8 n -- ) {: f fu b bu :}
   f fu UT-NEXT-ROW UT-F-FILE UT-FIELD!
   b bu UT-NEXT-ROW UT-F-BYTES UT-FIELD!
   UT-ANSWER-CLOSE ;

\ route r ru answers a request keyed k ku with status st and body b bu
: UT-ANSWER ( ^u8 n ^u8 n n ^u8 n -- ) {: r ru k ku st b bu :}
   r ru k ku st UT-ANSWER-OPEN
   b bu UT-BODY+
   UT-ANSWER-CLOSE ;

\ no rows: every request is answered 404
: UT-ANSWERS-RESET ( -- ) 0 UT-ROW-N atomic! 0 UT-ARENA-U ! ;

: UT-LOG+ ( ^u8 n -- ) {: a u :}
   UT-LOG-PATH UT-LOG-PATH-U @ a u FS:APPEND-FILE ;

: UT-LOG-END ( -- ) s\" \n" UT-LOG+ ;

: UT-UA-LOG ( HTTP:request -- )
   s" User-Agent" HTTP:HEADER-OF$ drop {: v vu :}
   s" ua User-Agent: " UT-LOG+ v vu UT-LOG+ UT-LOG-END ;

: UT-ACCOUNT-LOG ( HTTP:request -- )
   s" ChatGPT-Account-Id" HTTP:HEADER-OF$ 0= if 2drop exit then
   {: v vu :}
   s" ChatGPT-Account-Id: " UT-LOG+ v vu UT-LOG+ UT-LOG-END ;

: UT-BODY-LOG ( HTTP:request -- )
   HTTP:BODY$ {: b bu :}
   bu 0= if exit then
   s" body " UT-LOG+ b bu UT-LOG+ UT-LOG-END ;

: UT-AUTH-LOG ( HTTP:request -- )
   s" Authorization" HTTP:HEADER-OF$ 0= if 2drop exit then
   {: v vu :}
   s" Authorization: " UT-LOG+ v vu UT-LOG+ ;

\ the URL kiba wrote, then the Authorization line it sent, if any
: UT-URL-LOG ( HTTP:request -- ) {: q:HTTP:request :}
   q HTTP:PATH$ {: p pu :}
   s" https://" UT-LOG+ p 1+ pu 1- UT-LOG+
   q HTTP:QUERY$ {: a u :}
   u 0 > if s" ?" UT-LOG+ a u UT-LOG+ then
   s"  " UT-LOG+
   q UT-AUTH-LOG
   UT-LOG-END ;

: UT-TURN-FILE$ ( n -- ^u8 n )
   P-CLAUDE = if UT-CLAUDE-TURN UT-CLAUDE-TURN-U @ exit then
   UT-CODEX-TURN UT-CODEX-TURN-U @ ;

\ flock locks belong to the open file description, so a fresh open of the
\ turn file cannot lock it while a command holds the turn
: UT-TURN-STATE$ ( n -- ^u8 n )
   UT-TURN-FILE$ FS:>PATHZ open-rd {: fd :}
   fd 0 < if s" unknown" exit then
   fd >FD FS-LOCK:TRY {: got :}
   fd close
   got if s" free" exit then
   s" held" ;

: UT-TURN-LOG ( n -- )
   s" turn " UT-LOG+ UT-TURN-STATE$ UT-LOG+ s"  request" UT-LOG+ UT-LOG-END ;

\ what a request to provider p carried, one line each
: UT-SEEN ( HTTP:request n -- ) {: q:HTTP:request p :}
   q UT-UA-LOG
   q UT-ACCOUNT-LOG
   q UT-BODY-LOG
   q UT-URL-LOG
   p UT-TURN-LOG ;

: UT-BEARER$ ( HTTP:request -- ^u8 n )
   s" Authorization" HTTP:HEADER-OF$ 0= if drop 0 exit then
   {: v vu :}
   s" Bearer " nip {: n :}
   vu n < if v 0 exit then
   v n + vu n - ;

: UT-GRANT-KEY$ ( -- ^u8 n ) s\" \"refresh_token\":\"" ;

\ b bu up to its first quote
: UT-TO-QUOTE ( ^u8 n -- ^u8 n ) {: b bu :}
   b bu s\" \"" FIND-SUB MATCH option
      none OF b bu ENDOF
      some OF IDX>N b swap ENDOF
   ;MATCH ;

\ the refresh token a grant body names; empty when it names none
: UT-REFRESH$ ( ^u8 n -- ^u8 n ) {: b bu :}
   b bu UT-GRANT-KEY$ FIND-SUB MATCH option
      none OF b 0 ENDOF
      some OF IDX>N UT-GRANT-KEY$ nip + {: at :} b at + bu at - UT-TO-QUOTE ENDOF
   ;MATCH ;

\ key k ku takes a request when it is empty, the request's bearer token t tu
\ or the refresh token g gu it posts
: UT-KEY? ( ^u8 n ^u8 n ^u8 n -- bool ) {: k ku t tu g gu :}
   ku 0= if true exit then
   k ku t tu STR= if true exit then
   k ku g gu STR= ;

\ the newest row for route r ru whose key takes the request; -1 when none does
: UT-FIND ( ^u8 n ^u8 n ^u8 n -- n ) {: r ru t tu g gu :}
   UT-ROW-N atomic@ {: n :}
   n 0 ?do
      n 1- i - dup UT-F-ROUTE UT-ROW$ r ru STR=
      over UT-F-KEY UT-ROW$ t tu g gu UT-KEY? and
      if unloop exit then
      drop
   loop
   -1 ;

: UT-REPLY ( HTTP:request HTTP:response n -- )
   {: q:HTTP:request a:HTTP:response i :}
   i 0 < if a 404 HTTP:STATUS! exit then
   i UT-F-STATUS UT-ROW-CELL @ {: st :}
   st 0= if q HTTP:TAKE-OVER 2drop TCP4:CLOSE drop exit then
   a st HTTP:STATUS!
   a s" Content-Type" s" application/json" HTTP:HEADER!
   a i UT-F-BODY UT-ROW$ HTTP:BODY! ;

\ row i's file, when it names one, replaced before the answer
: UT-ROW-WRITE ( n -- ) {: i :}
   i 0 < if exit then
   i UT-F-FILE UT-ROW$ {: f fu :}
   fu 0= if exit then
   f fu i UT-F-BYTES UT-ROW$ FS:WRITE-ALL ;

\ a request to route r ru of provider p: logged, then answered from the rows
: UT-SERVE ( HTTP:request HTTP:response ^u8 n n -- )
   {: q:HTTP:request a:HTTP:response r ru p :}
   q p UT-SEEN
   r ru q UT-BEARER$ q HTTP:BODY$ UT-REFRESH$ UT-FIND {: i :}
   i UT-ROW-WRITE
   q a i UT-REPLY ;

: UT-CLAUDE-USAGE$ ( -- ^u8 n ) s" /api.anthropic.com/api/oauth/usage" ;
: UT-CLAUDE-PROFILE$ ( -- ^u8 n ) s" /api.anthropic.com/api/oauth/profile" ;
: UT-CLAUDE-TOKEN$ ( -- ^u8 n ) s" /platform.claude.com/v1/oauth/token" ;
: UT-CLAUDE-RESET$ ( -- ^u8 n )
   s" /api.anthropic.com/api/organizations/{org}/reset_rate_limits" ;
: UT-CODEX-USAGE$ ( -- ^u8 n ) s" /chatgpt.com/backend-api/wham/usage" ;
: UT-CODEX-CONSUME$ ( -- ^u8 n )
   s" /chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume" ;
: UT-CODEX-CREDITS$ ( -- ^u8 n )
   s" /chatgpt.com/backend-api/wham/rate-limit-reset-credits" ;
: UT-CODEX-TOKEN$ ( -- ^u8 n ) s" /auth.openai.com/oauth/token" ;

: UT-ROUTES ( -- )
   HTTP:ROUTES-RESET
   s" GET" UT-CLAUDE-USAGE$
   [: UT-CLAUDE-USAGE$ P-CLAUDE UT-SERVE ;] HTTP:ROUTE
   s" GET" UT-CLAUDE-PROFILE$
   [: UT-CLAUDE-PROFILE$ P-CLAUDE UT-SERVE ;] HTTP:ROUTE
   s" POST" UT-CLAUDE-TOKEN$
   [: UT-CLAUDE-TOKEN$ P-CLAUDE UT-SERVE ;] HTTP:ROUTE
   s" POST" UT-CLAUDE-RESET$
   [: UT-CLAUDE-RESET$ P-CLAUDE UT-SERVE ;] HTTP:ROUTE
   s" GET" UT-CODEX-USAGE$
   [: UT-CODEX-USAGE$ P-CODEX UT-SERVE ;] HTTP:ROUTE
   s" GET" UT-CODEX-CREDITS$
   [: UT-CODEX-CREDITS$ P-CODEX UT-SERVE ;] HTTP:ROUTE
   s" POST" UT-CODEX-CONSUME$
   [: UT-CODEX-CONSUME$ P-CODEX UT-SERVE ;] HTTP:ROUTE
   s" POST" UT-CODEX-TOKEN$
   [: UT-CODEX-TOKEN$ P-CODEX UT-SERVE ;] HTTP:ROUTE ;

: UT-TURN-PATH! ( n ^u8 ^n -- ) {: p buf up :}
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /turn-" SB-APPEND p PROVIDER$ SB-APPEND
   SB$ buf up PATH! ;

\ the paths a worker writes and locks are fixed before it runs
: UT-SERVE-START ( -- )
   UT-ARENA-CAP MEM-ALLOC-BYTES drop UT-ARENA-A !
   LOG$ UT-LOG-PATH UT-LOG-PATH-U PATH!
   P-CLAUDE UT-CLAUDE-TURN UT-CLAUDE-TURN-U UT-TURN-PATH!
   P-CODEX UT-CODEX-TURN UT-CODEX-TURN-U UT-TURN-PATH!
   UT-ANSWERS-RESET
   AIO:START
   UT-ROUTES
   UT-LOOPBACK 0 UT-WORKERS UT-IDLE-MS HTTP:START
   SB-RESET s" http://127.0.0.1:" SB-APPEND HTTP:PORT FMT:SB-U
   [char] / SB-APPEND-C SB$ UT-SERVE-AT ;

: UT-SERVE-STOP ( -- ) HTTP:STOP AIO:STOP ;

\ a Claude reset keyed k ku answers word w wu
: UT-RESULT ( ^u8 n ^u8 n -- ) {: k ku w wu :}
   UT-CLAUDE-RESET$ k ku 200 UT-ANSWER-OPEN
   s\" {\"result\":\"" UT-BODY+ w wu UT-BODY+ s\" \"}" UT-BODY+
   UT-ANSWER-CLOSE ;

: UT-CLAUDE-ANSWERS ( -- )
   UT-CLAUDE-USAGE$ s" " 401 s\" {\"error\":\"expired\"}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-a" 200 s\" {\"five_hour\":{\"utilization\":56.25,\"resets_at\":\"2026-09-15T14:00:00+00:00\"},\"seven_day\":{\"utilization\":100,\"resets_at\":\"2026-09-21T11:00:00+00:00\"},\"limits\":[{\"kind\":\"session\",\"group\":\"session\",\"scope\":null,\"percent\":56},{\"kind\":\"weekly_scoped\",\"group\":\"weekly\",\"scope\":{\"model\":{\"id\":null,\"display_name\":\"Fable\"},\"surface\":null},\"percent\":48,\"resets_at\":\"2026-09-22T13:00:00+00:00\"}]}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-b-new" 200 s\" {\"five_hour\":{\"utilization\":12.4,\"resets_at\":\"2026-09-15T15:00:00+00:00\"},\"seven_day_oauth_apps\":{\"utilization\":0.5,\"resets_at\":\"\"}}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" " 200 s\" {\"access_token\":\"sk-b-new\",\"refresh_token\":\"r-b-new\",\"expires_in\":3600,\"refresh_token_expires_in\":2592000}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" r-e" 429 s\" {\"error\":{\"type\":\"rate_limit_error\"}}" UT-ANSWER
   s" " s" reset" UT-RESULT
   UT-CLAUDE-RESET$ s" sk-a" 401 s\" {\"error\":\"expired\"}" UT-ANSWER
   UT-CLAUDE-RESET$ s" sk-s" 401 s\" {\"error\":\"expired\"}" UT-ANSWER ;

: UT-CODEX-USAGE-ANSWERS ( -- )
   UT-CODEX-USAGE$ s" " 401 s\" {\"error\":{\"code\":\"token_expired\"}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-c" 200 s\" {\"plan_type\":\"pro\",\"rate_limit\":{\"allowed\":false,\"limit_reached\":true,\"primary_window\":{\"used_percent\":100,\"limit_window_seconds\":604800,\"reset_after_seconds\":433078,\"reset_at\":1789904220},\"secondary_window\":null}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-d2" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000,\"reset_at\":1789489142},\"secondary_window\":{\"used_percent\":40,\"limit_window_seconds\":604800,\"reset_at\":1790075942}}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-dup" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":18000,\"used_percent\":20}}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-whole" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":30,\"limit_window_seconds\":6048e2,\"reset_at\":1789904220.0}},\"rate_limit_reset_credits\":{\"available_count\":2.0}}" UT-ANSWER
   UT-CODEX-CREDITS$ s" at-whole" 200 s\" {\"credits\":[{\"id\":\"c1\",\"status\":\"redeeming\",\"expires_at\":\"2026-11-20T00:00:00Z\"},{\"id\":\"c2\",\"status\":\"available\",\"expires_at\":\"2026-11-24T14:00:00Z\"},{\"expires_at\":\"2026-11-24T15:00:00+02:00\",\"id\":\"c3\",\"status\":\"available\"},{\"id\":\"c4\",\"status\":\"available\",\"expires_at\":null},\"x\",{\"id\":\"c5\",\"status\":\"available\",\"expires_at\":\"soon\"}],\"available_count\":4}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-nolist" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":604800,\"reset_at\":1789904220}},\"rate_limit_reset_credits\":{\"available_count\":1}}" UT-ANSWER
   UT-CODEX-CREDITS$ s" at-nolist" 500 s\" {\"credits\":[{\"id\":\"c\",\"status\":\"available\",\"expires_at\":\"2026-11-24T14:00:00Z\"}],\"available_count\":1}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-html" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":604800,\"reset_at\":1789904220}},\"rate_limit_reset_credits\":{\"available_count\":1}}" UT-ANSWER
   UT-CODEX-CREDITS$ s" at-html" 200 s" <html>" UT-ANSWER
   UT-CODEX-USAGE$ s" at-none" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":604800,\"reset_at\":1789904220}},\"rate_limit_reset_credits\":{\"available_count\":0}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-long" 200 s\" {\"plan_type\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\",\"rate_limit\":{\"primary_window\":{\"used_percent\":30,\"limit_window_seconds\":18000}}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-z" 401 s\" {\"error\":{\"code\":\"token_revoked\"}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-y" 401 s\" {\"error\":{\"code\":\"token_revoked\"}}" UT-ANSWER ;

: UT-CODEX-ANSWERS ( -- )
   UT-CODEX-USAGE-ANSWERS
   UT-CODEX-TOKEN$ s" " 200 s\" {\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d2\",\"refresh_token\":\"rt-d2\"}" UT-ANSWER
   UT-CODEX-TOKEN$ s" rt-z" 401 s\" {\"error\":\"invalid_grant\"}" UT-ANSWER
   UT-CODEX-TOKEN$ s" rt-y" 503 s" " UT-ANSWER
   UT-CODEX-CONSUME$ s" " 401 s\" {\"error\":{\"code\":\"token_expired\"}}" UT-ANSWER
   UT-CODEX-CONSUME$ s" at-d2" 200 s\" {\"code\":\"reset\"}" UT-ANSWER
   UT-CODEX-CONSUME$ s" at-z" 401 s\" {\"error\":{\"code\":\"token_revoked\"}}" UT-ANSWER ;

\ the shared answers: each endpoint by the bearer token or the refresh token
\ it is sent; an unknown token's usage call is rejected, an unknown grant
\ renewed to sk-b-new or at-d2, and a Claude reset answers "reset"
: UT-ANSWERS-DEFAULT ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-ANSWERS
   UT-CODEX-ANSWERS ;

\ ---- usage on the store ------------------------------------------------------
create UT-ERR-PATH 256 allot   variable UT-ERR-U

\ the file a usage run's stderr is captured in, under the scratch HOME
: UT-ERR$ ( -- ^u8 n ) UT-ERR-PATH UT-ERR-U @ ;

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
: UT-ID ( ^u8 n ^u8 n -- ) {: a u o ou :}
   SB-RESET s\" {\"emailAddress\":\"" SB-APPEND a u SB-APPEND [char] " SB-APPEND-C
   ou 0 > if s\" ,\"organizationUuid\":\"" SB-APPEND o ou SB-APPEND [char] " SB-APPEND-C then
   [char] } SB-APPEND-C
   SB$ ID-SLOT CLAUDE-OAUTH-IDENTITY ;

: UT-PUT-RAW ( n ^u8 n ^u8 n -- ) {: p a u l lu :}
   [: p a u ID-SLOT l lu UT-BUF -1 false DB-PUT ;] DB-WRITE ;

\ the row p a u holding login l lu, for email a u in organization o ou
: UT-PUT-ORG ( n ^u8 n ^u8 n ^u8 n -- ) {: p a u o ou l lu :}
   a u o ou UT-ID
   [: p a u l lu UT-PUT-RAW ;] UT-STORE ;

: UT-PUT ( n ^u8 n ^u8 n -- ) {: p a u l lu :}
   p a u s" " l lu UT-PUT-ORG ;

: UT-RECORD-KEEP ( n ^u8 n -- ) DB-FETCH TTRUE 0 DB-ROW-USAGE TTRUE ;

\ row p a u's usage record, in the record readers
: UT-RECORD ( n ^u8 n -- ) {: p a u :}
   [: p a u UT-RECORD-KEEP ;] UT-STORE ;

: UT-STATE= ( ^u8 n -- ) {: a u :}
   DB-USAGE-STATE DB-STATE$ a u T$= ;

\ usage answers with readings to round, chosen by the bearer token
: UT-ROUNDING-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-USAGE$ s" sk-r1" 200 s\" {\"five_hour\":{\"utilization\":12.495},\"seven_day_oauth_apps\":{\"utilization\":12.5},\"limits\":[{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"A\"}},\"percent\":12.495},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"B\"}},\"percent\":12.5},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"C\"}},\"percent\":0},{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"D\"}},\"percent\":-0.5}]}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-r2" 200 s\" {\"five_hour\":{\"utilization\":0},\"seven_day_oauth_apps\":{\"utilization\":-1},\"seven_day\":{\"utilization\":-0.4}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-r1" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":12.495,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":12.5,\"limit_window_seconds\":604800}}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-r2" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":0,\"limit_window_seconds\":18000},\"secondary_window\":{\"used_percent\":-2,\"limit_window_seconds\":604800}}}" UT-ANSWER ;

: UT-LIMIT= ( n ^u8 n n -- ) {: i a u pct :}
   i DB-LIMIT-LABEL$ a u T$=
   i DB-LIMIT-PERCENT pct T= ;

\ every caller rounds its reading once; a negative one leaves its window out
: UT-PCT-CALLERS ( -- )
   UT-ROUNDING-ROWS
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

\ a usage answer that lists entries that are not objects, then one with a
\ 65-byte model name and a 40-byte kind
: UT-SCOPED-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-USAGE$ s" " 200 s\" {\"limits\":[1,\"x\",null,[{\"kind\":\"weekly\"}],{\"kind\":\"weekly_scoped_kkkkkkkkkkkkkkkkkkkkkkkkkk\",\"scope\":{\"model\":{\"display_name\":\"ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}},\"percent\":7,\"resets_at\":\"2026-09-22T13:00:00+00:00\"}]}" UT-ANSWER ;

\ a non-object entry is skipped, and a long name and kind read whole
: UT-SCOPED-LONG ( -- )
   UT-SCOPED-ROWS
   P-CLAUDE s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-s1\"}}" false PROBE
   s" ok" UT-STATE= DB-LIMIT# 1 T=
   0 s" ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd Weekly" 7 UT-LIMIT=
   0 DB-LIMIT-RESETS$ s" 2026-09-22T13:00:00+00:00" T$= ;

\ a Codex usage answer with one window, whatever the token
: UT-LONG-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CODEX-USAGE$ s" " 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":12,\"limit_window_seconds\":18000}}}" UT-ANSWER ;

16384 constant UT-LONG-CAP   \ the login and both header lines it sends
create UT-LONG UT-LONG-CAP allot   variable UT-LONG-U

: UT-LONG-ROOM ( n -- )
   UT-LONG-U @ + UT-LONG-CAP > if E-SW-CAPACITY throw then ;

: UT-LONG+ ( ^u8 n -- ) {: a u :}
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
: UT-LONG$ ( n -- ^u8 n ) {: o :}
   UT-LONG o + UT-LONG-U @ o - ;

\ a 5000-byte access token and a 200-byte account id
: UT-TOK+ ( -- ) s" at-" UT-LONG+ [char] k 4997 UT-LONG-FILL ;
: UT-ACCT+ ( -- ) s" acct-" UT-LONG+ [char] q 195 UT-LONG-FILL ;

\ a token and an account id are read whole and sent whole
: UT-LONG-TOKEN ( -- )
   UT-LONG-ROWS
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

: UT-PLAN= ( n ^u8 n ^u8 n -- ) {: p a u l lu :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-PLAN$ l lu T$= ;] UT-STORE ;

: UT-ROW-LOGIN ( n ^u8 n [ ^u8 n -- ] -- ) {: p a u check :}
   [: p a u DB-FETCH TTRUE 0 DB-ROW-LOGIN$ check execute ;] UT-STORE ;

\ row p a u's record replaced by an ok one fetched at epoch second at
: UT-SET-AT ( n ^u8 n n -- ) {: p a u at :}
   SB-RESET s\" {\"fetchedAt\":" SB-APPEND at FMT:SB-U
   s\" ,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" SB-APPEND SB$ DB-USAGE-DECODE
   DB-USAGE-AT at T=
   [: [: p a u UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE ;

1 constant UT-OLD-AT                  \ a fetchedAt every probe moves past

\ row p a u's record fetched at UT-OLD-AT, so a probe shows in it
: UT-AGE ( n ^u8 n -- ) UT-OLD-AT UT-SET-AT ;

\ whether a probe recorded row p a u's outcome since UT-AGE
: UT-PROBED? ( n ^u8 n -- bool ) UT-RECORD DB-USAGE-AT UT-OLD-AT > ;

\ a limit under label l lu, k percent used, with no reset instant
: UT-WINDOW+ ( ^u8 n n -- ) {: l lu k :}
   s\" {\"label\":\"" SB-APPEND l lu SB-APPEND
   s\" \",\"percent\":" SB-APPEND k FMT:SB-U
   s\" ,\"resetsAt\":\"\"}" SB-APPEND ;

\ row p a u's record replaced by one in state s su fetched at UT-OLD-AT,
\ its session se and its week we percent used
: UT-SET-USED ( n ^u8 n ^u8 n n n -- ) {: p a u s su se we :}
   SB-RESET s\" {\"fetchedAt\":" SB-APPEND UT-OLD-AT FMT:SB-U
   s\" ,\"limits\":[" SB-APPEND s" Session (5-hour)" se UT-WINDOW+
   [char] , SB-APPEND-C s" Weekly (7-day)" we UT-WINDOW+
   s\" ],\"note\":\"\",\"state\":\"" SB-APPEND s su SB-APPEND
   s\" \"}" SB-APPEND SB$ DB-USAGE-DECODE
   s su UT-STATE= DB-LIMIT# 2 T=
   [: [: p a u UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE ;

\ row p a u's last reading had room, little room, none, or its login was gone
: UT-SET-FINE ( n ^u8 n -- ) s" ok" 10 20 UT-SET-USED ;
: UT-SET-TIGHT ( n ^u8 n -- ) s" ok" 60 20 UT-SET-USED ;
: UT-SET-BLOCKED ( n ^u8 n -- ) s" ok" 100 20 UT-SET-USED ;
: UT-SET-DEAD ( n ^u8 n -- ) s" revoked" 0 0 UT-SET-USED ;

\ a@x.test is Claude's one saved login
: UT-CLAUDE-ONLY-A ( -- )
   [: P-CLAUDE DB-LIST DB-ROW# 1 T=
      0 DB-ROW-NAME$ s" a@x.test" T$= ;] UT-STORE ;

: UT-USAGE-CLAUDE ( -- )
   P-CLAUDE s" a@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 3 T=
   0 DB-LIMIT-LABEL$ s" Session (5-hour)" T$=
   0 DB-LIMIT-PERCENT 56 T=
   0 DB-LIMIT-RESETS$ s" 2026-09-15T14:00:00+00:00" T$=
   1 DB-LIMIT-PERCENT 100 T=
   1 DB-LIMIT-RESETS$ s" 2026-09-21T11:00:00+00:00" T$=
   2 DB-LIMIT-LABEL$ s" Fable Weekly" T$=
   2 DB-LIMIT-PERCENT 48 T=
   2 DB-LIMIT-RESETS$ s" 2026-09-22T13:00:00+00:00" T$=
   DB-USAGE-AT 0 > TTRUE
   DB-RESETS? TFALSE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" a@x.test" CREDS-A$ UT-LOGIN=
   P-CLAUDE s" b@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 2 T=
   0 DB-LIMIT-PERCENT 12 T=
   1 DB-LIMIT-PERCENT 1 T=
   1 DB-LIMIT-LABEL$ s" Weekly (7-day)" T$=
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
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 2 T=
   0 DB-LIMIT-LABEL$ s" Session (5-hour)" T$=
   0 DB-LIMIT-PERCENT 12 T=
   1 DB-LIMIT-PERCENT 40 T=
   P-CODEX s" y@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" OpenAI's token endpoint answered 503" T$=
   P-CODEX s" y@x.test" AUTH-Y$ UT-LOGIN= ;

\ each request names its endpoint, its token and its client
: UT-USAGE-LOG ( -- )
   LOG$ READ-FILE$ {: l lu :}
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" https://api.anthropic.com/api/oauth/usage?cedar_ember=1&at_wall=1" CONTAINS? TTRUE
   l lu s" https://auth.openai.com/oauth/token" CONTAINS? TTRUE
   l lu s" Authorization: Bearer sk-a" CONTAINS? TTRUE
   l lu s" Authorization: Bearer at-y" CONTAINS? TTRUE
   l lu s" ua User-Agent: kiba" CONTAINS? TTRUE
   l lu s" ua User-Agent: codex-cli" CONTAINS? TTRUE
   l lu s" ua User-Agent: claude-cli/2.1.282 (external, cli)" CONTAINS? TTRUE ;

\ a saved Claude login whose access token has expired
: CREDS-T$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-t\",\"refreshToken\":\"r-t\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"max\"}}" ;

\ any Claude grant renewed to sk-t-new, whose usage call is answered with a
\ body one byte past BUF-CAP; every other usage call gets {}
: UT-RENEW-THROW-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-TOKEN$ s" " 200 s\" {\"access_token\":\"sk-t-new\",\"refresh_token\":\"r-t-new\",\"expires_in\":3600}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" " 200 s" {}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-t-new" 200 UT-ANSWER-OPEN
   STR-SPACE 4194305 UT-BODY-FILL
   UT-ANSWER-CLOSE ;

: UT-RENEWED-T ( ^u8 n -- ) {: c cu :}
   c cu CHECK-OBJECT
   c cu s\" \"accessToken\":\"sk-t-new\"" CONTAINS? TTRUE
   c cu s\" \"refreshToken\":\"r-t-new\"" CONTAINS? TTRUE
   c cu s\" \"expiresAt\":2," CONTAINS? TFALSE ;

\ a probe that throws after renewing the token records its error and keeps
\ the renewed login in the row
: UT-RENEWED-THROWS ( -- )
   UT-RENEW-THROW-ROWS
   P-CLAUDE s" t@x.test" CREDS-T$ UT-PUT
   P-CLAUDE CMD-USAGE
   P-CLAUDE s" t@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" too many: bytes in a JSON document (limit 4 MiB)" T$=
   P-CLAUDE s" t@x.test" [: UT-RENEWED-T ;] UT-ROW-LOGIN
   P-CLAUDE s" t@x.test" CMD-FORGET ;

\ ---- stdout that refuses every write -----------------------------------------
10 constant UT-SAVE-FD-MIN          \ the saved stdout lands clear of 0..2

: UT-OPEN-FULL ( -- n )
   s" /dev/full" FS:>PATHZ FS:O-WRONLY 0 open {: fd :}
   fd 0 < if E-FS-OPEN throw then
   fd ;

\ fd 1 back from saved, which is then closed
: UT-STDOUT-BACK ( n -- ) {: saved :}
   saved FD:STDOUT FD>N dup2 FD:STDOUT FD>N T=
   saved close-rc 0 T= ;

\ the throw code of the action run with fd 1 on /dev/full, which refuses every
\ write; the checks wait until fd 1 is back, so a failure's report is seen
: UT-FULL-STDOUT ( [ -- ] -- n ) {: act :}
   UT-OPEN-FULL {: full :}
   FD:STDOUT FD>N FD:F-DUPFD-CLOEXEC UT-SAVE-FD-MIN fcntl {: saved :}
   saved 0 < if full close-rc 0 T= E-FS-IO throw then
   full FD:STDOUT FD>N dup2 {: on :}
   full close-rc {: shut :}
   on FD:STDOUT FD>N = if [: act execute ;] catch else 0 then {: rc :}
   saved UT-STDOUT-BACK
   on FD:STDOUT FD>N T=
   shut 0 T=
   rc ;

: UT-OUTPUT-REFUSED-RUN ( -- )
   [: P-CLAUDE CMD-USAGE ;] UT-FULL-STDOUT E-SW-OUTPUT T=
   [: -1 CMD-USAGE ;] UT-FULL-STDOUT E-SW-OUTPUT T=
   [: false CMD-STATUS ;] UT-FULL-STDOUT E-SW-OUTPUT T= ;

\ stdout refusing the report fails the whole run, never one provider: usage
\ for one provider or every one, and status. With the live Claude files
\ mixed, stderr still gets the save-back fault each usage run collected
: UT-OUTPUT-REFUSED ( -- )
   P-CLAUDE s" t@x.test" CREDS-T$ UT-PUT
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   UT-ERR-PATH!
   UT-ERR$ STDERR:CAPTURE
   [: UT-OUTPUT-REFUSED-RUN ;] [: STDERR:;CAPTURE ;] finally
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: the live Claude files name different accounts; switch to an account to repair them\nclaude: live login not saved: the live Claude files name different accounts; switch to an account to repair them\n" T$=
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   P-CLAUDE s" t@x.test" CMD-FORGET ;

\ the action's stdout, run in this process
: UT-CAPTURE$ ( [ -- ] -- ^u8 n ) {: act :}
   act s" HOME" GETENV [: GT-OUT-ROOM ;] [: GT-ERR-ROOM ;]
   GT-CAPTURE-ACTION {: outu:len erru:len rc:n :}
   rc 0 T=
   outu LEN>N GT-OUT-U !
   GT-OUT$ ;

\ usage gives what is left, as status does: a used-up week leaves Claude's
\ session nothing, and an account with no reading gives its note
: UT-USAGE-TEXT ( ^u8 n -- ) {: o ou :}
   o ou s\" claude: a@x.test  Session (5-hour) 0% left · Weekly (7-day) 0% left · Fable Weekly 52% left\n" CONTAINS? TTRUE
   o ou s\" claude: e@x.test  Anthropic's token endpoint answered 429\n" CONTAINS? TTRUE
   o ou s\" codex: c@x.test  Weekly (7-day) 0% left\n" CONTAINS? TTRUE
   o ou s\" codex: d@x.test  Session (5-hour) 88% left · Weekly (7-day) 60% left\n" CONTAINS? TTRUE ;

\ each saved login UT-USAGE probes, every one there is
: UT-USAGE-ROWS ( [ n ^u8 n -- ] -- ) {: each :}
   [: P-CLAUDE DB-LIST DB-ROW# 4 T= P-CODEX DB-LIST DB-ROW# 3 T= ;] UT-STORE
   P-CLAUDE s" a@x.test" each execute
   P-CLAUDE s" b@x.test" each execute
   P-CLAUDE s" e@x.test" each execute
   P-CLAUDE s" f@x.test" each execute
   P-CODEX s" c@x.test" each execute
   P-CODEX s" d@x.test" each execute
   P-CODEX s" y@x.test" each execute ;

\ live claude a@x.test (sk-a) and codex c@x.test, saved back first; saved
\ b@x.test refreshes its expired token, e@x.test's refresh is rate limited
\ (an error, not a dead login), f@x.test has no refresh token; saved
\ d@x.test refreshes after a 401, y@x.test's refresh meets a 503. Each
\ account's error stays its own: the command succeeds.
: UT-USAGE ( -- )
   UT-ANSWERS-DEFAULT
   P-CLAUDE s" b@x.test" CREDS-B$ UT-PUT
   P-CLAUDE s" e@x.test" CREDS-E$ UT-PUT
   P-CLAUDE s" f@x.test" CREDS-F$ UT-PUT
   P-CODEX s" y@x.test" AUTH-Y$ UT-PUT
   [: UT-AGE ;] UT-USAGE-ROWS
   [: -1 CMD-USAGE ;] UT-CAPTURE$ UT-USAGE-TEXT
   [: UT-PROBED? TTRUE ;] UT-USAGE-ROWS
   UT-USAGE-CLAUDE
   UT-USAGE-CODEX
   UT-USAGE-LOG
   P-CLAUDE s" e@x.test" CMD-FORGET
   P-CLAUDE s" f@x.test" CMD-FORGET
   P-CODEX s" y@x.test" CMD-FORGET ;

: UT-RENEWED-B ( ^u8 n -- ) {: c cu :}
   c cu CHECK-OBJECT
   c cu s\" \"accessToken\":\"sk-b-new\"" CONTAINS? TTRUE
   c cu s\" \"refreshToken\":\"r-b-new\"" CONTAINS? TTRUE
   c cu s\" \"expiresAt\":2," CONTAINS? TFALSE
   c cu s\" \"refreshTokenExpiresAt\":1," CONTAINS? TFALSE
   c cu s\" \"refreshTokenExpiresAt\":" CONTAINS? TTRUE
   c cu s\" \"subscriptionType\":\"pro\"" CONTAINS? TTRUE ;

: UT-RENEWED-D ( ^u8 n -- ) {: d du :}
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

\ row a u holding the Codex login whose access token is at-<t>
: UT-PUT-AT ( ^u8 n ^u8 n -- ) {: a u t tu :}
   P-CODEX a u t tu AUTH-AT$ UT-PUT ;

\ an answer that repeats a key in a nested object is not a JSON object
: UT-ANSWER-REPEATS ( -- )
   P-CODEX s" dup@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" OpenAI's usage endpoint sent an answer that is not a JSON object" T$=
   DB-LIMIT# 0 T= ;

\ integers spelled 6048e2, 1789904220.0 and 2.0 read as those integers; the
\ expiry is the earliest available credit's as an instant, so c3 wins over
\ c2, which is earlier as text, and c1 does not count: it is redeeming
: UT-ANSWER-WHOLE ( -- )
   P-CODEX s" whole@x.test" UT-RECORD s" ok" UT-STATE=
   DB-LIMIT# 1 T=
   0 DB-LIMIT-LABEL$ s" Weekly (7-day)" T$=
   0 DB-LIMIT-PERCENT 30 T=
   0 DB-LIMIT-RESETS$ s" 2026-09-20T11:37:00Z" T$=
   DB-RESETS? TTRUE
   DB-RESETS-EXPIRY$ s" 2026-11-24T13:00:00Z" T$= ;

\ a plan longer than PLAN-CAP is the probe's error, never a missing plan
: UT-ANSWER-LONG ( -- )
   P-CODEX s" long@x.test" UT-RECORD s" error" UT-STATE=
   DB-USAGE-NOTE$ s" too many: bytes in a JSON string (limit 64)" T$=
   DB-LIMIT# 0 T= ;

\ a credit list that fails leaves the probe ok, with no expiry and no note
: UT-ANSWER-NO-LIST ( -- )
   P-CODEX s" nolist@x.test" UT-RECORD s" ok" UT-STATE=
   DB-RESETS-COUNT 1 T=
   DB-RESETS-EXPIRY$ s" " T$=
   DB-USAGE-NOTE$ s" " T$= ;

\ with no reset held the credit list is not asked for
: UT-ANSWER-NO-OFFER ( -- )
   P-CODEX s" none@x.test" UT-RECORD s" ok" UT-STATE=
   DB-RESETS? TTRUE
   DB-RESETS-COUNT 0 T=
   DB-RESETS-EXPIRY$ s" " T$= ;

\ a credit list not JSON leaves the probe ok, with no expiry and no note
: UT-ANSWER-HTML-LIST ( -- )
   P-CODEX s" html@x.test" UT-RECORD s" ok" UT-STATE=
   DB-RESETS-COUNT 1 T=
   DB-RESETS-EXPIRY$ s" " T$=
   DB-USAGE-NOTE$ s" " T$= ;

\ provider answers as a Codex usage probe reads them, its credit list included
: UT-ANSWER-READS ( -- )
   s" dup@x.test" s" dup" UT-PUT-AT
   s" whole@x.test" s" whole" UT-PUT-AT
   s" long@x.test" s" long" UT-PUT-AT
   s" nolist@x.test" s" nolist" UT-PUT-AT
   s" none@x.test" s" none" UT-PUT-AT
   s" html@x.test" s" html" UT-PUT-AT
   UT-LOG-MARK
   P-CODEX CMD-USAGE
   UT-LOG-NEW$ {: l lu :}
   l lu s" /rate-limit-reset-credits Authorization: Bearer at-whole" CONTAINS? TTRUE
   l lu s" /rate-limit-reset-credits Authorization: Bearer at-nolist" CONTAINS? TTRUE
   l lu s" /rate-limit-reset-credits Authorization: Bearer at-html" CONTAINS? TTRUE
   l lu s" /rate-limit-reset-credits Authorization: Bearer at-none" CONTAINS? TFALSE
   UT-ANSWER-REPEATS
   UT-ANSWER-WHOLE
   UT-ANSWER-LONG
   UT-ANSWER-NO-LIST
   UT-ANSWER-NO-OFFER
   UT-ANSWER-HTML-LIST
   P-CODEX s" dup@x.test" CMD-FORGET
   P-CODEX s" whole@x.test" CMD-FORGET
   P-CODEX s" long@x.test" CMD-FORGET
   P-CODEX s" nolist@x.test" CMD-FORGET
   P-CODEX s" none@x.test" CMD-FORGET
   P-CODEX s" html@x.test" CMD-FORGET ;

\ a credit list one byte past BUF-CAP leaves the probe ok with no expiry
: UT-CREDITS-TOO-BIG ( -- )
   UT-ANSWERS-RESET
   UT-CODEX-USAGE$ s" at-big" 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":604800,\"reset_at\":1789904220}},\"rate_limit_reset_credits\":{\"available_count\":1}}" UT-ANSWER
   UT-CODEX-CREDITS$ s" at-big" 200 UT-ANSWER-OPEN
   STR-SPACE 4194305 UT-BODY-FILL
   UT-ANSWER-CLOSE
   s" big@x.test" s" big" UT-PUT-AT
   P-CODEX CMD-USAGE
   P-CODEX s" big@x.test" UT-RECORD s" ok" UT-STATE=
   DB-RESETS-COUNT 1 T=
   DB-RESETS-EXPIRY$ s" " T$=
   DB-USAGE-NOTE$ s" " T$=
   P-CODEX s" big@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

\ ---- Claude probe outcomes ----------------------------------------------------
\ the Claude outcomes: the usage and profile calls answer by the bearer
\ token, the token call by the refresh grant; sk-down's usage call meets a
\ connection closed without an answer
: UT-CLAUDE-OUTCOME-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-USAGE$ s" " 200 s" {}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-nop" 403 s\" {\"type\":\"error\",\"error\":{\"type\":\"permission_error\",\"message\":\"OAuth authentication is currently not allowed for this organization.\",\"details\":{\"error_code\":\"oauth_not_allowed_for_organization\"}}}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-paid" 429 s\" {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Number of requests has exceeded your rate limit\"}}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-free" 429 s\" {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Number of requests has exceeded your rate limit\"}}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-rej" 401 s\" {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"Invalid bearer token\"}}" UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-down" 0 s" " UT-ANSWER
   UT-CLAUDE-USAGE$ s" sk-bad" 200 s" [1]" UT-ANSWER
   UT-CLAUDE-PROFILE$ s" " 200 s\" {\"organization\":{\"uuid\":\"org-p\",\"organization_type\":\"claude_max\"}}" UT-ANSWER
   UT-CLAUDE-PROFILE$ s" sk-free" 200 s\" {\"organization\":{\"uuid\":\"org-f\",\"organization_type\":\"claude_free\"}}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" " 200 s" {}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" r-old400" 400 s\" {\"error\":\"invalid_grant\",\"error_description\":\"Refresh token not found or invalid\"}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" r-old401" 401 s\" {\"error\":\"invalid_grant\"}" UT-ANSWER
   UT-CLAUDE-TOKEN$ s" r-hold" 403 s\" {\"error\":\"access_denied\",\"error_description\":\"account_on_hold\",\"error_uri\":\"https://support.anthropic.com/appeal\"}" UT-ANSWER ;

\ expiresAt of a token still good, and of one long expired
: UT-FAR ( -- n ) 4102444800000 ;
: UT-PAST ( -- n ) 2 ;

\ a saved Claude login holding sk-<t> and r-<t>, expiring at epoch
\ millisecond ms
: CREDS-TOKEN$ ( ^u8 n n -- ^u8 n ) {: t tu ms :}
   SB-RESET s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-" SB-APPEND t tu SB-APPEND
   s\" \",\"refreshToken\":\"r-" SB-APPEND t tu SB-APPEND
   s\" \",\"expiresAt\":" SB-APPEND ms FMT:SB-U
   s\" ,\"subscriptionType\":\"max\"}}" SB-APPEND
   SB$ UT-AT-BUF 1024 SPAN-COPY ;

: UT-OUTCOME$ ( -- ^u8 n ) s" o@x.test" ;

\ usage claude over the saved row o@x.test holding CREDS-TOKEN$ t ms; its record
\ is then in the record readers
: UT-CLAUDE-PROBE ( ^u8 n n -- ) {: t tu ms :}
   t tu ms CREDS-TOKEN$ {: l lu :}
   P-CLAUDE UT-OUTCOME$ l lu UT-PUT
   P-CLAUDE CMD-USAGE
   P-CLAUDE UT-OUTCOME$ UT-RECORD ;

\ the record reads state s su and note n nu
: UT-OUTCOME= ( ^u8 n ^u8 n -- ) {: s su n nu :}
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

\ every outcome of a saved Claude login's probe, as its usage record shows
\ it; the shared answers are back afterwards
: UT-CLAUDE-OUTCOMES ( -- )
   UT-CLAUDE-OUTCOME-ROWS
   UT-CLAUDE-NO-PLAN
   UT-CLAUDE-THROTTLED
   UT-CLAUDE-FREE
   UT-CLAUDE-REJECTED
   UT-CLAUDE-REFUSED
   UT-CLAUDE-ON-HOLD
   UT-CLAUDE-UNREACHED
   UT-CLAUDE-UNREADABLE
   UT-ANSWERS-DEFAULT ;

\ the fake `claude` logs its argv and every CLAUDE_CONFIG_DIR row execve gave
\ it, which sh collapses to one, then writes account B into CLAUDE_CONFIG_DIR,
\ or exits 3 when HOME holds fail-login
: UT-FAKE-CLAUDE ( -- )
   s" claude"
   s\" #!/bin/sh\necho \"claude $* cfg=$CLAUDE_CONFIG_DIR\" >> \"$KIBA_TEST_LOG\"\n/usr/bin/tr '\\0' '\\n' < /proc/$$/environ | while IFS= read -r l; do case \"$l\" in CLAUDE_CONFIG_DIR=*) echo \"env $l\";; esac; done >> \"$KIBA_TEST_LOG\"\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nprintf '%s' '{\"oauthAccount\":{\"accountUuid\":\"u2\",\"emailAddress\":\"b@x.test\",\"organizationUuid\":\"org-b\"}}' > \"$CLAUDE_CONFIG_DIR/.claude.json\"\nprintf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"sk-b\",\"refreshToken\":\"r-b\",\"expiresAt\":2,\"scopes\":[\"user:inference\"],\"subscriptionType\":\"pro\"}}' > \"$CLAUDE_CONFIG_DIR/.credentials.json\"\n"
   UT-WRITE-SCRIPT ;

\ `add` logs in inside a throwaway home: the live login stays where it is,
\ the new login is saved under its name, and the home is gone afterwards;
\ the new row is then probed as saved, its 401 renewing its token.
\ the fake `codex` records where it ran and every CODEX_HOME row execve gave
\ it, then writes AUTH-D on success, or nothing when HOME holds empty-login
: UT-FAKE-CODEX ( -- )
   s" codex"
   s\" #!/bin/sh\necho \"codexhome $CODEX_HOME\" >> \"$KIBA_TEST_LOG\"\n/usr/bin/tr '\\0' '\\n' < /proc/$$/environ | while IFS= read -r l; do case \"$l\" in CODEX_HOME=*) echo \"env $l\";; esac; done >> \"$KIBA_TEST_LOG\"\nif [ -e \"$HOME/.codex/auth.json\" ]; then echo present >> \"$KIBA_TEST_LOG\"; else echo absent >> \"$KIBA_TEST_LOG\"; fi\nif [ -e \"$HOME/fail-login\" ]; then exit 3; fi\nif [ -e \"$HOME/empty-login\" ]; then exit 0; fi\nprintf '%s' '{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImRAeC50ZXN0IiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfcGxhbl90eXBlIjoicHJvIiwiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdCJ9LCJleHAiOjF9.c2ln\",\"access_token\":\"at-d\",\"refresh_token\":\"rt-d\",\"account_id\":\"acct\"}}' > \"$CODEX_HOME/auth.json\"\n"
   UT-WRITE-SCRIPT ;

\ HOME's file f, made or removed by the test to steer the fake codex
: UT-HOME-FILE$ ( ^u8 n -- ^u8 n ) {: f fu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND f fu SB-APPEND SB$ UT-BUF 256 SPAN-COPY ;

: UT-CODEX-ROWS ( -- n )
   0 UT-N ! [: P-CODEX DB-LIST DB-ROW# UT-N ! ;] UT-STORE UT-N @ ;

\ where UT-ADD moves the fake codex aside
create UT-OFF-PATH 256 allot

: UT-ADD ( -- )
   UT-FAKE-CODEX
   UT-ANSWERS-DEFAULT
   P-CODEX s" d@x.test" CMD-FORGET
   s" /fail-login" UT-HOME-FILE$ {: f fu :}
   f fu s" x" FS:WRITE-ALL
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   [: P-CODEX s" " CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX LOGIN-HOME$ FS:DIR? TFALSE
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
   P-CODEX s" c@x.test" AUTH-C9$ UT-LOGIN=
   P-CODEX LOGIN-HOME$ FS:DIR? TFALSE
   LOG$ READ-FILE$ {: l lu :}
   l lu s\" present\nua User-Agent: codex-cli" CONTAINS? TTRUE
   l lu s" /login-codex/.codex" CONTAINS? TTRUE
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
   P-CODEX LOGIN-HOME$ FS:DIR? TFALSE
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
   LOG$ READ-FILE$ s" /login-claude/.claude" CONTAINS? TTRUE
   [: UT-CLAUDE-B ;] UT-STORE
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE LOGIN-HOME$ FS:DIR? TFALSE
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   P-CLAUDE s" b@x.test" CMD-FORGET
   P-CLAUDE s" zz@x.test" CMD-ADD
   P-CLAUDE s" zz@x.test" UT-ROW? TFALSE
   [: UT-CLAUDE-B ;] UT-STORE
   P-CLAUDE s" b@x.test" CMD-FORGET ;

\ a Claude add whose login fails leaves save working
: UT-ADD-FAILED ( -- )
   UT-FAKE-CLAUDE
   s" /fail-login" UT-HOME-FILE$ {: f fu :}
   f fu s" x" FS:WRITE-ALL
   [: P-CLAUDE s" " CMD-ADD ;] E-SW-LOGIN TTHROWSQ
   f fu FS:REMOVE-FILE
   P-CLAUDE LIVE-IDENTITY TTRUE ID-LIVE EMAIL$ s" a@x.test" T$=
   P-CLAUDE CMD-SAVE ;

create UT-REAL 256 allot

: UT-DIR-TAIL$ ( n -- ^u8 n )
   P-CLAUDE = if s" /.claude" exit then
   s" /.codex" ;

\ the provider's real home, where test.sh's second run points its variable
: UT-REAL-HOME$ ( n -- ^u8 n ) {: p :}
   SB-RESET HOME$ SB-APPEND s" /real-home" SB-APPEND
   p UT-DIR-TAIL$ SB-APPEND SB$ UT-REAL 256 SPAN-COPY ;

\ a provider's home variable set in kiba's own environment never reaches
\ the login, which gets exactly the throwaway login dir under that name
: UT-LOGIN-ENV ( n ^u8 n -- ) {: p var vu :}
   p UT-REAL-HOME$ {: r ru :}
   var vu GETENV r ru T$=
   UT-LOG-MARK
   p s" " CMD-ADD
   UT-LOG-NEW$ r ru CONTAINS? TFALSE
   p LOGIN-HOME$ UT-BUF 256 SPAN-COPY {: h hu :}
   SB-RESET s" env " SB-APPEND var vu SB-APPEND s" =" SB-APPEND
   h hu SB-APPEND
   p UT-DIR-TAIL$ SB-APPEND s\" \n" SB-APPEND
   UT-LOG-NEW$ SB$ CONTAINS? TTRUE ;

: UT-LOGIN-ENVS ( -- )
   UT-FAKE-CLAUDE
   P-CLAUDE s" CLAUDE_CONFIG_DIR" UT-LOGIN-ENV
   P-CLAUDE s" b@x.test" CMD-FORGET
   UT-FAKE-CODEX
   P-CODEX s" CODEX_HOME" UT-LOGIN-ENV ;

\ a's login with its access token expired
: CREDS-A-OLD$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a-old\",\"refreshToken\":\"r-a\",\"expiresAt\":1,\"subscriptionType\":\"max\"}}" ;

\ the live account's expired token is reported, never sent
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
   CLAUDE-CREDS$ READ-FILE$ CREDS-A-OLD$ T$=
   P-CLAUDE s" a@x.test" CREDS-A-OLD$ UT-LOGIN=
   CLAUDE-CONFIG$ CFG-BA$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE ;

\ one provider's unreadable live file does not stop the other's probe; the
\ command fails once both have run
: UT-USAGE-ISOLATION ( -- )
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   P-CODEX s" c@x.test" UT-AGE
   P-CODEX s" d@x.test" UT-AGE
   -1 UT-USAGE-ERR
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: a login file is not valid JSON\nclaude: a login file is not valid JSON\n" T$=
   P-CODEX s" c@x.test" UT-PROBED? TTRUE
   P-CODEX s" d@x.test" UT-PROBED? TTRUE
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
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   P-CLAUDE s" a@x.test" CMD-FORGET
   P-CLAUDE s" a@x.test #2" CMD-FORGET
   P-CLAUDE UT-LIVE-NAME s" a@x.test" T$=
   P-CLAUDE CMD-SAVE ;

\ a pending install stops the probe before anything is probed or refreshed
: UT-UNREPAIRED ( -- )
   [: [: P-CLAUDE s" b@x.test" DB-NOTE-PENDING ;] DB-WRITE ;] UT-STORE
   UT-CLAUDE-ONLY-A
   P-CLAUDE s" a@x.test" UT-AGE
   P-CLAUDE UT-USAGE-ERR
   UT-ERR$ READ-FILE$
   s\" claude: live login not saved: the live Claude files name different accounts; switch to an account to repair them\nclaude: the claude switch to b@x.test did not finish; nothing is probed or refreshed until a switch completes\n" T$=
   P-CLAUDE s" a@x.test" UT-PROBED? TFALSE
   E-SW-UNREPAIRED REASON$
   s" kiba: the claude switch to b@x.test did not finish; nothing is probed or refreshed until a switch completes" T$=
   [: [: P-CLAUDE DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   P-CLAUDE UT-PENDING? TFALSE ;

\ a record the store refuses is reported under its account's name; the
\ other account is still recorded
: UT-UNRECORDED ( -- )
   P-CODEX s" c@x.test" UT-AGE
   P-CODEX s" d@x.test" UT-AGE
   [: s" CREATE TRIGGER ut_refuse BEFORE UPDATE OF usage ON account WHEN NEW.name = 'd@x.test' BEGIN SELECT RAISE(ABORT, 'refused by the test'); END" s" test" DB-EXEC ;] UT-STORE
   P-CODEX UT-USAGE-ERR
   [: s" DROP TRIGGER ut_refuse" s" test" DB-EXEC ;] UT-STORE
   UT-ERR$ READ-FILE$
   s\" codex: d@x.test: usage not recorded: the account database refused: set usage: refused by the test\n" T$=
   P-CODEX s" c@x.test" UT-PROBED? TTRUE
   P-CODEX s" d@x.test" UT-PROBED? TFALSE ;

\ when every saved login was probed after the run began, the recorded
\ outcomes are reported and nothing is probed
: UT-USAGE-CHECKED ( -- )
   [: P-CODEX DB-LIST DB-ROW# 2 T= ;] UT-STORE
   epoch-seconds 100000 + {: later :}
   P-CODEX s" c@x.test" later UT-SET-AT
   P-CODEX s" d@x.test" later UT-SET-AT
   LOG$ READ-FILE$ nip {: lu :}
   P-CODEX CMD-USAGE
   LOG$ READ-FILE$ nip lu T=
   P-CODEX s" c@x.test" UT-RECORD DB-USAGE-AT later T=
   P-CODEX s" d@x.test" UT-RECORD DB-USAGE-AT later T=
   P-CODEX s" c@x.test" 1 UT-SET-AT
   P-CODEX s" d@x.test" 1 UT-SET-AT ;

: UT-SET-LOGIN ( n ^u8 n ^u8 n -- ) {: p a u l lu :}
   [: [: p a u l lu DB-SET-LOGIN ;] DB-WRITE ;] UT-STORE ;

\ use probes the login it installs as live, then the one it saved back as
\ saved: d's rejected token is reported, never renewed
: UT-USE-PROBES ( -- )
   P-CODEX s" d@x.test" AUTH-D$ UT-SET-LOGIN
   P-CODEX s" c@x.test" UT-AGE
   P-CODEX s" d@x.test" UT-AGE
   UT-LOG-MARK
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" d@x.test" UT-PROBED? TTRUE
   P-CODEX s" c@x.test" UT-PROBED? TTRUE
   UT-LOG-NEW$ s" auth.openai.com/oauth/token" CONTAINS? TFALSE
   P-CODEX s" d@x.test" UT-RECORD s" expired" UT-STATE=
   DB-USAGE-NOTE$ s" access token rejected; run codex once to refresh it" T$=
   P-CODEX s" c@x.test" CMD-USE
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" AUTH-D2$ UT-SET-LOGIN ;

: OAUTH-N$ ( -- ^u8 n )
   s\" {\"accountUuid\":\"u3\",\"emailAddress\":\"n@x.test\",\"organizationUuid\":\"org-n\"}" ;

\ a login whose token has expired; no shared usage answer is ok for it
: CREDS-N-OLD$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-n-old\",\"refreshToken\":\"r-n\",\"expiresAt\":1,\"subscriptionType\":\"pro\"}}" ;

\ the Claude row n@x.test, with the profile an install splices in
: UT-PUT-N ( -- )
   OAUTH-N$ ID-SLOT CLAUDE-OAUTH-IDENTITY
   [: [: P-CLAUDE s" n@x.test" ID-SLOT CREDS-N-OLD$ OAUTH-N$ false DB-PUT ;] DB-WRITE ;] UT-STORE ;

\ a refresh request for refresh token r, as the server logs it
: UT-GRANT$ ( ^u8 n -- ^u8 n ) {: r ru :}
   SB-RESET s\" body {\"grant_type\":\"refresh_token\",\"refresh_token\":\"" SB-APPEND
   r ru SB-APPEND s\" \"" SB-APPEND SB$ ;

\ a Claude use probes the login it installs as live, then the one it saved
\ back as saved: only the saved login's expired token is refreshed
: UT-USE-PROBES-CLAUDE ( -- )
   UT-PUT-N
   CLAUDE-CREDS$ CREDS-A-OLD$ WRITE-PRIVATE
   P-CLAUDE s" n@x.test" UT-AGE
   P-CLAUDE s" a@x.test" UT-AGE
   UT-LOG-MARK
   P-CLAUDE s" n@x.test" CMD-USE
   P-CLAUDE s" n@x.test" UT-PROBED? TTRUE
   P-CLAUDE s" a@x.test" UT-PROBED? TTRUE
   CLAUDE-CREDS$ READ-FILE$ CREDS-N-OLD$ T$=
   P-CLAUDE s" n@x.test" UT-RECORD s" expired" UT-STATE=
   DB-USAGE-NOTE$ s" access token expired; Claude Code refreshes it on its next run" T$=
   P-CLAUDE s" a@x.test" UT-RECORD s" ok" UT-STATE=
   UT-LOG-NEW$ s" r-a" UT-GRANT$ CONTAINS? TTRUE
   UT-LOG-NEW$ s" r-n" UT-GRANT$ CONTAINS? TFALSE
   P-CLAUDE s" a@x.test" CREDS-A$ UT-SET-LOGIN
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   P-CLAUDE s" n@x.test" CMD-FORGET ;

\ ---- next --------------------------------------------------------------------
\ where x first occurs in l; -1 when it does not
: UT-OFFSET ( ^u8 n ^u8 n -- n )
   FIND-SUB MATCH option
      none OF -1 ENDOF
      some OF IDX>N ENDOF
   ;MATCH ;

\ since the mark, both x and y were logged, x first
: UT-SENT-FIRST? ( ^u8 n ^u8 n -- bool ) {: x xu y yu :}
   UT-LOG-NEW$ {: l lu :}
   l lu x xu UT-OFFSET {: i :}
   l lu y yu UT-OFFSET {: j :}
   i 0 >= j 0 >= and i j < and ;

\ next skips the live row whatever its last reading, tries n although its
\ last reading was blocked, installs it once its fresh probe as a saved login
\ has room, then probes the login it saved back as saved: both expired
\ tokens are refreshed, n's first
: UT-NEXT-PICKS ( -- )
   UT-PUT-N
   CLAUDE-CREDS$ CREDS-A-OLD$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" UT-SET-FINE
   P-CLAUDE s" n@x.test" UT-SET-BLOCKED
   UT-LOG-MARK
   [: P-CLAUDE CMD-NEXT ;] UT-CAPTURE$ s\" claude: now n@x.test\n" T$=
   P-CLAUDE UT-LIVE-NAME s" n@x.test" T$=
   CLAUDE-CREDS$ READ-FILE$ s" sk-b-new" CONTAINS? TTRUE
   P-CLAUDE s" n@x.test" UT-PROBED? TTRUE
   P-CLAUDE s" a@x.test" UT-PROBED? TTRUE
   s\" \"refresh_token\":\"r-n\"" s\" \"refresh_token\":\"r-a\""
   UT-SENT-FIRST? TTRUE
   P-CLAUDE s" a@x.test" CREDS-A$ UT-SET-LOGIN
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   P-CLAUDE s" n@x.test" CMD-FORGET ;

\ a's login as the running CLI rewrites it: a new refresh token
: CREDS-A-ROT$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-a\",\"refreshToken\":\"r-a-rot\",\"expiresAt\":4102444800000,\"subscriptionType\":\"max\"}}" ;

\ n's refresh answers once the live Claude login is rewritten to a's rotated one
: UT-ROTATE-ON-N ( -- )
   UT-CLAUDE-TOKEN$ s" r-n" 200 UT-ANSWER-OPEN
   s\" {\"access_token\":\"sk-b-new\",\"refresh_token\":\"r-b-new\",\"expires_in\":3600}" UT-BODY+
   CLAUDE-CREDS$ CREDS-A-ROT$ UT-ANSWER-CLOSE-WRITING ;

\ a login the running CLI rewrites while next probes is the one saved back
: UT-NEXT-ROTATED ( -- )
   UT-PUT-N
   P-CLAUDE s" n@x.test" UT-AGE
   UT-ROTATE-ON-N
   P-CLAUDE CMD-NEXT
   P-CLAUDE UT-LIVE-NAME s" n@x.test" T$=
   P-CLAUDE s" a@x.test" CREDS-A-ROT$ UT-LOGIN=
   P-CLAUDE s" a@x.test" CREDS-A$ UT-SET-LOGIN
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   P-CLAUDE s" n@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

\ live Claude files mixed over the installed row's expired token: next
\ never tries that row, so the token the CLI holds is not refreshed
: UT-NEXT-MIXED ( -- )
   UT-PUT-N
   CLAUDE-CREDS$ CREDS-A-OLD$ WRITE-PRIVATE
   P-CLAUDE CMD-SAVE
   CLAUDE-CONFIG$ CFG-B$ WRITE-PRIVATE
   P-CLAUDE s" a@x.test" UT-SET-FINE
   P-CLAUDE s" n@x.test" UT-AGE
   P-CLAUDE CMD-NEXT
   P-CLAUDE UT-LIVE-NAME s" n@x.test" T$=
   P-CLAUDE s" a@x.test" UT-PROBED? TFALSE
   P-CLAUDE s" a@x.test" CREDS-A$ UT-SET-LOGIN
   P-CLAUDE s" a@x.test" CMD-USE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   CLAUDE-CONFIG$ READ-FILE$ CFG-BA$ T$=
   P-CLAUDE s" n@x.test" CMD-FORGET ;

\ token t's Codex usage call answers that its week is used up
: UT-USED-UP ( ^u8 n -- ) {: t tu :}
   UT-CODEX-USAGE$ t tu 200 s\" {\"rate_limit\":{\"primary_window\":{\"used_percent\":100,\"limit_window_seconds\":604800,\"reset_at\":1789904220}}}" UT-ANSWER ;

\ next tries rows in room order, passing over one whose fresh reading has
\ no room: fine, tight, session used up, week used up, then unplanned
: UT-NEXT-ORDER ( -- )
   s" at-full" UT-USED-UP
   s" e@x.test" s" idle" UT-PUT-AT
   s" f@x.test" s" full" UT-PUT-AT
   P-CODEX s" d@x.test" UT-SET-TIGHT
   P-CODEX s" e@x.test" UT-SET-BLOCKED
   P-CODEX s" f@x.test" UT-SET-FINE
   UT-LOG-MARK
   P-CODEX CMD-NEXT
   CODEX-AUTH$ READ-FILE$ AUTH-D2$ T$=
   s\" Bearer at-full\n" s\" Bearer at-d2\n" UT-SENT-FIRST? TTRUE
   P-CODEX s" f@x.test" UT-PROBED? TTRUE
   P-CODEX s" e@x.test" UT-PROBED? TFALSE
   P-CODEX s" c@x.test" CMD-USE
   s" at-idle" UT-USED-UP
   P-CODEX s" d@x.test" s" unsubscribed" 10 20 UT-SET-USED
   P-CODEX s" e@x.test" UT-SET-BLOCKED
   P-CODEX s" f@x.test" s" ok" 100 100 UT-SET-USED
   UT-LOG-MARK
   P-CODEX CMD-NEXT
   CODEX-AUTH$ READ-FILE$ AUTH-D2$ T$=
   s\" Bearer at-idle\n" s\" Bearer at-full\n" UT-SENT-FIRST? TTRUE
   s\" Bearer at-full\n" s\" Bearer at-d2\n" UT-SENT-FIRST? TTRUE
   P-CODEX s" c@x.test" CMD-USE
   P-CODEX s" e@x.test" CMD-FORGET
   P-CODEX s" f@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

\ with no other row's fresh reading having room, and the rows whose login
\ is gone never tried, next installs nothing and probes nothing more
: UT-NEXT-NO-ROOM ( -- )
   s" at-d2" UT-USED-UP
   P-CODEX s" z@x.test" AUTH-Z$ UT-PUT
   P-CODEX s" y@x.test" AUTH-Y$ UT-PUT
   P-CODEX s" c@x.test" UT-AGE
   P-CODEX s" d@x.test" UT-SET-FINE
   P-CODEX s" y@x.test" UT-SET-DEAD
   P-CODEX s" z@x.test" s" missing" 0 0 UT-SET-USED
   UT-LOG-MARK
   [: P-CODEX CMD-NEXT ;] E-SW-NO-ROOM TTHROWSQ
   CODEX-AUTH$ READ-FILE$ AUTH-C$ T$=
   P-CODEX s" d@x.test" UT-PROBED? TTRUE
   P-CODEX s" c@x.test" UT-PROBED? TFALSE
   P-CODEX s" y@x.test" UT-PROBED? TFALSE
   P-CODEX s" z@x.test" UT-PROBED? TFALSE
   P-CODEX s" y@x.test" CMD-FORGET
   P-CODEX s" z@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

\ a pending install stops next before anything is probed or switched
: UT-NEXT-UNREPAIRED ( -- )
   UT-PUT-N
   P-CLAUDE s" n@x.test" UT-AGE
   P-CLAUDE s" a@x.test" UT-AGE
   [: [: P-CLAUDE s" b@x.test" DB-NOTE-PENDING ;] DB-WRITE ;] UT-STORE
   UT-LOG-MARK
   [: P-CLAUDE CMD-NEXT ;] E-SW-UNREPAIRED TTHROWSQ
   UT-LOG-NEW$ s" https://" CONTAINS? TFALSE
   P-CLAUDE s" n@x.test" UT-PROBED? TFALSE
   P-CLAUDE s" a@x.test" UT-PROBED? TFALSE
   CLAUDE-CREDS$ READ-FILE$ CREDS-A$ T$=
   [: [: P-CLAUDE DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   P-CLAUDE s" n@x.test" CMD-FORGET ;

\ ---- redeem ------------------------------------------------------------------
create UT-AUTH-BUF 256 allot

\ row p a u's record replaced by an ok one fetched at UT-OLD-AT, offering
\ a reset of program g under grant w
: UT-OFFER ( n ^u8 n ^u8 n ^u8 n -- ) {: p a u g gu w wu :}
   SB-RESET s\" {\"fetchedAt\":" SB-APPEND UT-OLD-AT FMT:SB-U
   s\" ,\"limits\":[],\"note\":\"\",\"resets\":{\"count\":1,\"grant\":\"" SB-APPEND
   w wu SB-APPEND s\" \",\"program\":\"" SB-APPEND g gu SB-APPEND
   s\" \"},\"state\":\"ok\"}" SB-APPEND SB$ DB-USAGE-DECODE
   DB-RESETS? TTRUE
   [: [: p a u UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE ;

: CREDS-R$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-r\",\"refreshToken\":\"r-r\",\"expiresAt\":4102444800000,\"subscriptionType\":\"max\"}}" ;

\ a Codex login whose token UT-CODEX-WORD answers
: UT-AUTH-W$ ( ^u8 n -- ^u8 n ) {: w wu :}
   SB-RESET s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-w-" SB-APPEND
   w wu SB-APPEND
   s\" \",\"refresh_token\":\"rt-w\",\"account_id\":\"acct\"}}" SB-APPEND
   SB$ UT-AUTH-BUF 256 SPAN-COPY ;

\ r@x.test's banked grant w-<word> spent: the answer's word is the outcome
: UT-CLAUDE-WORD ( ^u8 n ^u8 n -- ) {: g gu t tu :}
   s" sk-r" g 2 + gu 2 - UT-RESULT
   P-CLAUDE s" r@x.test" s" cedar_ember" g gu UT-OFFER
   P-CLAUDE s" r@x.test" CMD-REDEEM
   s" r@x.test" REDEEMED$ t tu T$= ;

\ at-w-<w>'s reset is answered with code w, its usage call with {}
: UT-CODE-ROWS ( ^u8 n -- ) {: w wu :}
   SB-RESET s" at-w-" SB-APPEND w wu SB-APPEND SB$ {: k ku :}
   UT-CODEX-CONSUME$ k ku 200 UT-ANSWER-OPEN
   s\" {\"code\":\"" UT-BODY+ w wu UT-BODY+ s\" \"}" UT-BODY+
   UT-ANSWER-CLOSE
   UT-CODEX-USAGE$ k ku 200 s" {}" UT-ANSWER ;

: UT-CODEX-WORD ( ^u8 n ^u8 n -- ) {: w wu t tu :}
   w wu UT-CODE-ROWS
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
: UT-RID-AT ( ^u8 n -- n ) {: l lu :}
   l lu s\" \"request_id\":\"" FIND-SUB MATCH option
     none OF -1 ENDOF
     some OF IDX>N 14 + ENDOF
   ;MATCH ;

\ the first request id in the log is 36 bytes, uppercase 8-4-4-4-12 hex,
\ then the closing quote
: UT-RID ( ^u8 n -- ) {: l lu :}
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
   UT-LOG-MARK
   s" w-reset" s" Limit reset for r@x.test" UT-CLAUDE-WORD
   P-CLAUDE s" r@x.test" UT-PROBED? TTRUE
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
   UT-ANSWERS-DEFAULT
   UT-LOG-MARK
   P-CLAUDE s" r@x.test" s" juniper_tide" s" " UT-OFFER
   P-CLAUDE s" r@x.test" CMD-REDEEM
   s" r@x.test" REDEEMED$ s" Limit reset for r@x.test" T$=
   UT-LOG-NEW$ s\" body {\"program\":\"juniper_tide\"}" CONTAINS? TTRUE
   s" sk-r" s" bogus" UT-RESULT
   P-CLAUDE s" r@x.test" s" cedar_ember" s" w-bogus" UT-OFFER
   [: P-CLAUDE s" r@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s\" kiba: Anthropic's reset endpoint sent an unknown result \"bogus\"" T$=
   P-CLAUDE s" r@x.test" CREDS-R$ UT-LOGIN=
   P-CLAUDE s" r@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

: CREDS-S$ ( -- ^u8 n )
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

1100 constant UT-GRANT-U   \ bytes in UT-GRANT-ROWS' grant id, all g

\ a usage answer with each window's reset that banks two grants, each with
\ its ends_at, the next one UT-GRANT-U bytes of g with ends_at its first
\ member; a Claude reset answers "reset"
: UT-GRANT-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-USAGE$ s" " 200 UT-ANSWER-OPEN
   s\" {\"five_hour\":{\"utilization\":10,\"resets_at\":\"2026-10-01T10:00:00+00:00\"},\"seven_day\":{\"utilization\":20,\"resets_at\":\"2026-10-07T10:00:00+00:00\"},\"limits\":[{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"percent\":30,\"resets_at\":\"2026-10-08T10:00:00+00:00\"}],\"cedar_ember\":{\"eligible\":true,\"next_grant_id\":\"" UT-BODY+
   [char] g UT-GRANT-U UT-BODY-FILL
   s\" \",\"grants\":[{\"id\":\"other\",\"resets_left\":9,\"ends_at\":\"2026-10-20T00:00:00Z\"},{\"ends_at\":\"2026-11-24T14:00:00+00:00\",\"id\":\"" UT-BODY+
   [char] g UT-GRANT-U UT-BODY-FILL
   s\" \",\"resets_left\":2}]}}" UT-BODY+
   UT-ANSWER-CLOSE
   s" " s" reset" UT-RESULT ;

: CREDS-G$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-g\",\"refreshToken\":\"r-g\",\"expiresAt\":4102444800000,\"subscriptionType\":\"max\"}}" ;

\ a probe records each window's reset and the banked grant named next,
\ whole; spending it sends that grant whole
: UT-REDEEM-LONG-GRANT ( -- )
   UT-GRANT-ROWS
   0 UT-LONG-U ! [char] g UT-GRANT-U UT-LONG-FILL
   P-CLAUDE s" g@x.test" s" org-g" CREDS-G$ UT-PUT-ORG
   P-CLAUDE CREDS-G$ false PROBE
   s" ok" UT-STATE= DB-LIMIT# 3 T=
   0 DB-LIMIT-RESETS$ s" 2026-10-01T10:00:00+00:00" T$=
   1 DB-LIMIT-RESETS$ s" 2026-10-07T10:00:00+00:00" T$=
   2 DB-LIMIT-RESETS$ s" 2026-10-08T10:00:00+00:00" T$=
   DB-RESETS? TTRUE
   DB-RESETS-COUNT 2 T=
   DB-RESETS-PROGRAM$ s" cedar_ember" T$=
   DB-RESETS-GRANT$ 0 UT-LONG$ T$=
   DB-RESETS-EXPIRY$ s" 2026-11-24T14:00:00Z" T$=
   [: [: P-CLAUDE s" g@x.test" UT-BUF -1 DB-SET-USAGE ;] DB-WRITE ;] UT-STORE
   UT-LOG-MARK
   P-CLAUDE s" g@x.test" CMD-REDEEM
   s" g@x.test" REDEEMED$ s" Limit reset for g@x.test" T$=
   UT-LONG-U @ {: o :}
   s\" \"grant_id\":\"" UT-LONG+ [char] g UT-GRANT-U UT-LONG-FILL [char] " 1 UT-LONG-FILL
   UT-LOG-NEW$ o UT-LONG$ CONTAINS? TTRUE
   P-CLAUDE s" g@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

\ a next grant whose ends_at is null records no expiry, whatever another had
: UT-GRANT-NO-END ( -- )
   UT-ANSWERS-RESET
   UT-CLAUDE-USAGE$ s" " 200 s\" {\"five_hour\":{\"utilization\":10,\"resets_at\":\"2026-10-01T10:00:00+00:00\"},\"cedar_ember\":{\"eligible\":true,\"next_grant_id\":\"g-n\",\"grants\":[{\"id\":\"other\",\"resets_left\":9,\"ends_at\":\"2026-10-20T00:00:00Z\"},{\"id\":\"g-n\",\"resets_left\":1,\"ends_at\":null}]}}" UT-ANSWER
   P-CLAUDE s" g@x.test" s" org-g" CREDS-G$ UT-PUT-ORG
   P-CLAUDE CREDS-G$ false PROBE
   s" ok" UT-STATE=
   DB-RESETS-COUNT 1 T=
   DB-RESETS-EXPIRY$ s" " T$=
   P-CLAUDE s" g@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

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
   P-CODEX s" d@x.test" UT-PROBED? TTRUE
   s" d@x.test" REDEEMED$ s" Limit reset for d@x.test" T$=
   P-CODEX s" d@x.test" [: UT-RENEWED-D ;] UT-ROW-LOGIN
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
   P-CODEX s" w@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

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

\ UT-LOG-MARK where nothing may have logged yet, so the log may not exist
: UT-MARK ( -- )
   LOG$ FS:FILE? 0= if LOG$ s" " FS:WRITE-ALL then
   UT-LOG-MARK ;

: UT-SNAP+ ( ^u8 n -- ) {: a u :}
   UT-SNAP-U @ u + 8192 > if E-SW-CAPACITY throw then
   a UT-SNAP UT-SNAP-U @ + u BYTE-COPY
   u UT-SNAP-U +! ;

: UT-SNAP-KEEP ( n -- ) {: p :}
   0 UT-SNAP-U !
   p DB-LIST
   DB-ROW# 0 ?do i DB-ROW-NAME$ UT-SNAP+ i DB-ROW-LOGIN$ UT-SNAP+ loop ;

\ every saved row of p, its name then its login
: UT-SNAP$ ( n -- ^u8 n ) {: p :}
   [: p UT-SNAP-KEEP ;] UT-STORE UT-SNAP UT-SNAP-U @ ;

\ rc's reason as usage prints it on stderr, without the "kiba: " lead
: UT-BARE$ ( n -- ^u8 n ) REASON$ {: r ru :} r 6 + ru 6 - ;

: UT-JSON-C ( n -- ) {: c :}
   c [char] / = if $5C SB-APPEND-C then
   c SB-APPEND-C ;

\ "error":"<rc's bare reason>" as the snapshot writes it, its slashes escaped
: UT-ERROR-KEY$ ( n -- ^u8 n )
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
   r ru s" /login-claude/.claude/.claude.json" CONTAINS? TTRUE
   r ru c cu CONTAINS? TFALSE ;

\ Claude credentials without a config stop usage, status, redeem and add
: UT-ORPHAN-STOPS ( -- )
   UT-ANSWERS-DEFAULT
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
: UT-UNNAMED ( n ^u8 n ^u8 n -- ) {: p f fu d du :}
   f fu UT-PATH 256 SPAN-COPY {: g gu :}
   g gu READ-FILE$ UT-KEPT 2048 SPAN-COPY {: k ku :}
   p UT-SNAP$ UT-SNAP0 8192 SPAN-COPY {: s su :}
   su 0 > TTRUE
   UT-ANSWERS-DEFAULT
   g gu d du WRITE-PRIVATE
   [: UT-UNNAMED-STATUS ;] UT-STORE
   UT-MARK
   p UT-USAGE-ERR
   UT-LOG-NEW$ s" /oauth/token" CONTAINS? TFALSE
   p UT-SNAP$ s su T$=
   g gu k ku WRITE-PRIVATE ;

\ a Codex login with neither an id_token nor an API key
: AUTH-NO-ID$ ( -- ^u8 n )
   s\" {\"OPENAI_API_KEY\":null,\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-c\",\"refresh_token\":\"rt-c\",\"account_id\":\"acct\"}}" ;

: UT-UNNAMED-CLAUDE ( -- ) P-CLAUDE CLAUDE-CONFIG$ CFG-NOAUTH$ UT-UNNAMED ;
: UT-UNNAMED-CODEX ( -- ) P-CODEX CODEX-AUTH$ AUTH-NO-ID$ UT-UNNAMED ;

\ a saved Claude login whose token has expired is renewed before its reset
\ is sent; the reset then fails, and the renewed login is saved anyway
: UT-REDEEM-EXPIRED ( -- )
   P-CLAUDE s" b@x.test" s" org-b" CREDS-B$ UT-PUT-ORG
   s" sk-b-new" s" bogus" UT-RESULT
   P-CLAUDE s" b@x.test" s" cedar_ember" s" w-bogus" UT-OFFER
   UT-LOG-MARK
   [: P-CLAUDE s" b@x.test" CMD-REDEEM ;] E-SW-REMOTE TTHROWSQ
   E-SW-REMOTE REASON$ s\" kiba: Anthropic's reset endpoint sent an unknown result \"bogus\"" T$=
   P-CLAUDE s" b@x.test" [: UT-RENEWED-B ;] UT-ROW-LOGIN
   UT-LOG-NEW$ {: l lu :}
   l lu s" https://platform.claude.com/v1/oauth/token" CONTAINS? TTRUE
   l lu s" /org-b/reset_rate_limits Authorization: Bearer sk-b-new" CONTAINS? TTRUE
   l lu s\" Bearer sk-b\n" CONTAINS? TFALSE
   P-CLAUDE s" b@x.test" CMD-FORGET
   UT-ANSWERS-DEFAULT ;

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

\ a pending install leaves no saved name known not to be live: the redeem
\ stops before it sends
: UT-REDEEM-BLOCKED ( -- )
   P-CLAUDE s" r@x.test" s" org-r" CREDS-R$ UT-PUT-ORG
   P-CLAUDE s" r@x.test" s" cedar_ember" s" w-reset" UT-OFFER
   [: [: P-CLAUDE s" r@x.test" DB-NOTE-PENDING ;] DB-WRITE ;] UT-STORE
   E-SW-UNREPAIRED UT-REDEEM-STOPS
   [: [: P-CLAUDE DB-CLEAR-PENDING ;] DB-WRITE ;] UT-STORE
   P-CLAUDE s" r@x.test" CREDS-R$ UT-LOGIN=
   P-CLAUDE s" r@x.test" CMD-FORGET ;

\ ---- the SQLite store -------------------------------------------------------
create UT-NUL 3 allot                 \ a login blob holding a NUL byte
variable UT-V

\ the encoder's bytes (keys sorted, no spaces) for one usage record
: USAGE-LIT$ ( -- ^u8 n )
   s\" {\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}" ;

\ USAGE-LIT$ with the reset offer's expiry
: USAGE-EXPIRY-LIT$ ( -- ^u8 n )
   s\" {\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"expiresAt\":\"2026-11-24T14:00:00Z\",\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}" ;

\ the first column of the last row sql selects; 0 when it selects none
: UT-DB-INT ( ^u8 n -- n ) {: a u :}
   0 UT-V !
   a u s" test" [: ;] [: 0 DB-COL-INT UT-V ! ;] DB-QUERY
   UT-V @ ;

: UT-DB-OPEN ( -- )
   $61 UT-NUL c! 0 UT-NUL 1+ c! $62 UT-NUL 2 + c!
   DB-OPEN
   s" PRAGMA user_version" UT-DB-INT 7 T= ;

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
   DB-RESETS-EXPIRY$ nip 0 T=
   [: P-CLAUDE s" a@x.test" s" pro" DB-SET-USAGE ;] DB-WRITE
   s" {}" DB-USAGE-DECODE
   DB-USAGE-NOTE$ s" usage record is unreadable; refresh usage" T$=
   P-CLAUDE s" a@x.test" DB-FETCH TTRUE
   0 DB-ROW-PLAN$ s" pro" T$=
   0 DB-ROW-USAGE TTRUE
   DB-USAGE-ENCODE USAGE-LIT$ T$= ;

\ an expiry survives the store byte for byte; a new offer starts with none
: UT-DB-EXPIRY ( -- )
   USAGE-EXPIRY-LIT$ DB-USAGE-DECODE
   DB-USAGE-ENCODE USAGE-EXPIRY-LIT$ T$=
   DB-RESETS-EXPIRY$ s" 2026-11-24T14:00:00Z" T$=
   1 s" juniper_tide" s" " DB-RESETS!
   DB-RESETS-EXPIRY$ nip 0 T=
   DB-USAGE-ENCODE s" expiresAt" CONTAINS? TFALSE ;

\ a second note replaces the first; clearing leaves none
: UT-DB-PENDING ( -- )
   [: P-CLAUDE s" a@x.test" DB-NOTE-PENDING ;] DB-WRITE
   [: P-CLAUDE s" b@x.test" DB-NOTE-PENDING ;] DB-WRITE
   P-CLAUDE DB-PENDING TTRUE s" b@x.test" T$=
   [: P-CLAUDE DB-CLEAR-PENDING ;] DB-WRITE
   P-CLAUDE DB-PENDING TFALSE 2drop ;

: UT-DB-ROLLBACK ( -- )
   [: [: P-CLAUDE s" c@x.test" ID-SLOT CREDS-A$ UT-NUL -1 false DB-PUT
         E-SW-LOGIN throw ;] DB-WRITE ;] E-SW-LOGIN TTHROWSQ
   P-CLAUDE s" c@x.test" DB-FETCH TFALSE ;

\ a write outside DB-WRITE is refused; a nested DB-WRITE fails at BEGIN
\ and leaves the outer transaction open for its later writes
: UT-DB-NESTED ( -- )
   [: P-CLAUDE s" n@x.test" ID-SLOT CREDS-A$ UT-NUL -1 false DB-PUT ;]
   E-SW-DB TTHROWSQ
   DB-ERROR$ s" put: transaction is closed" T$=
   [: [: [: ;] DB-WRITE ;] E-SW-DB TTHROWSQ
      P-CLAUDE s" n@x.test" ID-SLOT CREDS-A$ UT-NUL -1 false DB-PUT ;] DB-WRITE
   P-CLAUDE s" n@x.test" DB-FETCH TTRUE
   [: P-CLAUDE s" n@x.test" DB-REMOVE ;] DB-WRITE
   P-CLAUDE s" n@x.test" DB-FETCH TFALSE ;

\ the status snapshot's bytes: two saved Claude logins under one email, the
\ live one in the second organization, and a live Codex login never saved
: SNAP-LIT$ ( -- ^u8 n )
   s\" {\"providers\":[{\"accounts\":[{\"active\":false,\"figures\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"low\":false}],\"name\":\"a@x.test\",\"oldAt\":1700003600,\"outcome\":\"failed\",\"plan\":\"max\",\"rank\":0,\"relogin\":true,\"shownPlan\":\"max\",\"standing\":\"fine\",\"usage\":{\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}},{\"active\":true,\"name\":\"a@x.test #2\",\"plan\":\"team\",\"rank\":1,\"relogin\":false,\"shownPlan\":\"team\",\"standing\":\"unprobed\"}],\"installedAt\":1700000500,\"live\":{\"email\":\"a@x.test\",\"plan\":\"team\"},\"provider\":\"claude\"},{\"accounts\":[],\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"},\"provider\":\"codex\"}]}" ;

\ the same store once the Claude config is not JSON and c@x.test is saved
: SNAP-ERROR-LIT$ ( -- ^u8 n )
   s\" {\"providers\":[{\"accounts\":[{\"active\":false,\"figures\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"low\":false}],\"name\":\"a@x.test\",\"oldAt\":1700003600,\"outcome\":\"failed\",\"plan\":\"max\",\"rank\":0,\"relogin\":true,\"shownPlan\":\"max\",\"standing\":\"fine\",\"usage\":{\"fetchedAt\":1700000000,\"limits\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-13T10:00:00Z\"},{\"label\":\"Weekly \\/ Opus\",\"percent\":-1,\"resetsAt\":\"\"}],\"note\":\"a\\/b \\\"q\\\"\\n\",\"resets\":{\"count\":2,\"grant\":\"g-1\",\"program\":\"cedar_ember\"},\"state\":\"throttled\"}},{\"active\":false,\"name\":\"a@x.test #2\",\"plan\":\"team\",\"rank\":1,\"relogin\":false,\"shownPlan\":\"team\",\"standing\":\"unprobed\"}],\"error\":\"a login file is not valid JSON\",\"installedAt\":1700000500,\"provider\":\"claude\"},{\"accounts\":[{\"active\":true,\"name\":\"c@x.test\",\"plan\":\"plus\",\"rank\":0,\"relogin\":false,\"shownPlan\":\"plus\",\"standing\":\"unprobed\"}],\"live\":{\"email\":\"c@x.test\",\"plan\":\"plus\"},\"provider\":\"codex\"}]}" ;

: UT-STATUS-ROWS ( -- )
   s" DELETE FROM account" s" test" DB-EXEC
   s" DELETE FROM live" s" test" DB-EXEC
   USAGE-LIT$ DB-USAGE-DECODE
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" a@x.test" ID-SLOT CREDS-A$ OAUTH-A$ true DB-PUT ;] DB-WRITE
   CFG-A2$ CREDS-A2$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" a@x.test #2" ID-SLOT CREDS-A2$ UT-NUL -1 false DB-PUT
      P-CLAUDE s" a@x.test #2" 1700000500 true DB-NOTE-INSTALLED ;] DB-WRITE ;

\ the value the JSON pointer p u names in the status snapshot, as written;
\ false when it names none
: UT-STATUS-AT ( ^u8 n -- ^u8 n bool ) {: p u :}
   STATUS-JSON$ {: j ju :}
   j ju p u JSON:POINTER-SPAN {: at len found :}
   j at + len found ;

\ the member the JSON pointer names in the status snapshot reads as written
: UT-AT= ( ^u8 n ^u8 n -- ) {: p u a v :}
   p u UT-STATUS-AT TTRUE a v T$= ;

: UT-NO-AT ( ^u8 n -- ) UT-STATUS-AT TFALSE 2drop ;

\ the active mark follows the live organization
: UT-STATUS-JSON ( -- )
   UT-STATUS-ROWS
   CLAUDE-CONFIG$ CFG-A2$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A2$ WRITE-PRIVATE
   CODEX-AUTH$ AUTH-C$ WRITE-PRIVATE
   STATUS-JSON$ SNAP-LIT$ T$=
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   s" /providers/0/accounts/0/active" UT-STATUS-AT TTRUE s" true" T$=
   s" /providers/0/accounts/1/active" UT-STATUS-AT TTRUE s" false" T$= ;

\ an unreadable Claude login is Claude's error alone: its saved accounts and
\ install time still show, and Codex reads as before
: UT-STATUS-ERROR ( -- )
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE
   [: P-CODEX s" c@x.test" ID-SLOT AUTH-C$ UT-NUL -1 false DB-PUT ;] DB-WRITE
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   STATUS-JSON$ SNAP-ERROR-LIT$ T$= ;

\ live Claude credentials whose plan is one byte past PLAN-CAP
: CREDS-LONG$ ( -- ^u8 n )
   s\" {\"claudeAiOauth\":{\"accessToken\":\"sk-l\",\"subscriptionType\":\"ppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp\"}}" ;

create UT-SQL 2048 allot   variable UT-SQL-U

: UT-SQL+ ( ^u8 n -- ) {: a u :}
   a UT-SQL UT-SQL-U @ + u BYTE-COPY
   u UT-SQL-U +! ;

\ n@x.test's stored usage names a state that is none of the nine, longer
\ than the decoder's state word holds
: UT-ODD-STATE ( -- )
   0 UT-SQL-U !
   s\" UPDATE account SET usage = '{\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"subscription-lapsed\"}' WHERE provider = 'claude' AND name = 'n@x.test'" UT-SQL+
   UT-SQL UT-SQL-U @ s" test" DB-EXEC ;

\ SQLite's message naming a 600-byte table reaches DB-ERROR$ and the reason whole
: UT-DB-LONG-ERROR ( -- )
   0 UT-SQL-U !   s" SELECT 1 FROM " UT-SQL+   600 0 ?do s" x" UT-SQL+ loop
   0 UT-LONG-U !   s" kiba: the account database refused: " UT-LONG+
   UT-LONG-U @ {: o :}
   s" probe: no such table: " UT-LONG+   [char] x 600 UT-LONG-FILL
   [: UT-SQL UT-SQL-U @ s" probe" DB-EXEC ;] E-SW-DB TTHROWSQ
   DB-ERROR$ o UT-LONG$ T$=
   E-SW-DB REASON$ 0 UT-LONG$ T$= ;

\ text status's stdout, run as the command runs it, with its own store open
: UT-STATUS-TEXT$ ( -- ^u8 n )
   DB-CLOSE [: false CMD-STATUS ;] UT-CAPTURE$ DB-OPEN ;

\ both forms of status carry every one of a record's 200 windows
: UT-STATUS-MANY ( -- )
   s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" DB-USAGE-DECODE
   200 0 ?do s" w" 1 s" r" DB-LIMIT+ loop
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" m@x.test" ID-SLOT CREDS-A$ OAUTH-A$ true DB-PUT ;] DB-WRITE
   0 UT-WANT-U ! s\" \"limits\":[" UT-WANT+
   200 0 ?do
      i 0 > if s" ," UT-WANT+ then
      s\" {\"label\":\"w\",\"left\":99,\"percent\":1,\"resetsAt\":\"r\"}" UT-WANT+
   loop
   s" ]" UT-WANT+
   STATUS-JSON$ UT-WANT$ CONTAINS? TTRUE
   0 UT-WANT-U ! s" )  " UT-WANT+
   200 0 ?do
      i 0 > if s"  · " UT-WANT+ then
      s" 99%" UT-WANT+
   loop
   s\" \n" UT-WANT+
   UT-STATUS-TEXT$ UT-WANT$ CONTAINS? TTRUE
   [: P-CLAUDE s" m@x.test" DB-REMOVE ;] DB-WRITE ;

\ w@x.test's record: the session and the week stored after a model window,
\ and a window with no reading
: UT-FIGURES-ROW ( -- )
   s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" DB-USAGE-DECODE
   s" Weekly / Opus" 91 s" 2026-11-21T00:00:00Z" DB-LIMIT+
   s" Weekly (7-day)" 60 s" 2026-11-20T00:00:00Z" DB-LIMIT+
   s" Weekly / Sonnet" -1 s" " DB-LIMIT+
   s" Session (5-hour)" 30 s" 2026-11-14T10:00:00Z" DB-LIMIT+
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" w@x.test" ID-SLOT CREDS-A$ OAUTH-A$ true DB-PUT ;] DB-WRITE ;

: FIGURES-LIT$ ( -- ^u8 n )
   s\" {\"active\":false,\"figures\":[{\"label\":\"Session (5-hour)\",\"left\":70,\"low\":false},{\"label\":\"Weekly (7-day)\",\"left\":40,\"low\":true},{\"label\":\"Weekly \\/ Opus\",\"left\":9,\"low\":true}],\"name\":\"w@x.test\",\"oldAt\":3601,\"outcome\":\"answered\",\"plan\":\"max\",\"rank\":1,\"relogin\":false,\"shownPlan\":\"max\",\"standing\":\"tight\",\"usage\":{\"fetchedAt\":1,\"limits\":[{\"label\":\"Weekly \\/ Opus\",\"left\":9,\"percent\":91,\"resetsAt\":\"2026-11-21T00:00:00Z\"},{\"label\":\"Weekly (7-day)\",\"left\":40,\"percent\":60,\"resetsAt\":\"2026-11-20T00:00:00Z\"},{\"label\":\"Weekly \\/ Sonnet\",\"percent\":-1,\"resetsAt\":\"\"},{\"label\":\"Session (5-hour)\",\"left\":70,\"percent\":30,\"resetsAt\":\"2026-11-14T10:00:00Z\"}],\"note\":\"\",\"state\":\"ok\"}}" ;

\ the text gives the session, the week, then the other windows with a
\ reading; JSON keeps the record's order and gives each window with a
\ reading the percent left
: UT-STATUS-FIGURES ( -- )
   UT-FIGURES-ROW
   STATUS-JSON$ FIGURES-LIT$ CONTAINS? TTRUE
   UT-STATUS-TEXT$ s\" \n    w@x.test (max)  70% · 40% · 9%\n" CONTAINS? TTRUE
   [: P-CLAUDE s" w@x.test" DB-REMOVE ;] DB-WRITE ;

create UT-PTR 128 allot

\ the JSON pointer to member k ku of Claude's account i, in UT-PTR
: UT-ACCOUNT$ ( n ^u8 n -- ^u8 n ) {: i k ku :}
   SB-RESET s" /providers/0/accounts/" SB-APPEND i FMT:SB-U
   [char] / SB-APPEND-C k ku SB-APPEND
   SB$ UT-PTR 128 SPAN-COPY ;

\ the usage record of a probe in state s su that read no window yet
: UT-ROOM-REC ( ^u8 n -- ) {: s su :}
   SB-RESET s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"" SB-APPEND
   s su SB-APPEND s\" \"}" SB-APPEND SB$ DB-USAGE-DECODE ;

\ the session and the week, each its percent used and its reset
: UT-ROOM-SW ( n ^u8 n n ^u8 n -- ) {: sp sa su wp wa wu :}
   s" Session (5-hour)" sp sa su DB-LIMIT+
   s" Weekly (7-day)" wp wa wu DB-LIMIT+ ;

\ saves Claude row a u, with the decoded record when with is true
: UT-CLAUDE-PUT ( ^u8 n bool -- ) {: a u with :}
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE a u ID-SLOT CREDS-A$ OAUTH-A$ with DB-PUT ;] DB-WRITE ;

\ Claude row a u, ok, its session sp and its week wp percent used
: UT-ROOM-OK ( ^u8 n n n -- ) {: a u sp wp :}
   s" ok" UT-ROOM-REC sp s" " wp s" " UT-ROOM-SW
   a u true UT-CLAUDE-PUT ;

\ d its week used up, reopening with it; e, g and h their session used
\ up, e with no reset, h's reset in another zone, first as an instant
: UT-ROOM-BLOCKED ( -- )
   s" ok" UT-ROOM-REC 100 s" 2026-11-20T00:00:00Z"
   100 s" 2026-11-25T00:00:00Z" UT-ROOM-SW
   s" d@x.test" true UT-CLAUDE-PUT
   s" ok" UT-ROOM-REC 100 s" " 20 s" 2026-11-19T00:00:00Z" UT-ROOM-SW
   s" e@x.test" true UT-CLAUDE-PUT
   s" ok" UT-ROOM-REC 100 s" 2026-11-22T00:00:00Z" 20 s" " UT-ROOM-SW
   s" g@x.test" true UT-CLAUDE-PUT
   s" ok" UT-ROOM-REC
   100 s" 2026-11-22T05:00:00+08:00" 20 s" " UT-ROOM-SW
   s" h@x.test" true UT-CLAUDE-PUT ;

\ f and m both used up, only f's session and m's week reset readable
: UT-ROOM-BOTH ( -- )
   s" ok" UT-ROOM-REC
   100 s" 2026-11-21T00:00:00Z" 100 s" soon" UT-ROOM-SW
   s" f@x.test" true UT-CLAUDE-PUT
   s" ok" UT-ROOM-REC
   100 s" soon" 100 s" 2026-11-23T00:00:00Z" UT-ROOM-SW
   s" m@x.test" true UT-CLAUDE-PUT ;

\ b no record; c unplanned; i a model window used up; j tight; k fine; l
\ dead, its session used up and reopening before any other
: UT-ROOM-OTHERS ( -- )
   s" b@x.test" false UT-CLAUDE-PUT
   s" unsubscribed" UT-ROOM-REC 10 s" " 20 s" " UT-ROOM-SW
   s" c@x.test" true UT-CLAUDE-PUT
   s" ok" UT-ROOM-REC 10 s" " 20 s" " UT-ROOM-SW
   s" Weekly / Opus" 100 s" " DB-LIMIT+
   s" i@x.test" true UT-CLAUDE-PUT
   s" j@x.test" 60 20 UT-ROOM-OK
   s" k@x.test" 10 20 UT-ROOM-OK
   s" revoked" UT-ROOM-REC
   100 s" 2026-11-18T00:00:00Z" 20 s" " UT-ROOM-SW
   s" l@x.test" true UT-CLAUDE-PUT ;

: UT-ROOM-RANKS ( -- )
   0 s" rank" UT-ACCOUNT$ s" 0" UT-AT=
   1 s" rank" UT-ACCOUNT$ s" 12" UT-AT=
   2 s" rank" UT-ACCOUNT$ s" 13" UT-AT=
   3 s" rank" UT-ACCOUNT$ s" 10" UT-AT=
   4 s" rank" UT-ACCOUNT$ s" 9" UT-AT=
   5 s" rank" UT-ACCOUNT$ s" 6" UT-AT=
   6 s" rank" UT-ACCOUNT$ s" 7" UT-AT=
   7 s" rank" UT-ACCOUNT$ s" 5" UT-AT=
   8 s" rank" UT-ACCOUNT$ s" 4" UT-AT=
   9 s" rank" UT-ACCOUNT$ s" 3" UT-AT=
   10 s" rank" UT-ACCOUNT$ s" 2" UT-AT=
   11 s" rank" UT-ACCOUNT$ s" 1" UT-AT=
   12 s" rank" UT-ACCOUNT$ s" 11" UT-AT=
   13 s" rank" UT-ACCOUNT$ s" 8" UT-AT= ;

: UT-ROOM-REOPENS ( -- )
   0 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   1 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   2 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   3 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   4 s" reopensAt" UT-ACCOUNT$
   s\" \"2026-11-25T00:00:00Z\"" UT-AT=
   5 s" reopensAt" UT-ACCOUNT$ s\" \"\"" UT-AT=
   6 s" reopensAt" UT-ACCOUNT$
   s\" \"2026-11-21T00:00:00Z\"" UT-AT=
   7 s" reopensAt" UT-ACCOUNT$
   s\" \"2026-11-22T00:00:00Z\"" UT-AT=
   8 s" reopensAt" UT-ACCOUNT$
   s\" \"2026-11-22T05:00:00+08:00\"" UT-AT=
   9 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   10 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   11 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   12 s" reopensAt" UT-ACCOUNT$ UT-NO-AT
   13 s" reopensAt" UT-ACCOUNT$
   s\" \"2026-11-23T00:00:00Z\"" UT-AT= ;

: UT-ROOM-DROP ( ^u8 n -- ) {: a u :}
   [: P-CLAUDE a u DB-REMOVE ;] DB-WRITE ;

: UT-ROOM-FORGET ( -- )
   s" b@x.test" UT-ROOM-DROP s" c@x.test" UT-ROOM-DROP
   s" d@x.test" UT-ROOM-DROP s" e@x.test" UT-ROOM-DROP
   s" f@x.test" UT-ROOM-DROP s" g@x.test" UT-ROOM-DROP
   s" h@x.test" UT-ROOM-DROP s" i@x.test" UT-ROOM-DROP
   s" j@x.test" UT-ROOM-DROP s" k@x.test" UT-ROOM-DROP
   s" l@x.test" UT-ROOM-DROP s" m@x.test" UT-ROOM-DROP ;

\ rows of every class out of name order: each one's rank, and when a
\ blocked one reopens
: UT-ROOM-ORDER ( -- )
   UT-ROOM-BLOCKED
   UT-ROOM-BOTH
   UT-ROOM-OTHERS
   UT-ROOM-RANKS
   UT-ROOM-REOPENS
   UT-ROOM-FORGET ;

\ saves a Codex row of c@x.test's login under the name, with the decoded
\ record
: UT-CODEX-PUT ( ^u8 n -- ) {: a u :}
   AUTH-C$ ID-SLOT CODEX-IDENTITY TTRUE
   [: P-CODEX a u ID-SLOT AUTH-C$ UT-NUL -1 true DB-PUT ;] DB-WRITE ;

\ Claude rows after a@x.test and a@x.test #2: fa's week is used up and two
\ windows share a label, fb is revoked, fd unsubscribed
: UT-FIELDS-CLAUDE ( -- )
   s\" {\"fetchedAt\":1700000000,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" DB-USAGE-DECODE
   s" Weekly / Opus" 20 s" " DB-LIMIT+
   s" Session (5-hour)" 30 s" " DB-LIMIT+
   s" Weekly (7-day)" 100 s" " DB-LIMIT+
   s" Weekly / Opus" 70 s" " DB-LIMIT+
   s" fa@x.test" true UT-CLAUDE-PUT
   s\" {\"fetchedAt\":5,\"limits\":[],\"note\":\"\",\"state\":\"revoked\"}" DB-USAGE-DECODE
   s" fb@x.test" true UT-CLAUDE-PUT
   s\" {\"fetchedAt\":8,\"limits\":[],\"note\":\"\",\"state\":\"unsubscribed\"}" DB-USAGE-DECODE
   s" fd@x.test" true UT-CLAUDE-PUT ;

\ Codex rows: c@x.test, the live login, and d@x.test, saved, both expired
: UT-FIELDS-CODEX ( -- )
   s\" {\"fetchedAt\":9,\"limits\":[],\"note\":\"\",\"state\":\"expired\"}" DB-USAGE-DECODE
   s" Session (5-hour)" 10 s" " DB-LIMIT+
   s" c@x.test" UT-CODEX-PUT
   s\" {\"fetchedAt\":11,\"limits\":[],\"note\":\"\",\"state\":\"expired\"}" DB-USAGE-DECODE
   s" d@x.test" UT-CODEX-PUT ;

\ a used-up week leaves Claude's session 0, low; each window of a shared
\ label gives its own left
: UT-FIELDS-BLOCKED ( -- )
   s" /providers/0/accounts/2/standing" s\" \"blocked\"" UT-AT=
   s" /providers/0/accounts/2/outcome" s\" \"answered\"" UT-AT=
   s" /providers/0/accounts/2/relogin" s" false" UT-AT=
   s" /providers/0/accounts/2/figures/0/label" s\" \"Session (5-hour)\"" UT-AT=
   s" /providers/0/accounts/2/figures/0/left" s" 0" UT-AT=
   s" /providers/0/accounts/2/figures/0/low" s" true" UT-AT=
   s" /providers/0/accounts/2/figures/2/low" s" false" UT-AT=
   s" /providers/0/accounts/2/usage/limits/0/left" s" 80" UT-AT=
   s" /providers/0/accounts/2/usage/limits/3/left" s" 30" UT-AT= ;

\ a record with no limits has no oldAt; a saved revoked login asks for a
\ new login
: UT-FIELDS-SAVED ( -- )
   s" /providers/0/accounts/3/standing" s\" \"dead\"" UT-AT=
   s" /providers/0/accounts/3/outcome" s\" \"answered\"" UT-AT=
   s" /providers/0/accounts/3/relogin" s" true" UT-AT=
   s" /providers/0/accounts/3/figures" s" []" UT-AT=
   s" /providers/0/accounts/3/oldAt" UT-NO-AT
   s" /providers/0/accounts/4/standing" s\" \"unplanned\"" UT-AT=
   s" /providers/0/accounts/4/shownPlan" s\" \"no plan\"" UT-AT= ;

\ the live login's expired token waits, a saved one's is dead
: UT-FIELDS-OTHER ( -- )
   s" /providers/1/accounts/0/active" s" true" UT-AT=
   s" /providers/1/accounts/0/standing" s\" \"fine\"" UT-AT=
   s" /providers/1/accounts/0/outcome" s\" \"waiting\"" UT-AT=
   s" /providers/1/accounts/0/relogin" s" false" UT-AT=
   s" /providers/1/accounts/1/standing" s\" \"dead\"" UT-AT=
   s" /providers/1/accounts/1/outcome" s\" \"answered\"" UT-AT=
   s" /providers/1/accounts/1/relogin" s" true" UT-AT= ;

\ each account carries what the panel shows of it
: UT-ACCOUNT-FIELDS ( -- )
   UT-FIELDS-CLAUDE UT-FIELDS-CODEX
   UT-FIELDS-BLOCKED UT-FIELDS-SAVED UT-FIELDS-OTHER
   [: P-CLAUDE s" fa@x.test" DB-REMOVE P-CLAUDE s" fb@x.test" DB-REMOVE
      P-CLAUDE s" fd@x.test" DB-REMOVE
      P-CODEX s" c@x.test" DB-REMOVE P-CODEX s" d@x.test" DB-REMOVE ;] DB-WRITE ;

\ the live read's reason is the one it stopped on, though decoding a row's
\ usage overflows another buffer before the error is written
: UT-STATUS-REASON ( -- )
   CFG-A$ CREDS-A$ ID-SLOT CLAUDE-IDENTITY TTRUE
   [: P-CLAUDE s" n@x.test" ID-SLOT CREDS-A$ OAUTH-A$ false DB-PUT ;] DB-WRITE
   UT-ODD-STATE
   CLAUDE-CONFIG$ CFG-A$ WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-LONG$ WRITE-PRIVATE
   STATUS-JSON$ s\" \"error\":\"too many: bytes in a JSON string (limit 64)\"" CONTAINS? TTRUE
   UT-STATUS-TEXT$ s\" claude: too many: bytes in a JSON string (limit 64)\n" CONTAINS? TTRUE
   CLAUDE-CONFIG$ s" {not json" WRITE-PRIVATE
   CLAUDE-CREDS$ CREDS-A$ WRITE-PRIVATE
   [: P-CLAUDE s" n@x.test" DB-REMOVE ;] DB-WRITE ;

\ a version 5 store: sixteen 64 KiB rows of history, an add record and a
\ pending row under an install claim
: UT-HISTORY-FILL ( -- )
   s" PRAGMA user_version = 5" s" test" DB-EXEC
   s" CREATE TABLE history (id INTEGER PRIMARY KEY, provider TEXT, details BLOB)"
   s" test" DB-EXEC
   s" CREATE INDEX history_provider ON history(provider, id)" s" test" DB-EXEC
   s" WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 16) INSERT INTO history (provider, details) SELECT 'claude', zeroblob(65536) FROM n"
   s" test" DB-EXEC
   s" CREATE TABLE adding (provider TEXT PRIMARY KEY, live BLOB, service TEXT NOT NULL) WITHOUT ROWID"
   s" test" DB-EXEC
   s" INSERT INTO adding VALUES ('claude', NULL, '')" s" test" DB-EXEC
   s" DROP TABLE pending" s" test" DB-EXEC
   s" CREATE TABLE pending (provider TEXT PRIMARY KEY, name TEXT NOT NULL, owner TEXT) WITHOUT ROWID"
   s" test" DB-EXEC
   s" INSERT INTO pending VALUES ('codex', 'p@x.test', 'c1')" s" test" DB-EXEC ;

\ the next open drops the history, the add record and the claim and
\ compacts the store: no page is free
: UT-DB-COMPACT ( -- )
   UT-HISTORY-FILL
   DB-CLOSE DB-OPEN
   s" SELECT count(*) FROM sqlite_schema WHERE tbl_name = 'history'" UT-DB-INT 0 T=
   s" SELECT count(*) FROM sqlite_schema WHERE tbl_name = 'adding'" UT-DB-INT 0 T=
   s" SELECT count(*) FROM pragma_table_info('pending') WHERE name = 'owner'" UT-DB-INT 0 T=
   P-CODEX DB-PENDING TTRUE s" p@x.test" T$=
   s" PRAGMA user_version" UT-DB-INT 7 T=
   s" PRAGMA freelist_count" UT-DB-INT 0 T=
   [: P-CODEX DB-CLEAR-PENDING ;] DB-WRITE ;

\ a newer schema is refused and leaves the store closed
: UT-DB-VERSION ( -- )
   s" PRAGMA user_version = 8" s" test" DB-EXEC
   DB-CLOSE
   [: DB-OPEN ;] E-SW-DB-VERSION TTHROWSQ
   [: P-CLAUDE DB-LIST ;] E-SW-DB TTHROWSQ ;

create UT-LABEL 200 allot   create UT-RESET 100 allot

\ seventeen limits with long labels and resets survive the record's codec
: UT-DB-MANY ( -- )
   200 0 ?do [char] l UT-LABEL i + c! loop
   100 0 ?do [char] r UT-RESET i + c! loop
   s\" {\"fetchedAt\":1,\"limits\":[],\"note\":\"\",\"state\":\"ok\"}" DB-USAGE-DECODE
   17 0 ?do UT-LABEL 200 i UT-RESET 100 DB-LIMIT+ loop
   DB-USAGE-ENCODE DB-USAGE-DECODE
   s" ok" UT-STATE= DB-LIMIT# 17 T=
   17 0 ?do
      i UT-LABEL 200 i UT-LIMIT=
      i DB-LIMIT-RESETS$ UT-RESET 100 T$=
   loop ;

: UT-DB ( -- )
   UT-DB-OPEN
   UT-DB-PUT
   UT-DB-FETCH
   UT-DB-USAGE
   UT-DB-EXPIRY
   UT-DB-MANY
   UT-DB-PENDING
   UT-DB-ROLLBACK
   UT-DB-NESTED
   UT-DB-LONG-ERROR
   UT-STATUS-JSON
   UT-STATUS-MANY
   UT-STATUS-FIGURES
   UT-ROOM-ORDER
   UT-ACCOUNT-FIELDS
   UT-STATUS-ERROR
   UT-STATUS-REASON
   UT-DB-COMPACT
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

: UT-TURN$ ( -- ^u8 n )
   STORE$ {: s su :}
   SB-RESET s su SB-APPEND s" /turn-claude" SB-APPEND
   SB$ UT-TURN UT-TURN-U PATH!
   UT-TURN UT-TURN-U @ ;

: UT-QUEUE$ ( -- ^u8 n )
   UT-TURN$ {: t tu :}
   SB-RESET t tu SB-APPEND s" .queue" SB-APPEND
   SB$ UT-QUEUE UT-QUEUE-U PATH!
   UT-QUEUE UT-QUEUE-U @ ;

\ an entry no waiter holds, sorting before any a waiter makes
: UT-STALE$ ( -- ^u8 n )
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
\ the Codex outcomes: the usage call answers 429 to at-t, 200 to at-d2 and
\ 401 to any other token; the token endpoint refuses rt-x with
\ invalid_grant, answers rt-u without an access token and 503 to anything
\ else
: UT-CODEX-OUTCOME-ROWS ( -- )
   UT-ANSWERS-RESET
   UT-CODEX-USAGE$ s" " 401 s\" {\"error\":{\"code\":\"token_expired\"}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-t" 429 s\" {\"error\":{\"code\":\"rate_limited\"}}" UT-ANSWER
   UT-CODEX-USAGE$ s" at-d2" 200 s" {}" UT-ANSWER
   UT-CODEX-TOKEN$ s" " 503 s" " UT-ANSWER
   UT-CODEX-TOKEN$ s" rt-x" 400 s\" {\"error\":\"invalid_grant\"}" UT-ANSWER
   UT-CODEX-TOKEN$ s" rt-u" 200 s\" {\"refresh_token\":\"rt-u2\"}" UT-ANSWER ;

\ an API-key login whose tokens hold an access token but no id_token
: AUTH-KEY-AT$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"sk-k\",\"tokens\":{\"access_token\":\"at-k\",\"refresh_token\":\"rt-k\"}}" ;

: AUTH-X$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-x\",\"refresh_token\":\"rt-x\",\"account_id\":\"acct\"}}" ;

\ a ChatGPT login with no refresh token
: AUTH-M$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-m\",\"account_id\":\"acct\"}}" ;

: AUTH-U$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-u\",\"refresh_token\":\"rt-u\",\"account_id\":\"acct\"}}" ;

: AUTH-T$ ( -- ^u8 n )
   s\" {\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"at-t\",\"refresh_token\":\"rt-t\",\"account_id\":\"acct\"}}" ;

\ usage codex run with row a u holding login l lu, the log marked
\ before it
: UT-OUTCOME-RUN ( ^u8 n ^u8 n -- ) {: a u l lu :}
   P-CODEX a u l lu UT-PUT
   UT-LOG-MARK
   P-CODEX CMD-USAGE ;

: UT-NOTE= ( ^u8 n -- ) {: a u :}
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

\ each outcome of a Codex probe that the shared answers never give, as its
\ usage record shows it; the live c@x.test answers 401 throughout
: UT-CODEX-OUTCOMES ( -- )
   UT-CODEX-OUTCOME-ROWS
   UT-CODEX-API-KEY
   UT-CODEX-LIVE-401
   UT-CODEX-REFUSED
   UT-CODEX-NO-GRANT
   UT-CODEX-NO-ACCESS
   UT-CODEX-THROTTLED
   UT-ANSWERS-DEFAULT ;

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
: UT-TURN-OF$ ( n -- ^u8 n )
   UT-OWN-TURN UT-OWN-TURN-U UT-TURN-PATH!
   UT-OWN-TURN UT-OWN-TURN-U @ ;

\ the fake script name in the scratch PATH
: UT-FAKE$ ( ^u8 n -- ^u8 n ) {: n nu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND
   SB$ UT-FAKE-PATH UT-FAKE-U PATH!
   UT-FAKE-PATH UT-FAKE-U @ ;

\ where the fake name goes once a turn check runs in front of it
: UT-ANSWERS$ ( ^u8 n -- ^u8 n ) {: n nu :}
   HOME$ {: h hu :}
   SB-RESET h hu SB-APPEND s" /bin/" SB-APPEND n nu SB-APPEND
   s" -answers" SB-APPEND
   SB$ UT-ANS-PATH UT-ANS-U PATH!
   UT-ANS-PATH UT-ANS-U @ ;

\ a script that logs "turn held <name>" when provider p's turn is locked as
\ it starts, "turn free <name>" when it is not, then runs the fake name
: UT-WRAP$ ( n ^u8 n -- ^u8 n ) {: p n nu :}
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
: UT-TURN-WRAP ( n ^u8 n -- ) {: p n nu :}
   n nu UT-FAKE$ n nu UT-ANSWERS$ FS:RENAME-FILE
   n nu p n nu UT-WRAP$ UT-WRITE-SCRIPT ;

: UT-TURN-LINE$ ( ^u8 n ^u8 n -- ^u8 n ) {: s su n nu :}
   SB-RESET s" turn " SB-APPEND s su SB-APPEND
   STR-SPACE SB-APPEND-C n nu SB-APPEND SB$ ;

\ since the mark, name ran with its provider's turn held, never without:
\ a fake's name, or request for the requests the server took
: UT-RAN-HELD ( ^u8 n -- ) {: n nu :}
   UT-LOG-NEW$ {: l lu :}
   l lu s" held" n nu UT-TURN-LINE$ CONTAINS? TTRUE
   l lu s" free" n nu UT-TURN-LINE$ CONTAINS? TFALSE
   l lu s" unknown" n nu UT-TURN-LINE$ CONTAINS? TFALSE ;

\ usage probes each provider's logins inside that provider's turn
: UT-USAGE-HELD ( -- )
   UT-ANSWERS-DEFAULT
   UT-LOG-MARK
   P-CLAUDE CMD-USAGE
   s" request" UT-RAN-HELD
   UT-LOG-MARK
   P-CODEX CMD-USAGE
   s" request" UT-RAN-HELD ;

\ use probes the login it installs and the one it saved back in its turn
: UT-USE-HELD ( -- )
   UT-LOG-MARK
   P-CODEX s" d@x.test" CMD-USE
   P-CODEX s" c@x.test" CMD-USE
   s" request" UT-RAN-HELD ;

\ next probes the logins it tries and the one it saved back in its turn
: UT-NEXT-HELD ( -- )
   P-CODEX s" d@x.test" UT-AGE
   UT-LOG-MARK
   P-CODEX CMD-NEXT
   s" request" UT-RAN-HELD
   P-CODEX s" c@x.test" CMD-USE ;

\ redeem asks for the reset and probes again in its turn
: UT-REDEEM-HELD ( -- )
   UT-LOG-MARK
   s" reset" s" Limit reset for w@x.test" UT-CODEX-WORD
   s" request" UT-RAN-HELD
   P-CODEX s" w@x.test" CMD-FORGET ;

\ add's login runs in its turn, and so does the probe of the new login
: UT-ADD-HELD ( -- )
   UT-FAKE-CLAUDE P-CLAUDE s" claude" UT-TURN-WRAP
   UT-LOG-MARK
   P-CLAUDE s" b@x.test" CMD-ADD
   s" claude" UT-RAN-HELD
   s" request" UT-RAN-HELD
   P-CLAUDE s" b@x.test" CMD-FORGET
   UT-FAKE-CLAUDE ;

\ every command that calls out does so holding its provider's turn
: UT-COMMANDS-HELD ( -- )
   UT-USAGE-HELD
   UT-USE-HELD
   UT-NEXT-HELD
   UT-REDEEM-HELD
   UT-ADD-HELD
   UT-ANSWERS-DEFAULT ;

\ a Claude turn held elsewhere: usage waits TURN-WAIT-MS, reports the busy
\ turn as Claude's error and calls nothing
: UT-USAGE-BUSY ( -- )
   UT-TURN$ FS:>PATHZ open-rd {: fd :}
   fd >FD FS-LOCK:TRY TTRUE
   300 TURN-WAIT-MS !
   UT-CLAUDE-ONLY-A
   P-CLAUDE s" a@x.test" UT-AGE
   UT-LOG-MARK
   P-CLAUDE UT-USAGE-ERR
   120000 TURN-WAIT-MS !
   fd close
   UT-ERR$ READ-FILE$
   s\" claude: another kiba holds that provider's turn\n" T$=
   UT-LOG-NEW$ nip 0 T=
   P-CLAUDE s" a@x.test" UT-PROBED? TFALSE ;

\ ---- kiba as a program -------------------------------------------------------
\ MAIN ends the process through die, so a child runs it: the hb running this
\ suite loads src/kiba.f and a file that calls MAIN. The child's HOME and
\ store are its own, and its URL-BASE names a scheme libcurl may not speak,
\ so a probe fails before it reaches any network.
create UT-HB PATH-CAP allot
create UT-PROG PATH-CAP allot    variable UT-PROG-U
create UT-AT PATH-CAP allot      variable UT-AT-U
create UT-CHILD PATH-CAP allot   variable UT-CHILD-U   \ the child's HOME
create UT-CC PATH-CAP allot      variable UT-CC-U      \ its CLAUDE_CONFIG_DIR
create UT-CX PATH-CAP allot      variable UT-CX-U      \ its CODEX_HOME
$1A4 constant UT-MODE-OUT                              \ 0644

\ directory d's entry f, f starting with a slash
: UT-AT$ ( ^u8 n ^u8 n -- ^u8 n )
   {: d du f fu :}
   SB-RESET d du SB-APPEND f fu SB-APPEND SB$ UT-AT UT-AT-U PATH!
   UT-AT UT-AT-U @ ;

: UT-CHILD$ ( -- ^u8 n ) UT-CHILD UT-CHILD-U @ ;
: UT-CC$ ( -- ^u8 n ) UT-CC UT-CC-U @ ;
: UT-CX$ ( -- ^u8 n ) UT-CX UT-CX-U @ ;

\ the child's HOME, HOME's entry f
: UT-CHILD! ( ^u8 n -- ) HOME$ 2swap UT-AT$ UT-CHILD UT-CHILD-U PATH! ;

: UT-HB$ ( -- ^u8 n )
   s" /proc/self/exe" FS:>PATHZ UT-HB PATH-CAP readlink {: n :}
   n 0 < if E-FS-IO throw then
   UT-HB n ;

: UT-KIBA-F$ ( -- ^u8 n )
   SB-RESET SOURCE-ROOT:CURRENT$ SB-APPEND s" /../src/kiba.f" SB-APPEND
   SB$ UT-PROG UT-PROG-U PATH!
   UT-PROG UT-PROG-U @ ;

: UT-MAIN-F$ ( -- ^u8 n ) HOME$ s" /kiba-main.f" UT-AT$ ;
: UT-OUT$ ( -- ^u8 n ) HOME$ s" /kiba-out" UT-AT$ ;
: UT-ERR-OUT$ ( -- ^u8 n ) HOME$ s" /kiba-err" UT-AT$ ;

\ the child's program: requests go nowhere, then MAIN
: UT-OFFLINE-MAIN$ ( -- ^u8 n )
   s\" package SW\n: UT-OFFLINE ( -- ) s\" none://\" URL-BASE URL-BASE-U PATH! ;\nUT-OFFLINE\n;package\nMAIN\n" ;

\ kiba's MAIN, its arguments to follow
: UT-KIBA-NEW ( -- PROCESS:request )
   UT-MAIN-F$ UT-OFFLINE-MAIN$ FS:WRITE-ALL
   UT-HB$ PROCESS:NEW
   s" --load" PROCESS:ARG
   UT-KIBA-F$ PROCESS:ARG
   UT-MAIN-F$ PROCESS:ARG
   s" --" PROCESS:ARG
   s" HOME" UT-CHILD$ PROCESS:ENV
   s" XDG_DATA_HOME" UT-CHILD$ s" /data" UT-AT$ PROCESS:ENV
   s" PATH" UT-CHILD$ s" /bin" UT-AT$ PROCESS:ENV ;

: UT-CREATE ( ^u8 n -- n )
   FS:>PATHZ FS:O-WRONLY FS:O-CREAT or FS:O-TRUNC or UT-MODE-OUT open {: fd :}
   fd 0 < if E-FS-OPEN throw then
   fd ;

\ the exit code of the run, its stdout in UT-OUT$ and its stderr in
\ UT-ERR-OUT$
: UT-KIBA-RUN ( PROCESS:request -- n )
   UT-OUT$ UT-CREATE {: out :}
   UT-ERR-OUT$ UT-CREATE {: err :}
   1 >FD out >FD PROCESS:FD
   2 >FD err >FD PROCESS:FD
   PROCESS:SPAWN {: pid :}
   out close-rc 0 T=
   err close-rc 0 T=
   pid PROCESS:WAIT PROCESS:STATUS>RC RC>N ;

\ the run printed o on stdout and e on stderr, then exited with c
: UT-KIBA= ( PROCESS:request ^u8 n ^u8 n n -- )
   {: o ou e eu c :}
   UT-KIBA-RUN {: rc :}
   UT-OUT$ READ-FILE$ o ou T$=
   UT-ERR-OUT$ READ-FILE$ e eu T$=
   rc c T= ;

: USAGE-TEXT$ ( -- ^u8 n )
   s\" usage: kiba status [--json]\n       kiba save [claude|codex]\n       kiba use <claude|codex> <email>\n       kiba next <claude|codex>\n       kiba add <claude|codex> [name]\n       kiba forget <claude|codex> <email>\n       kiba redeem <claude|codex> <email>\n       kiba usage [claude|codex]\n" ;

\ MAIN exits 0 after a run, 1 with the reason when a command fails, and 64
\ with the usage when it refuses the command line
: UT-EXIT-CODES ( -- )
   s" /exit-home" UT-CHILD!
   UT-KIBA-NEW s" status" PROCESS:ARG
   s\" claude: no live login\ncodex: no live login\n" s" " 0 UT-KIBA=
   UT-KIBA-NEW s" forget" PROCESS:ARG s" claude" PROCESS:ARG
   s" nobody@x.test" PROCESS:ARG
   s" " s\" kiba: no such saved account\n" 1 UT-KIBA=
   UT-KIBA-NEW s" use" PROCESS:ARG s" bogus" PROCESS:ARG s" x" PROCESS:ARG
   s" " USAGE-TEXT$ 64 UT-KIBA=
   UT-KIBA-NEW s" next" PROCESS:ARG s" bogus" PROCESS:ARG
   s" " USAGE-TEXT$ 64 UT-KIBA=
   UT-KIBA-NEW s" next" PROCESS:ARG s" claude" PROCESS:ARG
   s" " s\" kiba: no other saved account was found with room\n" 1 UT-KIBA=
   UT-KIBA-NEW s" " USAGE-TEXT$ 64 UT-KIBA= ;

\ UT-KIBA-NEW with the live files placed in UT-CC$ and UT-CX$
: UT-PLACED-NEW ( -- PROCESS:request )
   UT-KIBA-NEW
   s" CLAUDE_CONFIG_DIR" UT-CC$ PROCESS:ENV
   s" CODEX_HOME" UT-CX$ PROCESS:ENV ;

\ the placed live files hold Claude's config c and credentials k and
\ Codex's auth x
: UT-PLACED! ( ^u8 n ^u8 n ^u8 n -- )
   {: c cu k ku x xu :}
   UT-CC$ s" /.claude.json" UT-AT$ c cu WRITE-PRIVATE
   UT-CC$ s" /.credentials.json" UT-AT$ k ku WRITE-PRIVATE
   UT-CX$ s" /auth.json" UT-AT$ x xu WRITE-PRIVATE ;

: UT-PLACED= ( ^u8 n ^u8 n ^u8 n -- )
   {: c cu k ku x xu :}
   UT-CC$ s" /.claude.json" UT-AT$ READ-FILE$ c cu T$=
   UT-CC$ s" /.credentials.json" UT-AT$ READ-FILE$ k ku T$=
   UT-CX$ s" /auth.json" UT-AT$ READ-FILE$ x xu T$= ;

\ nothing at the places under HOME the live files take by default
: UT-HOME-BARE ( -- )
   UT-CHILD$ s" /.claude.json" UT-AT$ FS:EXISTS? TFALSE
   UT-CHILD$ s" /.claude" UT-AT$ FS:EXISTS? TFALSE
   UT-CHILD$ s" /.codex" UT-AT$ FS:EXISTS? TFALSE ;

: UT-PLACED-USE ( ^u8 n ^u8 n -- PROCESS:request )
   {: p pu a au :}
   UT-PLACED-NEW s" use" PROCESS:ARG p pu PROCESS:ARG a au PROCESS:ARG ;

\ with CLAUDE_CONFIG_DIR and CODEX_HOME set, save reads the live files
\ there and use writes them there; HOME's places stay empty
: UT-CONFIG-PLACES ( -- )
   s" /place-home" UT-CHILD!
   HOME$ s" /place-claude" UT-AT$ UT-CC UT-CC-U PATH!
   HOME$ s" /place-codex" UT-AT$ UT-CX UT-CX-U PATH!
   UT-CC$ ENSURE-PRIVATE
   UT-CX$ ENSURE-PRIVATE
   CFG-B$ CREDS-B$ AUTH-D$ UT-PLACED!
   UT-PLACED-NEW s" save" PROCESS:ARG
   s\" claude: saved b@x.test\ncodex: saved d@x.test\n" s" " 0 UT-KIBA=
   CFG-A$ CREDS-A$ AUTH-C$ UT-PLACED!
   s" claude" s" b@x.test" UT-PLACED-USE s\" claude: now b@x.test\n" s" " 0 UT-KIBA=
   s" codex" s" d@x.test" UT-PLACED-USE s\" codex: now d@x.test\n" s" " 0 UT-KIBA=
   CFG-AB$ CREDS-B$ AUTH-D$ UT-PLACED=
   UT-HOME-BARE ;

: UT-ALL ( -- )
   UT-B64
   UT-JWT
   UT-DOC
   UT-IDENTITY
   UT-PLAN-UNREADABLE
   UT-STRINGS
   UT-READER-RECOVERS
   UT-CLAIMS-REPEAT
   UT-DEEP-REPEAT
   UT-REPEATS-FAST
   UT-FIELD-LONG
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
   UT-CONFIG-DIR
   UT-RESTORED
   UT-REPAIR-PENDING
   UT-MISMATCH
   UT-DAMAGED-ROW
   UT-REPEATED-CREDS
   UT-API-KEY
   UT-SYMLINK
   UT-REL-SYMLINK
   UT-FAILED-WRITE
   UT-MIXED-PAIR
   UT-ORPHAN
   UT-ORPHAN-LONG
   UT-ORPHAN-STOPS
   UT-UNNAMED-CLAUDE
   UT-UNNAMED-CODEX
   UT-STORE-FORGET
   UT-LIVE-AC
   UT-ADD
   UT-ADD-EMPTY
   UT-ADD-CLAUDE
   UT-ADD-FAILED
   UT-PCT
   UT-RFC3339
   UT-PCT-CALLERS
   UT-SCOPED-LONG
   UT-LONG-TOKEN
   UT-RENEWED-THROWS
   UT-CREDITS-TOO-BIG
   UT-OUTPUT-REFUSED
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
   UT-NEXT-PICKS
   UT-NEXT-ROTATED
   UT-NEXT-MIXED
   UT-NEXT-ORDER
   UT-NEXT-NO-ROOM
   UT-NEXT-UNREPAIRED
   UT-COMMANDS-HELD
   UT-USAGE-BUSY
   UT-REDEEM-CLAUDE
   UT-REDEEM-RENEWED
   UT-REDEEM-SEGMENT
   UT-REDEEM-LONG-GRANT
   UT-GRANT-NO-END
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
   UT-EXIT-CODES
   UT-CONFIG-PLACES ;

\ test.sh's second run starts kiba with CLAUDE_CONFIG_DIR and CODEX_HOME
\ set, which only the login environment case expects
: UT-HOMES-SET? ( -- bool )
   s" CLAUDE_CONFIG_DIR" GETENV nip 0 > ;

\ UT-LOG-MARK reads the log, which exists only once a fake has written it
: UT-HOMES ( -- )
   LOG$ s" " FS:WRITE-ALL
   UT-LOGIN-ENVS ;

: UT-CASES ( -- )
   UT-HOMES-SET? if UT-HOMES exit then
   UT-ALL ;

: UT-MAIN ( -- )
   T-RESET
   ALLOC-BUFFERS
   UT-SERVE-START
   [: UT-CASES ;] [: UT-SERVE-STOP ;] finally
   T-REPORT ;

UT-MAIN

;package
