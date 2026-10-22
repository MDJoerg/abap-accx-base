"! <p class="shorttext synchronized">Access Explorer resource: accx://tool-guide</p>
"! Fixed text, no system data. Questions whose tools are not all available on the
"! server are left out.
CLASS zcl_accx_r_tool_guide DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_resource.

ENDCLASS.

CLASS zcl_accx_r_tool_guide IMPLEMENTATION.

  METHOD zif_accx_resource~get_descriptor.
    result = VALUE #( uri         = `accx://tool-guide`
                      name        = `tool-guide`
                      title       = `Which Access Explorer tool for which question`
                      description = `Maps typical questions to the tools available on this server and lists the rules that apply to all tools.`
                      mime_type   = `text/markdown` ).
  ENDMETHOD.

  METHOD zif_accx_resource~read.
    TYPES: BEGIN OF ty_row,
             question TYPE string,
             tools    TYPE string_table,
           END OF ty_row.
    DATA rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    rows = VALUE #(
        ( question = `A user cannot start a transaction or lacks an authorization (start with the failed checks, then simulate, then look for roles)`
          tools    = VALUE #( ( `get_failed_authorization_checks` ) ( `check_user_access` ) ( `explain_missing_access` ) ) )
        ( question = `Overview of one user: lock, validity, last logon, roles, profiles`
          tools    = VALUE #( ( `get_user_profile` ) ) )
        ( question = `Which authorization values does a user hold for an object, and from which role`
          tools    = VALUE #( ( `get_user_authorizations` ) ) )
        ( question = `Who may start a transaction or holds an authorization`
          tools    = VALUE #( ( `find_users` ) ) )
        ( question = `Which roles grant a transaction or authorization values`
          tools    = VALUE #( ( `find_roles` ) ) )
        ( question = `A Fiori app is missing or does not start for a user`
          tools    = VALUE #( ( `diagnose_fiori_app_access` ) ) )
        ( question = `What does a Fiori app need, independent of a user`
          tools    = VALUE #( ( `find_fiori_app` ) ) )
        ( question = `What does a user see in the launchpad, and through which role`
          tools    = VALUE #( ( `get_user_launchpad` ) ) )
        ( question = `Details of a launchpad catalog: tiles, target mappings, roles, lost references`
          tools    = VALUE #( ( `get_catalog_details` ) ) )
        ( question = `An OData service answers with 403 or is not reachable`
          tools    = VALUE #( ( `get_service_access` ) ) )
        ( question = `Understand one role: type, menu, users, composite and derived relations`
          tools    = VALUE #( ( `get_role_details` ) ) )
        ( question = `Authorization data of a role as PFCG expert mode shows it`
          tools    = VALUE #( ( `get_role_authorizations` ) ) )
        ( question = `How two roles differ`
          tools    = VALUE #( ( `compare_roles` ) ) )
        ( question = `Quality of many roles at once (cleanup, before audits)`
          tools    = VALUE #( ( `check_role_health` ) ) )
        ( question = `Give a user the access of a colleague, or find outliers within a user group`
          tools    = VALUE #( ( `compare_users` ) ( `analyze_user_group` ) ) )
        ( question = `Quarterly access review: hygiene, critical authorizations, changes`
          tools    = VALUE #( ( `get_user_hygiene_report` ) ( `run_critical_access_check` ) ( `get_authorization_changes` ) ) )
        ( question = `Who or what holds critical authorizations or combinations`
          tools    = VALUE #( ( `run_critical_access_check` ) ) )
        ( question = `Is a CDS entity protected, and who sees which rows`
          tools    = VALUE #( ( `get_cds_access_control` ) ( `find_unprotected_cds_exposures` ) ( `simulate_cds_access` ) ) )
        ( question = `Plan a change of a role without changing anything`
          tools    = VALUE #( ( `draft_role_change` ) ) )
        ( question = `Carry out an approved change (administrator server only)`
          tools    = VALUE #( ( `apply_role_change` ) ( `assign_role` ) ) )
        ).

    DATA(lines) = VALUE string_table(
        ( |# Access Explorer: which tool for which question| )
        ( `` )
        ( |Only tools available on this server are listed.| )
        ( `` )
        ).
    LOOP AT rows INTO DATA(row).
      DATA(complete) = abap_true.
      DATA(tool_list) = ``.
      LOOP AT row-tools INTO DATA(tool).
        IF NOT line_exists( visible_tools[ table_line = tool ] ).
          complete = abap_false.
          EXIT.
        ENDIF.
        tool_list = COND #( WHEN tool_list IS INITIAL THEN |`{ tool }`| ELSE |{ tool_list }, `{ tool }`| ).
      ENDLOOP.
      IF complete = abap_true.
        APPEND |- { row-question }: { tool_list }| TO lines.
      ENDIF.
    ENDLOOP.
    APPEND `` TO lines.
    APPEND |## Rules for all tools| TO lines.
    APPEND |- Use identifiers exactly as the tools return them, also when they are pseudonyms such as U-1A2B3C4D.| TO lines.
    APPEND |- Follow the "Next steps" at the end of a result: they contain the arguments of the sensible follow-up call.| TO lines.
    APPEND |- A result only contains what the calling user may display. Hidden entries are counted; quote the counts and say that the result is incomplete.| TO lines.
    APPEND |- Lists are limited by max_rows. If a list is truncated, say so and narrow the question instead of raising the limit blindly.| TO lines.
    APPEND |- Do not guess authorization values. Use the ones from get_failed_authorization_checks or from the tool results.| TO lines.
    APPEND |- Write tools return a plan first. Show it, and run it with plan_id and confirm set to true only after the user approved exactly this plan.| TO lines.
    result = concat_lines_of( table = lines sep = |\n| ).
  ENDMETHOD.

ENDCLASS.

