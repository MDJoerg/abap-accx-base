"! <p class="shorttext synchronized">Access Explorer: tool arguments (adapter-neutral)</p>
"! Implemented by each transport adapter as a thin wrapper over its request
"! object, and by core helpers for tests and the RFC facade.
INTERFACE zif_accx_args PUBLIC.

  METHODS has
    IMPORTING !name         TYPE string
    RETURNING VALUE(result) TYPE abap_bool.

  METHODS get_string
    IMPORTING !name         TYPE string
              !default      TYPE string OPTIONAL
    RETURNING VALUE(result) TYPE string.

  METHODS get_integer
    IMPORTING !name         TYPE string
              !default      TYPE i OPTIONAL
    RETURNING VALUE(result) TYPE i.

  METHODS get_boolean
    IMPORTING !name         TYPE string
              !default      TYPE abap_bool OPTIONAL
    RETURNING VALUE(result) TYPE abap_bool.

  METHODS get_strings
    IMPORTING !name         TYPE string
    RETURNING VALUE(result) TYPE string_table.

  "! Names of all supplied arguments
  METHODS get_names
    RETURNING VALUE(result) TYPE string_table.

ENDINTERFACE.
