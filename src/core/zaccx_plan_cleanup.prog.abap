*&---------------------------------------------------------------------*
*& Access Explorer: housekeeping of ZACCX_PLAN, to be scheduled as a
*& periodic background job (e.g. daily). Cancels expired open plans,
*& fails plans that hang in RUNNING (the change may be incomplete) and
*& deletes closed plans after the retention period.
*&---------------------------------------------------------------------*
REPORT zaccx_plan_cleanup.

PARAMETERS p_hang TYPE i DEFAULT zif_accx_plan_store=>co_default_hang_minutes.
PARAMETERS p_keep TYPE i DEFAULT zif_accx_plan_store=>co_default_keep_days.
PARAMETERS p_test AS CHECKBOX DEFAULT abap_false.

START-OF-SELECTION.
  IF p_hang < 0 OR p_keep < 0.
    MESSAGE 'Minutes and days must not be negative' TYPE 'E'.
  ENDIF.

  DATA(cleaned) = zcl_accx_factory=>plan_store( )->cleanup( hang_minutes = p_hang
                                                            keep_days    = p_keep
                                                            test_only    = p_test ).
  IF p_test = abap_false.
    COMMIT WORK.
  ENDIF.

  DATA(counts) = |expired { REDUCE i( INIT n = 0 FOR c IN cleaned WHERE ( action = zif_accx_plan_store=>co_cleanup-expired ) NEXT n = n + 1 ) }, | &&
                 |hanging { REDUCE i( INIT n = 0 FOR c IN cleaned WHERE ( action = zif_accx_plan_store=>co_cleanup-hanging ) NEXT n = n + 1 ) }, | &&
                 |deleted { REDUCE i( INIT n = 0 FOR c IN cleaned WHERE ( action = zif_accx_plan_store=>co_cleanup-deleted ) NEXT n = n + 1 ) }|.
  WRITE / |{ COND #( WHEN p_test = abap_true THEN `Test run - nothing changed. ` ) }Plans { counts }.|.
  " job log
  MESSAGE |Plans { counts }{ COND #( WHEN p_test = abap_true THEN ` (test run)` ) }| TYPE 'S'.

  IF cleaned IS NOT INITIAL.
    SKIP.
    LOOP AT cleaned INTO DATA(entry).
      WRITE: / entry-action, entry-state, entry-tool_name(20), entry-caller, entry-target(30), entry-plan_id.
    ENDLOOP.
  ENDIF.
  LOOP AT cleaned INTO entry WHERE action = zif_accx_plan_store=>co_cleanup-hanging.
    MESSAGE |Plan { entry-plan_id } ({ entry-tool_name }, { entry-target }) was hanging - check the target| TYPE 'S' DISPLAY LIKE 'W'.
  ENDLOOP.
