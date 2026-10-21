CLASS ltd_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo.
ENDCLASS.

CLASS ltd_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'JDOE' OR user = 'NOAUTH' OR user = 'HIDDEN' OR user = 'LOCKED' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result-user = user.
    IF user = 'LOCKED'.
      result-locked       = abap_true.
      result-lock_reasons = `locked by administrator`.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments ##NEEDED.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_profile_assignments ##NEEDED.
  ENDMETHOD.
ENDCLASS.

"! Evaluator double: JDOE and LOCKED pass checks; records the last simulated check
CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator.
    DATA last_check TYPE zif_accx_auth_evaluator=>ty_check.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~transaction_exists.
    result = xsdbool( tcode = 'SU01' ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = xsdbool( object = 'S_TABU_DIS' ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    result = VALUE #( ( object = 'S_TCODE' fields = VALUE #( ( field = 'TCD' value = tcode ) ) reason = `start` ) ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~simulate.
    last_check = check.
    DATA(ok) = xsdbool( user = 'JDOE' OR user = 'LOCKED' ).
    result = VALUE #( object      = check-object
                      condition   = `test`
                      granted     = ok
                      return_code = COND #( WHEN ok = abap_true THEN 0 ELSE 12 )
                      outcome     = COND #( WHEN ok = abap_true THEN `granted` ELSE `missing` ) ).
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

CLASS ltc_check_user_access DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut       TYPE REF TO zif_accx_tool.
    DATA evaluator TYPE REF TO ltd_evaluator.
    DATA ctx       TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS args_for
      IMPORTING !user         TYPE string
                !target_type  TYPE string DEFAULT `transaction`
                !target       TYPE string
      RETURNING VALUE(result) TYPE REF TO zcl_accx_args_map.
    METHODS run
      IMPORTING !args         TYPE REF TO zcl_accx_args_map
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_result
      RAISING   zcx_accx_error.
    METHODS expect_status
      IMPORTING !args   TYPE REF TO zcl_accx_args_map
                !status TYPE string.

    METHODS transaction_granted         FOR TESTING RAISING zcx_accx_error.
    METHODS transaction_missing         FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_transaction         FOR TESTING.
    METHODS unknown_user                FOR TESTING.
    METHODS user_not_displayable        FOR TESTING.
    METHODS authorization_values_parsed FOR TESTING RAISING zcx_accx_error.
    METHODS locked_user_flagged         FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_check_user_access IMPLEMENTATION.

  METHOD setup.
    evaluator = NEW ltd_evaluator( ).
    zcl_accx_domain_factory=>inject( user_repo = NEW ltd_repo( ) auth_evaluator = evaluator ).
    cut = NEW zcl_accx_t_check_user_access( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD args_for.
    result = NEW zcl_accx_args_map( ).
    result->set( name = `user` value = user ).
    result->set( name = `target_type` value = target_type ).
    result->set( name = `target` value = target ).
  ENDMETHOD.

  METHOD run.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
  ENDMETHOD.

  METHOD expect_status.
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( |Expected status { status }| ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = status act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD transaction_granted.
    DATA(result) = run( args_for( user = `jdoe` target = `su01` ) ).
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_check_user_access=>ty_payload.
    ASSIGN result-data->* TO <payload>.
    cl_abap_unit_assert=>assert_true( <payload>-granted ).
    cl_abap_unit_assert=>assert_true( <payload>-logon_possible ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User **JDOE** **may** start transaction SU01*` act = result-summary ).
    cl_abap_unit_assert=>assert_initial( result-warnings ).
  ENDMETHOD.

  METHOD transaction_missing.
    DATA(result) = run( args_for( user = `NOAUTH` target = `SU01` ) ).
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_check_user_access=>ty_payload.
    ASSIGN result-data->* TO <payload>.
    cl_abap_unit_assert=>assert_false( <payload>-granted ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*may not*` act = result-summary ).
    " SU53 side effect must be pointed out
    cl_abap_unit_assert=>assert_not_initial( result-warnings ).
  ENDMETHOD.

  METHOD unknown_transaction.
    expect_status( args   = args_for( user = `JDOE` target = `ZZZ_NOPE` )
                   status = zif_accx_types=>co_status-not_found ).
  ENDMETHOD.

  METHOD unknown_user.
    expect_status( args   = args_for( user = `NOBODY` target = `SU01` )
                   status = zif_accx_types=>co_status-not_found ).
  ENDMETHOD.

  METHOD user_not_displayable.
    expect_status( args   = args_for( user = `HIDDEN` target = `SU01` )
                   status = zif_accx_types=>co_status-denied ).
  ENDMETHOD.

  METHOD authorization_values_parsed.
    DATA(args) = args_for( user = `JDOE` target_type = `authorization` target = `s_tabu_dis` ).
    args->set_list( name = `values` values = VALUE #( ( `actvt = 02` ) ( `DICBERCLS=SC` ) ( `bogus` ) ) ).
    run( args ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_TABU_DIS' act = evaluator->last_check-object ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zif_accx_auth_evaluator=>ty_field_values( ( field = 'ACTVT' value = `02` )
                                                            ( field = 'DICBERCLS' value = `SC` )
                                                            ( field = 'BOGUS' value = `` ) )
      act = evaluator->last_check-fields ).
  ENDMETHOD.

  METHOD locked_user_flagged.
    " AUTHORITY-CHECK FOR USER grants for locked users - the tool must say so
    DATA(result) = run( args_for( user = `LOCKED` target = `SU01` ) ).
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_check_user_access=>ty_payload.
    ASSIGN result-data->* TO <payload>.
    cl_abap_unit_assert=>assert_true( <payload>-granted ).
    cl_abap_unit_assert=>assert_false( <payload>-logon_possible ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*would be authorized to*cannot log on*locked by administrator*` act = result-summary ).
    cl_abap_unit_assert=>assert_not_initial( result-warnings ).
  ENDMETHOD.

ENDCLASS.
