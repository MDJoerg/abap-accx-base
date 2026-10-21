"! <p class="shorttext synchronized">Access Explorer: privacy strategy</p>
"! Applied centrally by the runtime. Personal fields are recognized by their
"! data element (configuration), so tools need no privacy code.
INTERFACE zif_accx_privacy PUBLIC.

  "! Outbound: protect result data before the summary is rendered
  METHODS protect_result
    CHANGING !result TYPE zif_accx_types=>ty_result.

  "! Inbound: map pseudonyms in arguments back to clear values
  METHODS resolve_args
    IMPORTING !args         TYPE REF TO zif_accx_args
    RETURNING VALUE(result) TYPE REF TO zif_accx_args.

ENDINTERFACE.
