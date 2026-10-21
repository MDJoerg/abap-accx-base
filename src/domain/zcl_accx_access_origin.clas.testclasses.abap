"! DEBUG: one group (S_DEVELOP DEBUG + 02 in one authorization); SPLIT: two groups (S_ADMI_FCD, S_LOG_COM);
"! combination DBG_SPLIT = DEBUG + SPLIT
CLASS ltd_rules DEFINITION FINAL FOR TESTING INHERITING FROM zcl_accx_critical_rules.
  PUBLIC SECTION.
    METHODS constructor.
ENDCLASS.

CLASS ltd_rules IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    loaded = abap_true.
    rules = VALUE #( ( id = 'DEBUG' color = '6' text = `Debugging with replace` )
                     ( id = 'SPLIT' color = '3' text = `Admin and commands` ) ).
    rule_values = VALUE #(
      ( id = 'DEBUG' group = '1' object = 'S_DEVELOP' field = 'OBJTYPE' low = 'DEBUG' searchtype = 'AND' )
      ( id = 'DEBUG' group = '1' object = 'S_DEVELOP' field = 'ACTVT' low = '02' searchtype = 'AND' )
      ( id = 'SPLIT' group = '1' object = 'S_ADMI_FCD' field = 'S_ADMI_FCD' low = 'PADM' searchtype = 'AND' )
      ( id = 'SPLIT' group = '2' object = 'S_LOG_COM' searchtype = 'AND' ) ).
    combinations = VALUE #( ( id = 'DBG_SPLIT' rule = 'DEBUG' ) ( id = 'DBG_SPLIT' rule = 'SPLIT' ) ).
  ENDMETHOD.
ENDCLASS.

"! User U: role ZDEV (directly), role ZADM via composite ZCOMP, profile ZLOG (manual), profile T-EMPTY;
"! reference user profile SAP_ALL
CLASS ltd_origin DEFINITION FINAL FOR TESTING INHERITING FROM zcl_accx_access_origin.
  PUBLIC SECTION.
    DATA value_reads TYPE i.
  PROTECTED SECTION.
    METHODS sources_of REDEFINITION.
    METHODS values_of  REDEFINITION.
ENDCLASS.

CLASS ltd_origin IMPLEMENTATION.
  METHOD sources_of.
    IF user = 'U'.
      result = VALUE #( ( profile = 'T-DEV' role = 'ZDEV' )
                        ( profile = 'T-ADM' role = 'ZADM' via = `composite role ZCOMP` )
                        ( profile = 'ZLOG' )
                        ( profile = 'T-EMPTY' role = 'ZEMPTY' )
                        ( profile = 'SAP_ALL' via = `reference user REF` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD values_of.
    value_reads += 1.
    CASE profile.
      WHEN 'T-DEV'.
        result = VALUE #( ( object = 'S_DEVELOP' auth = 'D1' field = 'OBJTYPE' low = 'DEBUG' )
                          ( object = 'S_DEVELOP' auth = 'D1' field = 'ACTVT' low = '02' ) ).
      WHEN 'T-ADM'.
        result = VALUE #( ( object = 'S_ADMI_FCD' auth = 'A1' field = 'S_ADMI_FCD' low = 'PADM' ) ).
      WHEN 'ZLOG'.
        result = VALUE #( ( object = 'S_LOG_COM' auth = 'L1' field = 'COMMAND' low = 'ZLS' ) ).
      WHEN 'SAP_ALL'.
        result = VALUE #( ( object = 'S_DEVELOP' auth = '&_SAP_ALL' field = 'OBJTYPE' low = '*' )
                          ( object = 'S_DEVELOP' auth = '&_SAP_ALL' field = 'ACTVT' low = '*' )
                          ( object = 'S_ADMI_FCD' auth = '&_SAP_ALL' field = 'S_ADMI_FCD' low = '*' )
                          ( object = 'S_LOG_COM' auth = '&_SAP_ALL' field = 'COMMAND' low = '*' ) ).
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_access_origin DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO ltd_origin.

    METHODS setup.
    METHODS describe
      IMPORTING !origins      TYPE zif_accx_access_origin=>ty_origins
      RETURNING VALUE(result) TYPE string.

    METHODS role_and_reference_user  FOR TESTING.
    METHODS groups_split_over_sources FOR TESTING.
    METHODS combination_components   FOR TESTING.
    METHODS profile_values_cached    FOR TESTING.
    METHODS unknown_user             FOR TESTING.
ENDCLASS.

CLASS ltc_access_origin IMPLEMENTATION.

  METHOD setup.
    cut = NEW ltd_origin( NEW ltd_rules( ) ).
  ENDMETHOD.

  METHOD describe.
    LOOP AT origins INTO DATA(origin).
      result = |{ result }{ origin-rule }:{ origin-source_type } { origin-source }| &&
               |{ COND #( WHEN origin-complete = abap_false THEN `(partly)` ) }| &&
               |{ COND #( WHEN origin-via IS NOT INITIAL THEN `[` && origin-via && `]` ) } |.
    ENDLOOP.
    result = condense( result ).
  ENDMETHOD.

  METHOD role_and_reference_user.
    cl_abap_unit_assert=>assert_equals(
      exp = `DEBUG:role ZDEV DEBUG:profile SAP_ALL[reference user REF]`
      act = describe( cut->zif_accx_access_origin~trace_rule( user = 'U' rule = 'DEBUG' ) ) ).
  ENDMETHOD.

  METHOD groups_split_over_sources.
    " SPLIT needs both groups: ZADM and ZLOG only together, SAP_ALL alone
    cl_abap_unit_assert=>assert_equals(
      exp = `SPLIT:role ZADM(partly)[composite role ZCOMP] SPLIT:profile ZLOG(partly) SPLIT:profile SAP_ALL[reference user REF]`
      act = describe( cut->zif_accx_access_origin~trace_rule( user = 'U' rule = 'SPLIT' ) ) ).
  ENDMETHOD.

  METHOD combination_components.
    DATA(origins) = cut->zif_accx_access_origin~trace_combination( user = 'U' combination = 'DBG_SPLIT' ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = lines( origins ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'DEBUG' act = origins[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = 'SPLIT' act = origins[ 5 ]-rule ).
  ENDMETHOD.

  METHOD profile_values_cached.
    cut->zif_accx_access_origin~trace_rule( user = 'U' rule = 'DEBUG' ).
    cut->zif_accx_access_origin~trace_rule( user = 'U' rule = 'SPLIT' ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = cut->value_reads ).
  ENDMETHOD.

  METHOD unknown_user.
    cl_abap_unit_assert=>assert_initial( cut->zif_accx_access_origin~trace_rule( user = 'NOBODY' rule = 'DEBUG' ) ).
    cl_abap_unit_assert=>assert_initial( cut->zif_accx_access_origin~trace_rule( user = 'U' rule = 'NONE' ) ).
  ENDMETHOD.

ENDCLASS.
