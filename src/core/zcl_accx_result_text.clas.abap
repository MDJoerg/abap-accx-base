"! <p class="shorttext synchronized">Access Explorer: text of a tool result for clients</p>
"! The readable text every transport adapter returns next to the structured
"! data: summary, warnings, next steps and sources. Kept in the core so that
"! all adapters show the same text.
CLASS zcl_accx_result_text DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS compose
      IMPORTING !tool_result  TYPE zif_accx_types=>ty_result
      RETURNING VALUE(result) TYPE string.

    "! True for the statuses that are reported as an error to the client
    CLASS-METHODS is_failure
      IMPORTING !tool_result  TYPE zif_accx_types=>ty_result
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_result_text IMPLEMENTATION.

  METHOD compose.
    result = COND #( WHEN tool_result-summary IS NOT INITIAL THEN tool_result-summary ELSE |Status: { tool_result-status }| ).
    IF tool_result-status = zif_accx_types=>co_status-confirm OR tool_result-status = zif_accx_types=>co_status-partial.
      result = |Status: { tool_result-status }\n\n{ result }|.
    ENDIF.
    IF tool_result-warnings IS NOT INITIAL.
      result = |{ result }\n\nWarnings:|.
      LOOP AT tool_result-warnings INTO DATA(warning).
        result = |{ result }\n- { warning }|.
      ENDLOOP.
    ENDIF.
    IF tool_result-next_steps IS NOT INITIAL.
      result = |{ result }\n\nNext steps:|.
      LOOP AT tool_result-next_steps INTO DATA(next_step).
        result = |{ result }\n- { next_step }|.
      ENDLOOP.
    ENDIF.
    IF tool_result-sources IS NOT INITIAL.
      result = |{ result }\n\nSources: { concat_lines_of( table = tool_result-sources sep = `, ` ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD is_failure.
    result = xsdbool( tool_result-status = zif_accx_types=>co_status-denied
                   OR tool_result-status = zif_accx_types=>co_status-invalid
                   OR tool_result-status = zif_accx_types=>co_status-error ).
  ENDMETHOD.

ENDCLASS.

