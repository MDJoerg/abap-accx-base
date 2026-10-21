"! Variants: VCA_A (authorizations, DEBUG red + TABLE yellow), VCA_B (DEBUG again), VCC_C (combination), EMPTY
CLASS ltd_gateway DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_suim_gateway PARTIALLY IMPLEMENTED.
    DATA last_users TYPE susr_t_range_4_xubname.
    DATA last_roles TYPE susr_t_range_4_agr_name.
ENDCLASS.

CLASS ltd_gateway IMPLEMENTATION.
  METHOD zif_accx_suim_gateway~get_variants.
    result = VALUE #( ( kind = zif_accx_suim_gateway=>co_kind-authorization name = `VCA_A` text = `Basis` rule_count = 2 )
                      ( kind = zif_accx_suim_gateway=>co_kind-authorization name = `VCA_B` rule_count = 1 )
                      ( kind = zif_accx_suim_gateway=>co_kind-combination   name = `VCC_C` rule_count = 1 )
                      ( kind = zif_accx_suim_gateway=>co_kind-authorization name = `EMPTY` rule_count = 0 ) ).
  ENDMETHOD.
  METHOD zif_accx_suim_gateway~critical_users.
    last_users = users.
    CASE variant.
      WHEN `VCA_A`.
        result-findings = VALUE #( ( kind = kind rule = `DEBUG` text = `Debug replace` color = '6' subject = `CRIT` )
                                   ( kind = kind rule = `DEBUG` text = `Debug replace` color = '6' subject = `HIDDEN` )
                                   ( kind = kind rule = `TABLE` text = `Table maint.` color = '3' subject = `CRIT` )
                                   ( kind = kind rule = `TABLE` text = `Table maint.` color = '3' subject = `MON1` )
                                   ( kind = kind rule = `TABLE` text = `Table maint.` color = '3' subject = `MON2` ) ).
      WHEN `VCA_B`.
        result-findings = VALUE #( ( kind = kind rule = `DEBUG` text = `Debug replace` color = '6' subject = `CRIT` ) ).
        result-messages = VALUE #( ( `SUIM I 01/829: some users not displayed` ) ).
      WHEN `VCC_C`.
        result-findings = VALUE #( ( kind = kind rule = `DBG_TAB` text = `Debug and tables` color = '6' subject = `CRIT` ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_suim_gateway~critical_roles.
    last_roles = roles.
    IF variant = `VCA_A`.
      result-findings = VALUE #( ( kind = kind rule = `DEBUG` text = `Debug replace` color = '6' subject = `ZROLE` role_type = 'S' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! CRIT: DEBUG from role ZCRIT, TABLE partly from profile SAP_ALL; MON1/MON2: TABLE from role ZMON (MON2 via ZCOMP)
CLASS ltd_origin DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_access_origin.
    DATA calls TYPE i.
ENDCLASS.

CLASS ltd_origin IMPLEMENTATION.
  METHOD zif_accx_access_origin~trace_rule.
    calls += 1.
    CASE user.
      WHEN 'CRIT'.
        IF rule = 'DEBUG'.
          result = VALUE #( ( rule = rule source_type = zif_accx_access_origin=>co_source-role source = `ZCRIT`
                              profile = 'T-CRIT' complete = abap_true ) ).
        ELSE.
          result = VALUE #( ( rule = rule source_type = zif_accx_access_origin=>co_source-profile source = `SAP_ALL`
                              profile = 'SAP_ALL' complete = abap_false ) ).
        ENDIF.
      WHEN 'MON1'.
        result = VALUE #( ( rule = rule source_type = zif_accx_access_origin=>co_source-role source = `ZMON`
                            profile = 'T-MON' complete = abap_true ) ).
      WHEN 'MON2'.
        result = VALUE #( ( rule = rule source_type = zif_accx_access_origin=>co_source-role source = `ZMON`
                            profile = 'T-MON' via = `composite role ZCOMP` complete = abap_true ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_access_origin~trace_combination.
    result = VALUE #( ( LINES OF zif_accx_access_origin~trace_rule( user = user rule = 'DEBUG' ) )
                      ( LINES OF zif_accx_access_origin~trace_rule( user = user rule = 'TABLE' ) ) ).
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

