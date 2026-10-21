"! <p class="shorttext synchronized">Access Explorer tool: get_role_details</p>
"! Structure and state of one role as PFCG shows it: type, derivation,
"! composite roles, menu with launchpad content, authorization data by
"! maintenance status, open fields, organizational levels, profile, users and
"! the consistency findings (profile not generated, open fields, organizational
"! levels without value, user comparison pending, derived role not in sync with
"! its reference role, empty composite role).
CLASS zcl_accx_t_get_role_details DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_role_details`.

    CONSTANTS: BEGIN OF co_role_type,
                 single    TYPE string VALUE `single`,
                 composite TYPE string VALUE `composite`,
                 derived   TYPE string VALUE `derived`,
               END OF co_role_type.

    " Finding codes, in the order the findings are reported
    CONSTANTS: BEGIN OF co_finding,
                 empty_composite    TYPE string VALUE `empty_composite`,
                 open_fields        TYPE string VALUE `open_fields`,
                 org_level          TYPE string VALUE `org_level_empty`,
                 not_generated      TYPE string VALUE `profile_not_generated`,
                 out_of_sync        TYPE string VALUE `derived_out_of_sync`,
                 comparison_pending TYPE string VALUE `user_comparison_pending`,
                 empty_role         TYPE string VALUE `no_content`,
               END OF co_finding.

    TYPES: BEGIN OF ty_payload,
             role            TYPE string,
             description     TYPE string,
             "! single, composite or derived
             role_type       TYPE string,
             "! derived role: the reference role whose menu and authorizations it inherits
             derived_from    TYPE string,
             "! roles derived from this role
             derived_roles   TYPE string_table,
             "! composite roles containing the role
             composite_roles TYPE string_table,
             "! composite role: its single roles
             single_roles    TYPE string_table,
             "! transactions in the menu (derived roles: of the reference role)
             transactions    TYPE string_table,
             "! launchpad catalogs, groups and spaces in the menu
             catalogs        TYPE string_table,
             groups          TYPE string_table,
             spaces          TYPE string_table,
             "! active authorization objects
             object_count    TYPE i,
             "! S_TCODE allows every transaction
             all_transactions TYPE abap_bool,
             profile_generated TYPE abap_bool,
             maintenance     TYPE zif_accx_role_repo=>ty_maintenance,
             "! users holding the role today (directly or through a composite role)
             assigned_users  TYPE i,
             "! derived role: authorization values only in the reference role (only_a) or only in this role
             "! (only_b), organizational level fields aside
             reference_diff  TYPE zcl_accx_role_diff=>ty_diff,
             "! consistency findings, worst first
             findings        TYPE string_table,
             "! codes of the findings (co_finding), same order
             finding_codes   TYPE string_table,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! Role names the caller may display; the others are counted as hidden
    METHODS visible
      IMPORTING !roles        TYPE string_table
                !ctx          TYPE REF TO zif_accx_context
      CHANGING  !result       TYPE zif_accx_types=>ty_result
      RETURNING VALUE(names)  TYPE string_table.

    METHODS findings
      CHANGING !payload TYPE ty_payload.

    METHODS add_finding
      IMPORTING !code    TYPE string
                !text    TYPE string
      CHANGING  !payload TYPE ty_payload.

    METHODS listed
      IMPORTING !names        TYPE string_table
                !max          TYPE i DEFAULT 15
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_role_details IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get role details`
      description = |Shows one PFCG role: type (single, composite, derived), reference role and derived roles, | &&
                    |composite roles containing it or its single roles, the menu (transactions, launchpad catalogs, | &&
                    |groups, spaces), the authorization data by maintenance status (standard, maintained, changed, | &&
                    |manual, inactive), open fields, organizational levels, generated profile, creation and last | &&
                    |change, the number of users holding it today, and consistency findings: profile not generated, | &&
                    |open fields, organizational levels without value, user comparison pending, derived role not in | &&
                    |sync with its reference role, empty composite role. Use it to understand a role before changing or assigning it, or to check why a role does | &&
                    |not work as expected.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_ROLE_DETAILS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role`
                                      description = `Role name, e.g. Z_FI_AP_CLERK (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 30 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(role) = CONV agr_name( to_upper( condense( args->get_string( `role` ) ) ) ).
    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    IF repo->exists( role ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Role { role } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_role( role ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display role { role } (S_USER_AGR, activity 03).| ).
    ENDIF.

    DATA(info) = repo->get_role_info( role ).
    DATA(payload) = NEW ty_payload( role              = CONV #( role )
                                    description       = info-description
                                    role_type         = COND #( WHEN info-composite = abap_true THEN co_role_type-composite
                                                                WHEN info-derived_from IS NOT INITIAL THEN co_role_type-derived
                                                                ELSE co_role_type-single )
                                    derived_from      = CONV #( info-derived_from )
                                    object_count      = info-object_count
                                    all_transactions  = info-broad
                                    profile_generated = info-generated ).
    result-data = payload.
    payload->composite_roles = visible( EXPORTING roles = info-parents ctx = ctx CHANGING result = result ).
    payload->single_roles    = visible( EXPORTING roles = info-children ctx = ctx CHANGING result = result ).
    payload->derived_roles   = visible( EXPORTING roles = VALUE #( FOR d IN repo->get_derived_roles( role ) ( CONV #( d ) ) )
                                                  ctx   = ctx
                                        CHANGING  result = result ).
    DATA(counts) = repo->count_assigned_users( VALUE #( ( role ) ) ).
    payload->assigned_users = VALUE #( counts[ role = role ]-users OPTIONAL ).

    IF info-composite = abap_false.
      " derived roles have no menu of their own; PFCG shows the menu of the reference role
      DATA(menu_role) = COND agr_name( WHEN info-derived_from IS NOT INITIAL THEN info-derived_from ELSE role ).
      payload->transactions = repo->get_transactions( menu_role ).
      LOOP AT zcl_accx_domain_factory=>fiori_repo( )->get_role_content( VALUE #( ( menu_role ) ) ) INTO DATA(content).
        CASE content-type.
          WHEN zif_accx_fiori_repo=>co_content_type-catalog.
            APPEND content-id TO payload->catalogs.
          WHEN zif_accx_fiori_repo=>co_content_type-group.
            APPEND content-id TO payload->groups.
          WHEN zif_accx_fiori_repo=>co_content_type-flp_space.
            APPEND |{ content-id }{ COND #( WHEN content-template = abap_true THEN ` (template)` ) }| TO payload->spaces.
        ENDCASE.
      ENDLOOP.
      payload->maintenance = repo->get_maintenance( role ).
      IF info-derived_from IS NOT INITIAL.
        DATA(org_fields) = repo->get_org_fields( ).
        payload->reference_diff = zcl_accx_role_diff=>diff(
          a = zcl_accx_role_diff=>value_set( values = repo->get_authorization_values( info-derived_from ) skip_fields = org_fields )
          b = zcl_accx_role_diff=>value_set( values = repo->get_authorization_values( role ) skip_fields = org_fields ) ).
      ENDIF.
    ENDIF.
    findings( CHANGING payload = payload->* ).

    result-total_count = lines( payload->transactions ).
    result-sources = VALUE #( ( `AGR_DEFINE, AGR_TEXTS, AGR_AGRS, AGR_FLAGS (role)` )
                              ( `AGR_TCODES, AGR_HIER, AGR_BUFFI (menu, launchpad content)` )
                              ( `AGR_1250, AGR_1251, AGR_1252, AGR_1016 (authorization data, profile)` )
                              ( `AGR_USERS, UST04 (users, user comparison)` ) ).
    IF line_exists( payload->finding_codes[ table_line = co_finding-out_of_sync ] ).
      APPEND |Use compare_roles with role_a { info-derived_from } and role_b { role } for the differences; | &&
             |pass the reference role on to its derived roles (PFCG: generate derived roles, or any apply_role_change | &&
             |on { info-derived_from }).| TO result-next_steps.
    ENDIF.
    IF line_exists( payload->finding_codes[ table_line = co_finding-open_fields ] )
       OR line_exists( payload->finding_codes[ table_line = co_finding-org_level ] )
       OR line_exists( payload->finding_codes[ table_line = co_finding-not_generated ] )
       OR line_exists( payload->finding_codes[ table_line = co_finding-comparison_pending ] ).
      APPEND |Fix the findings in PFCG, role { COND #( WHEN info-derived_from IS NOT INITIAL AND payload->maintenance-open_fields IS INITIAL
                                                        THEN info-derived_from ELSE role ) }| &&
             |{ COND #( WHEN payload->maintenance-comparison_pending > 0 THEN `, and run the user comparison (PFUD)` ) }; | &&
             |apply_role_change can fill open fields.| TO result-next_steps.
    ENDIF.
    IF payload->assigned_users > 0.
      APPEND |Use find_users with role { role } to see who holds it.| TO result-next_steps.
    ENDIF.
    APPEND |Use run_critical_access_check (scope roles, role { role }) for the critical authorizations it grants.| TO result-next_steps.
  ENDMETHOD.

  METHOD visible.
    LOOP AT roles INTO DATA(name).
      IF ctx->guard( )->can_display_role( CONV #( name ) ) = abap_true.
        APPEND name TO names.
      ELSE.
        result-hidden_by_authorization += 1.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD findings.
    DATA(maintenance) = payload-maintenance.
    IF payload-role_type = co_role_type-composite.
      IF payload-single_roles IS INITIAL.
        add_finding( EXPORTING code = co_finding-empty_composite text = `Composite role without single roles: it grants nothing.`
                     CHANGING  payload = payload ).
      ENDIF.
      RETURN.
    ENDIF.
    IF maintenance-open_fields IS NOT INITIAL.
      add_finding( EXPORTING code    = co_finding-open_fields
                             text    = |{ lines( maintenance-open_fields ) } open { COND #( WHEN lines( maintenance-open_fields ) = 1 THEN `field` ELSE `fields` ) } | &&
                                       |(the profile cannot be generated while they are open): { listed( maintenance-open_fields ) }|
                   CHANGING  payload = payload ).
    ENDIF.
    LOOP AT maintenance-org_levels INTO DATA(level) WHERE low IS INITIAL AND high IS INITIAL.
      add_finding( EXPORTING code = co_finding-org_level text = |Organizational level { level-level } has no value.|
                   CHANGING  payload = payload ).
    ENDLOOP.
    IF payload-profile_generated = abap_false AND ( payload-object_count > 0 OR payload-transactions IS NOT INITIAL ).
      add_finding( EXPORTING code = co_finding-not_generated text = `Profile not generated: the users get none of its authorizations.`
                   CHANGING  payload = payload ).
    ENDIF.
    DATA(diff) = payload-reference_diff.
    IF diff-only_a IS NOT INITIAL OR diff-only_b IS NOT INITIAL.
      add_finding( EXPORTING code    = co_finding-out_of_sync
                             text    = |Not in sync with reference role { payload-derived_from }: values only in the reference role { lines( diff-only_a ) }, | &&
                                       |only in this role { lines( diff-only_b ) } (e.g. | &&
                                       |{ COND #( WHEN diff-only_a IS NOT INITIAL THEN diff-only_a[ 1 ] ELSE diff-only_b[ 1 ] ) }).|
                   CHANGING  payload = payload ).
    ENDIF.
    IF maintenance-comparison_pending > 0.
      add_finding( EXPORTING code    = co_finding-comparison_pending
                             text    = |User comparison pending: { maintenance-comparison_pending } of { payload-assigned_users } users holding the role lack | &&
                                       |its profile in their user master.|
                   CHANGING  payload = payload ).
    ENDIF.
    IF payload-object_count = 0 AND payload-transactions IS INITIAL AND payload-catalogs IS INITIAL.
      add_finding( EXPORTING code = co_finding-empty_role text = `The role has neither menu entries nor authorizations.`
                   CHANGING  payload = payload ).
    ENDIF.
  ENDMETHOD.

  METHOD add_finding.
    APPEND text TO payload-findings.
    APPEND code TO payload-finding_codes.
  ENDMETHOD.

  METHOD listed.
    LOOP AT names INTO DATA(name) TO max.
      result = |{ result }{ COND #( WHEN sy-tabix > 1 THEN `, ` ) }{ name }|.
    ENDLOOP.
    IF lines( names ) > max.
      result = |{ result } and { lines( names ) - max } more|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    DATA(m) = <payload>-maintenance.

    result-summary = |Role **{ <payload>-role }**{ COND #( WHEN <payload>-description IS NOT INITIAL THEN | ({ <payload>-description })| ) }: | &&
                     |{ COND #( WHEN <payload>-derived_from IS NOT INITIAL THEN |role derived from { <payload>-derived_from }|
                                ELSE |{ <payload>-role_type } role| ) }, | &&
                     |{ <payload>-assigned_users } { COND #( WHEN <payload>-assigned_users = 1 THEN `user` ELSE `users` ) } today.|.
    IF <payload>-single_roles IS NOT INITIAL OR <payload>-role_type = co_role_type-composite.
      result-summary = |{ result-summary }\n- Single roles: { COND #( WHEN <payload>-single_roles IS INITIAL THEN `none`
                                                                     ELSE listed( <payload>-single_roles ) ) }|.
    ENDIF.
    IF <payload>-composite_roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n- Contained in composite roles: { listed( <payload>-composite_roles ) }|.
    ENDIF.
    IF <payload>-derived_roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n- Derived roles: { listed( <payload>-derived_roles ) }|.
    ENDIF.
    IF <payload>-role_type <> co_role_type-composite.
      result-summary = |{ result-summary }\n- Menu{ COND #( WHEN <payload>-derived_from IS NOT INITIAL
                                                           THEN | (of { <payload>-derived_from })| ) }: | &&
                       |{ lines( <payload>-transactions ) } { COND #( WHEN lines( <payload>-transactions ) = 1 THEN `transaction` ELSE `transactions` ) }| &&
                       |{ COND #( WHEN <payload>-transactions IS NOT INITIAL THEN | ({ listed( <payload>-transactions ) })| ) }| &&
                       |{ COND #( WHEN <payload>-catalogs IS NOT INITIAL THEN |; catalogs { listed( <payload>-catalogs ) }| ) }| &&
                       |{ COND #( WHEN <payload>-groups IS NOT INITIAL THEN |; groups { listed( <payload>-groups ) }| ) }| &&
                       |{ COND #( WHEN <payload>-spaces IS NOT INITIAL THEN |; spaces { listed( <payload>-spaces ) }| ) }|.
      result-summary = |{ result-summary }\n- Authorizations: { <payload>-object_count } objects; { m-standard } standard, | &&
                       |{ m-maintained } maintained, { m-changed } changed, { m-manual } manual, { m-inactive } inactive| &&
                       |{ COND #( WHEN <payload>-all_transactions = abap_true THEN `; S_TCODE allows **every transaction**` ) }|.
      IF m-org_levels IS NOT INITIAL.
        result-summary = |{ result-summary }\n- Organizational levels: { concat_lines_of( sep = `, ` table = VALUE string_table(
                           FOR l IN m-org_levels ( |{ l-level }={ COND #( WHEN l-low IS INITIAL AND l-high IS INITIAL THEN `(empty)` ELSE l-low ) }| &&
                                                   |{ COND #( WHEN l-high IS NOT INITIAL THEN |-{ l-high }| ) }| ) ) ) }|.
      ENDIF.
      result-summary = |{ result-summary }\n- Profile: { COND #( WHEN m-profiles IS INITIAL THEN `none`
                                                                ELSE concat_lines_of( table = m-profiles sep = `, ` ) ) }, | &&
                       |{ COND #( WHEN <payload>-profile_generated = abap_true THEN `generated` ELSE `**not generated**` ) }| &&
                       |{ COND #( WHEN m-changed_by IS NOT INITIAL THEN |; last changed by { m-changed_by } on { m-changed_on DATE = ISO }|
                                  WHEN m-created_by IS NOT INITIAL THEN |; created by { m-created_by } on { m-created_on DATE = ISO }| ) }|.
    ENDIF.
    IF <payload>-findings IS INITIAL.
      result-summary = |{ result-summary }\n\nNo consistency findings.|.
    ELSE.
      result-summary = |{ result-summary }\n\n**Findings:**|.
      LOOP AT <payload>-findings INTO DATA(finding).
        result-summary = |{ result-summary }\n- { finding }|.
      ENDLOOP.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } related roles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

