"! <p class="shorttext synchronized">Access Explorer: runtime (local or remote)</p>
"! The only entry point transport adapters use. Local implementation runs the
"! pipeline in this system; a router/remote implementation can be added for
"! central (federated) servers without touching adapters.
INTERFACE zif_accx_runtime PUBLIC.

  "! Tools of the context's profile the caller is authorized for
  METHODS get_catalog
    IMPORTING !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_tool_descriptors.

  "! Prompts of the context's profile whose tools are all available to the caller
  METHODS get_prompts DEFAULT IGNORE
    IMPORTING !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_prompt=>ty_descriptors.

  "! Never raises: an unknown, unavailable or badly called prompt is returned with a non-ok status
  METHODS get_prompt DEFAULT IGNORE
    IMPORTING !name         TYPE string
              !args         TYPE REF TO zif_accx_args
              !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_prompt=>ty_result.

  METHODS get_resources DEFAULT IGNORE
    IMPORTING !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_resource=>ty_descriptors.

  "! Never raises: an unknown resource is returned with status not_found
  METHODS read_resource DEFAULT IGNORE
    IMPORTING !uri          TYPE string
              !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_resource=>ty_content.

  "! Never raises: every failure is returned as a result with a non-ok status
  METHODS execute
    IMPORTING !tool_name    TYPE string
              !args         TYPE REF TO zif_accx_args
              !ctx          TYPE REF TO zif_accx_context
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_result.

ENDINTERFACE.
