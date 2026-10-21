"! <p class="shorttext synchronized">Access Explorer tool: get_catalog_details</p>
"! Shows a launchpad catalog with its tiles and target mappings, where it is
"! used (roles with their users, pages and groups showing its tiles, references
"! from other catalogs) and its inconsistencies: tiles without a target mapping
"! in the catalog, lost references, content errors and references of other
"! catalogs to items that no longer exist here. Embedded launchpad only.
CLASS zcl_accx_t_get_catalog_details DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_catalog_details`.

    TYPES: BEGIN OF ty_tile,
             tile_id          TYPE string,
             title            TYPE string,
             subtitle         TYPE string,
             tile_type        TYPE string,
             "! INTENT, URL or NONE
             navigation       TYPE string,
             intent           TYPE string,
             url              TYPE string,
             "! target mapping for the intent in this catalog
             mapping_id       TYPE string,
             "! no target mapping here: catalogs that have one for the intent
             mapping_catalogs TYPE string_table,
             consistent       TYPE abap_bool,
             state_text       TYPE string,
             reference        TYPE string,
             deprecation      TYPE string,
             pages            TYPE string_table,
             groups           TYPE string_table,
           END OF ty_tile,
           ty_tiles TYPE STANDARD TABLE OF ty_tile WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mapping,
             mapping_id  TYPE string,
             intent      TYPE string,
             title       TYPE string,
             app_type    TYPE string,
             target      TYPE string,
             fiori_ids   TYPE string,
             consistent  TYPE abap_bool,
             state_text  TYPE string,
             reference   TYPE string,
             deprecation TYPE string,
             "! tiles of this catalog navigating to the intent (0 = only reachable by navigation)
             tiles       TYPE i,
           END OF ty_mapping,
           ty_mappings TYPE STANDARD TABLE OF ty_mapping WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role,
             role           TYPE string,
             "! users holding the role today (directly or through a composite role)
             assigned_users TYPE i,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_problems,
             "! tiles and target mappings whose original no longer exists
             lost_references       TYPE i,
             "! tiles navigating to an intent without target mapping in this catalog
             tiles_without_mapping TYPE i,
             "! of these: no catalog has a target mapping for the intent
             tiles_without_target  TYPE i,
             content_errors        TYPE i,
             deprecated_items      TYPE i,
             "! references in other catalogs to items of this catalog that no longer exist
             lost_references_elsewhere TYPE i,
           END OF ty_problems.

    TYPES: BEGIN OF ty_payload,
             catalog                TYPE string,
             title                  TYPE string,
             package                TYPE string,
             changed_by             TYPE string,
             changed_on             TYPE string,
             tile_count             TYPE i,
             mapping_count          TYPE i,
             problems               TYPE ty_problems,
             "! roles containing the catalog, most users first
             roles                  TYPE ty_roles,
             "! roles containing the catalog the caller may not display
             hidden_roles           TYPE i,
             "! pages (client-specific) and groups showing tiles of the catalog
             pages                  TYPE string_table,
             groups                 TYPE string_table,
             "! items of other catalogs referring to items of this catalog
             referenced_by          TYPE zif_accx_fiori_repo=>ty_references,
             "! tiles, items with problems first (max_rows)
             tiles                  TYPE ty_tiles,
             "! target mappings, items with problems first (max_rows)
             target_mappings        TYPE ty_mappings,
             "! start authorizations PFCG adds with the catalog (with_defaults)
             authorization_defaults TYPE string_table,
           END OF ty_payload.

    CONSTANTS co_roles_shown    TYPE i VALUE 10.
    CONSTANTS co_problems_shown TYPE i VALUE 10.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! Roles containing the catalog with their users; hidden roles counted
    METHODS add_roles
      IMPORTING !ctx     TYPE REF TO zif_accx_context
                !repo    TYPE REF TO zif_accx_fiori_repo
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result.

    "! Start authorizations PFCG adds with the catalog
    METHODS add_defaults
      IMPORTING !repo    TYPE REF TO zif_accx_fiori_repo
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result.

    "! Next steps for the problems found
    METHODS add_next_steps
      IMPORTING !payload TYPE ty_payload
                !lost    TYPE string_table
      CHANGING  !result  TYPE zif_accx_types=>ty_result.

    METHODS json_string
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_catalog_details IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get catalog details`
      description = |Shows a Fiori launchpad catalog: its tiles and target mappings, where it is used (roles containing | &&
                    |it with the number of users holding them today, pages and groups showing its tiles, references from | &&
                    |other catalogs) and its inconsistencies: tiles whose intent has no target mapping in the catalog (with | &&
                    |the catalogs that have one), lost references (tiles or target mappings whose original was deleted), | &&
                    |content errors, deprecated items and references of other catalogs to deleted items of this catalog. | &&
                    |Optionally lists the start authorizations PFCG adds with the catalog. Tiles and target mappings with | &&
                    |problems come first. Embedded launchpad only.|
      group       = zif_accx_types=>co_group-fiori
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-normal
      output_type = `\CLASS=ZCL_ACCX_T_GET_CATALOG_DETAILS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `catalog_id`
                                      description = `ID of the launchpad catalog, e.g. SAP_BASIS_TCR_T (case is ignored if not exact).`
                                      required    = abap_true
                                      maximum     = 35 ) )
                             ( param( name        = `with_defaults`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = |List the start authorizations (transactions, S_SERVICE and S_START values) | &&
                                                    |PFCG adds to a role menu with the catalog (default false).| ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA lost   TYPE string_table.
    DATA ranked TYPE ty_tiles.

    DATA(catalog_id) = condense( args->get_string( `catalog_id` ) ).
    IF catalog_id IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `Give a catalog ID.` ).
    ENDIF.
    DATA(repo) = zcl_accx_domain_factory=>fiori_repo( ).
    DATA(catalog) = repo->get_catalog( catalog_id ).
    IF catalog-catalog IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Launchpad catalog { catalog_id } does not exist; find_fiori_app names the | &&
                                                    |catalogs of an app.| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( catalog       = catalog-catalog
                                    title         = catalog-title
                                    package       = catalog-package
                                    changed_by    = catalog-changed_by
                                    changed_on    = catalog-changed_on
                                    tile_count    = lines( catalog-tiles )
                                    mapping_count = lines( catalog-apps ) ).
    result-data = payload.
    result-sources = VALUE #( ( `/UI2/FDM_PUBLIC_API (catalogs, tiles, target mappings, groups)` )
                              ( `/UI2/CL_FDM_PAGE_API_FACTORY (pages showing the tiles)` )
                              ( `AGR_HIER, AGR_BUFFI (catalogs in role menus), AGR_USERS (users holding the roles)` ) ).

    " where the tiles are shown
    DATA(tile_pages) = repo->get_tile_pages( VALUE #( FOR t IN catalog-tiles ( catalog = t-catalog tile_id = t-tile_id ) ) ).
    TRY.
        DATA(groups) = repo->get_all_groups( ).
      CATCH zcx_accx_error INTO DATA(error).
        APPEND |Groups not read: { error->message }| TO result-warnings.
    ENDTRY.

    " tiles
    LOOP AT catalog-tiles INTO DATA(found_tile).
      DATA(tile) = CORRESPONDING ty_tile( found_tile ).
      IF tile-intent IS NOT INITIAL.
        tile-mapping_id = VALUE #( catalog-apps[ intent = tile-intent ]-mapping_id OPTIONAL ).
        IF tile-mapping_id IS INITIAL.
          payload->problems-tiles_without_mapping += 1.
          LOOP AT repo->find_apps( tile-intent ) INTO DATA(other) WHERE intent = tile-intent.
            IF NOT line_exists( tile-mapping_catalogs[ table_line = other-catalog ] ).
              APPEND other-catalog TO tile-mapping_catalogs.
            ENDIF.
          ENDLOOP.
          IF tile-mapping_catalogs IS INITIAL.
            payload->problems-tiles_without_target += 1.
          ENDIF.
        ENDIF.
      ENDIF.
      tile-pages = VALUE #( FOR p IN tile_pages WHERE ( tile_id = found_tile-tile_id ) ( p-page ) ).
      LOOP AT groups INTO DATA(group).
        IF line_exists( group-tiles[ catalog = catalog-catalog tile_id = found_tile-tile_id ] ).
          APPEND group-group TO tile-groups.
        ENDIF.
      ENDLOOP.
      LOOP AT tile-pages INTO DATA(page).
        IF NOT line_exists( payload->pages[ table_line = page ] ).
          APPEND page TO payload->pages.
        ENDIF.
      ENDLOOP.
      LOOP AT tile-groups INTO DATA(group_id).
        IF NOT line_exists( payload->groups[ table_line = group_id ] ).
          APPEND group_id TO payload->groups.
        ENDIF.
      ENDLOOP.
      IF found_tile-state_text CS `reference lost`.
        payload->problems-lost_references += 1.
        DATA(original) = substring_before( val = found_tile-reference sub = `/` ).
        IF NOT line_exists( lost[ table_line = original ] ).
          APPEND original TO lost.
        ENDIF.
      ELSEIF found_tile-consistent = abap_false.
        payload->problems-content_errors += 1.
      ENDIF.
      IF found_tile-deprecation IS NOT INITIAL.
        payload->problems-deprecated_items += 1.
      ENDIF.
      APPEND tile TO payload->tiles.
    ENDLOOP.

    " target mappings
    LOOP AT catalog-apps INTO DATA(app).
      DATA(mapping) = CORRESPONDING ty_mapping( app ).
      mapping-tiles = REDUCE i( INIT n = 0 FOR t IN catalog-tiles WHERE ( intent = app-intent ) NEXT n = n + 1 ).
      IF app-state_text CS `reference lost`.
        payload->problems-lost_references += 1.
        original = substring_before( val = app-reference sub = `/` ).
        IF NOT line_exists( lost[ table_line = original ] ).
          APPEND original TO lost.
        ENDIF.
      ELSEIF app-consistent = abap_false.
        payload->problems-content_errors += 1.
      ENDIF.
      IF app-deprecation IS NOT INITIAL.
        payload->problems-deprecated_items += 1.
      ENDIF.
      APPEND mapping TO payload->target_mappings.
    ENDLOOP.

    payload->referenced_by = repo->get_references( catalog-catalog ).
    payload->problems-lost_references_elsewhere = REDUCE i( INIT n = 0 FOR r IN payload->referenced_by WHERE ( lost = abap_true )
                                                            NEXT n = n + 1 ).

    " problems first: inconsistent, without target mapping in the catalog, deprecated, the others
    SORT payload->tiles BY title tile_id.
    DO 4 TIMES.
      DATA(rank) = sy-index.
      LOOP AT payload->tiles INTO tile.
        IF rank = COND i( WHEN tile-consistent = abap_false THEN 1
                          WHEN tile-intent IS NOT INITIAL AND tile-mapping_id IS INITIAL THEN 2
                          WHEN tile-deprecation IS NOT INITIAL THEN 3
                          ELSE 4 ).
          APPEND tile TO ranked.
        ENDIF.
      ENDLOOP.
    ENDDO.
    payload->tiles = ranked.
    SORT payload->target_mappings BY consistent ASCENDING deprecation DESCENDING title ASCENDING mapping_id ASCENDING.
    result-total_count = payload->tile_count + payload->mapping_count.
    IF lines( payload->tiles ) > ctx->max_rows( ).
      DELETE payload->tiles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->target_mappings ) > ctx->max_rows( ).
      DELETE payload->target_mappings FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    add_roles( EXPORTING ctx = ctx repo = repo CHANGING payload = payload->* result = result ).
    IF args->get_boolean( name = `with_defaults` default = abap_false ) = abap_true.
      add_defaults( EXPORTING repo = repo CHANGING payload = payload->* result = result ).
    ENDIF.
    add_next_steps( EXPORTING payload = payload->* lost = lost CHANGING result = result ).
  ENDMETHOD.

  METHOD add_roles.
    DATA names TYPE zif_accx_role_repo=>ty_roles.

    LOOP AT repo->get_catalog_roles( VALUE #( ( payload-catalog ) ) ) INTO DATA(role_catalog).
      IF line_exists( payload-roles[ role = CONV string( role_catalog-role ) ] ) OR line_exists( names[ table_line = role_catalog-role ] ).
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_role( role_catalog-role ) = abap_false.
        payload-hidden_roles += 1.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( role = role_catalog-role ) TO payload-roles.
      APPEND role_catalog-role TO names.
    ENDLOOP.
    result-hidden_by_authorization += payload-hidden_roles.
    DATA(counts) = zcl_accx_domain_factory=>role_repo( )->count_assigned_users( names ).
    LOOP AT payload-roles ASSIGNING FIELD-SYMBOL(<role>).
      <role>-assigned_users = VALUE #( counts[ role = CONV agr_name( <role>-role ) ]-users OPTIONAL ).
    ENDLOOP.
    SORT payload-roles BY assigned_users DESCENDING role ASCENDING.
  ENDMETHOD.

  METHOD add_defaults.
    DATA(defaults) = repo->get_catalog_defaults( payload-catalog ).
    APPEND `/UI2/CL_CATALOG_DETAIL (authorization defaults, as PFCG reads them), /IWFND/I_MED_SRH` TO result-sources.
    LOOP AT defaults-defaults INTO DATA(default).
      APPEND COND string( WHEN default-type = 'TR' THEN |S_TCODE TCD={ default-name }|
                          WHEN default-object = 'IWSG' OR default-object = 'IWSV'
                          THEN |S_SERVICE SRV_NAME={ default-name }, SRV_TYPE=HT ({ default-object } { default-obj_name })| &&
                               |{ COND #( WHEN default-active = abap_false THEN ` - service not active` ) }|
                          ELSE |S_START AUTHPGMID={ default-pgmid }, AUTHOBJTYP={ default-object }, AUTHOBJNAM={ default-obj_name }| )
        TO payload-authorization_defaults.
    ENDLOOP.
    LOOP AT defaults-messages INTO DATA(message).
      APPEND |Authorization defaults: { message }| TO result-warnings.
    ENDLOOP.
    IF defaults-defaults IS INITIAL AND defaults-messages IS INITIAL.
      APPEND |PFCG reads no authorization defaults for { payload-catalog }: a role menu gets no start authorizations with | &&
             |this catalog; check SU24 data of its apps or the role menu after adding it.| TO result-warnings.
    ENDIF.
  ENDMETHOD.

  METHOD add_next_steps.
    IF payload-problems-lost_references > 0.
      DATA(lost_on_pages) = VALUE string_table( ).
      LOOP AT payload-tiles INTO DATA(tile) WHERE state_text CS `reference lost`.
        LOOP AT tile-pages INTO DATA(page).
          IF NOT line_exists( lost_on_pages[ table_line = page ] ).
            APPEND page TO lost_on_pages.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      APPEND |Remove the { payload-problems-lost_references } lost references in the Launchpad Content Manager | &&
             |(/UI2/FLPCM_CUST, filter on reference lost) or restore the originals in { concat_lines_of( table = lost sep = `, ` ) }| &&
             |{ COND #( WHEN lost_on_pages IS NOT INITIAL
                        THEN |; pages { concat_lines_of( table = lost_on_pages sep = `, ` ) } show such tiles| ) }.|
        TO result-next_steps.
    ENDIF.
    " one step per tile without target mapping, the first few only
    DATA(listed) = 0.
    LOOP AT payload-tiles INTO tile WHERE intent IS NOT INITIAL AND mapping_id IS INITIAL.
      listed += 1.
      IF listed > 3.
        APPEND |{ payload-problems-tiles_without_mapping - 3 } more tiles have no target mapping in { payload-catalog } | &&
               |(see tiles, mapping_catalogs).| TO result-next_steps.
        EXIT.
      ENDIF.
      IF tile-mapping_catalogs IS INITIAL.
        APPEND |Tile "{ tile-title }" navigates to { tile-intent }, but no catalog has a target mapping for it: the tile | &&
               |cannot start an app until a target mapping is created.| TO result-next_steps.
      ELSE.
        APPEND |Tile "{ tile-title }" navigates to { tile-intent }, whose target mapping is only in | &&
               |{ concat_lines_of( table = tile-mapping_catalogs sep = `, ` ) }: users also need one of these catalogs; add a | &&
               |reference of the target mapping to { payload-catalog } to make the catalog self-contained.| TO result-next_steps.
      ENDIF.
    ENDLOOP.
    IF payload-problems-lost_references_elsewhere > 0.
      DATA(catalogs) = VALUE string_table( ).
      LOOP AT payload-referenced_by INTO DATA(reference) WHERE lost = abap_true.
        IF NOT line_exists( catalogs[ table_line = reference-catalog ] ).
          APPEND reference-catalog TO catalogs.
        ENDIF.
      ENDLOOP.
      DATA(named) = catalogs.
      IF lines( named ) > co_problems_shown.
        DELETE named FROM co_problems_shown + 1.
        APPEND |... { lines( catalogs ) - co_problems_shown } more| TO named.
      ENDIF.
      APPEND |{ payload-problems-lost_references_elsewhere } references in { lines( catalogs ) } other catalogs | &&
             |({ concat_lines_of( table = named sep = `, ` ) }) point to deleted items of { payload-catalog }; run | &&
             |get_catalog_details for these catalogs to clean them up.| TO result-warnings.
    ENDIF.
    IF payload-roles IS INITIAL AND payload-hidden_roles = 0.
      APPEND |No role contains { payload-catalog }; to offer its apps, plan adding it to a role with draft_role_change | &&
             |\{"role":"...","add_catalogs":[{ json_string( payload-catalog ) }]\}.| TO result-next_steps.
    ENDIF.
    IF payload-target_mappings IS NOT INITIAL.
      APPEND `For roles, start authorization and OData services of one app, run find_fiori_app with its intent.` TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD json_string.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |Catalog **{ <payload>-catalog }**{ COND #( WHEN <payload>-title IS NOT INITIAL THEN | ({ <payload>-title })| ) }: | &&
                     |{ <payload>-tile_count } { COND #( WHEN <payload>-tile_count = 1 THEN `tile` ELSE `tiles` ) }, | &&
                     |{ <payload>-mapping_count } target { COND #( WHEN <payload>-mapping_count = 1 THEN `mapping` ELSE `mappings` ) }| &&
                     |{ COND #( WHEN <payload>-package IS NOT INITIAL THEN |; package { <payload>-package }| ) }| &&
                     |{ COND #( WHEN <payload>-changed_by IS NOT INITIAL
                                THEN |, last changed by { <payload>-changed_by } on { <payload>-changed_on }| ) }.|.

    " usage
    IF <payload>-roles IS INITIAL.
      result-summary = |{ result-summary }\n- Roles: none{ COND #( WHEN <payload>-hidden_roles > 0
                                                                  THEN | you may display ({ <payload>-hidden_roles } hidden)| ) }|.
    ELSE.
      DATA(role_texts) = VALUE string_table( ).
      LOOP AT <payload>-roles INTO DATA(role) TO co_roles_shown.
        APPEND |{ role-role } ({ role-assigned_users } { COND #( WHEN role-assigned_users = 1 THEN `user` ELSE `users` ) })|
          TO role_texts.
      ENDLOOP.
      IF lines( <payload>-roles ) > co_roles_shown.
        APPEND |... { lines( <payload>-roles ) - co_roles_shown } more| TO role_texts.
      ENDIF.
      result-summary = |{ result-summary }\n- Roles ({ lines( <payload>-roles ) }, most users first): | &&
                       |{ concat_lines_of( table = role_texts sep = `, ` ) }| &&
                       |{ COND #( WHEN <payload>-hidden_roles > 0 THEN |; { <payload>-hidden_roles } hidden| ) }|.
    ENDIF.
    result-summary = |{ result-summary }\n- Pages showing its tiles: | &&
                     |{ COND #( WHEN <payload>-pages IS INITIAL THEN `none` ELSE concat_lines_of( table = <payload>-pages sep = `, ` ) ) }| &&
                     |\n- Groups showing its tiles: | &&
                     |{ COND #( WHEN <payload>-groups IS INITIAL THEN `none` ELSE concat_lines_of( table = <payload>-groups sep = `, ` ) ) }|.
    IF <payload>-referenced_by IS NOT INITIAL.
      DATA(referring) = VALUE string_table( ).
      LOOP AT <payload>-referenced_by INTO DATA(reference).
        IF NOT line_exists( referring[ table_line = reference-catalog ] ).
          APPEND reference-catalog TO referring.
        ENDIF.
      ENDLOOP.
      result-summary = |{ result-summary }\n- Referenced by { lines( <payload>-referenced_by ) } items in { lines( referring ) } | &&
                       |other { COND #( WHEN lines( referring ) = 1 THEN `catalog` ELSE `catalogs` ) }| &&
                       |{ COND #( WHEN <payload>-problems-lost_references_elsewhere > 0
                                  THEN |, **{ <payload>-problems-lost_references_elsewhere } of them lost** (original deleted here)| ) }|.
    ENDIF.

    " problems
    DATA(problems) = <payload>-problems.
    IF problems-lost_references = 0 AND problems-tiles_without_mapping = 0 AND problems-content_errors = 0
       AND problems-lost_references_elsewhere = 0.
      result-summary = |{ result-summary }\n\nNo inconsistencies found|.
      result-summary = |{ result-summary }{ COND #( WHEN problems-deprecated_items > 0
                                                     THEN |; { problems-deprecated_items } deprecated | &&
                                                          |{ COND #( WHEN problems-deprecated_items = 1 THEN `item` ELSE `items` ) }| ) }.|.
    ELSE.
      result-summary = |{ result-summary }\n\n**Inconsistencies:**|.
      IF problems-lost_references > 0.
        result-summary = |{ result-summary }\n- { problems-lost_references } lost | &&
                         |{ COND #( WHEN problems-lost_references = 1 THEN `reference` ELSE `references` ) } (original deleted)|.
      ENDIF.
      IF problems-tiles_without_mapping > 0.
        result-summary = |{ result-summary }\n- { problems-tiles_without_mapping } | &&
                         |{ COND #( WHEN problems-tiles_without_mapping = 1 THEN `tile` ELSE `tiles` ) } without target mapping | &&
                         |in the catalog{ COND #( WHEN problems-tiles_without_target > 0
                                                  THEN |, { problems-tiles_without_target } without any target mapping| ) }|.
      ENDIF.
      IF problems-content_errors > 0.
        result-summary = |{ result-summary }\n- { problems-content_errors } | &&
                         |{ COND #( WHEN problems-content_errors = 1 THEN `item` ELSE `items` ) } with content errors|.
      ENDIF.
      IF problems-lost_references_elsewhere > 0.
        result-summary = |{ result-summary }\n- { problems-lost_references_elsewhere } | &&
                         |{ COND #( WHEN problems-lost_references_elsewhere = 1 THEN `reference` ELSE `references` ) } | &&
                         |in other catalogs to deleted items|.
      ENDIF.
      IF problems-deprecated_items > 0.
        result-summary = |{ result-summary }\n- { problems-deprecated_items } deprecated | &&
                         |{ COND #( WHEN problems-deprecated_items = 1 THEN `item` ELSE `items` ) }|.
      ENDIF.
      DATA(shown) = 0.
      LOOP AT <payload>-tiles INTO DATA(tile) WHERE consistent = abap_false OR ( intent IS NOT INITIAL AND mapping_id IS INITIAL ).
        shown += 1.
        IF shown > co_problems_shown.
          EXIT.
        ENDIF.
        result-summary = |{ result-summary }\n  - tile { tile-tile_id }{ COND #( WHEN tile-title IS NOT INITIAL THEN | "{ tile-title }"| ) }: | &&
                         |{ COND #( WHEN tile-state_text IS NOT INITIAL THEN tile-state_text
                                    ELSE |no target mapping for { tile-intent }| ) }|.
      ENDLOOP.
      LOOP AT <payload>-target_mappings INTO DATA(mapping) WHERE consistent = abap_false.
        shown += 1.
        IF shown > co_problems_shown.
          EXIT.
        ENDIF.
        result-summary = |{ result-summary }\n  - target mapping { mapping-mapping_id }{ COND #( WHEN mapping-intent <> `-`
                                                                                         THEN | ({ mapping-intent })| ) }: | &&
                         |{ mapping-state_text }|.
      ENDLOOP.
      IF shown > co_problems_shown.
        result-summary = |{ result-summary }\n  - ... see tiles and target_mappings|.
      ENDIF.
    ENDIF.

    IF <payload>-authorization_defaults IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Start authorizations PFCG adds** ({ lines( <payload>-authorization_defaults ) }): | &&
                       |{ concat_lines_of( table = <payload>-authorization_defaults sep = `; ` ) }|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } roles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
