"! <p class="shorttext synchronized">Access Explorer: tool registry</p>
"! Collects the tools of all active plugins (incl. the built-in CORE plugin)
"! and filters them by server profile.
INTERFACE zif_accx_registry PUBLIC.

  TYPES: BEGIN OF ty_issue,
           plugin_id TYPE string,
           message   TYPE string,
         END OF ty_issue,
         ty_issues TYPE STANDARD TABLE OF ty_issue WITH EMPTY KEY.

  METHODS get_tools
    IMPORTING !profile      TYPE string
    RETURNING VALUE(result) TYPE zif_accx_plugin=>ty_tools.

  "! Unbound when the tool does not exist in the profile
  METHODS get_tool
    IMPORTING !name         TYPE string
              !profile      TYPE string
    RETURNING VALUE(result) TYPE REF TO zif_accx_tool.

  "! Prompts of the active plugins; they are offered only where their tools are available
  METHODS get_prompts DEFAULT IGNORE
    IMPORTING !profile      TYPE string
    RETURNING VALUE(result) TYPE zif_accx_plugin=>ty_prompts.

  METHODS get_resources DEFAULT IGNORE
    IMPORTING !profile      TYPE string
    RETURNING VALUE(result) TYPE zif_accx_plugin=>ty_resources.

  "! Plugins skipped or tools rejected while loading (for diagnostics)
  METHODS get_issues
    RETURNING VALUE(result) TYPE ty_issues.

ENDINTERFACE.
