"! <p class="shorttext synchronized">Access Explorer: plugin-based tool registry</p>
"! Discovers all implementations of ZIF_ACCX_PLUGIN. The CORE plugin is always
"! active; any other plugin needs an active entry in ZACCX_PLUGIN (decision E6).
"! Failures of a plugin only skip that plugin and are reported via get_issues.
CLASS zcl_accx_registry DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_registry.

    CONSTANTS co_core_plugin_id   TYPE string VALUE `CORE`.
    CONSTANTS co_plugin_interface TYPE seoclsname VALUE 'ZIF_ACCX_PLUGIN'.

  PRIVATE SECTION.
    TYPES ty_plugins TYPE STANDARD TABLE OF REF TO zif_accx_plugin WITH EMPTY KEY.
    TYPES: BEGIN OF ty_cached,
             profile TYPE string,
             tools   TYPE zif_accx_plugin=>ty_tools,
           END OF ty_cached.

    TYPES: BEGIN OF ty_guidance,
             profile   TYPE string,
             prompts   TYPE zif_accx_plugin=>ty_prompts,
             resources TYPE zif_accx_plugin=>ty_resources,
           END OF ty_guidance.

    DATA cache          TYPE HASHED TABLE OF ty_cached WITH UNIQUE KEY profile.
    DATA guidance_cache TYPE HASHED TABLE OF ty_guidance WITH UNIQUE KEY profile.
    DATA issues TYPE zif_accx_registry=>ty_issues.

    METHODS load_tools
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE zif_accx_plugin=>ty_tools.

    "! Prompts and resources of the active plugins, loaded once per profile
    METHODS get_guidance
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE ty_guidance.

    METHODS load_guidance
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE ty_guidance.

    METHODS get_active_plugins
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE ty_plugins.

    "! Empty result = all groups
    METHODS get_profile_groups
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE string_table.

    "! Comma separated list, trimmed and upper case
    METHODS split_list
      IMPORTING !list         TYPE csequence
      RETURNING VALUE(result) TYPE string_table.

    METHODS add_issue
      IMPORTING !plugin_id TYPE csequence
                !message   TYPE csequence.

ENDCLASS.

