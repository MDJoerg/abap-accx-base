"! <p class="shorttext synchronized">Access Explorer: fail-closed authorizer</p>
"! Used when the configured authorizer class cannot be instantiated:
"! a broken customer check must never result in open access.
CLASS zcl_accx_authorizer_deny DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_authorizer.

ENDCLASS.

CLASS zcl_accx_authorizer_deny IMPLEMENTATION.

  METHOD zif_accx_authorizer~check_endpoint.
    result = abap_false.
  ENDMETHOD.

  METHOD zif_accx_authorizer~check_tool.
    result = abap_false.
  ENDMETHOD.

ENDCLASS.
