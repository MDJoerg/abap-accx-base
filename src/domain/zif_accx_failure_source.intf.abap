"! <p class="shorttext synchronized">Access Explorer: failed authorization checks</p>
"! Source of authorization checks that actually failed for a user (SU53 buffer,
"! user trace STUSERTRACE). Entries written by ACCX simulations (AUTHORITY-CHECK
"! FOR USER executed by the user as caller) are flagged so tools can drop them.
INTERFACE zif_accx_failure_source PUBLIC.

  CONSTANTS: BEGIN OF co_source,
               su53  TYPE string VALUE `su53`,
               trace TYPE string VALUE `trace`,
             END OF co_source.

  CONSTANTS: BEGIN OF co_trace_mode,
               inactive TYPE char1 VALUE ' ',
               active   TYPE char1 VALUE 'X',
               filtered TYPE char1 VALUE 'F',
             END OF co_trace_mode.

  TYPES: BEGIN OF ty_failure,
           "! SU53: time of the check; trace: time the check was first recorded
           timestamp     TYPE timestampl,
           instance      TYPE msname2,
           object        TYPE xuobject,
           fields        TYPE zif_accx_auth_evaluator=>ty_field_values,
           return_code   TYPE i,
           transaction   TYPE tcode,
           program       TYPE programm,
           line          TYPE i,
           "! Application context (e.g. OData service, Fiori app) if the kernel recorded one
           application   TYPE string,
           "! Check was executed FOR USER on behalf of this user
           for_user      TYPE syuname,
           "! Entry stems from an ACCX simulation, not from real work of the user
           is_simulation TYPE abap_bool,
           "! co_source-su53 or co_source-trace
           source        TYPE string,
         END OF ty_failure,
         ty_failures TYPE STANDARD TABLE OF ty_failure WITH EMPTY KEY.

  TYPES: BEGIN OF ty_read_result,
           failures TYPE ty_failures,
           "! Application servers that could not be read
           errors   TYPE string_table,
         END OF ty_read_result.

  TYPES: BEGIN OF ty_trace_status,
           "! co_trace_mode: profile parameter auth/auth_user_trace on this application server
           mode        TYPE char1,
           "! The user passes the user filter of STUSERTRACE (always true without filter)
           covers_user TYPE abap_bool,
         END OF ty_trace_status.

  "! Failed checks from the SU53 buffers of all application servers.
  "! SAP checks the caller itself: own user free, other users S_USER_GRP 03.
  METHODS read_su53
    IMPORTING !user         TYPE syuname
              !from         TYPE timestampl
              !to           TYPE timestampl OPTIONAL
    RETURNING VALUE(result) TYPE ty_read_result
    RAISING   zcx_accx_error.

  "! Failed checks from the user trace (STUSERTRACE, table SUAUTHVALTRC). The trace
  "! records every distinct check once, with the time of its first occurrence.
  "! SAP checks the caller: S_ADMI_FCD STUR; the user group is not checked.
  METHODS read_trace
    IMPORTING !user         TYPE syuname
              !from         TYPE timestampl
              !to           TYPE timestampl OPTIONAL
    RETURNING VALUE(result) TYPE ty_read_result
    RAISING   zcx_accx_error.

  "! Whether the user trace is switched on and records this user.
  METHODS trace_status
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE ty_trace_status.

ENDINTERFACE.
