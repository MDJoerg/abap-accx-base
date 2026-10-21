"! <p class="shorttext synchronized">Access Explorer tool: get_user_authorizations</p>
"! Effective authorization values of a user for one authorization object, each
"! with its origin: the profile in the user master, the role it was generated
"! for and the composite role or reference user it comes through. Roles
"! assigned today whose profile is not yet in the user master (user comparison
"! pending) are reported, as are locked or expired users.
CLASS zcl_accx_t_get_user_auths DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_user_authorizations`.

    TYPES: BEGIN OF ty_value,
             auth        TYPE string,
             field       TYPE string,
             low         TYPE string,
             high        TYPE string,
             "! role or profile
             source_type TYPE string,
             "! role, or profile assigned directly
             source      TYPE string,
             profile     TYPE string,
             "! composite role or reference user it comes through
             via         TYPE string,
           END OF ty_value,
           ty_values TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.

    TYPES: BEGIN OF ty_field,
             field  TYPE string,
             "! distinct values over all authorizations (ranges as LOW-HIGH)
             values TYPE string_table,
             "! one authorization allows every value (*)
             full   TYPE abap_bool,
           END OF ty_field,
           ty_fields TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user               TYPE string,
             object             TYPE string,
             "! only this field (empty = all fields)
             field              TYPE string,
             "! user locked or outside its validity: the values are not usable
             usable             TYPE abap_bool,
             "! number of authorizations of the object in the user master
             authorizations     TYPE i,
             "! roles or profiles granting the object
             sources            TYPE string_table,
             fields             TYPE ty_fields,
             values             TYPE ty_values,
             "! roles assigned today whose profile is not in the user master yet (user comparison pending)
             comparison_pending TYPE string_table,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

ENDCLASS.

CLASS zcl_accx_t_get_user_auths IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get user authorizations`
      description = |Lists the authorization values a user holds for one authorization object, as the user master | &&
                    |has them after the user comparison, each with its origin: the role (or profile assigned directly) | &&
                    |and the composite role or reference user it comes through. Per field it condenses all values and | &&
                    |flags * (full authorization). Reports roles assigned today whose profile is not yet in the user | &&
                    |master (user comparison pending) and locked or expired users. Typical questions: "which tables may | &&
                    |X display (S_TABU_NAM)", "where does X get S_DEVELOP from". To test one concrete check use | &&
                    |check_user_access; to find what is missing use explain_missing_access.|
      group       = zif_accx_types=>co_group-user
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_USER_AUTHS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `SAP user ID (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `object`
                                      description = `Authorization object, e.g. S_TABU_NAM.`
                                      required    = abap_true
                                      maximum     = 10 ) )
                             ( param( name        = `field`
                                      description = `Only this field of the object, e.g. TABLE.`
                                      maximum     = 10 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(user)   = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(object) = CONV xuobject( to_upper( condense( args->get_string( `object` ) ) ) ).
    DATA(field)  = to_upper( condense( args->get_string( `field` ) ) ).
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(origin)    = zcl_accx_domain_factory=>access_origin( ).

    IF user_repo->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { user } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { user } (S_USER_GRP, activity 03).| ).
    ENDIF.
    IF zcl_accx_domain_factory=>auth_evaluator( )->object_exists( object ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Authorization object { object } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_authorization( object ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display authorizations of { object } (S_USER_AUT, activity 03).| ).
    ENDIF.

    DATA(master) = user_repo->get_user( user ).
    DATA(payload) = NEW ty_payload( user   = CONV #( user )
                                    object = CONV #( object )
                                    field  = field
                                    usable = xsdbool( master-locked = abap_false
                                                      AND ( master-valid_from IS INITIAL OR master-valid_from <= sy-datum )
                                                      AND ( master-valid_to IS INITIAL OR master-valid_to >= sy-datum ) ) ).
    result-data = payload.

    DATA(sources) = origin->get_user_sources( user ).
    DATA(auths) = VALUE string_table( ).
    LOOP AT sources INTO DATA(source).
      DATA(name) = COND string( WHEN source-role IS NOT INITIAL THEN source-role ELSE source-profile ).
      DATA(values) = origin->get_profile_values( profile = source-profile objects = VALUE #( ( CONV #( object ) ) ) ).
      IF values IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ( source-role IS NOT INITIAL AND ctx->guard( )->can_display_role( source-role ) = abap_false )
         OR ( source-role IS INITIAL AND ctx->guard( )->can_display_profile( source-profile ) = abap_false ).
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      IF NOT line_exists( payload->sources[ table_line = name ] ).
        APPEND name TO payload->sources.
      ENDIF.
      LOOP AT values INTO DATA(value).
        IF field IS NOT INITIAL AND value-field <> field.
          CONTINUE.
        ENDIF.
        IF NOT line_exists( auths[ table_line = |{ source-profile }/{ value-auth }| ] ).
          APPEND |{ source-profile }/{ value-auth }| TO auths.
        ENDIF.
        APPEND VALUE #( auth        = value-auth
                        field       = value-field
                        low         = value-low
                        high        = value-high
                        source_type = COND #( WHEN source-role IS NOT INITIAL THEN zif_accx_access_origin=>co_source-role
                                              ELSE zif_accx_access_origin=>co_source-profile )
                        source      = name
                        profile     = source-profile
                        via         = source-via ) TO payload->values.
        " condensed per field
        READ TABLE payload->fields ASSIGNING FIELD-SYMBOL(<field>) WITH KEY field = value-field.
        IF sy-subrc <> 0.
          APPEND VALUE #( field = value-field ) TO payload->fields ASSIGNING <field>.
        ENDIF.
        DATA(text) = COND string( WHEN value-high IS NOT INITIAL THEN |{ value-low }-{ value-high }| ELSE CONV #( value-low ) ).
        IF value-low = '*'.
          <field>-full = abap_true.
        ENDIF.
        IF text IS NOT INITIAL AND NOT line_exists( <field>-values[ table_line = text ] ).
          APPEND text TO <field>-values.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    payload->authorizations = lines( auths ).
    LOOP AT payload->fields ASSIGNING <field>.
      SORT <field>-values.
    ENDLOOP.
    SORT payload->fields BY field.
    SORT payload->values BY source field low.

    " roles assigned today whose generated profile is not in the user master
    DATA(profile_roles) = VALUE string_table( FOR s IN sources WHERE ( role IS NOT INITIAL ) ( CONV #( s-role ) ) ).
    LOOP AT user_repo->get_role_assignments( user ) INTO DATA(assignment) WHERE active = abap_true.
      IF line_exists( profile_roles[ table_line = assignment-role ] ) OR line_exists( payload->comparison_pending[ table_line = assignment-role ] ).
        CONTINUE.
      ENDIF.
      DATA(info) = role_repo->get_role_info( assignment-role ).
      IF info-composite = abap_false AND info-generated = abap_true AND ctx->guard( )->can_display_role( assignment-role ) = abap_true.
        APPEND CONV string( assignment-role ) TO payload->comparison_pending.
      ENDIF.
    ENDLOOP.

    result-total_count = lines( payload->values ).
    IF lines( payload->values ) > ctx->max_rows( ).
      DELETE payload->values FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.
    result-sources = VALUE #( ( `UST04, USREFUS (profiles of the user master)` ) ( `UST10C, UST10S, UST12 (profile values)` )
                              ( `AGR_1016, AGR_USERS, AGR_AGRS (role and composite role of a profile)` ) ).
    IF payload->usable = abap_false.
      APPEND |{ user } is locked or outside its validity period: none of these values can be used today.| TO result-warnings.
    ENDIF.
    IF payload->comparison_pending IS NOT INITIAL.
      APPEND |User comparison pending for { concat_lines_of( table = payload->comparison_pending sep = `, ` ) }: their | &&
             |authorizations are not in the user master yet (PFUD).| TO result-warnings.
    ENDIF.
    IF payload->values IS INITIAL.
      APPEND |Use explain_missing_access to find a role that grants { object } to { user }.| TO result-next_steps.
    ELSE.
      APPEND |Use check_user_access to test one concrete check of { object } for { user }.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    IF <payload>-authorizations = 0.
      result-summary = |**{ <payload>-user }** holds no authorization for { <payload>-object }| &&
                       |{ COND #( WHEN <payload>-field IS NOT INITIAL THEN | field { <payload>-field }| ) }.|.
    ELSE.
      result-summary = |**{ <payload>-user }** holds { <payload>-authorizations } | &&
                       |{ COND #( WHEN <payload>-authorizations = 1 THEN `authorization` ELSE `authorizations` ) } for | &&
                       |**{ <payload>-object }** from { concat_lines_of( table = <payload>-sources sep = `, ` ) }:|.
      LOOP AT <payload>-fields INTO DATA(field).
        DATA(others) = VALUE string_table( FOR v IN field-values WHERE ( table_line <> `*` ) ( v ) ).
        DATA(parts) = VALUE string_table( ).
        IF field-full = abap_true.
          APPEND `**all values (*)**` TO parts.
        ENDIF.
        IF others IS NOT INITIAL.
          DATA(shown) = others.
          DELETE shown FROM 21.
          APPEND |{ concat_lines_of( table = shown sep = `, ` ) }| &&
                 |{ COND #( WHEN lines( others ) > 20 THEN | and { lines( others ) - 20 } more| ) }| TO parts.
        ENDIF.
        result-summary = |{ result-summary }\n- { field-field }: { concat_lines_of( table = parts sep = `; ` ) }|.
      ENDLOOP.
      DATA(via) = VALUE string_table( FOR x IN <payload>-values WHERE ( via IS NOT INITIAL ) ( |{ x-source } via { x-via }| ) ).
      SORT via.
      DELETE ADJACENT DUPLICATES FROM via.
      IF via IS NOT INITIAL.
        result-summary = |{ result-summary }\n\nAssigned through: { concat_lines_of( table = via sep = `; ` ) }.|.
      ENDIF.
    ENDIF.
    IF <payload>-usable = abap_false.
      result-summary = |{ result-summary }\n\n**The user is locked or outside its validity period.**|.
    ENDIF.
    IF <payload>-comparison_pending IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**User comparison pending** for { concat_lines_of( table = <payload>-comparison_pending sep = `, ` ) } | &&
                       |(their values are not included).|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } roles/profiles with values hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

