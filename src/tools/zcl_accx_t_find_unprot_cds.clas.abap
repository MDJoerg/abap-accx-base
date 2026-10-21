"! <p class="shorttext synchronized">Access Explorer tool: find_unprotected_cds_exposures</p>
"! Audit of OData exposures: CDS entities exposed by service definitions (or OData.publish)
"! matching a name pattern, with their protection status - no DCL role, access control
"! switched off, roles without conditions, custom entities - published services first.
CLASS zcl_accx_t_find_unprot_cds DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `find_unprotected_cds_exposures`.

    TYPES: BEGIN OF ty_count,
             status   TYPE string,
             entities TYPE i,
           END OF ty_count,
           ty_counts TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.

    TYPES: BEGIN OF ty_entity,
             entity              TYPE string,
             kind                TYPE string,
             authorization_check TYPE string,
             "! see ZCL_ACCX_DCL_ANALYZER=>CO_STATUS
             status              TYPE string,
             protected           TYPE abap_bool,
             reason              TYPE string,
             "! number of DCL roles on the entity
             roles               TYPE i,
             "! exposed in at least one published service
             published           TYPE abap_bool,
             "! services exposing it, e.g. ZUI_MH_TASK (V2, published)
             services            TYPE string_table,
           END OF ty_entity,
           ty_entities TYPE STANDARD TABLE OF ty_entity WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             patterns              TYPE string_table,
             package               TYPE string,
             service_definitions   TYPE i,
             entities_checked      TYPE i,
             "! entities per status, unprotected first
             counts                TYPE ty_counts,
             unprotected           TYPE i,
             "! unprotected entities in published services
             published_unprotected TYPE i,
             "! unprotected entities (all with include_protected), published first
             entities              TYPE ty_entities,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

ENDCLASS.

