"! <p class="shorttext synchronized">Access Explorer: tool call audit logger</p>
INTERFACE zif_accx_logger PUBLIC.

  TYPES: BEGIN OF ty_entry,
           caller       TYPE syuname,
           profile      TYPE string,
           system_id    TYPE string,
           tool_name    TYPE string,
           status       TYPE string,
           row_count    TYPE i,
           hidden_count TYPE i,
           duration_ms  TYPE i,
           "! SHA-256 of the arguments - clear values are not logged
           args_hash    TYPE string,
           message      TYPE string,
         END OF ty_entry.

  METHODS log
    IMPORTING !entry TYPE ty_entry.

ENDINTERFACE.
