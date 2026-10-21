"! <p class="shorttext synchronized">Access Explorer: authorization value matching</p>
"! Shared rules for comparing authorization values (single value, pattern
"! with *, range). Organizational level placeholders ($...) never match.
CLASS zcl_accx_auth_value DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    "! Does an authorization value (single, pattern or range) cover the checked value?
    CLASS-METHODS covers
      IMPORTING !value        TYPE csequence
                !low          TYPE csequence
                !high         TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_auth_value IMPLEMENTATION.

  METHOD covers.
    IF high IS NOT INITIAL.
      result = xsdbool( value >= low AND value <= high ).
    ELSEIF low = '*'.
      result = abap_true.
    ELSEIF low CA '*'.
      result = xsdbool( value CP low ).
    ELSE.
      result = xsdbool( value = low ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
