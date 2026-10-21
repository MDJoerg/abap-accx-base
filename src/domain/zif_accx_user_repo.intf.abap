"! <p class="shorttext synchronized">Access Explorer: user master data reader</p>
"! Reads without authorization checks - callers must filter with the caller guard.
INTERFACE zif_accx_user_repo PUBLIC.

  TYPES: BEGIN OF ty_user,
           user           TYPE syuname,
           full_name      TYPE string,
           user_type      TYPE string,
           user_type_code TYPE c LENGTH 1,
           user_group     TYPE string,
           valid_from     TYPE d,
           valid_to       TYPE d,
           locked         TYPE abap_bool,
           lock_reasons   TYPE string,
           last_logon     TYPE string,
           password_state TYPE string,
         END OF ty_user.

  TYPES: BEGIN OF ty_role_assignment,
           role          TYPE agr_name,
           description   TYPE string,
           valid_from    TYPE d,
           valid_to      TYPE d,
           active        TYPE abap_bool,
           via_composite TYPE abap_bool,
         END OF ty_role_assignment,
         ty_role_assignments TYPE STANDARD TABLE OF ty_role_assignment WITH EMPTY KEY.

  TYPES: BEGIN OF ty_profile_assignment,
           profile     TYPE xuprofile,
           description TYPE string,
         END OF ty_profile_assignment,
         ty_profile_assignments TYPE STANDARD TABLE OF ty_profile_assignment WITH EMPTY KEY.

  TYPES: BEGIN OF ty_member,
           user             TYPE syuname,
           user_type_code   TYPE c LENGTH 1,
           user_group       TYPE xuclass,
           valid_from       TYPE d,
           valid_to         TYPE d,
           locked           TYPE abap_bool,
           "! date of the last logon; initial = never logged on
           last_logon       TYPE d,
           "! password set by an administrator and not yet changed by the user
           initial_password TYPE abap_bool,
         END OF ty_member,
         ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

  TYPES: BEGIN OF ty_group_assignment,
           user TYPE syuname,
           role TYPE agr_name,
         END OF ty_group_assignment,
         ty_group_assignments TYPE STANDARD TABLE OF ty_group_assignment WITH EMPTY KEY.

  TYPES: BEGIN OF ty_group_profile,
           user    TYPE syuname,
           profile TYPE xuprofile,
         END OF ty_group_profile,
         ty_group_profiles TYPE STANDARD TABLE OF ty_group_profile WITH EMPTY KEY.

  TYPES ty_user_group_range TYPE RANGE OF xuclass.

  TYPES: BEGIN OF ty_role_count,
           user  TYPE syuname,
           roles TYPE i,
         END OF ty_role_count,
         ty_role_counts TYPE SORTED TABLE OF ty_role_count WITH UNIQUE KEY user.

  METHODS exists
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE abap_bool.

  METHODS get_user
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE ty_user.

  "! Role assignments (AGR_USERS) incl. expired ones, flagged via ACTIVE
  METHODS get_role_assignments
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE ty_role_assignments.

  "! Profile assignments (UST04) - effective after user comparison
  METHODS get_profile_assignments
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE ty_profile_assignments.

  "! Users of the user group (USR02-CLASS), by name
  METHODS get_group_members DEFAULT IGNORE
    IMPORTING !user_group   TYPE xuclass
    RETURNING VALUE(result) TYPE ty_members.

  "! Role assignments valid today of the users of the user group (directly or through a composite
  "! role), one row per user and role
  METHODS get_group_assignments DEFAULT IGNORE
    IMPORTING !user_group   TYPE xuclass
    RETURNING VALUE(result) TYPE ty_group_assignments.

  "! Profiles in the user master (UST04) of the users of the user group that were not generated
  "! for a role, i.e. assigned directly (e.g. SAP_ALL)
  METHODS get_group_direct_profiles DEFAULT IGNORE
    IMPORTING !user_group   TYPE xuclass
    RETURNING VALUE(result) TYPE ty_group_profiles.

  "! Users of the given user groups (empty range: all users), by name
  METHODS get_users DEFAULT IGNORE
    IMPORTING !user_groups  TYPE ty_user_group_range
    RETURNING VALUE(result) TYPE ty_members.

  "! Number of distinct roles assigned today (directly or through a composite role) per user of the
  "! given user groups; users without roles are left out
  METHODS get_role_counts DEFAULT IGNORE
    IMPORTING !user_groups  TYPE ty_user_group_range
    RETURNING VALUE(result) TYPE ty_role_counts.

  "! Profiles assigned directly (not generated for a role) to users of the given user groups
  METHODS get_direct_profiles DEFAULT IGNORE
    IMPORTING !user_groups  TYPE ty_user_group_range
    RETURNING VALUE(result) TYPE ty_group_profiles.

  "! Value of a profile parameter of this application server, e.g. login/no_automatic_user_sapstar
  METHODS get_profile_parameter DEFAULT IGNORE
    IMPORTING !name         TYPE string
    RETURNING VALUE(result) TYPE string.

ENDINTERFACE.
