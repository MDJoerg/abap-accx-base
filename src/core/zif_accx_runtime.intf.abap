"! <p class="shorttext synchronized">Access Explorer: runtime (local or remote)</p>
"! The only entry point transport adapters use. Local implementation runs the
"! pipeline in this system; a router/remote implementation can be added for
"! central (federated) servers without touching adapters.
INTERFACE zif_accx_runtime PUBLIC.

  "! Tools of the context's profile the caller is authorized for
  METHODS get_catalog
    IMPORTING !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_tool_descriptors.

  "! Never raises: every failure is returned as a result with a non-ok status
  METHODS execute
    IMPORTING !tool_name    TYPE string
              !args         TYPE REF TO zif_accx_args
              !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_result.

ENDINTERFACE.
