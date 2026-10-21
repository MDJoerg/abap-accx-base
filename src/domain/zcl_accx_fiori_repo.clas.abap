"! <p class="shorttext synchronized">Access Explorer: Fiori launchpad content</p>
"! Sources: /UI2/FDM_PUBLIC_API (catalogs and groups in the client-specific
"! scope, which includes the cross-client layer), AGR_HIER/AGR_BUFFI (catalogs,
"! groups and spaces in role menus), /UI2/CL_FDM_SPACE_API_FACTORY and
"! /UI2/CL_FDM_PAGE_API_FACTORY (spaces, pages and their tiles),
"! /UI2/CL_FLP_SETTINGS_API (launchpad settings), /UI2/CL_CATALOG_DETAIL
"! (authorization defaults of a catalog, as PFCG reads them), UI5 app index
"! (data sources of a component), /IWFND/I_MED_SRH (gateway service
"! registration) and USOBHASH (S_SERVICE values). Launchpad content and role
"! menus are cached per instance.
CLASS zcl_accx_fiori_repo DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_catalog_header,
             catalog    TYPE string,
             "! CAT (standard) or CAR (replicated)
             type       TYPE string,
             title      TYPE string,
             package    TYPE string,
             changed_by TYPE string,
             changed_on TYPE string,
           END OF ty_catalog_header.

    TYPES: BEGIN OF ty_item_reference,
             original_catalog TYPE string,
             reference        TYPE zif_accx_fiori_repo=>ty_reference,
           END OF ty_item_reference.

    DATA apps            TYPE zif_accx_fiori_repo=>ty_apps.
    DATA tiles           TYPE zif_accx_fiori_repo=>ty_tiles.
    DATA item_references TYPE STANDARD TABLE OF ty_item_reference WITH EMPTY KEY.
    "! all catalogs, also those without target mappings
    DATA catalog_headers TYPE STANDARD TABLE OF ty_catalog_header WITH EMPTY KEY.
    DATA apps_loaded     TYPE abap_bool.
    DATA role_catalogs   TYPE zif_accx_fiori_repo=>ty_role_catalogs.
    DATA role_contents   TYPE zif_accx_fiori_repo=>ty_role_contents.
    DATA roles_loaded    TYPE abap_bool.

    "! All catalogs with the target mappings and tiles of all catalogs
    METHODS load_apps
      RAISING zcx_accx_error.

    "! Catalogs, groups and spaces of all role menus
    METHODS load_role_catalogs.

    "! Service, version and S_SERVICE values of an OData data source URL
    METHODS service_of_url
      IMPORTING !url          TYPE string
      RETURNING VALUE(result) TYPE zif_accx_fiori_repo=>ty_service.

    "! State text of a launchpad item: lost reference, content errors or warnings
    METHODS state_text
      IMPORTING !item         TYPE /ui2/if_fdm=>ts_item
      RETURNING VALUE(result) TYPE string.

    "! Deprecation of a launchpad item with its successor
    METHODS deprecation_text
      IMPORTING !item         TYPE /ui2/if_fdm=>ts_item
      RETURNING VALUE(result) TYPE string.

    "! Remembers a reference to an item of another catalog
    METHODS add_reference
      IMPORTING !item TYPE /ui2/if_fdm=>ts_item
                !kind TYPE string.

ENDCLASS.

