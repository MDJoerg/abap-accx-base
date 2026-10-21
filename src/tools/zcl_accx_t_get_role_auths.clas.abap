"! <p class="shorttext synchronized">Access Explorer tool: get_role_authorizations</p>
"! Authorization data of one single or derived role as PFCG shows it: every
"! authorization with its maintenance status (standard, maintained, changed,
"! manual), active or inactive, and its field values incl. open fields and
"! organizational level placeholders.
CLASS zcl_accx_t_get_role_auths DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_role_authorizations`.

    TYPES: BEGIN OF ty_field,
             field  TYPE string,
             "! values as LOW or LOW-HIGH; empty = open field
             values TYPE string_table,
           END OF ty_field,
           ty_fields TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY.

    TYPES: BEGIN OF ty_authorization,
             object TYPE string,
             auth   TYPE string,
             text   TYPE string,
             "! standard, maintained, changed or manual
             status TYPE string,
             active TYPE abap_bool,
             fields TYPE ty_fields,
           END OF ty_authorization,
           ty_authorizations TYPE STANDARD TABLE OF ty_authorization WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             role           TYPE string,
             derived_from   TYPE string,
             object         TYPE string,
             "! counts over all displayable authorizations (before max_rows)
             standard       TYPE i,
             maintained     TYPE i,
             changed        TYPE i,
             manual         TYPE i,
             inactive       TYPE i,
             "! open fields of active authorizations, as OBJECT-FIELD
             open_fields    TYPE string_table,
             "! organizational level placeholders used, e.g. $BUKRS
             org_levels     TYPE string_table,
             authorizations TYPE ty_authorizations,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS status_text
      IMPORTING !status       TYPE c
      RETURNING VALUE(result) TYPE string.

    METHODS fields_text
      IMPORTING !fields       TYPE ty_fields
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_role_auths IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get role authorizations`
      description = |Lists the authorization data of one single or derived PFCG role as the expert mode of PFCG | &&
                    |shows it: every authorization with object, text, maintenance status (standard = SU24 proposal | &&
                    |unchanged, maintained = proposal with a value filled in, changed = proposal value changed, | &&
                    |manual = added by hand), active or inactive, and its field values, including open fields and | &&
                    |organizational level placeholders ($BUKRS). Optionally limited to one authorization object. | &&
                    |Use it to review what a role really allows or why a value is in it; use get_role_details | &&
                    |for the overview and compare_roles for differences between roles.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_ROLE_AUTHS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role`
                                      description = `Role name, e.g. Z_FI_AP_CLERK (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 30 ) )
                             ( param( name        = `object`
                                      description = `Only authorizations of this authorization object, e.g. S_TABU_DIS.`
                                      maximum     = 10 ) )
                             ( param( name        = `include_inactive`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `Also list inactive authorizations (default false; they are counted anyway).` ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA hidden_objects TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.

    DATA(role) = CONV agr_name( to_upper( condense( args->get_string( `role` ) ) ) ).
    DATA(object) = CONV xuobject( to_upper( condense( args->get_string( `object` ) ) ) ).
    DATA(include_inactive) = args->get_boolean( name = `include_inactive` default = abap_false ).
    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    IF repo->exists( role ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Role { role } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_role( role ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display role { role } (S_USER_AGR, activity 03).| ).
    ENDIF.
    DATA(info) = repo->get_role_info( role ).
    IF info-composite = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = |{ role } is a composite role and has no authorization data of its own; ask for its single roles| &&
                  |{ COND #( WHEN info-children IS NOT INITIAL THEN |: { concat_lines_of( table = info-children sep = `, ` ) }| ) }.| ).
    ENDIF.
    IF object IS NOT INITIAL AND ctx->guard( )->can_display_authorization( object ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display authorizations of object { object } (S_USER_AUT, activity 03).| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( role = CONV #( role ) derived_from = CONV #( info-derived_from ) object = CONV #( object ) ).
    result-data = payload.

    LOOP AT repo->get_authorizations( role = role object = object ) INTO DATA(authorization).
      IF ctx->guard( )->can_display_authorization( authorization-object ) = abap_false.
        INSERT authorization-object INTO TABLE hidden_objects.
        CONTINUE.
      ENDIF.
      IF authorization-inactive = abap_true.
        payload->inactive += 1.
        IF include_inactive = abap_false.
          CONTINUE.
        ENDIF.
      ELSE.
        CASE authorization-status.
          WHEN 'G'.
            payload->maintained += 1.
          WHEN 'M'.
            payload->changed += 1.
          WHEN 'U'.
            payload->manual += 1.
          WHEN OTHERS.
            payload->standard += 1.
        ENDCASE.
      ENDIF.

      DATA(entry) = VALUE ty_authorization( object = authorization-object
                                            auth   = authorization-auth
                                            text   = authorization-text
                                            status = status_text( authorization-status )
                                            active = xsdbool( authorization-inactive = abap_false ) ).
      LOOP AT authorization-values INTO DATA(value).
        DATA(field) = CONV string( value-field ).
        IF NOT line_exists( entry-fields[ field = field ] ).
          APPEND VALUE #( field = field ) TO entry-fields.
        ENDIF.
        ASSIGN entry-fields[ field = field ] TO FIELD-SYMBOL(<field>).
        DATA(low) = condense( CONV string( value-low ) ).
        IF low IS INITIAL AND value-high IS INITIAL.
          IF entry-active = abap_true.
            APPEND |{ entry-object }-{ field }| TO payload->open_fields.
          ENDIF.
          CONTINUE.
        ENDIF.
        " organizational level placeholder, e.g. $BUKRS ($* and the like are ordinary patterns)
        IF value-high IS INITIAL AND matches( val = low pcre = `^\$[A-Z_0-9]+$` )
           AND NOT line_exists( payload->org_levels[ table_line = low ] ).
          APPEND low TO payload->org_levels.
        ENDIF.
        APPEND COND #( WHEN value-high IS INITIAL THEN low ELSE |{ low }-{ condense( value-high ) }| ) TO <field>-values.
      ENDLOOP.
      APPEND entry TO payload->authorizations.
    ENDLOOP.

    result-hidden_by_authorization = lines( hidden_objects ).
    result-total_count = lines( payload->authorizations ).
    IF lines( payload->authorizations ) > ctx->max_rows( ).
      DELETE payload->authorizations FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.
    IF result-total_count = 0 AND object IS NOT INITIAL.
      APPEND |Role { role } has no authorization for object { object }.| TO result-warnings.
    ENDIF.
    result-sources = VALUE #( ( `AGR_1250 (authorizations, status)` ) ( `AGR_1251 (field values)` ) ).
    IF payload->open_fields IS NOT INITIAL.
      APPEND |Fill the open fields ({ lines( payload->open_fields ) }) before generating the profile; | &&
             |draft_role_change and apply_role_change can do this.| TO result-next_steps.
    ENDIF.
    IF info-derived_from IS NOT INITIAL.
      APPEND |The values are maintained in the reference role { info-derived_from } (apart from organizational levels); | &&
             |change them there.| TO result-next_steps.
    ENDIF.
    APPEND |Use get_role_details with role { role } for menu, profile and users.| TO result-next_steps.
  ENDMETHOD.

  METHOD status_text.
    result = SWITCH #( status WHEN 'G' THEN `maintained`
                              WHEN 'M' THEN `changed`
                              WHEN 'U' THEN `manual`
                              ELSE `standard` ).
  ENDMETHOD.

  METHOD fields_text.
    LOOP AT fields INTO DATA(field).
      result = |{ result }{ COND #( WHEN sy-tabix > 1 THEN `; ` ) }{ field-field }=| &&
               |{ COND #( WHEN field-values IS INITIAL THEN `(open)` ELSE concat_lines_of( table = field-values sep = `,` ) ) }|.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    DATA(active) = <payload>-standard + <payload>-maintained + <payload>-changed + <payload>-manual.

    result-summary = |Role **{ <payload>-role }**{ COND #( WHEN <payload>-derived_from IS NOT INITIAL
                                                         THEN | (derived from { <payload>-derived_from })| ) }: | &&
                     |{ active } active { COND #( WHEN active = 1 THEN `authorization` ELSE `authorizations` ) }| &&
                     |{ COND #( WHEN <payload>-object IS NOT INITIAL THEN | for { <payload>-object }| ) } | &&
                     |({ <payload>-standard } standard, { <payload>-maintained } maintained, { <payload>-changed } changed, | &&
                     |{ <payload>-manual } manual), { <payload>-inactive } inactive.|.
    IF <payload>-open_fields IS NOT INITIAL.
      result-summary = |{ result-summary } **{ lines( <payload>-open_fields ) } open fields**.|.
    ENDIF.
    IF <payload>-org_levels IS NOT INITIAL.
      result-summary = |{ result-summary } Organizational levels: { concat_lines_of( table = <payload>-org_levels sep = `, ` ) }.|.
    ENDIF.
    LOOP AT <payload>-authorizations INTO DATA(authorization).
      result-summary = |{ result-summary }\n- { authorization-object } ({ authorization-auth }, { authorization-status }| &&
                       |{ COND #( WHEN authorization-active = abap_false THEN `, **inactive**` ) }): { fields_text( authorization-fields ) }|.
    ENDLOOP.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nShowing { lines( <payload>-authorizations ) } of { result-total_count } authorizations | &&
                       |- filter by object or raise max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\nAuthorizations of { result-hidden_by_authorization } objects hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

