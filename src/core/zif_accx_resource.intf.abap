"! <p class="shorttext synchronized">Access Explorer: resource contract</p>
"! A resource is readable background text the MCP client can load or offer to
"! the model, for example a glossary or a FAQ. The text is fixed in the class
"! and never contains system data. Resources never reference an MCP SDK.
INTERFACE zif_accx_resource PUBLIC.

  TYPES: BEGIN OF ty_descriptor,
           uri         TYPE string,
           name        TYPE string,
           title       TYPE string,
           description TYPE string,
           mime_type   TYPE string,
         END OF ty_descriptor,
         ty_descriptors TYPE STANDARD TABLE OF ty_descriptor WITH EMPTY KEY.

  " status: see zif_accx_types=>co_status (ok, not_found); message is the
  " reason when the status is not ok
  TYPES: BEGIN OF ty_content,
           status    TYPE string,
           message   TYPE string,
           uri       TYPE string,
           mime_type TYPE string,
           text      TYPE string,
         END OF ty_content.

  METHODS get_descriptor
    RETURNING VALUE(result) TYPE ty_descriptor.

  "! The text of the resource. visible_tools are the tools available to the
  "! caller, so that a text can leave out tools of other profiles.
  METHODS read
    IMPORTING visible_tools TYPE string_table
    RETURNING VALUE(result) TYPE string.

ENDINTERFACE.
