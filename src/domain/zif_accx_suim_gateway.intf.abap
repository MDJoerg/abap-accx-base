"! <p class="shorttext synchronized">Access Explorer: SUIM report APIs</p>
"! Encapsulates the SUIM APIs (function group SUSR_SUIM_APIS). They run the
"! SUIM reports and check the caller themselves; rows the caller may not see
"! are dropped silently, so results may be incomplete.
INTERFACE zif_accx_suim_gateway PUBLIC.

  CONSTANTS: BEGIN OF co_kind,
               authorization TYPE string VALUE `authorization`,
               combination   TYPE string VALUE `combination`,
             END OF co_kind.

  "! Values per field in a search by authorization values (SUIM: value OR value)
  CONSTANTS co_max_alternatives TYPE i VALUE 2.

  " Variant of critical authorizations (kind authorization) or combinations
  TYPES: BEGIN OF ty_variant,
           kind       TYPE string,
           name       TYPE string,
           text       TYPE string,
           rule_count TYPE i,
         END OF ty_variant,
         ty_variants TYPE STANDARD TABLE OF ty_variant WITH EMPTY KEY.

  TYPES: BEGIN OF ty_finding,
           kind      TYPE string,
           "! critical authorization id or combination id
           rule      TYPE string,
           text      TYPE string,
           "! SUIM color: 6 red, 3 yellow, other
           color     TYPE c LENGTH 1,
           "! user or role
           subject   TYPE string,
           "! roles only: S single role, C composite role
           role_type TYPE c LENGTH 1,
         END OF ty_finding,
         ty_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

  TYPES: BEGIN OF ty_result,
           findings TYPE ty_findings,
           "! messages of SUIM (warnings, possibly incomplete results)
           messages TYPE string_table,
         END OF ty_result.

  "! Field of the searched authorization object with alternative values (OR, at most co_max_alternatives)
  TYPES: BEGIN OF ty_value_criterion,
           field  TYPE xufield,
           values TYPE string_table,
         END OF ty_value_criterion,
         ty_value_criteria TYPE STANDARD TABLE OF ty_value_criterion WITH EMPTY KEY.

  "! Search for users (RSUSR002); all given criteria must be met
  TYPES: BEGIN OF ty_user_query,
           users         TYPE susr_t_range_4_xubname,
           user_groups   TYPE susr_t_sel_opt_group,
           roles         TYPE susr_t_sel_opt_agr,
           profiles      TYPE susr_t_sel_opt_prof,
           "! users who may start the transaction (S_TCODE and the check object of SE93)
           transaction   TYPE tcode,
           "! users with an authorization for the object, covering the values if given
           object        TYPE xuobject,
           values        TYPE ty_value_criteria,
           unlocked_only TYPE abap_bool,
         END OF ty_user_query.

  TYPES: BEGIN OF ty_user_hit,
           user           TYPE xubname,
           name           TYPE string,
           user_type      TYPE xuustyp,
           user_group     TYPE xuclass,
           valid_from     TYPE d,
           valid_to       TYPE d,
           "! lock reason as SUIM shows it, empty if not locked
           lock           TYPE string,
           reference_user TYPE xubname,
         END OF ty_user_hit,
         ty_user_hits TYPE STANDARD TABLE OF ty_user_hit WITH EMPTY KEY.

  TYPES: BEGIN OF ty_user_result,
           users    TYPE ty_user_hits,
           messages TYPE string_table,
         END OF ty_user_result.

  "! Search for roles (RSUSR070); all given criteria must be met
  TYPES: BEGIN OF ty_role_query,
           roles        TYPE susr_t_sel_opt_agr,
           descriptions TYPE susr_t_sel_opt_ptext,
           "! roles granting the transaction (S_TCODE)
           transactions TYPE susr_t_sel_opt_xupname,
           object       TYPE xuobject,
           values       TYPE ty_value_criteria,
           "! roles assigned to these users; empty = any assignment
           users        TYPE susr_t_sel_opt_xupname,
           single       TYPE abap_bool,
           composite    TYPE abap_bool,
         END OF ty_role_query.

  TYPES: BEGIN OF ty_role_hit,
           role      TYPE agr_name,
           text      TYPE string,
           "! S single role, C composite role
           role_type TYPE c LENGTH 1,
         END OF ty_role_hit,
         ty_role_hits TYPE STANDARD TABLE OF ty_role_hit WITH EMPTY KEY.

  TYPES: BEGIN OF ty_role_result,
           roles    TYPE ty_role_hits,
           messages TYPE string_table,
         END OF ty_role_result.

  METHODS get_variants
    RETURNING VALUE(result) TYPE ty_variants.

  "! Users meeting the critical authorizations or combinations of a variant (RSUSR008_009_NEW)
  METHODS critical_users
    IMPORTING !kind        TYPE string
              !variant     TYPE string
              !users       TYPE susr_t_range_4_xubname OPTIONAL
              !user_groups TYPE susr_t_sel_opt_group OPTIONAL
              !valid_only  TYPE abap_bool DEFAULT abap_true
    RETURNING VALUE(result) TYPE ty_result
    RAISING   zcx_accx_error.

  "! Roles meeting the critical authorizations or combinations of a variant
  METHODS critical_roles
    IMPORTING !kind        TYPE string
              !variant     TYPE string
              !roles       TYPE susr_t_range_4_agr_name OPTIONAL
    RETURNING VALUE(result) TYPE ty_result
    RAISING   zcx_accx_error.

  "! Users by complex selection criteria (RSUSR002)
  METHODS find_users
    IMPORTING !query        TYPE ty_user_query
    RETURNING VALUE(result) TYPE ty_user_result
    RAISING   zcx_accx_error.

  "! Roles by complex selection criteria (RSUSR070)
  METHODS find_roles
    IMPORTING !query        TYPE ty_role_query
    RETURNING VALUE(result) TYPE ty_role_result
    RAISING   zcx_accx_error.

ENDINTERFACE.
