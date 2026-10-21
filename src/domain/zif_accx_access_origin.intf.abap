"! <p class="shorttext synchronized">Access Explorer: origin of critical authorizations</p>
"! Names the roles and profiles through which a user holds a critical
"! authorization: every profile in the user master (UST04, including the
"! reference user's) is evaluated on its own; generated profiles are traced
"! back to their role and, where assigned through one, to the composite role.
INTERFACE zif_accx_access_origin PUBLIC.

  CONSTANTS: BEGIN OF co_source,
               role    TYPE string VALUE `role`,
               profile TYPE string VALUE `profile`,
             END OF co_source.

  TYPES: BEGIN OF ty_origin,
           "! critical authorization (for combinations: the component)
           rule        TYPE auth_id,
           source_type TYPE string,
           "! role, or profile not generated from a role
           source      TYPE string,
           profile     TYPE xuprofile,
           "! composite roles or reference user through which the source is assigned
           via         TYPE string,
           "! the source alone meets the rule; otherwise only together with other sources
           complete    TYPE abap_bool,
         END OF ty_origin,
         ty_origins TYPE STANDARD TABLE OF ty_origin WITH EMPTY KEY.

  TYPES: BEGIN OF ty_user_source,
           profile TYPE xuprofile,
           "! role the profile was generated for; empty for profiles assigned directly
           role    TYPE agr_name,
           "! composite roles or reference user through which the profile is assigned
           via     TYPE string,
         END OF ty_user_source,
         ty_user_sources TYPE STANDARD TABLE OF ty_user_source WITH EMPTY KEY.

  "! Profiles in the user master (UST04, also the reference user's), each with its role and the
  "! composite role or reference user it comes through
  METHODS get_user_sources DEFAULT IGNORE
    IMPORTING !user         TYPE xubname
    RETURNING VALUE(result) TYPE ty_user_sources.

  "! Active authorization values of a profile (composite profiles expanded) for the objects,
  "! or of every object when all_objects is set and no object is given
  METHODS get_profile_values DEFAULT IGNORE
    IMPORTING !profile      TYPE xuprofile
              !objects      TYPE string_table
              !all_objects  TYPE abap_bool DEFAULT abap_false
    RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

  "! Sources of a critical authorization held by a user
  METHODS trace_rule
    IMPORTING !user         TYPE xubname
              !rule         TYPE auth_id
    RETURNING VALUE(result) TYPE ty_origins.

  "! Sources of every critical authorization of a combination held by a user
  METHODS trace_combination
    IMPORTING !user         TYPE xubname
              !combination  TYPE comb_id
    RETURNING VALUE(result) TYPE ty_origins.

ENDINTERFACE.
