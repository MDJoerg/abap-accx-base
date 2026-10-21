"! <p class="shorttext synchronized">Access Explorer tool: find_users</p>
"! Users by role, profile, transaction or authorization values, via the SUIM
"! API of report RSUSR002 (users by complex selection criteria). RSUSR002
"! ignores the validity of role assignments; with a role criterion, users
"! whose matching assignment is not valid today are left out here.
CLASS zcl_accx_t_find_users DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_user,
             user           TYPE string,
             name           TYPE string,
             user_type      TYPE string,
             user_group     TYPE string,
             valid_from     TYPE d,
             valid_to       TYPE d,
             locked         TYPE abap_bool,
             lock_reason    TYPE string,
             reference_user TYPE string,
           END OF ty_user,
           ty_users TYPE STANDARD TABLE OF ty_user WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             "! the search criteria in words
             criteria                 TYPE string,
             users                    TYPE ty_users,
             "! users left out because they are not valid today (valid_users_only)
             not_valid_today          TYPE i,
             "! users left out because their assignment of the searched role is not valid today
             role_assignment_inactive TYPE i,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `find_users`.
    CONSTANTS co_listed_in_summary TYPE i VALUE 25.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS user_type_text
      IMPORTING !user_type    TYPE xuustyp
      RETURNING VALUE(result) TYPE string.

    "! Does the user hold a role matching the pattern today?
    METHODS holds_role_today
      IMPORTING !user         TYPE xubname
                !role         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_t_find_users IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Find users`
      description = |Finds users who hold a role or profile, may start a transaction, or hold an authorization | &&
                    |covering given field values (SUIM report RSUSR002, users by complex selection criteria). | &&
                    |All given criteria must be met. Authorization values are evaluated as in SUIM: a user is found | &&
                    |if one of his authorizations allows the value (also through * or ranges). Typical questions: | &&
                    |"who may change tables of group SC" (object S_TABU_DIS, values ACTVT=02, DICBERCLS=SC), | &&
                    |"who may start SU01", "who has role X". SUIM leaves out users you may not display.|
      group       = zif_accx_types=>co_group-user
      read_only   = abap_true
      idempotent  = abap_true
      long_running = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-personal
      output_type = `\CLASS=ZCL_ACCX_T_FIND_USERS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `transaction`
                                      description = `Users who may start this transaction (S_TCODE and the check object of SE93).`
                                      maximum     = 20 ) )
                             ( param( name        = `object`
                                      description = `Users with an authorization for this authorization object, e.g. S_TABU_DIS.`
                                      maximum     = 10 ) )
                             ( param( name        = `values`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |With object: field values the authorization must allow, as FIELD=VALUE, e.g. | &&
                                                    |ACTVT=02. Give a field twice for alternatives (OR, max. 2 per field).| ) )
                             ( param( name        = `role`
                                      description = `Users with an assignment of this role valid today (pattern with * allowed).`
                                      maximum     = 30 ) )
                             ( param( name        = `profile`
                                      description = `Users with this profile, e.g. SAP_ALL (pattern with * allowed).`
                                      maximum     = 12 ) )
                             ( param( name        = `user`
                                      description = `Restrict to user IDs, pattern with * allowed, e.g. ACCX*.`
                                      maximum     = 12 ) )
                             ( param( name        = `user_group`
                                      description = `Restrict to a user group (authorization check group).`
                                      maximum     = 12 ) )
                             ( param( name        = `exclude_locked`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `Leave out locked users (default false).` ) )
                             ( param( name        = `valid_users_only`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `Only users valid today (default true).` ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA query TYPE zif_accx_suim_gateway=>ty_user_query.
    DATA words TYPE string_table.

    DATA(transaction) = to_upper( condense( args->get_string( `transaction` ) ) ).
    DATA(object)      = to_upper( condense( args->get_string( `object` ) ) ).
    DATA(role)        = to_upper( condense( args->get_string( `role` ) ) ).
    DATA(profile)     = to_upper( condense( args->get_string( `profile` ) ) ).
    DATA(user)        = to_upper( condense( args->get_string( `user` ) ) ).
    DATA(user_group)  = to_upper( condense( args->get_string( `user_group` ) ) ).
    DATA(valid_only)  = args->get_boolean( name = `valid_users_only` default = abap_true ).
    query-unlocked_only = args->get_boolean( name = `exclude_locked` default = abap_false ).
    query-values = zcl_accx_search_criteria=>value_criteria( args->get_strings( `values` ) ).

    IF query-values IS NOT INITIAL AND object IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `values need the authorization object they belong to (parameter object).` ).
    ENDIF.
    IF transaction IS INITIAL AND object IS INITIAL AND role IS INITIAL AND profile IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = `Give at least one of transaction, object, role or profile; for a single user use get_user_profile.` ).
    ENDIF.
    IF transaction IS NOT INITIAL AND zcl_accx_domain_factory=>auth_evaluator( )->transaction_exists( CONV #( transaction ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Transaction { transaction } does not exist.| ).
    ENDIF.
    IF object IS NOT INITIAL AND zcl_accx_domain_factory=>auth_evaluator( )->object_exists( CONV #( object ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Authorization object { object } does not exist.| ).
    ENDIF.

    query-transaction = transaction.
    query-object      = object.
    IF role IS NOT INITIAL.
      APPEND INITIAL LINE TO query-roles ASSIGNING FIELD-SYMBOL(<role>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = role IMPORTING sign = <role>-sign option = <role>-option low = <role>-low ).
      APPEND |with role { role }| TO words.
    ENDIF.
    IF profile IS NOT INITIAL.
      APPEND INITIAL LINE TO query-profiles ASSIGNING FIELD-SYMBOL(<profile>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = profile IMPORTING sign = <profile>-sign option = <profile>-option low = <profile>-low ).
      APPEND |with profile { profile }| TO words.
    ENDIF.
    IF transaction IS NOT INITIAL.
      APPEND |who may start transaction { transaction }| TO words.
    ENDIF.
    IF object IS NOT INITIAL.
      APPEND |with authorization { zcl_accx_search_criteria=>describe_values( object = object criteria = query-values ) }| TO words.
    ENDIF.
    IF user IS NOT INITIAL.
      APPEND INITIAL LINE TO query-users ASSIGNING FIELD-SYMBOL(<user>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = user IMPORTING sign = <user>-sign option = <user>-option low = <user>-low ).
      APPEND |among users { user }| TO words.
    ENDIF.
    IF user_group IS NOT INITIAL.
      APPEND INITIAL LINE TO query-user_groups ASSIGNING FIELD-SYMBOL(<group>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = user_group IMPORTING sign = <group>-sign option = <group>-option low = <group>-low ).
      APPEND |in user group { user_group }| TO words.
    ENDIF.
    IF query-unlocked_only = abap_true.
      APPEND `not locked` TO words.
    ENDIF.

    DATA(found) = zcl_accx_domain_factory=>suim_gateway( )->find_users( query ).
    APPEND LINES OF found-messages TO result-warnings.

    DATA(payload) = NEW ty_payload( criteria = concat_lines_of( table = words sep = `, ` ) ).
    result-data = payload.
    LOOP AT found-users INTO DATA(hit).
      IF valid_only = abap_true
         AND ( hit-valid_from > sy-datum OR ( hit-valid_to IS NOT INITIAL AND hit-valid_to < sy-datum ) ).
        payload->not_valid_today += 1.
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_user( hit-user ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      IF role IS NOT INITIAL AND holds_role_today( user = hit-user role = role ) = abap_false.
        payload->role_assignment_inactive += 1.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( user           = hit-user
                      " SUIM shows the user ID when no name is maintained
                      name           = COND #( WHEN hit-name <> hit-user THEN hit-name )
                      user_type      = user_type_text( hit-user_type )
                      user_group     = hit-user_group
                      valid_from     = hit-valid_from
                      valid_to       = hit-valid_to
                      locked         = xsdbool( hit-lock IS NOT INITIAL )
                      lock_reason    = hit-lock
                      reference_user = hit-reference_user ) TO payload->users.
    ENDLOOP.
    SORT payload->users BY user.

    result-total_count = lines( payload->users ).
    IF lines( payload->users ) > ctx->max_rows( ).
      DELETE payload->users FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `SUSR_SUIM_API_RSUSR002 (SUIM RSUSR002, users by complex selection criteria)` ) ).
    IF role IS NOT INITIAL.
      APPEND `AGR_USERS (validity of the role assignment)` TO result-sources.
    ENDIF.
    IF payload->users IS NOT INITIAL.
      IF object IS NOT INITIAL OR transaction IS NOT INITIAL.
        APPEND |Use find_roles with the same transaction or object values to see which roles grant this access.| TO result-next_steps.
      ENDIF.
      APPEND |Use get_user_profile for { payload->users[ 1 ]-user } to see the roles and profiles of a listed user.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD holds_role_today.
    LOOP AT zcl_accx_domain_factory=>user_repo( )->get_role_assignments( user ) INTO DATA(assignment) WHERE active = abap_true.
      IF ( role CA '*' AND assignment-role CP role ) OR assignment-role = role.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD user_type_text.
    result = SWITCH #( user_type
                       WHEN 'A' THEN `dialog`
                       WHEN 'B' THEN `system`
                       WHEN 'C' THEN `communication`
                       WHEN 'L' THEN `reference`
                       WHEN 'S' THEN `service`
                       ELSE user_type ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    IF <payload>-users IS INITIAL.
      result-summary = |No users found { <payload>-criteria }.|.
    ELSE.
      result-summary = |**{ result-total_count }** { COND #( WHEN result-total_count = 1 THEN `user` ELSE `users` ) } | &&
                       |{ <payload>-criteria }:|.
      LOOP AT <payload>-users INTO DATA(user) TO co_listed_in_summary.
        result-summary = |{ result-summary }\n- **{ user-user }**{ COND #( WHEN user-name IS NOT INITIAL THEN | ({ user-name })| ) }, | &&
                         |{ user-user_type }{ COND #( WHEN user-user_group IS NOT INITIAL THEN |, group { user-user_group }| ) }| &&
                         |{ COND #( WHEN user-locked = abap_true THEN |, **locked** ({ user-lock_reason })| ) }| &&
                         |{ COND #( WHEN user-valid_to IS NOT INITIAL THEN |, valid to { user-valid_to DATE = ISO }| ) }| &&
                         |{ COND #( WHEN user-reference_user IS NOT INITIAL THEN |, reference user { user-reference_user }| ) }|.
      ENDLOOP.
      IF lines( <payload>-users ) > co_listed_in_summary.
        result-summary = |{ result-summary }\n- ... { lines( <payload>-users ) - co_listed_in_summary } more in the structured result|.
      ENDIF.
    ENDIF.
    IF <payload>-not_valid_today > 0.
      result-summary = |{ result-summary }\n\n{ <payload>-not_valid_today } { COND #( WHEN <payload>-not_valid_today = 1
                       THEN `user that is` ELSE `users that are` ) } not valid today left out.|.
    ENDIF.
    IF <payload>-role_assignment_inactive > 0.
      result-summary = |{ result-summary }\n\n{ <payload>-role_assignment_inactive } { COND #( WHEN <payload>-role_assignment_inactive = 1
                       THEN `user` ELSE `users` ) } left out whose assignment of the role is not valid today (expired or future).|.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList truncated to max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } { COND #( WHEN result-hidden_by_authorization = 1
                       THEN `user` ELSE `users` ) } hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
