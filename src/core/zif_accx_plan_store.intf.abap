"! <p class="shorttext synchronized">Access Explorer: plans of write tools</p>
"! Plan and execution of a write tool are separate calls (decision E10). The
"! first call stores what would be changed; the second call executes it only
"! with the plan id, for the same caller and tool, before the plan expires and
"! only once. The fingerprint describes the target state at planning time;
"! the tool compares it before executing.
INTERFACE zif_accx_plan_store PUBLIC.

  CONSTANTS: BEGIN OF co_state,
               open      TYPE string VALUE `OPEN`,
               running   TYPE string VALUE `RUNNING`,
               executed  TYPE string VALUE `EXECUTED`,
               partial   TYPE string VALUE `PARTIAL`,
               failed    TYPE string VALUE `FAILED`,
               cancelled TYPE string VALUE `CANCELLED`,
             END OF co_state.

  "! minutes a plan stays executable
  CONSTANTS co_default_ttl TYPE i VALUE 15.
  "! minutes after expiry a RUNNING plan counts as hanging
  CONSTANTS co_default_hang_minutes TYPE i VALUE 60.
  "! days closed plans are kept
  CONSTANTS co_default_keep_days TYPE i VALUE 90.

  TYPES: BEGIN OF ty_plan,
           plan_id     TYPE string,
           tool_name   TYPE string,
           caller      TYPE syuname,
           profile     TYPE string,
           "! changed object, e.g. a role
           target      TYPE string,
           state       TYPE string,
           created_at  TYPE timestampl,
           expires_at  TYPE timestampl,
           fingerprint TYPE string,
           "! tool-specific plan (JSON)
           payload     TYPE string,
           summary     TYPE string,
           outcome     TYPE string,
         END OF ty_plan.

  TYPES: BEGIN OF ty_cleaned,
           plan_id   TYPE string,
           tool_name TYPE string,
           caller    TYPE syuname,
           target    TYPE string,
           "! state before the cleanup
           state     TYPE string,
           "! expired (OPEN -> CANCELLED), hanging (RUNNING -> FAILED) or deleted
           action    TYPE string,
         END OF ty_cleaned,
         ty_cleaned_list TYPE STANDARD TABLE OF ty_cleaned WITH EMPTY KEY.

  CONSTANTS: BEGIN OF co_cleanup,
               expired TYPE string VALUE `expired`,
               hanging TYPE string VALUE `hanging`,
               deleted TYPE string VALUE `deleted`,
             END OF co_cleanup.

  "! Stores an open plan for the caller and returns it with id and expiry
  METHODS create
    IMPORTING !plan         TYPE ty_plan
              !ttl_minutes  TYPE i DEFAULT co_default_ttl
    RETURNING VALUE(result) TYPE ty_plan.

  "! Plan by id; initial if it does not exist
  METHODS get
    IMPORTING !plan_id      TYPE string
    RETURNING VALUE(result) TYPE ty_plan.

  "! Takes an open plan for execution (state RUNNING, only once)
  "! @raising zcx_accx_error | unknown, foreign, other tool, expired or no longer open
  METHODS claim
    IMPORTING !plan_id      TYPE string
              !tool_name    TYPE string
              !caller       TYPE syuname
    RETURNING VALUE(result) TYPE ty_plan
    RAISING   zcx_accx_error.

  "! Final state with the outcome of the execution (EXECUTED, PARTIAL, FAILED, CANCELLED)
  METHODS close
    IMPORTING !plan_id TYPE string
              !state   TYPE string
              !outcome TYPE string OPTIONAL.

  "! Housekeeping: cancels expired OPEN plans, fails RUNNING plans that are
  "! hanging (still running hang_minutes after expiry - the change may be
  "! incomplete) and deletes closed plans older than keep_days (0 = keep all)
  "! @parameter test_only | only list what would be changed
  METHODS cleanup DEFAULT IGNORE
    IMPORTING !hang_minutes TYPE i DEFAULT co_default_hang_minutes
              !keep_days    TYPE i DEFAULT co_default_keep_days
              !test_only    TYPE abap_bool DEFAULT abap_false
    RETURNING VALUE(result) TYPE ty_cleaned_list.

ENDINTERFACE.
