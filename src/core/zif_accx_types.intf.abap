"! <p class="shorttext synchronized">Access Explorer: neutral types and constants</p>
"! SDK-neutral contract types shared by core, tools, domain services, plugins
"! and transport adapters. Must not reference any MCP SDK type.
INTERFACE zif_accx_types PUBLIC.

  "! Product release, semantic versioning MAJOR.MINOR.PATCH (see KTD of package ZACCX)
  CONSTANTS co_release TYPE string VALUE `0.35.0`.

  " Result status values
  CONSTANTS: BEGIN OF co_status,
               ok        TYPE string VALUE `ok`,
               partial   TYPE string VALUE `partial`,
               not_found TYPE string VALUE `not_found`,
               ambiguous TYPE string VALUE `ambiguous`,
               denied    TYPE string VALUE `denied`,
               invalid   TYPE string VALUE `invalid`,
               error     TYPE string VALUE `error`,
               "! a write tool stored a plan; the user must confirm it before it is executed
               confirm   TYPE string VALUE `confirmation_required`,
             END OF co_status.

  " Parameter kinds (mapped to JSON schema types by the adapters)
  CONSTANTS: BEGIN OF co_kind,
               string      TYPE string VALUE `string`,
               integer     TYPE string VALUE `integer`,
               number      TYPE string VALUE `number`,
               boolean     TYPE string VALUE `boolean`,
               date        TYPE string VALUE `date`,
               string_list TYPE string VALUE `string_list`,
             END OF co_kind.

  " Tool groups (used by server profiles)
  CONSTANTS: BEGIN OF co_group,
               user  TYPE string VALUE `USER`,
               role  TYPE string VALUE `ROLE`,
               diag  TYPE string VALUE `DIAG`,
               fiori TYPE string VALUE `FIORI`,
               data  TYPE string VALUE `DATA`,
               audit TYPE string VALUE `AUDIT`,
               "! write tools (plugin ADMIN); only in profiles with ALLOW_WRITE
               admin TYPE string VALUE `ADMIN`,
             END OF co_group.

  " Data sensitivity of a tool result
  CONSTANTS: BEGIN OF co_sensitivity,
               normal   TYPE string VALUE `normal`,
               personal TYPE string VALUE `personal`,
               security TYPE string VALUE `security`,
             END OF co_sensitivity.

  " Reserved parameter names with a uniform meaning across all tools
  CONSTANTS: BEGIN OF co_param,
               max_rows TYPE string VALUE `max_rows`,
               cursor   TYPE string VALUE `cursor`,
               language TYPE string VALUE `language`,
               system   TYPE string VALUE `system`,
               "! write tools: id of the stored plan to execute
               plan_id  TYPE string VALUE `plan_id`,
               "! write tools: the user confirmed the plan (required together with plan_id)
               confirm  TYPE string VALUE `confirm`,
             END OF co_param.

  " One tool input parameter
  TYPES: BEGIN OF ty_param,
           name        TYPE string,
           kind        TYPE string,
           required    TYPE abap_bool,
           description TYPE string,
           enum        TYPE string_table,
           default     TYPE string,
           "! minimum/maximum (integer, number) or length (string); both initial = unbounded
           minimum     TYPE i,
           maximum     TYPE i,
         END OF ty_param,
         ty_params TYPE STANDARD TABLE OF ty_param WITH KEY name.

  " Neutral tool descriptor (catalog entry)
  TYPES: BEGIN OF ty_tool_descriptor,
           name               TYPE string,
           title              TYPE string,
           description        TYPE string,
           group              TYPE string,
           params             TYPE ty_params,
           "! Absolute RTTI type name of the result data payload (for output schemas)
           output_type        TYPE string,
           "! abap_false = write tool: only in profiles with ALLOW_WRITE, never in production clients
           read_only          TYPE abap_bool,
           idempotent         TYPE abap_bool,
           "! write tool that may change or remove existing data
           destructive        TYPE abap_bool,
           long_running       TYPE abap_bool,
           sensitivity        TYPE string,
           "! Empty for core tools, otherwise the contributing plugin id
           plugin_id          TYPE string,
           "! Reserved: output schema rendered by a remote system (federation)
           output_schema_json TYPE string,
         END OF ty_tool_descriptor,
         ty_tool_descriptors TYPE STANDARD TABLE OF ty_tool_descriptor WITH KEY name.

  " Plan of a write tool waiting for the user's confirmation (status confirmation_required)
  TYPES: BEGIN OF ty_confirmation,
           plan_id    TYPE string,
           "! what will be changed, for the confirmation prompt
           prompt     TYPE string,
           "! plan expiry, ISO timestamp UTC
           expires_at TYPE string,
         END OF ty_confirmation.

  " Neutral tool result
  TYPES: BEGIN OF ty_result,
           status                  TYPE string,
           "! Markdown summary for the LLM / human reader (rendered after privacy step)
           summary                 TYPE string,
           data                    TYPE REF TO data,
           "! Reserved: payload serialized by a remote system (federation)
           data_json               TYPE string,
           next_steps              TYPE string_table,
           "! Evidence: tables, APIs, transactions the answer is based on
           sources                 TYPE string_table,
           warnings                TYPE string_table,
           truncated               TYPE abap_bool,
           total_count             TYPE i,
           hidden_by_authorization TYPE i,
           "! set with status confirmation_required
           confirmation            TYPE ty_confirmation,
         END OF ty_result.

  " Outcome of a prerequisite or consistency check
  TYPES: BEGIN OF ty_check_result,
           ok      TYPE abap_bool,
           message TYPE string,
         END OF ty_check_result.

ENDINTERFACE.
