"! <p class="shorttext synchronized">Access Explorer: plugin contract</p>
"! Implemented once per plugin package (ZACCX_PLG_*). The core tool set is
"! contributed through the same contract by a built-in plugin with id CORE.
"! New plugins are inactive until explicitly activated (decision E6).
INTERFACE zif_accx_plugin PUBLIC.

  "! Incremented only on incompatible contract changes
  CONSTANTS co_core_api_version TYPE i VALUE 1.

  TYPES: BEGIN OF ty_info,
           id                TYPE string,
           title             TYPE string,
           version           TYPE string,
           required_core_api TYPE i,
         END OF ty_info.

  TYPES ty_tools     TYPE STANDARD TABLE OF REF TO zif_accx_tool WITH EMPTY KEY.
  TYPES ty_prompts   TYPE STANDARD TABLE OF REF TO zif_accx_prompt WITH EMPTY KEY.
  TYPES ty_resources TYPE STANDARD TABLE OF REF TO zif_accx_resource WITH EMPTY KEY.

  METHODS get_info
    RETURNING VALUE(result) TYPE ty_info.

  "! E.g. software component installed, destination reachable
  METHODS check_prerequisites
    RETURNING VALUE(result) TYPE zif_accx_types=>ty_check_result.

  METHODS get_tools
    RETURNING VALUE(result) TYPE ty_tools.

  "! Ready-made instructions for the client; optional, none by default
  METHODS get_prompts DEFAULT IGNORE
    RETURNING VALUE(result) TYPE ty_prompts.

  "! Background texts for the client; optional, none by default
  METHODS get_resources DEFAULT IGNORE
    RETURNING VALUE(result) TYPE ty_resources.

ENDINTERFACE.
