\ sw-identity.f - the email and plan of a login, live or saved.
require ../src/sw-json.f

package SW

256 constant EMAIL-CAP
64 constant PLAN-CAP

create EMAIL-BUF EMAIL-CAP allot   variable EMAIL-U
create PLAN-BUF PLAN-CAP allot     variable PLAN-U
create ORG-BUF 128 allot           variable ORG-U      \ organization or account id
create ORGNAME-BUF 128 allot       variable ORGNAME-U  \ its human name, may be empty

public

: EMAIL$ ( -- ptr u8 n ) EMAIL-BUF EMAIL-U @ ;
: PLAN$ ( -- ptr u8 n ) PLAN-BUF PLAN-U @ ;
: ORG$ ( -- ptr u8 n ) ORG-BUF ORG-U @ ;
: ORGNAME$ ( -- ptr u8 n ) ORGNAME-BUF ORGNAME-U @ ;

: NO-IDENTITY ( -- )
   0 EMAIL-U ! 0 PLAN-U ! 0 ORG-U ! 0 ORGNAME-U ! ;

\ ---- Claude Code ------------------------------------------------------------
: CLAUDE-PLAN ( ptr u8 n -- )
   s" claudeAiOauth" s" subscriptionType" PLAN-BUF PLAN-CAP DOC-STR2
   dup 0 < if drop 0 then PLAN-U ! ;

\ the organization tells two logins under one email apart
: CLAUDE-ORG ( ptr u8 n -- ) {: cfg cu :}
   cfg cu s" oauthAccount" s" organizationUuid" ORG-BUF 128 DOC-STR2 dup 0 < if drop 0 then ORG-U !
   cfg cu s" oauthAccount" s" organizationName" ORGNAME-BUF 128 DOC-STR2 dup 0 < if drop 0 then ORGNAME-U ! ;

\ the oauthAccount object on its own, as saved in a slot
: CLAUDE-OAUTH-IDENTITY ( ptr u8 n -- bool ) {: d du :}
   NO-IDENTITY
   d du s" emailAddress" EMAIL-BUF EMAIL-CAP DOC-STR1 dup 0 < if drop false exit then EMAIL-U !
   d du s" organizationUuid" ORG-BUF 128 DOC-STR1 dup 0 < if drop 0 then ORG-U !
   d du s" organizationName" ORGNAME-BUF 128 DOC-STR1 dup 0 < if drop 0 then ORGNAME-U !
   true ;

\ config document (.claude.json) plus credentials document
: CLAUDE-IDENTITY ( ptr u8 n ptr u8 n -- bool ) {: cfg cu cr cru :}
   NO-IDENTITY
   cfg cu s" oauthAccount" s" emailAddress" EMAIL-BUF EMAIL-CAP DOC-STR2
   dup 0 < if drop false exit then EMAIL-U !
   cfg cu CLAUDE-ORG
   cr cru CLAUDE-PLAN
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

\ an API-key login has no claims; it is saved under a fixed slot name
: CODEX-API-KEY? ( ptr u8 n -- bool ) {: d du :}
   d du s" OPENAI_API_KEY" TOK-BUF BUF-CAP DOC-STR1 0 <= if false exit then
   s" api-key" EMAIL-BUF EMAIL-U EMAIL-CAP SPAN!
   s" apikey" PLAN-BUF PLAN-U PLAN-CAP SPAN!
   true ;

\ auth.json document: identity comes from the id_token claims
: CODEX-IDENTITY ( ptr u8 n -- bool ) {: d du :}
   NO-IDENTITY
   d du s" tokens" s" id_token" TOK-BUF BUF-CAP DOC-STR2
   dup 0 < if drop d du CODEX-API-KEY? exit then {: tu :}
   TOK-BUF tu JWT-PAYLOAD OBJ-BUF BUF-CAP B64URL-DECODE OBJ-U !
   OBJ$ s" email" EMAIL-BUF EMAIL-CAP DOC-STR1
   dup 0 < if drop false exit then EMAIL-U !
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_plan_type" PLAN-BUF PLAN-CAP DOC-STR2
   dup 0 < if drop 0 then PLAN-U !
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_account_id" ORG-BUF 128 DOC-STR2
   dup 0 < if drop 0 then ORG-U !
   0 ORGNAME-U !
   true ;

;package
