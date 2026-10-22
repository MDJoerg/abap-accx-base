"! <p class="shorttext synchronized">Access Explorer tool: analyze_user_group</p>
"! Overview of a user group: members by user type, hygiene findings per user
"! (profiles assigned directly, no logon for a long time, never logged on,
"! initial password, no roles, validity, locks), the most frequent roles and
"! outliers - roles only one member holds.
CLASS zcl_accx_t_analyze_user_group DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `analyze_user_group`.
    "! default number of days without logon after which a dialog user counts as inactive
    CONSTANTS co_inactive_days TYPE i VALUE zcl_accx_user_hygiene=>co_inactive_days.
    "! smallest number of members for which a role held by one member only is an outlier
    CONSTANTS co_outlier_members TYPE i VALUE 5.

    TYPES: BEGIN OF ty_count,
             code  TYPE string,
             users TYPE i,
           END OF ty_count,
           ty_counts TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.

    TYPES: BEGIN OF ty_member,
             user          TYPE string,
             user_type     TYPE string,
             "! last logon date, empty if never; the findings repeat it, so privacy mode MINIMIZE needs it as a field
             last_logon    TYPE d,
             "! position of the worst finding in the severity order (1 = most severe)
             severity      TYPE i,
             findings      TYPE string_table,
             finding_codes TYPE string_table,
           END OF ty_member,
           ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role,
             role  TYPE string,
             users TYPE i,
             "! share of the members in percent
             share TYPE i,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_outlier,
             role TYPE string,
             user TYPE string,
           END OF ty_outlier,
           ty_outliers TYPE STANDARD TABLE OF ty_outlier WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user_group    TYPE string,
             "! members the caller may display
             members       TYPE i,
             "! members per user type (Dialog, System, ...)
             user_types    TYPE ty_counts,
             inactive_days TYPE i,
             "! members per finding code, in severity order
             counts        TYPE ty_counts,
             with_findings TYPE i,
             "! members with findings, most severe first
             users         TYPE ty_members,
             "! distinct roles assigned today
             roles_total   TYPE i,
             "! most frequent roles
             top_roles     TYPE ty_roles,
             "! roles only one member holds (groups of at least co_outlier_members)
             outliers      TYPE ty_outliers,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    METHODS listed
      IMPORTING !names        TYPE string_table
                !max          TYPE i DEFAULT 15
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_analyze_user_group IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Analyze user group`
      description = |Overview of one user group (SU01 user group for authorization checks): members by user type; | &&
                    |hygiene findings per user - profiles assigned directly (e.g. SAP_ALL), dialog users without logon | &&
                    |for inactive_days or never logged on, initial passwords, users without roles, expired or not yet | &&
                    |valid users, locked users; the most frequent roles and outliers (a role only one member holds). | &&
                    |Use it for access reviews and to prepare a role concept; compare_users explains one member against | &&
                    |the group.|
      group       = zif_accx_types=>co_group-user
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-personal
      output_type = `\CLASS=ZCL_ACCX_T_ANALYZE_USER_GROUP\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user_group`
                                      description = `User group (case-insensitive), e.g. SUPER.`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `inactive_days`
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = |Days without logon after which a dialog user counts as inactive (default { co_inactive_days }).|
                                      minimum     = 1
                                      maximum     = 3650 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    TYPES: BEGIN OF ty_holders,
             role  TYPE agr_name,
             users TYPE string_table,
           END OF ty_holders.
    DATA holders TYPE SORTED TABLE OF ty_holders WITH UNIQUE KEY role.
    DATA hidden_roles TYPE SORTED TABLE OF agr_name WITH UNIQUE KEY table_line.

    DATA(group) = CONV xuclass( to_upper( condense( args->get_string( `user_group` ) ) ) ).
    IF group IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `user_group is required.` ).
    ENDIF.
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(members) = user_repo->get_group_members( group ).
    IF members IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User group { group } has no users.| ).
    ENDIF.
    DATA(payload) = NEW ty_payload( user_group    = group
                                    inactive_days = args->get_integer( name = `inactive_days` default = co_inactive_days ) ).
    IF payload->inactive_days < 1.
      payload->inactive_days = co_inactive_days.
    ENDIF.
    result-data = payload.

    LOOP AT members INTO DATA(member).
      IF ctx->guard( )->can_display_user( member-user ) = abap_false.
        result-hidden_by_authorization += 1.
        DELETE members.
      ENDIF.
    ENDLOOP.
    IF members IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display the users of group { group } (S_USER_GRP, activity 03).| ).
    ENDIF.
    payload->members = lines( members ).

    DATA(assignments) = user_repo->get_group_assignments( group ).
    DATA(profiles) = user_repo->get_group_direct_profiles( group ).
    LOOP AT assignments INTO DATA(assignment).
      IF NOT line_exists( members[ user = assignment-user ] ).
        CONTINUE.
      ENDIF.
      IF line_exists( hidden_roles[ table_line = assignment-role ] ).
        CONTINUE.
      ENDIF.
      READ TABLE holders ASSIGNING FIELD-SYMBOL(<holders>) WITH TABLE KEY role = assignment-role.
      IF sy-subrc <> 0.
        IF ctx->guard( )->can_display_role( assignment-role ) = abap_false.
          INSERT assignment-role INTO TABLE hidden_roles.
          CONTINUE.
        ENDIF.
        INSERT VALUE #( role = assignment-role ) INTO TABLE holders ASSIGNING <holders>.
      ENDIF.
      APPEND CONV string( assignment-user ) TO <holders>-users.
    ENDLOOP.
    result-hidden_by_authorization += lines( hidden_roles ).

    " findings per member
    LOOP AT members INTO member.
      DATA(type_text) = zcl_accx_user_hygiene=>user_type_text( member-user_type_code ).
      READ TABLE payload->user_types ASSIGNING FIELD-SYMBOL(<type>) WITH KEY code = type_text.
      IF sy-subrc <> 0.
        APPEND VALUE #( code = type_text ) TO payload->user_types ASSIGNING <type>.
      ENDIF.
      <type>-users += 1.

      DATA(assessment) = zcl_accx_user_hygiene=>assess(
                           member          = member
                           roles           = COND #( WHEN line_exists( assignments[ user = member-user ] ) THEN 1 ELSE 0 )
                           direct_profiles = VALUE #( FOR p IN profiles WHERE ( user = member-user ) ( CONV #( p-profile ) ) )
                           inactive_days   = payload->inactive_days ).
      IF assessment-finding_codes IS NOT INITIAL.
        APPEND VALUE #( user          = member-user
                        user_type     = type_text
                        last_logon    = member-last_logon
                        severity      = assessment-severity
                        findings      = assessment-findings
                        finding_codes = assessment-finding_codes ) TO payload->users.
      ENDIF.
    ENDLOOP.
    SORT payload->user_types BY users DESCENDING code ASCENDING.

    payload->with_findings = lines( payload->users ).
    LOOP AT zcl_accx_user_hygiene=>severity_order( ) INTO DATA(code).
      DATA(count) = REDUCE i( INIT n = 0 FOR u IN payload->users
                              NEXT n = n + COND #( WHEN line_exists( u-finding_codes[ table_line = code ] ) THEN 1 ELSE 0 ) ).
      IF count > 0.
        APPEND VALUE #( code = code users = count ) TO payload->counts.
      ENDIF.
    ENDLOOP.
    SORT payload->users BY severity ASCENDING user ASCENDING.

    " roles: most frequent, and outliers held by one member only
    payload->roles_total = lines( holders ).
    LOOP AT holders INTO DATA(holder).
      APPEND VALUE #( role  = holder-role
                      users = lines( holder-users )
                      share = lines( holder-users ) * 100 / payload->members ) TO payload->top_roles.
      IF lines( holder-users ) = 1 AND payload->members >= co_outlier_members.
        APPEND VALUE #( role = holder-role user = holder-users[ 1 ] ) TO payload->outliers.
      ENDIF.
    ENDLOOP.
    SORT payload->top_roles BY users DESCENDING role ASCENDING.
    SORT payload->outliers BY user role.

    result-total_count = lines( payload->users ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->users ) > max.
      DELETE payload->users FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->top_roles ) > max.
      DELETE payload->top_roles FROM max + 1.
    ENDIF.
    IF lines( payload->outliers ) > max.
      DELETE payload->outliers FROM max + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `USR02 (members, user type, validity, lock, last logon, password state)` )
                              ( `AGR_USERS (roles assigned today)` )
                              ( `UST04, AGR_1016 (profiles assigned directly)` ) ).
    IF line_exists( payload->counts[ code = zcl_accx_user_hygiene=>co_finding-direct_profile ] ).
      APPEND `Replace profiles assigned directly by roles; run_critical_access_check shows which critical authorizations they grant.`
             TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = zcl_accx_user_hygiene=>co_finding-inactive ] ) OR line_exists( payload->counts[ code = zcl_accx_user_hygiene=>co_finding-never_logged_on ] ).
      APPEND |Lock or delete dialog users without logon (more than { payload->inactive_days } days or never) after checking with | &&
             |their managers; get_user_profile shows one user.| TO result-next_steps.
    ENDIF.
    IF payload->outliers IS NOT INITIAL.
      APPEND |Use compare_users with peer_group { group } for the users holding outlier roles.| TO result-next_steps.
    ENDIF.
    IF line_exists( payload->counts[ code = zcl_accx_user_hygiene=>co_finding-expired ] ).
      APPEND `Expired users keep their roles; delete them or remove the assignments once the retention period is over.` TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD listed.
    LOOP AT names INTO DATA(name) TO max.
      result = |{ result }{ COND #( WHEN sy-tabix > 1 THEN `, ` ) }{ name }|.
    ENDLOOP.
    IF lines( names ) > max.
      result = |{ result } and { lines( names ) - max } more|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |User group **{ <payload>-user_group }**: { <payload>-members } users | &&
                     |({ concat_lines_of( table = VALUE string_table( FOR t IN <payload>-user_types ( |{ t-users } { t-code }| ) ) sep = `, ` ) }), | &&
                     |{ <payload>-roles_total } roles assigned today, | &&
                     |{ COND #( WHEN <payload>-with_findings = 0 THEN `no hygiene findings`
                                ELSE |**{ <payload>-with_findings } users with findings**| ) }.|.
    LOOP AT <payload>-counts INTO DATA(count).
      result-summary = |{ result-summary }\n- { count-code }: { count-users } { COND #( WHEN count-users = 1 THEN `user` ELSE `users` ) }|.
    ENDLOOP.
    IF <payload>-users IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Users, most severe first:**|.
      LOOP AT <payload>-users INTO DATA(user).
        result-summary = |{ result-summary }\n- **{ user-user }** ({ user-user_type }): { concat_lines_of( table = user-findings sep = ` ` ) }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-top_roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nMost frequent roles: | &&
                       |{ listed( names = VALUE #( FOR r IN <payload>-top_roles ( |{ r-role } ({ r-users }, { r-share }%)| ) ) max = 10 ) }|.
    ENDIF.
    IF <payload>-outliers IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Outliers** (role held by one member only): | &&
                       |{ listed( VALUE #( FOR o IN <payload>-outliers ( |{ o-role } ({ o-user })| ) ) ) }|.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nLists cut to max_rows ({ result-total_count } users with findings) - raise max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } users or roles left out due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

