"! <p class="shorttext synchronized">Access Explorer: tool contract</p>
"! One class per tool. Tools never reference an MCP SDK.
"! Execution is two-phased so that the summary is rendered from data that
"! already passed the privacy layer.
INTERFACE zif_accx_tool PUBLIC.

  METHODS get_descriptor
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_tool_descriptor.

  "! Phase 1: business logic. Fills data, status, sources, warnings - no summary.
  METHODS execute
    IMPORTING !args         TYPE REF TO zif_accx_args
              !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_result
    RAISING   zcx_accx_error.

  "! Phase 2: render summary and next steps from the privacy-protected result
  METHODS render_summary
    IMPORTING !ctx    TYPE REF TO zif_accx_context
    CHANGING  !result TYPE zif_accx_types=>ty_result.

ENDINTERFACE.
