"! <p class="shorttext synchronized">Access Explorer: server texts for clients</p>
"! Description and instructions every transport adapter announces to clients
"! (initialize), kept in the core so that all adapters say the same.
CLASS zcl_accx_server_info DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CONSTANTS co_name  TYPE string VALUE `accx`.
    CONSTANTS co_title TYPE string VALUE `Access Explorer`.

    CLASS-METHODS description
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS instructions
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_server_info IMPLEMENTATION.

  METHOD description.
    result = |Analysis of SAP users, roles and authorizations in system { sy-sysid }, client { sy-mandt }.|.
  ENDMETHOD.

  METHOD instructions.
    result = |Access Explorer (release { zif_accx_types=>co_release }) answers questions about SAP users, roles and | &&
             |authorizations in system { sy-sysid }, client { sy-mandt }. Results only contain data the calling user may | &&
             |display; hidden entries are counted, never silently dropped. Typical flow: get_user_profile for an overview | &&
             |of a user, then check_user_access to test whether the user may start a transaction or holds an | &&
             |authorization. Name the missing authorization object and field values precisely. Simulated failed checks | &&
             |also appear in the SU53 of the calling user. All tools are read-only except write tools (group ADMIN), | &&
             |which only appear in profiles that allow writing: they first return a plan; show it to the user and execute | &&
             |it (plan_id with confirm = true) only after the user explicitly approved exactly this plan - never on your | &&
             |own. The resources accx://tool-guide, accx://glossary and accx://faq explain which tool answers which | &&
             |question and the terms used. Answer in the language of the question.|.
  ENDMETHOD.

ENDCLASS.

