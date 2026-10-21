"! <p class="shorttext synchronized">Access Explorer: default authorizer (redefine)</p>
"! Default: no additional usage restriction. Access is still limited by ICF
"! logon/S_ICF on the endpoint and by the caller guard on data level.
"! Customer extension: inherit, redefine check_endpoint and/or check_tool
"! with an AUTHORITY-CHECK on the customer's own authorization object, and
"! register the subclass in ZACCX_PROFILE-AUTHORIZER_CLASS.
CLASS zcl_accx_authorizer DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_authorizer.

ENDCLASS.

CLASS zcl_accx_authorizer IMPLEMENTATION.

  METHOD zif_accx_authorizer~check_endpoint.
    result = abap_true.
  ENDMETHOD.

  METHOD zif_accx_authorizer~check_tool.
    result = abap_true.
  ENDMETHOD.

ENDCLASS.