CLASS zcl_accx_t_find_unprot_cds IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Find unprotected CDS exposures`
      description = |Audit of OData exposures: the CDS entities exposed by service definitions (or published with | &&
                    |@OData.publish) whose name matches the patterns (default Z*, Y*), each with its protection - no DCL | &&
                    |role while authorizationCheck allows reading without one (#NOT_REQUIRED, #CHECK, not annotated), | &&
                    |#NOT_ALLOWED, roles granting without condition or with fixed values only, custom entities whose query | &&
                    |class must check. Entities in published services first; counts per status. get_cds_access_control | &&
                    |explains one entity.|
      group       = zif_accx_types=>co_group-audit
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_FIND_UNPROT_CDS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `names`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |Service definitions, or entities published with @OData.publish, as names or | &&
                                                    |patterns with * (default Z* and Y*).| ) )
                             ( param( name        = `package`
                                      description = `Package of the service definition (pattern with * allowed).`
                                      maximum     = 30 ) )
                             ( param( name        = `include_protected`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `List protected entities too (default false: only unprotected and custom entities).` ) )
                             ( param( name        = `published_only`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `Only entities in published services (default false).` ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA names TYPE zif_accx_cds_access=>ty_names.
    DATA packages TYPE zif_accx_cds_access=>ty_names.
    DATA entity_names TYPE zif_accx_cds_access=>ty_names.
    DATA grants TYPE zcl_accx_dcl_analyzer=>ty_grants.

    DATA(payload) = NEW ty_payload( ).
    result-data = payload.
    LOOP AT args->get_strings( `names` ) INTO DATA(pattern).
      pattern = to_upper( condense( pattern ) ).
      IF pattern IS NOT INITIAL AND NOT line_exists( payload->patterns[ table_line = pattern ] ).
        APPEND pattern TO payload->patterns.
      ENDIF.
    ENDLOOP.
    IF payload->patterns IS INITIAL.
      payload->patterns = VALUE #( ( `Z*` ) ( `Y*` ) ).
    ENDIF.
    names = VALUE #( FOR p IN payload->patterns ( sign = 'I' option = COND #( WHEN p CA '*+' THEN 'CP' ELSE 'EQ' ) low = p ) ).
    payload->package = to_upper( condense( args->get_string( `package` ) ) ).
    IF payload->package IS NOT INITIAL.
      packages = VALUE #( ( sign = 'I' option = COND #( WHEN payload->package CA '*+' THEN 'CP' ELSE 'EQ' ) low = payload->package ) ).
    ENDIF.
    DATA(include_protected) = args->get_boolean( name = `include_protected` default = abap_false ).
    DATA(published_only) = args->get_boolean( name = `published_only` default = abap_false ).

    DATA(repo) = zcl_accx_domain_factory=>cds_access( ).
    DATA(exposures) = repo->find_exposures( names = names packages = packages ).
    IF published_only = abap_true.
      DELETE exposures WHERE published = abap_false.
    ENDIF.
    payload->service_definitions = lines( VALUE string_table( FOR GROUPS d OF e IN exposures WHERE ( service_definition IS NOT INITIAL )
                                                              GROUP BY e-service_definition ( d ) ) ).
    entity_names = VALUE #( FOR GROUPS n OF e IN exposures GROUP BY e-entity ( sign = 'I' option = 'EQ' low = n ) ).
    IF entity_names IS INITIAL.
      result-sources = VALUE #( ( `TADIR, SRVD_RT_ENTITIES, DDHEADANNO (exposures)` ) ).
      APPEND `No exposed CDS entities for these names - check the patterns, e.g. names ["ZUI_*"] or package.` TO result-next_steps.
      RETURN.
    ENDIF.

    DATA(entities) = repo->get_entities( entity_names ).
    DATA(roles) = repo->get_roles( entity_names ).
    LOOP AT roles INTO DATA(role).
      APPEND LINES OF zcl_accx_dcl_analyzer=>parse( role-source ) TO grants.
    ENDLOOP.
    DATA(order) = zcl_accx_dcl_analyzer=>status_order( ).

    LOOP AT entity_names INTO DATA(entity_name).
      DATA(entity) = VALUE zif_accx_cds_access=>ty_entity( entities[ name = entity_name-low ] OPTIONAL ).
      IF entity IS INITIAL.
        " exposed but no CDS entity of its own, e.g. a table entity or an artifact of another kind
        CONTINUE.
      ENDIF.
      DATA(protection) = zcl_accx_dcl_analyzer=>protection( entity = entity grants = grants ).
      DATA(row) = VALUE ty_entity( entity              = entity-name
                                   kind                = COND #( WHEN entity-kind IS INITIAL THEN `DDIC-based view` ELSE entity-kind )
                                   authorization_check = COND #( WHEN entity-authorization_check IS NOT INITIAL
                                                                 THEN |#{ entity-authorization_check }| )
                                   status              = protection-status
                                   protected           = protection-protected
                                   reason              = protection-reason
                                   roles               = REDUCE i( INIT c = 0 FOR r IN roles WHERE ( entity = entity-name ) NEXT c = c + 1 ) ).
      LOOP AT exposures INTO DATA(exposure) WHERE entity = entity-name.
        IF exposure-published = abap_true.
          row-published = abap_true.
        ENDIF.
        DATA(service) = COND string( WHEN exposure-service IS NOT INITIAL THEN exposure-service
                                     ELSE |{ exposure-service_definition } (not bound)| ).
        DATA(text) = |{ service }{ COND #( WHEN exposure-published = abap_true THEN | ({ exposure-protocol }, published)| ) }|.
        IF NOT line_exists( row-services[ table_line = text ] ).
          APPEND text TO row-services.
        ENDIF.
      ENDLOOP.
      payload->entities_checked += 1.
      READ TABLE payload->counts ASSIGNING FIELD-SYMBOL(<count>) WITH KEY status = row-status.
      IF sy-subrc <> 0.
        APPEND VALUE #( status = row-status ) TO payload->counts ASSIGNING <count>.
      ENDIF.
      <count>-entities += 1.
      IF row-protected = abap_false AND row-status <> zcl_accx_dcl_analyzer=>co_status-custom.
        payload->unprotected += 1.
        IF row-published = abap_true.
          payload->published_unprotected += 1.
        ENDIF.
      ENDIF.
      IF row-protected = abap_false OR include_protected = abap_true.
        APPEND row TO payload->entities.
      ENDIF.
    ENDLOOP.

    " counts and list in severity order, published first
    DATA(sorted) = VALUE ty_counts( ).
    LOOP AT order INTO DATA(status).
      READ TABLE payload->counts INTO DATA(count) WITH KEY status = status.
      IF sy-subrc = 0.
        APPEND count TO sorted.
      ENDIF.
    ENDLOOP.
    payload->counts = sorted.
    TYPES: BEGIN OF ty_sortable,
             published TYPE abap_bool,
             severity  TYPE i,
             entity    TYPE ty_entity,
           END OF ty_sortable.
    DATA sortable TYPE STANDARD TABLE OF ty_sortable WITH EMPTY KEY.
    sortable = VALUE #( FOR x IN payload->entities ( published = x-published
                                                     severity  = line_index( order[ table_line = x-status ] )
                                                     entity    = x ) ).
    SORT sortable BY published DESCENDING severity ASCENDING entity-entity ASCENDING.
    payload->entities = VALUE #( FOR y IN sortable ( y-entity ) ).

    result-total_count = lines( payload->entities ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->entities ) > max.
      DELETE payload->entities FROM max + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `TADIR, SRVD_RT_ENTITIES, DDHEADANNO (exposures)` )
                              ( `SRVB_SERVICES, /IWFND/I_MED_SRH, /IWFND/C_V4_MSGR (bindings, publication)` )
                              ( `DDLDEPENDENCY, DD02B, DDHEADANNO (entities, authorizationCheck)` )
                              ( `ACMDCLMETADATAEN, ACMDCLMETADATA, ACMDCLSRC (DCL roles)` ) ).
    IF payload->published_unprotected > 0.
      APPEND |{ payload->published_unprotected } entities in published services have no effective access control: whoever may call | &&
             |the service (S_SERVICE) reads all rows. Add DCL roles with aspect pfcg_auth conditions, starting with the published ones; | &&
             |get_service_access shows who may call a service.| TO result-next_steps.
    ELSEIF payload->unprotected > 0.
      APPEND `The unprotected entities are not in a published service yet - add DCL roles before publishing.` TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ status = zcl_accx_dcl_analyzer=>co_status-custom ] ).
      APPEND `Custom entities: check the authorization checks in their query implementation classes.` TO result-next_steps.
    ENDIF.
    IF payload->entities IS NOT INITIAL.
      APPEND |get_cds_access_control { payload->entities[ 1 ]-entity } explains the first entity.| TO result-next_steps.
    ENDIF.
    APPEND `Write access is controlled by the behavior definition (authorization master), not by DCL; this audit covers reading.`
           TO result-warnings.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |{ <payload>-entities_checked } CDS entities exposed in { <payload>-service_definitions } service definitions | &&
                     |({ concat_lines_of( table = <payload>-patterns sep = `, ` ) }| &&
                     |{ COND #( WHEN <payload>-package IS NOT INITIAL THEN |, package { <payload>-package }| ) }): | &&
                     |{ COND #( WHEN <payload>-unprotected = 0 THEN `no unprotected entities`
                                ELSE |**{ <payload>-unprotected } without effective access control**, { <payload>-published_unprotected } of them in published services| ) }.|.
    LOOP AT <payload>-counts INTO DATA(count).
      result-summary = |{ result-summary }\n- { count-status }: { count-entities }|.
    ENDLOOP.
    IF <payload>-entities IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Entities, published first:**|.
      LOOP AT <payload>-entities INTO DATA(entity).
        result-summary = |{ result-summary }\n- **{ entity-entity }** ({ entity-status }, { COND #( WHEN entity-authorization_check IS INITIAL THEN `not annotated`
                                                                                                    ELSE entity-authorization_check ) }): | &&
                         |{ concat_lines_of( table = entity-services sep = `, ` ) }|.
      ENDLOOP.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList cut to max_rows ({ result-total_count } entities) - narrow names or package.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

