"! C1: T1 lost reference (on page P1), T2 navigates to O-run (target mapping only in C9), T3 to D-run (no
"! target mapping anywhere), T4 to A-show (M1, in group G1, deprecated); M2 lost reference. C2 refers to C1
"! (one reference lost). Roles: R_A and R_HIDDEN contain C1. C0: empty, in no role, no authorization defaults.
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_catalog.
    DATA(intent) = zif_accx_fiori_repo=>co_navigation-intent.
    CASE to_upper( catalog ).
      WHEN `C1`.
        result = VALUE #(
          catalog = `C1` title = `Catalog one` package = `ZPKG` changed_by = `DEV` changed_on = `2026-10-01`
          tiles   = VALUE #( catalog = `C1`
                             ( tile_id = `T4` title = `Fine` intent = `A-show` deprecation = `deprecated`
                               consistent = abap_true navigation = intent )
                             ( tile_id = `T1` consistent = abap_false navigation = zif_accx_fiori_repo=>co_navigation-none
                               reference = `ORIG/X1` state_text = `reference lost (the original ORIG/X1 no longer exists)` )
                             ( tile_id = `T2` title = `Orphan` intent = `O-run` consistent = abap_true navigation = intent )
                             ( tile_id = `T3` title = `Dead` intent = `D-run` consistent = abap_true navigation = intent ) )
          apps    = VALUE #( catalog = `C1`
                             ( mapping_id = `M1` intent = `A-show` title = `Fine` consistent = abap_true )
                             ( mapping_id = `M2` intent = `B-run` reference = `ORIG/Y1`
                               state_text = `reference lost (the original ORIG/Y1 no longer exists)` ) ) ).
      WHEN `C0`.
        result = VALUE #( catalog = `C0` title = `Empty` ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~find_apps.
    IF query = `O-run`.
      result = VALUE #( ( catalog = `C9` intent = `O-run` consistent = abap_true ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_references.
    IF catalog = `C1`.
      result = VALUE #( kind = zif_accx_fiori_repo=>co_item_kind-tile
                        ( catalog = `C2` id = `R1` original_id = `T4` )
                        ( catalog = `C2` id = `R2` original_id = `T9` lost = abap_true ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_tile_pages.
    IF line_exists( tiles[ tile_id = `T1` ] ).
      result = VALUE #( ( catalog = `C1` tile_id = `T1` page = `P1` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_all_groups.
    result = VALUE #( ( group = `G1` tiles = VALUE #( ( catalog = `C1` tile_id = `T4` ) ( catalog = `C2` tile_id = `R1` ) ) ) ).
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_roles.
    IF line_exists( catalogs[ table_line = `C1` ] ).
      result = VALUE #( catalog = `C1` ( role = 'R_A' ) ( role = 'R_HIDDEN' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_defaults.
    IF catalog = `C1`.
      result-defaults = VALUE #( ( type = `TR` name = `SE16` pgmid = `R3TR` object = `TRAN` obj_name = `SE16` active = abap_undefined )
                                 ( type = `HT` name = `H1` pgmid = `R3TR` object = `IWSG` obj_name = `/Z/SRV_0001` active = abap_false )
                                 ( type = `HT` name = `H2` pgmid = `R3TR` object = `WDYA` obj_name = `ZWDA` active = abap_undefined ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~count_assigned_users.
    result = VALUE #( ( role = 'R_A' users = 4 ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'R_HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_catalog_details DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !catalog       TYPE string
                !with_defaults TYPE abap_bool DEFAULT abap_false
      EXPORTING !result        TYPE zif_accx_types=>ty_result
                !payload       TYPE zcl_accx_t_get_catalog_details=>ty_payload
      RAISING   zcx_accx_error.

    METHODS problems_first_with_usage   FOR TESTING RAISING zcx_accx_error.
    METHODS next_steps_and_warnings     FOR TESTING RAISING zcx_accx_error.
    METHODS defaults_and_unused_catalog FOR TESTING RAISING zcx_accx_error.
    METHODS not_found_and_invalid       FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_get_catalog_details IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( fiori_repo = NEW ltd_fiori( )
                                     role_repo  = NEW ltd_role_repo( ) ).
    cut = NEW zcl_accx_t_get_catalog_details( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_catalog_details=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `catalog_id` value = catalog ).
    IF with_defaults = abap_true.
      args->set( name = `with_defaults` value = `true` ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD problems_first_with_usage.
    run( EXPORTING catalog = `c1` IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_equals( exp = `C1` act = payload-catalog ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-tile_count ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-mapping_count ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-problems-lost_references ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-problems-tiles_without_mapping ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-problems-tiles_without_target ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-problems-deprecated_items ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-problems-lost_references_elsewhere ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = payload-problems-content_errors ).

    " inconsistent first, then without target mapping (by title), then deprecated
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `T1` ) ( `T3` ) ( `T2` ) ( `T4` ) )
                                        act = VALUE string_table( FOR t IN payload-tiles ( t-tile_id ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C9` ) ) act = payload-tiles[ 3 ]-mapping_catalogs ).
    cl_abap_unit_assert=>assert_equals( exp = `M1` act = payload-tiles[ 4 ]-mapping_id ).
    cl_abap_unit_assert=>assert_equals( exp = `M2` act = payload-target_mappings[ 1 ]-mapping_id ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-target_mappings[ 2 ]-tiles ).

    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `P1` ) ) act = payload-pages ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `G1` ) ) act = payload-groups ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `G1` ) ) act = payload-tiles[ 4 ]-groups ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-roles[ 1 ]-assigned_users ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-hidden_roles ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).

    cl_abap_unit_assert=>assert_char_cp( exp = `*R_A (4 users); 1 hidden*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*2 lost references (original deleted)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*2 tiles without target mapping in the catalog, 1 without any*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*tile T3 "Dead": no target mapping for D-run*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*target mapping M2 (B-run): reference lost*` act = result-summary ).
  ENDMETHOD.

  METHOD next_steps_and_warnings.
    run( EXPORTING catalog = `C1` IMPORTING result = DATA(result) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Remove the 2 lost references*originals in ORIG; pages P1 show such tiles.`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Tile "Dead" navigates to D-run, but no catalog*` act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Tile "Orphan" navigates to O-run, whose target mapping is only in C9*`
                                         act = result-next_steps[ 3 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*find_fiori_app*` act = result-next_steps[ 4 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = lines( result-next_steps ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `1 references in 1 other catalogs (C2) point to deleted items of C1*`
                                         act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD defaults_and_unused_catalog.
    run( EXPORTING catalog = `C1` with_defaults = abap_true IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE string_table( ( `S_TCODE TCD=SE16` )
                                ( `S_SERVICE SRV_NAME=H1, SRV_TYPE=HT (IWSG /Z/SRV_0001) - service not active` )
                                ( `S_START AUTHPGMID=R3TR, AUTHOBJTYP=WDYA, AUTHOBJNAM=ZWDA` ) )
      act = payload-authorization_defaults ).

    run( EXPORTING catalog = `C0` with_defaults = abap_true IMPORTING result = DATA(result) payload = payload ).
    cl_abap_unit_assert=>assert_initial( payload-authorization_defaults ).
    cl_abap_unit_assert=>assert_char_cp( exp = `PFCG reads no authorization defaults for C0*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No role contains C0*"add_catalogs":["C0"]*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( result-next_steps ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*No inconsistencies found.*` act = result-summary ).
  ENDMETHOD.

  METHOD not_found_and_invalid.
    TRY.
        run( `NOPE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( `  ` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
