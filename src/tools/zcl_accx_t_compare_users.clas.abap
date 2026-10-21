"! <p class="shorttext synchronized">Access Explorer tool: compare_users</p>
"! Differences between two users (roles, profiles assigned directly,
"! authorization values, critical authorizations, launchpad catalogs), or
"! between a user and the other members of a user group (roles most
"! colleagues hold that the user lacks, roles hardly any colleague holds).
"! Personal parts - time-limited assignments, derived roles, organizational
"! level values, profiles assigned directly - are flagged, so a colleague can
"! serve as a template for a new employee.
CLASS zcl_accx_t_compare_users DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `compare_users`.
    "! default share of the colleagues (percent) from which a role is typical for the user group
    CONSTANTS co_typical_share TYPE i VALUE 50.
    "! own roles held by at most this share of the colleagues (percent) are unusual
    CONSTANTS co_unusual_share TYPE i VALUE 10.

    CONSTANTS: BEGIN OF co_scope,
                 roles TYPE string VALUE `roles`,
                 auth  TYPE string VALUE `auth`,
                 fiori TYPE string VALUE `fiori`,
                 all   TYPE string VALUE `all`,
               END OF co_scope.

    TYPES: BEGIN OF ty_user,
             user       TYPE string,
             full_name  TYPE string,
             user_group TYPE string,
             user_type  TYPE string,
             "! not locked and within its validity period
             usable     TYPE abap_bool,
             "! roles assigned today (single roles of composite roles included)
             roles      TYPE i,
           END OF ty_user.

    TYPES: BEGIN OF ty_role,
             role          TYPE string,
             description   TYPE string,
             "! end of a time-limited assignment (initial = unlimited)
             valid_to      TYPE d,
             "! assigned only through a composite role
             via_composite TYPE abap_bool,
             derived_from  TYPE string,
             "! why the assignment is specific to its user (time limit, derived role)
             personal      TYPE string,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_peer_role,
             role        TYPE string,
             description TYPE string,
             "! colleagues holding the role today
             peers       TYPE i,
             "! share of the colleagues in percent
             share       TYPE i,
           END OF ty_peer_role,
           ty_peer_roles TYPE STANDARD TABLE OF ty_peer_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user             TYPE ty_user,
             "! second user (compare_with); empty when compared with a user group
             other            TYPE ty_user,
             peer_group       TYPE string,
             "! other members of the user group the caller may display
             peers            TYPE i,
             scope            TYPE string,
             object           TYPE string,
             roles_only_user  TYPE ty_roles,
             roles_only_other TYPE ty_roles,
             roles_common     TYPE i,
             "! profiles assigned directly (not generated for a role); only_a = user, only_b = other user
             profiles         TYPE zcl_accx_role_diff=>ty_diff,
             "! values as OBJECT FIELD=VALUE without organizational level fields
             values           TYPE zcl_accx_role_diff=>ty_diff,
             "! values of organizational level fields (company code, plant ...)
             org_values       TYPE zcl_accx_role_diff=>ty_diff,
             "! critical authorizations (SUIM rules) as RULE: text
             critical         TYPE zcl_accx_role_diff=>ty_diff,
             catalogs         TYPE zcl_accx_role_diff=>ty_diff,
             "! user group: roles at least typical_share percent of the colleagues hold that the user lacks
             typical_share    TYPE i,
             typical_missing  TYPE ty_peer_roles,
             "! user group: roles of the user that at most co_unusual_share percent of the colleagues hold
             unusual          TYPE ty_peer_roles,
             identical        TYPE abap_bool,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    CONSTANTS co_unlimited TYPE d VALUE '99991231'.

    DATA hidden TYPE zcl_accx_role_diff=>ty_set.

    METHODS check_user
      IMPORTING !name         TYPE string
                !ctx          TYPE REF TO zif_accx_context
      RETURNING VALUE(result) TYPE syuname
      RAISING   zcx_accx_error.

    METHODS user_side
      IMPORTING !master       TYPE zif_accx_user_repo=>ty_user
                !roles        TYPE ty_roles
      RETURNING VALUE(result) TYPE ty_user.

    "! Roles assigned today the caller may display, one entry per role
    METHODS active_roles
      IMPORTING !assignments  TYPE zif_accx_user_repo=>ty_role_assignments
                !ctx          TYPE REF TO zif_accx_context
      RETURNING VALUE(result) TYPE ty_roles.

    METHODS compare_two
      IMPORTING !user    TYPE syuname
                !other   TYPE syuname
                !roles   TYPE ty_roles
                !ctx     TYPE REF TO zif_accx_context
                !payload TYPE REF TO ty_payload
      CHANGING  !result  TYPE zif_accx_types=>ty_result.

    METHODS compare_peers
      IMPORTING !user    TYPE syuname
                !group   TYPE xuclass
                !roles   TYPE ty_roles
                !ctx     TYPE REF TO zif_accx_context
                !payload TYPE REF TO ty_payload
      CHANGING  !result  TYPE zif_accx_types=>ty_result.

    "! Roles of one user missing at the other: name plus derivation and personal parts
    METHODS only_in
      IMPORTING !roles        TYPE ty_roles
                !names        TYPE string_table
      RETURNING VALUE(result) TYPE ty_roles.

    "! Authorization values of the user master (profiles the caller may display, objects it may display)
    METHODS values_of
      IMPORTING !user         TYPE syuname
                !object       TYPE xuobject
                !ctx          TYPE REF TO zif_accx_context
      EXPORTING !profiles     TYPE string_table
      RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

    METHODS catalogs_of
      IMPORTING !roles        TYPE ty_roles
      RETURNING VALUE(result) TYPE string_table.

    METHODS critical_set
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE string_table.

    METHODS cut
      IMPORTING !max       TYPE i
      CHANGING  !diff      TYPE zcl_accx_role_diff=>ty_diff
                !truncated TYPE abap_bool.

    METHODS listed
      IMPORTING !names        TYPE string_table
                !max          TYPE i DEFAULT 15
      RETURNING VALUE(result) TYPE string.

    METHODS role_text
      IMPORTING !role         TYPE ty_role
      RETURNING VALUE(result) TYPE string.

    METHODS diff_line
      IMPORTING !label        TYPE string
                !diff         TYPE zcl_accx_role_diff=>ty_diff
                !payload      TYPE ty_payload
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_compare_users IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Compare users`
      description = |Compares a user with another user (compare_with) or with the other members of a user group | &&
                    |(peer_group; default: the user's own group). Two users: roles assigned today only to one of them, | &&
                    |profiles assigned directly, and by scope the authorization values of the user masters (organizational | &&
                    |level values apart), the critical authorizations (SUIM rules) and the launchpad catalogs only one | &&
                    |holds. Personal parts are flagged: time-limited assignments, derived roles (organizational levels of | &&
                    |their holder), roles only through a composite role. User group: the roles most colleagues hold that | &&
                    |the user lacks and the user's roles hardly any colleague holds. Typical questions: "what may X do | &&
                    |that Y may not", "new employee should get the same as colleague Y", "what do colleagues have that | &&
                    |X lacks".|
      group       = zif_accx_types=>co_group-user
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_COMPARE_USERS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `SAP user ID, e.g. the new employee (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `compare_with`
                                      description = `Second user, e.g. the colleague serving as template.`
                                      maximum     = 12 ) )
                             ( param( name        = `peer_group`
                                      description = `User group to compare with instead of a second user (default: the user's own group).`
                                      maximum     = 12 ) )
                             ( param( name        = `scope`
                                      description = |Two users: roles (default; roles and profiles), auth (plus authorization values | &&
                                                    |and critical authorizations), fiori (plus launchpad catalogs) or all.|
                                      enum        = VALUE #( ( co_scope-roles ) ( co_scope-auth ) ( co_scope-fiori ) ( co_scope-all ) )
                                      default     = co_scope-roles ) )
                             ( param( name        = `object`
                                      description = `Compare only the values of this authorization object (implies scope auth).`
                                      maximum     = 10 ) )
                             ( param( name        = `typical_share`
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = |User group: share of the colleagues (percent) from which a role counts as typical | &&
                                                    |(default { co_typical_share }).|
                                      minimum     = 1
                                      maximum     = 100 ) )
                             ( param( name        = zif_accx_types=>co_param-max_rows
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = `Maximum number of entries per list and side (1-500, default 50).`
                                      minimum     = 1
                                      maximum     = 500 ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    CLEAR hidden.
    DATA(user) = check_user( name = args->get_string( `user` ) ctx = ctx ).
    DATA(other_name) = to_upper( condense( args->get_string( `compare_with` ) ) ).
    DATA(group_name) = to_upper( condense( args->get_string( `peer_group` ) ) ).
    IF other_name IS NOT INITIAL AND group_name IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `Pass either compare_with or peer_group, not both.` ).
    ENDIF.
    DATA(scope) = to_lower( condense( args->get_string( `scope` ) ) ).
    IF scope IS INITIAL.
      scope = co_scope-roles.
    ENDIF.
    IF scope <> co_scope-roles AND scope <> co_scope-auth AND scope <> co_scope-fiori AND scope <> co_scope-all.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Unknown scope { scope }: use roles, auth, fiori or all.| ).
    ENDIF.
    DATA(object) = CONV xuobject( to_upper( condense( args->get_string( `object` ) ) ) ).
    IF object IS NOT INITIAL.
      IF zcl_accx_domain_factory=>auth_evaluator( )->object_exists( object ) = abap_false.
        RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Authorization object { object } does not exist.| ).
      ENDIF.
      IF ctx->guard( )->can_display_authorization( object ) = abap_false.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                            message = |You are not authorized to display authorizations of { object } (S_USER_AUT, activity 03).| ).
      ENDIF.
      IF scope = co_scope-roles.
        scope = co_scope-auth.
      ELSEIF scope = co_scope-fiori.
        scope = co_scope-all.
      ENDIF.
    ENDIF.

    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(master) = user_repo->get_user( user ).
    DATA(roles) = active_roles( assignments = user_repo->get_role_assignments( user ) ctx = ctx ).
    DATA(payload) = NEW ty_payload( user          = user_side( master = master roles = roles )
                                    scope         = scope
                                    object        = CONV #( object )
                                    typical_share = args->get_integer( name = `typical_share` default = co_typical_share ) ).
    IF payload->typical_share < 1 OR payload->typical_share > 100.
      payload->typical_share = co_typical_share.
    ENDIF.
    result-data = payload.

    IF other_name IS NOT INITIAL.
      DATA(other) = check_user( name = other_name ctx = ctx ).
      IF other = user.
        RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `user and compare_with are the same user.` ).
      ENDIF.
      compare_two( EXPORTING user = user other = other roles = roles ctx = ctx payload = payload CHANGING result = result ).
    ELSE.
      DATA(group) = CONV xuclass( COND string( WHEN group_name IS NOT INITIAL THEN group_name ELSE master-user_group ) ).
      IF group IS INITIAL.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                            message = |User { user } has no user group: pass compare_with or peer_group.| ).
      ENDIF.
      compare_peers( EXPORTING user = user group = group roles = roles ctx = ctx payload = payload CHANGING result = result ).
    ENDIF.
    result-hidden_by_authorization = lines( hidden ).
  ENDMETHOD.

  METHOD compare_two.
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(other_roles) = active_roles( assignments = user_repo->get_role_assignments( other ) ctx = ctx ).
    payload->other = user_side( master = user_repo->get_user( other ) roles = other_roles ).

    DATA(names) = zcl_accx_role_diff=>diff_lists( a = VALUE #( FOR r IN roles ( r-role ) )
                                                  b = VALUE #( FOR r IN other_roles ( r-role ) ) ).
    payload->roles_only_user  = only_in( roles = roles names = names-only_a ).
    payload->roles_only_other = only_in( roles = other_roles names = names-only_b ).
    payload->roles_common     = names-common.

    DATA(auth) = xsdbool( payload->scope = co_scope-auth OR payload->scope = co_scope-all ).
    DATA(object) = CONV xuobject( payload->object ).
    DATA profiles_user TYPE string_table.
    DATA profiles_other TYPE string_table.
    DATA(values_user)  = values_of( EXPORTING user = user  object = object ctx = ctx IMPORTING profiles = profiles_user ).
    DATA(values_other) = values_of( EXPORTING user = other object = object ctx = ctx IMPORTING profiles = profiles_other ).
    payload->profiles = zcl_accx_role_diff=>diff_lists( a = profiles_user b = profiles_other ).
    IF auth = abap_true.
      " organizational levels differ between colleagues by design: compared separately
      DATA(org_fields) = zcl_accx_domain_factory=>role_repo( )->get_org_fields( ).
      payload->values = zcl_accx_role_diff=>diff( a = zcl_accx_role_diff=>value_set( values = values_user skip_fields = org_fields )
                                                  b = zcl_accx_role_diff=>value_set( values = values_other skip_fields = org_fields ) ).
      DATA(org_user)  = VALUE zif_accx_critical_rules=>ty_auth_values( ).
      DATA(org_other) = VALUE zif_accx_critical_rules=>ty_auth_values( ).
      LOOP AT values_user INTO DATA(value) WHERE field IS NOT INITIAL.
        IF line_exists( org_fields[ table_line = CONV string( value-field ) ] ).
          APPEND value TO org_user.
        ENDIF.
      ENDLOOP.
      LOOP AT values_other INTO value WHERE field IS NOT INITIAL.
        IF line_exists( org_fields[ table_line = CONV string( value-field ) ] ).
          APPEND value TO org_other.
        ENDIF.
      ENDLOOP.
      payload->org_values = zcl_accx_role_diff=>diff( a = zcl_accx_role_diff=>value_set( org_user )
                                                      b = zcl_accx_role_diff=>value_set( org_other ) ).
      payload->critical = zcl_accx_role_diff=>diff_lists( a = critical_set( values_user ) b = critical_set( values_other ) ).
    ENDIF.
    IF payload->scope = co_scope-fiori OR payload->scope = co_scope-all.
      payload->catalogs = zcl_accx_role_diff=>diff_lists( a = catalogs_of( roles ) b = catalogs_of( other_roles ) ).
    ENDIF.
    payload->identical = xsdbool( payload->roles_only_user IS INITIAL AND payload->roles_only_other IS INITIAL
                                  AND payload->profiles-only_a IS INITIAL AND payload->profiles-only_b IS INITIAL
                                  AND payload->values-only_a IS INITIAL AND payload->values-only_b IS INITIAL
                                  AND payload->org_values-only_a IS INITIAL AND payload->org_values-only_b IS INITIAL
                                  AND payload->catalogs-only_a IS INITIAL AND payload->catalogs-only_b IS INITIAL ).

    result-total_count = lines( payload->roles_only_user ) + lines( payload->roles_only_other )
                         + lines( payload->values-only_a ) + lines( payload->values-only_b ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->roles_only_user ) > max.
      DELETE payload->roles_only_user FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->roles_only_other ) > max.
      DELETE payload->roles_only_other FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    cut( EXPORTING max = max CHANGING diff = payload->values     truncated = result-truncated ).
    cut( EXPORTING max = max CHANGING diff = payload->org_values truncated = result-truncated ).
    cut( EXPORTING max = max CHANGING diff = payload->catalogs   truncated = result-truncated ).

    result-sources = VALUE #( ( `USR02, USR21 (user master), AGR_USERS, AGR_TEXTS (roles assigned today)` )
                              ( `UST04, UST10C, UST10S, UST12, AGR_1016 (profiles and authorization values of the user master)` ) ).
    IF auth = abap_true.
      APPEND `USORG (organizational level fields), USCRAUTH, USCRAUTHID (critical authorizations)` TO result-sources.
    ENDIF.
    IF payload->catalogs-common > 0 OR payload->catalogs-only_a IS NOT INITIAL OR payload->catalogs-only_b IS NOT INITIAL.
      APPEND `AGR_HIER, AGR_BUFFI (launchpad catalogs in the role menus)` TO result-sources.
    ENDIF.

    IF payload->user-usable = abap_false.
      APPEND |{ user } is locked or outside its validity period.| TO result-warnings.
    ENDIF.
    IF payload->other-usable = abap_false.
      APPEND |{ other } is locked or outside its validity period.| TO result-warnings.
    ENDIF.

    " what the user would get to match the other user: direct assignments, not single roles of a composite role
    DATA(to_request) = VALUE string_table( FOR r IN payload->roles_only_other WHERE ( via_composite = abap_false ) ( r-role ) ).
    IF to_request IS NOT INITIAL.
      APPEND |To give { user } the access of { other }, request { listed( to_request ) } via the access request process | &&
             |(assign_role assigns one role per call after approval).| TO result-next_steps.
    ENDIF.
    DATA(personal) = VALUE string_table( FOR r IN payload->roles_only_other WHERE ( personal IS NOT INITIAL ) ( r-role ) ).
    IF personal IS NOT INITIAL.
      APPEND |Do not copy { listed( personal ) } unchecked: they are specific to { other } (time limit, derived role with | &&
             |{ other }'s organizational levels) - choose the derived role of { user }'s own organizational unit.| TO result-next_steps.
    ENDIF.
    IF payload->profiles-only_b IS NOT INITIAL.
      APPEND |{ other } holds profiles assigned directly ({ listed( payload->profiles-only_b ) }): do not copy them, assign roles instead.|
             TO result-next_steps.
    ENDIF.
    IF payload->critical-only_b IS NOT INITIAL.
      APPEND |{ other } holds critical authorizations { user } does not; copying { other }'s roles grants them too - | &&
             |check with run_critical_access_check before the request.| TO result-next_steps.
    ENDIF.
    IF auth = abap_false AND ( payload->roles_only_user IS NOT INITIAL OR payload->roles_only_other IS NOT INITIAL ).
      APPEND `Use scope auth for the authorization values and critical authorizations behind the role difference, or compare_roles for two similar roles.`
             TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD compare_peers.
    TYPES: BEGIN OF ty_count,
             role  TYPE agr_name,
             peers TYPE i,
           END OF ty_count.
    DATA peers  TYPE SORTED TABLE OF syuname WITH UNIQUE KEY table_line.
    DATA counts TYPE SORTED TABLE OF ty_count WITH UNIQUE KEY role.

    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    payload->peer_group = group.
    LOOP AT user_repo->get_group_members( group ) INTO DATA(member) WHERE user <> user.
      IF ctx->guard( )->can_display_user( member-user ) = abap_true.
        INSERT member-user INTO TABLE peers.
      ELSE.
        INSERT |user { member-user }| INTO TABLE hidden.
      ENDIF.
    ENDLOOP.
    payload->peers = lines( peers ).
    result-sources = VALUE #( ( `USR02 (user group members), AGR_USERS, AGR_TEXTS (roles assigned today)` ) ).
    IF payload->scope <> co_scope-roles.
      APPEND `Against a user group only roles are compared; use compare_with for authorization values or catalogs.` TO result-warnings.
    ENDIF.
    IF peers IS INITIAL.
      APPEND |User group { group } has no other users you may display.| TO result-warnings.
      RETURN.
    ENDIF.

    LOOP AT user_repo->get_group_assignments( group ) INTO DATA(assignment).
      IF NOT line_exists( peers[ table_line = assignment-user ] ).
        CONTINUE.
      ENDIF.
      READ TABLE counts ASSIGNING FIELD-SYMBOL(<count>) WITH TABLE KEY role = assignment-role.
      IF sy-subrc <> 0.
        INSERT VALUE #( role = assignment-role ) INTO TABLE counts ASSIGNING <count>.
      ENDIF.
      <count>-peers += 1.
    ENDLOOP.

    LOOP AT counts INTO DATA(count).
      DATA(share) = count-peers * 100 / payload->peers.
      IF share < payload->typical_share OR line_exists( roles[ role = count-role ] ).
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_role( count-role ) = abap_false.
        INSERT |role { count-role }| INTO TABLE hidden.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( role = count-role peers = count-peers share = share ) TO payload->typical_missing.
    ENDLOOP.
    LOOP AT roles INTO DATA(role).
      DATA(holders) = VALUE i( counts[ role = CONV agr_name( role-role ) ]-peers OPTIONAL ).
      IF holders > 0.
        payload->roles_common += 1.
      ENDIF.
      share = holders * 100 / payload->peers.
      IF share <= co_unusual_share.
        APPEND VALUE #( role = role-role description = role-description peers = holders share = share ) TO payload->unusual.
      ENDIF.
    ENDLOOP.
    SORT payload->typical_missing BY share DESCENDING role ASCENDING.
    SORT payload->unusual BY share ASCENDING role ASCENDING.

    result-total_count = lines( payload->typical_missing ) + lines( payload->unusual ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->typical_missing ) > max.
      DELETE payload->typical_missing FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->unusual ) > max.
      DELETE payload->unusual FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    LOOP AT payload->typical_missing ASSIGNING FIELD-SYMBOL(<typical>).
      <typical>-description = role_repo->get_role_info( CONV #( <typical>-role ) )-description.
    ENDLOOP.

    IF payload->typical_missing IS NOT INITIAL.
      APPEND |{ user } lacks roles most colleagues in { group } hold ({ listed( names = VALUE #( FOR t IN payload->typical_missing ( t-role ) ) max = 5 ) }): | &&
             |clarify with the line manager whether { user } needs them; explain_missing_access names the role for a concrete | &&
             |gap, assign_role assigns it after approval.| TO result-next_steps.
    ENDIF.
    IF payload->unusual IS NOT INITIAL.
      APPEND |Review whether { user } still needs { listed( names = VALUE #( FOR u IN payload->unusual ( u-role ) ) max = 5 ) } - | &&
             |hardly any colleague in { group } holds them (get_role_details shows what they grant).| TO result-next_steps.
    ENDIF.
    APPEND |Use compare_users with compare_with for a colleague to see the authorization values behind the difference.| TO result-next_steps.
  ENDMETHOD.

  METHOD check_user.
    result = to_upper( condense( name ) ).
    IF zcl_accx_domain_factory=>user_repo( )->exists( result ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { result } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( result ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { result } (S_USER_GRP, activity 03).| ).
    ENDIF.
  ENDMETHOD.

  METHOD user_side.
    result = VALUE #( user       = master-user
                      full_name  = master-full_name
                      user_group = master-user_group
                      user_type  = master-user_type
                      usable     = xsdbool( master-locked = abap_false
                                            AND ( master-valid_from IS INITIAL OR master-valid_from <= sy-datum )
                                            AND ( master-valid_to IS INITIAL OR master-valid_to >= sy-datum ) )
                      roles      = lines( roles ) ).
  ENDMETHOD.

  METHOD active_roles.
    LOOP AT assignments INTO DATA(assignment) WHERE active = abap_true.
      IF ctx->guard( )->can_display_role( assignment-role ) = abap_false.
        INSERT |role { assignment-role }| INTO TABLE hidden.
        CONTINUE.
      ENDIF.
      DATA(valid_to) = COND d( WHEN assignment-valid_to < co_unlimited THEN assignment-valid_to ).
      READ TABLE result ASSIGNING FIELD-SYMBOL(<role>) WITH KEY role = CONV string( assignment-role ).
      IF sy-subrc <> 0.
        APPEND VALUE #( role          = assignment-role
                        description   = assignment-description
                        valid_to      = valid_to
                        via_composite = assignment-via_composite ) TO result.
        CONTINUE.
      ENDIF.
      " several assignments of the same role: a direct one and the latest end count
      IF assignment-via_composite = abap_false.
        <role>-via_composite = abap_false.
      ENDIF.
      IF <role>-valid_to IS NOT INITIAL AND ( valid_to IS INITIAL OR valid_to > <role>-valid_to ).
        <role>-valid_to = valid_to.
      ENDIF.
    ENDLOOP.
    SORT result BY role.
  ENDMETHOD.

  METHOD only_in.
    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    LOOP AT names INTO DATA(name).
      DATA(role) = roles[ role = name ].
      role-derived_from = repo->get_role_info( CONV #( name ) )-derived_from.
      DATA(reasons) = VALUE string_table( ).
      IF role-valid_to IS NOT INITIAL.
        APPEND |assigned until { role-valid_to DATE = ISO }| TO reasons.
      ENDIF.
      IF role-derived_from IS NOT INITIAL.
        APPEND |derived from { role-derived_from } (organizational levels)| TO reasons.
      ENDIF.
      role-personal = concat_lines_of( table = reasons sep = `, ` ).
      APPEND role TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD values_of.
    DATA allowed TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.
    DATA denied  TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.

    CLEAR profiles.
    DATA(origin) = zcl_accx_domain_factory=>access_origin( ).
    DATA(objects) = COND string_table( WHEN object IS NOT INITIAL THEN VALUE #( ( CONV #( object ) ) ) ).
    LOOP AT origin->get_user_sources( user ) INTO DATA(source).
      IF source-role IS NOT INITIAL AND ctx->guard( )->can_display_role( source-role ) = abap_false.
        INSERT |role { source-role }| INTO TABLE hidden.
        CONTINUE.
      ENDIF.
      IF source-role IS INITIAL.
        IF ctx->guard( )->can_display_profile( source-profile ) = abap_false.
          INSERT |profile { source-profile }| INTO TABLE hidden.
          CONTINUE.
        ENDIF.
        APPEND CONV string( source-profile ) TO profiles.
      ENDIF.
      LOOP AT origin->get_profile_values( profile = source-profile objects = objects all_objects = xsdbool( objects IS INITIAL ) )
           INTO DATA(value).
        IF NOT line_exists( allowed[ table_line = value-object ] ).
          IF line_exists( denied[ table_line = value-object ] ).
            CONTINUE.
          ENDIF.
          IF ctx->guard( )->can_display_authorization( value-object ) = abap_false.
            INSERT value-object INTO TABLE denied.
            INSERT |object { value-object }| INTO TABLE hidden.
            CONTINUE.
          ENDIF.
          INSERT value-object INTO TABLE allowed.
        ENDIF.
        APPEND value TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD catalogs_of.
    DATA menu_roles TYPE zif_accx_role_repo=>ty_roles.
    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    LOOP AT roles INTO DATA(role).
      " derived roles have no menu of their own: PFCG shows the reference role's
      DATA(reference) = repo->get_role_info( CONV #( role-role ) )-derived_from.
      APPEND COND agr_name( WHEN reference IS NOT INITIAL THEN reference ELSE CONV #( role-role ) ) TO menu_roles.
    ENDLOOP.
    SORT menu_roles BY table_line.
    DELETE ADJACENT DUPLICATES FROM menu_roles COMPARING table_line.
    IF menu_roles IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT zcl_accx_domain_factory=>fiori_repo( )->get_role_catalogs( menu_roles ) INTO DATA(catalog).
      APPEND catalog-catalog TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD critical_set.
    IF values IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT zcl_accx_domain_factory=>critical_rules( )->evaluate( values ) INTO DATA(hit).
      APPEND |{ hit-rule }: { hit-text }| TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD cut.
    IF lines( diff-only_a ) > max.
      DELETE diff-only_a FROM max + 1.
      truncated = abap_true.
    ENDIF.
    IF lines( diff-only_b ) > max.
      DELETE diff-only_b FROM max + 1.
      truncated = abap_true.
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

  METHOD role_text.
    DATA(notes) = VALUE string_table( ).
    IF role-via_composite = abap_true.
      APPEND `via composite role` TO notes.
    ENDIF.
    IF role-personal IS NOT INITIAL.
      APPEND |personal: { role-personal }| TO notes.
    ENDIF.
    result = |{ role-role }{ COND #( WHEN notes IS NOT INITIAL THEN | ({ concat_lines_of( table = notes sep = `; ` ) })| ) }|.
  ENDMETHOD.

  METHOD diff_line.
    IF diff-only_a IS INITIAL AND diff-only_b IS INITIAL.
      result = |\n- { label }: no differences ({ diff-common } in both)|.
      RETURN.
    ENDIF.
    result = |\n- { label }: { diff-common } in both|.
    IF diff-only_a IS NOT INITIAL.
      result = |{ result }\n  - only { payload-user-user }: { listed( diff-only_a ) }|.
    ENDIF.
    IF diff-only_b IS NOT INITIAL.
      result = |{ result }\n  - only { payload-other-user }: { listed( diff-only_b ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    DATA(a) = <payload>-user.
    DATA(b) = <payload>-other.

    IF <payload>-peer_group IS NOT INITIAL.
      result-summary = |**{ a-user }**{ COND #( WHEN a-full_name IS NOT INITIAL THEN | ({ a-full_name })| ) } compared with the | &&
                       |{ <payload>-peers } other users of user group **{ <payload>-peer_group }**: { a-roles } roles today, | &&
                       |{ <payload>-roles_common } of them also held by colleagues.|.
      IF <payload>-typical_missing IS NOT INITIAL.
        result-summary = |{ result-summary }\n\n**Roles most colleagues hold that { a-user } lacks** (at least { <payload>-typical_share }%):|.
        LOOP AT <payload>-typical_missing INTO DATA(typical).
          result-summary = |{ result-summary }\n- { typical-role }{ COND #( WHEN typical-description IS NOT INITIAL THEN | ({ typical-description })| ) }: | &&
                           |{ typical-peers } of { <payload>-peers } ({ typical-share }%)|.
        ENDLOOP.
      ELSEIF <payload>-peers > 0.
        result-summary = |{ result-summary } No role held by at least { <payload>-typical_share }% of the colleagues is missing.|.
      ENDIF.
      IF <payload>-unusual IS NOT INITIAL.
        result-summary = |{ result-summary }\n\n**Roles of { a-user } hardly any colleague holds** (at most { co_unusual_share }%):|.
        LOOP AT <payload>-unusual INTO DATA(unusual).
          result-summary = |{ result-summary }\n- { unusual-role }{ COND #( WHEN unusual-description IS NOT INITIAL THEN | ({ unusual-description })| ) }: | &&
                           |{ unusual-peers } of { <payload>-peers }|.
        ENDLOOP.
      ENDIF.
    ELSE.
      result-summary = |Users **{ a-user }** ({ a-full_name }, group { a-user_group }, { a-roles } roles) and | &&
                       |**{ b-user }** ({ b-full_name }, group { b-user_group }, { b-roles } roles)| &&
                       |{ COND #( WHEN <payload>-object IS NOT INITIAL THEN |, object { <payload>-object } only| ) }.|.
      IF <payload>-identical = abap_true.
        result-summary = |{ result-summary } No differences in scope { <payload>-scope }.|.
      ENDIF.
      result-summary = |{ result-summary }\n- Roles: { <payload>-roles_common } in both|.
      IF <payload>-roles_only_user IS NOT INITIAL.
        result-summary = |{ result-summary }\n  - only { a-user }: | &&
                         |{ concat_lines_of( table = VALUE string_table( FOR r IN <payload>-roles_only_user ( role_text( r ) ) ) sep = `, ` ) }|.
      ENDIF.
      IF <payload>-roles_only_other IS NOT INITIAL.
        result-summary = |{ result-summary }\n  - only { b-user }: | &&
                         |{ concat_lines_of( table = VALUE string_table( FOR r IN <payload>-roles_only_other ( role_text( r ) ) ) sep = `, ` ) }|.
      ENDIF.
      IF <payload>-profiles-common > 0 OR <payload>-profiles-only_a IS NOT INITIAL OR <payload>-profiles-only_b IS NOT INITIAL.
        result-summary = result-summary && diff_line( label = `Profiles assigned directly` diff = <payload>-profiles payload = <payload> ).
      ENDIF.
      IF <payload>-scope = co_scope-auth OR <payload>-scope = co_scope-all.
        result-summary = result-summary && diff_line( label = `Authorization values (without organizational levels)` diff = <payload>-values payload = <payload> ).
        IF <payload>-org_values-common > 0 OR <payload>-org_values-only_a IS NOT INITIAL OR <payload>-org_values-only_b IS NOT INITIAL.
          result-summary = result-summary && diff_line( label = `Organizational level values (personal)` diff = <payload>-org_values payload = <payload> ).
        ENDIF.
        IF <payload>-critical-only_a IS NOT INITIAL OR <payload>-critical-only_b IS NOT INITIAL.
          result-summary = result-summary && diff_line( label = `**Critical authorizations**` diff = <payload>-critical payload = <payload> ).
        ENDIF.
      ENDIF.
      IF <payload>-scope = co_scope-fiori OR <payload>-scope = co_scope-all.
        result-summary = result-summary && diff_line( label = `Launchpad catalogs` diff = <payload>-catalogs payload = <payload> ).
      ENDIF.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nLists cut to max_rows per side - filter by object or raise max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } users, roles, profiles or objects left out due to missing | &&
                       |display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

