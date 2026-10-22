"! <p class="shorttext synchronized">Access Explorer tool: get_user_hygiene_report</p>
"! User hygiene across all users or several user groups: profiles assigned directly,
"! dialog users without logon for a long time or never, initial passwords, expired
"! users that still hold roles, and the state of the standard users (SAP*, DDIC,
"! SAPCPIC, EARLYWATCH, TMSADM).
CLASS zcl_accx_t_user_hygiene DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_user_hygiene_report`.

    CONSTANTS: BEGIN OF co_check,
                 direct_profile   TYPE string VALUE `direct_profile`,
                 inactive         TYPE string VALUE `inactive`,
                 never_logged_on  TYPE string VALUE `never_logged_on`,
                 initial_password TYPE string VALUE `initial_password`,
                 "! expired users that still hold roles or profiles
                 expired          TYPE string VALUE `expired`,
                 standard_users   TYPE string VALUE `standard_users`,
               END OF co_check.

    "! profile parameter that disables the built-in SAP* when the user master record is missing
    CONSTANTS co_sapstar_parameter TYPE string VALUE `login/no_automatic_user_sapstar`.

    TYPES: BEGIN OF ty_count,
             code  TYPE string,
             users TYPE i,
           END OF ty_count,
           ty_counts TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.

    TYPES: BEGIN OF ty_group,
             user_group    TYPE string,
             users         TYPE i,
             with_findings TYPE i,
           END OF ty_group,
           ty_groups TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.

    TYPES: BEGIN OF ty_user,
             user          TYPE string,
             user_group    TYPE string,
             user_type     TYPE string,
             "! last logon date, empty if never; the findings repeat it, so privacy mode MINIMIZE needs it as a field
             last_logon    TYPE d,
             "! position of the worst finding in the severity order (1 = most severe)
             severity      TYPE i,
             findings      TYPE string_table,
             finding_codes TYPE string_table,
           END OF ty_user,
           ty_users TYPE STANDARD TABLE OF ty_user WITH EMPTY KEY.

    TYPES: BEGIN OF ty_standard_user,
             user       TYPE string,
             exists     TYPE abap_bool,
             user_type  TYPE string,
             user_group TYPE string,
             locked     TYPE abap_bool,
             last_logon TYPE string,
             profiles   TYPE string_table,
             findings   TYPE string_table,
           END OF ty_standard_user,
           ty_standard_users TYPE STANDARD TABLE OF ty_standard_user WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             "! all users, or the user groups given
             scope             TYPE string,
             checks            TYPE string_table,
             inactive_days     TYPE i,
             "! users the caller may display
             users_checked     TYPE i,
             "! users with findings per check, in severity order
             counts            TYPE ty_counts,
             with_findings     TYPE i,
             "! user groups with findings first
             user_groups       TYPE ty_groups,
             "! users with findings, most severe first
             users             TYPE ty_users,
             standard_users    TYPE ty_standard_users,
             "! value of login/no_automatic_user_sapstar (standard_users check)
             sapstar_parameter TYPE string,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS all_checks
      RETURNING VALUE(result) TYPE string_table.

    METHODS check_standard_users
      IMPORTING !ctx     TYPE REF TO zif_accx_context
                !payload TYPE REF TO ty_payload
      CHANGING  !result  TYPE zif_accx_types=>ty_result.

ENDCLASS.

CLASS zcl_accx_t_user_hygiene IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `User hygiene report`
      description = |User hygiene across all users or the given user groups (quarterly access review): profiles | &&
                    |assigned directly (e.g. SAP_ALL), dialog users not locked without logon for inactive_days or never | &&
                    |logged on, initial passwords not changed, expired users that still hold roles, and the standard | &&
                    |users SAP*, DDIC, SAPCPIC, EARLYWATCH and TMSADM (exists, locked, user type, profiles, | &&
                    |{ co_sapstar_parameter }). Counts per check and per user group; analyze_user_group goes into one group.|
      group       = zif_accx_types=>co_group-audit
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-personal
      output_type = `\CLASS=ZCL_ACCX_T_USER_HYGIENE\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `checks`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |Checks to run (default all): { concat_lines_of( table = all_checks( ) sep = `, ` ) }.| ) )
                             ( param( name        = `user_group`
                                      description = `Limit to user groups, e.g. SUPER or Z* (default all users). The standard users are checked anyway.`
                                      maximum     = 12 ) )
                             ( param( name        = `inactive_days`
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = |Days without logon after which a dialog user counts as inactive (default { zcl_accx_user_hygiene=>co_inactive_days }).|
                                      minimum     = 1
                                      maximum     = 3650 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA groups TYPE zif_accx_user_repo=>ty_user_group_range.

    DATA(payload) = NEW ty_payload( inactive_days = args->get_integer( name    = `inactive_days`
                                                                       default = zcl_accx_user_hygiene=>co_inactive_days ) ).
    IF payload->inactive_days < 1.
      payload->inactive_days = zcl_accx_user_hygiene=>co_inactive_days.
    ENDIF.
    DATA(known) = all_checks( ).
    LOOP AT args->get_strings( `checks` ) INTO DATA(check).
      check = to_lower( condense( check ) ).
      IF check IS INITIAL OR line_exists( payload->checks[ table_line = check ] ).
        CONTINUE.
      ENDIF.
      IF NOT line_exists( known[ table_line = check ] ).
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                            message = |Unknown check "{ check }" - use { concat_lines_of( table = all_checks( ) sep = `, ` ) }.| ).
      ENDIF.
      APPEND check TO payload->checks.
    ENDLOOP.
    IF payload->checks IS INITIAL.
      payload->checks = all_checks( ).
    ENDIF.
    DATA(group) = to_upper( condense( args->get_string( `user_group` ) ) ).
    IF group IS NOT INITIAL.
      groups = VALUE #( ( sign = 'I' option = COND #( WHEN group CA '*+' THEN 'CP' ELSE 'EQ' ) low = group ) ).
      payload->scope = |user groups { group }|.
    ELSE.
      payload->scope = `all users`.
    ENDIF.
    result-data = payload.

    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(members) = user_repo->get_users( groups ).
    IF members IS INITIAL AND group IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |No users in user groups { group }.| ).
    ENDIF.
    LOOP AT members INTO DATA(member).
      IF ctx->guard( )->can_display_group( member-user_group ) = abap_false.
        result-hidden_by_authorization += 1.
        DELETE members.
      ENDIF.
    ENDLOOP.
    IF members IS INITIAL AND group IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display the users of user groups { group } (S_USER_GRP, activity 03).| ).
    ENDIF.
    payload->users_checked = lines( members ).

    " checks per user
    DATA(role_counts) = user_repo->get_role_counts( groups ).
    DATA(profiles) = user_repo->get_direct_profiles( groups ).
    DATA(order) = zcl_accx_user_hygiene=>severity_order( ).
    LOOP AT members INTO member.
      READ TABLE payload->user_groups ASSIGNING FIELD-SYMBOL(<group>) WITH KEY user_group = CONV string( member-user_group ).
      IF sy-subrc <> 0.
        APPEND VALUE #( user_group = member-user_group ) TO payload->user_groups ASSIGNING <group>.
      ENDIF.
      <group>-users += 1.

      DATA(roles) = VALUE i( role_counts[ user = member-user ]-roles OPTIONAL ).
      DATA(direct) = VALUE string_table( FOR p IN profiles WHERE ( user = member-user ) ( CONV #( p-profile ) ) ).
      DATA(assessment) = zcl_accx_user_hygiene=>assess( member          = member
                                                        roles           = roles
                                                        direct_profiles = direct
                                                        inactive_days   = payload->inactive_days ).
      DATA(entry) = VALUE ty_user( user       = member-user
                                   user_group = member-user_group
                                   user_type  = zcl_accx_user_hygiene=>user_type_text( member-user_type_code )
                                   last_logon = member-last_logon ).
      LOOP AT assessment-finding_codes INTO DATA(code).
        DATA(text) = assessment-findings[ sy-tabix ].
        IF NOT line_exists( payload->checks[ table_line = code ] ).
          CONTINUE.
        ENDIF.
        IF code = zcl_accx_user_hygiene=>co_finding-expired.
          " an expired user cannot log on: only the authorizations it keeps matter
          IF roles = 0 AND direct IS INITIAL.
            CONTINUE.
          ENDIF.
          text = |{ text } Still holds { COND #( WHEN roles > 0 THEN |{ roles } roles| ) }| &&
                 |{ COND #( WHEN roles > 0 AND direct IS NOT INITIAL THEN ` and ` ) }| &&
                 |{ COND #( WHEN direct IS NOT INITIAL THEN |profiles { concat_lines_of( table = direct sep = `, ` ) }| ) }.|.
        ENDIF.
        APPEND code TO entry-finding_codes.
        APPEND text TO entry-findings.
      ENDLOOP.
      IF entry-finding_codes IS INITIAL.
        CONTINUE.
      ENDIF.
      LOOP AT order INTO code.
        IF line_exists( entry-finding_codes[ table_line = code ] ).
          entry-severity = sy-tabix.
          EXIT.
        ENDIF.
      ENDLOOP.
      APPEND entry TO payload->users.
      <group>-with_findings += 1.
    ENDLOOP.

    payload->with_findings = lines( payload->users ).
    LOOP AT order INTO code.
      DATA(count) = REDUCE i( INIT n = 0 FOR u IN payload->users
                              NEXT n = n + COND #( WHEN line_exists( u-finding_codes[ table_line = code ] ) THEN 1 ELSE 0 ) ).
      IF count > 0.
        APPEND VALUE #( code = code users = count ) TO payload->counts.
      ENDIF.
    ENDLOOP.
    SORT payload->users BY severity ASCENDING user ASCENDING.
    SORT payload->user_groups BY with_findings DESCENDING users DESCENDING user_group ASCENDING.

    IF line_exists( payload->checks[ table_line = co_check-standard_users ] ).
      check_standard_users( EXPORTING ctx = ctx payload = payload CHANGING result = result ).
    ENDIF.

    result-total_count = lines( payload->users ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->users ) > max.
      DELETE payload->users FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->user_groups ) > max.
      DELETE payload->user_groups FROM max + 1.
    ENDIF.

    result-sources = VALUE #( ( `USR02 (user type, user group, validity, lock, last logon, password state)` )
                              ( `AGR_USERS (roles assigned today)` )
                              ( `UST04, AGR_1016 (profiles assigned directly)` ) ).
    IF line_exists( payload->checks[ table_line = co_check-standard_users ] ).
      APPEND |Profile parameter { co_sapstar_parameter }| TO result-sources.
    ENDIF.
    IF line_exists( payload->counts[ code = co_check-direct_profile ] ).
      APPEND `Replace profiles assigned directly by roles; run_critical_access_check shows which critical authorizations they grant.`
             TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = co_check-inactive ] ) OR line_exists( payload->counts[ code = co_check-never_logged_on ] ).
      APPEND |Lock dialog users without logon (more than { payload->inactive_days } days or never) after checking with their | &&
             |managers, e.g. with SU10; the profile parameter login/password_max_idle_productive locks them automatically.| TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = co_check-initial_password ] ).
      APPEND `Initial passwords that are never used are a risk: lock the users or limit them with login/password_max_idle_initial.`
             TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = co_check-expired ] ).
      APPEND `Expired users still hold roles: remove the assignments or delete the users once the retention period is over.`
             TO result-next_steps.
    ENDIF.
    IF line_exists( payload->checks[ table_line = co_check-standard_users ] ).
      IF REDUCE i( INIT n = 0 FOR s IN payload->standard_users NEXT n = n + lines( s-findings ) ) > 0.
        APPEND `Secure the standard users with findings (lock, user type System, no SAP_ALL, user group SUPER).` TO result-next_steps.
      ENDIF.
      APPEND `This tool cannot see whether standard users still have their default passwords - check that with report RSUSR003.`
             TO result-next_steps.
    ENDIF.
    IF payload->user_groups IS NOT INITIAL AND payload->user_groups[ 1 ]-with_findings > 0.
      APPEND |analyze_user_group { payload->user_groups[ 1 ]-user_group } shows the group with the most findings in detail.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD check_standard_users.
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    payload->sapstar_parameter = user_repo->get_profile_parameter( co_sapstar_parameter ).
    LOOP AT VALUE string_table( ( `SAP*` ) ( `DDIC` ) ( `SAPCPIC` ) ( `EARLYWATCH` ) ( `TMSADM` ) ) INTO DATA(name).
      DATA(user) = CONV syuname( name ).
      DATA(entry) = VALUE ty_standard_user( user = name exists = user_repo->exists( user ) ).
      IF entry-exists = abap_false.
        IF name = `SAP*` AND payload->sapstar_parameter <> `1`.
          APPEND |Does not exist and { co_sapstar_parameter } is { COND #( WHEN payload->sapstar_parameter IS INITIAL THEN `not set`
                                                                            ELSE payload->sapstar_parameter ) }: | &&
                 |the built-in SAP* with its default password can log on. Create SAP* (locked) or set the parameter to 1.|
                 TO entry-findings.
        ENDIF.
        APPEND entry TO payload->standard_users.
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_user( user ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      DATA(master) = user_repo->get_user( user ).
      entry-user_type  = master-user_type.
      entry-user_group = master-user_group.
      entry-locked     = master-locked.
      entry-last_logon = master-last_logon.
      entry-profiles   = VALUE #( FOR p IN user_repo->get_profile_assignments( user ) ( CONV #( p-profile ) ) ).
      IF master-locked = abap_false AND name <> `TMSADM`.
        APPEND `Not locked.` TO entry-findings.
      ENDIF.
      IF master-user_type_code = 'A' AND name <> `SAP*`.
        APPEND `Dialog user - use type System (or Communication) so nobody can log on with it in the GUI.` TO entry-findings.
      ENDIF.
      IF name = `SAP*` AND entry-profiles IS NOT INITIAL.
        APPEND |Has profiles ({ concat_lines_of( table = entry-profiles sep = `, ` ) }) - SAP* should have none.| TO entry-findings.
      ELSEIF line_exists( entry-profiles[ table_line = `SAP_ALL` ] ) AND name <> `DDIC`.
        APPEND `Has SAP_ALL.` TO entry-findings.
      ENDIF.
      IF ( name = `SAP*` OR name = `DDIC` ) AND master-user_group <> `SUPER`.
        APPEND |User group { COND #( WHEN master-user_group IS INITIAL THEN `empty` ELSE master-user_group ) } - | &&
               |put it into SUPER so only administrators may change it.| TO entry-findings.
      ENDIF.
      IF name = `TMSADM` AND sy-mandt <> '000'.
        APPEND |Exists in client { sy-mandt } - TMSADM is needed in client 000 only.| TO entry-findings.
      ENDIF.
      APPEND entry TO payload->standard_users.
    ENDLOOP.
  ENDMETHOD.

  METHOD all_checks.
    result = VALUE #( ( co_check-direct_profile )
                      ( co_check-inactive )
                      ( co_check-never_logged_on )
                      ( co_check-initial_password )
                      ( co_check-expired )
                      ( co_check-standard_users ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |User hygiene for { <payload>-scope } ({ <payload>-users_checked } users checked): | &&
                     |{ COND #( WHEN <payload>-with_findings = 0 THEN `no findings`
                                ELSE |**{ <payload>-with_findings } users with findings**| ) }.|.
    LOOP AT <payload>-counts INTO DATA(count).
      result-summary = |{ result-summary }\n- { count-code }: { count-users } { COND #( WHEN count-users = 1 THEN `user` ELSE `users` ) }|.
    ENDLOOP.
    DATA(groups) = VALUE string_table( FOR g IN <payload>-user_groups WHERE ( with_findings > 0 )
                                       ( |{ COND #( WHEN g-user_group IS INITIAL THEN `(no group)` ELSE g-user_group ) } | &&
                                         |{ g-with_findings } of { g-users }| ) ).
    IF groups IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nUser groups with findings: { concat_lines_of( table = groups sep = `, ` ) }.|.
    ENDIF.
    IF <payload>-standard_users IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Standard users:**|.
      LOOP AT <payload>-standard_users INTO DATA(standard).
        DATA(state) = COND string( WHEN standard-exists = abap_false THEN `does not exist`
                                   ELSE |{ standard-user_type }, { COND #( WHEN standard-locked = abap_true THEN `locked` ELSE `not locked` ) }| &&
                                        |{ COND #( WHEN standard-last_logon IS NOT INITIAL THEN |, last logon { standard-last_logon }| ) }| ).
        result-summary = |{ result-summary }\n- { COND #( WHEN standard-findings IS INITIAL THEN standard-user ELSE |**{ standard-user }**| ) } | &&
                         |({ state }): { COND #( WHEN standard-findings IS INITIAL THEN `ok`
                                                 ELSE concat_lines_of( table = standard-findings sep = ` ` ) ) }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-users IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Users, most severe first:**|.
      LOOP AT <payload>-users INTO DATA(user).
        result-summary = |{ result-summary }\n- **{ user-user }** ({ user-user_type }{ COND #( WHEN user-user_group IS NOT INITIAL THEN |, { user-user_group }| ) }): | &&
                         |{ concat_lines_of( table = user-findings sep = ` ` ) }|.
      ENDLOOP.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList cut to max_rows ({ result-total_count } users with findings) - raise max_rows or limit user_group.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } users left out due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

