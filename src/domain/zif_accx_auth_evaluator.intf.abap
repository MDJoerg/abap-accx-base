"! <p class="shorttext synchronized">Access Explorer: authorization check evaluation</p>
"! Resolves which checks a target requires and simulates them for a user.
"! Side effect of simulate: failed checks are written to the SU53 buffer of
"! the CALLING user (kernel behaviour of AUTHORITY-CHECK ... FOR USER).
"! FOR USER does not consider lock or validity of the user.
INTERFACE zif_accx_auth_evaluator PUBLIC.

  TYPES: BEGIN OF ty_field_value,
           field TYPE xufield,
           value TYPE string,
         END OF ty_field_value,
         ty_field_values TYPE STANDARD TABLE OF ty_field_value WITH EMPTY KEY.

  TYPES: BEGIN OF ty_check,
           object TYPE xuobject,
           fields TYPE ty_field_values,
           "! Why the check is required, e.g. 'Transaction start (S_TCODE)'
           reason TYPE string,
         END OF ty_check,
         ty_checks TYPE STANDARD TABLE OF ty_check WITH EMPTY KEY.

  TYPES: BEGIN OF ty_check_result,
           object      TYPE xuobject,
           condition   TYPE string,
           reason      TYPE string,
           granted     TYPE abap_bool,
           return_code TYPE i,
           outcome     TYPE string,
           "! Checked field values (same as the input check)
           fields      TYPE ty_field_values,
         END OF ty_check_result,
         ty_check_results TYPE STANDARD TABLE OF ty_check_result WITH EMPTY KEY.

  METHODS transaction_exists
    IMPORTING !tcode        TYPE tcode
    RETURNING VALUE(result) TYPE abap_bool.

  METHODS object_exists
    IMPORTING !object       TYPE xuobject
    RETURNING VALUE(result) TYPE abap_bool.

  "! Start checks of a transaction: S_TCODE plus the SE93 check object (TSTCA)
  METHODS get_transaction_checks
    IMPORTING !tcode        TYPE tcode
    RETURNING VALUE(result) TYPE ty_checks.

  "! Simulate one check for another user (max. 10 fields)
  METHODS simulate
    IMPORTING !user         TYPE syuname
              !check        TYPE ty_check
    RETURNING VALUE(result) TYPE ty_check_result.

ENDINTERFACE.
