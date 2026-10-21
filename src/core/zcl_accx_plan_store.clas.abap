"! <p class="shorttext synchronized">Access Explorer: plans of write tools (ZACCX_PLAN)</p>
"! Database implementation of the plan store. Claiming a plan is a single
"! conditional UPDATE, so a plan is executed at most once. No COMMIT: the
"! plan state is committed with the change the tool makes, or at the end of
"! the request. The cleanup changes a plan only in the state it was read in,
"! so it does not interfere with a claim running at the same time.
CLASS zcl_accx_plan_store DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_plan_store.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_row,
             plan_id   TYPE zaccx_plan-plan_id,
             tool_name TYPE zaccx_plan-tool_name,
             caller    TYPE zaccx_plan-caller,
             target    TYPE zaccx_plan-target,
             state     TYPE zaccx_plan-state,
           END OF ty_row,
           ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    METHODS now
      RETURNING VALUE(result) TYPE timestampl.

    "! now minus the given seconds
    METHODS before
      IMPORTING !now          TYPE timestampl
                !secs         TYPE i
      RETURNING VALUE(result) TYPE timestampl.

    METHODS cleaned
      IMPORTING !row          TYPE ty_row
                !action       TYPE string
      RETURNING VALUE(result) TYPE zif_accx_plan_store=>ty_cleaned.

ENDCLASS.

CLASS zcl_accx_plan_store IMPLEMENTATION.

  METHOD zif_accx_plan_store~create.
    result = plan.
    TRY.
        result-plan_id = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        result-plan_id = |{ sy-uname }{ now( ) }|.
    ENDTRY.
    result-caller     = COND #( WHEN plan-caller IS INITIAL THEN sy-uname ELSE plan-caller ).
    result-state      = zif_accx_plan_store=>co_state-open.
    result-created_at = now( ).
    " whole seconds, as shown to the user
    result-expires_at = cl_abap_tstmp=>add( tstmp = CONV timestamp( result-created_at ) secs = ttl_minutes * 60 ).
    INSERT zaccx_plan FROM @( VALUE #( plan_id     = result-plan_id
                                       tool_name   = result-tool_name
                                       caller      = result-caller
                                       profile     = result-profile
                                       target      = result-target
                                       state       = result-state
                                       created_at  = result-created_at
                                       expires_at  = result-expires_at
                                       fingerprint = result-fingerprint
                                       payload     = result-payload
                                       summary     = result-summary ) ).
  ENDMETHOD.

  METHOD zif_accx_plan_store~get.
    SELECT SINGLE * FROM zaccx_plan WHERE plan_id = @plan_id INTO @DATA(row).
    IF sy-subrc = 0.
      result = CORRESPONDING #( row ).
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_plan_store~claim.
    result = zif_accx_plan_store~get( plan_id ).
    IF result IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Plan { plan_id } does not exist.| ).
    ENDIF.
    IF result-caller <> caller OR to_lower( result-tool_name ) <> to_lower( tool_name ).
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |Plan { plan_id } was made by another user or for another tool.| ).
    ENDIF.
    IF result-state <> zif_accx_plan_store=>co_state-open.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Plan { plan_id } is { to_lower( result-state ) }; make a new plan.| ).
    ENDIF.
    IF result-expires_at < now( ).
      zif_accx_plan_store~close( plan_id = plan_id state = zif_accx_plan_store=>co_state-cancelled outcome = `expired` ).
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Plan { plan_id } has expired; make a new plan.| ).
    ENDIF.
    UPDATE zaccx_plan SET state = @zif_accx_plan_store=>co_state-running
      WHERE plan_id = @plan_id AND state = @zif_accx_plan_store=>co_state-open.
    IF sy-dbcnt <> 1.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Plan { plan_id } is already being executed.| ).
    ENDIF.
    result-state = zif_accx_plan_store=>co_state-running.
  ENDMETHOD.

  METHOD zif_accx_plan_store~close.
    UPDATE zaccx_plan SET state = @state, outcome = @outcome, closed_at = @( now( ) ) WHERE plan_id = @plan_id.
  ENDMETHOD.

  METHOD zif_accx_plan_store~cleanup.
    DATA rows TYPE ty_rows.
    DATA(current) = now( ).

    " open plans past their expiry can no longer be executed
    SELECT plan_id, tool_name, caller, target, state FROM zaccx_plan
      WHERE state = @zif_accx_plan_store=>co_state-open AND expires_at < @current
      ORDER BY created_at, plan_id
      INTO CORRESPONDING FIELDS OF TABLE @rows.
    LOOP AT rows INTO DATA(row).
      IF test_only = abap_false.
        UPDATE zaccx_plan SET state = @zif_accx_plan_store=>co_state-cancelled, outcome = `expired`, closed_at = @current
          WHERE plan_id = @row-plan_id AND state = @row-state.
        CHECK sy-dbcnt = 1.
      ENDIF.
      APPEND cleaned( row = row action = zif_accx_plan_store=>co_cleanup-expired ) TO result.
    ENDLOOP.

    " a claimed plan is closed in the same request; still RUNNING long after expiry means the request was aborted
    DATA(hang_limit) = before( now = current secs = hang_minutes * 60 ).
    SELECT plan_id, tool_name, caller, target, state FROM zaccx_plan
      WHERE state = @zif_accx_plan_store=>co_state-running AND expires_at < @hang_limit
      ORDER BY created_at, plan_id
      INTO CORRESPONDING FIELDS OF TABLE @rows.
    LOOP AT rows INTO row.
      IF test_only = abap_false.
        DATA(outcome) = |aborted: still running { hang_minutes } minutes after expiry; the change may be incomplete - check { row-target }|.
        UPDATE zaccx_plan SET state = @zif_accx_plan_store=>co_state-failed, outcome = @outcome, closed_at = @current
          WHERE plan_id = @row-plan_id AND state = @row-state.
        CHECK sy-dbcnt = 1.
      ENDIF.
      APPEND cleaned( row = row action = zif_accx_plan_store=>co_cleanup-hanging ) TO result.
    ENDLOOP.

    IF keep_days <= 0.
      RETURN.
    ENDIF.
    DATA(keep_limit) = before( now = current secs = keep_days * 86400 ).
    SELECT plan_id, tool_name, caller, target, state FROM zaccx_plan
      WHERE state <> @zif_accx_plan_store=>co_state-open AND state <> @zif_accx_plan_store=>co_state-running
        AND closed_at < @keep_limit
      ORDER BY created_at, plan_id
      INTO CORRESPONDING FIELDS OF TABLE @rows.
    LOOP AT rows INTO row.
      IF test_only = abap_false.
        DELETE FROM zaccx_plan WHERE plan_id = @row-plan_id AND state = @row-state.
        CHECK sy-dbcnt = 1.
      ENDIF.
      APPEND cleaned( row = row action = zif_accx_plan_store=>co_cleanup-deleted ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD now.
    GET TIME STAMP FIELD result.
  ENDMETHOD.

  METHOD before.
    result = cl_abap_tstmp=>subtractsecs( tstmp = CONV timestamp( now ) secs = secs ).
  ENDMETHOD.

  METHOD cleaned.
    result = VALUE #( plan_id   = row-plan_id
                      tool_name = row-tool_name
                      caller    = row-caller
                      target    = row-target
                      state     = row-state
                      action    = action ).
  ENDMETHOD.

ENDCLASS.
