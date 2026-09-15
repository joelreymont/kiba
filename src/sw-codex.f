\ sw-codex.f - save and install Codex CLI logins.
require ../src/sw-identity.f

package SW

: AUTH-NAME$ ( -- ptr u8 n ) s" auth.json" ;

public

EXPORT AUTH-NAME$

: CODEX-LIVE-IDENTITY ( -- bool )
   CODEX-AUTH$ FILE? 0= if NO-IDENTITY false exit then
   CODEX-AUTH$ READ-FILE$ CODEX-IDENTITY ;

\ requires CODEX-LIVE-IDENTITY to have loaded the live document
: CODEX-SAVE-LIVE ( ptr u8 n -- ) {: a u :}
   P-CODEX a u SLOT-DIR$ ENSURE-PRIVATE
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE$ WRITE-PRIVATE ;

: CODEX-SLOT-PLAN ( ptr u8 n -- ) {: a u :}
   0 PLAN-U !
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE? 0= if exit then
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ READ-FILE$ CODEX-IDENTITY drop ;

: CODEX-INSTALL ( ptr u8 n -- ) {: a u :}
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ FILE? 0= if E-SW-NO-ACCOUNT throw then
   P-CODEX a u AUTH-NAME$ SLOT-FILE$ READ-FILE$ CODEX-IDENTITY 0= if E-SW-JSON throw then
   a u EMAIL$ NAME-FOR-EMAIL? 0= if E-SW-MISMATCH throw then
   CODEX-AUTH$ DIRNAME ENSURE-DIR
   CODEX-AUTH$ FILE$ WRITE-PRIVATE ;

;package
