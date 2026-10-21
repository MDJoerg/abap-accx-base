"! Users: FAIL (failures incl. a simulation entry, trace active), EMPTY (no failures, trace off),
"! NOSTUR (caller may not read the trace), HIDDEN (not displayable)
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'FAIL' OR user = 'EMPTY' OR user = 'NOSTUR' OR user = 'HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments ##NEEDED.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_profile_assignments ##NEEDED.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_failure_source DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_failure_source.
ENDCLASS.

CLASS ltd_failure_source IMPLEMENTATION.
  METHOD zif_accx_failure_source~read_su53.
    IF user <> 'FAIL'.
      RETURN.
    ENDIF.
    result-failures = VALUE #( source = zif_accx_failure_source=>co_source-su53
      ( timestamp = '20261021080000' object = 'S_TCODE' return_code = 12 transaction = 'SM37'
        fields = VALUE #( ( field = 'TCD' value = `SM37` ) ) )
      ( timestamp = '20261021090000' object = 'S_TCODE' return_code = 12 transaction = 'SM37'
        fields = VALUE #( ( field = 'TCD' value = `SM37` ) ) )
      ( timestamp = '20261021100000' object = 'S_DEVELOP' return_code = 4 transaction = 'SE38'
        fields = VALUE #( ( field = 'OBJTYPE' value = `PROG` ) ( field = 'ACTVT' value = `02` ) ( field = 'DEVCLASS' value = `` ) ) )
      ( timestamp = '20261021110000' object = 'S_TCODE' return_code = 12 program = 'ZCL_ACCX_AUTH_EVALUATOR=======CP'
        is_simulation = abap_true fields = VALUE #( ( field = 'TCD' value = `SU01` ) ) ) ).
    result-errors = VALUE #( ( `server2: no connection` ) ).
  ENDMETHOD.

  METHOD zif_accx_failure_source~read_trace.
    IF user = 'NOSTUR'.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = `Reading the user trace (STUSERTRACE) requires authorization S_ADMI_FCD with value STUR.` ).
    ENDIF.
    IF user <> 'FAIL'.
      RETURN.
    ENDIF.
    result-failures = VALUE #( source = zif_accx_failure_source=>co_source-trace
      ( timestamp = '20261015080000' object = 'S_TCODE' return_code = 12 transaction = 'SM37'
        fields = VALUE #( ( field = 'TCD' value = `SM37` ) ) )
      ( timestamp = '20261014070000' object = 'S_SERVICE' return_code = 12 application = `IWSG ZACCX_SRV_0001`
        fields = VALUE #( ( field = 'SRV_NAME' value = `3A4F` ) ( field = 'SRV_TYPE' value = `HT` ) ) )
      ( timestamp = '20261013070000' object = 'S_TCODE' return_code = 12 for_user = 'OTHER'
        is_simulation = abap_true fields = VALUE #( ( field = 'TCD' value = `SU01` ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_failure_source~trace_status.
    result = COND #( WHEN user = 'FAIL'
                     THEN VALUE #( mode = zif_accx_failure_source=>co_trace_mode-active covers_user = abap_true )
                     ELSE VALUE #( mode = zif_accx_failure_source=>co_trace_mode-inactive ) ).
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

CLASS ltc_get_failed_checks DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user    TYPE string
                !source  TYPE string OPTIONAL
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_failed_checks=>ty_payload
      RAISING   zcx_accx_error.

    METHODS condensed_newest_first FOR TESTING RAISING zcx_accx_error.
    METHODS merged_with_trace      FOR TESTING RAISING zcx_accx_error.
    METHODS nothing_recorded       FOR TESTING RAISING zcx_accx_error.
    METHODS trace_not_permitted    FOR TESTING RAISING zcx_accx_error.
    METHODS hidden_user_denied     FOR TESTING.
ENDCLASS.

CLASS ltc_get_failed_checks IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( user_repo      = NEW ltd_user_repo( )
                                     failure_source = NEW ltd_failure_source( ) ).
    cut = NEW zcl_accx_t_get_failed_checks( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_failed_checks=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    IF source IS NOT INITIAL.
      args->set( name = `source` value = source ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD condensed_newest_first.
    run( EXPORTING user = `fail` source = `su53` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-failures ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_DEVELOP' act = payload-failures[ 1 ]-object ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_TCODE' act = payload-failures[ 2 ]-object ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-failures[ 2 ]-occurrences ).
    cl_abap_unit_assert=>assert_char_cp( exp = `2026-10-21T09:00:00*` act = payload-failures[ 2 ]-last_seen ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-filtered_simulations ).
    cl_abap_unit_assert=>assert_initial( payload-trace_status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*S_DEVELOP (OBJTYPE=PROG, ACTVT=02, DEVCLASS=) - authorization for the object exists*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*transaction SM37, 2 times*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*target S_DEVELOP, values OBJTYPE=PROG ACTVT=02 to find*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*server2*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD merged_with_trace.
    run( EXPORTING user = `FAIL` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-failures ) ).
    " SU53 and trace entries of the same check are one finding
    cl_abap_unit_assert=>assert_equals( exp = 'S_TCODE' act = payload-failures[ 2 ]-object ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-failures[ 2 ]-occurrences ).
    cl_abap_unit_assert=>assert_equals( exp = `su53, trace` act = payload-failures[ 2 ]-sources ).
    cl_abap_unit_assert=>assert_char_cp( exp = `2026-10-21T09:00:00*` act = payload-failures[ 2 ]-last_seen ).
    cl_abap_unit_assert=>assert_char_cp( exp = `2026-10-15T08:00:00*` act = payload-failures[ 2 ]-first_recorded ).
    " only in the trace
    cl_abap_unit_assert=>assert_equals( exp = 'S_SERVICE' act = payload-failures[ 3 ]-object ).
    cl_abap_unit_assert=>assert_equals( exp = `trace` act = payload-failures[ 3 ]-sources ).
    cl_abap_unit_assert=>assert_initial( payload-failures[ 3 ]-last_seen ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-filtered_simulations ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true act = payload-trace_read ).
    cl_abap_unit_assert=>assert_equals( exp = `active` act = payload-trace_status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*first recorded 2026-10-14T07:00:00*S_SERVICE (SRV_NAME=3A4F, SRV_TYPE=HT)*IWSG ZACCX_SRV_0001* [trace]*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*transaction SM37, 3 times [su53, trace]*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*User trace (STUSERTRACE): active.*` act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( result-sources ) ).
  ENDMETHOD.

  METHOD nothing_recorded.
    run( EXPORTING user = `EMPTY` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-failures ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No failed authorization checks recorded for user **EMPTY***` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*User trace (STUSERTRACE): inactive.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*reproduce the error*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*auth/auth_user_trace*does not switch it on*` act = result-next_steps[ 2 ] ).

    run( EXPORTING user = `EMPTY` source = `trace` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*switched off*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_initial( payload-since_utc ).
  ENDMETHOD.

  METHOD trace_not_permitted.
    " source all: SU53 is still read, the trace gives a warning
    run( EXPORTING user = `NOSTUR` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_false act = payload-trace_read ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User trace not read: *S_ADMI_FCD*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*inactive, not read.*` act = result-summary ).

    TRY.
        run( user = `NOSTUR` source = `trace` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.

    TRY.
        run( user = `FAIL` source = `st01` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD hidden_user_denied.
    TRY.
        run( `HIDDEN` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
