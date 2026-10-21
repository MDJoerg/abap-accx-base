"! <p class="shorttext synchronized">Access Explorer: tool/runtime error</p>
"! Raised by tools and domain services. The runtime converts it into a neutral
"! result with the given status and an LLM-readable message.
CLASS zcx_accx_error DEFINITION PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Result status the runtime should report (see zif_accx_types=>co_status)
    DATA status  TYPE string READ-ONLY.
    "! LLM-readable message
    DATA message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING !textid   LIKE textid OPTIONAL
                !previous LIKE previous OPTIONAL
                !status   TYPE string DEFAULT `error`
                !message  TYPE string OPTIONAL.

    METHODS get_text REDEFINITION.
ENDCLASS.

CLASS zcx_accx_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( textid = textid previous = previous ).
    me->status  = status.
    me->message = message.
  ENDMETHOD.

  METHOD get_text.
    IF message IS NOT INITIAL.
      result = message.
    ELSE.
      result = super->get_text( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
