"! <p class="shorttext synchronized">Access Explorer tool: find_roles</p>
"! Roles by name, description, transaction, authorization values or user
"! assignment, via the SUIM API of report RSUSR070 (roles by complex
"! selection criteria), with the number of users holding each role today.
CLASS zcl_accx_t_find_roles DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_role,
             role           TYPE string,
             description    TYPE string,
             "! single or composite
             role_type      TYPE string,
             "! users with an assignment valid today (directly or through a composite role)
             assigned_users TYPE i,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             "! the search criteria in words
             criteria TYPE string,
             roles    TYPE ty_roles,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `find_roles`.
    CONSTANTS co_listed_in_summary TYPE i VALUE 25.

    CONSTANTS: BEGIN OF co_role_type,
                 any       TYPE string VALUE `any`,
                 single    TYPE string VALUE `single`,
                 composite TYPE string VALUE `composite`,
               END OF co_role_type.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

ENDCLASS.

CLASS zcl_accx_t_find_roles IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Find roles`
      description = |Finds roles by name or description, by a transaction they grant, by authorization values they | &&
                    |allow, or by the users they are assigned to (SUIM report RSUSR070, roles by complex selection | &&
                    |criteria). All given criteria must be met. Authorization values are evaluated as in SUIM (also * | &&
                    |and ranges). Each role comes with the number of users holding it today. Typical questions: "which | &&
                    |roles allow debugging with replace" (object S_DEVELOP, values OBJTYPE=DEBUG, ACTVT=02), "which roles | &&
                    |contain SM37", "which roles does user X have". SUIM leaves out roles you may not display.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      long_running = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_FIND_ROLES\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role`
                                      description = `Role name or pattern with *, e.g. Z_FI*.`
                                      maximum     = 30 ) )
                             ( param( name        = `description`
                                      description = `Text in the role description; * patterns allowed, otherwise searched as part of the text.`
                                      maximum     = 80 ) )
                             ( param( name        = `transaction`
                                      description = `Roles granting this transaction in S_TCODE (pattern with * allowed).`
                                      maximum     = 20 ) )
                             ( param( name        = `object`
                                      description = `Roles with an authorization for this authorization object, e.g. S_DEVELOP.`
                                      maximum     = 10 ) )
                             ( param( name        = `values`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |With object: field values the authorization must allow, as FIELD=VALUE, e.g. | &&
                                                    |ACTVT=02. Give a field twice for alternatives (OR, max. 2 per field).| ) )
                             ( param( name        = `assigned_to_user`
                                      description = `Roles assigned to this user (pattern with * allowed).`
                                      maximum     = 12 ) )
                             ( param( name        = `role_type`
                                      description = `single, composite or any (default).`
                                      enum        = VALUE #( ( co_role_type-any ) ( co_role_type-single ) ( co_role_type-composite ) ) ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA query TYPE zif_accx_suim_gateway=>ty_role_query.
    DATA words TYPE string_table.
    DATA names TYPE zif_accx_role_repo=>ty_roles.

    DATA(role)        = to_upper( condense( args->get_string( `role` ) ) ).
    DATA(description) = condense( args->get_string( `description` ) ).
    DATA(transaction) = to_upper( condense( args->get_string( `transaction` ) ) ).
    DATA(object)      = to_upper( condense( args->get_string( `object` ) ) ).
    DATA(user)        = to_upper( condense( args->get_string( `assigned_to_user` ) ) ).
    DATA(role_type)   = COND string( WHEN args->has( `role_type` ) THEN args->get_string( `role_type` ) ELSE co_role_type-any ).
    query-values = zcl_accx_search_criteria=>value_criteria( args->get_strings( `values` ) ).

    IF query-values IS NOT INITIAL AND object IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `values need the authorization object they belong to (parameter object).` ).
    ENDIF.
    IF role IS INITIAL AND description IS INITIAL AND transaction IS INITIAL AND object IS INITIAL AND user IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = `Give at least one of role, description, transaction, object or assigned_to_user.` ).
    ENDIF.
    IF transaction IS NOT INITIAL AND transaction NA '*'
       AND zcl_accx_domain_factory=>auth_evaluator( )->transaction_exists( CONV #( transaction ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Transaction { transaction } does not exist.| ).
    ENDIF.
    IF object IS NOT INITIAL AND zcl_accx_domain_factory=>auth_evaluator( )->object_exists( CONV #( object ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Authorization object { object } does not exist.| ).
    ENDIF.

    query-object    = object.
    query-single    = xsdbool( role_type <> co_role_type-composite ).
    query-composite = xsdbool( role_type <> co_role_type-single ).
    IF role IS NOT INITIAL.
      APPEND INITIAL LINE TO query-roles ASSIGNING FIELD-SYMBOL(<role>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = role IMPORTING sign = <role>-sign option = <role>-option low = <role>-low ).
      APPEND |named { role }| TO words.
    ENDIF.
    IF description IS NOT INITIAL.
      DATA(text_pattern) = COND string( WHEN description CA '*' THEN description ELSE |*{ description }*| ).
      APPEND INITIAL LINE TO query-descriptions ASSIGNING FIELD-SYMBOL(<text>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = text_pattern IMPORTING sign = <text>-sign option = <text>-option low = <text>-low ).
      APPEND |with description { text_pattern }| TO words.
    ENDIF.
    IF transaction IS NOT INITIAL.
      APPEND INITIAL LINE TO query-transactions ASSIGNING FIELD-SYMBOL(<transaction>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = transaction
                                            IMPORTING sign = <transaction>-sign option = <transaction>-option low = <transaction>-low ).
      APPEND |granting transaction { transaction }| TO words.
    ENDIF.
    IF object IS NOT INITIAL.
      APPEND |with authorization { zcl_accx_search_criteria=>describe_values( object = object criteria = query-values ) }| TO words.
    ENDIF.
    IF user IS NOT INITIAL.
      APPEND INITIAL LINE TO query-users ASSIGNING FIELD-SYMBOL(<user>).
      zcl_accx_search_criteria=>range_line( EXPORTING value = user IMPORTING sign = <user>-sign option = <user>-option low = <user>-low ).
      APPEND |assigned to { user }| TO words.
    ENDIF.
    IF role_type <> co_role_type-any.
      APPEND |{ role_type } roles only| TO words.
    ENDIF.

    DATA(found) = zcl_accx_domain_factory=>suim_gateway( )->find_roles( query ).
    APPEND LINES OF found-messages TO result-warnings.

    DATA(payload) = NEW ty_payload( criteria = concat_lines_of( table = words sep = `, ` ) ).
    result-data = payload.
    LOOP AT found-roles INTO DATA(hit).
      IF ctx->guard( )->can_display_role( hit-role ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( role        = hit-role
                      description = hit-text
                      role_type   = SWITCH #( hit-role_type WHEN 'C' THEN co_role_type-composite ELSE co_role_type-single ) )
        TO payload->roles.
      APPEND hit-role TO names.
    ENDLOOP.

    DATA(counts) = zcl_accx_domain_factory=>role_repo( )->count_assigned_users( names ).
    LOOP AT payload->roles ASSIGNING FIELD-SYMBOL(<found>).
      <found>-assigned_users = VALUE #( counts[ role = CONV agr_name( <found>-role ) ]-users OPTIONAL ).
    ENDLOOP.
    " most used roles first
    SORT payload->roles BY assigned_users DESCENDING role ASCENDING.

    result-total_count = lines( payload->roles ).
    IF lines( payload->roles ) > ctx->max_rows( ).
      DELETE payload->roles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `SUSR_SUIM_API_RSUSR070 (SUIM RSUSR070, roles by complex selection criteria)` )
                              ( `AGR_USERS (assigned users today)` ) ).
    IF payload->roles IS NOT INITIAL.
      DATA(top) = payload->roles[ 1 ].
      APPEND |Use find_users with role { top-role } to see who holds it{ COND #( WHEN object IS NOT INITIAL
                                                                       THEN `, or with the same object values to see who holds the access by any role or profile` ) }.|
        TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    IF <payload>-roles IS INITIAL.
      result-summary = |No roles found { <payload>-criteria }.|.
    ELSE.
      result-summary = |**{ result-total_count }** { COND #( WHEN result-total_count = 1 THEN `role` ELSE `roles` ) } | &&
                       |{ <payload>-criteria }, most used first:|.
      LOOP AT <payload>-roles INTO DATA(role) TO co_listed_in_summary.
        result-summary = |{ result-summary }\n- **{ role-role }**| &&
                         |{ COND #( WHEN role-description IS NOT INITIAL AND role-description <> role-role THEN | ({ role-description })| ) }, | &&
                         |{ role-role_type }, { role-assigned_users } { COND #( WHEN role-assigned_users = 1 THEN `user` ELSE `users` ) }|.
      ENDLOOP.
      IF lines( <payload>-roles ) > co_listed_in_summary.
        result-summary = |{ result-summary }\n- ... { lines( <payload>-roles ) - co_listed_in_summary } more in the structured result|.
      ENDIF.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList truncated to max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } roles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
