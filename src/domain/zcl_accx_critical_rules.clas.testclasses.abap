"! Rule definitions as in SUIM, without database access
CLASS ltd_rules DEFINITION FINAL FOR TESTING INHERITING FROM zcl_accx_critical_rules.
  PUBLIC SECTION.
    METHODS constructor.
ENDCLASS.

CLASS ltd_rules IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    loaded = abap_true.
    rules = VALUE #( ( id = 'DEBUG' color = '6' text = `Debugging with replace` )
                     ( id = 'ADMIN' color = '6' text = `Admin functions` )
                     ( id = 'FULL'  color = '3' text = `Any user for jobs` )
                     ( id = 'LOGC'  color = '1' text = `Logical commands` )
                     ( id = 'MULTI' color = '3' text = `Two fields, OR` )
                     ( id = 'TWO'   color = '3' text = `Two groups` )
                     ( id = 'EMPTY' color = '6' text = `Rule without values` ) ).
    rule_values = VALUE #(
      " AND: both fields in one authorization
      ( id = 'DEBUG' object = 'S_DEVELOP' field = 'OBJTYPE' low = 'DEBUG' searchtype = 'AND' )
      ( id = 'DEBUG' object = 'S_DEVELOP' field = 'ACTVT' low = '02' searchtype = 'AND' )
      " OR: any of the values
      ( id = 'ADMIN' object = 'S_ADMI_FCD' field = 'S_ADMI_FCD' low = 'PADM' searchtype = 'OR' )
      ( id = 'ADMIN' object = 'S_ADMI_FCD' field = 'S_ADMI_FCD' low = 'NADM' searchtype = 'OR' )
      " #*: only the full authorization
      ( id = 'FULL' object = 'S_BTCH_NAM' field = 'BTCUNAME' low = '#*' searchtype = 'AND' )
      " object only
      ( id = 'LOGC' object = 'S_LOG_COM' searchtype = 'AND' )
      " OR across fields: one criterion of any field suffices (SUIM CHECK_VALUE)
      ( id = 'MULTI' object = 'S_RZL_ADM' field = 'ACTVT' low = '01' searchtype = 'OR' )
      ( id = 'MULTI' object = 'S_RZL_ADM' field = 'ZZFIELD' low = 'X' searchtype = 'OR' )
      " two groups: both must be met
      ( id = 'TWO' group = '1' object = 'S_LOG_COM' searchtype = 'AND' )
      ( id = 'TWO' group = '2' object = 'S_BTCH_NAM' field = 'BTCUNAME' low = '#*' searchtype = 'AND' ) ).
    " DBG_ADM: both; ONE_OF: DEBUG or FULL
    combinations = VALUE #( ( id = 'DBG_ADM' rule = 'ADMIN' searchtype = 'AND' ) ( id = 'DBG_ADM' rule = 'DEBUG' searchtype = 'AND' )
                            ( id = 'ONE_OF' rule = 'DEBUG' searchtype = 'OR' ) ( id = 'ONE_OF' rule = 'FULL' searchtype = 'OR' ) ).
    combination_rules = VALUE #( ( id = 'DBG_ADM' color = '6' text = `Debug and admin` )
                                 ( id = 'ONE_OF' color = '3' text = `Debug or jobs` ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_critical_rules DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_critical_rules.

    METHODS setup.
    METHODS rules_of
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE string.

    METHODS and_needs_same_authorization  FOR TESTING.
    METHODS and_met_by_pattern            FOR TESTING.
    METHODS or_any_value                  FOR TESTING.
    METHODS or_across_fields              FOR TESTING.
    METHODS full_authorization_only       FOR TESTING.
    METHODS object_only                   FOR TESTING.
    METHODS org_level_placeholder_ignored FOR TESTING.
    METHODS all_groups_needed             FOR TESTING.
    METHODS combination_components        FOR TESTING.
    METHODS combinations_from_hits        FOR TESTING.
ENDCLASS.

CLASS ltc_critical_rules IMPLEMENTATION.

  METHOD setup.
    cut = NEW ltd_rules( ).
  ENDMETHOD.

  METHOD rules_of.
    LOOP AT cut->evaluate( values ) INTO DATA(hit).
      result = |{ result }{ hit-rule }/{ hit-level } |.
    ENDLOOP.
    result = condense( result ).
  ENDMETHOD.

  METHOD and_needs_same_authorization.
    " DEBUG in one authorization, 02 in another: not critical
    cl_abap_unit_assert=>assert_initial( rules_of( VALUE #(
      ( object = 'S_DEVELOP' auth = 'A1' field = 'OBJTYPE' low = 'DEBUG' )
      ( object = 'S_DEVELOP' auth = 'A1' field = 'ACTVT' low = '03' )
      ( object = 'S_DEVELOP' auth = 'A2' field = 'OBJTYPE' low = 'PROG' )
      ( object = 'S_DEVELOP' auth = 'A2' field = 'ACTVT' low = '02' ) ) ) ).
  ENDMETHOD.

  METHOD and_met_by_pattern.
    cl_abap_unit_assert=>assert_equals( exp = `DEBUG/high` act = rules_of( VALUE #(
      ( object = 'S_DEVELOP' auth = 'A1' field = 'OBJTYPE' low = 'DEB*' )
      ( object = 'S_DEVELOP' auth = 'A1' field = 'ACTVT' low = '01' high = '03' ) ) ) ).
  ENDMETHOD.

  METHOD or_any_value.
    cl_abap_unit_assert=>assert_equals( exp = `ADMIN/high` act = rules_of( VALUE #(
      ( object = 'S_ADMI_FCD' auth = 'A1' field = 'S_ADMI_FCD' low = 'NADM' ) ) ) ).
    cl_abap_unit_assert=>assert_initial( rules_of( VALUE #(
      ( object = 'S_ADMI_FCD' auth = 'A1' field = 'S_ADMI_FCD' low = 'ST0R' ) ) ) ).
  ENDMETHOD.

  METHOD or_across_fields.
    cl_abap_unit_assert=>assert_equals( exp = `MULTI/medium` act = rules_of( VALUE #(
      ( object = 'S_RZL_ADM' auth = 'A1' field = 'ACTVT' low = '01' ) ) ) ).
  ENDMETHOD.

  METHOD full_authorization_only.
    cl_abap_unit_assert=>assert_initial( rules_of( VALUE #(
      ( object = 'S_BTCH_NAM' auth = 'A1' field = 'BTCUNAME' low = 'BATCHUSER' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `FULL/medium` act = rules_of( VALUE #(
      ( object = 'S_BTCH_NAM' auth = 'A1' field = 'BTCUNAME' low = '*' ) ) ) ).
  ENDMETHOD.

  METHOD object_only.
    cl_abap_unit_assert=>assert_equals( exp = `LOGC/low` act = rules_of( VALUE #(
      ( object = 'S_LOG_COM' auth = 'A1' field = 'COMMAND' low = 'ZLS' ) ) ) ).
  ENDMETHOD.

  METHOD org_level_placeholder_ignored.
    cl_abap_unit_assert=>assert_initial( rules_of( VALUE #(
      ( object = 'S_ADMI_FCD' auth = 'A1' field = 'S_ADMI_FCD' low = '$ADMIN' ) ) ) ).
  ENDMETHOD.

  METHOD all_groups_needed.
    DATA(only_first) = VALUE zif_accx_critical_rules=>ty_auth_values(
      ( object = 'S_LOG_COM' auth = 'A1' field = 'COMMAND' low = 'ZLS' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( cut->rule_groups( 'TWO' ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( cut->met_groups( rule = 'TWO' values = only_first ) ) ).
    " LOGC only, TWO not met
    cl_abap_unit_assert=>assert_equals( exp = `LOGC/low` act = rules_of( only_first ) ).
    cl_abap_unit_assert=>assert_equals( exp = `FULL/medium LOGC/low TWO/medium` act = rules_of( VALUE #(
      ( object = 'S_LOG_COM' auth = 'A1' field = 'COMMAND' low = 'ZLS' )
      ( object = 'S_BTCH_NAM' auth = 'A2' field = 'BTCUNAME' low = '*' ) ) ) ).
  ENDMETHOD.

  METHOD combination_components.
    cl_abap_unit_assert=>assert_equals( exp = VALUE zif_accx_critical_rules=>ty_rule_ids( ( 'ADMIN' ) ( 'DEBUG' ) )
                                        act = cut->combination_rules( 'DBG_ADM' ) ).
    cl_abap_unit_assert=>assert_initial( cut->combination_rules( 'NONE' ) ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = lines( cut->rule_objects( ) ) ).
  ENDMETHOD.

  METHOD combinations_from_hits.
    DATA(admin) = VALUE zif_accx_critical_rules=>ty_hit( rule = 'ADMIN' ).
    DATA(debug) = VALUE zif_accx_critical_rules=>ty_hit( rule = 'DEBUG' ).
    " AND components: both needed
    cl_abap_unit_assert=>assert_initial( cut->evaluate_combinations( VALUE #( ( admin ) ) ) ).
    DATA(both) = cut->evaluate_combinations( VALUE #( ( admin ) ( debug ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( both ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zif_accx_critical_rules=>ty_hit( rule = 'DBG_ADM' text = `Debug and admin` level = `high` )
                                        act = both[ 1 ] ).
    " OR components: one suffices
    DATA(one) = cut->evaluate_combinations( VALUE #( ( debug ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'ONE_OF' act = one[ 1 ]-rule ).
  ENDMETHOD.

ENDCLASS.
