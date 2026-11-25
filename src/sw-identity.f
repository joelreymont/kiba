split-str
\ sw-identity.f - the email and plan of a login, live or saved.
require ../src/sw-json.f
require ../src/sw-base.f
require ../src/sw-io.f
require src/lib/adt/option.f
require src/lib/prelude.f
require src/lib/string.f
require src/lib/base64.f
require src/lib/span.f

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

\ one row of every buffer and one lens record, per identity
2 constant ID-COUNT

\ the byte lengths of an identity's email, plan and organization
STRUCTURE lens DERIVE addr FIELD email n FIELD plan n FIELD org n ;STRUCTURE

create EMAIL-BUF ID-COUNT EMAIL-CAP * allot
create PLAN-BUF ID-COUNT PLAN-CAP * allot
create ORG-BUF ID-COUNT ORG-CAP * allot       \ organization or account id
ID-COUNT TYPED-BUFFER ID-LENS lens

: EMAIL-ROW ( n -- ^u8 ) EMAIL-BUF swap EMAIL-CAP * + ;
: PLAN-ROW ( n -- ^u8 ) PLAN-BUF swap PLAN-CAP * + ;
: ORG-ROW ( n -- ^u8 ) ORG-BUF swap ORG-CAP * + ;

\ a field DOC-STR1 or DOC-STR2 could not read is empty, not -1 bytes long
: LEN! ( n ^n -- ) {: len p :} len 0 max p ! ;

public

: EMAIL$ ( n -- ^u8 n ) {: id :} id EMAIL-ROW id ID-LENS LENS-EMAIL @ ;
: PLAN$ ( n -- ^u8 n ) {: id :} id PLAN-ROW id ID-LENS LENS-PLAN @ ;
: ORG$ ( n -- ^u8 n ) {: id :} id ORG-ROW id ID-LENS LENS-ORG @ ;

\ one identity cleared to empty: no login is known yet
: NO-IDENTITY ( n -- ) {: id :}
   0 0 0 LENS-MAKE id ID-LENS ! ;

\ ---- reading a login ---------------------------------------------------------
\ A login that must be read is checked with CHECK-FIELDS, so a document it
\ refuses throws; one that may be unreadable is checked with FIELDS?, which
\ answers false instead.
private

\ ---- Claude Code ------------------------------------------------------------
\ credentials FIELDS? refuses name no plan; false then
: PLAN-READ? ( ^u8 n n -- bool ) {: cr cru id :}
   cr cru FIELDS? 0= if false exit then
   cr cru s" claudeAiOauth" s" subscriptionType" id PLAN-ROW PLAN-CAP DOC-STR2
   id ID-LENS LENS-PLAN LEN!
   true ;

public

\ the credentials' plan; empty when FIELDS? refuses them or they lack the
\ string, since the account comes from the config alone; a plan longer than
\ PLAN-CAP is E-SW-CAPACITY
: CLAUDE-PLAN ( ^u8 n n -- ) {: cr cru id :}
   cr cru id PLAN-READ? 0= if 0 id ID-LENS LENS-PLAN LEN! then ;

\ the oauthAccount object on its own, as saved in a slot; E-SW-JSON unless
\ CHECK-FIELDS takes it and it names an email
: CLAUDE-OAUTH-IDENTITY ( ^u8 n n -- ) {: d du id :}
   id NO-IDENTITY
   d du CHECK-FIELDS
   d du s" emailAddress" id EMAIL-ROW EMAIL-CAP DOC-STR1
   dup 0 <= if E-SW-JSON throw then id ID-LENS LENS-EMAIL LEN!
   d du s" organizationUuid" id ORG-ROW ORG-CAP DOC-STR1 id ID-LENS LENS-ORG LEN! ;

private

