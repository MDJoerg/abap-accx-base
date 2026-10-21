"! <p class="shorttext synchronized">Access Explorer: per-request execution context</p>
INTERFACE zif_accx_context PUBLIC.

  "! Named user on whose behalf the request runs (the principal)
  METHODS caller
    RETURNING VALUE(result) TYPE syuname.

  METHODS language
    RETURNING VALUE(result) TYPE sylangu.

  "! Effective row limit (already clamped)
  METHODS max_rows
    RETURNING VALUE(result) TYPE i.

  "! Server profile, e.g. bc/access-support
  METHODS profile
    RETURNING VALUE(result) TYPE string.

  "! System id the request is executed on (federation-ready)
  METHODS system_id
    RETURNING VALUE(result) TYPE string.

  "! Data-level checks of the caller
  METHODS guard
    RETURNING VALUE(result) TYPE REF TO zif_accx_caller_guard.

  "! Privacy strategy configured for the profile
  METHODS privacy
    RETURNING VALUE(result) TYPE REF TO zif_accx_privacy.

  "! Usage authorization configured for the profile (customer extension point)
  METHODS authorizer
    RETURNING VALUE(result) TYPE REF TO zif_accx_authorizer.

  "! Transport adapter can ask the user to resolve ambiguities (elicitation)
  METHODS client_can_elicit
    RETURNING VALUE(result) TYPE abap_bool.

  "! Why write tools may not run (profile without ALLOW_WRITE, production client); empty = allowed
  METHODS write_problem
    RETURNING VALUE(result) TYPE string.

ENDINTERFACE.
