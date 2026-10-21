"! <p class="shorttext synchronized">Access Explorer tool: compare_roles</p>
"! Differences between two roles: relation (derivation, common reference role),
"! authorization values per object and field, objects, menu transactions,
"! launchpad catalogs, single roles, organizational levels and the critical
"! authorizations only one of them grants. Composite roles are compared by the
"! union of their single roles.
CLASS zcl_accx_t_compare_roles DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `compare_roles`.

    TYPES: BEGIN OF ty_side,
             role         TYPE string,
             "! single, composite or derived
             role_type    TYPE string,
             derived_from TYPE string,
             users        TYPE i,
           END OF ty_side.

    TYPES: BEGIN OF ty_payload,
             role_a           TYPE ty_side,
             role_b           TYPE ty_side,
             "! e.g. "ZB is derived from ZA"; empty without relation
             relation         TYPE string,
             object           TYPE string,
             "! values as OBJECT FIELD=VALUE; only_a = granted by role A only
             "! (organizational level fields aside for derived roles)
             values           TYPE zcl_accx_role_diff=>ty_diff,
             objects_only_a   TYPE string_table,
             objects_only_b   TYPE string_table,
             transactions     TYPE zcl_accx_role_diff=>ty_diff,
             catalogs         TYPE zcl_accx_role_diff=>ty_diff,
             single_roles     TYPE zcl_accx_role_diff=>ty_diff,
             "! as $LEVEL=VALUE
             org_levels       TYPE zcl_accx_role_diff=>ty_diff,
             "! critical authorizations (SUIM rules) as RULE: text
             critical         TYPE zcl_accx_role_diff=>ty_diff,
             identical        TYPE abap_bool,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_content,
             values       TYPE zif_accx_critical_rules=>ty_auth_values,
             transactions TYPE string_table,
             catalogs     TYPE string_table,
             org_levels   TYPE string_table,
           END OF ty_content.

    METHODS check_role
      IMPORTING !name         TYPE string
                !ctx          TYPE REF TO zif_accx_context
      RETURNING VALUE(result) TYPE agr_name
      RAISING   zcx_accx_error.

    "! Values, menu, catalogs and org levels of a role; composite roles: union of their displayable single roles
    METHODS content_of
      IMPORTING !role         TYPE agr_name
                !info         TYPE zif_accx_role_repo=>ty_role_info
                !object       TYPE xuobject
                !ctx          TYPE REF TO zif_accx_context
      CHANGING  !hidden       TYPE i
      RETURNING VALUE(result) TYPE ty_content.

    METHODS side
      IMPORTING !role         TYPE agr_name
                !info         TYPE zif_accx_role_repo=>ty_role_info
                !counts       TYPE zif_accx_role_repo=>ty_user_counts
      RETURNING VALUE(result) TYPE ty_side.

    METHODS critical_set
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE string_table.

    METHODS cut
      IMPORTING !max      TYPE i
      CHANGING  !diff     TYPE zcl_accx_role_diff=>ty_diff
                !truncated TYPE abap_bool.

    METHODS listed
      IMPORTING !names        TYPE string_table
                !max          TYPE i DEFAULT 15
      RETURNING VALUE(result) TYPE string.

    METHODS diff_line
      IMPORTING !label        TYPE string
                !diff         TYPE zcl_accx_role_diff=>ty_diff
                !payload      TYPE ty_payload
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_compare_roles IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Compare roles`
      description = |Compares two PFCG roles: how they are related (one derived from the other, same reference | &&
                    |role), the authorization values only one of them grants (per object and field, independent | &&
                    |of how the authorizations are split), objects only in one of them, menu transactions, | &&
                    |launchpad catalogs, single roles of composite roles, organizational levels, and the critical | &&
                    |authorizations (SUIM rules) only one of them grants. Composite roles are compared by the union | &&
                    |of their single roles, derived roles by the menu of their reference role. Use it to check a | &&
                    |derived role against its reference, to choose between two candidate roles, or to see what a | &&
                    |copy changed.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_COMPARE_ROLES\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role_a`
                                      description = `First role, e.g. the reference role (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 30 ) )
                             ( param( name        = `role_b`
                                      description = `Second role, e.g. the derived role or the copy (case-insensitive).`
                                      required    = abap_true
                                      maximum     = 30 ) )
                             ( param( name        = `object`
                                      description = `Compare only the values of this authorization object, e.g. S_TABU_DIS.`
                                      maximum     = 10 ) )
                             ( param( name        = zif_accx_types=>co_param-max_rows
                                      kind        = zif_accx_types=>co_kind-integer
                                      description = `Maximum number of differences per list and side (1-500, default 50).`
                                      minimum     = 1
                                      maximum     = 500 ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA hidden TYPE i.

    DATA(role_a) = check_role( name = args->get_string( `role_a` ) ctx = ctx ).
    DATA(role_b) = check_role( name = args->get_string( `role_b` ) ctx = ctx ).
    IF role_a = role_b.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `role_a and role_b are the same role.` ).
    ENDIF.
    DATA(object) = CONV xuobject( to_upper( condense( args->get_string( `object` ) ) ) ).
    IF object IS NOT INITIAL AND ctx->guard( )->can_display_authorization( object ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display authorizations of object { object } (S_USER_AUT, activity 03).| ).
    ENDIF.

    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(info_a) = repo->get_role_info( role_a ).
    DATA(info_b) = repo->get_role_info( role_b ).
    DATA(counts) = repo->count_assigned_users( VALUE #( ( role_a ) ( role_b ) ) ).
    DATA(payload) = NEW ty_payload( role_a = side( role = role_a info = info_a counts = counts )
                                    role_b = side( role = role_b info = info_b counts = counts )
                                    object = CONV #( object ) ).
    result-data = payload.

    payload->relation = COND #( WHEN info_b-derived_from = role_a THEN |{ role_b } is derived from { role_a }|
                                WHEN info_a-derived_from = role_b THEN |{ role_a } is derived from { role_b }|
                                WHEN info_a-derived_from IS NOT INITIAL AND info_a-derived_from = info_b-derived_from
                                  THEN |both are derived from { info_a-derived_from }|
                                WHEN line_exists( info_a-parents[ table_line = CONV string( role_b ) ] ) THEN |{ role_a } is part of composite role { role_b }|
                                WHEN line_exists( info_b-parents[ table_line = CONV string( role_a ) ] ) THEN |{ role_b } is part of composite role { role_a }| ).
    " derived roles differ in their organizational levels by design; those are compared separately
    DATA(skip_fields) = COND string_table( WHEN info_a-derived_from IS NOT INITIAL OR info_b-derived_from IS NOT INITIAL
                                           THEN repo->get_org_fields( ) ).

    DATA(content_a) = content_of( EXPORTING role = role_a info = info_a object = object ctx = ctx CHANGING hidden = hidden ).
    DATA(content_b) = content_of( EXPORTING role = role_b info = info_b object = object ctx = ctx CHANGING hidden = hidden ).
    result-hidden_by_authorization = hidden.

    payload->values = zcl_accx_role_diff=>diff( a = zcl_accx_role_diff=>value_set( values = content_a-values skip_fields = skip_fields )
                                                b = zcl_accx_role_diff=>value_set( values = content_b-values skip_fields = skip_fields ) ).
    DATA(objects) = zcl_accx_role_diff=>diff(
      a = zcl_accx_role_diff=>objects_of( VALUE #( FOR v IN content_a-values ( CONV #( v-object ) ) ) )
      b = zcl_accx_role_diff=>objects_of( VALUE #( FOR v IN content_b-values ( CONV #( v-object ) ) ) ) ).
    payload->objects_only_a = objects-only_a.
    payload->objects_only_b = objects-only_b.
    payload->critical = zcl_accx_role_diff=>diff_lists( a = critical_set( content_a-values ) b = critical_set( content_b-values ) ).
    IF object IS INITIAL.
      payload->transactions = zcl_accx_role_diff=>diff_lists( a = content_a-transactions b = content_b-transactions ).
      payload->catalogs     = zcl_accx_role_diff=>diff_lists( a = content_a-catalogs b = content_b-catalogs ).
      payload->org_levels   = zcl_accx_role_diff=>diff_lists( a = content_a-org_levels b = content_b-org_levels ).
      IF info_a-composite = abap_true OR info_b-composite = abap_true.
        payload->single_roles = zcl_accx_role_diff=>diff_lists( a = info_a-children b = info_b-children ).
      ENDIF.
    ENDIF.
    payload->identical = xsdbool( payload->values-only_a IS INITIAL AND payload->values-only_b IS INITIAL
                                  AND payload->transactions-only_a IS INITIAL AND payload->transactions-only_b IS INITIAL
                                  AND payload->catalogs-only_a IS INITIAL AND payload->catalogs-only_b IS INITIAL
                                  AND payload->single_roles-only_a IS INITIAL AND payload->single_roles-only_b IS INITIAL
                                  AND payload->org_levels-only_a IS INITIAL AND payload->org_levels-only_b IS INITIAL ).

    result-total_count = lines( payload->values-only_a ) + lines( payload->values-only_b ).
    DATA(max) = ctx->max_rows( ).
    cut( EXPORTING max = max CHANGING diff = payload->values       truncated = result-truncated ).
    cut( EXPORTING max = max CHANGING diff = payload->transactions truncated = result-truncated ).
    cut( EXPORTING max = max CHANGING diff = payload->catalogs     truncated = result-truncated ).

    result-sources = VALUE #( ( `AGR_DEFINE, AGR_AGRS, AGR_FLAGS (role type, derivation, composite roles)` )
                              ( `AGR_1251, AGR_1252 (authorization values, organizational levels)` )
                              ( `AGR_TCODES, AGR_HIER, AGR_BUFFI (menu, launchpad catalogs)` )
                              ( `USCRAUTH, USCRAUTHID (critical authorizations)` ) ).
    IF info_b-derived_from = role_a AND ( payload->values-only_a IS NOT INITIAL OR payload->values-only_b IS NOT INITIAL ).
      APPEND |{ role_b } is not in sync with its reference role { role_a }: pass { role_a } on to its derived roles | &&
             |(PFCG: generate derived roles, or any apply_role_change on { role_a }).| TO result-next_steps.
    ELSEIF info_a-derived_from = role_b AND ( payload->values-only_a IS NOT INITIAL OR payload->values-only_b IS NOT INITIAL ).
      APPEND |{ role_a } is not in sync with its reference role { role_b }: pass { role_b } on to its derived roles | &&
             |(PFCG: generate derived roles, or any apply_role_change on { role_b }).| TO result-next_steps.
    ENDIF.
    IF payload->objects_only_a IS NOT INITIAL OR payload->objects_only_b IS NOT INITIAL OR payload->values-only_a IS NOT INITIAL.
      APPEND |Use get_role_authorizations with role and object for the authorizations behind a difference.| TO result-next_steps.
    ENDIF.
    IF payload->critical-only_b IS NOT INITIAL.
      APPEND |{ role_b } grants critical authorizations { role_a } does not; check them with run_critical_access_check | &&
             |(scope roles, role { role_b }) before assigning it.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD check_role.
    result = to_upper( condense( name ) ).
    IF zcl_accx_domain_factory=>role_repo( )->exists( result ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Role { result } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_role( result ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display role { result } (S_USER_AGR, activity 03).| ).
    ENDIF.
  ENDMETHOD.

  METHOD content_of.
    DATA hidden_objects TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.
    DATA roles          TYPE zif_accx_role_repo=>ty_roles.

    DATA(repo) = zcl_accx_domain_factory=>role_repo( ).
    IF info-composite = abap_true.
      LOOP AT info-children INTO DATA(child).
        IF ctx->guard( )->can_display_role( CONV #( child ) ) = abap_true.
          APPEND CONV agr_name( child ) TO roles.
        ELSE.
          hidden += 1.
        ENDIF.
      ENDLOOP.
    ELSE.
      roles = VALUE #( ( role ) ).
    ENDIF.

    LOOP AT roles INTO DATA(single).
      LOOP AT repo->get_authorization_values( single ) INTO DATA(value).
        IF object IS NOT INITIAL AND value-object <> object.
          CONTINUE.
        ENDIF.
        IF ctx->guard( )->can_display_authorization( value-object ) = abap_false.
          INSERT value-object INTO TABLE hidden_objects.
          CONTINUE.
        ENDIF.
        APPEND value TO result-values.
      ENDLOOP.
      " derived roles have no menu of their own: PFCG shows the reference role's
      DATA(menu_role) = single.
      DATA(reference) = COND agr_name( WHEN single = role THEN info-derived_from ELSE repo->get_role_info( single )-derived_from ).
      IF reference IS NOT INITIAL.
        menu_role = reference.
      ENDIF.
      APPEND LINES OF repo->get_transactions( menu_role ) TO result-transactions.
      LOOP AT zcl_accx_domain_factory=>fiori_repo( )->get_role_content( VALUE #( ( menu_role ) ) ) INTO DATA(content)
           WHERE type = zif_accx_fiori_repo=>co_content_type-catalog.
        APPEND content-id TO result-catalogs.
      ENDLOOP.
      LOOP AT repo->get_maintenance( single )-org_levels INTO DATA(level).
        APPEND |{ level-level }={ COND #( WHEN level-low IS INITIAL AND level-high IS INITIAL THEN `(empty)` ELSE level-low ) }| &&
               |{ COND #( WHEN level-high IS NOT INITIAL THEN |-{ level-high }| ) }| TO result-org_levels.
      ENDLOOP.
    ENDLOOP.
    hidden += lines( hidden_objects ).
  ENDMETHOD.

  METHOD side.
    result = VALUE #( role         = role
                      role_type    = COND #( WHEN info-composite = abap_true THEN `composite`
                                             WHEN info-derived_from IS NOT INITIAL THEN `derived`
                                             ELSE `single` )
                      derived_from = info-derived_from
                      users        = VALUE #( counts[ role = role ]-users OPTIONAL ) ).
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

  METHOD diff_line.
    IF diff-only_a IS INITIAL AND diff-only_b IS INITIAL.
      result = |\n- { label }: no differences ({ diff-common } in both)|.
      RETURN.
    ENDIF.
    result = |\n- { label }: { diff-common } in both|.
    IF diff-only_a IS NOT INITIAL.
      result = |{ result }\n  - only { payload-role_a-role }: { listed( diff-only_a ) }|.
    ENDIF.
    IF diff-only_b IS NOT INITIAL.
      result = |{ result }\n  - only { payload-role_b-role }: { listed( diff-only_b ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    DATA(a) = <payload>-role_a.
    DATA(b) = <payload>-role_b.

    result-summary = |Roles **{ a-role }** ({ a-role_type }, { a-users } users) and **{ b-role }** ({ b-role_type }, { b-users } users)| &&
                     |{ COND #( WHEN <payload>-relation IS NOT INITIAL THEN |: { <payload>-relation }| ) }| &&
                     |{ COND #( WHEN <payload>-object IS NOT INITIAL THEN |, object { <payload>-object } only| ) }.|.
    IF <payload>-identical = abap_true.
      result-summary = |{ result-summary } They grant the same{ COND #( WHEN <payload>-object IS INITIAL THEN ` menu and` ) } | &&
                       |authorization values ({ <payload>-values-common }).|.
    ENDIF.
    result-summary = result-summary && diff_line( label = `Authorization values` diff = <payload>-values payload = <payload> ).
    IF <payload>-objects_only_a IS NOT INITIAL.
      result-summary = |{ result-summary }\n- Objects only in { a-role }: { listed( <payload>-objects_only_a ) }|.
    ENDIF.
    IF <payload>-objects_only_b IS NOT INITIAL.
      result-summary = |{ result-summary }\n- Objects only in { b-role }: { listed( <payload>-objects_only_b ) }|.
    ENDIF.
    IF <payload>-object IS INITIAL.
      result-summary = result-summary && diff_line( label = `Menu transactions` diff = <payload>-transactions payload = <payload> ).
      IF <payload>-catalogs-common > 0 OR <payload>-catalogs-only_a IS NOT INITIAL OR <payload>-catalogs-only_b IS NOT INITIAL.
        result-summary = result-summary && diff_line( label = `Launchpad catalogs` diff = <payload>-catalogs payload = <payload> ).
      ENDIF.
      IF a-role_type = `composite` OR b-role_type = `composite`.
        result-summary = result-summary && diff_line( label = `Single roles` diff = <payload>-single_roles payload = <payload> ).
      ENDIF.
      IF <payload>-org_levels-common > 0 OR <payload>-org_levels-only_a IS NOT INITIAL OR <payload>-org_levels-only_b IS NOT INITIAL.
        result-summary = result-summary && diff_line( label = `Organizational levels` diff = <payload>-org_levels payload = <payload> ).
      ENDIF.
    ENDIF.
    IF <payload>-critical-only_a IS NOT INITIAL OR <payload>-critical-only_b IS NOT INITIAL.
      result-summary = result-summary && diff_line( label = `**Critical authorizations**` diff = <payload>-critical payload = <payload> ).
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nLists cut to max_rows per side - filter by object for the full picture.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } single roles or objects left out due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

