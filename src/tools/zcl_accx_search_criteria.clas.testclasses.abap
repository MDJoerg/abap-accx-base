CLASS ltc_search_criteria DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS repeated_field_is_alternative FOR TESTING RAISING zcx_accx_error.
    METHODS pair_without_value            FOR TESTING.
ENDCLASS.

CLASS ltc_search_criteria IMPLEMENTATION.

  METHOD repeated_field_is_alternative.
    DATA(criteria) = zcl_accx_search_criteria=>value_criteria( VALUE #( ( ` actvt = 02` ) ( `DICBERCLS=SC` ) ( `ACTVT=03` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( criteria ) ).
    cl_abap_unit_assert=>assert_equals( exp = `S_TABU_DIS with ACTVT=02 or 03, DICBERCLS=SC`
                                        act = zcl_accx_search_criteria=>describe_values( object = `S_TABU_DIS` criteria = criteria ) ).
  ENDMETHOD.

  METHOD pair_without_value.
    TRY.
        zcl_accx_search_criteria=>value_criteria( VALUE #( ( `ACTVT` ) ) ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
