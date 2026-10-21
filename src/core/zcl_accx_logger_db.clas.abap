"! <p class="shorttext synchronized">Access Explorer: audit log to ZACCX_LOG</p>
"! No explicit commit: the entry is persisted with the LUW of the request.
CLASS zcl_accx_logger_db DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_logger.

ENDCLASS.

CLASS zcl_accx_logger_db IMPLEMENTATION.

  METHOD zif_accx_logger~log.
    DATA row TYPE zaccx_log.
    TRY.
        row-log_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        RETURN.
    ENDTRY.
    GET TIME STAMP FIELD row-logged_at.
    row-caller       = entry-caller.
    row-profile      = entry-profile.
    row-system_id    = entry-system_id.
    row-tool_name    = entry-tool_name.
    row-status       = entry-status.
    row-row_count    = entry-row_count.
    row-hidden_count = entry-hidden_count.
    row-duration_ms  = entry-duration_ms.
    row-args_hash    = entry-args_hash.
    row-message      = entry-message.
    INSERT zaccx_log FROM @row.
  ENDMETHOD.

ENDCLASS.
