\ sw-identity.f - the email and plan of a login, live or saved.
require ../src/sw-json.f

package SW

256 constant EMAIL-CAP
64 constant PLAN-CAP
128 constant ORG-CAP

public

\ kiba holds two logins at once, the live one and the slot it is comparing
\ against, so every parser and accessor names the identity it works on
0 constant ID-LIVE
1 constant ID-SLOT

private

\ one row of every buffer and one length cell per field, per identity
2 constant ID-COUNT
0 constant F-EMAIL
1 constant F-PLAN
2 constant F-ORG
3 constant F-COUNT

create EMAIL-BUF ID-COUNT EMAIL-CAP * allot
create PLAN-BUF ID-COUNT PLAN-CAP * allot
create ORG-BUF ID-COUNT ORG-CAP * allot       \ organization or account id
create ID-LENS ID-COUNT F-COUNT * cells allot

: EMAIL-ROW ( n -- ptr u8 ) EMAIL-BUF swap EMAIL-CAP * + ;
: PLAN-ROW ( n -- ptr u8 ) PLAN-BUF swap PLAN-CAP * + ;
: ORG-ROW ( n -- ptr u8 ) ORG-BUF swap ORG-CAP * + ;

: LEN-CELL ( n n -- ptr n ) {: id f :} ID-LENS id F-COUNT * f + cells + ;
: LEN@ ( n n -- n ) LEN-CELL @ ;

\ a field DOC-STR1 or DOC-STR2 could not read is empty, not -1 bytes long
: LEN! ( n n n -- ) {: len id f :} len 0 max id f LEN-CELL ! ;

public

: EMAIL$ ( n -- ptr u8 n ) {: id :} id EMAIL-ROW id F-EMAIL LEN@ ;
: PLAN$ ( n -- ptr u8 n ) {: id :} id PLAN-ROW id F-PLAN LEN@ ;
: ORG$ ( n -- ptr u8 n ) {: id :} id ORG-ROW id F-ORG LEN@ ;

\ one identity cleared to empty: no login is known yet
: NO-IDENTITY ( n -- ) {: id :}
   F-COUNT 0 ?do 0 id i LEN! loop ;

\ ---- Claude Code ------------------------------------------------------------
: CLAUDE-PLAN ( ptr u8 n n -- ) {: cr cru id :}
   cr cru s" claudeAiOauth" s" subscriptionType" id PLAN-ROW PLAN-CAP DOC-STR2
   id F-PLAN LEN! ;

\ the organization tells two logins under one email apart
: CLAUDE-ORG ( ptr u8 n n -- ) {: cfg cu id :}
   cfg cu s" oauthAccount" s" organizationUuid" id ORG-ROW ORG-CAP DOC-STR2 id F-ORG LEN! ;

\ the oauthAccount object on its own, as saved in a slot
: CLAUDE-OAUTH-IDENTITY ( ptr u8 n n -- bool ) {: d du id :}
   id NO-IDENTITY
   d du s" emailAddress" id EMAIL-ROW EMAIL-CAP DOC-STR1 dup 0 < if drop false exit then id F-EMAIL LEN!
   d du s" organizationUuid" id ORG-ROW ORG-CAP DOC-STR1 id F-ORG LEN!
   true ;

\ config document (.claude.json) plus credentials document
: CLAUDE-IDENTITY ( ptr u8 n ptr u8 n n -- bool ) {: cfg cu cr cru id :}
   id NO-IDENTITY
   cfg cu s" oauthAccount" s" emailAddress" id EMAIL-ROW EMAIL-CAP DOC-STR2
   dup 0 < if drop false exit then id F-EMAIL LEN!
   cfg cu id CLAUDE-ORG
   cr cru id CLAUDE-PLAN
   true ;

\ ---- Codex ------------------------------------------------------------------
: JWT-PAYLOAD ( ptr u8 n -- ptr u8 n ) {: t tu :}
   t tu DOT INDEX-OF MATCH option
     none OF E-SW-JSON throw ENDOF
     some OF IDX>N ENDOF
   ;MATCH {: d1 :}
   t d1 1+ + tu d1 1+ - {: r ru :}
   r ru DOT INDEX-OF MATCH option
     none OF E-SW-JSON throw ENDOF
     some OF IDX>N ENDOF
   ;MATCH {: d2 :}
   r d2 ;

: CODEX-API-KEY? ( ptr u8 n -- bool ) {: d du :}
   d du s" OPENAI_API_KEY" TOK-BUF BUF-CAP DOC-STR1 0 > ;

\ an API-key login has no claims; it is saved under a fixed slot name
: CODEX-API-IDENTITY ( ptr u8 n n -- bool ) {: d du id :}
   d du CODEX-API-KEY? 0= if false exit then
   s" api-key" id EMAIL-ROW id F-EMAIL LEN-CELL EMAIL-CAP SPAN!
   s" apikey" id PLAN-ROW id F-PLAN LEN-CELL PLAN-CAP SPAN!
   true ;

\ auth.json document: identity comes from the id_token claims
: CODEX-IDENTITY ( ptr u8 n n -- bool ) {: d du id :}
   id NO-IDENTITY
   d du s" tokens" s" id_token" TOK-BUF BUF-CAP DOC-STR2
   dup 0 < if drop d du id CODEX-API-IDENTITY exit then {: tu :}
   TOK-BUF tu JWT-PAYLOAD OBJ-BUF BUF-CAP B64URL-DECODE OBJ-U !
   OBJ$ s" email" id EMAIL-ROW EMAIL-CAP DOC-STR1
   dup 0 < if drop false exit then id F-EMAIL LEN!
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_plan_type" id PLAN-ROW PLAN-CAP DOC-STR2 id F-PLAN LEN!
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_account_id" id ORG-ROW ORG-CAP DOC-STR2 id F-ORG LEN!
   true ;

;package
