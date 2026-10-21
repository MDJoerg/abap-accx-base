CLASS ltc_role_diff DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS values_independent_of_auths FOR TESTING.
    METHODS lists_and_objects           FOR TESTING.
ENDCLASS.

CLASS ltc_role_diff IMPLEMENTATION.

  METHOD values_independent_of_auths.
    " the same values split over different authorizations are equal; skipped fields are ignored
    DATA(a) = zcl_accx_role_diff=>value_set( values = VALUE #( ( object = 'S_TCODE' auth = 'A1' field = 'TCD' low = 'SE16' )
                                                               ( object = 'S_TCODE' auth = 'A2' field = 'TCD' low = 'SM30' high = 'SM37' )
                                                               ( object = 'PLOG' auth = 'A3' field = 'PLVAR' low = '$PLVAR' ) )
                                             skip_fields = VALUE #( ( `PLVAR` ) ) ).
    DATA(b) = zcl_accx_role_diff=>value_set( VALUE #( ( object = 'S_TCODE' auth = 'B1' field = 'TCD' low = 'SE16' )
                                                      ( object = 'S_TCODE' auth = 'B1' field = 'TCD' low = 'SM30' high = 'SM37' )
                                                      ( object = 'S_TABU_DIS' auth = 'B2' field = 'DICBERCLS' ) ) ).
    DATA(diff) = zcl_accx_role_diff=>diff( a = a b = b ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = diff-common ).
    cl_abap_unit_assert=>assert_initial( diff-only_a ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS DICBERCLS=(open)` ) ) act = diff-only_b ).
  ENDMETHOD.

  METHOD lists_and_objects.
    DATA(diff) = zcl_accx_role_diff=>diff_lists( a = VALUE #( ( `SE16` ) ( `SU01` ) ( `SE16` ) ) b = VALUE #( ( `SU01` ) ( `SM37` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SE16` ) ) act = diff-only_a ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SM37` ) ) act = diff-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = diff-common ).
    DATA(objects) = zcl_accx_role_diff=>objects_of( VALUE #( ( `S_TCODE TCD=SE16` ) ( `S_TCODE TCD=SU01` ) ( `PLOG PLVAR=01` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_role_diff=>ty_set( ( `PLOG` ) ( `S_TCODE` ) ) act = objects ).
  ENDMETHOD.

ENDCLASS.
