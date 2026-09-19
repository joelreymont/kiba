\ sw-codex.f - save and install Codex CLI logins.
require ../src/sw-identity.f

package SW

: AUTH-NAME$ ( -- ptr u8 n ) s" auth.json" ;

public

EXPORT AUTH-NAME$

: CODEX-LIVE-IDENTITY ( -- bool )
   CODEX-AUTH$ FILE? 0= if ID-LIVE NO-IDENTITY false exit then
   CODEX-AUTH$ READ-FILE$ ID-LIVE CODEX-IDENTITY ;

\ the live document is read here, so a slot read between naming the account
\ and saving it cannot put another login's bytes in the slot
: CODEX-SAVE-LIVE ( ptr u8 n -- ) {: a u :}
   CODEX-AUTH$ FILE-BUF FILE-U READ-INTO 2drop
   P-CODEX a u SLOT-DIR$ ENSURE-PRIVATE
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE$ WRITE-PRIVATE ;

: CODEX-SLOT-PLAN ( ptr u8 n -- ) {: a u :}
   ID-SLOT NO-IDENTITY
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE? 0= if exit then
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ READ-SLOT$ ID-SLOT CODEX-IDENTITY drop ;

: CODEX-INSTALL ( ptr u8 n -- ) {: a u :}
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE? 0= if E-SW-NO-ACCOUNT throw then
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ READ-SLOT$ ID-SLOT CODEX-IDENTITY 0= if E-SW-JSON throw then
   a u ID-SLOT EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then
   CODEX-AUTH$ DIRNAME ENSURE-PRIVATE
   CODEX-AUTH$ SDOC$ WRITE-PRIVATE ;

;package
