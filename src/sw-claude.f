\ sw-claude.f - Claude Code's live login: read and written.
require ../src/sw-identity.f
require ../src/sw-db.f
require ../src/sw-base.f
require ../src/sw-paths.f
require ../src/sw-io.f
require ../src/sw-json.f
require src/lib/fs-mutate.f
require src/lib/fs.f
require src/lib/prelude.f
require src/lib/string.f

package SW

: OAUTH-KEY$ ( -- ptr u8 n ) s" oauthAccount" ;

: OUT-RESET ( -- ) 0 OUT-U ! ;

: OUT+ ( ptr u8 n -- ) {: a u :}
   OUT-U @ u + BUF-CAP > if DOC-TOO-BIG then
   a OUT-BUF OUT-U @ + u BYTE-COPY
   OUT-U @ u + OUT-U ! ;

: CFG-PART+ ( n n -- ) {: off len :}
   CFG-BUF off + len OUT+ ;

\ OUT = CFG[0,off) + OBJ + CFG[off+len, end)
: SPLICE-CONFIG ( n n -- ) {: off len :}
   OUT-RESET
   0 off CFG-PART+
   OBJ$ OUT+
   off len + CFG-U @ off len + - CFG-PART+ ;

\ OUT = CFG[0,close) + ["oauthAccount":OBJ] + CFG[close, end)
: INSERT-CONFIG ( n bool -- ) {: close members :}
   OUT-RESET
   0 close CFG-PART+
   members if s\" ," OUT+ then
   s\" \"oauthAccount\":" OUT+
   OBJ$ OUT+
   close CFG-U @ close - CFG-PART+ ;

: NEW-CONFIG ( -- )
   OUT-RESET
   s\" {\"oauthAccount\":" OUT+
   OBJ$ OUT+
   s\" }" OUT+ ;

: CHECK-CREDS ( ptr u8 n -- ) {: d du :}
   d du CHECK-OBJECT
   d du s" claudeAiOauth" DOC-OBJ-SPAN? 0= if E-SW-JSON throw then 2drop ;

: CHECK-SLOT-EMAIL ( ptr u8 n -- ) {: a u :}
   OBJ$ ID-SLOT CLAUDE-OAUTH-IDENTITY
   a u ID-SLOT EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then ;

create ORPHAN-CFG PATH-CAP allot   variable ORPHAN-CFG-U

: NOTE-ORPHAN ( -- ) CLAUDE-CONFIG$ ORPHAN-CFG ORPHAN-CFG-U PATH! ;

public

\ the config CLAUDE-LIVE last found missing beside live credentials
: ORPHAN-CONFIG$ ( -- ptr u8 n ) ORPHAN-CFG ORPHAN-CFG-U @ ;

\ ---- the live login over the store ----------------------------------------
private

\ The live config goes to CFG, length -1 when there is none, and the live
\ credentials to FILE, length -1 likewise.

\ false when there are no credentials; credentials without a config are some
\ account's tokens and nothing says whose, so they are E-SW-ORPHAN-LIVE
\ about the config ORPHAN-CONFIG$ then names
: CLAUDE-LIVE ( -- bool )
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-OPT 2drop
   CLAUDE-CREDS$ FILE-BUF FILE-U READ-OPT nip 0 < if false exit then
   CFG-U @ 0 < if NOTE-ORPHAN E-SW-ORPHAN-LIVE throw then
   true ;

\ ID-LIVE from the config in CFG and the credentials in FILE; answers the
\ oauthAccount object in CFG, and E-SW-JSON when there is none
: CLAUDE-DECODE ( -- ptr u8 n )
   CFG$ FILE$ ID-LIVE CLAUDE-ACCOUNT 0= if E-SW-JSON throw then ;

\ the login as one read: the credentials, and the profile the identity came
\ from; false when there is no live login
: CLAUDE-LIVE-LOGIN ( -- ptr u8 n ptr u8 n bool )
   CLAUDE-LIVE 0= if FILE-BUF 0 FILE-BUF -1 false exit then
   CLAUDE-DECODE {: pa pu :}
   FILE$ pa pu true ;

create MIXED-NAME NAME-CAP allot   variable MIXED-NAME-U

: MIXED-NAME$ ( -- ptr u8 n ) MIXED-NAME MIXED-NAME-U @ ;

\ an org on either side that is unknown matches
: SAME-ORG? ( -- bool )
   ID-LIVE ORG$ nip 0= if true exit then
   0 DB-ROW-ORG$ nip 0= if true exit then
   ID-LIVE ORG$ 0 DB-ROW-ORG$ STR= ;

\ the installed row exists, the live config names another account, and the
\ live credentials are still that row's login
: OTHER-OVER-INSTALLED? ( -- bool )
   P-CLAUDE DB-INSTALLED 0= if 2drop false exit then
   MIXED-NAME MIXED-NAME-U NAME-CAP SPAN!
   P-CLAUDE MIXED-NAME$ DB-FETCH 0= if false exit then
   CLAUDE-DECODE 2drop
   MIXED-NAME$ ID-LIVE EMAIL$ NAME-FOR-EMAIL? SAME-ORG? and if false exit then
   FILE$ 0 DB-ROW-LOGIN$ STR= ;

\ The live files are read first, so orphan credentials throw even while an
\ install is pending. A pending install is mixed whatever the files hold.
: CLAUDE-LIVE-MIXED? ( -- bool )
   CLAUDE-LIVE {: pair :}
   P-CLAUDE DB-PENDING nip nip if true exit then
   pair 0= if false exit then
   OTHER-OVER-INSTALLED? ;

\ OUT = the live config with its top-level oauthAccount value, of any kind,
\ replaced by OBJ; inserted before the closing brace when absent; a new
\ document when there is no config
: CLAUDE-SPLICED ( -- )
   CFG-U @ 0 < if NEW-CONFIG exit then
   CFG$ OAUTH-KEY$ DOC-VALUE-SPAN? if SPLICE-CONFIG exit then
   2drop CFG$ DOC-CLOSE INSERT-CONFIG ;

\ removes the file a config write would replace; nothing to do when absent,
\ E-FS-IO and nothing removed when a directory is there
: DROP-CONFIG ( -- )
   CLAUDE-CONFIG$ WRITE-TARGET {: t tu :}
   t tu FS:EXISTS? if t tu FS:REMOVE-FILE then ;

public

\ makes the live config the document; length -1 removes it
: PUT-CONFIG ( ptr u8 n -- ) {: d du :}
   du 0 < if DROP-CONFIG exit then
   CLAUDE-CONFIG$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CONFIG$ d du WRITE-PRIVATE ;

private

: PUT-CREDS ( ptr u8 n -- ) {: d du :}
   CLAUDE-CREDS$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CREDS$ d du WRITE-PRIVATE ;

\ whether the live credentials read back as FILE, the bytes read before an
\ install: a write that failed may still have replaced them
: CREDS-BACK? ( -- bool )
   CLAUDE-CREDS$ BACK-BUF BACK-U READ-OPT FILE$ SAME-OPT? ;

;package
