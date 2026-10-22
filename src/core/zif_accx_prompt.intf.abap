"! <p class="shorttext synchronized">Access Explorer: prompt contract</p>
"! A prompt is a ready-made instruction a user picks in the MCP client (for
"! example as a slash command): it tells the model which tools to call in
"! which order. The text is fixed in the class and never contains system data;
"! only the checked, single-line values of the declared arguments are inserted.
"! Prompts never reference an MCP SDK. They are offered only where all tools
"! they rely on are available to the caller.
INTERFACE zif_accx_prompt PUBLIC.

  TYPES: BEGIN OF ty_argument,
           name        TYPE string,
           description TYPE string,
           required    TYPE abap_bool,
         END OF ty_argument,
         ty_arguments TYPE STANDARD TABLE OF ty_argument WITH EMPTY KEY.

  " tools: names of the tools the instruction relies on
  TYPES: BEGIN OF ty_descriptor,
           name        TYPE string,
           title       TYPE string,
           description TYPE string,
           arguments   TYPE ty_arguments,
           tools       TYPE string_table,
         END OF ty_descriptor,
         ty_descriptors TYPE STANDARD TABLE OF ty_descriptor WITH EMPTY KEY.

  TYPES: BEGIN OF ty_message,
           role TYPE string,
           text TYPE string,
         END OF ty_message,
         ty_messages TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY.

  " status: see zif_accx_types=>co_status (ok, invalid, not_found); message
  " is the reason when the status is not ok
  TYPES: BEGIN OF ty_result,
           status      TYPE string,
           message     TYPE string,
           description TYPE string,
           messages    TYPE ty_messages,
         END OF ty_result.

  CONSTANTS: BEGIN OF co_role,
               user      TYPE string VALUE `user`,
               assistant TYPE string VALUE `assistant`,
             END OF co_role.

  METHODS get_descriptor
    RETURNING VALUE(result) TYPE ty_descriptor.

  "! Builds the messages for the given argument values. Never raises: a missing
  "! or malformed argument is returned with status invalid.
  METHODS render
    IMPORTING !args         TYPE REF TO zif_accx_args
    RETURNING VALUE(result) TYPE ty_result.

ENDINTERFACE.
