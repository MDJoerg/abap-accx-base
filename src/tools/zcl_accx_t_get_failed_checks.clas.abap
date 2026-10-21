"! <p class="shorttext synchronized">Access Explorer tool: get_failed_authorization_checks</p>
"! Reads the authorization checks that failed for a user (SU53 buffer of all
"! application servers, user trace STUSERTRACE), drops entries caused by ACCX
"! simulations and condenses repeated checks across both sources.
CLASS zcl_accx_t_get_failed_checks DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_failure,
             "! newest occurrence in the SU53 buffer
             last_seen      TYPE string,
             "! first occurrence recorded by the user trace
             first_recorded TYPE string,
             "! su53, trace or both
             sources        TYPE string,
             "! SU53 entries plus distinct trace entries
             occurrences    TYPE i,
             object         TYPE xuobject,
             condition      TYPE string,
             return_code    TYPE i,
             outcome        TYPE string,
             transaction    TYPE tcode,
             application    TYPE string,
             program        TYPE programm,
             line           TYPE i,
             instance       TYPE msname2,
             fields         TYPE zif_accx_auth_evaluator=>ty_field_values,
           END OF ty_failure,
           ty_failures TYPE STANDARD TABLE OF ty_failure WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user                 TYPE syuname,
             "! su53, trace or all
             source               TYPE string,
             since_utc            TYPE string,
             trace_since_utc      TYPE string,
             "! active, active with filter, inactive (on this application server)
             trace_status         TYPE string,
             "! the trace records this user (no user filter, or the user passes it)
             trace_records_user   TYPE abap_bool,
             trace_read           TYPE abap_bool,
             failures             TYPE ty_failures,
             "! entries dropped because they stem from simulations (ACCX or FOR USER)
             filtered_simulations TYPE i,
             unreachable_servers  TYPE string_table,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `get_failed_authorization_checks`.
    CONSTANTS co_default_minutes TYPE i VALUE 1440.
    CONSTANTS co_default_trace_minutes TYPE i VALUE 43200.

    CONSTANTS: BEGIN OF co_source,
                 su53  TYPE string VALUE `su53`,
                 trace TYPE string VALUE `trace`,
                 all   TYPE string VALUE `all`,
               END OF co_source.

    CONSTANTS: BEGIN OF co_trace_status,
                 active   TYPE string VALUE `active`,
                 filtered TYPE string VALUE `active with filter`,
                 inactive TYPE string VALUE `inactive`,
               END OF co_trace_status.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS outcome
      IMPORTING !return_code  TYPE i
      RETURNING VALUE(result) TYPE string.

    METHODS condition
      IMPORTING !fields       TYPE zif_accx_auth_evaluator=>ty_field_values
      RETURNING VALUE(result) TYPE string.

    METHODS explain_hint
      IMPORTING !user         TYPE syuname
                !failure      TYPE ty_failure
      RETURNING VALUE(result) TYPE string.

    METHODS iso
      IMPORTING !timestamp    TYPE timestampl
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_failed_checks IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get failed authorization checks`
      description = |Lists the authorization checks that failed for a user. Sources: the SU53 buffers of all application | &&
                    |servers (latest failures, lost on server restart) and the user trace STUSERTRACE (table SUAUTHVALTRC, | &&
                    |kept in the database, records every distinct check once with the time it first occurred - only while | &&
                    |the trace is switched on for the user). Identical checks are condensed across both sources with their | &&
                    |number of occurrences, newest first. Checks caused by simulations (check_user_access, | &&
                    |explain_missing_access or other AUTHORITY-CHECK FOR USER calls) are filtered out. The result says | &&
                    |whether the user trace is active. If nothing is found, the user should reproduce the error first. Use | &&
                    |the result with explain_missing_access to find a role that closes the gap.|
      group       = zif_accx_types=>co_group-diag
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_FAILED_CHECKS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `SAP user ID whose failed checks are read, e.g. JDOE (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `source`
                                      description = |all (default: SU53 buffer and user trace), su53 or trace. Reading the | &&
                                                    |user trace needs S_ADMI_FCD STUR; with all, a missing authorization | &&
                                                    |only gives a warning.|
                                      enum        = VALUE #( ( co_source-all ) ( co_source-su53 ) ( co_source-trace ) ) ) )
                             ( param( name        = `since_minutes`
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = |Only failures of the last N minutes (1-43200; default { co_default_minutes } | &&
                                                    |for the SU53 buffer, { co_default_trace_minutes } for the user trace, which | &&
                                                    |records the first occurrence only).|
                                      minimum     = 1
                                      maximum     = 43200 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA now     TYPE timestampl.
    DATA entries TYPE zif_accx_failure_source=>ty_failures.

    DATA(user)    = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(source)  = to_lower( condense( args->get_string( name = `source` default = co_source-all ) ) ).
    DATA(minutes) = args->get_integer( name = `since_minutes` default = co_default_minutes ).
    DATA(trace_minutes) = COND i( WHEN args->has( `since_minutes` ) = abap_true THEN minutes ELSE co_default_trace_minutes ).

    IF source <> co_source-all AND source <> co_source-su53 AND source <> co_source-trace.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Unknown source "{ source }" - use all, su53 or trace.| ).
    ENDIF.
    IF zcl_accx_domain_factory=>user_repo( )->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |User { user } does not exist in system { sy-sysid }, client { sy-mandt }.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { user } (S_USER_GRP, activity 03).| ).
    ENDIF.

    DATA(failure_source) = zcl_accx_domain_factory=>failure_source( ).
    DATA(payload) = NEW ty_payload( user = user source = source ).
    result-data = payload.
    GET TIME STAMP FIELD now.

    IF source <> co_source-trace.
      DATA(from) = cl_abap_tstmp=>subtractsecs( tstmp = now secs = minutes * 60 ).
      DATA(su53) = failure_source->read_su53( user = user from = from ).
      payload->since_utc           = iso( from ).
      payload->unreachable_servers = su53-errors.
      APPEND LINES OF su53-failures TO entries.
      APPEND `SU53 buffer (SUSR_USER_SU53_READ)` TO result-sources.
      LOOP AT su53-errors INTO DATA(error).
        APPEND |Application server not read: { error }| TO result-warnings.
      ENDLOOP.
    ENDIF.

    IF source <> co_source-su53.
      DATA(status) = failure_source->trace_status( user ).
      payload->trace_status       = SWITCH #( status-mode
                                              WHEN zif_accx_failure_source=>co_trace_mode-active   THEN co_trace_status-active
                                              WHEN zif_accx_failure_source=>co_trace_mode-filtered THEN co_trace_status-filtered
                                              ELSE co_trace_status-inactive ).
      payload->trace_records_user = status-covers_user.
      DATA(trace_from) = cl_abap_tstmp=>subtractsecs( tstmp = now secs = trace_minutes * 60 ).
      payload->trace_since_utc = iso( trace_from ).
      TRY.
          DATA(trace) = failure_source->read_trace( user = user from = trace_from ).
          payload->trace_read = abap_true.
          APPEND LINES OF trace-failures TO entries.
          APPEND `User trace STUSERTRACE (SUAUTH_READ_USER_TRACE, table SUAUTHVALTRC)` TO result-sources.
          APPEND LINES OF trace-errors TO result-warnings.
        CATCH zcx_accx_error INTO DATA(trace_error).
          IF source = co_source-trace.
            RAISE EXCEPTION trace_error.
          ENDIF.
          APPEND |User trace not read: { trace_error->get_text( ) }| TO result-warnings.
      ENDTRY.
      IF status-mode = zif_accx_failure_source=>co_trace_mode-inactive AND source = co_source-trace.
        APPEND `The user trace is switched off on this application server; only entries recorded earlier are shown.`
               TO result-warnings.
      ELSEIF status-mode <> zif_accx_failure_source=>co_trace_mode-inactive AND status-covers_user = abap_false.
        APPEND |The user trace is active with a filter that does not include { user }.| TO result-warnings.
      ENDIF.
    ENDIF.

    " newest first, identical checks condensed across both sources (the first known application is kept)
    SORT entries BY timestamp DESCENDING.
    LOOP AT entries INTO DATA(entry).
      IF entry-is_simulation = abap_true.
        payload->filtered_simulations += 1.
        CONTINUE.
      ENDIF.
      DATA(condition) = condition( entry-fields ).
      ASSIGN payload->failures[ object      = entry-object
                                condition   = condition
                                transaction = entry-transaction ] TO FIELD-SYMBOL(<known>).
      IF sy-subrc <> 0.
        APPEND VALUE #( object      = entry-object
                        condition   = condition
                        return_code = entry-return_code
                        outcome     = outcome( entry-return_code )
                        transaction = entry-transaction
                        application = entry-application
                        program     = entry-program
                        line        = entry-line
                        instance    = entry-instance
                        fields      = entry-fields ) TO payload->failures ASSIGNING <known>.
      ELSEIF <known>-application IS INITIAL.
        <known>-application = entry-application.
      ENDIF.
      <known>-occurrences += 1.
      IF entry-source = zif_accx_failure_source=>co_source-trace.
        " sorted newest first: the last trace entry is the first recorded one
        <known>-first_recorded = iso( entry-timestamp ).
      ELSEIF <known>-last_seen IS INITIAL.
        <known>-last_seen = iso( entry-timestamp ).
        <known>-instance  = entry-instance.
      ENDIF.
      IF find( val = <known>-sources sub = entry-source ) < 0.
        <known>-sources = COND #( WHEN <known>-sources IS INITIAL THEN entry-source ELSE |{ <known>-sources }, { entry-source }| ).
      ENDIF.
    ENDLOOP.

    result-total_count = lines( payload->failures ).
    IF lines( payload->failures ) > ctx->max_rows( ).
      DELETE payload->failures FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    IF payload->failures IS NOT INITIAL.
      APPEND explain_hint( user = user failure = payload->failures[ 1 ] ) TO result-next_steps.
      RETURN.
    ENDIF.
    IF source <> co_source-trace.
      APPEND |The SU53 buffer only keeps the latest failures per application server and is cleared on restart. | &&
             |Ask { user } to reproduce the error, then call this tool again.| TO result-next_steps.
    ELSEIF status-covers_user = abap_true.
      APPEND |Ask { user } to reproduce the error while the user trace is active, then call this tool again.| TO result-next_steps.
    ENDIF.
    IF source <> co_source-su53 AND ( status-mode = zif_accx_failure_source=>co_trace_mode-inactive OR status-covers_user = abap_false ).
      APPEND |To record failures independently of the SU53 buffer, an administrator can switch on the user trace | &&
             |(transaction STUSERTRACE, profile parameter auth/auth_user_trace = Y, or F with { user } in the user filter). | &&
             |The Access Explorer does not switch it on.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD iso.
    result = |{ cl_abap_tstmp=>move_to_short_trunc( timestamp ) TIMESTAMP = ISO }|.
  ENDMETHOD.

  METHOD outcome.
    result = SWITCH #( return_code
                       WHEN 4  THEN `authorization for the object exists, but not for these values`
                       WHEN 12 THEN `no authorization for this object at all`
                       WHEN 40 THEN `invalid user ID`
                       ELSE |failed with return code { return_code }| ).
  ENDMETHOD.

  METHOD condition.
    LOOP AT fields INTO DATA(field).
      result = |{ result }{ COND #( WHEN result IS NOT INITIAL THEN `, ` ) }{ field-field }={ field-value }|.
    ENDLOOP.
  ENDMETHOD.

  METHOD explain_hint.
    IF failure-object = 'S_TCODE' AND line_exists( failure-fields[ field = 'TCD' ] ).
      result = |Use explain_missing_access with user { user }, target_type transaction, target | &&
               |{ failure-fields[ field = 'TCD' ]-value } to find a role that closes the gap.|.
      RETURN.
    ENDIF.
    DATA(values) = VALUE string_table( FOR f IN failure-fields WHERE ( value IS NOT INITIAL ) ( |{ f-field }={ f-value }| ) ).
    result = |Use explain_missing_access with user { user }, target_type authorization, target { failure-object }| &&
             |{ COND #( WHEN values IS NOT INITIAL THEN |, values { concat_lines_of( table = values sep = ` ` ) }| ) }| &&
             | to find a role that closes the gap.|.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    DATA(period) = COND string( WHEN <payload>-since_utc IS NOT INITIAL AND <payload>-trace_read = abap_true
                                THEN |since { <payload>-since_utc } UTC (SU53) and { <payload>-trace_since_utc } UTC (user trace)|
                                WHEN <payload>-since_utc IS NOT INITIAL
                                THEN |since { <payload>-since_utc } UTC|
                                ELSE |since { <payload>-trace_since_utc } UTC (user trace)| ).
    IF <payload>-failures IS INITIAL.
      result-summary = |No failed authorization checks recorded for user **{ <payload>-user }** { period }.|.
    ELSE.
      result-summary = |**{ result-total_count }** distinct failed authorization | &&
                       |{ COND #( WHEN result-total_count = 1 THEN `check` ELSE `checks` ) } for user **{ <payload>-user }** | &&
                       |{ period }, newest first:|.
      LOOP AT <payload>-failures INTO DATA(failure).
        result-summary = |{ result-summary }\n- | &&
                         |{ COND #( WHEN failure-last_seen IS NOT INITIAL THEN failure-last_seen
                                    ELSE |first recorded { failure-first_recorded }| ) }: | &&
                         |{ failure-object } ({ failure-condition }) - { failure-outcome }| &&
                         |{ COND #( WHEN failure-transaction IS NOT INITIAL THEN |, transaction { failure-transaction }| ) }| &&
                         |{ COND #( WHEN failure-application IS NOT INITIAL THEN |, { failure-application }| ) }| &&
                         |{ COND #( WHEN failure-occurrences > 1 THEN |, { failure-occurrences } times| ) }| &&
                         |{ COND #( WHEN <payload>-trace_read = abap_true AND <payload>-source = co_source-all
                                    THEN | [{ failure-sources }]| ) }|.
      ENDLOOP.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList truncated - raise max_rows or shorten since_minutes.|.
    ENDIF.
    IF <payload>-filtered_simulations > 0.
      result-summary = |{ result-summary }\n\n{ <payload>-filtered_simulations } entries were ignored because the Access Explorer | &&
                       |itself caused them (simulations, visibility checks) or they were checked for another user.|.
    ENDIF.
    IF <payload>-trace_status IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nUser trace (STUSERTRACE): { <payload>-trace_status }| &&
                       |{ COND #( WHEN <payload>-trace_status <> co_trace_status-inactive AND <payload>-trace_records_user = abap_false
                                  THEN |, { <payload>-user } is not in the user filter| ) }| &&
                       |{ COND #( WHEN <payload>-trace_read = abap_false THEN `, not read` ) }.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
