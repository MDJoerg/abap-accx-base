"! <p class="shorttext synchronized">Access Explorer: built-in CORE plugin</p>
"! Contributes the core tool set, prompts and resources. Always active (no
"! ZACCX_PLUGIN entry needed).
CLASS zcl_accx_core_plugin DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_plugin.

ENDCLASS.

CLASS zcl_accx_core_plugin IMPLEMENTATION.

  METHOD zif_accx_plugin~get_info.
    result = VALUE #( id                = zcl_accx_registry=>co_core_plugin_id
                      title             = `Access Explorer core tools`
                      version           = zif_accx_types=>co_release
                      required_core_api = zif_accx_plugin=>co_core_api_version ).
  ENDMETHOD.

  METHOD zif_accx_plugin~check_prerequisites.
    result-ok = abap_true.
  ENDMETHOD.

  METHOD zif_accx_plugin~get_tools.
    result = VALUE #( ( NEW zcl_accx_t_get_user_profile( ) )
                      ( NEW zcl_accx_t_check_user_access( ) )
                      ( NEW zcl_accx_t_explain_missing( ) )
                      ( NEW zcl_accx_t_get_failed_checks( ) )
                      ( NEW zcl_accx_t_run_critical_check( ) )
                      ( NEW zcl_accx_t_find_users( ) )
                      ( NEW zcl_accx_t_find_roles( ) )
                      ( NEW zcl_accx_t_draft_role_change( ) )
                      ( NEW zcl_accx_t_diagnose_fiori_app( ) )
                      ( NEW zcl_accx_t_get_user_launchpad( ) )
                      ( NEW zcl_accx_t_find_fiori_app( ) )
                      ( NEW zcl_accx_t_get_catalog_details( ) )
                      ( NEW zcl_accx_t_get_role_details( ) )
                      ( NEW zcl_accx_t_get_user_auths( ) )
                      ( NEW zcl_accx_t_get_service_access( ) )
                      ( NEW zcl_accx_t_get_role_auths( ) )
                      ( NEW zcl_accx_t_compare_roles( ) )
                      ( NEW zcl_accx_t_check_role_health( ) )
                      ( NEW zcl_accx_t_compare_users( ) )
                      ( NEW zcl_accx_t_analyze_user_group( ) )
                      ( NEW zcl_accx_t_user_hygiene( ) )
                      ( NEW zcl_accx_t_get_auth_changes( ) )
                      ( NEW zcl_accx_t_get_cds_access( ) )
                      ( NEW zcl_accx_t_find_unprot_cds( ) )
                      ( NEW zcl_accx_t_simulate_cds( ) ) ).
  ENDMETHOD.

  METHOD zif_accx_plugin~get_prompts.
    result = VALUE #( ( NEW zcl_accx_p_diagnose_access( ) )
                      ( NEW zcl_accx_p_fiori_app( ) )
                      ( NEW zcl_accx_p_access_review( ) ) ).
  ENDMETHOD.

  METHOD zif_accx_plugin~get_resources.
    result = VALUE #( ( NEW zcl_accx_r_tool_guide( ) )
                      ( NEW zcl_accx_r_glossary( ) )
                      ( NEW zcl_accx_r_faq( ) ) ).
  ENDMETHOD.

ENDCLASS.
