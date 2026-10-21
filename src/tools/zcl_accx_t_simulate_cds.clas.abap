"! <p class="shorttext synchronized">Access Explorer tool: simulate_cds_access</p>
"! Evaluates the access control of one CDS entity for one user with the ACM runtime,
"! as SACMSEL does with enforcement layer None: full access, no access or the WHERE
"! condition with the user's values. Names the authorization objects of the DCL roles
"! with the user's values and the roles they come from, and optionally counts the
"! visible rows (no row content).
CLASS zcl_accx_t_simulate_cds DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `simulate_cds_access`.
    "! longer conditions are cut in the payload
    CONSTANTS co_max_condition TYPE i VALUE 4000.

    TYPES: BEGIN OF ty_field,
             field  TYPE string,
             "! distinct values over all authorizations (ranges as LOW-HIGH)
             values TYPE string_table,
             "! one authorization allows every value (*)
             full   TYPE abap_bool,
           END OF ty_field,
           ty_fields TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY.

    TYPES: BEGIN OF ty_object,
             object     TYPE string,
             "! fields the DCL conditions map to entity elements
             dcl_fields TYPE string_table,
             "! the user holds an authorization of the object
             granted    TYPE abap_bool,
             fields     TYPE ty_fields,
             "! roles, or profiles assigned directly, granting the object
             sources    TYPE string_table,
           END OF ty_object,
           ty_objects TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user                TYPE string,
             entity              TYPE string,
             description         TYPE string,
             kind                TYPE string,
             "! annotation value, e.g. #CHECK; empty = not annotated
             authorization_check TYPE string,
             "! protection status of the entity, see ZCL_ACCX_DCL_ANALYZER=>CO_STATUS
             status              TYPE string,
             protected           TYPE abap_bool,
             "! user locked or outside its validity: cannot log on, the result applies once usable again
             user_usable         TYPE abap_bool,
             "! full, none, restricted (ZIF_ACCX_CDS_ACCESS=>CO_ACCESS); empty = not evaluated
             access              TYPE string,
             reason              TYPE string,
             "! restricted: WHERE condition of the ACM runtime with the user's values
             condition           TYPE string,
             condition_cut       TYPE abap_bool,
             "! restricted, but the condition needs a join and is not given as WHERE condition
             join_only           TYPE abap_bool,
             "! elements masked by cell rules
             masked_elements     TYPE string_table,
             roles               TYPE string_table,
             objects             TYPE ty_objects,
             "! authorization objects of the DCL conditions the user does not hold
             missing_objects     TYPE string_table,
             rows_counted        TYPE abap_bool,
             visible_rows        TYPE int8,
             total_rows          TYPE int8,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS add_user_values
      IMPORTING !user    TYPE syuname
                !ctx     TYPE REF TO zif_accx_context
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result.

    METHODS explain
      CHANGING !payload TYPE ty_payload.

ENDCLASS.