CLASS zcl_accx_fiori_repo IMPLEMENTATION.

  METHOD zif_accx_fiori_repo~find_apps.
    load_apps( ).
    DATA(text) = condense( query ).
    DATA(upper) = to_upper( text ).
    IF text CA '-' AND text NA ` `.
      " intent: semantic object-action
      LOOP AT apps INTO DATA(app) WHERE intent IS NOT INITIAL.
        IF to_upper( app-intent ) = upper.
          APPEND app TO result.
        ENDIF.
      ENDLOOP.
    ELSEIF matches( val = upper pcre = `F\d{3,5}[A-Z]?` ).
      LOOP AT apps INTO app.
        SPLIT app-fiori_ids AT `,` INTO TABLE DATA(ids).
        IF line_exists( ids[ table_line = upper ] ).
          APPEND app TO result.
        ENDIF.
      ENDLOOP.
    ELSE.
      " transaction behind a GUI app, or every word in the title
      SPLIT upper AT ` ` INTO TABLE DATA(words).
      LOOP AT apps INTO app.
        IF app-app_type = zif_accx_fiori_repo=>co_app_type-gui AND app-target = upper.
          APPEND app TO result.
          CONTINUE.
        ENDIF.
        DATA(title) = to_upper( app-title ).
        IF title IS NOT INITIAL AND NOT line_exists( words[ table_line = `` ] ).
          DATA(all_found) = abap_true.
          LOOP AT words INTO DATA(word).
            IF title NS word.
              all_found = abap_false.
              EXIT.
            ENDIF.
          ENDLOOP.
          IF all_found = abap_true.
            APPEND app TO result.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_catalog.
    load_apps( ).
    DATA(id) = condense( catalog ).
    DATA(header) = VALUE #( catalog_headers[ catalog = id ] OPTIONAL ).
    IF header IS INITIAL.
      LOOP AT catalog_headers INTO DATA(candidate).
        IF to_upper( candidate-catalog ) = to_upper( id ).
          header = candidate.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF header IS INITIAL.
      RETURN.
    ENDIF.
    result = VALUE #( catalog    = header-catalog
                      title      = header-title
                      package    = header-package
                      changed_by = header-changed_by
                      changed_on = header-changed_on
                      apps       = VALUE #( FOR a IN apps WHERE ( catalog = header-catalog ) ( a ) )
                      tiles      = VALUE #( FOR t IN tiles WHERE ( catalog = header-catalog ) ( t ) ) ).
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_references.
    load_apps( ).
    LOOP AT item_references INTO DATA(item_reference) WHERE original_catalog = catalog.
      APPEND item_reference-reference TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_catalog_defaults.
    DATA delta TYPE /ui2/if_pfcg_cat_detail_bes=>tt_ui_delta_alv.

    " the pseudo URL of a catalog node in the role menu, with authorization defaults;
    " dark mode: no popup, the application log /UI2/PFCG is written only if there are messages
    CAST /ui2/if_pfcg_cat_detail_bes( NEW /ui2/cl_catalog_detail( ) )->get_content_for_pfcg(
      EXPORTING iv_url            = |X-SAP-UI2-CATALOGPAGE:{ catalog }?ROLE_ORIGIN={ sy-sysid }CLNT{ sy-mandt }| &&
                                    |&AUTH_DEFAULTS=X&DEST_FES=|
                iv_execution_mode = /ui2/if_pfcg_cat_detail_bes=>cs_execution_mode-dark_report
                iv_ui_action      = /ui2/if_pfcg_cat_detail_bes=>cs_ui_action-display
                it_ui_delta_alv   = delta
      IMPORTING et_appl_ok        = DATA(applications)
                et_message        = DATA(messages) ).
    LOOP AT messages INTO DATA(message) WHERE type CA 'EAW'.
      APPEND condense( message-message ) TO result-messages.
    ENDLOOP.
    LOOP AT applications INTO DATA(application).
      APPEND VALUE #( type     = application-type
                      name     = condense( application-name )
                      pgmid    = application-pgmid
                      object   = application-object
                      obj_name = condense( application-obj_name )
                      active   = abap_undefined ) TO result-defaults ASSIGNING FIELD-SYMBOL(<default>).
      IF <default>-object = 'IWSG'.
        SELECT SINGLE @abap_true FROM /iwfnd/i_med_srh
          WHERE srv_identifier = @<default>-obj_name AND is_active = 'A'
          INTO @DATA(active).
        <default>-active = xsdbool( active = abap_true ).
        CLEAR active.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD load_apps.
    TYPES: BEGIN OF ty_tile_title,
             catalog TYPE string,
             intent  TYPE string,
             title   TYPE string,
           END OF ty_tile_title.
    DATA tile_titles TYPE SORTED TABLE OF ty_tile_title WITH NON-UNIQUE KEY intent catalog.

    IF apps_loaded = abap_true.
      RETURN.
    ENDIF.
    apps_loaded = abap_true.

    TRY.
        DATA(api) = CAST /ui2/if_fdm_pub_catalog_api(
          NEW /ui2/cl_fdm_pub_catalog_api( iv_scope = /ui2/if_fdm_pub=>gc_scope-customization ) ).
        DATA(items) = api->get_catalog_items( it_catalog_key          = api->get_all_catalog_keys( )
                                              iv_include_support_data = abap_true ).
      CATCH /ui2/cx_fdm_input_invalid /ui2/cx_fdm_unexpected INTO DATA(error).
        RAISE EXCEPTION NEW zcx_accx_error( message = |Launchpad content could not be read: { error->get_text( ) }| ).
    ENDTRY.

    DATA(headers) = items->get_catalog_headers( ).
    LOOP AT headers INTO DATA(header).
      DATA(stamp) = |{ header-metadata-modified_on }|.
      APPEND VALUE #( catalog    = header-key-id
                      type       = header-key-type
                      title      = header-display-title_text
                      package    = header-metadata-package
                      changed_by = header-metadata-modified_by
                      changed_on = COND #( WHEN strlen( stamp ) >= 8 AND header-metadata-modified_on IS NOT INITIAL
                                           THEN |{ CONV d( substring( val = stamp len = 8 ) ) DATE = ISO }| ) )
        TO catalog_headers.
    ENDLOOP.

    LOOP AT items->get_tiles( ) INTO DATA(fdm_tile).
      DATA(tile) = VALUE zif_accx_fiori_repo=>ty_tile(
        catalog     = fdm_tile-key-parent_key-id
        tile_id     = fdm_tile-key-id
        title       = fdm_tile-display-title_text
        subtitle    = fdm_tile-display-subtitle_text
        tile_type   = fdm_tile-type
        navigation  = SWITCH #( fdm_tile-navigation-type
                                WHEN /ui2/if_fdm=>gc_tile_navigation_type-intent THEN zif_accx_fiori_repo=>co_navigation-intent
                                WHEN /ui2/if_fdm=>gc_tile_navigation_type-url    THEN zif_accx_fiori_repo=>co_navigation-url
                                ELSE zif_accx_fiori_repo=>co_navigation-none )
        consistent  = xsdbool( fdm_tile-state_content <> /ui2/if_fdm=>gc_state_content-content_error
                               AND fdm_tile-state_reference <> /ui2/if_fdm=>gc_state_reference-reference_lost )
        state_text  = state_text( fdm_tile-item )
        reference   = COND #( WHEN fdm_tile-ref_key-id IS NOT INITIAL
                              THEN |{ fdm_tile-ref_key-parent_key-id }/{ fdm_tile-ref_key-id }| )
        deprecation = deprecation_text( fdm_tile-item ) ).
      " navigation targets are boxed components: initial unless the navigation type uses them
      IF tile-navigation = zif_accx_fiori_repo=>co_navigation-intent
         AND fdm_tile-navigation-target-intent-semantic_object IS NOT INITIAL.
        tile-intent = |{ fdm_tile-navigation-target-intent-semantic_object }-{ fdm_tile-navigation-target-intent-semantic_action }|.
        INSERT VALUE #( catalog = tile-catalog intent = tile-intent title = tile-title ) INTO TABLE tile_titles.
      ELSEIF tile-navigation = zif_accx_fiori_repo=>co_navigation-url.
        tile-url = fdm_tile-navigation-target-url-url.
      ENDIF.
      IF fdm_tile-state_reference = /ui2/if_fdm=>gc_state_reference-reference_lost.
        " the launchpad shows a placeholder title
        CLEAR tile-title.
      ENDIF.
      APPEND tile TO tiles.
      add_reference( item = fdm_tile-item kind = zif_accx_fiori_repo=>co_item_kind-tile ).
    ENDLOOP.

    LOOP AT items->get_target_mappings( ) INTO DATA(mapping).
      DATA(app) = VALUE zif_accx_fiori_repo=>ty_app(
        catalog     = mapping-key-parent_key-id
        mapping_id  = mapping-key-id
        intent      = |{ mapping-navigation-semantic_object }-{ mapping-navigation-semantic_action }|
        title       = mapping-display-title_text
        app_type    = mapping-application-type
        fiori_ids   = concat_lines_of( table = mapping-support-fiori_ids sep = `,` )
        desktop     = xsdbool( mapping-navigation-form_factors-desktop IS NOT INITIAL )
        tablet      = xsdbool( mapping-navigation-form_factors-tablet IS NOT INITIAL )
        phone       = xsdbool( mapping-navigation-form_factors-phone IS NOT INITIAL )
        consistent  = xsdbool( mapping-state_content <> /ui2/if_fdm=>gc_state_content-content_error
                               AND mapping-state_reference <> /ui2/if_fdm=>gc_state_reference-reference_lost )
        state_text  = state_text( mapping-item )
        reference   = COND #( WHEN mapping-ref_key-id IS NOT INITIAL
                              THEN |{ mapping-ref_key-parent_key-id }/{ mapping-ref_key-id }| )
        deprecation = deprecation_text( mapping-item ) ).
      app-catalog_title = VALUE #( catalog_headers[ catalog = app-catalog ]-title OPTIONAL ).
      " target parts are boxed components: initial unless the type uses them
      app-target = SWITCH #( app-app_type
                             WHEN zif_accx_fiori_repo=>co_app_type-ui5 THEN mapping-application-target-ui5-component
                             WHEN zif_accx_fiori_repo=>co_app_type-gui
                             THEN COND #( WHEN mapping-transaction_code IS NOT INITIAL THEN mapping-transaction_code
                                          ELSE mapping-application-target-gui-transaction_code )
                             WHEN zif_accx_fiori_repo=>co_app_type-wda
                             THEN to_upper( mapping-application-target-wda-application )
                             WHEN zif_accx_fiori_repo=>co_app_type-url THEN mapping-application-target-url-uri ).
      IF app-title IS INITIAL.
        " the title users see is the one of the tile; prefer the tile of the same catalog
        LOOP AT tile_titles INTO DATA(tile_title) WHERE intent = app-intent AND title IS NOT INITIAL.
          app-title = tile_title-title.
          IF tile_title-catalog = app-catalog.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
      APPEND app TO apps.
      add_reference( item = mapping-item kind = zif_accx_fiori_repo=>co_item_kind-mapping ).
    ENDLOOP.
  ENDMETHOD.

  METHOD state_text.
    result = COND #( WHEN item-state_reference = /ui2/if_fdm=>gc_state_reference-reference_lost
                     THEN |reference lost (the original { item-ref_key-parent_key-id }/{ item-ref_key-id } no longer exists)|
                     WHEN item-state_content = /ui2/if_fdm=>gc_state_content-content_error   THEN `content contains errors`
                     WHEN item-state_content = /ui2/if_fdm=>gc_state_content-content_warning THEN `content contains warnings` ).
  ENDMETHOD.

  METHOD deprecation_text.
    result = SWITCH #( item-state_deprecation-deprecation
                       WHEN /ui2/if_fdm=>gc_state_deprecation-deprecated
                       THEN |deprecated{ COND #( WHEN item-state_deprecation-successor IS NOT INITIAL
                                                 THEN |, successor { item-state_deprecation-successor }| ) }|
                       WHEN /ui2/if_fdm=>gc_state_deprecation-archived THEN `archived` ).
  ENDMETHOD.

  METHOD add_reference.
    IF item-ref_key-id IS INITIAL OR item-ref_key-parent_key-id = item-key-parent_key-id.
      RETURN.
    ENDIF.
    APPEND VALUE #( original_catalog = item-ref_key-parent_key-id
                    reference        = VALUE #( catalog     = item-key-parent_key-id
                                                kind        = kind
                                                id          = item-key-id
                                                original_id = item-ref_key-id
                                                lost        = xsdbool( item-state_reference =
                                                                       /ui2/if_fdm=>gc_state_reference-reference_lost ) ) )
      TO item_references.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_role_catalogs.
    load_role_catalogs( ).
    LOOP AT role_catalogs INTO DATA(role_catalog).
      IF line_exists( roles[ table_line = role_catalog-role ] ).
        APPEND role_catalog TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_catalog_roles.
    load_role_catalogs( ).
    LOOP AT role_catalogs INTO DATA(role_catalog).
      IF line_exists( catalogs[ table_line = role_catalog-catalog ] ).
        APPEND role_catalog TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_role_menu_nodes.
    TYPES ty_hash_names TYPE STANDARD TABLE OF xupname WITH EMPTY KEY.
    DATA hash_names TYPE ty_hash_names.

    " transactions (TR) and start authorization nodes (OT SERVICE, URL OTSERVICE<name><TR|HT>);
    " PFCG puts the authorization defaults of a catalog below the catalog node (OT CAT_PROVIDER)
    SELECT h~object_id, h~parent_id, h~reporttype, h~report, b~url
      FROM agr_hier AS h LEFT OUTER JOIN agr_buffi AS b ON b~agr_name = h~agr_name AND b~object_id = h~object_id
      WHERE h~agr_name = @role
      ORDER BY h~object_id
      INTO TABLE @DATA(nodes).
    LOOP AT nodes INTO DATA(node).
      DATA(entry) = VALUE zif_accx_fiori_repo=>ty_menu_node( node = |{ node-object_id }| ).
      IF node-reporttype = 'TR'.
        entry-type = `TR`.
        entry-name = condense( node-report ).
      ELSEIF node-reporttype = 'OT' AND node-report = 'SERVICE' AND node-url CP 'OTSERVICE*' AND strlen( node-url ) > 11.
        entry-type = substring( val = node-url off = strlen( node-url ) - 2 len = 2 ).
        entry-name = condense( substring( val = node-url off = 9 len = strlen( node-url ) - 11 ) ).
      ELSE.
        CONTINUE.
      ENDIF.
      READ TABLE nodes INTO DATA(parent) WITH KEY object_id = node-parent_id.
      IF sy-subrc = 0 AND parent-reporttype = 'OT' AND parent-report = 'CAT_PROVIDER'.
        SPLIT parent-url AT ':' INTO DATA(prefix) DATA(rest) ##NEEDED.
        SPLIT rest AT '?' INTO entry-catalog DATA(parameters) ##NEEDED.
      ENDIF.
      IF entry-type = `HT`.
        APPEND CONV xupname( entry-name ) TO hash_names.
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.

    IF hash_names IS NOT INITIAL.
      SELECT name, object, obj_name FROM usobhash
        FOR ALL ENTRIES IN @hash_names WHERE name = @hash_names-table_line AND type = 'HT'
        INTO TABLE @DATA(hashes).
      LOOP AT result ASSIGNING FIELD-SYMBOL(<entry>) WHERE type = `HT`.
        READ TABLE hashes INTO DATA(hash) WITH KEY name = <entry>-name.
        IF sy-subrc = 0.
          <entry>-object   = hash-object.
          <entry>-obj_name = condense( hash-obj_name ).
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_role_content.
    load_role_catalogs( ).
    LOOP AT role_contents INTO DATA(content).
      IF line_exists( roles[ table_line = content-role ] ).
        APPEND content TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_groups.
    IF groups IS INITIAL.
      RETURN.
    ENDIF.
    " groups that do not exist are skipped by the API
    DATA(keys) = VALUE /ui2/if_fdm_pub=>tt_group_key( FOR g IN groups ( type = 'GRP' id = g ) ).
    TRY.
        DATA(items) = CAST /ui2/if_fdm_pub_group_api(
          NEW /ui2/cl_fdm_pub_group_api( iv_scope = /ui2/if_fdm_pub=>gc_scope-customization ) )->get_group_items( keys ).
      CATCH /ui2/cx_fdm_input_invalid /ui2/cx_fdm_not_found /ui2/cx_fdm_unexpected INTO DATA(error).
        RAISE EXCEPTION NEW zcx_accx_error( message = |Launchpad groups could not be read: { error->get_text( ) }| ).
    ENDTRY.
    DATA(group_tiles) = items->get_tiles( ).
    LOOP AT items->get_group_headers( ) INTO DATA(header).
      " a group tile refers to a tile of a catalog
      APPEND VALUE #( group = header-key-id
                      title = header-display-title_text
                      tiles = VALUE #( FOR t IN group_tiles WHERE ( key-parent_key-id = header-key-id )
                                       ( catalog = t-source_tile_key-parent_key-id tile_id = t-source_tile_key-id ) ) )
        TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_all_groups.
    TRY.
        DATA(keys) = CAST /ui2/if_fdm_pub_group_api(
          NEW /ui2/cl_fdm_pub_group_api( iv_scope = /ui2/if_fdm_pub=>gc_scope-customization ) )->get_all_group_keys( ).
      CATCH /ui2/cx_fdm_unexpected INTO DATA(error).
        RAISE EXCEPTION NEW zcx_accx_error( message = |Launchpad groups could not be read: { error->get_text( ) }| ).
    ENDTRY.
    result = zif_accx_fiori_repo~get_groups( VALUE #( FOR k IN keys ( CONV #( k-id ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_tile_pages.
    DATA keys TYPE /ui2/if_fdm_page_section_tile=>tt_tile_key.

    IF tiles IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        " catalog type (standard or replicated) from the catalog headers
        load_apps( ).
      CATCH zcx_accx_error ##NO_HANDLER.
        " standard catalogs assumed
    ENDTRY.
    LOOP AT tiles INTO DATA(tile).
      APPEND VALUE #( tile_catalog_id   = tile-catalog
                      tile_catalog_type = VALUE #( catalog_headers[ catalog = tile-catalog ]-type DEFAULT `CAT` )
                      tile_id           = tile-tile_id ) TO keys.
    ENDLOOP.
    TRY.
        DATA(page_api) = /ui2/cl_fdm_page_api_factory=>get_instance( ).
        page_api->set_scope( /ui2/if_fdm=>gc_scope-customization ).
        DATA(assignments) = page_api->get_page_ids_by_tiles( is_filter_conditions = VALUE #( tile_keys = keys ) ).
      CATCH /ui2/cx_fdm.
        RETURN.
    ENDTRY.
    LOOP AT assignments INTO DATA(assignment).
      LOOP AT assignment-page_ids INTO DATA(page).
        APPEND VALUE #( catalog = assignment-tile_catalog_id tile_id = assignment-tile_id page = page ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_space.
    " space templates live in the configuration scope, spaces in the customization scope
    DATA(scope) = COND /ui2/fdm_scope( WHEN template = abap_true THEN /ui2/if_fdm=>gc_scope-configuration
                                       ELSE /ui2/if_fdm=>gc_scope-customization ).
    TRY.
        DATA(space_api) = /ui2/cl_fdm_space_api_factory=>get_instance( ).
        space_api->set_scope( scope ).
        DATA(found) = space_api->get_space( CONV #( id ) ).
        DATA(page_api) = /ui2/cl_fdm_page_api_factory=>get_instance( ).
        page_api->set_scope( scope ).
      CATCH /ui2/cx_fdm_input_invalid /ui2/cx_fdm_not_found /ui2/cx_fdm_authorization.
        RETURN.
    ENDTRY.
    result = VALUE #( id = found->id title = found->title ).
    LOOP AT found->get_page_assignments( ) INTO DATA(assignment).
      DATA(page) = VALUE zif_accx_fiori_repo=>ty_page( page   = assignment-id
                                                       title  = assignment-title
                                                       hidden = xsdbool( assignment-hidden IS NOT INITIAL ) ).
      TRY.
          DATA(structure) = page_api->get_page_structure( assignment-id ).
          LOOP AT structure-sections INTO DATA(section).
            LOOP AT section-assignment_items INTO DATA(item) WHERE tile-tile_catalog_id IS NOT INITIAL.
              APPEND VALUE #( catalog = item-tile-tile_catalog_id tile_id = item-tile-tile_id ) TO page-tiles.
            ENDLOOP.
          ENDLOOP.
        CATCH /ui2/cx_fdm_not_found /ui2/cx_fdm_authorization ##NO_HANDLER.
          " assigned page that does not exist: no tiles
      ENDTRY.
      APPEND page TO result-pages.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_settings.
    DATA(settings) = CAST /ui2/if_flp_settings( NEW /ui2/cl_flp_settings_api( ) ).
    result-spaces      = xsdbool( settings->get_setting_param( 'SPACES' ) = /ui2/if_flp_settings=>gc_boolean-true ).
    result-user_switch = xsdbool( settings->get_setting_param( 'SPACES_ENABLE_USER' ) = /ui2/if_flp_settings=>gc_boolean-true ).
  ENDMETHOD.

  METHOD load_role_catalogs.
    IF roles_loaded = abap_true.
      RETURN.
    ENDIF.
    roles_loaded = abap_true.
    " menu URLs: X-SAP-UI2-CATALOGPAGE:<catalog>?<parameters>, sap-ui2-group:<group>, <space> or <space template>
    SELECT h~agr_name, h~report, b~url FROM agr_hier AS h
      INNER JOIN agr_buffi AS b ON b~agr_name = h~agr_name AND b~object_id = h~object_id
      WHERE h~reporttype = 'OT'
        AND h~report IN ('CAT_PROVIDER', 'GROUP_PROVIDER', 'SPACE_PROVIDER', 'SPACET_PROVIDER')
      INTO TABLE @DATA(entries).
    LOOP AT entries INTO DATA(entry).
      DATA(content) = VALUE zif_accx_fiori_repo=>ty_role_content( role = entry-agr_name ).
      CASE entry-report.
        WHEN 'CAT_PROVIDER'.
          SPLIT entry-url AT ':' INTO DATA(prefix) DATA(rest) ##NEEDED.
          SPLIT rest AT '?' INTO DATA(catalog) DATA(parameters) ##NEEDED.
          content-type = zif_accx_fiori_repo=>co_content_type-catalog.
          content-id   = catalog.
          IF catalog IS NOT INITIAL AND NOT line_exists( role_catalogs[ role = entry-agr_name catalog = catalog ] ).
            APPEND VALUE #( role = entry-agr_name catalog = catalog ) TO role_catalogs.
          ENDIF.
        WHEN 'GROUP_PROVIDER'.
          content-type = zif_accx_fiori_repo=>co_content_type-group.
          content-id   = substring_after( val = entry-url sub = ':' ).
        WHEN OTHERS.
          content-type     = zif_accx_fiori_repo=>co_content_type-flp_space.
          content-id       = condense( entry-url ).
          content-template = xsdbool( entry-report = 'SPACET_PROVIDER' ).
      ENDCASE.
      IF content-id IS NOT INITIAL AND NOT line_exists( role_contents[ role = content-role type = content-type id = content-id ] ).
        APPEND content TO role_contents.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_app_services.
    DATA dependencies TYPE /ui5/if_ui5_app_index=>tt_app_dependencies.
    DATA urls         TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    TRY.
        /ui5/cl_ui5_app_api_factory=>get_app_index_instance( )->get_ui5_app_info_json(
          EXPORTING it_components   = VALUE #( ( CONV #( component ) ) )
          IMPORTING et_dependencies = dependencies ).
      CATCH /ui5/cx_app_api_invalid_input INTO DATA(error).
        RAISE EXCEPTION NEW zcx_accx_error( message = |UI5 app index: { error->get_text( ) }| ).
    ENDTRY.
    LOOP AT dependencies INTO DATA(dependency).
      LOOP AT dependency-async_hints-cache_tokens-data_sources INTO DATA(source).
        IF source-url CS '/sap/opu/odata'.
          INSERT source-url INTO TABLE urls.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT urls INTO DATA(url).
      APPEND service_of_url( url ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_fiori_repo~get_service.
    DATA(url) = condense( name ).
    IF url NS '/sap/opu/'.
      " V2 service name: /NAMESPACE/NAME or NAME (namespace SAP)
      DATA(input) = to_upper( url ).
      DATA(namespace) = `SAP`.
      DATA(service) = input.
      FIND PCRE `^/([^/]+)/(.+)$` IN input SUBMATCHES namespace service.
      url = |/sap/opu/odata/{ namespace }/{ service };v={ COND #( WHEN version IS INITIAL THEN `0001` ELSE version ) }/|.
    ENDIF.
    result = service_of_url( url ).
    IF result-name IS INITIAL.
      RETURN.
    ENDIF.

    result-registered = xsdbool( result-identifier IS NOT INITIAL ).
    IF result-identifier IS NOT INITIAL.
      SELECT DISTINCT system_alias FROM /iwfnd/c_mgdeam WHERE service_id = @result-identifier
        ORDER BY system_alias INTO TABLE @DATA(aliases).
      result-aliases = VALUE #( FOR a IN aliases ( CONV #( a-system_alias ) ) ).
    ENDIF.

    " generic ICF node of the protocol: default_host/sap/opu/odata(4); the root node has parent FFF...
    DATA parent TYPE icfparguid VALUE 'FFFFFFFFFFFFFFFFFFFFFFFFF'.
    result-icf_active = abap_undefined.
    LOOP AT VALUE string_table( ( `DEFAULT_HOST` ) ( `SAP` ) ( `OPU` )
                                ( COND #( WHEN result-odata_version = `4.0` THEN `ODATA4` ELSE `ODATA` ) ) ) INTO DATA(node).
      SELECT SINGLE icfnodguid FROM icfservice WHERE icf_name = @node AND icfparguid = @parent INTO @DATA(guid).
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      SELECT SINGLE icfactive FROM icfservloc WHERE icf_name = @node AND icfparguid = @parent INTO @DATA(active).
      IF active = abap_false.
        result-icf_active = abap_false.
        RETURN.
      ENDIF.
      parent = guid.
    ENDLOOP.
    result-icf_active = abap_true.
  ENDMETHOD.

  METHOD service_of_url.
    DATA namespace TYPE string.
    DATA name      TYPE string.
    DATA version   TYPE string.
    DATA group     TYPE string.
    DATA suffix    TYPE string ##NEEDED.

    result-url = url.
    IF url CS '/sap/opu/odata4/'.
      " /sap/opu/odata4/<namespace>/<service group>/<repository>/<namespace>/<service>/<version>/
      result-odata_version = `4.0`.
      FIND PCRE `/sap/opu/odata4/([^/]+)/([^/]+)/[^/]+/[^/]+/([^/]+)/([^/]+)` IN url
           SUBMATCHES namespace group name version.
      result-name    = to_upper( name ).
      result-version = version.
      " publication of V4 service groups is not checked; the start check is S_START R3TR G4BA <group>
      result-active  = abap_undefined.
      SELECT name AS hash, object, obj_name FROM usobhash
        WHERE type = 'HT' AND object = 'G4BA' AND obj_name = @( to_upper( group ) )
        INTO CORRESPONDING FIELDS OF TABLE @result-hashes.
      RETURN.
    ENDIF.

    " /sap/opu/odata/<namespace>/<service>[;v=<version>]/
    result-odata_version = `2.0`.
    FIND PCRE `/sap/opu/odata/([^/;]+)/([^/;?]+)(;v=(\d+))?` IN url SUBMATCHES namespace name suffix version.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    namespace = to_upper( namespace ).
    namespace = COND #( WHEN namespace = `SAP` THEN `` ELSE |/{ namespace }/| ).
    name      = to_upper( name ).
    version   = COND #( WHEN version IS INITIAL THEN `0001` ELSE |{ CONV numc4( version ) }| ).
    result-name    = |{ namespace }{ name }|.
    result-version = version.

    SELECT srv_identifier, is_active FROM /iwfnd/i_med_srh
      WHERE namespace = @namespace AND service_name = @name AND service_version = @version
      INTO TABLE @DATA(registrations).
    DATA identifier TYPE /iwfnd/med_mdl_srg_identifier.
    identifier = VALUE #( registrations[ is_active = 'A' ]-srv_identifier OPTIONAL ).
    result-active = xsdbool( identifier IS NOT INITIAL ).
    result-identifier = COND #( WHEN identifier IS NOT INITIAL THEN identifier
                                ELSE VALUE #( registrations[ 1 ]-srv_identifier OPTIONAL ) ).

    " frontend: gateway service (IWSG); backend: service <namespace><name> with version (IWSV)
    DATA(backend) = |{ result-name }%|.
    SELECT name, object, obj_name FROM usobhash
      WHERE type = 'HT'
        AND ( ( object = 'IWSG' AND obj_name = @identifier AND obj_name <> @space ) OR ( object = 'IWSV' AND obj_name LIKE @backend ) )
      INTO TABLE @DATA(hashes).
    LOOP AT hashes INTO DATA(hash).
      IF hash-object = 'IWSV' AND condense( hash-obj_name ) <> |{ result-name } { version }|.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( object = hash-object hash = hash-name obj_name = condense( hash-obj_name ) ) TO result-hashes.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
