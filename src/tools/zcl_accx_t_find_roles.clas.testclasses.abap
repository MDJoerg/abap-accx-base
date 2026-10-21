"! RSUSR070 result: R_A (single, 1 user), R_B (composite, 5 users), R_C (single, no users), R_HIDDEN
CLASS ltd_gateway DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_suim_gateway PARTIALLY IMPLEMENTED.
    DATA last_query TYPE zif_accx_suim_gateway=>ty_role_query.
ENDCLASS.

CLASS ltd_gateway IMPLEMENTATION.
  METHOD zif_accx_suim_gateway~find_roles.
    last_query = query.
    result-roles = VALUE #( ( role = 'R_A' text = `Role A` role_type = 'S' )
                            ( role = 'R_B' text = `Combo` role_type = 'C' )
                            ( role = 'R_C' text = `R_C` role_type = 'S' )
                            ( role = 'R_HIDDEN' text = `Hidden` role_type = 'S' ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
    DATA last_roles TYPE zif_accx_role_repo=>ty_roles.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~count_assigned_users.
    last_roles = roles.
    result = VALUE #( ( role = 'R_A' users = 1 ) ( role = 'R_B' users = 5 ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~transaction_exists.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = xsdbool( object <> 'S_NOPE' ).
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

CLASS ltc_find_roles DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut       TYPE REF TO zif_accx_tool.
    DATA ctx       TYPE REF TO zif_accx_context.
    DATA gateway   TYPE REF TO ltd_gateway.
    DATA role_repo TYPE REF TO ltd_role_repo.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !args    TYPE REF TO zcl_accx_args_map
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_find_roles=>ty_payload
      RAISING   zcx_accx_error.
    METHODS expect_error
      IMPORTING !args   TYPE REF TO zcl_accx_args_map
                !status TYPE string.

    METHODS most_used_first    FOR TESTING RAISING zcx_accx_error.
    METHODS query_mapping      FOR TESTING RAISING zcx_accx_error.
    METHODS criterion_required FOR TESTING.
    METHODS unknown_object     FOR TESTING.
ENDCLASS.

CLASS ltc_find_roles IMPLEMENTATION.

  METHOD setup.
    gateway = NEW ltd_gateway( ).
    role_repo = NEW ltd_role_repo( ).
    zcl_accx_domain_factory=>inject( suim_gateway   = gateway
                                     role_repo      = role_repo
                                     auth_evaluator = NEW ltd_evaluator( ) ).
    cut = NEW zcl_accx_t_find_roles( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_find_roles=>ty_payload.
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

  METHOD most_used_first.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `transaction` value = `SM37` ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    " hidden role neither listed nor counted
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( role_repo->last_roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = `R_B` act = payload-roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = `composite` act = payload-roles[ 1 ]-role_type ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = payload-roles[ 3 ]-assigned_users ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 'EQ' act = gateway->last_query-transactions[ 1 ]-option ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**3** roles granting transaction SM37, most used first:*- **R_B** (Combo), composite, 5 users*`
                                         act = result-summary ).
    " description equal to the name is not repeated
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **R_C**, single, 0 users*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use find_users with role R_B*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD query_mapping.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `description` value = `Monitor` ).
    args->set( name = `assigned_to_user` value = `accx*` ).
    args->set( name = `role_type` value = `single` ).
    args->set( name = `object` value = `S_BTCH_ADM` ).
    run( EXPORTING args = args IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = '*Monitor*' act = gateway->last_query-descriptions[ 1 ]-low ).
    cl_abap_unit_assert=>assert_equals( exp = 'CP' act = gateway->last_query-descriptions[ 1 ]-option ).
    cl_abap_unit_assert=>assert_equals( exp = 'ACCX*' act = gateway->last_query-users[ 1 ]-low ).
    cl_abap_unit_assert=>assert_true( gateway->last_query-single ).
    cl_abap_unit_assert=>assert_false( gateway->last_query-composite ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_BTCH_ADM' act = gateway->last_query-object ).
    cl_abap_unit_assert=>assert_equals(
      exp = `with description *Monitor*, with authorization S_BTCH_ADM, assigned to ACCX*, single roles only`
      act = payload-criteria ).
  ENDMETHOD.

  METHOD criterion_required.
    expect_error( args = NEW zcl_accx_args_map( )->set( name = `role_type` value = `single` )
                  status = zif_accx_types=>co_status-invalid ).
  ENDMETHOD.

  METHOD unknown_object.
    expect_error( args = NEW zcl_accx_args_map( )->set( name = `object` value = `S_NOPE` )
                  status = zif_accx_types=>co_status-not_found ).
  ENDMETHOD.

ENDCLASS.
