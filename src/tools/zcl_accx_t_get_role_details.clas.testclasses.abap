"! ZR: single role (2 users, in composite ZC and hidden ZHIDDEN, reference of ZD), menu SE16, catalog C1,
"! one open field, empty org level $BUKRS, profile not generated, user comparison pending for 1 user;
"! ZD: derived from ZR, in sync apart from the organizational level field PLVAR; ZD2: derived from ZR, lacks a value;
"! ZC: composite without single roles
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~exists.
    result = xsdbool( role = 'ZR' OR role = 'ZD' OR role = 'ZD2' OR role = 'ZC' OR role = 'ZSECRET' ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role description = |Role { role }| object_count = 5 ).
    CASE role.
      WHEN 'ZR'.
        result-parents = VALUE #( ( `ZC` ) ( `ZHIDDEN` ) ).
      WHEN 'ZD' OR 'ZD2'.
        result-derived_from = 'ZR'.
        result-generated    = abap_true.
      WHEN 'ZC'.
        result-composite    = abap_true.
        result-object_count = 0.
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_transactions.
    IF role = 'ZR'.
      result = VALUE #( ( `SE16` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorization_values.
    result = VALUE #( ( object = 'S_TCODE' auth = 'A1' field = 'TCD' low = 'SE16' )
                      ( object = 'PLOG' auth = 'A2' field = 'PLVAR' low = COND #( WHEN role = 'ZR' THEN '$PLVAR' ELSE '01' ) ) ).
    IF role <> 'ZD2'.
      APPEND VALUE #( object = 'S_TABU_DIS' auth = 'A3' field = 'ACTVT' low = '03' ) TO result.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_org_fields.
    result = VALUE #( ( `PLVAR` ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_derived_roles.
    IF role = 'ZR'.
      result = VALUE #( ( 'ZD' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    IF line_exists( roles[ table_line = 'ZR' ] ).
      INSERT VALUE #( role = 'ZR' users = 2 ) INTO TABLE result.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_maintenance.
    IF role <> 'ZR'.
      result = VALUE #( profiles = VALUE #( ( `T-1` ) ) standard = 3 ).
      RETURN.
    ENDIF.
    result = VALUE #( profiles           = VALUE #( ( `T-0` ) )
                      standard           = 2
                      maintained         = 1
                      manual             = 1
                      open_fields        = VALUE #( ( `S_TABU_DIS-DICBERCLS` ) )
                      org_levels         = VALUE #( ( level = `$BUKRS` ) )
                      comparison_pending = 1
                      changed_by         = `ADMIN`
                      changed_on         = '20261020' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_role_content.
    IF line_exists( roles[ table_line = 'ZR' ] ).
      result = VALUE #( ( role = 'ZR' type = zif_accx_fiori_repo=>co_content_type-catalog id = `C1` )
                        ( role = 'ZR' type = zif_accx_fiori_repo=>co_content_type-flp_space id = `S1` template = abap_true ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides roles ZHIDDEN and ZSECRET
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'ZHIDDEN' AND role <> 'ZSECRET' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_role_details DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !role    TYPE string
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_role_details=>ty_payload
      RAISING   zcx_accx_error.

    METHODS single_role_with_findings FOR TESTING RAISING zcx_accx_error.
    METHODS derived_role_menu         FOR TESTING RAISING zcx_accx_error.
    METHODS derived_out_of_sync       FOR TESTING RAISING zcx_accx_error.
    METHODS empty_composite           FOR TESTING RAISING zcx_accx_error.
    METHODS refusals                  FOR TESTING.
ENDCLASS.

CLASS ltc_get_role_details IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( role_repo = NEW ltd_role_repo( ) fiori_repo = NEW ltd_fiori( ) ).
    cut = NEW zcl_accx_t_get_role_details( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_role_details=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = role ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD single_role_with_findings.
    run( EXPORTING role = `zr` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `single` act = payload-role_type ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZC` ) ) act = payload-composite_roles ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZD` ) ) act = payload-derived_roles ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C1` ) ) act = payload-catalogs ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S1 (template)` ) ) act = payload-spaces ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-assigned_users ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = lines( payload-findings ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `open_fields` ) ( `org_level_empty` ) ( `profile_not_generated` )
                                                                  ( `user_comparison_pending` ) )
                                        act = payload-finding_codes ).
    cl_abap_unit_assert=>assert_char_cp( exp = `1 open field*S_TABU_DIS-DICBERCLS` act = payload-findings[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `Organizational level $BUKRS has no value.` act = payload-findings[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Profile not generated*` act = payload-findings[ 3 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User comparison pending: 1 of 2 users*` act = payload-findings[ 4 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Role **ZR** (Role ZR): single role, 2 users today.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*2 standard, 1 maintained, 0 changed, 1 manual, 0 inactive*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*$BUKRS=(empty)*Profile: T-0, **not generated**; last changed by ADMIN on 2026-10-20*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*run the user comparison (PFUD)*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD derived_role_menu.
    run( EXPORTING role = `ZD` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `derived` act = payload-role_type ).
    cl_abap_unit_assert=>assert_equals( exp = `ZR` act = payload-derived_from ).
    " the menu is the reference role's
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SE16` ) ) act = payload-transactions ).
    cl_abap_unit_assert=>assert_initial( payload-findings ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*role derived from ZR, 0 users today.*Menu (of ZR): 1 transaction (SE16)*No consistency findings.*`
                                         act = result-summary ).
  ENDMETHOD.

  METHOD derived_out_of_sync.
    run( EXPORTING role = `ZD2` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS ACTVT=03` ) ) act = payload-reference_diff-only_a ).
    cl_abap_unit_assert=>assert_initial( payload-reference_diff-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `derived_out_of_sync` ) ) act = payload-finding_codes ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Not in sync with reference role ZR: values only in the reference role 1, only in this role 0 (e.g. S_TABU_DIS ACTVT=03).`
                                         act = payload-findings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use compare_roles with role_a ZR and role_b ZD2*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD empty_composite.
    run( EXPORTING role = `ZC` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `composite` act = payload-role_type ).
    cl_abap_unit_assert=>assert_initial( payload-maintenance ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Composite role without single roles: it grants nothing.` ) )
                                        act = payload-findings ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Single roles: none*` act = result-summary ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( `ZNONE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( `ZSECRET` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
