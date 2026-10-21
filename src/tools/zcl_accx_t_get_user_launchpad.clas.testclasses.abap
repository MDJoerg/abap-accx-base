"! U1: R_SPACE (space S1), R_CAT (catalogs C_A, C_NONE; also an expired assignment), R_OLD expired
"! (catalog C_OLD, group G1), R_HIDDEN (catalog C_B, group G2; the caller may not display it)
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'U1' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    result = VALUE #( ( role = 'R_SPACE'  active = abap_true  valid_to = '99991231' )
                      ( role = 'R_CAT'    active = abap_false valid_to = '20200101' )
                      ( role = 'R_CAT'    active = abap_true  valid_to = '99991231' )
                      ( role = 'R_OLD'    active = abap_false valid_to = '20200101' )
                      ( role = 'R_HIDDEN' active = abap_true  valid_to = '99991231' ) ).
  ENDMETHOD.
ENDCLASS.

"! S1: page P1 with tiles from C_A, C_B, C_X; hidden page P2 with a tile from C_Y
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
    CLASS-DATA spaces TYPE abap_bool.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_settings.
    result = VALUE #( spaces = spaces user_switch = abap_false ).
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_role_content.
    DATA(all) = VALUE zif_accx_fiori_repo=>ty_role_contents(
      ( role = 'R_SPACE'  type = zif_accx_fiori_repo=>co_content_type-flp_space id = `S1` )
      ( role = 'R_CAT'    type = zif_accx_fiori_repo=>co_content_type-catalog   id = `C_A` )
      ( role = 'R_CAT'    type = zif_accx_fiori_repo=>co_content_type-catalog   id = `C_NONE` )
      ( role = 'R_OLD'    type = zif_accx_fiori_repo=>co_content_type-catalog   id = `C_OLD` )
      ( role = 'R_OLD'    type = zif_accx_fiori_repo=>co_content_type-group     id = `G1` )
      ( role = 'R_HIDDEN' type = zif_accx_fiori_repo=>co_content_type-catalog   id = `C_B` )
      ( role = 'R_HIDDEN' type = zif_accx_fiori_repo=>co_content_type-group     id = `G2` ) ).
    LOOP AT all INTO DATA(content).
      IF line_exists( roles[ table_line = content-role ] ).
        APPEND content TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog.
    result = SWITCH #( catalog
      WHEN `C_A`   THEN VALUE #( catalog = `C_A` title = `Catalog A`
                                 apps = VALUE #( ( intent = `A-x` ) ( intent = `A-y` ) ( intent = `A-x` ) ) )
      WHEN `C_B`   THEN VALUE #( catalog = `C_B` title = `Catalog B` apps = VALUE #( ( intent = `B-x` ) ) )
      WHEN `C_OLD` THEN VALUE #( catalog = `C_OLD` title = `Old` apps = VALUE #( ( intent = `O-x` ) ) ) ).
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_groups.
    DATA(all) = VALUE zif_accx_fiori_repo=>ty_groups(
      ( group = `G1` title = `Group 1` tiles = VALUE #( ( catalog = `C_OLD` tile_id = `T1` ) ) )
      ( group = `G2` title = `Group 2` tiles = VALUE #( ( catalog = `C_B` tile_id = `T2` ) ) ) ).
    LOOP AT all INTO DATA(group).
      IF line_exists( groups[ table_line = group-group ] ).
        APPEND group TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_space.
    IF id = `S1`.
      result = VALUE #( id = `S1` title = `Space 1`
                        pages = VALUE #( ( page = `P1` title = `Page 1`
                                           tiles = VALUE #( ( catalog = `C_A` tile_id = `T1` )
                                                            ( catalog = `C_B` tile_id = `T2` )
                                                            ( catalog = `C_X` tile_id = `T3` ) ) )
                                         ( page = `P2` title = `Page 2` hidden = abap_true
                                           tiles = VALUE #( ( catalog = `C_Y` tile_id = `T4` ) ) ) ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
    CLASS-DATA composite TYPE abap_bool.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role composite = xsdbool( role = 'R_SPACE' AND composite = abap_true ) ).
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

CLASS ltc_get_user_launchpad DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user    TYPE string DEFAULT `U1`
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_user_launchpad=>ty_payload
      RAISING   zcx_accx_error.

    METHODS content_and_hidden_tiles FOR TESTING RAISING zcx_accx_error.
    METHODS composite_not_drafted    FOR TESTING RAISING zcx_accx_error.
    METHODS groups_home_ignores_pages FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_user             FOR TESTING.
ENDCLASS.

CLASS ltc_get_user_launchpad IMPLEMENTATION.

  METHOD setup.
    ltd_fiori=>spaces = abap_true.
    ltd_role_repo=>composite = abap_false.
    zcl_accx_domain_factory=>inject( user_repo  = NEW ltd_user_repo( )
                                     role_repo  = NEW ltd_role_repo( )
                                     fiori_repo = NEW ltd_fiori( ) ).
    cut = NEW zcl_accx_t_get_user_launchpad( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_user_launchpad=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD content_and_hidden_tiles.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_equals( exp = `spaces` act = payload-home ).
    " catalogs of displayable roles only; C_B of R_HIDDEN still makes its tile visible
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-catalogs ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = `active` act = payload-catalogs[ catalog = `C_A` ]-state ).
    cl_abap_unit_assert=>assert_equals( exp = `R_CAT` act = payload-catalogs[ catalog = `C_A` ]-roles[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `missing` act = payload-catalogs[ catalog = `C_NONE` ]-state ).
    cl_abap_unit_assert=>assert_equals( exp = `not_valid_today` act = payload-catalogs[ catalog = `C_OLD` ]-state ).
    cl_abap_unit_assert=>assert_equals( exp = `R_OLD (expired on 2020-01-01)` act = payload-catalogs[ catalog = `C_OLD` ]-roles[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-apps ).

    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-groups ) ).
    cl_abap_unit_assert=>assert_equals( exp = `not_valid_today` act = payload-groups[ group = `G1` ]-state ).

    DATA(page) = payload-spaces[ space_id = `S1` ]-pages[ page = `P1` ].
    cl_abap_unit_assert=>assert_equals( exp = 3 act = page-tiles ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = page-visible_tiles ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C_X` ) ) act = page-missing_catalogs ).
    " the hidden page P2 does not count
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C_X` ) ) act = payload-missing_catalogs ).
    cl_abap_unit_assert=>assert_equals( exp = `R_SPACE` act = payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*"role":"R_SPACE","add_catalogs":["C_X"]*` act = payload-draft_arguments ).

    cl_abap_unit_assert=>assert_char_cp( exp = `*catalog C_NONE*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( result-next_steps[ table_line = `Launchpad content of R_OLD (expired on 2020-01-01) is not shown: extend the role assignment via the access request process if it is still needed.` ] ) ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*2 of 3 tiles visible; catalogs missing: C_X*` act = result-summary ).
  ENDMETHOD.

  METHOD composite_not_drafted.
    ltd_role_repo=>composite = abap_true.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C_X` ) ) act = payload-missing_catalogs ).
    cl_abap_unit_assert=>assert_initial( payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Tiles from C_X stay hidden*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD groups_home_ignores_pages.
    ltd_fiori=>spaces = abap_false.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `groups` act = payload-home ).
    cl_abap_unit_assert=>assert_initial( payload-missing_catalogs ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Spaces** (not shown: the home page uses groups)*` act = result-summary ).
  ENDMETHOD.

  METHOD unknown_user.
    TRY.
        run( `NOPE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
