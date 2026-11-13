\ sw-codex.f - the Codex CLI's live login: read and written.
require ../src/sw-identity.f

package SW

public

: CODEX-LIVE-IDENTITY ( -- bool )
   CODEX-AUTH$ FS:FILE? 0= if ID-LIVE NO-IDENTITY false exit then
   CODEX-AUTH$ READ-FILE$ ID-LIVE CODEX-IDENTITY ;

private

\ the live auth.json as one read into FILE, the identity in ID-LIVE decoded
\ from those same bytes; no profile. False when there is no auth.json.
: CODEX-LIVE-LOGIN ( -- ptr u8 n ptr u8 n bool )
   CODEX-AUTH$ FILE-BUF FILE-U READ-OPT nip 0 < if
      FILE-BUF 0 FILE-BUF -1 false exit
   then
   FILE$ ID-LIVE CODEX-IDENTITY 0= if E-SW-JSON throw then
   FILE$ FILE-BUF -1 true ;

: PUT-AUTH ( ptr u8 n -- ) {: d du :}
   CODEX-AUTH$ DIRNAME ENSURE-PRIVATE
   CODEX-AUTH$ d du WRITE-PRIVATE ;

;package