CLASS zcl_accx_registry IMPLEMENTATION.

  METHOD zif_accx_registry~get_tools.
    READ TABLE cache INTO DATA(cached) WITH TABLE KEY profile = profile.
    IF sy-subrc = 0.
      result = cached-tools.
      RETURN.
    ENDIF.
    result = load_tools( profile ).
    INSERT VALUE #( profile = profile tools = result ) INTO TABLE cache.
  ENDMETHOD.

  METHOD zif_accx_registry~get_tool.
    LOOP AT zif_accx_registry~get_tools( profile ) INTO DATA(tool).
      IF tool->get_descriptor( )-name = name.
        result = tool.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_registry~get_prompts.
    result = get_guidance( profile )-prompts.
  ENDMETHOD.

  METHOD zif_accx_registry~get_resources.
    result = get_guidance( profile )-resources.
  ENDMETHOD.

  METHOD get_guidance.
    READ TABLE guidance_cache INTO result WITH TABLE KEY profile = profile.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    result = load_guidance( profile ).
    INSERT result INTO TABLE guidance_cache.
  ENDMETHOD.

  METHOD load_guidance.
    DATA prompt_names   TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA resource_uris  TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    result-profile = profile.
    LOOP AT get_active_plugins( profile ) INTO DATA(plugin).
      DATA(plugin_id) = ``.
      DATA(plugin_prompts) = VALUE zif_accx_plugin=>ty_prompts( ).
      DATA(plugin_resources) = VALUE zif_accx_plugin=>ty_resources( ).
      TRY.
          plugin_id = plugin->get_info( )-id.
          LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
            DATA(prompt_name) = prompt->get_descriptor( )-name.
            IF prompt_name IS INITIAL OR line_exists( prompt_names[ table_line = prompt_name ] ).
              add_issue( plugin_id = plugin_id message = |Prompt without name or duplicate name { prompt_name } ignored| ).
              CONTINUE.
            ENDIF.
            INSERT prompt_name INTO TABLE prompt_names.
            APPEND prompt TO plugin_prompts.
          ENDLOOP.
          LOOP AT plugin->get_resources( ) INTO DATA(resource).
            DATA(resource_uri) = resource->get_descriptor( )-uri.
            IF resource_uri IS INITIAL OR line_exists( resource_uris[ table_line = resource_uri ] ).
              add_issue( plugin_id = plugin_id message = |Resource without URI or duplicate URI { resource_uri } ignored| ).
              CONTINUE.
            ENDIF.
            INSERT resource_uri INTO TABLE resource_uris.
            APPEND resource TO plugin_resources.
          ENDLOOP.
        CATCH cx_root INTO DATA(error).
          add_issue( plugin_id = plugin_id message = error->get_text( ) ).
          CONTINUE.
      ENDTRY.
      APPEND LINES OF plugin_prompts TO result-prompts.
      APPEND LINES OF plugin_resources TO result-resources.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_registry~get_issues.
    result = issues.
  ENDMETHOD.

  METHOD load_tools.
    DATA names TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA(groups) = get_profile_groups( profile ).

    LOOP AT get_active_plugins( profile ) INTO DATA(plugin).
      DATA(plugin_id) = ``.
      DATA(plugin_tools) = VALUE zif_accx_plugin=>ty_tools( ).
      TRY.
          plugin_id = plugin->get_info( )-id.
          LOOP AT plugin->get_tools( ) INTO DATA(tool).
            DATA(descriptor) = tool->get_descriptor( ).
            IF groups IS NOT INITIAL AND NOT line_exists( groups[ table_line = to_upper( descriptor-group ) ] ).
              CONTINUE.
            ENDIF.
            IF line_exists( names[ table_line = descriptor-name ] ).
              add_issue( plugin_id = plugin_id message = |Duplicate tool name { descriptor-name } ignored| ).
              CONTINUE.
            ENDIF.
            INSERT descriptor-name INTO TABLE names.
            APPEND tool TO plugin_tools.
          ENDLOOP.
        CATCH cx_root INTO DATA(error).
          add_issue( plugin_id = plugin_id message = error->get_text( ) ).
          CONTINUE.
      ENDTRY.
      APPEND LINES OF plugin_tools TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_active_plugins.
    TYPES: BEGIN OF ty_ranked,
             rank   TYPE i,
             plugin TYPE REF TO zif_accx_plugin,
           END OF ty_ranked.
    DATA ranked TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.
    DATA plugin TYPE REF TO zif_accx_plugin.
    DATA implementers TYPE seo_relkeys.

    TRY.
        implementers = NEW cl_oo_interface( co_plugin_interface )->get_implementing_classes( ).
      CATCH cx_class_not_existent.
        RETURN.
    ENDTRY.

    SELECT plugin_id, active, priority, profiles FROM zaccx_plugin INTO TABLE @DATA(settings).

    LOOP AT implementers INTO DATA(implementer).
      CLEAR plugin.
      TRY.
          CREATE OBJECT plugin TYPE (implementer-clsname).
          DATA(info) = plugin->get_info( ).
        CATCH cx_root INTO DATA(error).
          add_issue( plugin_id = implementer-clsname message = error->get_text( ) ).
          CONTINUE.
      ENDTRY.

      DATA(rank) = 0.
      IF to_upper( info-id ) = co_core_plugin_id.
        rank = cl_abap_math=>max_int4.
      ELSE.
        READ TABLE settings INTO DATA(setting) WITH KEY plugin_id = to_upper( info-id ).
        IF sy-subrc <> 0 OR setting-active = abap_false.
          " discovered but not activated
          CONTINUE.
        ENDIF.
        IF setting-profiles IS NOT INITIAL AND setting-profiles <> '*'.
          DATA(allowed_profiles) = split_list( setting-profiles ).
          IF NOT line_exists( allowed_profiles[ table_line = to_upper( profile ) ] ).
            CONTINUE.
          ENDIF.
        ENDIF.
        rank = setting-priority.
      ENDIF.

      IF info-required_core_api <> zif_accx_plugin=>co_core_api_version.
        add_issue( plugin_id = info-id
                   message   = |Requires core API { info-required_core_api }, installed { zif_accx_plugin=>co_core_api_version }| ).
        CONTINUE.
      ENDIF.

      TRY.
          DATA(check) = plugin->check_prerequisites( ).
        CATCH cx_root INTO error.
          add_issue( plugin_id = info-id message = error->get_text( ) ).
          CONTINUE.
      ENDTRY.
      IF check-ok = abap_false.
        add_issue( plugin_id = info-id message = check-message ).
        CONTINUE.
      ENDIF.

      APPEND VALUE #( rank = rank plugin = plugin ) TO ranked.
    ENDLOOP.

    SORT ranked BY rank DESCENDING.
    result = VALUE #( FOR entry IN ranked ( entry-plugin ) ).
  ENDMETHOD.

  METHOD get_profile_groups.
    SELECT SINGLE tool_groups FROM zaccx_profile WHERE profile = @profile INTO @DATA(groups).
    IF sy-subrc <> 0 OR groups IS INITIAL OR groups = '*'.
      RETURN.
    ENDIF.
    result = split_list( groups ).
  ENDMETHOD.

  METHOD split_list.
    SPLIT list AT ',' INTO TABLE DATA(parts).
    LOOP AT parts INTO DATA(part).
      part = to_upper( condense( part ) ).
      IF part IS NOT INITIAL.
        APPEND part TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_issue.
    " the plugins are walked once for the tools and once for the guidance
    IF line_exists( issues[ plugin_id = plugin_id message = message ] ).
      RETURN.
    ENDIF.
    APPEND VALUE #( plugin_id = plugin_id message = message ) TO issues.
  ENDMETHOD.

ENDCLASS.
