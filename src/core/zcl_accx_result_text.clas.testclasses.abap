CLASS ltc_result_text DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS summary_only        FOR TESTING.
    METHODS empty_summary       FOR TESTING.
    METHODS all_parts_in_order  FOR TESTING.
    METHODS status_for_partial  FOR TESTING.
    METHODS failures            FOR TESTING.
ENDCLASS.

CLASS ltc_result_text IMPLEMENTATION.

  METHOD summary_only.
    cl_abap_unit_assert=>assert_equals(
      exp = `Found 3 users.`
      act = zcl_accx_result_text=>compose( VALUE #( status = zif_accx_types=>co_status-ok summary = `Found 3 users.` ) ) ).
  ENDMETHOD.

  METHOD empty_summary.
    cl_abap_unit_assert=>assert_equals(
      exp = `Status: not_found`
      act = zcl_accx_result_text=>compose( VALUE #( status = zif_accx_types=>co_status-not_found ) ) ).
  ENDMETHOD.

  METHOD all_parts_in_order.
    DATA(text) = zcl_accx_result_text=>compose( VALUE #( status     = zif_accx_types=>co_status-ok
                                                         summary    = `Summary`
                                                         warnings   = VALUE #( ( `W1` ) ( `W2` ) )
                                                         next_steps = VALUE #( ( `N1` ) )
                                                         sources    = VALUE #( ( `S1` ) ( `S2` ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = |Summary\n\nWarnings:\n- W1\n- W2\n\nNext steps:\n- N1\n\nSources: S1, S2|
      act = text ).
  ENDMETHOD.

  METHOD status_for_partial.
    cl_abap_unit_assert=>assert_equals(
      exp = |Status: partial\n\nSome hidden|
      act = zcl_accx_result_text=>compose( VALUE #( status = zif_accx_types=>co_status-partial summary = `Some hidden` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = |Status: confirmation_required\n\nPlan|
      act = zcl_accx_result_text=>compose( VALUE #( status = zif_accx_types=>co_status-confirm summary = `Plan` ) ) ).
  ENDMETHOD.

  METHOD failures.
    cl_abap_unit_assert=>assert_true( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-denied ) ) ).
    cl_abap_unit_assert=>assert_true( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-invalid ) ) ).
    cl_abap_unit_assert=>assert_true( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-error ) ) ).
    cl_abap_unit_assert=>assert_false( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-ok ) ) ).
    cl_abap_unit_assert=>assert_false( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-not_found ) ) ).
    cl_abap_unit_assert=>assert_false( zcl_accx_result_text=>is_failure( VALUE #( status = zif_accx_types=>co_status-confirm ) ) ).
  ENDMETHOD.

ENDCLASS.
