"! <p class="shorttext synchronized">Access Explorer: local runtime pipeline</p>
"! Pipeline per call: resolve tool, usage authorization (customer extension
"! point ZIF_ACCX_AUTHORIZER), guard rails of write tools, resolve pseudonyms,
"! neutral validation, execute, privacy, render summary, audit log.
"! Write tools (descriptor read_only = false) are offered and run only where
"! the context allows writing (profile ALLOW_WRITE, no production client); a
"! stored plan is executed only with plan_id and confirm = true.
"! Never raises - every failure becomes a result with a non-ok status.
CLASS zcl_accx_runtime_local DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_runtime.

    METHODS constructor
      IMPORTING !registry TYPE REF TO zif_accx_registry
                !logger   TYPE REF TO zif_accx_logger OPTIONAL.

  PRIVATE SECTION.
    DATA registry TYPE REF TO zif_accx_registry.
    DATA logger   TYPE REF TO zif_accx_logger.

    "! Fails closed if the customer authorizer raises an exception
    METHODS is_authorized
      IMPORTING !ctx          TYPE REF TO zif_accx_context
                !descriptor   TYPE zif_accx_types=>ty_tool_descriptor
      RETURNING VALUE(result) TYPE abap_bool.

    "! Guard rails of a write tool; initial result = may run
    METHODS check_write
      IMPORTING !ctx          TYPE REF TO zif_accx_context
                !args         TYPE REF TO zif_accx_args
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_result.

    "! Returns an LLM-readable problem description, empty when valid
    METHODS validate
      IMPORTING !descriptor   TYPE zif_accx_types=>ty_tool_descriptor
                !args         TYPE REF TO zif_accx_args
      RETURNING VALUE(result) TYPE string.

    METHODS run
      IMPORTING !tool         TYPE REF TO zif_accx_tool
                !args         TYPE REF TO zif_accx_args
                !ctx          TYPE REF TO zif_accx_context
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_result.

    METHODS hash_args
      IMPORTING !args         TYPE REF TO zif_accx_args
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_runtime_local IMPLEMENTATION.

  METHOD constructor.
    me->registry = registry.
    me->logger   = logger.
  ENDMETHOD.

  METHOD zif_accx_runtime~get_catalog.
    DATA(write_allowed) = xsdbool( ctx->write_problem( ) IS INITIAL ).
    LOOP AT registry->get_tools( ctx->profile( ) ) INTO DATA(tool).
      DATA(descriptor) = tool->get_descriptor( ).
      " write tools are not offered where they may not run
      IF descriptor-read_only = abap_false AND write_allowed = abap_false.
        CONTINUE.
      ENDIF.
      IF is_authorized( ctx = ctx descriptor = descriptor ) = abap_true.
        APPEND descriptor TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_runtime~execute.
    DATA start      TYPE i.
    DATA stop       TYPE i.
    DATA descriptor TYPE zif_accx_types=>ty_tool_descriptor.
    GET RUN TIME FIELD start.

    DATA(tool) = registry->get_tool( name = tool_name profile = ctx->profile( ) ).
    IF tool IS NOT BOUND.
      result = VALUE #( status  = zif_accx_types=>co_status-invalid
                        summary = |Unknown tool '{ tool_name }' for this server.| ).
    ELSE.
      descriptor = tool->get_descriptor( ).
      IF is_authorized( ctx = ctx descriptor = descriptor ) = abap_false.
        result = VALUE #( status  = zif_accx_types=>co_status-denied
                          summary = |You are not authorized to use tool '{ tool_name }'.| ).
      ELSEIF descriptor-read_only = abap_false.
        " guard rails of write tools (decision E10)
        result = check_write( ctx = ctx args = args ).
      ENDIF.
      IF result-status IS INITIAL.
        DATA(clear_args) = args.
        TRY.
            clear_args = ctx->privacy( )->resolve_args( args ).
          CATCH cx_root INTO DATA(error).
            result = VALUE #( status  = zif_accx_types=>co_status-invalid
                              summary = |Arguments could not be resolved: { error->get_text( ) }| ).
        ENDTRY.
        IF result-status IS INITIAL.
          DATA(problem) = validate( descriptor = descriptor args = clear_args ).
          IF problem IS NOT INITIAL.
            result = VALUE #( status = zif_accx_types=>co_status-invalid summary = problem ).
          ELSE.
            result = run( tool = tool args = clear_args ctx = ctx ).
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    GET RUN TIME FIELD stop.
    IF logger IS BOUND.
      TRY.
          " write tools are always logged with their outcome
          DATA(writes) = xsdbool( descriptor-name IS NOT INITIAL AND descriptor-read_only = abap_false ).
          logger->log( VALUE #( caller       = ctx->caller( )
                                profile      = ctx->profile( )
                                system_id    = ctx->system_id( )
                                tool_name    = tool_name
                                status       = result-status
                                row_count    = result-total_count
                                hidden_count = result-hidden_by_authorization
                                duration_ms  = ( stop - start ) / 1000
                                args_hash    = hash_args( args )
                                message      = COND #( WHEN writes = abap_true
                                                       THEN |{ COND #( WHEN result-confirmation-plan_id IS NOT INITIAL
                                                                       THEN |plan { result-confirmation-plan_id }: | ) }| &&
                                                            |{ result-summary }|
                                                       WHEN result-status <> zif_accx_types=>co_status-ok
                                                       THEN result-summary ) ) ).
        CATCH cx_root ##NO_HANDLER.
          " logging must never break the tool call
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  METHOD check_write.
    DATA(problem) = ctx->write_problem( ).
    IF problem IS NOT INITIAL.
      result = VALUE #( status = zif_accx_types=>co_status-denied summary = problem ).
      RETURN.
    ENDIF.
    DATA(plan_id) = args->get_string( zif_accx_types=>co_param-plan_id ).
    DATA(confirmed) = args->get_boolean( name = zif_accx_types=>co_param-confirm default = abap_false ).
    IF plan_id IS NOT INITIAL AND confirmed = abap_false.
      result = VALUE #( status  = zif_accx_types=>co_status-invalid
                        summary = |Executing plan { plan_id } needs confirm = true, given only after the user has approved the plan.| ).
    ELSEIF plan_id IS INITIAL AND confirmed = abap_true.
      result = VALUE #( status  = zif_accx_types=>co_status-invalid
                        summary = `confirm is only allowed together with the plan_id of a stored plan; make the plan first.` ).
    ENDIF.
  ENDMETHOD.

  METHOD run.
    TRY.
        result = tool->execute( args = args ctx = ctx ).
        IF result-status IS INITIAL.
          result-status = zif_accx_types=>co_status-ok.
        ENDIF.
      CATCH zcx_accx_error INTO DATA(tool_error).
        result = VALUE #( status = tool_error->status summary = tool_error->get_text( ) ).
        RETURN.
      CATCH cx_root INTO DATA(error).
        result = VALUE #( status  = zif_accx_types=>co_status-error
                          summary = |Internal error: { error->get_text( ) }| ).
        RETURN.
    ENDTRY.

    TRY.
        ctx->privacy( )->protect_result( CHANGING result = result ).
      CATCH cx_root.
        " fail closed: never return data that may be unprotected
        result = VALUE #( status  = zif_accx_types=>co_status-error
                          summary = `Privacy processing failed - result withheld.` ).
        RETURN.
    ENDTRY.

    TRY.
        tool->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      CATCH cx_root INTO error.
        APPEND |Summary could not be rendered: { error->get_text( ) }| TO result-warnings.
    ENDTRY.
  ENDMETHOD.

  METHOD is_authorized.
    TRY.
        result = ctx->authorizer( )->check_tool( profile = ctx->profile( ) tool = descriptor ).
      CATCH cx_root.
        result = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD validate.
    LOOP AT descriptor-params INTO DATA(param).
      IF args->has( param-name ) = abap_false.
        IF param-required = abap_true.
          result = |Missing required parameter '{ param-name }'.|.
          RETURN.
        ENDIF.
        CONTINUE.
      ENDIF.
      CASE param-kind.
        WHEN zif_accx_types=>co_kind-string.
          DATA(value) = args->get_string( param-name ).
          IF param-required = abap_true AND value IS INITIAL.
            result = |Parameter '{ param-name }' must not be empty.|.
            RETURN.
          ENDIF.
          IF param-enum IS NOT INITIAL AND value IS NOT INITIAL
             AND NOT line_exists( param-enum[ table_line = value ] ).
            result = |Parameter '{ param-name }' must be one of: { concat_lines_of( table = param-enum sep = `, ` ) }.|.
            RETURN.
          ENDIF.
          IF param-maximum > 0 AND strlen( value ) > param-maximum.
            result = |Parameter '{ param-name }' must not exceed { param-maximum } characters.|.
            RETURN.
          ENDIF.
        WHEN zif_accx_types=>co_kind-integer.
          DATA(number) = args->get_integer( param-name ).
          IF ( param-minimum <> 0 OR param-maximum <> 0 )
             AND ( number < param-minimum OR number > param-maximum ).
            result = |Parameter '{ param-name }' must be between { param-minimum } and { param-maximum }.|.
            RETURN.
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD hash_args.
    DATA(text) = ``.
    DATA(names) = args->get_names( ).
    SORT names.
    LOOP AT names INTO DATA(name).
      text = |{ text }{ name }={ concat_lines_of( table = args->get_strings( name ) sep = `,` ) }{ args->get_string( name ) };|.
    ENDLOOP.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_char( EXPORTING if_algorithm  = 'SHA256'
                                                                   if_data       = text
                                                         IMPORTING ef_hashstring = DATA(hash) ).
        result = hash.
      CATCH cx_abap_message_digest.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
