\ sw-claude.f - save and install Claude Code logins.
require ../src/sw-identity.f

package SW

: CREDS-NAME$ ( -- ptr u8 n ) s" credentials.json" ;
: OAUTH-NAME$ ( -- ptr u8 n ) s" oauth-account.json" ;
: OAUTH-KEY$ ( -- ptr u8 n ) s" oauthAccount" ;

: OUT-RESET ( -- ) 0 OUT-U ! ;

: OUT+ ( ptr u8 n -- ) {: a u :}
   OUT-U @ u + BUF-CAP > if E-SW-CAPACITY throw then
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

\ the saved object replaces the live value of any kind, so a null left by a
\ logout is overwritten rather than joined by a second key; a missing key is
\ inserted and a missing file is created
: BUILD-CONFIG ( -- )
   CLAUDE-CONFIG$ FILE? 0= if NEW-CONFIG exit then
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-INTO 2drop
   CFG$ OAUTH-KEY$ DOC-VALUE-SPAN? if SPLICE-CONFIG exit then
   2drop CFG$ DOC-CLOSE INSERT-CONFIG ;

: WRITE-CONFIG-LIVE ( -- )
   CLAUDE-CONFIG$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CONFIG$ OUT$ WRITE-PRIVATE ;

\ until the config rename lands nothing is replaced, so a failed first write
\ takes its marker with it; after it the marker must stay
: WRITE-CONFIG-MARKED ( -- )
   [: WRITE-CONFIG-LIVE ;] catch {: rc :}
   rc 0= if exit then
   P-CLAUDE CLEAR-MARK
   rc throw ;

: CHECK-CREDS ( ptr u8 n -- ) {: d du :}
   d du CHECK-OBJECT
   d du s" claudeAiOauth" DOC-OBJ-SPAN? 0= if E-SW-JSON throw then 2drop ;

: CHECK-SLOT-EMAIL ( ptr u8 n -- ) {: a u :}
   OBJ$ ID-SLOT CLAUDE-OAUTH-IDENTITY 0= if E-SW-JSON throw then
   a u ID-SLOT EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then ;

public

EXPORT CREDS-NAME$

\ loads both live documents; false when Claude Code has no login
: CLAUDE-LIVE-IDENTITY ( -- bool )
   CLAUDE-CONFIG$ FILE? 0= if ID-LIVE NO-IDENTITY false exit then
   CLAUDE-CREDS$ FILE? 0= if ID-LIVE NO-IDENTITY false exit then
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-INTO
   CLAUDE-CREDS$ FILE-BUF FILE-U READ-INTO
   ID-LIVE CLAUDE-IDENTITY ;

\ the two live documents are read here, so a slot read between naming the
\ account and saving it cannot put another login's bytes in the slot
: CLAUDE-SAVE-LIVE ( ptr u8 n -- ) {: a u :}
   CLAUDE-CONFIG$ CFG-BUF CFG-U READ-INTO 2drop
   CLAUDE-CREDS$ FILE-BUF FILE-U READ-INTO 2drop
   P-CLAUDE a u SLOT-DIR$ ENSURE-PRIVATE
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ FILE$ WRITE-PRIVATE
   CFG$ OAUTH-KEY$ DOC-OBJ-SPAN {: off len :}
   P-CLAUDE a u OAUTH-NAME$ SLOT-FILE$ CFG-BUF off + len WRITE-PRIVATE ;

: CLAUDE-SLOT-PLAN ( ptr u8 n -- ) {: a u :}
   ID-SLOT NO-IDENTITY
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ FILE? 0= if exit then
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ READ-FILE$ ID-SLOT CLAUDE-PLAN ;

\ the marker brackets the two live writes; see sw-io.f
: CLAUDE-INSTALL ( ptr u8 n -- ) {: a u :}
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ FILE? 0= if E-SW-NO-ACCOUNT throw then
   P-CLAUDE a u OAUTH-NAME$ SLOT-FILE$ FILE? 0= if E-SW-NO-ACCOUNT throw then
   P-CLAUDE a u OAUTH-NAME$ SLOT-FILE$ OBJ-BUF OBJ-U READ-INTO CHECK-OBJECT
   a u CHECK-SLOT-EMAIL
   BUILD-CONFIG
   P-CLAUDE a u CREDS-NAME$ SLOT-FILE$ READ-FILE$ CHECK-CREDS
   P-CLAUDE a u MARK-INSTALL
   WRITE-CONFIG-MARKED
   CLAUDE-CREDS$ DIRNAME ENSURE-PRIVATE
   CLAUDE-CREDS$ FILE$ WRITE-PRIVATE
   P-CLAUDE CLEAR-MARK
   P-CLAUDE a u NOTE-INSTALLED ;

;package
