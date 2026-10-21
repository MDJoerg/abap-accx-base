"! Test double: tool with one required and one enum parameter.
"! user = FAIL raises zcx_accx_error, user = CRASH raises a runtime exception,
"! otherwise returns three rows containing the user name.
CLASS ltd_tool DEFINITION FINAL FOR TESTING
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.
ENDCLASS.

CLASS ltd_tool IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #( name      = `echo_user`
                      title     = `Echo user`
                      group     = zif_accx_types=>co_group-user
                      read_only = abap_true
                      params    = VALUE #( ( param( name = `user` description = `User id` required = abap_true ) )
                                           ( param( name        = `mode`
                                                    description = `Output mode`
                                                    enum        = VALUE #( ( `short` ) ( `long` ) ) ) )
                                           ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(user) = args->get_string( `user` ).
    CASE user.
      WHEN `FAIL`.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                            message = `User FAIL does not exist.` ).
      WHEN `CRASH`.
        DATA(zero) = 0.
        DATA(boom) = 1 / zero ##NEEDED.
    ENDCASE.
    DATA(rows) = NEW string_table( ( user ) ( user ) ( user ) ).
    result-data = rows.
    result-sources = VALUE #( ( `TEST` ) ).
    apply_row_limit( EXPORTING max_rows = ctx->max_rows( ) CHANGING result = result ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    " Summary is built from the data as seen after the privacy step
    FIELD-SYMBOLS <rows> TYPE string_table.
    ASSIGN result-data->* TO <rows>.
    result-summary = <rows>[ 1 ].
  ENDMETHOD.

ENDCLASS.

"! Test double: write tool - without plan_id it plans (plan P1), with plan_id it executes
CLASS ltd_write_tool DEFINITION FINAL FOR TESTING
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
ENDCLASS.

CLASS ltd_write_tool IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #( name        = `change_thing`
                      title       = `Change thing`
                      group       = zif_accx_types=>co_group-admin
                      read_only   = abap_false
                      destructive = abap_true
                      params      = VALUE #( ( param( name = `plan_id` description = `Plan` ) )
                                             ( param( name = `confirm` kind = zif_accx_types=>co_kind-boolean description = `Confirmed` ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    IF args->get_string( `plan_id` ) IS INITIAL.
      result = VALUE #( status       = zif_accx_types=>co_status-confirm
                        summary      = `planned`
                        confirmation = VALUE #( plan_id = `P1` prompt = `Change the thing?` ) ).
    ELSE.
      result-summary = `executed`.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

CLASS ltd_registry DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_registry.
    DATA tools TYPE zif_accx_plugin=>ty_tools.
ENDCLASS.

CLASS ltd_registry IMPLEMENTATION.

  METHOD zif_accx_registry~get_tools.
    result = tools.
  ENDMETHOD.

  METHOD zif_accx_registry~get_tool.
    LOOP AT tools INTO DATA(tool).
      IF tool->get_descriptor( )-name = name.
        result = tool.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_registry~get_issues ##NEEDED.
  ENDMETHOD.

ENDCLASS.

"! Privacy double: replaces every row with PSEUDO, or fails on demand
CLASS ltd_privacy DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_privacy.
    DATA fail TYPE abap_bool.
ENDCLASS.

CLASS ltd_privacy IMPLEMENTATION.

  METHOD zif_accx_privacy~protect_result.
    FIELD-SYMBOLS <rows> TYPE string_table.
    IF fail = abap_true.
      RAISE EXCEPTION NEW cx_sy_itab_line_not_found( ).
    ENDIF.
    IF result-data IS BOUND.
      ASSIGN result-data->* TO <rows>.
      LOOP AT <rows> ASSIGNING FIELD-SYMBOL(<row>).
        <row> = `PSEUDO`.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_privacy~resolve_args.
    result = args.
  ENDMETHOD.

ENDCLASS.

"! Authorizer double: a customer-style subclass of the default authorizer
CLASS ltd_authorizer DEFINITION FINAL FOR TESTING
  INHERITING FROM zcl_accx_authorizer.

  PUBLIC SECTION.
    DATA deny_group TYPE string.
    DATA crash      TYPE abap_bool.
    METHODS zif_accx_authorizer~check_tool REDEFINITION.
ENDCLASS.

CLASS ltd_authorizer IMPLEMENTATION.

  METHOD zif_accx_authorizer~check_tool.
    IF crash = abap_true.
      RAISE EXCEPTION NEW cx_sy_itab_line_not_found( ).
    ENDIF.
    result = xsdbool( tool-group <> deny_group ).
  ENDMETHOD.

ENDCLASS.

CLASS ltd_logger DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_logger.
    DATA entries TYPE STANDARD TABLE OF zif_accx_logger=>ty_entry WITH EMPTY KEY.
ENDCLASS.

CLASS ltd_logger IMPLEMENTATION.

  METHOD zif_accx_logger~log.
    APPEND entry TO entries.
  ENDMETHOD.

ENDCLASS.

CLASS ltc_runtime DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut        TYPE REF TO zif_accx_runtime.
    DATA privacy    TYPE REF TO ltd_privacy.
    DATA authorizer TYPE REF TO ltd_authorizer.
    DATA logger     TYPE REF TO ltd_logger.
    DATA ctx        TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS call
      IMPORTING !tool_name    TYPE string DEFAULT `echo_user`
                !args         TYPE REF TO zcl_accx_args_map
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_result.
    METHODS allow_writing.

    METHODS unknown_tool_is_invalid      FOR TESTING.
    METHODS missing_required_is_invalid  FOR TESTING.
    METHODS enum_violation_is_invalid    FOR TESTING.
    METHODS ok_path_privacy_then_summary FOR TESTING.
    METHODS row_limit_applied            FOR TESTING.
    METHODS tool_error_keeps_status      FOR TESTING.
    METHODS runtime_error_is_caught      FOR TESTING.
    METHODS privacy_failure_withholds    FOR TESTING.
    METHODS every_call_is_logged         FOR TESTING.
    METHODS authorizer_denies_execution  FOR TESTING.
    METHODS authorizer_filters_catalog   FOR TESTING.
    METHODS authorizer_crash_fails_closed FOR TESTING.
    METHODS write_tool_needs_permission  FOR TESTING.
    METHODS write_plan_then_confirm      FOR TESTING.
ENDCLASS.

CLASS ltc_runtime IMPLEMENTATION.

  METHOD setup.
    DATA(registry) = NEW ltd_registry( ).
    registry->tools = VALUE #( ( NEW ltd_tool( ) ) ( NEW ltd_write_tool( ) ) ).
    privacy    = NEW ltd_privacy( ).
    authorizer = NEW ltd_authorizer( ).
    logger     = NEW ltd_logger( ).
    cut = NEW zcl_accx_runtime_local( registry = registry logger = logger ).
    ctx = NEW zcl_accx_context( profile    = `test/unit`
                                max_rows   = 2
                                guard      = NEW zcl_accx_caller_guard( )
                                privacy    = privacy
                                authorizer = authorizer ).
  ENDMETHOD.

  METHOD allow_writing.
    ctx = NEW zcl_accx_context( profile       = `test/admin`
                                max_rows      = 2
                                guard         = NEW zcl_accx_caller_guard( )
                                privacy       = privacy
                                authorizer    = authorizer
                                write_problem = `` ).
  ENDMETHOD.

  METHOD call.
    result = cut->execute( tool_name = tool_name args = args ctx = ctx ).
  ENDMETHOD.

  METHOD unknown_tool_is_invalid.
    DATA(result) = call( tool_name = `does_not_exist` args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = result-status ).
  ENDMETHOD.

  METHOD missing_required_is_invalid.
    DATA(result) = call( args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = result-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*'user'*` act = result-summary ).
  ENDMETHOD.

  METHOD enum_violation_is_invalid.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `X` )->set( name = `mode` value = `bad` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = result-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*short, long*` act = result-summary ).
  ENDMETHOD.

  METHOD ok_path_privacy_then_summary.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` )->set( name = `mode` value = `short` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status ).
    " summary was rendered after privacy replaced JDOE
    cl_abap_unit_assert=>assert_equals( exp = `PSEUDO` act = result-summary ).
  ENDMETHOD.

  METHOD row_limit_applied.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` ) ).
    FIELD-SYMBOLS <rows> TYPE string_table.
    ASSIGN result-data->* TO <rows>.
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( <rows> ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( result-truncated ).
  ENDMETHOD.

  METHOD tool_error_keeps_status.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `FAIL` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = result-status ).
    cl_abap_unit_assert=>assert_equals( exp = `User FAIL does not exist.` act = result-summary ).
  ENDMETHOD.

  METHOD runtime_error_is_caught.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `CRASH` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-error act = result-status ).
  ENDMETHOD.

  METHOD privacy_failure_withholds.
    privacy->fail = abap_true.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-error act = result-status ).
    cl_abap_unit_assert=>assert_not_bound( result-data ).
  ENDMETHOD.

  METHOD every_call_is_logged.
    call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` ) ).
    call( tool_name = `does_not_exist` args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( logger->entries ) ).
    DATA(first) = logger->entries[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `echo_user` act = first-tool_name ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = first-status ).
    cl_abap_unit_assert=>assert_not_initial( first-args_hash ).
    cl_abap_unit_assert=>assert_char_np( exp = `*JDOE*` act = first-args_hash ).
  ENDMETHOD.

  METHOD authorizer_denies_execution.
    authorizer->deny_group = zif_accx_types=>co_group-user.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = result-status ).
    cl_abap_unit_assert=>assert_not_bound( result-data ).
  ENDMETHOD.

  METHOD authorizer_filters_catalog.
    " the write tool is not offered without write permission
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( cut->get_catalog( ctx ) ) ).
    authorizer->deny_group = zif_accx_types=>co_group-user.
    cl_abap_unit_assert=>assert_initial( cut->get_catalog( ctx ) ).
  ENDMETHOD.

  METHOD authorizer_crash_fails_closed.
    authorizer->crash = abap_true.
    DATA(result) = call( args = NEW zcl_accx_args_map( )->set( name = `user` value = `JDOE` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = result-status ).
    cl_abap_unit_assert=>assert_initial( cut->get_catalog( ctx ) ).
  ENDMETHOD.

  METHOD write_tool_needs_permission.
    DATA(result) = call( tool_name = `change_thing` args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = result-status ).
    cl_abap_unit_assert=>assert_equals( exp = zcl_accx_context=>co_write_not_enabled act = result-summary ).

    allow_writing( ).
    DATA(catalog) = cut->get_catalog( ctx ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( catalog ) ).
    " usage authorization still applies to write tools
    authorizer->deny_group = zif_accx_types=>co_group-admin.
    result = call( tool_name = `change_thing` args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = result-status ).
  ENDMETHOD.

  METHOD write_plan_then_confirm.
    allow_writing( ).
    DATA(result) = call( tool_name = `change_thing` args = NEW zcl_accx_args_map( ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-confirm act = result-status ).
    cl_abap_unit_assert=>assert_equals( exp = `P1` act = result-confirmation-plan_id ).
    cl_abap_unit_assert=>assert_equals( exp = `plan P1: planned` act = logger->entries[ 1 ]-message ).

    " plan without confirmation and confirmation without plan are refused
    result = call( tool_name = `change_thing` args = NEW zcl_accx_args_map( )->set( name = `plan_id` value = `P1` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = result-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*needs confirm = true*` act = result-summary ).
    result = call( tool_name = `change_thing` args = NEW zcl_accx_args_map( )->set( name = `confirm` value = `true` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = result-status ).

    result = call( tool_name = `change_thing`
                   args      = NEW zcl_accx_args_map( )->set( name = `plan_id` value = `P1` )->set( name = `confirm` value = `true` ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-ok act = result-status ).
    " write calls are logged with their outcome, also when ok
    cl_abap_unit_assert=>assert_equals( exp = `executed` act = logger->entries[ 4 ]-message ).
  ENDMETHOD.

ENDCLASS.
