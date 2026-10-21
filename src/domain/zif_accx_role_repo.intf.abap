"! <p class="shorttext synchronized">Access Explorer: role reader</p>
"! Reads without authorization checks - callers must filter with the caller guard.
INTERFACE zif_accx_role_repo PUBLIC.

  TYPES ty_roles TYPE STANDARD TABLE OF agr_name WITH EMPTY KEY.

  TYPES: BEGIN OF ty_role_info,
           role         TYPE agr_name,
           description  TYPE string,
           composite    TYPE abap_bool,
           generated    TYPE abap_bool,
           "! number of active authorization objects (breadth of the role)
           object_count TYPE i,
           "! role grants every transaction (S_TCODE *)
           broad        TYPE abap_bool,
           "! composite roles containing this role
           parents      TYPE string_table,
           "! derived roles: the reference role whose menu and authorizations are inherited
           derived_from TYPE agr_name,
           "! composite roles: the single roles they contain
           children     TYPE string_table,
         END OF ty_role_info.

  TYPES: BEGIN OF ty_org_level,
           "! organizational level variable, e.g. $BUKRS
           level TYPE string,
           low   TYPE string,
           high  TYPE string,
         END OF ty_org_level,
         ty_org_levels TYPE STANDARD TABLE OF ty_org_level WITH EMPTY KEY.

  TYPES: BEGIN OF ty_maintenance,
           "! generated profiles of the role (AGR_1016)
           profiles           TYPE string_table,
           "! active authorizations by maintenance status as PFCG shows it
           standard           TYPE i,
           maintained         TYPE i,
           changed            TYPE i,
           manual             TYPE i,
           "! inactive authorizations
           inactive           TYPE i,
           "! open fields of active authorizations, as OBJECT-FIELD
           open_fields        TYPE string_table,
           org_levels         TYPE ty_org_levels,
           "! users holding the role today whose user master lacks its profile (user comparison pending)
           comparison_pending TYPE i,
           created_by         TYPE string,
           created_on         TYPE d,
           changed_by         TYPE string,
           changed_on         TYPE d,
         END OF ty_maintenance.

  TYPES: BEGIN OF ty_authorization,
           object   TYPE xuobject,
           auth     TYPE xuauth,
           "! authorization text (AGR_1250-ATEXT)
           text     TYPE string,
           "! PFCG status: S standard, G maintained, M changed, U manual
           status   TYPE c LENGTH 1,
           inactive TYPE abap_bool,
           "! field values; an open field has one row without low and high
           values   TYPE zif_accx_critical_rules=>ty_auth_values,
         END OF ty_authorization,
         ty_authorizations TYPE STANDARD TABLE OF ty_authorization WITH EMPTY KEY.

  TYPES: BEGIN OF ty_user_count,
           role  TYPE agr_name,
           users TYPE i,
         END OF ty_user_count,
         ty_user_counts TYPE SORTED TABLE OF ty_user_count WITH UNIQUE KEY role.

  "! Single and composite roles with an active authorization that covers the
  "! check (patterns with * and value ranges are evaluated; org level
  "! placeholders $... are not resolved)
  METHODS find_roles_granting
    IMPORTING !check        TYPE zif_accx_auth_evaluator=>ty_check
    RETURNING VALUE(result) TYPE ty_roles.

  METHODS exists
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE abap_bool.

  METHODS get_role_info
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE ty_role_info.

  "! Transactions in the role menu (AGR_TCODES)
  METHODS get_transactions
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE string_table.

  "! Active authorization values of the role (AGR_1251)
  METHODS get_authorization_values
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

  "! Roles derived from the role (AGR_DEFINE-PARENT_AGR)
  METHODS get_derived_roles
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE ty_roles.

  "! Users of the user group with an assignment of the role valid today
  METHODS count_holders
    IMPORTING !role         TYPE agr_name
              !user_group   TYPE xuclass
              !exclude_user TYPE syuname OPTIONAL
    RETURNING VALUE(result) TYPE i.

  METHODS count_group_members
    IMPORTING !user_group   TYPE xuclass
              !exclude_user TYPE syuname OPTIONAL
    RETURNING VALUE(result) TYPE i.

  "! Authorization data of a role: generated profiles, maintenance status of its authorizations,
  "! open fields, organizational levels, pending user comparison, creation and last change
  METHODS get_maintenance DEFAULT IGNORE
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE ty_maintenance.

  "! All authorizations of the role with their values, inactive ones included (AGR_1250, AGR_1251),
  "! by object and authorization; optionally of one object only
  METHODS get_authorizations DEFAULT IGNORE
    IMPORTING !role         TYPE agr_name
              !object       TYPE xuobject OPTIONAL
    RETURNING VALUE(result) TYPE ty_authorizations.

  "! Roles whose name matches the pattern (* any characters, + one character), by name; at most max_count
  METHODS find_by_pattern DEFAULT IGNORE
    IMPORTING !pattern      TYPE string
              !max_count    TYPE i
    RETURNING VALUE(result) TYPE ty_roles.

  "! Authorization fields that are organizational levels (USORG)
  METHODS get_org_fields DEFAULT IGNORE
    RETURNING VALUE(result) TYPE string_table.

  "! Users with an assignment valid today (directly or through a composite role), per role;
  "! roles without such users are missing
  METHODS count_assigned_users
    IMPORTING !roles        TYPE ty_roles
    RETURNING VALUE(result) TYPE ty_user_counts.

ENDINTERFACE.
