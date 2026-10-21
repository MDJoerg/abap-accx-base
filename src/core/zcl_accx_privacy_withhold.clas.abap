"! <p class="shorttext synchronized">Access Explorer: fail-closed privacy fallback</p>
"! Used when a profile requests a privacy mode or class that cannot be
"! provided: result data is withheld instead of being returned unprotected.
CLASS zcl_accx_privacy_withhold DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_privacy.

    METHODS constructor
      IMPORTING !reason TYPE string.

  PRIVATE SECTION.
    DATA reason TYPE string.

ENDCLASS.

CLASS zcl_accx_privacy_withhold IMPLEMENTATION.

  METHOD constructor.
    me->reason = reason.
  ENDMETHOD.

  METHOD zif_accx_privacy~protect_result.
    CLEAR: result-data, result-data_json, result-summary.
    result-status = zif_accx_types=>co_status-error.
    APPEND |Result data withheld by privacy policy: { reason }| TO result-warnings.
  ENDMETHOD.

  METHOD zif_accx_privacy~resolve_args.
    result = args.
  ENDMETHOD.

ENDCLASS.
