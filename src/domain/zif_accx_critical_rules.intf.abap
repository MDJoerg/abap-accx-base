"! <p class="shorttext synchronized">Access Explorer: critical authorization rules</p>
"! Classifies authorization values as critical. The default implementation
"! uses the critical authorizations maintained in SUIM (USCRAUTHID, USCRAUTH)
"! with the same AND/OR semantics as report RSUSR008_009_NEW.
INTERFACE zif_accx_critical_rules PUBLIC.

  CONSTANTS: BEGIN OF co_level,
               high   TYPE string VALUE `high`,
               medium TYPE string VALUE `medium`,
               low    TYPE string VALUE `low`,
             END OF co_level.

  " One authorization value; rows with the same object and auth form one authorization
  TYPES: BEGIN OF ty_auth_value,
           object TYPE xuobject,
           auth   TYPE xuauth,
           field  TYPE xufield,
           low    TYPE xuval,
           high   TYPE xuval,
         END OF ty_auth_value,
         ty_auth_values TYPE STANDARD TABLE OF ty_auth_value WITH EMPTY KEY.

  TYPES: BEGIN OF ty_hit,
           rule  TYPE auth_id,
           text  TYPE string,
           level TYPE string,
         END OF ty_hit,
         ty_hits TYPE STANDARD TABLE OF ty_hit WITH EMPTY KEY.

  TYPES ty_groups   TYPE STANDARD TABLE OF cr_auth WITH EMPTY KEY.
  TYPES ty_rule_ids TYPE STANDARD TABLE OF auth_id WITH EMPTY KEY.

  "! Critical rules met by the given authorization values
  METHODS evaluate
    IMPORTING !values       TYPE ty_auth_values
    RETURNING VALUE(result) TYPE ty_hits.

  "! Critical rules met by the active authorizations of a role
  METHODS evaluate_role
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE ty_hits.

  "! Critical combinations (USRCOMB) whose authorizations are all among the given hits
  "! (components with search type OR: one of them suffices)
  METHODS evaluate_combinations
    IMPORTING !hits         TYPE ty_hits
    RETURNING VALUE(result) TYPE ty_hits.

  "! Groups (CR_AUTH) of a rule; a rule is met when all groups are met
  METHODS rule_groups
    IMPORTING !rule         TYPE auth_id
    RETURNING VALUE(result) TYPE ty_groups.

  "! Groups of a rule met by the given authorization values
  METHODS met_groups
    IMPORTING !rule         TYPE auth_id
              !values       TYPE ty_auth_values
    RETURNING VALUE(result) TYPE ty_groups.

  "! Authorization objects used by any rule
  METHODS rule_objects
    RETURNING VALUE(result) TYPE string_table.

  "! Critical authorizations (rules) that make up a critical combination
  METHODS combination_rules
    IMPORTING !combination  TYPE comb_id
    RETURNING VALUE(result) TYPE ty_rule_ids.

ENDINTERFACE.
