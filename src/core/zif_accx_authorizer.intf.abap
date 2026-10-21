"! <p class="shorttext synchronized">Access Explorer: usage authorization (extension point)</p>
"! Decides whether the calling user may use a server profile and its tools.
"! The product ships no authorization object of its own: customers implement
"! their check by inheriting from ZCL_ACCX_AUTHORIZER and registering the
"! subclass per profile in ZACCX_PROFILE-AUTHORIZER_CLASS.
"! Data-level checks (which users/roles may be displayed) are NOT done here,
"! see ZIF_ACCX_CALLER_GUARD.
INTERFACE zif_accx_authorizer PUBLIC.

  "! Endpoint level: may the caller use this server profile at all?
  "! Called once per request by the transport adapter.
  METHODS check_endpoint
    IMPORTING !profile      TYPE string
    RETURNING VALUE(result) TYPE abap_bool.

  "! Tool level: may the caller see and execute this tool?
  "! Used to filter the tool catalog and before every execution.
  METHODS check_tool
    IMPORTING !profile      TYPE string
              !tool         TYPE zif_accx_types=>ty_tool_descriptor
    RETURNING VALUE(result) TYPE abap_bool.

ENDINTERFACE.