\ config document (.claude.json) plus credentials document; the config is
\ checked with CHECK-OBJECT; answers the oauthAccount object in cfg, and
\ false with an empty span when it holds none
: CLAUDE-ACCOUNT ( ^u8 n ^u8 n n -- ^u8 n bool )
   {: cfg cu cr cru id :}
   id NO-IDENTITY
   cfg cu CHECK-OBJECT
   cfg cu s" oauthAccount" DOC-OBJ-SPAN? 0= if
      2drop cfg 0 false exit
   then {: off len :}
   cfg off + len {: pa pu :}
   pa pu id CLAUDE-OAUTH-IDENTITY
   cr cru id CLAUDE-PLAN
   pa pu true ;

public

\ CLAUDE-ACCOUNT's identity alone: false when the config holds no
\ oauthAccount object
: CLAUDE-IDENTITY ( ^u8 n ^u8 n n -- bool )
   CLAUDE-ACCOUNT nip nip ;

\ ---- Codex ------------------------------------------------------------------
: JWT-PAYLOAD ( ^u8 n -- ^u8 n ) {: t tu :}
   t tu $2E STR:INDEX-OF MATCH option
     none OF E-SW-JSON throw ENDOF
     some OF IDX>N ENDOF
   ;MATCH {: d1 :}
   t d1 1+ + tu d1 1+ - {: r ru :}
   r ru $2E STR:INDEX-OF MATCH option
     none OF E-SW-JSON throw ENDOF
     some OF IDX>N ENDOF
   ;MATCH {: d2 :}
   r d2 ;

private

: PAD-END? ( ^u8 n -- bool ) {: a u :}
   u 0= if false exit then
   a u + 1- c@ EQUALS = ;

: UNPADDED ( ^u8 n -- ^u8 n )
   2 0 do 2dup PAD-END? if 1- then loop ;

public

\ OBJ = the decoded JWT payload; up to two trailing `=` are dropped first.
\ The decoder refuses unused low bits that are not zero, which conforming
\ encoders never write (RFC 4648 section 3.5). Its E-BASE64 codes reach
\ callers
: DECODE-PAYLOAD ( ^u8 n -- ) UNPADDED OBJ-BUF BUF-CAP SPAN:MAKE BASE64:DECODE-URL OBJ-U ! ;

\ OPENAI_API_KEY is a non-empty string in a document FIELDS? takes
: CODEX-API-KEY? ( ^u8 n -- bool ) {: d du :}
   d du FIELDS? 0= if false exit then
   d du s" OPENAI_API_KEY" TOK-BUF BUF-CAP DOC-STR1 0 > ;

\ an API-key login has no claims; it is saved under a fixed slot name
: CODEX-API-IDENTITY ( ^u8 n n -- bool ) {: d du id :}
   d du CODEX-API-KEY? 0= if false exit then
   s" api-key" id EMAIL-ROW id ID-LENS LENS-EMAIL EMAIL-CAP SPAN!
   s" apikey" id PLAN-ROW id ID-LENS LENS-PLAN PLAN-CAP SPAN!
   true ;

\ the auth.json document, its identity from the id_token claims; E-SW-JSON
\ unless CHECK-FIELDS takes the document and the claims and they name an
\ email
: CODEX-IDENTITY ( ^u8 n n -- bool ) {: d du id :}
   id NO-IDENTITY
   d du CHECK-FIELDS
   d du s" tokens" s" id_token" TOK-BUF BUF-CAP DOC-STR2
   dup 0 < if drop d du id CODEX-API-IDENTITY exit then {: tu :}
   TOK-BUF tu JWT-PAYLOAD DECODE-PAYLOAD
   OBJ$ CHECK-FIELDS
   OBJ$ s" email" id EMAIL-ROW EMAIL-CAP DOC-STR1
   dup 0 <= if E-SW-JSON throw then id ID-LENS LENS-EMAIL LEN!
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_plan_type" id PLAN-ROW PLAN-CAP DOC-STR2 id ID-LENS LENS-PLAN LEN!
   OBJ$ s" https://api.openai.com/auth" s" chatgpt_account_id" id ORG-ROW ORG-CAP DOC-STR2 id ID-LENS LENS-ORG LEN!
   true ;

;package
