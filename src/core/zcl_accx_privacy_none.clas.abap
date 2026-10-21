"! <p class="shorttext synchronized">Access Explorer: privacy mode NONE</p>
"! Pass-through strategy: results are returned unchanged.
CLASS zcl_accx_privacy_none DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_privacy.

ENDCLASS.

CLASS zcl_accx_privacy_none IMPLEMENTATION.

  METHOD zif_accx_privacy~protect_result ##NEEDED.
  ENDMETHOD.

  METHOD zif_accx_privacy~resolve_args.
    result = args.
  ENDMETHOD.

ENDCLASS.
