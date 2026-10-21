"! Users: MON3 (missing, group TEST, holds ROLE_OWN and SAP_TEMPLATE), EXPIR (missing, had ROLE_A until 2026-10-19),
"! OK (authorized)
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'MON3' OR user = 'EXPIR' OR user = 'OK' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user user_group = `TEST` ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    CASE user.
      WHEN 'EXPIR'.
        result = VALUE #( ( role = 'ROLE_A' valid_from = '20260101' valid_to = '20261019' active = abap_false ) ).
      WHEN 'MON3'.
        result = VALUE #( ( role = 'SAP_TEMPLATE' active = abap_true ) ( role = 'ROLE_OWN' active = abap_true ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_profile_assignments ##NEEDED.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~transaction_exists.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    result = VALUE #( ( object = 'S_TCODE' fields = VALUE #( ( field = 'TCD' value = tcode ) ) reason = `start` ) ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~simulate.
    result = VALUE #( object    = check-object
                      condition = `TCD=SM37`
                      granted   = xsdbool( user = 'OK' )
                      outcome   = COND #( WHEN user = 'OK' THEN `granted` ELSE `missing` )
                      fields    = check-fields ).
  ENDMETHOD.
ENDCLASS.

"! Roles granting the check: ROLE_A (narrow, 2 peers, in ROLE_COMBO), ROLE_BROAD (S_TCODE *, no peers; SAP_ALT
"! instead if sap_alternative is set), ROLE_CRIT (3 peers, critical), ROLE_COMBO (composite), ROLE_NOGEN (no profile),
"! ROLE_HIDDEN (not displayable); none if no_roles is set, the roles in granting if that is filled.
"! ROLE_BROAD, ROLE_STAR and SAP_WIDE grant TCD *. Own roles of MON3: ROLE_OWN (4 peers), SAP_TEMPLATE (9 peers).
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
    CLASS-DATA no_roles        TYPE abap_bool.
    CLASS-DATA sap_alternative TYPE abap_bool.
    CLASS-DATA granting        TYPE zif_accx_role_repo=>ty_roles.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~find_roles_granting.
    IF no_roles = abap_true.
      RETURN.
    ENDIF.
    IF granting IS NOT INITIAL.
      result = granting.
      RETURN.
    ENDIF.
    result = VALUE #( ( 'ROLE_A' ) ( 'ROLE_COMBO' ) ( 'ROLE_CRIT' ) ( 'ROLE_HIDDEN' ) ( 'ROLE_NOGEN' ) ).
    " the uncritical role outside the user group is an SAP template when sap_alternative is set
    APPEND COND agr_name( WHEN sap_alternative = abap_true THEN 'SAP_ALT' ELSE 'ROLE_BROAD' ) TO result.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role generated = abap_true object_count = 10 ).
    CASE role.
      WHEN 'ROLE_A'.
        result-description = `Monitoring`.
        result-parents     = VALUE #( ( `ROLE_COMBO` ) ).
      WHEN 'ROLE_BROAD'.
        result-broad        = abap_true.
        result-object_count = 50.
      WHEN 'ROLE_COMBO'.
        result-composite = abap_true.
      WHEN 'ROLE_NOGEN'.
        result-generated = abap_false.
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_holders.
    result = SWITCH #( role WHEN 'ROLE_A' THEN 2 WHEN 'ROLE_CRIT' THEN 3 WHEN 'ROLE_OWN' THEN 4 WHEN 'SAP_TEMPLATE' THEN 9 ELSE 0 ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_group_members.
    result = 5.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorization_values.
    result = VALUE #( ( object = 'S_TCODE' auth = 'T1' field = 'TCD'
                        low    = COND #( WHEN role = 'ROLE_BROAD' OR role = 'ROLE_STAR' OR role = 'SAP_WIDE'
                                         THEN '*' ELSE 'SM37' ) ) ).
  ENDMETHOD.
ENDCLASS.

"! JOBS: met by SM37 itself (request), ADMIN: in ROLE_CRIT (and in ROLE_A if a_critical is set, in every role if all_critical)
CLASS ltd_critical DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_critical_rules PARTIALLY IMPLEMENTED.
    CLASS-DATA a_critical   TYPE abap_bool.
    CLASS-DATA all_critical TYPE abap_bool.
ENDCLASS.

