"! RSUSR002 result: U2 (locked), U1 (no name), EXPIRED (valid to 2020), HIDDEN (not displayable)
CLASS ltd_gateway DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_suim_gateway PARTIALLY IMPLEMENTED.
    DATA last_query TYPE zif_accx_suim_gateway=>ty_user_query.
ENDCLASS.

CLASS ltd_gateway IMPLEMENTATION.
  METHOD zif_accx_suim_gateway~find_users.
    last_query = query.
    result-users = VALUE #( ( user = 'U2' name = `User Two` user_type = 'A' user_group = 'TEST' lock = `Administrator` )
                            ( user = 'U1' name = `U1` user_type = 'S' user_group = 'TEST' )
                            ( user = 'EXPIRED' name = `EXPIRED` user_type = 'A' valid_to = '20200101' )
                            ( user = 'HIDDEN' name = `HIDDEN` user_type = 'A' ) ).
    result-messages = VALUE #( ( `SUIM W 01/878: incomplete` ) ).
  ENDMETHOD.
ENDCLASS.

"! Z_ROLE: active for U1 and EXPIRED, expired for U2
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~get_role_assignments.
    result = VALUE #( ( role = 'Z_ROLE' active = xsdbool( user <> 'U2' ) ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~transaction_exists.
    result = xsdbool( tcode <> 'NOPE' ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = xsdbool( user <> 'HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_find_users DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut     TYPE REF TO zif_accx_tool.
    DATA ctx     TYPE REF TO zif_accx_context.
    DATA gateway TYPE REF TO ltd_gateway.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !args    TYPE REF TO zcl_accx_args_map
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_find_users=>ty_payload
      RAISING   zcx_accx_error.
    METHODS expect_error
      IMPORTING !args   TYPE REF TO zcl_accx_args_map
                !status TYPE string.

    METHODS by_authorization_values FOR TESTING RAISING zcx_accx_error.
    METHODS role_pattern_and_tcode  FOR TESTING RAISING zcx_accx_error.
    METHODS criterion_required      FOR TESTING.
    METHODS values_need_object      FOR TESTING.
    METHODS unknown_transaction     FOR TESTING.
ENDCLASS.

CLASS ltc_find_users IMPLEMENTATION.

  METHOD setup.
    gateway = NEW ltd_gateway( ).
    zcl_accx_domain_factory=>inject( suim_gateway   = gateway
                                     user_repo      = NEW ltd_user_repo( )
                                     auth_evaluator = NEW ltd_evaluator( ) ).
    cut = NEW zcl_accx_t_find_users( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_find_users=>ty_payload.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD expect_error.
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( |{ status } expected| ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = status act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD by_authorization_values.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `object` value = `s_develop` ).
    args->set_list( name = `values` values = VALUE #( ( `objtype=DEBUG` ) ( `ACTVT=02` ) ( `ACTVT=03` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).

    " same field twice = alternatives
    cl_abap_unit_assert=>assert_equals( exp = 'S_DEVELOP' act = gateway->last_query-object ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( gateway->last_query-values ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'OBJTYPE' act = gateway->last_query-values[ 1 ]-field ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( gateway->last_query-values[ 2 ]-values ) ).
    " expired and hidden users left out, sorted, name equal to the ID dropped
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-users ) ).
    cl_abap_unit_assert=>assert_equals( exp = `U1` act = payload-users[ 1 ]-user ).
    cl_abap_unit_assert=>assert_initial( payload-users[ 1 ]-name ).
    cl_abap_unit_assert=>assert_equals( exp = `service` act = payload-users[ 1 ]-user_type ).
    cl_abap_unit_assert=>assert_true( payload-users[ 2 ]-locked ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-not_valid_today ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**2** users with authorization S_DEVELOP with OBJTYPE=DEBUG, ACTVT=02 or 03:*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **U2** (User Two), dialog, group TEST, **locked** (Administrator)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*1 user that is not valid today left out*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use find_roles*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*01/878*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD role_pattern_and_tcode.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `z*` ).
    args->set( name = `transaction` value = `sm37` ).
    args->set( name = `exclude_locked` value = `true` ).
    args->set( name = `valid_users_only` value = `false` ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 'CP' act = gateway->last_query-roles[ 1 ]-option ).
    cl_abap_unit_assert=>assert_equals( exp = 'Z*' act = gateway->last_query-roles[ 1 ]-low ).
    cl_abap_unit_assert=>assert_equals( exp = 'SM37' act = gateway->last_query-transaction ).
    cl_abap_unit_assert=>assert_true( gateway->last_query-unlocked_only ).
    " validity filter off: the expired user stays; U2's role assignment has expired (SUIM still lists it)
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-users ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-role_assignment_inactive ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*1 user left out whose assignment of the role is not valid today*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = `with role Z*, who may start transaction SM37, not locked` act = payload-criteria ).
  ENDMETHOD.

  METHOD criterion_required.
    expect_error( args = NEW zcl_accx_args_map( )->set( name = `user` value = `ACCX*` )
                  status = zif_accx_types=>co_status-invalid ).
  ENDMETHOD.

  METHOD values_need_object.
    expect_error( args = NEW zcl_accx_args_map( )->set_list( name = `values` values = VALUE #( ( `ACTVT=02` ) ) )
                  status = zif_accx_types=>co_status-invalid ).
  ENDMETHOD.

  METHOD unknown_transaction.
    expect_error( args = NEW zcl_accx_args_map( )->set( name = `transaction` value = `NOPE` )
                  status = zif_accx_types=>co_status-not_found ).
  ENDMETHOD.

ENDCLASS.
