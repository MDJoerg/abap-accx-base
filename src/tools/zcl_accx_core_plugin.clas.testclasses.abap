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
