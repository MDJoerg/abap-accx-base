"! <p class="shorttext synchronized">Access Explorer tool: get_user_profile</p>
"! 360-degree overview of one user: master data, role and profile assignments.
CLASS zcl_accx_t_get_user_profile DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_payload,
             user     TYPE zif_accx_user_repo=>ty_user,
             roles    TYPE zif_accx_user_repo=>ty_role_assignments,
             profiles TYPE zif_accx_user_repo=>ty_profile_assignments,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `get_user_profile`.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS format_date
      IMPORTING !date         TYPE d
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_user_profile IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get user profile`
      description = |Returns a 360-degree overview of one SAP user in this system: master data (user type, user group, validity, | &&
                    |lock status and reason, last logon, password state), the assigned roles with validity and whether they come | &&
                    |from a composite role, and the assigned profiles. Use it first whenever a question concerns a specific user. | &&
                    |Only data the calling user is authorized to display is returned; hidden roles and profiles are counted.|
      group       = zif_accx_types=>co_group-user
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-personal
      output_type = `\CLASS=ZCL_ACCX_T_GET_USER_PROFILE\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `SAP user ID, e.g. JDOE (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(user) = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(repo) = zcl_accx_domain_factory=>user_repo( ).

    IF repo->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |User { user } does not exist in system { sy-sysid }, client { sy-mandt }.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { user } (S_USER_GRP, activity 03).| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( user = repo->get_user( user ) ).

    LOOP AT repo->get_role_assignments( user ) INTO DATA(role).
      IF ctx->guard( )->can_display_role( role-role ) = abap_true.
        APPEND role TO payload->roles.
      ELSE.
        result-hidden_by_authorization += 1.
      ENDIF.
    ENDLOOP.

    LOOP AT repo->get_profile_assignments( user ) INTO DATA(profile).
      IF ctx->guard( )->can_display_profile( profile-profile ) = abap_true.
        APPEND profile TO payload->profiles.
      ELSE.
        result-hidden_by_authorization += 1.
      ENDIF.
    ENDLOOP.

    result-total_count = lines( payload->roles ).
    IF lines( payload->roles ) > ctx->max_rows( ).
      DELETE payload->roles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->profiles ) > ctx->max_rows( ).
      DELETE payload->profiles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    result-data       = payload.
    result-sources    = VALUE #( ( `USR02` ) ( `USR21/ADRP` ) ( `AGR_USERS` ) ( `UST04` ) ).
    result-next_steps = VALUE #( ( |Use check_user_access to test whether { user } may start a transaction or holds an authorization.| ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    DATA(user) = <payload>-user.
    DATA(active) = REDUCE i( INIT n = 0 FOR r IN <payload>-roles WHERE ( active = abap_true ) NEXT n = n + 1 ).
    DATA(composite) = REDUCE i( INIT n = 0 FOR r IN <payload>-roles WHERE ( via_composite = abap_true ) NEXT n = n + 1 ).

    result-summary =
      |**{ user-user }**{ COND #( WHEN user-full_name IS NOT INITIAL THEN | ({ user-full_name })| ) }: | &&
      |{ user-user_type } user, user group { COND #( WHEN user-user_group IS INITIAL THEN `none` ELSE user-user_group ) }, | &&
      |valid from { format_date( user-valid_from ) } to { format_date( user-valid_to ) }, | &&
      |{ COND #( WHEN user-locked = abap_true THEN |**locked** ({ user-lock_reasons })| ELSE `not locked` ) }, | &&
      |last logon { user-last_logon }, password { user-password_state }.| &&
      | Roles: { lines( <payload>-roles ) } ({ active } active today, { composite } via composite role).| &&
      | Profiles: { lines( <payload>-profiles ) }.|.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary } Lists truncated to { ctx->max_rows( ) } entries.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary } { result-hidden_by_authorization } roles/profiles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

  METHOD format_date.
    result = COND #( WHEN date IS INITIAL THEN `unlimited` ELSE |{ date DATE = ISO }| ).
  ENDMETHOD.

ENDCLASS.
