"! Integration test on the real system: registry discovery, runtime catalog
"! and real checks of the calling user only (no other user, so no SU53 noise).
CLASS ltc_integration DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA runtime TYPE REF TO zif_accx_runtime.
    DATA ctx     TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS registry_finds_core_tools FOR TESTING.
    METHODS catalog_lists_core_tools  FOR TESTING.
    METHODS own_user_profile          FOR TESTING.
    METHODS own_transaction_check     FOR TESTING.
    METHODS own_failed_checks         FOR TESTING.
ENDCLASS.

CLASS ltc_integration IMPLEMENTATION.

  METHOD setup.
    runtime = NEW zcl_accx_runtime_local( registry = NEW zcl_accx_registry( ) ).
    ctx = NEW zcl_accx_context( profile  = `test/integration`
                                max_rows = 50
                                guard    = NEW zcl_accx_caller_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD registry_finds_core_tools.
    DATA registry TYPE REF TO zif_accx_registry.
    registry = NEW zcl_accx_registry( ).
    DATA(tools) = registry->get_tools( `test/integration` ).
    cl_abap_unit_assert=>assert_bound( registry->get_tool( name = zcl_accx_t_get_user_profile=>co_name profile = `test/integration` ) ).
    cl_abap_unit_assert=>assert_bound( registry->get_tool( name = zcl_accx_t_check_user_access=>co_name profile = `test/integration` ) ).
    cl_abap_unit_assert=>assert_number_between( lower = 2 upper = 1000 number = lines( tools ) ).
  ENDMETHOD.

  METHOD catalog_lists_core_tools.
    DATA(catalog) = runtime->get_catalog( ctx ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( catalog[ name = zcl_accx_t_get_user_profile=>co_name ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( catalog[ name = zcl_accx_t_check_user_access=>co_name ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( catalog[ name = zcl_accx_t_get_failed_checks=>co_name ] ) ) ).
  ENDMETHOD.

  METHOD own_user_profile.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = sy-uname ).
    DATA(result) = runtime->execute( tool_name = zcl_accx_t_get_user_profile=>co_name args = args ctx = ctx ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status msg = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = |**{ sy-uname }***| act = result-summary ).
  ENDMETHOD.

  METHOD own_transaction_check.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = sy-uname ).
    args->set( name = `target_type` value = `transaction` ).
    args->set( name = `target` value = `SU53` ).
    DATA(result) = runtime->execute( tool_name = zcl_accx_t_check_user_access=>co_name args = args ctx = ctx ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status msg = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = |User **{ sy-uname }** *start transaction SU53*| act = result-summary ).
  ENDMETHOD.

  METHOD own_failed_checks.
    " reading the own SU53 buffer needs no authorization; content depends on the system
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = sy-uname ).
    DATA(result) = runtime->execute( tool_name = zcl_accx_t_get_failed_checks=>co_name args = args ctx = ctx ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status msg = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = |*{ sy-uname }*| act = result-summary ).
  ENDMETHOD.

ENDCLASS.

"! Prompts and resources of the CORE plugin: consistent with the tool set and free of
"! leftovers of the text generation
CLASS ltc_guidance DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA plugin TYPE REF TO zif_accx_plugin.

    METHODS setup.
    "! Tools of the core plugin
    METHODS core_tools
      RETURNING VALUE(result) TYPE string_table.
    "! Core tools plus the tools of the ADMIN plugin (this package must not reference it)
    METHODS all_tools
      RETURNING VALUE(result) TYPE string_table.
    METHODS render
      IMPORTING !prompt       TYPE REF TO zif_accx_prompt
                !args         TYPE REF TO zcl_accx_args_map
      RETURNING VALUE(result) TYPE zif_accx_prompt=>ty_result.

    METHODS prompts_rely_on_core_tools    FOR TESTING.
    METHODS prompts_are_described         FOR TESTING.
    METHODS prompts_render_their_tools    FOR TESTING.
    METHODS prompts_check_required        FOR TESTING.
    METHODS review_period_is_checked      FOR TESTING.
    METHODS registry_offers_core_guidance FOR TESTING.
    METHODS resources_are_unique          FOR TESTING.
    METHODS resources_have_text           FOR TESTING.
    METHODS tool_guide_covers_every_tool  FOR TESTING.
    METHODS tool_guide_hides_unavailable  FOR TESTING.
ENDCLASS.

CLASS ltc_guidance IMPLEMENTATION.

  METHOD setup.
    plugin = NEW zcl_accx_core_plugin( ).
  ENDMETHOD.

  METHOD core_tools.
    LOOP AT plugin->get_tools( ) INTO DATA(tool).
      APPEND tool->get_descriptor( )-name TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD all_tools.
    result = core_tools( ).
    APPEND `apply_role_change` TO result.
    APPEND `assign_role` TO result.
  ENDMETHOD.

  METHOD render.
    result = prompt->render( args ).
  ENDMETHOD.

  METHOD prompts_rely_on_core_tools.
    DATA(tools) = core_tools( ).
    cl_abap_unit_assert=>assert_not_initial( plugin->get_prompts( ) ).
    LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
      DATA(descriptor) = prompt->get_descriptor( ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-tools ).
      LOOP AT descriptor-tools INTO DATA(tool).
        cl_abap_unit_assert=>assert_true( act = xsdbool( line_exists( tools[ table_line = tool ] ) )
                                          msg = |Prompt { descriptor-name } relies on unknown tool { tool }| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD prompts_are_described.
    DATA names TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
      DATA(descriptor) = prompt->get_descriptor( ).
      cl_abap_unit_assert=>assert_true( act = xsdbool( matches( val = descriptor-name pcre = `[a-z]+(_[a-z]+)*` ) )
                                        msg = |Prompt name { descriptor-name }| ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-title ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-description ).
      INSERT descriptor-name INTO TABLE names.
      cl_abap_unit_assert=>assert_subrc( msg = |Duplicate prompt { descriptor-name }| ).
      LOOP AT descriptor-arguments INTO DATA(argument).
        cl_abap_unit_assert=>assert_not_initial( act = argument-name msg = |Argument of { descriptor-name }| ).
        cl_abap_unit_assert=>assert_not_initial( act = argument-description msg = |Argument { argument-name } of { descriptor-name }| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD prompts_render_their_tools.
    LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
      DATA(descriptor) = prompt->get_descriptor( ).
      DATA(args) = NEW zcl_accx_args_map( ).
      LOOP AT descriptor-arguments INTO DATA(argument).
        args->set( name = argument-name value = |VALUE_{ sy-tabix }| ).
      ENDLOOP.
      DATA(result) = render( prompt = prompt args = args ).
      cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status msg = descriptor-name ).
      cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( result-messages ) ).
      DATA(text) = result-messages[ 1 ]-text.
      " the instruction names every tool it relies on and every value the user gave
      LOOP AT descriptor-tools INTO DATA(tool).
        cl_abap_unit_assert=>assert_true( act = xsdbool( contains( val = text sub = tool ) )
                                          msg = |{ descriptor-name } does not mention { tool }| ).
      ENDLOOP.
      LOOP AT descriptor-arguments INTO argument.
        IF argument-name = `period_days`.
          CONTINUE.
        ENDIF.
        cl_abap_unit_assert=>assert_true( act = xsdbool( contains( val = text sub = |VALUE_{ sy-tabix }| ) )
                                          msg = |{ descriptor-name } does not use { argument-name }| ).
      ENDLOOP.
      " no leftovers of placeholders or template escapes
      cl_abap_unit_assert=>assert_false( act = xsdbool( text CA `{}\` ) msg = |Leftover in { descriptor-name }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD prompts_check_required.
    LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
      DATA(descriptor) = prompt->get_descriptor( ).
      DATA(any_required) = abap_false.
      LOOP AT descriptor-arguments INTO DATA(argument) WHERE required = abap_true.
        any_required = abap_true.
      ENDLOOP.
      DATA(result) = render( prompt = prompt args = NEW zcl_accx_args_map( ) ).
      cl_abap_unit_assert=>assert_equals( exp = COND string( WHEN any_required = abap_true THEN zif_accx_types=>co_status-invalid
                                                             ELSE zif_accx_types=>co_status-ok )
                                          act = result-status
                                          msg = descriptor-name ).
    ENDLOOP.
  ENDMETHOD.

  METHOD review_period_is_checked.
    DATA review TYPE REF TO zif_accx_prompt.
    LOOP AT plugin->get_prompts( ) INTO DATA(prompt).
      IF prompt->get_descriptor( )-name = `quarterly_access_review`.
        review = prompt.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_bound( review ).

    DATA(thirty) = render( prompt = review args = NEW zcl_accx_args_map( )->set( name = `period_days` value = `30` )->set( name = `user_group` value = `SUPER` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*last 30 days*` act = thirty-messages[ 1 ]-text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*user group "SUPER"*` act = thirty-messages[ 1 ]-text ).

    " anything but 1 to 366 falls back to 90 days and the whole system
    DATA(bad_values) = VALUE string_table( ( `abc` ) ( `0` ) ( `367` ) ( `-5` ) ( `1000` ) ).
    LOOP AT bad_values INTO DATA(bad).
      DATA(fallback) = render( prompt = review args = NEW zcl_accx_args_map( )->set( name = `period_days` value = bad ) ).
      cl_abap_unit_assert=>assert_char_cp( exp = `*last 90 days*` act = fallback-messages[ 1 ]-text msg = bad ).
      cl_abap_unit_assert=>assert_char_cp( exp = `*for all users*` act = fallback-messages[ 1 ]-text ).
    ENDLOOP.
  ENDMETHOD.

  METHOD registry_offers_core_guidance.
    DATA registry TYPE REF TO zif_accx_registry.
    registry = NEW zcl_accx_registry( ).
    cl_abap_unit_assert=>assert_true( xsdbool( lines( registry->get_prompts( `test/unit` ) ) >= lines( plugin->get_prompts( ) ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lines( registry->get_resources( `test/unit` ) ) >= lines( plugin->get_resources( ) ) ) ).
  ENDMETHOD.

  METHOD resources_are_unique.
    DATA uris TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    cl_abap_unit_assert=>assert_not_initial( plugin->get_resources( ) ).
    LOOP AT plugin->get_resources( ) INTO DATA(resource).
      DATA(descriptor) = resource->get_descriptor( ).
      cl_abap_unit_assert=>assert_char_cp( exp = `accx://*` act = descriptor-uri ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-name ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-title ).
      cl_abap_unit_assert=>assert_not_initial( descriptor-description ).
      cl_abap_unit_assert=>assert_equals( exp = `text/markdown` act = descriptor-mime_type ).
      INSERT descriptor-uri INTO TABLE uris.
      cl_abap_unit_assert=>assert_subrc( msg = |Duplicate resource { descriptor-uri }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD resources_have_text.
    LOOP AT plugin->get_resources( ) INTO DATA(resource).
      DATA(text) = resource->read( all_tools( ) ).
      cl_abap_unit_assert=>assert_char_cp( exp = `## *` act = text msg = resource->get_descriptor( )-uri ).
      cl_abap_unit_assert=>assert_false( act = xsdbool( text CA `{}\` ) msg = |Leftover in { resource->get_descriptor( )-uri }| ).
      " lines must stay readable for the client: no line feed at the very start or end
      cl_abap_unit_assert=>assert_false( act = xsdbool( substring( val = text len = 1 ) = cl_abap_char_utilities=>newline ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD tool_guide_covers_every_tool.
    " a new tool without an entry in the guide fails here
    DATA guide TYPE REF TO zif_accx_resource.
    LOOP AT plugin->get_resources( ) INTO DATA(resource).
      IF resource->get_descriptor( )-uri = `accx://tool-guide`.
        guide = resource.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_bound( guide ).
    DATA(text) = guide->read( all_tools( ) ).
    LOOP AT all_tools( ) INTO DATA(tool).
      cl_abap_unit_assert=>assert_true( act = xsdbool( contains( val = text sub = |`{ tool }`| ) )
                                        msg = |Tool guide does not mention { tool }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD tool_guide_hides_unavailable.
    DATA guide TYPE REF TO zif_accx_resource.
    LOOP AT plugin->get_resources( ) INTO DATA(resource).
      IF resource->get_descriptor( )-uri = `accx://tool-guide`.
        guide = resource.
      ENDIF.
    ENDLOOP.
    DATA(text) = guide->read( VALUE #( ( `get_user_profile` ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( contains( val = text sub = `get_user_profile` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( contains( val = text sub = `find_users` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( contains( val = text sub = `assign_role` ) ) ).
    " the rules for all tools stay
    cl_abap_unit_assert=>assert_true( xsdbool( contains( val = text sub = `Rules for all tools` ) ) ).
    " a question with several tools is listed only if all of them are available
    DATA(partial) = guide->read( VALUE #( ( `get_failed_authorization_checks` ) ( `check_user_access` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( contains( val = partial sub = `lacks an authorization` ) ) ).
  ENDMETHOD.

ENDCLASS.