CLASS zcl_accx_t_simulate_cds IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Simulate CDS access`
      description = |Evaluates the access control of one CDS entity for one user with the ACM runtime, as transaction | &&
                    |SACMSEL does: full access, no access, or the WHERE condition with the user's authorization values | &&
                    |inserted (also SACF, switches and inherited conditions as the runtime applies them). Lists the | &&
                    |authorization objects of the DCL roles with the user's values and the roles they come from, and | &&
                    |the objects the user lacks. With count_rows it counts the rows the user sees and the total (only | &&
                    |for callers allowed to preview the entity's data bypassing access control in ADT; no row content | &&
                    |is returned). Typical question: "why does X see no or only some entries in app Y". | &&
                    |get_cds_access_control shows the DCL roles without a user.|
      group       = zif_accx_types=>co_group-data
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_SIMULATE_CDS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `SAP user ID (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `cds_entity`
                                      description = `CDS entity name (case-insensitive), e.g. I_BUSINESSUSERBASIC.`
                                      required    = abap_true
                                      maximum     = 40 ) )
                             ( param( name        = `count_rows`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = |Count the rows the user sees and the total (default false; needs the ADT | &&
                                                    |data preview with privileged access, S_DEVELOP).| ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA grants TYPE zcl_accx_dcl_analyzer=>ty_grants.

    DATA(user) = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(name) = to_upper( condense( args->get_string( `cds_entity` ) ) ).
    IF user IS INITIAL OR name IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `user and cds_entity are required.` ).
    ENDIF.
    IF name CA '*+'.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `cds_entity takes one name; find_unprotected_cds_exposures searches by pattern.` ).
    ENDIF.
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    IF user_repo->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { user } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { user } (S_USER_GRP, activity 03).| ).
    ENDIF.
    DATA(repo) = zcl_accx_domain_factory=>cds_access( ).
    DATA(names) = VALUE zif_accx_cds_access=>ty_names( ( sign = 'I' option = 'EQ' low = name ) ).
    DATA(entities) = repo->get_entities( names ).
    IF entities IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |CDS entity { name } not found (no active DDL source defines it).| ).
    ENDIF.
    DATA(entity) = entities[ 1 ].

    DATA(master) = user_repo->get_user( user ).
    DATA(payload) = NEW ty_payload( user                = CONV #( user )
                                    entity              = entity-name
                                    description         = entity-description
                                    kind                = COND #( WHEN entity-kind IS INITIAL THEN `DDIC-based view` ELSE entity-kind )
                                    authorization_check = COND #( WHEN entity-authorization_check IS NOT INITIAL
                                                                  THEN |#{ entity-authorization_check }| )
                                    user_usable         = xsdbool( master-locked = abap_false
                                                                   AND ( master-valid_from IS INITIAL OR master-valid_from <= sy-datum )
                                                                   AND ( master-valid_to IS INITIAL OR master-valid_to >= sy-datum ) ) ).
    result-data = payload.

    " authorization objects of the DCL conditions
    LOOP AT repo->get_roles( names ) INTO DATA(role).
      APPEND role-role TO payload->roles.
      LOOP AT zcl_accx_dcl_analyzer=>parse( role-source ) INTO DATA(grant) WHERE entity = name.
        APPEND grant TO grants.
        LOOP AT zcl_accx_dcl_analyzer=>merge( grant-conditions ) INTO DATA(condition)
             WHERE kind = zcl_accx_dcl_analyzer=>co_kind-pfcg.
          READ TABLE payload->objects ASSIGNING FIELD-SYMBOL(<object>) WITH KEY object = condition-object.
          IF sy-subrc <> 0.
            APPEND VALUE #( object = condition-object ) TO payload->objects ASSIGNING <object>.
          ENDIF.
          LOOP AT condition-fields INTO DATA(field) WHERE table_line IS NOT INITIAL.
            IF NOT line_exists( <object>-dcl_fields[ table_line = field ] ).
              APPEND field TO <object>-dcl_fields.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
    DATA(protection) = zcl_accx_dcl_analyzer=>protection( entity = entity grants = grants ).
    payload->status    = protection-status.
    payload->protected = protection-protected.
    add_user_values( EXPORTING user = user ctx = ctx CHANGING payload = payload->* result = result ).

    result-sources = VALUE #( ( `CL_ACMRT_KERNEL_PROXY get_access_restrictions (ACM runtime, as SACMSEL)` )
                              ( `ACMDCLMETADATAEN, ACMDCLSRC (DCL roles), UST04, UST10C/S, UST12 (user values)` ) ).

    IF payload->status = zcl_accx_dcl_analyzer=>co_status-custom OR payload->status = zcl_accx_dcl_analyzer=>co_status-abstract.
      explain( CHANGING payload = payload->* ).
      APPEND |Custom entities: the query implementation class of { name } decides; the ACM runtime does not apply.|
             TO result-next_steps.
      RETURN.
    ENDIF.

    DATA(evaluation) = repo->evaluate( user = user entity = name ).
    IF evaluation-error IS NOT INITIAL.
      APPEND |ACM runtime: { evaluation-error }| TO result-warnings.
    ENDIF.
    payload->access          = evaluation-access.
    payload->join_only       = evaluation-join_only.
    payload->masked_elements = evaluation-masked_elements.
    payload->condition       = evaluation-condition.
    IF strlen( payload->condition ) > co_max_condition.
      payload->condition     = substring( val = payload->condition len = co_max_condition ).
      payload->condition_cut = abap_true.
    ENDIF.
    explain( CHANGING payload = payload->* ).

    DATA(count_rows) = args->get_boolean( name = `count_rows` default = abap_false ).
    IF count_rows = abap_true AND payload->access IS NOT INITIAL.
      IF ctx->guard( )->can_preview_privileged( name ) = abap_false.
        APPEND |Rows not counted: you are not authorized to preview { name } bypassing access control | &&
               |(S_DEVELOP, as for the ADT data preview).| TO result-warnings.
      ELSE.
        DATA(count) = repo->count_rows( entity = name access = payload->access condition = evaluation-condition ).
        IF count-error IS NOT INITIAL.
          APPEND |Rows not counted: { count-error }| TO result-warnings.
        ELSE.
          payload->rows_counted = abap_true.
          payload->visible_rows = count-visible.
          payload->total_rows   = count-total.
        ENDIF.
      ENDIF.
    ENDIF.

    IF payload->user_usable = abap_false.
      APPEND |{ user } is locked or outside its validity and cannot log on; the result applies once the user is usable again.|
             TO result-warnings.
    ENDIF.
    IF payload->masked_elements IS NOT INITIAL.
      APPEND |Cell rules mask elements for { user }: { concat_lines_of( table = payload->masked_elements sep = `, ` ) }.|
             TO result-warnings.
    ENDIF.
    IF payload->condition_cut = abap_true.
      APPEND |The condition is cut after { co_max_condition } characters.| TO result-warnings.
    ENDIF.

    IF payload->rows_counted = abap_true AND payload->visible_rows = 0 AND payload->total_rows > 0.
      APPEND |{ user } sees none of the { payload->total_rows } rows.| TO result-warnings.
    ENDIF.
    IF payload->access = zif_accx_cds_access=>co_access-none OR payload->access = zif_accx_cds_access=>co_access-restricted.
      LOOP AT payload->missing_objects INTO DATA(missing).
        APPEND |{ user } lacks { missing }: find_roles with values ({ missing } ...) shows roles granting it; | &&
               |explain_missing_access { user } with object { missing } and the needed values proposes a role.| TO result-next_steps.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF payload->access = zif_accx_cds_access=>co_access-restricted.
      LOOP AT payload->objects INTO DATA(object) WHERE granted = abap_true.
        APPEND |get_user_authorizations { user } { object-object } shows where the values come from.| TO result-next_steps.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF count_rows = abap_false AND payload->access IS NOT INITIAL.
      APPEND `count_rows=true counts the rows the user sees (needs the ADT data preview with privileged access).` TO result-next_steps.
    ENDIF.
    APPEND |get_cds_access_control { name } shows the DCL roles and the services exposing the entity.| TO result-next_steps.
  ENDMETHOD.

  METHOD add_user_values.
    IF payload-objects IS INITIAL.
      RETURN.
    ENDIF.
    DATA(origin) = zcl_accx_domain_factory=>access_origin( ).
    DATA(object_names) = VALUE string_table( ).
    LOOP AT payload-objects INTO DATA(entry).
      IF ctx->guard( )->can_display_authorization( CONV #( entry-object ) ) = abap_true.
        APPEND entry-object TO object_names.
      ELSE.
        result-hidden_by_authorization += 1.
      ENDIF.
    ENDLOOP.
    IF object_names IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT origin->get_user_sources( user ) INTO DATA(source).
      DATA(values) = origin->get_profile_values( profile = source-profile objects = object_names ).
      IF values IS INITIAL.
        CONTINUE.
      ENDIF.
      IF ( source-role IS NOT INITIAL AND ctx->guard( )->can_display_role( source-role ) = abap_false )
         OR ( source-role IS INITIAL AND ctx->guard( )->can_display_profile( source-profile ) = abap_false ).
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      DATA(name) = COND string( WHEN source-role IS NOT INITIAL THEN source-role ELSE source-profile ).
      LOOP AT values INTO DATA(value).
        READ TABLE payload-objects ASSIGNING FIELD-SYMBOL(<object>) WITH KEY object = CONV string( value-object ).
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        <object>-granted = abap_true.
        IF NOT line_exists( <object>-sources[ table_line = name ] ).
          APPEND name TO <object>-sources.
        ENDIF.
        READ TABLE <object>-fields ASSIGNING FIELD-SYMBOL(<field>) WITH KEY field = CONV string( value-field ).
        IF sy-subrc <> 0.
          APPEND VALUE #( field = value-field ) TO <object>-fields ASSIGNING <field>.
        ENDIF.
        IF value-low = '*'.
          <field>-full = abap_true.
        ENDIF.
        DATA(text) = COND string( WHEN value-high IS NOT INITIAL THEN |{ value-low }-{ value-high }| ELSE CONV #( value-low ) ).
        IF text IS NOT INITIAL AND NOT line_exists( <field>-values[ table_line = text ] ).
          APPEND text TO <field>-values.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT payload-objects ASSIGNING <object>.
      SORT <object>-fields BY field.
      LOOP AT <object>-fields ASSIGNING <field>.
        SORT <field>-values.
      ENDLOOP.
      IF <object>-granted = abap_false AND line_exists( object_names[ table_line = <object>-object ] ).
        APPEND <object>-object TO payload-missing_objects.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD explain.
    payload-reason = SWITCH #( payload-status
      WHEN zcl_accx_dcl_analyzer=>co_status-custom   THEN `Custom entity: its query implementation class checks authorizations, not the ACM runtime.`
      WHEN zcl_accx_dcl_analyzer=>co_status-abstract THEN `Abstract entity: it has no data.` ).
    IF payload-reason IS NOT INITIAL.
      RETURN.
    ENDIF.
    payload-reason = SWITCH #( payload-access
      WHEN zif_accx_cds_access=>co_access-full THEN
        COND #( WHEN payload-protected = abap_false
                THEN |All rows: { payload-entity } has no effective access control ({ payload-status }).|
                ELSE |All rows: the authorization values of { payload-user } fulfil a condition without restriction (for example *).| )
      WHEN zif_accx_cds_access=>co_access-none THEN
        COND #( WHEN payload-missing_objects IS NOT INITIAL
                THEN |No rows: { payload-user } holds no authorization of { concat_lines_of( table = payload-missing_objects sep = `, ` ) }.|
                WHEN payload-roles IS INITIAL
                THEN |No rows: { payload-entity } requires access control ({ payload-authorization_check }) but has no DCL role.|
                ELSE |No rows: the values of { payload-user } fulfil no condition of the DCL roles.| )
      WHEN zif_accx_cds_access=>co_access-restricted THEN
        COND #( WHEN payload-join_only = abap_true
                THEN |Some rows: the condition needs a join (path expressions or runtime CTE) and is not shown as WHERE condition.|
                WHEN NOT line_exists( payload-objects[ granted = abap_true ] ) AND payload-missing_objects IS NOT INITIAL
                THEN |Only rows whose protected elements are initial: { payload-user } holds no authorization of | &&
                     |{ concat_lines_of( table = payload-missing_objects sep = `, ` ) }.|
                ELSE |Only rows matching the condition with the values of { payload-user }.| )
      ELSE `Not evaluated: the ACM runtime returned no result.` ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |**{ <payload>-user }** on CDS entity **{ <payload>-entity }**| &&
                     |{ COND #( WHEN <payload>-description IS NOT INITIAL THEN | ({ <payload>-description })| ) }: | &&
                     |**{ SWITCH string( <payload>-access WHEN zif_accx_cds_access=>co_access-full       THEN `full access`
                                                         WHEN zif_accx_cds_access=>co_access-none       THEN `no access`
                                                         WHEN zif_accx_cds_access=>co_access-restricted THEN `restricted`
                                                         ELSE `not evaluated` ) }**. { <payload>-reason }|.
    IF <payload>-condition IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nCondition: `{ <payload>-condition }`|.
    ENDIF.
    IF <payload>-rows_counted = abap_true.
      result-summary = |{ result-summary }\n\nRows: { <payload>-visible_rows } of { <payload>-total_rows } visible.|.
    ENDIF.
    IF <payload>-objects IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Authorization objects of the DCL roles** ({ concat_lines_of( table = <payload>-roles sep = `, ` ) }):|.
      LOOP AT <payload>-objects INTO DATA(object).
        IF object-granted = abap_false.
          result-summary = |{ result-summary }\n- { object-object }: **not held**|.
          CONTINUE.
        ENDIF.
        result-summary = |{ result-summary }\n- { object-object }: | &&
                         |{ concat_lines_of( sep   = `; `
                                             table = VALUE string_table( FOR f IN object-fields
                                                                         ( |{ f-field } { concat_lines_of( table = f-values sep = `, ` ) }| ) ) ) } | &&
                         |(from { concat_lines_of( table = object-sources sep = `, ` ) })|.
      ENDLOOP.
    ENDIF.
    IF <payload>-user_usable = abap_false.
      result-summary = |{ result-summary }\n\nThe user is locked or outside its validity.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