CLASS ltd_critical IMPLEMENTATION.
  METHOD zif_accx_critical_rules~evaluate.
    IF line_exists( values[ low = 'SM37' ] ).
      result = VALUE #( ( rule = 'JOBS' text = `Job administration` level = zif_accx_critical_rules=>co_level-medium ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_critical_rules~evaluate_role.
    result = VALUE #( ( rule = 'JOBS' text = `Job administration` level = zif_accx_critical_rules=>co_level-medium ) ).
    IF role = 'ROLE_CRIT' OR ( role = 'ROLE_A' AND a_critical = abap_true ) OR all_critical = abap_true.
      APPEND VALUE #( rule = 'ADMIN' text = `Admin functions` level = zif_accx_critical_rules=>co_level-high ) TO result.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'ROLE_HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_explain_missing DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user    TYPE string
                !args    TYPE REF TO zcl_accx_args_map OPTIONAL
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_explain_missing=>ty_payload
      RAISING   zcx_accx_error.

    METHODS peer_role_ranked_first      FOR TESTING RAISING zcx_accx_error.
    METHODS critical_role_flagged       FOR TESTING RAISING zcx_accx_error.
    METHODS less_critical_alternative   FOR TESTING RAISING zcx_accx_error.
    METHODS expired_assignment_first    FOR TESTING RAISING zcx_accx_error.
    METHODS nothing_missing             FOR TESTING RAISING zcx_accx_error.
    METHODS draft_when_no_role_fits     FOR TESTING RAISING zcx_accx_error.
    METHODS draft_when_all_critical     FOR TESTING RAISING zcx_accx_error.
    METHODS draft_when_alternative_sap  FOR TESTING RAISING zcx_accx_error.
    METHODS draft_for_authorization     FOR TESTING RAISING zcx_accx_error.
    METHODS wildcard_and_template_down  FOR TESTING RAISING zcx_accx_error.
    METHODS draft_when_only_wildcard    FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_explain_missing IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( user_repo      = NEW ltd_user_repo( )
                                     role_repo      = NEW ltd_role_repo( )
                                     auth_evaluator = NEW ltd_evaluator( )
                                     critical_rules = NEW ltd_critical( ) ).
    cut = NEW zcl_accx_t_explain_missing( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
    ltd_critical=>a_critical = abap_false.
    ltd_critical=>all_critical = abap_false.
    ltd_role_repo=>no_roles = abap_false.
    ltd_role_repo=>sap_alternative = abap_false.
    CLEAR ltd_role_repo=>granting.
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_explain_missing=>ty_payload.
    DATA(call) = args.
    IF call IS NOT BOUND.
      call = NEW zcl_accx_args_map( ).
      call->set( name = `target_type` value = `transaction` ).
      call->set( name = `target` value = `SM37` ).
    ENDIF.
    call->set( name = `user` value = user ).
    result = cut->execute( args = call ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD peer_role_ranked_first.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " composite, not generated and hidden roles are not offered;
    " roles held in the user group first, the less critical one before the critical one
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-candidates ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_A' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_CRIT' act = payload-candidates[ 2 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_BROAD' act = payload-candidates[ 3 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Recommended:** role **ROLE_A** (Monitoring); held by 2 of 5 other users*ROLE_COMBO*`
                                         act = result-summary ).
    " the approved request is handed over to assign_role
    cl_abap_unit_assert=>assert_equals(
      exp = `{"user":"MON3","role":"ROLE_A","reason":"Missing access found by explain_missing_access: transaction SM37"}`
      act = payload-assign_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Request role ROLE_A for MON3 via the access request process; once approved, ` &&
                                               `with write access (plugin ADMIN): assign_role {"user":"MON3","role":"ROLE_A",*}.`
                                         act = result-next_steps[ 1 ] ).
    " an uncritical role fits: no role change proposed
    cl_abap_unit_assert=>assert_initial( payload-draft_arguments ).
  ENDMETHOD.

  METHOD critical_role_flagged.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " the request itself is critical; that rule does not count against the candidates
    cl_abap_unit_assert=>assert_equals( exp = 'JOBS' act = payload-request_critical[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_initial( payload-candidates[ 1 ]-critical ).
    cl_abap_unit_assert=>assert_equals( exp = 100 act = payload-candidates[ 2 ]-critical_score ).
    cl_abap_unit_assert=>assert_initial( payload-less_critical_option ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*requested access itself is critical:** Job administration (JOBS, medium)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*ROLE_CRIT: 3 peers*critical: Admin functions (ADMIN, high)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*ROLE_BROAD: 0 peers*no further critical authorizations*`
                                         act = result-summary ).
  ENDMETHOD.

  METHOD less_critical_alternative.
    ltd_critical=>a_critical = abap_true.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " both peer roles are critical: most peers wins, the uncritical role is named as alternative
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_CRIT' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_BROAD' act = payload-less_critical_option ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Also grants critical authorizations:** Admin functions (ADMIN, high)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Less critical alternative:** role **ROLE_BROAD***` act = result-summary ).
    " assign_role would refuse the critical role without accept_critical
    cl_abap_unit_assert=>assert_char_cp( exp = `*assign_role {"user":"MON3","role":"ROLE_CRIT",*unless accept_critical is set).`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*less critical role ROLE_BROAD instead*` act = result-next_steps[ 2 ] ).
    " an existing customer alternative is preferred over a role change
    cl_abap_unit_assert=>assert_initial( payload-draft_role ).
  ENDMETHOD.

  METHOD expired_assignment_first.
    run( EXPORTING user = `EXPIR` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_A' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_true( payload-candidates[ 1 ]-previously_assigned ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*assignment expired on 2026-10-19, renewing it closes the gap*` act = result-summary ).
    " the direct assignment is renewed with assign_role (new dates from today)
    cl_abap_unit_assert=>assert_char_cp( exp = `{"user":"EXPIR","role":"ROLE_A",*` act = payload-assign_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Extend or renew*; once approved*assign_role {"user":"EXPIR"*`
                                         act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD nothing_missing.
    run( EXPORTING user = `OK` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_true( payload-already_granted ).
    cl_abap_unit_assert=>assert_initial( payload-candidates ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*already may start transaction SM37 - no authorization is missing*` act = result-summary ).
  ENDMETHOD.

  METHOD draft_when_no_role_fits.
    ltd_role_repo=>no_roles = abap_true.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-candidates ).
    " customer role before the SAP template, although the template has more colleagues
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_OWN' act = payload-draft_role ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-draft_role_peers ).
    cl_abap_unit_assert=>assert_equals(
      exp = `{"role":"ROLE_OWN","add_transactions":["SM37"],"for_user":"MON3",` &&
            `"reason":"Missing access found by explain_missing_access: transaction SM37"}`
      act = payload-draft_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No existing role fits: *ROLE_OWN with draft_role_change {"role":"ROLE_OWN"*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*change a role instead of assigning one.** Extend the user's role **ROLE_OWN** (held by 4 colleagues*`
                                         act = result-summary ).
  ENDMETHOD.

  METHOD draft_when_all_critical.
    ltd_critical=>all_critical = abap_true.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " equally critical everywhere: the role most used in the group is recommended, no alternative exists
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_CRIT' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_initial( payload-less_critical_option ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_OWN' act = payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `To avoid the further critical authorizations of ROLE_CRIT: *draft_role_change*`
                                         act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD draft_when_alternative_sap.
    ltd_critical=>a_critical = abap_true.
    ltd_role_repo=>sap_alternative = abap_true.
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " an SAP template is copied, not assigned: the role change is offered as well
    cl_abap_unit_assert=>assert_equals( exp = 'SAP_ALT' act = payload-less_critical_option ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_OWN' act = payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*role **SAP_ALT** (not held by colleagues of the user group; SAP template role, to be copied first)*`
                                         act = result-summary ).
  ENDMETHOD.

  METHOD draft_for_authorization.
    ltd_role_repo=>no_roles = abap_true.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `target_type` value = `authorization` ).
    args->set( name = `target` value = `S_DEVELOP` ).
    args->set_list( name = `values` values = VALUE #( ( `OBJTYPE=DEBUG` ) ( `ACTVT=02` ) ) ).
    run( EXPORTING user = `MON3` args = args IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_char_cp(
      exp = `{"role":"ROLE_OWN","object":"S_DEVELOP","values":["OBJTYPE=DEBUG","ACTVT=02"],"for_user":"MON3",*`
      act = payload-draft_arguments ).
  ENDMETHOD.

  METHOD wildcard_and_template_down.
    ltd_role_repo=>granting = VALUE #( ( 'SAP_WIDE' ) ( 'ROLE_STAR' ) ( 'ROLE_NARROW' ) ).
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " all uncritical and unused: exact values first, then the customer wildcard role, the SAP template last
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_NARROW' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_STAR' act = payload-candidates[ 2 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'SAP_WIDE' act = payload-candidates[ 3 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = `S_TCODE-TCD` act = payload-candidates[ 2 ]-wildcard_fields ).
    cl_abap_unit_assert=>assert_true( payload-candidates[ 3 ]-sap_template ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*ROLE_STAR: 0 peers, 10 objects, wildcard: S_TCODE-TCD*` act = result-summary ).
    " a precise role fits: no role change proposed
    cl_abap_unit_assert=>assert_initial( payload-draft_role ).
  ENDMETHOD.

  METHOD draft_when_only_wildcard.
    ltd_role_repo=>granting = VALUE #( ( 'SAP_WIDE' ) ).
    run( EXPORTING user = `MON3` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " only an SAP template with wildcard nobody in the group holds: the precise role change comes first
    cl_abap_unit_assert=>assert_equals( exp = 'SAP_WIDE' act = payload-candidates[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 'ROLE_OWN' act = payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `To avoid the full wildcard (S_TCODE-TCD) of SAP_WIDE: *ROLE_OWN*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Copy the SAP template role SAP_WIDE to a customer role*`
                                         act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*SAP template role.*Grants S_TCODE-TCD with full wildcard*`
                                         act = result-summary ).
    " a template is copied, never assigned
    cl_abap_unit_assert=>assert_initial( payload-assign_arguments ).
  ENDMETHOD.

ENDCLASS.
