"! <p class="shorttext synchronized">Access Explorer tool: check_role_health</p>
"! Consistency findings over many roles (name pattern): profile not generated,
"! open fields, organizational levels without value, derived role not in sync
"! with its reference role, user comparison pending, empty composite role, role
"! without content - per role the same checks as get_role_details. Roles
"! without users today are listed separately.
CLASS zcl_accx_t_check_role_health DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `check_role_health`.
    "! roles evaluated at most per call
    CONSTANTS co_max_roles TYPE i VALUE 500.

    TYPES: BEGIN OF ty_role,
             role          TYPE string,
             role_type     TYPE string,
             users         TYPE i,
             "! held by users today: its findings affect them
             in_use        TYPE abap_bool,
             "! position of its worst finding in the severity order (1 = most severe)
             severity      TYPE i,
             findings      TYPE string_table,
             finding_codes TYPE string_table,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_count,
             code  TYPE string,
             roles TYPE i,
           END OF ty_count,
           ty_counts TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             role_pattern TYPE string,
             "! roles evaluated (displayable, matching the pattern)
             checked      TYPE i,
             "! roles with at least one finding
             with_findings TYPE i,
             "! roles per finding code (codes of get_role_details), in severity order
             counts       TYPE ty_counts,
             "! roles with findings: roles in use first, then by worst finding and users today
             roles        TYPE ty_roles,
             "! roles without users today (no finding: may be templates or prepared roles)
             unused       TYPE string_table,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! Finding codes in severity order
    METHODS severity_order
      RETURNING VALUE(result) TYPE string_table.

    METHODS rank
      IMPORTING !role         TYPE ty_role
      RETURNING VALUE(result) TYPE i.

    METHODS listed
      IMPORTING !names        TYPE string_table
                !max          TYPE i DEFAULT 15
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_check_role_health IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Check role health`
      description = |Checks many PFCG roles at once (name pattern, e.g. Z*) for consistency findings: profile not | &&
                    |generated, open fields, organizational levels without value, derived role not in sync with | &&
                    |its reference role, user comparison pending, empty composite role, role without menu and | &&
                    |authorizations. Returns counts per finding and the affected roles (roles held by users first, | &&
                    |then by severity), | &&
                    |plus the roles nobody holds today. Evaluates at most { co_max_roles } roles per call. Use it | &&
                    |for role cleanup and before audits; get_role_details shows one role in detail.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_CHECK_ROLE_HEALTH\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role_pattern`
                                      description = `Role name pattern with * (any characters) and + (one character), default Z*.`
                                      default     = `Z*`
                                      maximum     = 30 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    FIELD-SYMBOLS <found> TYPE zcl_accx_t_get_role_details=>ty_payload.

    DATA(pattern) = to_upper( condense( args->get_string( `role_pattern` ) ) ).
    IF pattern IS INITIAL.
      pattern = `Z*`.
    ENDIF.
    IF pattern CO `*+`.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `The role pattern needs at least one character besides * and +, e.g. Z* or ZFI_*.` ).
    ENDIF.
    DATA(payload) = NEW ty_payload( role_pattern = pattern ).
    result-data = payload.

    DATA(roles) = zcl_accx_domain_factory=>role_repo( )->find_by_pattern( pattern = pattern max_count = co_max_roles + 1 ).
    IF lines( roles ) > co_max_roles.
      DELETE roles FROM co_max_roles + 1.
      result-truncated = abap_true.
      APPEND |More than { co_max_roles } roles match { pattern }; only the first { co_max_roles } were checked - narrow the pattern.|
             TO result-warnings.
    ENDIF.

    DATA(details) = NEW zcl_accx_t_get_role_details( ).
    LOOP AT roles INTO DATA(role).
      IF ctx->guard( )->can_display_role( role ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      DATA(role_args) = NEW zcl_accx_args_map( ).
      role_args->set( name = `role` value = role ).
      TRY.
          DATA(detail) = details->zif_accx_tool~execute( args = role_args ctx = ctx ).
        CATCH zcx_accx_error INTO DATA(error).
          APPEND |{ role }: { error->message }| TO result-warnings.
          CONTINUE.
      ENDTRY.
      ASSIGN detail-data->* TO <found>.
      DATA(found) = <found>.
      payload->checked += 1.
      IF found-assigned_users = 0.
        APPEND found-role TO payload->unused.
      ENDIF.
      IF found-findings IS NOT INITIAL.
        DATA(entry) = VALUE ty_role( role          = found-role
                                     role_type     = found-role_type
                                     users         = found-assigned_users
                                     in_use        = xsdbool( found-assigned_users > 0 )
                                     findings      = found-findings
                                     finding_codes = found-finding_codes ).
        entry-severity = rank( entry ).
        APPEND entry TO payload->roles.
      ENDIF.
    ENDLOOP.

    payload->with_findings = lines( payload->roles ).
    LOOP AT severity_order( ) INTO DATA(code).
      DATA(count) = REDUCE i( INIT n = 0 FOR r IN payload->roles
                              NEXT n = n + COND #( WHEN line_exists( r-finding_codes[ table_line = code ] ) THEN 1 ELSE 0 ) ).
      IF count > 0.
        APPEND VALUE #( code = code roles = count ) TO payload->counts.
      ENDIF.
    ENDLOOP.

    " findings of roles in use first, then the worst finding, then users today
    SORT payload->roles BY in_use DESCENDING severity ASCENDING users DESCENDING role ASCENDING.

    result-total_count = lines( payload->roles ).
    IF lines( payload->roles ) > ctx->max_rows( ).
      DELETE payload->roles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.
    result-sources = VALUE #( ( `AGR_DEFINE (roles matching the pattern)` )
                              ( `get_role_details per role: AGR_1016, AGR_1250, AGR_1251, AGR_1252, AGR_AGRS, AGR_USERS, UST04` ) ).
    IF payload->roles IS NOT INITIAL.
      APPEND |Use get_role_details with role { payload->roles[ 1 ]-role } for the most severe case.| TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = zcl_accx_t_get_role_details=>co_finding-comparison_pending ] ).
      APPEND `Run the user comparison (PFUD, or job PFCG_TIME_DEPENDENCY) for the roles with a pending comparison.` TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = zcl_accx_t_get_role_details=>co_finding-out_of_sync ] ).
      APPEND `Use compare_roles (reference role against derived role) for the roles not in sync, then pass the reference roles on.`
             TO result-next_steps.
    ENDIF.
    IF payload->unused IS NOT INITIAL.
      APPEND `Roles without users may be templates or obsolete; get_authorization_changes and the role owner tell which.` TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD severity_order.
    result = VALUE #( ( zcl_accx_t_get_role_details=>co_finding-not_generated )
                      ( zcl_accx_t_get_role_details=>co_finding-open_fields )
                      ( zcl_accx_t_get_role_details=>co_finding-out_of_sync )
                      ( zcl_accx_t_get_role_details=>co_finding-comparison_pending )
                      ( zcl_accx_t_get_role_details=>co_finding-org_level )
                      ( zcl_accx_t_get_role_details=>co_finding-empty_composite )
                      ( zcl_accx_t_get_role_details=>co_finding-empty_role ) ).
  ENDMETHOD.

  METHOD rank.
    result = lines( severity_order( ) ) + 1.
    LOOP AT severity_order( ) INTO DATA(code).
      IF line_exists( role-finding_codes[ table_line = code ] ).
        result = sy-tabix.
        RETURN.
      ENDIF.
    ENDLOOP.
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

    result-summary = |{ <payload>-checked } roles matching **{ <payload>-role_pattern }** checked: | &&
                     |{ COND #( WHEN <payload>-with_findings = 0 THEN `no consistency findings`
                                ELSE |**{ <payload>-with_findings } with findings**| ) }, | &&
                     |{ lines( <payload>-unused ) } without users today.|.
    LOOP AT <payload>-counts INTO DATA(count).
      result-summary = |{ result-summary }\n- { count-code }: { count-roles } { COND #( WHEN count-roles = 1 THEN `role` ELSE `roles` ) }|.
    ENDLOOP.
    IF <payload>-roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Roles, in use and most severe first:**|.
      LOOP AT <payload>-roles INTO DATA(role).
        result-summary = |{ result-summary }\n- **{ role-role }** ({ role-role_type }, { role-users } users): | &&
                         |{ concat_lines_of( table = role-findings sep = ` ` ) }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-unused IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nWithout users today: { listed( <payload>-unused ) }|.
    ENDIF.
    IF result-truncated = abap_true AND lines( <payload>-roles ) < result-total_count.
      result-summary = |{ result-summary }\n\nShowing { lines( <payload>-roles ) } of { result-total_count } roles with findings - raise max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } matching roles not checked due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

