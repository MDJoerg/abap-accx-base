"! <p class="shorttext synchronized">Access Explorer: request context</p>
CLASS zcl_accx_context DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_context.

    CONSTANTS co_write_not_enabled TYPE string VALUE `Write tools are not enabled for this server profile.`.

    "! @parameter authorizer    | Optional; defaults to ZCL_ACCX_AUTHORIZER (no restriction)
    "! @parameter write_problem | Empty = write tools allowed; default: not allowed
    METHODS constructor
      IMPORTING !profile           TYPE string
                !max_rows          TYPE i
                !guard             TYPE REF TO zif_accx_caller_guard
                !privacy           TYPE REF TO zif_accx_privacy
                !authorizer        TYPE REF TO zif_accx_authorizer OPTIONAL
                !caller            TYPE syuname DEFAULT sy-uname
                !language          TYPE sylangu DEFAULT sy-langu
                !system_id         TYPE string OPTIONAL
                !client_can_elicit TYPE abap_bool DEFAULT abap_false
                !write_problem     TYPE string DEFAULT co_write_not_enabled.

  PRIVATE SECTION.
    DATA profile           TYPE string.
    DATA max_rows          TYPE i.
    DATA guard             TYPE REF TO zif_accx_caller_guard.
    DATA privacy           TYPE REF TO zif_accx_privacy.
    DATA authorizer        TYPE REF TO zif_accx_authorizer.
    DATA caller            TYPE syuname.
    DATA language          TYPE sylangu.
    DATA system_id         TYPE string.
    DATA client_can_elicit TYPE abap_bool.
    DATA write_problem     TYPE string.

ENDCLASS.

CLASS zcl_accx_context IMPLEMENTATION.

  METHOD constructor.
    me->profile           = profile.
    me->max_rows          = max_rows.
    me->guard             = guard.
    me->privacy           = privacy.
    me->authorizer        = COND #( WHEN authorizer IS BOUND THEN authorizer ELSE NEW zcl_accx_authorizer( ) ).
    me->caller            = caller.
    me->language          = language.
    me->system_id         = COND #( WHEN system_id IS INITIAL THEN CONV string( sy-sysid ) ELSE system_id ).
    me->client_can_elicit = client_can_elicit.
    me->write_problem     = write_problem.
  ENDMETHOD.

  METHOD zif_accx_context~caller.
    result = caller.
  ENDMETHOD.

  METHOD zif_accx_context~language.
    result = language.
  ENDMETHOD.

  METHOD zif_accx_context~max_rows.
    result = max_rows.
  ENDMETHOD.

  METHOD zif_accx_context~profile.
    result = profile.
  ENDMETHOD.

  METHOD zif_accx_context~system_id.
    result = system_id.
  ENDMETHOD.

  METHOD zif_accx_context~guard.
    result = guard.
  ENDMETHOD.

  METHOD zif_accx_context~privacy.
    result = privacy.
  ENDMETHOD.

  METHOD zif_accx_context~authorizer.
    result = authorizer.
  ENDMETHOD.

  METHOD zif_accx_context~client_can_elicit.
    result = client_can_elicit.
  ENDMETHOD.

  METHOD zif_accx_context~write_problem.
    result = write_problem.
  ENDMETHOD.

ENDCLASS.
