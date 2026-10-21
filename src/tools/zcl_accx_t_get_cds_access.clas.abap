"! <p class="shorttext synchronized">Access Explorer tool: get_cds_access_control</p>
"! Access control of one CDS entity: AccessControl.authorizationCheck, the DCL roles
"! protecting it with their conditions (PFCG objects and fields, inherited conditions),
"! whether it is effectively protected, and the OData services exposing it.
CLASS zcl_accx_t_get_cds_access DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_cds_access_control`.

    TYPES: BEGIN OF ty_role,
             role          TYPE string,
             dcl           TYPE string,
             "! grant select without condition
             unconditional TYPE abap_bool,
             conditions    TYPE string_table,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_object,
             object  TYPE string,
             fields  TYPE string_table,
             filters TYPE string_table,
           END OF ty_object,
           ty_objects TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             entity              TYPE string,
             description         TYPE string,
             ddl_source          TYPE string,
             package             TYPE string,
             kind                TYPE string,
             "! annotation value, e.g. #CHECK; empty = not annotated
             authorization_check TYPE string,
             "! see ZCL_ACCX_DCL_ANALYZER=>CO_STATUS
             status              TYPE string,
             protected           TYPE abap_bool,
             reason              TYPE string,
             roles               TYPE ty_roles,
             "! authorization objects the roles check, merged over all roles
             pfcg_objects        TYPE ty_objects,
             "! entities or roles whose conditions are inherited
             inherited_from      TYPE string_table,
             exposures           TYPE zif_accx_cds_access=>ty_exposures,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS exposure_text
      IMPORTING !exposure     TYPE zif_accx_cds_access=>ty_exposure
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_cds_access IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get CDS access control`
      description = |Access control of one CDS entity: @AccessControl.authorizationCheck, the DCL roles protecting it | &&
                    |with their conditions (aspect pfcg_auth with authorization object, fields and fixed values such as | &&
                    |ACTVT, inherited conditions, aspect user), whether the entity is effectively protected for SELECT, the | &&
                    |authorization objects users need, and the OData services exposing it (service definition, binding, | &&
                    |published as V2 or V4, @OData.publish). Conditions are read from the DCL source; simulate_cds_access evaluates them for a user.|
      group       = zif_accx_types=>co_group-data
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-normal
      output_type = `\CLASS=ZCL_ACCX_T_GET_CDS_ACCESS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `cds_entity`
                                      description = `CDS entity name (case-insensitive), e.g. I_BUSINESSUSERBASIC.`
                                      required    = abap_true
                                      maximum     = 40 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(name) = to_upper( condense( args->get_string( `cds_entity` ) ) ).
    IF name IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `cds_entity is required.` ).
    ENDIF.
    IF name CA '*+'.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `cds_entity takes one name; find_unprotected_cds_exposures searches by pattern.` ).
    ENDIF.
    DATA(repo) = zcl_accx_domain_factory=>cds_access( ).
    DATA(names) = VALUE zif_accx_cds_access=>ty_names( ( sign = 'I' option = 'EQ' low = name ) ).
    DATA(entities) = repo->get_entities( names ).
    IF entities IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |CDS entity { name } not found (no active DDL source defines it).| ).
    ENDIF.
    DATA(entity) = entities[ 1 ].

    DATA(grants) = VALUE zcl_accx_dcl_analyzer=>ty_grants( ).
    DATA(payload) = NEW ty_payload( entity              = entity-name
                                    description         = entity-description
                                    ddl_source          = entity-ddl_source
                                    package             = entity-package
                                    kind                = COND #( WHEN entity-kind IS INITIAL THEN `DDIC-based view` ELSE entity-kind )
                                    authorization_check = COND #( WHEN entity-authorization_check IS NOT INITIAL
                                                                  THEN |#{ entity-authorization_check }| ) ).
    result-data = payload.

    LOOP AT repo->get_roles( names ) INTO DATA(role).
      DATA(role_grants) = VALUE zcl_accx_dcl_analyzer=>ty_grants(
                            FOR g IN zcl_accx_dcl_analyzer=>parse( role-source ) WHERE ( entity = name ) ( g ) ).
      APPEND LINES OF role_grants TO grants.
      DATA(entry) = VALUE ty_role( role = role-role dcl = role-dcl ).
      LOOP AT role_grants INTO DATA(grant).
        IF grant-unconditional = abap_true.
          entry-unconditional = abap_true.
          APPEND `grant select without condition` TO entry-conditions.
        ELSEIF grant-static_filter = abap_true.
          APPEND `fixed values only, the same for every user` TO entry-conditions.
        ENDIF.
        LOOP AT zcl_accx_dcl_analyzer=>merge( grant-conditions ) INTO DATA(condition).
          APPEND zcl_accx_dcl_analyzer=>condition_text( condition ) TO entry-conditions.
          CASE condition-kind.
            WHEN zcl_accx_dcl_analyzer=>co_kind-pfcg.
              READ TABLE payload->pfcg_objects ASSIGNING FIELD-SYMBOL(<object>) WITH KEY object = condition-object.
              IF sy-subrc <> 0.
                APPEND VALUE #( object = condition-object ) TO payload->pfcg_objects ASSIGNING <object>.
              ENDIF.
              LOOP AT condition-fields INTO DATA(field) WHERE table_line IS NOT INITIAL.
                IF NOT line_exists( <object>-fields[ table_line = field ] ).
                  APPEND field TO <object>-fields.
                ENDIF.
              ENDLOOP.
              LOOP AT condition-filters INTO DATA(filter).
                IF NOT line_exists( <object>-filters[ table_line = filter ] ).
                  APPEND filter TO <object>-filters.
                ENDIF.
              ENDLOOP.
            WHEN zcl_accx_dcl_analyzer=>co_kind-inherit.
              IF NOT line_exists( payload->inherited_from[ table_line = condition-object ] ).
                APPEND condition-object TO payload->inherited_from.
              ENDIF.
          ENDCASE.
        ENDLOOP.
      ENDLOOP.
      IF role_grants IS INITIAL.
        APPEND `no grant on this entity found in the DCL source` TO entry-conditions.
      ENDIF.
      APPEND entry TO payload->roles.
    ENDLOOP.

    DATA(protection) = zcl_accx_dcl_analyzer=>protection( entity = entity grants = grants ).
    payload->status    = protection-status.
    payload->protected = protection-protected.
    payload->reason    = protection-reason.
    payload->exposures = repo->get_exposures( names ).
    SORT payload->exposures BY published DESCENDING service_definition binding.

    result-total_count = lines( payload->exposures ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->exposures ) > max.
      DELETE payload->exposures FROM max + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `DDLDEPENDENCY, DD02B, DDHEADANNO, DDDDLSRCT, TADIR (entity, annotation)` )
                              ( `ACMDCLMETADATAEN, ACMDCLMETADATA, ACMDCLSRC (DCL roles and sources)` )
                              ( `SRVD_RT_ENTITIES, SRVB_SERVICES, /IWFND/I_MED_SRH, /IWFND/C_V4_MSGR (exposure)` ) ).
    DATA(published) = VALUE zif_accx_cds_access=>ty_exposure( payload->exposures[ published = abap_true ] OPTIONAL ).
    IF payload->protected = abap_false AND payload->status <> zcl_accx_dcl_analyzer=>co_status-custom AND published IS NOT INITIAL.
      APPEND |{ name } is published in service { published-service } without effective access control: whoever may call | &&
             |the service (S_SERVICE) reads all rows. Add a DCL role with aspect pfcg_auth conditions; get_service_access | &&
             |{ published-service } shows who may call it.| TO result-next_steps.
    ELSEIF payload->protected = abap_false AND payload->status <> zcl_accx_dcl_analyzer=>co_status-custom.
      APPEND |Add a DCL role (define role ... grant select on { name } where ... = aspect pfcg_auth( ... )) before | &&
             |exposing { name } in a service.| TO result-next_steps.
    ENDIF.
    IF payload->status = zcl_accx_dcl_analyzer=>co_status-custom.
      APPEND |Check the authorization checks in the query implementation class of { name }.| TO result-next_steps.
    ENDIF.
    IF payload->pfcg_objects IS NOT INITIAL.
      APPEND |Users see rows only with { concat_lines_of( table = VALUE string_table( FOR o IN payload->pfcg_objects ( o-object ) ) sep = `, ` ) } | &&
             |in their roles; find_roles or find_users with values (OBJECT FIELD=VALUE) show who has them.| TO result-next_steps.
    ENDIF.
    LOOP AT payload->inherited_from INTO DATA(inherited) WHERE table_line <> `SUPER`.
      APPEND |get_cds_access_control { inherited } shows the inherited conditions.| TO result-next_steps.
      EXIT.
    ENDLOOP.
    IF payload->roles IS NOT INITIAL.
      APPEND |simulate_cds_access with a user and { name } evaluates the conditions for that user.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD exposure_text.
    result = COND #( WHEN exposure-auto_published = abap_true THEN |@OData.publish service { exposure-service }|
                     WHEN exposure-binding IS INITIAL THEN |service definition { exposure-service_definition } (not bound)|
                     ELSE |{ exposure-service_definition } as { exposure-alias }, binding { exposure-binding }| ) &&
             COND #( WHEN exposure-published = abap_true THEN | - published { exposure-protocol }| ELSE ` - not published` ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |CDS entity **{ <payload>-entity }**{ COND #( WHEN <payload>-description IS NOT INITIAL THEN | ({ <payload>-description })| ) }, | &&
                     |{ <payload>-kind }, DDL source { <payload>-ddl_source }, package { <payload>-package }. | &&
                     |authorizationCheck: { COND #( WHEN <payload>-authorization_check IS INITIAL THEN `not annotated` ELSE <payload>-authorization_check ) }.| &&
                     |\n\n{ COND #( WHEN <payload>-protected = abap_true THEN `Protected` ELSE `**Not protected**` ) } ({ <payload>-status }): { <payload>-reason }|.
    IF <payload>-roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**DCL roles:**|.
      LOOP AT <payload>-roles INTO DATA(role).
        result-summary = |{ result-summary }\n- { role-role }{ COND #( WHEN role-dcl <> role-role THEN | (DCL { role-dcl })| ) }: | &&
                         |{ concat_lines_of( table = role-conditions sep = `; ` ) }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-pfcg_objects IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nAuthorization objects: | &&
                       |{ concat_lines_of( sep   = `, `
                                           table = VALUE string_table( FOR o IN <payload>-pfcg_objects
                                                                       ( |{ o-object }{ COND #( WHEN o-fields IS NOT INITIAL
                                                                                                THEN | ({ concat_lines_of( table = o-fields sep = `, ` ) })| ) }| ) ) ) }.|.
    ENDIF.
    IF <payload>-exposures IS INITIAL.
      result-summary = |{ result-summary }\n\nNot exposed in an OData service.|.
    ELSE.
      result-summary = |{ result-summary }\n\n**Exposed in:**|.
      LOOP AT <payload>-exposures INTO DATA(exposure).
        result-summary = |{ result-summary }\n- { exposure_text( exposure ) }|.
      ENDLOOP.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nExposures cut to max_rows ({ result-total_count }).|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