CLASS ltc_run_critical_check DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut     TYPE REF TO zif_accx_tool.
    DATA ctx     TYPE REF TO zif_accx_context.
    DATA gateway TYPE REF TO ltd_gateway.
    DATA origin  TYPE REF TO ltd_origin.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !args    TYPE REF TO zcl_accx_args_map
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_run_critical_check=>ty_payload
      RAISING   zcx_accx_error.

    METHODS users_condensed_per_rule FOR TESTING RAISING zcx_accx_error.
    METHODS user_pattern_as_range    FOR TESTING RAISING zcx_accx_error.
    METHODS roles_scope              FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_variant          FOR TESTING.
    METHODS role_filter_needs_scope  FOR TESTING.
    METHODS origin_per_finding       FOR TESTING RAISING zcx_accx_error.
    METHODS origin_switched_off      FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_run_critical_check IMPLEMENTATION.

  METHOD setup.
    gateway = NEW ltd_gateway( ).
    origin = NEW ltd_origin( ).
    zcl_accx_domain_factory=>inject( suim_gateway = gateway access_origin = origin ).
    cut = NEW zcl_accx_t_run_critical_check( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_run_critical_check=>ty_payload.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD users_condensed_per_rule.
    run( EXPORTING args = NEW zcl_accx_args_map( ) IMPORTING result = DATA(result) payload = DATA(payload) ).
    " empty variant skipped; DEBUG of two variants counted once; hidden user dropped
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-variants ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-rules ) ).
    " red rules first, within red by holders
    cl_abap_unit_assert=>assert_equals( exp = `DBG_TAB` act = payload-rules[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = `DEBUG` act = payload-rules[ 2 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-rules[ 2 ]-holder_count ).
    cl_abap_unit_assert=>assert_equals( exp = `VCA_A, VCA_B` act = payload-findings[ 2 ]-variants ).
    cl_abap_unit_assert=>assert_equals( exp = `TABLE` act = payload-rules[ 3 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = `medium` act = payload-rules[ 3 ]-level ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = result-total_count ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Table maint.** (TABLE, authorization, medium): 3 users - CRIT, MON1, MON2*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `VCA_B: SUIM I 01/829*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD user_pattern_as_range.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = `accx*` ).
    args->set( name = `variant` value = `vca_a` ).
    run( EXPORTING args = args IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-variants ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'CP' act = gateway->last_users[ 1 ]-option ).
    cl_abap_unit_assert=>assert_equals( exp = 'ACCX*' act = gateway->last_users[ 1 ]-low ).
  ENDMETHOD.

  METHOD roles_scope.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `scope` value = `roles` ).
    args->set( name = `role` value = `ZROLE` ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 'EQ' act = gateway->last_roles[ 1 ]-option ).
    cl_abap_unit_assert=>assert_equals( exp = `single` act = payload-findings[ 1 ]-role_type ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*1 role - ZROLE*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Check in PFCG*` act = result-next_steps[ 1 ] ).
    " no origin for roles
    cl_abap_unit_assert=>assert_equals( exp = 0 act = origin->calls ).
  ENDMETHOD.

  METHOD unknown_variant.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `variant` value = `NOPE` ).
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
        cl_abap_unit_assert=>assert_char_cp( exp = `*Available: VCA_A, VCA_B, VCC_C*` act = error->message ).
    ENDTRY.
  ENDMETHOD.

  METHOD role_filter_needs_scope.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `Z*` ).
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD origin_per_finding.
    run( EXPORTING args = NEW zcl_accx_args_map( ) IMPORTING result = DATA(result) payload = DATA(payload) ).
    " combination: per component
    cl_abap_unit_assert=>assert_equals( exp = `DEBUG: role ZCRIT; TABLE: profile SAP_ALL (partly)`
                                        act = payload-findings[ kind = `combination` subject = `CRIT` ]-origin ).
    cl_abap_unit_assert=>assert_equals( exp = `role ZMON (via composite role ZCOMP)`
                                        act = payload-findings[ rule = `TABLE` subject = `MON2` ]-origin ).
    " sources per rule, most frequent first, without the composite detail
    cl_abap_unit_assert=>assert_equals( exp = `role ZMON (2), profile SAP_ALL (1)`
                                        act = payload-rules[ rule = `TABLE` ]-sources ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*3 users - CRIT, MON1, MON2; granted by role ZMON (2), profile SAP_ALL (1)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Debug and tables (DBG_TAB) comes mostly from profile SAP_ALL*`
                                         act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD origin_switched_off.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `with_origin` value = abap_false ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = origin->calls ).
    cl_abap_unit_assert=>assert_initial( payload-rules[ 1 ]-sources ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use get_user_profile*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

ENDCLASS.
