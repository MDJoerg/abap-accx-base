CLASS ltc_failure_source DEFINITION DEFERRED.
CLASS zcl_accx_failure_source DEFINITION LOCAL FRIENDS ltc_failure_source.

"! Mapping of SU53 and trace entries; which entries count as caused by ACCX
CLASS ltc_failure_source DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zcl_accx_failure_source.

    METHODS setup.
    METHODS su53_own_rfc_is_simulation FOR TESTING.
    METHODS trace_rows_mapped          FOR TESTING.
ENDCLASS.

CLASS ltc_failure_source IMPLEMENTATION.

  METHOD setup.
    cut = NEW #( ).
  ENDMETHOD.

  METHOD su53_own_rfc_is_simulation.
    " SUIM API called by ACCX (DESTINATION 'NONE'): visibility check of the caller
    DATA(failure) = cut->to_failure(
      user  = 'JDOE'
      entry = VALUE #( bname = 'JDOE' objct = 'S_USER_AGR' rc = 4 type = 'RF' name = 'SUSR_SUIM_API_RSUSR070'
                       typetext = 'RFC Function Module' disp_name = 'SUSR_SUIM_API_RSUSR070' abapprog = 'SAPLSUSR_SUIM'
                       fiel1 = 'ACT_GROUP' val01 = 'SAP_XI_DEMOAPP' fiel2 = 'ACTVT' val02 = '03' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = failure-is_simulation ).
    cl_abap_unit_assert=>assert_equals( exp = `RFC Function Module SUSR_SUIM_API_RSUSR070` act = failure-application ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( failure-fields ) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_failure_source=>co_source-su53 act = failure-source ).

    " any other function module called by RFC is real work of the user
    failure = cut->to_failure(
      user  = 'JDOE'
      entry = VALUE #( bname = 'JDOE' objct = 'S_USER_AGR' rc = 4 type = 'RF' name = 'BAPI_USER_GET_DETAIL' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = failure-is_simulation ).

    " ACCX program or checked for another user
    failure = cut->to_failure( user  = 'JDOE'
                               entry = VALUE #( bname = 'JDOE' objct = 'S_TCODE' rc = 12 abapprog = 'ZCL_ACCX_CALLER_GUARD=========CP' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = failure-is_simulation ).
    failure = cut->to_failure( user  = 'JDOE'
                               entry = VALUE #( bname = 'JDOE' objct = 'S_TCODE' rc = 12 foruser = 'OTHER' ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = failure-is_simulation ).
  ENDMETHOD.

  METHOD trace_rows_mapped.
    DATA(failures) = cut->trace_to_failures(
      user  = 'JDOE'
      trace = VALUE #( ( username = 'JDOE' type = 'TR' name = 'SM37' object = 'S_TCODE' rc = 12 field1 = 'SM37'
                         firstcall = '20261021080000' )
                       ( username = 'JDOE' type = 'RF' name = 'SUAUTH_READ_TRACE_VALUES' object = 'S_ADMI_FCD' rc = 4
                         field1 = 'STUR' ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( failures ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'SM37' act = failures[ 1 ]-transaction ).
    cl_abap_unit_assert=>assert_initial( failures[ 1 ]-application ).
    " field name from TOBJ
    cl_abap_unit_assert=>assert_equals( exp = 'TCD' act = failures[ 1 ]-fields[ 1 ]-field ).
    cl_abap_unit_assert=>assert_equals( exp = `SM37` act = failures[ 1 ]-fields[ 1 ]-value ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = failures[ 1 ]-is_simulation ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_failure_source=>co_source-trace act = failures[ 1 ]-source ).
    " the trace read of ACCX itself
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = failures[ 2 ]-is_simulation ).
    cl_abap_unit_assert=>assert_equals( exp = `RF SUAUTH_READ_TRACE_VALUES` act = failures[ 2 ]-application ).
  ENDMETHOD.

ENDCLASS.
