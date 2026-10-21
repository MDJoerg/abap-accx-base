"! <p class="shorttext synchronized">Access Explorer tool: draft_role_change</p>
"! Plans a role change without writing anything (decision E10, stage 2): which
"! authorization values PFCG would add from the SU24 proposals of new
"! transactions and from the authorization defaults of new launchpad catalogs,
"! which start authorizations leave the role with removed catalogs, which
"! fields stay open, which critical authorizations and combinations the
"! change introduces, whom it affects, the PFCG steps and a change request text.
"! For composite roles: the single roles to add or remove and the critical
"! authorizations the composite role gains or loses with them. New single roles
"! (create): empty or as a copy of another role, e.g. an SAP template role;
"! everything critical they grant counts as added.
CLASS zcl_accx_t_draft_role_change DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `draft_role_change`.

    CONSTANTS: BEGIN OF co_status,
                 add              TYPE string VALUE `add`,
                 remove           TYPE string VALUE `remove`,
                 already_in_role  TYPE string VALUE `already_in_role`,
                 granted_by_value TYPE string VALUE `granted_by_value`,
                 not_in_role      TYPE string VALUE `not_in_role`,
                 unknown          TYPE string VALUE `unknown`,
                 covered          TYPE string VALUE `covered`,
                 open             TYPE string VALUE `open`,
                 org_level        TYPE string VALUE `org_level`,
                 review           TYPE string VALUE `review`,
                 "! a composite role cannot contain composite roles
                 composite        TYPE string VALUE `composite`,
               END OF co_status.

    TYPES: BEGIN OF ty_transaction,
             transaction TYPE string,
             "! add or remove
             action      TYPE string,
             status      TYPE string,
             note        TYPE string,
           END OF ty_transaction,
           ty_transactions TYPE STANDARD TABLE OF ty_transaction WITH EMPTY KEY.

    TYPES: BEGIN OF ty_catalog,
             catalog           TYPE string,
             title             TYPE string,
             "! add or remove
             action            TYPE string,
             "! add, already_in_role, unknown; remove, not_in_role
             status            TYPE string,
             "! target mappings in the catalog
             apps              TYPE i,
             "! authorization defaults PFCG adds below the catalog node (removal: the nodes below it): transactions
             transactions      TYPE string_table,
             "! gateway services (S_SERVICE)
             services          TYPE string_table,
             "! of these, services not active in the gateway
             inactive_services TYPE string_table,
             "! applications started with S_START (Web Dynpro WDYA, OData V4 group G4BA), as TYPE NAME
             start_objects     TYPE string_table,
             "! removal: other roles containing the catalog; their users keep its apps
             other_roles       TYPE string_table,
             note              TYPE string,
           END OF ty_catalog,
           ty_catalogs TYPE STANDARD TABLE OF ty_catalog WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role_entry,
             role             TYPE string,
             description      TYPE string,
             "! add or remove
             action           TYPE string,
             "! add, already_in_role, unknown, composite; remove, not_in_role
             status           TYPE string,
             "! other composite roles containing the single role
             other_composites TYPE string_table,
             note             TYPE string,
           END OF ty_role_entry,
           ty_role_entries TYPE STANDARD TABLE OF ty_role_entry WITH EMPTY KEY.

    TYPES: BEGIN OF ty_value,
             object TYPE string,
             field  TYPE string,
             value  TYPE string,
             "! menu, start check or SU24 with the transaction, catalog with the service, or manual
             source TYPE string,
             "! covered (role allows it already), add, open (to be maintained), org_level,
             "! remove (start authorization of a removed catalog), review (removal)
             status TYPE string,
           END OF ty_value,
           ty_values TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             role                 TYPE string,
             description          TYPE string,
             "! the role does not exist yet and is created (empty, or as a copy of copy_from)
             create               TYPE abap_bool,
             "! new role: the role it is copied from (menu, authorization data, texts; no users)
             copy_from            TYPE string,
             "! composite role: the change adds or removes single roles
             composite            TYPE abap_bool,
             "! role to change in PFCG (the reference role of a derived role)
             change_target        TYPE string,
             derived_from         TYPE string,
             "! roles derived from the change target; they inherit the change
             derived_roles        TYPE string_table,
             "! composite roles containing the role
             composite_roles      TYPE string_table,
             "! users holding the change target or its derived roles today
             assigned_users       TYPE i,
             for_user             TYPE string,
             for_user_has_role    TYPE abap_bool,
             transactions         TYPE ty_transactions,
             catalogs             TYPE ty_catalogs,
             "! composite role: single roles to add or remove
             roles                TYPE ty_role_entries,
             authorization_values TYPE ty_values,
             "! critical authorizations and combinations the role does not grant today but would after the change
             critical_added       TYPE zif_accx_critical_rules=>ty_hits,
             "! composite role: critical authorizations and combinations it no longer grants after the change
             critical_removed     TYPE zif_accx_critical_rules=>ty_hits,
             steps                TYPE string_table,
             request_text         TYPE string,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_cached_proposals,
             name      TYPE string,
             type      TYPE string,
             proposals TYPE zif_accx_proposal_source=>ty_proposals,
           END OF ty_cached_proposals.

    DATA proposal_cache TYPE HASHED TABLE OF ty_cached_proposals WITH UNIQUE KEY name type.

    "! SU24 proposals of a transaction (TR) or an OData service or application hash (HT)
    METHODS proposals_of
      IMPORTING !name         TYPE csequence
                !type         TYPE csequence DEFAULT 'TR'
      RETURNING VALUE(result) TYPE zif_accx_proposal_source=>ty_proposals.

    "! Start check and SU24 proposals of a transaction PFCG adds to the menu
    METHODS plan_transaction
      IMPORTING !tcode      TYPE csequence
                !label      TYPE string
                !auth       TYPE csequence
                !before     TYPE zif_accx_critical_rules=>ty_auth_values
      CHANGING  !payload    TYPE ty_payload
                !new_values TYPE zif_accx_critical_rules=>ty_auth_values.

    "! Authorization defaults of a launchpad catalog as PFCG adds them, and their SU24 proposals
    METHODS plan_catalog
      IMPORTING !catalog_id    TYPE string
                !position      TYPE i
                !menu_catalogs TYPE zif_accx_fiori_repo=>ty_role_catalogs
                !before        TYPE zif_accx_critical_rules=>ty_auth_values
      CHANGING  !payload       TYPE ty_payload
                !new_values    TYPE zif_accx_critical_rules=>ty_auth_values.

    "! Catalogs to remove: the nodes below the catalog node and the start authorizations and
    "! SU24 objects that leave the role with them (unless other menu entries bring them too)
    METHODS plan_catalog_removals
      IMPORTING !catalog_ids   TYPE string_table
                !menu_catalogs TYPE zif_accx_fiori_repo=>ty_role_catalogs
                !before        TYPE zif_accx_critical_rules=>ty_auth_values
      CHANGING  !payload       TYPE ty_payload.

    "! Does an authorization of the object allow the value (range: both ends)?
    METHODS covered
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
                !object       TYPE csequence
                !field        TYPE csequence
                !low          TYPE csequence
                !high         TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE abap_bool.

    "! Classify one value PFCG would add and remember it for the critical evaluation
    METHODS plan_value
      IMPORTING !object     TYPE csequence
                !field      TYPE csequence
                !low        TYPE csequence
                !high       TYPE csequence OPTIONAL
                !source     TYPE string
                !auth       TYPE csequence
                !before     TYPE zif_accx_critical_rules=>ty_auth_values
      CHANGING  !payload    TYPE ty_payload
                !new_values TYPE zif_accx_critical_rules=>ty_auth_values.

    METHODS value_text
      IMPORTING !low          TYPE csequence
                !high         TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE string.

    METHODS critical_hits
      IMPORTING !rules        TYPE REF TO zif_accx_critical_rules
                !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_hits.

    "! Single roles to add to or remove from a composite role, and the critical authorizations
    "! and combinations the composite role gains or loses with them
    METHODS plan_composite
      IMPORTING !info    TYPE zif_accx_role_repo=>ty_role_info
                !adds    TYPE string_table
                !removes TYPE string_table
                !guard   TYPE REF TO zif_accx_caller_guard
      CHANGING  !payload TYPE ty_payload.

    "! Checks for a new role: name free and in the customer namespace, copy source an existing single role
    METHODS check_new_role
      IMPORTING !role      TYPE string
                !copy_from TYPE string
                !guard     TYPE REF TO zif_accx_caller_guard
      RAISING   zcx_accx_error.

    METHODS build_steps
      IMPORTING !reason  TYPE string
      CHANGING  !payload TYPE ty_payload.

    METHODS build_composite_steps
      IMPORTING !reason  TYPE string
      CHANGING  !payload TYPE ty_payload.

    METHODS render_composite
      IMPORTING !payload      TYPE ty_payload
      RETURNING VALUE(result) TYPE string.

    METHODS fields_with_status
      IMPORTING !payload      TYPE ty_payload
                !status       TYPE string
                !source       TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE string.

    METHODS critical_text
      IMPORTING !hits         TYPE zif_accx_critical_rules=>ty_hits
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_draft_role_change IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Draft role change`
      description = |Plans a change of a role without changing anything: adding or removing transactions in the role | &&
                    |menu, adding or removing launchpad catalogs and adding authorization values manually. For new transactions | &&
                    |it shows the authorization values PFCG would add from the SU24 proposals and the start check; for new | &&
                    |catalogs the authorization defaults of their apps (S_SERVICE of the OData services, transactions, S_START) | &&
                    |with their SU24 proposals; for removed catalogs the start authorizations that leave the role with the nodes | &&
                    |below the catalog and the other roles that still give the catalog. It shows which values the role already | &&
                    |allows, which fields stay open or need organizational levels, and which critical authorizations or critical | &&
                    |combinations (SUIM) the role would gain. For a composite role it plans adding or removing single roles | &&
                    |(add_roles, remove_roles) with the critical authorizations the composite role gains or loses. With create = true | &&
                    |it plans a new single role in the customer namespace, empty or as a copy of copy_from (e.g. an SAP template | &&
                    |role, which must not be changed itself); everything critical the new role grants counts as added. It names the role to change (the reference role of a derived role), | &&
                    |derived and composite roles and the number of users affected, and returns the PFCG steps and a change | &&
                    |request text. Use it after explain_missing_access or diagnose_fiori_app_access to turn a recommendation | &&
                    |into a request.|
      group       = zif_accx_types=>co_group-role
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_DRAFT_ROLE_CHANGE\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `role`
                                      description = `Role to change: a single role, or a composite role with add_roles/remove_roles.`
                                      required    = abap_true
                                      maximum     = 30 ) )
                             ( param( name        = `create`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = |true: role does not exist yet and is created as a single role (customer | &&
                                                    |namespace), empty or as a copy of copy_from; the other changes apply to the new role.| ) )
                             ( param( name        = `copy_from`
                                      description = |With create: existing single role to copy (menu, authorization data, texts; | &&
                                                    |no users), e.g. an SAP template role.|
                                      maximum     = 30 ) )
                             ( param( name        = `description`
                                      description = `With create: description of the new role.`
                                      maximum     = 80 ) )
                             ( param( name        = `add_transactions`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = `Transactions to add to the role menu.` ) )
                             ( param( name        = `remove_transactions`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = `Transactions to remove from the role menu.` ) )
                             ( param( name        = `add_catalogs`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |Launchpad catalogs to add to the role menu (catalog ids, e.g. | &&
                                                    |SAP_BASIS_BC_UI_FLD); PFCG adds the start authorizations of their apps.| ) )
                             ( param( name        = `remove_catalogs`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = |Launchpad catalogs to remove from the role menu, with the authorization | &&
                                                    |default nodes PFCG added below them.| ) )
                             ( param( name        = `add_roles`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = `Composite role only: single roles to add to it.` ) )
                             ( param( name        = `remove_roles`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = `Composite role only: single roles to remove from it.` ) )
                             ( param( name        = `object`
                                      description = `Authorization object to add manually (only if no transaction brings it), e.g. S_TABU_NAM.`
                                      maximum     = 10 ) )
                             ( param( name        = `values`
                                      kind        = zif_accx_types=>co_kind-string_list
                                      description = `With object: values to add as FIELD=VALUE; a field may appear several times.` ) )
                             ( param( name        = `for_user`
                                      description = `User who needs the access; the plan checks whether the user holds the role.`
                                      maximum     = 12 ) )
                             ( param( name        = `reason`
                                      description = `Business reason for the change request text.`
                                      maximum     = 255 ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA new_values TYPE zif_accx_critical_rules=>ty_auth_values.
    DATA targets    TYPE zif_accx_role_repo=>ty_roles.

    DATA(role)     = to_upper( condense( args->get_string( `role` ) ) ).
    DATA(object)   = to_upper( condense( args->get_string( `object` ) ) ).
    DATA(for_user) = to_upper( condense( args->get_string( `for_user` ) ) ).
    DATA(reason)   = condense( args->get_string( `reason` ) ).
    DATA(create)   = args->get_boolean( name = `create` default = abap_false ).
    DATA(copy_from) = to_upper( condense( args->get_string( `copy_from` ) ) ).
    DATA(description) = condense( args->get_string( `description` ) ).
    DATA(adds)     = VALUE string_table( FOR a IN args->get_strings( `add_transactions` ) ( to_upper( condense( a ) ) ) ).
    DATA(removes)  = VALUE string_table( FOR r IN args->get_strings( `remove_transactions` ) ( to_upper( condense( r ) ) ) ).
    DATA(catalog_ids) = VALUE string_table( FOR k IN args->get_strings( `add_catalogs` ) ( condense( k ) ) ).
    DATA(catalog_removals) = VALUE string_table( FOR q IN args->get_strings( `remove_catalogs` ) ( condense( q ) ) ).
    DATA(manual)   = zcl_accx_search_criteria=>value_criteria( args->get_strings( `values` ) ).
    DELETE adds WHERE table_line IS INITIAL.
    DELETE removes WHERE table_line IS INITIAL.
    DELETE catalog_ids WHERE table_line IS INITIAL.
    DATA(role_adds)    = VALUE string_table( FOR g IN args->get_strings( `add_roles` ) ( to_upper( condense( g ) ) ) ).
    DATA(role_removes) = VALUE string_table( FOR h IN args->get_strings( `remove_roles` ) ( to_upper( condense( h ) ) ) ).
    DELETE catalog_removals WHERE table_line IS INITIAL.
    DELETE role_adds WHERE table_line IS INITIAL.
    DELETE role_removes WHERE table_line IS INITIAL.
    DATA(single_changes) = xsdbool( adds IS NOT INITIAL OR removes IS NOT INITIAL OR catalog_ids IS NOT INITIAL
                                    OR catalog_removals IS NOT INITIAL OR object IS NOT INITIAL ).
    DATA(role_changes)   = xsdbool( role_adds IS NOT INITIAL OR role_removes IS NOT INITIAL ).

    IF single_changes = abap_false AND role_changes = abap_false AND ( create = abap_false OR copy_from IS INITIAL ).
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = |Give add_transactions, remove_transactions, add_catalogs, remove_catalogs or object with values | &&
                  |(single role), add_roles, remove_roles (composite role), or create = true with copy_from (new role).| ).
    ENDIF.
    IF create = abap_false AND copy_from IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `copy_from creates a new role; set create = true as well.` ).
    ENDIF.
    IF create = abap_true AND role_changes = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `New roles are single roles; create composite roles in PFCG.` ).
    ENDIF.
    IF manual IS NOT INITIAL AND object IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `values need the authorization object they belong to (parameter object).` ).
    ENDIF.

    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(evaluator) = zcl_accx_domain_factory=>auth_evaluator( ).
    IF create = abap_true.
      check_new_role( role = role copy_from = copy_from guard = ctx->guard( ) ).
    ELSEIF role_repo->exists( CONV #( role ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Role { role } does not exist; plan it with create = true to create it.| ).
    ELSEIF ctx->guard( )->can_display_role( CONV #( role ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-denied message = |You may not display role { role }.| ).
    ENDIF.
    IF object IS NOT INITIAL AND evaluator->object_exists( CONV #( object ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Authorization object { object } does not exist.| ).
    ENDIF.

    " a new role: nothing of the copy source but its description carries over
    DATA(info) = COND zif_accx_role_repo=>ty_role_info(
      WHEN create = abap_false THEN role_repo->get_role_info( CONV #( role ) )
      ELSE VALUE #( role        = CONV #( role )
                    description = COND #( WHEN description IS NOT INITIAL THEN description
                                          WHEN copy_from IS NOT INITIAL THEN role_repo->get_role_info( CONV #( copy_from ) )-description ) ) ).
    IF info-composite = abap_true AND single_changes = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = |{ role } is a composite role and holds no authorizations itself. Draft the change for one of its | &&
                  |single roles ({ concat_lines_of( table = info-children sep = `, ` ) }) or for a role to add to it | &&
                  |(add_roles).| ).
    ELSEIF info-composite = abap_false AND role_changes = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-invalid
        message = |add_roles and remove_roles change composite roles; { role } is a single role| &&
                  |{ COND #( WHEN info-parents IS NOT INITIAL
                             THEN | (contained in { concat_lines_of( table = info-parents sep = `, ` ) })| ) }.| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( role            = role
                                    description     = info-description
                                    composite       = info-composite
                                    derived_from    = info-derived_from
                                    change_target   = COND #( WHEN info-derived_from IS NOT INITIAL THEN info-derived_from ELSE role )
                                    composite_roles = info-parents
                                    create          = create
                                    copy_from       = copy_from
                                    for_user        = for_user ).
    result-data = payload.
    DATA(target) = CONV agr_name( payload->change_target ).
    payload->derived_roles = VALUE #( FOR d IN role_repo->get_derived_roles( target ) ( CONV #( d ) ) ).

    " impact: users of the change target and of all roles inheriting from it
    targets = VALUE #( ( target ) ).
    LOOP AT payload->derived_roles INTO DATA(derived).
      APPEND CONV agr_name( derived ) TO targets.
    ENDLOOP.
    LOOP AT role_repo->count_assigned_users( targets ) INTO DATA(count).
      payload->assigned_users += count-users.
    ENDLOOP.

    IF info-composite = abap_true.
      plan_composite( EXPORTING info = info adds = role_adds removes = role_removes guard = ctx->guard( )
                      CHANGING  payload = payload->* ).
    ELSE.
      " a new role starts with what it is copied from, or with nothing
      DATA(source) = COND agr_name( WHEN create = abap_false THEN target ELSE copy_from ).
      DATA(before) = COND zif_accx_critical_rules=>ty_auth_values(
                       WHEN create = abap_false THEN role_repo->get_authorization_values( CONV #( role ) )
                       WHEN source IS NOT INITIAL THEN role_repo->get_authorization_values( source ) ).
      DATA(menu)   = COND #( WHEN source IS NOT INITIAL THEN role_repo->get_transactions( source ) ).

      " transactions to add: start check and SU24 proposals against what the role allows today
      LOOP AT adds INTO DATA(add).
        DATA(position) = sy-tabix.
        IF evaluator->transaction_exists( CONV #( add ) ) = abap_false.
          APPEND VALUE #( transaction = add action = co_status-add status = co_status-unknown
                          note = `transaction does not exist` ) TO payload->transactions.
          CONTINUE.
        ENDIF.
        IF line_exists( menu[ table_line = add ] ).
          APPEND VALUE #( transaction = add action = co_status-add status = co_status-already_in_role
                          note = `already in the role menu` ) TO payload->transactions.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( transaction = add action = co_status-add status = co_status-add
                        note = COND #( WHEN covered( values = before object = `S_TCODE` field = `TCD` low = add ) = abap_true
                                       THEN `S_TCODE already allows it through a range or pattern; adding it to the menu adds its SU24 proposals` ) )
          TO payload->transactions.
        plan_transaction( EXPORTING tcode = add label = add auth = |NT{ position }| before = before
                          CHANGING  payload = payload->* new_values = new_values ).
      ENDLOOP.

      " catalogs to add: authorization defaults of their apps and the SU24 proposals of these;
      " catalogs to remove: the start authorizations below their nodes
      IF catalog_ids IS NOT INITIAL OR catalog_removals IS NOT INITIAL.
        DATA(menu_catalogs) = COND #( WHEN source IS NOT INITIAL
                                      THEN zcl_accx_domain_factory=>fiori_repo( )->get_role_catalogs( VALUE #( ( source ) ) ) ).
        LOOP AT catalog_ids INTO DATA(catalog_id).
          plan_catalog( EXPORTING catalog_id = catalog_id position = sy-tabix menu_catalogs = menu_catalogs before = before
                        CHANGING  payload = payload->* new_values = new_values ).
        ENDLOOP.
        IF catalog_removals IS NOT INITIAL.
          plan_catalog_removals( EXPORTING catalog_ids = catalog_removals menu_catalogs = menu_catalogs before = before
                                 CHANGING  payload = payload->* ).
        ENDIF.
      ENDIF.

      " transactions to remove: objects only they propose are candidates for review
      LOOP AT removes INTO DATA(remove).
        IF line_exists( menu[ table_line = remove ] ).
          APPEND VALUE #( transaction = remove action = co_status-remove status = co_status-remove ) TO payload->transactions.
          DATA(still_proposed) = VALUE string_table( ).
          LOOP AT menu INTO DATA(other) WHERE table_line <> remove.
            IF line_exists( removes[ table_line = other ] ).
              CONTINUE.
            ENDIF.
            LOOP AT proposals_of( other )-objects INTO DATA(other_object) WHERE proposed = abap_true.
              APPEND CONV string( other_object-object ) TO still_proposed.
            ENDLOOP.
          ENDLOOP.
          LOOP AT proposals_of( remove )-objects INTO DATA(own_object) WHERE proposed = abap_true.
            IF NOT line_exists( still_proposed[ table_line = own_object-object ] )
               AND line_exists( before[ object = own_object-object ] )
               AND NOT line_exists( payload->authorization_values[ object = own_object-object status = co_status-review ] ).
              APPEND VALUE #( object = own_object-object source = |SU24 { remove }| status = co_status-review ) TO payload->authorization_values.
            ENDIF.
          ENDLOOP.
        ELSEIF covered( values = before object = `S_TCODE` field = `TCD` low = remove ) = abap_true.
          APPEND VALUE #( transaction = remove action = co_status-remove status = co_status-granted_by_value
                          note = `not in the menu, but a range or pattern in S_TCODE allows it; restrict that value` ) TO payload->transactions.
        ELSE.
          APPEND VALUE #( transaction = remove action = co_status-remove status = co_status-not_in_role
                          note = `the role neither contains nor allows it` ) TO payload->transactions.
        ENDIF.
      ENDLOOP.

      " manual authorization
      LOOP AT manual INTO DATA(criterion).
        LOOP AT criterion-values INTO DATA(manual_value).
          plan_value( EXPORTING object = object field = criterion-field low = manual_value
                                source = `manual` auth = `NMANUAL`
                                before = before
                      CHANGING  payload = payload->* new_values = new_values ).
        ENDLOOP.
      ENDLOOP.
      IF object IS NOT INITIAL AND manual IS INITIAL.
        APPEND VALUE #( object = object source = `manual` status = co_status-open ) TO payload->authorization_values.
      ENDIF.

      " critical authorizations the role would gain (open fields and org levels are not evaluated);
      " a new role gains everything it grants
      IF new_values IS NOT INITIAL OR create = abap_true.
        DATA(rules) = zcl_accx_domain_factory=>critical_rules( ).
        DATA(hits_before) = COND #( WHEN create = abap_false THEN critical_hits( rules = rules values = before ) ).
        DATA(after) = before.
        APPEND LINES OF new_values TO after.
        LOOP AT critical_hits( rules = rules values = after ) INTO DATA(hit).
          IF NOT line_exists( hits_before[ rule = hit-rule ] ).
            APPEND hit TO payload->critical_added.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF for_user IS NOT INITIAL.
      DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
      IF user_repo->exists( CONV #( for_user ) ) = abap_false.
        RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { for_user } does not exist.| ).
      ENDIF.
      IF ctx->guard( )->can_display_user( CONV #( for_user ) ) = abap_false.
        RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-denied message = |You may not display user { for_user }.| ).
      ENDIF.
      DATA(assignments) = user_repo->get_role_assignments( CONV #( for_user ) ).
      payload->for_user_has_role = xsdbool( line_exists( assignments[ role = CONV agr_name( role ) active = abap_true ] ) ).
    ENDIF.

    IF info-composite = abap_true.
      build_composite_steps( EXPORTING reason = reason CHANGING payload = payload->* ).
      result-total_count = lines( payload->roles ).
      result-sources = VALUE #( ( `AGR_DEFINE, AGR_AGRS, AGR_USERS (composite and single roles)` )
                                ( `AGR_1251 (authorizations of the single roles)` )
                                ( `USCRAUTHID, USCRAUTH, USRCOMB, USCRCOMID (critical authorizations)` ) ).
    ELSE.
      build_steps( EXPORTING reason = reason CHANGING payload = payload->* ).
      result-total_count = lines( payload->authorization_values ).
      result-sources = VALUE #( ( `AGR_DEFINE, AGR_TCODES, AGR_1251, AGR_AGRS, AGR_USERS (role)` )
                                ( `USOBX_C, USOBT_C (SU24 proposals), TSTCA (start check)` )
                                ( `USCRAUTHID, USCRAUTH, USRCOMB, USCRCOMID (critical authorizations)` ) ).
    ENDIF.
    IF catalog_ids IS NOT INITIAL.
      APPEND |/UI2/FDM_PUBLIC_API, AGR_HIER, AGR_BUFFI (catalogs), /UI2/CL_CATALOG_DETAIL (authorization defaults as | &&
             |PFCG reads them), /IWFND/I_MED_SRH (service activation)| TO result-sources.
    ENDIF.
    IF catalog_removals IS NOT INITIAL.
      APPEND `AGR_HIER, AGR_BUFFI (catalog nodes and the nodes below them), USOBHASH (service and application hashes)` TO result-sources.
    ENDIF.
    IF info-derived_from IS NOT INITIAL.
      APPEND |{ role } is derived from { info-derived_from }: menu changes are made there and reach all | &&
             |{ lines( payload->derived_roles ) } derived roles.| TO result-warnings.
    ENDIF.
    IF payload->change_target CP 'SAP_*'.
      APPEND |{ payload->change_target } is an SAP template role; change a copy in the customer namespace (create = true, | &&
             |copy_from = { payload->change_target }).| TO result-warnings.
    ENDIF.
    IF create = abap_true AND copy_from IS NOT INITIAL.
      APPEND |AGR_DEFINE, AGR_TCODES, AGR_1251 of { copy_from } (copy source)| TO result-sources.
    ENDIF.
    LOOP AT payload->transactions INTO DATA(unknown) WHERE status = co_status-unknown.
      APPEND |Transaction { unknown-transaction } does not exist and is left out.| TO result-warnings.
    ENDLOOP.
    LOOP AT payload->catalogs INTO DATA(unknown_catalog) WHERE status = co_status-unknown OR status = co_status-not_in_role.
      APPEND |Catalog { unknown_catalog-catalog } is left out: { unknown_catalog-note }.| TO result-warnings.
    ENDLOOP.
    LOOP AT payload->roles INTO DATA(left_out)
         WHERE status = co_status-unknown OR status = co_status-not_in_role OR status = co_status-composite.
      APPEND |Role { left_out-role } is left out: { left_out-note }.| TO result-warnings.
    ENDLOOP.

    IF for_user IS NOT INITIAL.
      APPEND |After the change: check_user_access for { for_user } to confirm the access.| TO result-next_steps.
    ENDIF.
    IF create = abap_true.
      APPEND |After creating { role }: assign it with assign_role to the users who need it; nobody holds it yet.| TO result-next_steps.
    ELSE.
      APPEND |Use find_users with role { payload->change_target } to see the users affected.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD check_new_role.
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    IF role_repo->exists( CONV #( role ) ) = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Role { role } exists already; plan the change without create.| ).
    ENDIF.
    IF NOT ( role CP 'Z*' OR role CP 'Y*' ) OR role CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |{ role } is no customer role name; new roles start with Z or Y and use | &&
                                                    |letters, digits and underscores only.| ).
    ENDIF.
    IF copy_from IS INITIAL.
      RETURN.
    ENDIF.
    IF role_repo->exists( CONV #( copy_from ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |Role { copy_from } does not exist.| ).
    ENDIF.
    IF guard->can_display_role( CONV #( copy_from ) ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-denied message = |You may not display role { copy_from }.| ).
    ENDIF.
    DATA(source) = role_repo->get_role_info( CONV #( copy_from ) ).
    IF source-composite = abap_true.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |{ copy_from } is a composite role; copy single roles only (composite roles in PFCG).| ).
    ELSEIF source-derived_from IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |{ copy_from } is derived from { source-derived_from }; its copy would be derived | &&
                                                    |too - copy the reference role { source-derived_from } instead.| ).
    ENDIF.
  ENDMETHOD.

  METHOD plan_transaction.
    LOOP AT zcl_accx_domain_factory=>auth_evaluator( )->get_transaction_checks( CONV #( tcode ) ) INTO DATA(check).
      LOOP AT check-fields INTO DATA(check_field).
        plan_value( EXPORTING object = check-object field = check_field-field low = check_field-value
                              source = COND #( WHEN check-object = 'S_TCODE' THEN |menu { label }| ELSE |start check { label }| )
                              auth   = |{ auth }S|
                              before = before
                    CHANGING  payload = payload new_values = new_values ).
      ENDLOOP.
    ENDLOOP.
    LOOP AT proposals_of( tcode )-values INTO DATA(proposal).
      plan_value( EXPORTING object = proposal-object field = proposal-field low = proposal-low high = proposal-high
                            source = |SU24 { label }|
                            auth   = |{ auth }{ proposal-object }|
                            before = before
                  CHANGING  payload = payload new_values = new_values ).
    ENDLOOP.
  ENDMETHOD.

  METHOD plan_catalog.
    DATA(fiori_repo) = zcl_accx_domain_factory=>fiori_repo( ).
    TRY.
        DATA(catalog) = fiori_repo->get_catalog( catalog_id ).
      CATCH zcx_accx_error INTO DATA(error).
        APPEND VALUE #( catalog = catalog_id action = co_status-add status = co_status-unknown note = error->message ) TO payload-catalogs.
        RETURN.
    ENDTRY.
    IF catalog-catalog IS INITIAL.
      APPEND VALUE #( catalog = catalog_id action = co_status-add status = co_status-unknown
                      note    = `the catalog does not exist in the launchpad content` ) TO payload-catalogs.
      RETURN.
    ENDIF.
    DATA(entry) = VALUE ty_catalog( catalog = catalog-catalog title = catalog-title apps = lines( catalog-apps )
                                    action  = co_status-add status = co_status-add ).
    IF line_exists( menu_catalogs[ catalog = catalog-catalog ] ).
      entry-status = co_status-already_in_role.
      entry-note   = `already in the role menu`.
      APPEND entry TO payload-catalogs.
      RETURN.
    ENDIF.

    " the nodes PFCG adds below the catalog: transactions, and hashes of services (S_SERVICE)
    " or of other applications (S_START), each with its SU24 proposals
    DATA(defaults) = fiori_repo->get_catalog_defaults( catalog-catalog ).
    entry-note = concat_lines_of( table = defaults-messages sep = `; ` ).
    LOOP AT defaults-defaults INTO DATA(default).
      DATA(auth)  = |NC{ position }{ sy-tabix }|.
      DATA(label) = |{ default-obj_name } (catalog { catalog-catalog })|.
      IF default-type = 'TR'.
        IF zcl_accx_domain_factory=>auth_evaluator( )->transaction_exists( CONV #( default-name ) ) = abap_false.
          CONTINUE.
        ENDIF.
        APPEND default-name TO entry-transactions.
        plan_transaction( EXPORTING tcode = default-name label = label auth = auth before = before
                          CHANGING  payload = payload new_values = new_values ).
        CONTINUE.
      ENDIF.
      IF default-object = 'IWSG' OR default-object = 'IWSV'.
        IF default-object = 'IWSG'.
          APPEND default-obj_name TO entry-services.
          IF default-active = abap_false.
            APPEND default-obj_name TO entry-inactive_services.
          ENDIF.
        ENDIF.
        " PFCG collects the services of the menu in one S_SERVICE authorization
        plan_value( EXPORTING object = `S_SERVICE` field = `SRV_NAME` low = default-name source = |service { label }|
                              auth = |NC{ position }SRV| before = before
                    CHANGING  payload = payload new_values = new_values ).
        plan_value( EXPORTING object = `S_SERVICE` field = `SRV_TYPE` low = `HT` source = |service { label }|
                              auth = |NC{ position }SRV| before = before
                    CHANGING  payload = payload new_values = new_values ).
      ELSE.
        APPEND |{ default-object } { default-obj_name }| TO entry-start_objects.
        DATA(start_auth) = |NC{ position }{ default-object }|.
        plan_value( EXPORTING object = `S_START` field = `AUTHPGMID` low = default-pgmid source = |start { label }|
                              auth = start_auth before = before
                    CHANGING  payload = payload new_values = new_values ).
        plan_value( EXPORTING object = `S_START` field = `AUTHOBJTYP` low = default-object source = |start { label }|
                              auth = start_auth before = before
                    CHANGING  payload = payload new_values = new_values ).
        plan_value( EXPORTING object = `S_START` field = `AUTHOBJNAM` low = default-obj_name source = |start { label }|
                              auth = start_auth before = before
                    CHANGING  payload = payload new_values = new_values ).
      ENDIF.
      LOOP AT proposals_of( name = default-name type = 'HT' )-values INTO DATA(proposal).
        plan_value( EXPORTING object = proposal-object field = proposal-field low = proposal-low high = proposal-high
                              source = |SU24 { label }|
                              auth   = |{ auth }{ proposal-object }|
                              before = before
                    CHANGING  payload = payload new_values = new_values ).
      ENDLOOP.
    ENDLOOP.
    IF defaults-defaults IS INITIAL AND entry-note IS INITIAL.
      entry-note = `no authorization defaults`.
    ENDIF.
    APPEND entry TO payload-catalogs.
  ENDMETHOD.

  METHOD plan_value.
    DATA(status) = COND string( WHEN low CP '$*' THEN co_status-org_level
                                WHEN low IS INITIAL AND high IS INITIAL THEN co_status-open
                                WHEN covered( values = before object = object field = field low = low high = high ) = abap_true
                                THEN co_status-covered
                                ELSE co_status-add ).
    " PFCG adds a whole new authorization: values the role allows elsewhere are part of it too,
    " so they count for the critical evaluation (open fields and org levels are unknown)
    IF status = co_status-add OR status = co_status-covered.
      APPEND VALUE #( object = object auth = auth field = field low = low high = high ) TO new_values.
    ENDIF.
    DATA(text) = value_text( low = low high = high ).
    " the same value from several transactions is listed once
    IF line_exists( payload-authorization_values[ object = CONV string( object ) field = CONV string( field ) value = text ] ).
      RETURN.
    ENDIF.
    APPEND VALUE #( object = object field = field value = text source = source status = status ) TO payload-authorization_values.
  ENDMETHOD.

  METHOD covered.
    LOOP AT values INTO DATA(value) WHERE object = object AND field = field.
      IF zcl_accx_auth_value=>covers( value = CONV string( low ) low = value-low high = value-high ) = abap_true
         AND ( high IS INITIAL OR zcl_accx_auth_value=>covers( value = CONV string( high ) low = value-low high = value-high ) = abap_true ).
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD value_text.
    IF high IS INITIAL.
      result = low.
    ELSE.
      result = |{ low }-{ high }|.
    ENDIF.
  ENDMETHOD.

  METHOD proposals_of.
    ASSIGN proposal_cache[ name = name type = type ] TO FIELD-SYMBOL(<cached>).
    IF sy-subrc <> 0.
      DATA(source) = zcl_accx_domain_factory=>proposal_source( ).
      INSERT VALUE #( name      = name
                      type      = type
                      proposals = COND #( WHEN type = 'HT' THEN source->get_for_service( CONV #( name ) )
                                          ELSE source->get_for_transaction( CONV #( name ) ) ) )
        INTO TABLE proposal_cache ASSIGNING <cached>.
    ENDIF.
    result = <cached>-proposals.
  ENDMETHOD.

  METHOD critical_hits.
    result = rules->evaluate( values ).
    APPEND LINES OF rules->evaluate_combinations( result ) TO result.
  ENDMETHOD.

  METHOD critical_text.
    LOOP AT hits INTO DATA(hit).
      result = |{ result }{ COND #( WHEN result IS NOT INITIAL THEN `; ` ) }{ hit-text } ({ hit-rule }, { hit-level })|.
    ENDLOOP.
  ENDMETHOD.

  METHOD fields_with_status.
    LOOP AT payload-authorization_values INTO DATA(value) WHERE status = status.
      IF source IS NOT INITIAL AND value-source <> source.
        CONTINUE.
      ENDIF.
      DATA(item) = COND string( WHEN value-field IS INITIAL THEN value-object
                                WHEN status = co_status-add OR status = co_status-org_level OR status = co_status-remove
                                THEN |{ value-object } { value-field }={ value-value }|
                                ELSE |{ value-object }-{ value-field }| ).
      IF result NS item.
        result = |{ result }{ COND #( WHEN result IS NOT INITIAL THEN `, ` ) }{ item }|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_steps.
    DATA changes  TYPE string_table.
    DATA request  TYPE string_table.
    DATA inactive TYPE string_table.
    DATA effects  TYPE string_table.

    DATA(target)    = payload-change_target.
    DATA(to_add)    = concat_lines_of( table = VALUE string_table( FOR t IN payload-transactions
                                                                    WHERE ( status = co_status-add ) ( t-transaction ) ) sep = `, ` ).
    DATA(to_remove) = concat_lines_of( table = VALUE string_table( FOR t IN payload-transactions
                                                                    WHERE ( status = co_status-remove ) ( t-transaction ) ) sep = `, ` ).
    DATA(catalogs)  = concat_lines_of( table = VALUE string_table( FOR c IN payload-catalogs
                                                                    WHERE ( status = co_status-add ) ( c-catalog ) ) sep = `, ` ).
    DATA(catalogs_removed) = concat_lines_of( table = VALUE string_table( FOR c IN payload-catalogs
                                                                           WHERE ( status = co_status-remove ) ( c-catalog ) ) sep = `, ` ).
    LOOP AT payload-catalogs INTO DATA(catalog) WHERE status = co_status-add.
      LOOP AT catalog-inactive_services INTO DATA(service).
        IF NOT line_exists( inactive[ table_line = service ] ).
          APPEND service TO inactive.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT payload-catalogs INTO catalog WHERE status = co_status-remove.
      APPEND |{ catalog-catalog }: { catalog-note }| TO effects.
    ENDLOOP.
    DATA(added)     = fields_with_status( payload = payload status = co_status-add ).
    DATA(manual)    = fields_with_status( payload = payload status = co_status-add source = `manual` ).
    DATA(open)      = fields_with_status( payload = payload status = co_status-open ).
    DATA(org)       = fields_with_status( payload = payload status = co_status-org_level ).
    DATA(review)    = fields_with_status( payload = payload status = co_status-review ).
    DATA(removed)   = fields_with_status( payload = payload status = co_status-remove ).
    DATA(critical)  = critical_text( payload-critical_added ).
    DATA(removed_entries) = concat_lines_of( table = VALUE string_table( FOR e IN VALUE string_table( ( to_remove ) ( catalogs_removed ) )
                                                                          WHERE ( table_line IS NOT INITIAL ) ( e ) ) sep = `, ` ).

    IF payload-create = abap_true AND payload-copy_from IS NOT INITIAL.
      APPEND |PFCG: copy role { payload-copy_from } to { target } without user assignments| &&
             |{ COND #( WHEN payload-description IS NOT INITIAL THEN |, description "{ payload-description }"| ) }.| TO payload-steps.
      APPEND |create { target } as a copy of { payload-copy_from }| TO changes.
    ELSEIF payload-create = abap_true.
      APPEND |PFCG: create single role { target }| &&
             |{ COND #( WHEN payload-description IS NOT INITIAL THEN |, description "{ payload-description }"| ) }.| TO payload-steps.
      APPEND |create single role { target }| TO changes.
    ELSEIF target CP 'SAP_*'.
      APPEND |Copy { target } to the customer namespace in PFCG and change the copy; SAP template roles are overwritten by upgrades.|
        TO payload-steps.
    ENDIF.
    IF payload-derived_from IS NOT INITIAL.
      APPEND |{ payload-role } is derived from { target }: make the menu change in { target }.| TO payload-steps.
    ENDIF.
    IF to_add IS NOT INITIAL.
      APPEND |PFCG { target }, tab Menu: add transaction { to_add }.| TO payload-steps.
      APPEND |add { to_add } to the menu| TO changes.
    ENDIF.
    IF catalogs IS NOT INITIAL.
      APPEND |PFCG { target }, tab Menu: add launchpad catalog { catalogs } (Insert node > Launchpad catalog) with the | &&
             |authorization default values, so that PFCG adds the start authorizations of its apps (OData services, | &&
             |transactions) below the catalog node.| TO payload-steps.
      APPEND |add launchpad catalog { catalogs } to the menu| TO changes.
    ENDIF.
    IF to_remove IS NOT INITIAL.
      APPEND |PFCG { target }, tab Menu: remove transaction { to_remove }.| TO payload-steps.
      APPEND |remove { to_remove } from the menu| TO changes.
    ENDIF.
    IF catalogs_removed IS NOT INITIAL.
      APPEND |PFCG { target }, tab Menu: remove launchpad catalog { catalogs_removed } together with the authorization | &&
             |default nodes below it.| TO payload-steps.
      APPEND |remove launchpad catalog { catalogs_removed } from the menu| TO changes.
    ENDIF.
    IF to_add IS NOT INITIAL OR to_remove IS NOT INITIAL OR catalogs IS NOT INITIAL OR catalogs_removed IS NOT INITIAL
       OR payload-copy_from IS NOT INITIAL.
      APPEND |Tab Authorizations: change authorization data in expert mode "Read old status and merge with new data", so | &&
             |that the SU24 proposals are { COND #( WHEN to_add IS NOT INITIAL OR catalogs IS NOT INITIAL THEN `added`
                                                     ELSE `adjusted` ) }.| TO payload-steps.
    ENDIF.
    IF removed IS NOT INITIAL.
      APPEND |Check that these start authorizations are gone after the merge (PFCG keeps maintained or changed | &&
             |authorizations): { removed }.| TO payload-steps.
    ENDIF.
    IF open IS NOT INITIAL.
      APPEND |Maintain the open fields (yellow lights): { open }. Use the narrowest values the user needs.| TO payload-steps.
    ENDIF.
    IF org IS NOT INITIAL.
      APPEND |Maintain the organizational levels: { org }.| TO payload-steps.
    ENDIF.
    IF manual IS NOT INITIAL.
      APPEND |Add the authorization manually (Edit > Insert authorization > Manually) and maintain: { manual }.| TO payload-steps.
      APPEND |add { manual } manually| TO changes.
    ENDIF.
    IF review IS NOT INITIAL.
      APPEND |Check whether these objects are still needed; only { removed_entries } proposed them: { review }.| TO payload-steps.
    ENDIF.
    APPEND `Generate the profile.` TO payload-steps.
    IF payload-derived_roles IS NOT INITIAL.
      APPEND |Pass the change on to the derived roles and generate them: { concat_lines_of( table = payload-derived_roles sep = `, ` ) }.|
        TO payload-steps.
    ENDIF.
    IF payload-create = abap_false.
      APPEND |Run the user comparison (PFUD) so that the change reaches the { payload-assigned_users } assigned users.| TO payload-steps.
    ENDIF.
    IF inactive IS NOT INITIAL.
      APPEND |Activate the OData services { concat_lines_of( table = inactive sep = `, ` ) } in /IWFND/MAINT_SERVICE; | &&
             |their apps cannot load data otherwise.| TO payload-steps.
    ENDIF.
    IF payload-for_user IS NOT INITIAL AND payload-for_user_has_role = abap_false.
      APPEND |Assign role { payload-role } to { payload-for_user } with a validity period; the user does not hold it today.| TO payload-steps.
    ENDIF.
    IF critical IS NOT INITIAL.
      APPEND |Have the change approved by the owner of the critical authorizations it adds ({ critical }), or create a separate | &&
             |role for this access instead of extending { target }.| TO payload-steps.
    ENDIF.
    APPEND |Check the result with run_critical_access_check (scope roles, role { target }).| TO payload-steps.

    " change request text, one line per topic
    APPEND COND #( WHEN payload-create = abap_true THEN |Request for new role { target }|
                   ELSE |Change request for role { target }| ) TO request.
    " roles without a text show their name as description
    IF payload-description IS NOT INITIAL AND payload-description <> payload-role.
      APPEND |Role description: { payload-description }| TO request.
    ENDIF.
    IF payload-copy_from IS NOT INITIAL.
      APPEND |Copy of: { payload-copy_from } (menu and authorization data; no users)| TO request.
    ENDIF.
    IF payload-for_user IS NOT INITIAL.
      APPEND |Needed by: { payload-for_user }| TO request.
    ENDIF.
    IF reason IS NOT INITIAL.
      APPEND |Reason: { reason }| TO request.
    ENDIF.
    IF changes IS NOT INITIAL.
      APPEND |Changes: { concat_lines_of( table = changes sep = `; ` ) }| TO request.
    ELSE.
      APPEND `Changes: none needed, the role already contains the requested access` TO request.
    ENDIF.
    IF added IS NOT INITIAL.
      APPEND |Authorization values added: { added }| TO request.
    ENDIF.
    IF removed IS NOT INITIAL.
      APPEND |Start authorizations removed: { removed }| TO request.
    ENDIF.
    IF effects IS NOT INITIAL.
      APPEND |Launchpad: { concat_lines_of( table = effects sep = `; ` ) }| TO request.
    ENDIF.
    IF open IS NOT INITIAL.
      APPEND |Fields to be maintained: { open }| TO request.
    ENDIF.
    IF org IS NOT INITIAL.
      APPEND |Organizational levels: { org }| TO request.
    ENDIF.
    IF review IS NOT INITIAL.
      APPEND |Objects to review after the removal: { review }| TO request.
    ENDIF.
    IF inactive IS NOT INITIAL.
      APPEND |OData services to activate: { concat_lines_of( table = inactive sep = `, ` ) }| TO request.
    ENDIF.
    APPEND |Critical authorizations added (SUIM): { COND #( WHEN critical IS NOT INITIAL THEN critical ELSE `none` ) }| TO request.
    DATA(impact) = |Impact: { payload-assigned_users } users|.
    IF payload-derived_roles IS NOT INITIAL.
      impact = |{ impact }, derived roles { concat_lines_of( table = payload-derived_roles sep = `, ` ) }|.
    ENDIF.
    IF payload-composite_roles IS NOT INITIAL.
      impact = |{ impact }, contained in composite roles { concat_lines_of( table = payload-composite_roles sep = `, ` ) }|.
    ENDIF.
    APPEND impact TO request.
    IF payload-for_user IS NOT INITIAL AND payload-for_user_has_role = abap_false.
      APPEND |Also assign role { payload-role } to { payload-for_user }.| TO request.
    ENDIF.
    APPEND |Draft by Access Explorer { zif_accx_types=>co_release } on { sy-datum DATE = ISO }; nothing has been changed in the system.|
      TO request.
    payload-request_text = concat_lines_of( table = request sep = |\n| ).
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.
    IF <payload>-composite = abap_true.
      result-summary = render_composite( <payload> ).
      RETURN.
    ENDIF.

    DATA(adds)     = REDUCE i( INIT n = 0 FOR t IN <payload>-transactions WHERE ( status = co_status-add ) NEXT n = n + 1 ).
    DATA(removes)  = REDUCE i( INIT n = 0 FOR t IN <payload>-transactions WHERE ( status = co_status-remove ) NEXT n = n + 1 ).
    DATA(catalogs) = REDUCE i( INIT n = 0 FOR c IN <payload>-catalogs WHERE ( status = co_status-add ) NEXT n = n + 1 ).
    DATA(catalogs_removed) = REDUCE i( INIT n = 0 FOR c IN <payload>-catalogs WHERE ( status = co_status-remove ) NEXT n = n + 1 ).
    DATA(covered)  = REDUCE i( INIT n = 0 FOR v IN <payload>-authorization_values WHERE ( status = co_status-covered ) NEXT n = n + 1 ).
    DATA(added)    = fields_with_status( payload = <payload> status = co_status-add ).
    DATA(open)     = fields_with_status( payload = <payload> status = co_status-open ).
    DATA(removed)  = fields_with_status( payload = <payload> status = co_status-remove ).

    result-summary = |**Draft for { COND #( WHEN <payload>-create = abap_true THEN `new role` ELSE `role` ) } { <payload>-role }**|.
    IF <payload>-copy_from IS NOT INITIAL.
      result-summary = |{ result-summary } (copy of { <payload>-copy_from })|.
    ENDIF.
    IF <payload>-change_target <> <payload>-role.
      result-summary = |{ result-summary } (change in reference role { <payload>-change_target })|.
    ENDIF.
    result-summary = |{ result-summary }: { adds } { COND #( WHEN adds = 1 THEN `transaction` ELSE `transactions` ) } to add, | &&
                     |{ removes } to remove| &&
                     |{ COND #( WHEN line_exists( <payload>-catalogs[ action = co_status-add ] )
                                THEN |, { catalogs } { COND #( WHEN catalogs = 1 THEN `catalog` ELSE `catalogs` ) } to add| ) }| &&
                     |{ COND #( WHEN line_exists( <payload>-catalogs[ action = co_status-remove ] )
                                THEN |, { catalogs_removed } { COND #( WHEN catalogs_removed = 1 THEN `catalog` ELSE `catalogs` ) } | &&
                                     |to remove| ) }| &&
                     |; { <payload>-assigned_users } | &&
                     |{ COND #( WHEN <payload>-assigned_users = 1 THEN `user` ELSE `users` ) } affected. Nothing has been changed.|.

    LOOP AT <payload>-transactions INTO DATA(transaction) WHERE note IS NOT INITIAL.
      result-summary = |{ result-summary }\n- { transaction-transaction }: { transaction-note }|.
    ENDLOOP.
    LOOP AT <payload>-catalogs INTO DATA(catalog).
      result-summary = |{ result-summary }\n- Catalog { catalog-catalog }| &&
                       |{ COND #( WHEN catalog-title IS NOT INITIAL THEN | ({ catalog-title })| ) }: |.
      IF catalog-status <> co_status-add AND catalog-status <> co_status-remove.
        result-summary = |{ result-summary }{ catalog-note }|.
        CONTINUE.
      ENDIF.
      DATA(parts) = VALUE string_table( ).
      IF catalog-services IS NOT INITIAL.
        APPEND |S_SERVICE for { lines( catalog-services ) } OData | &&
               |{ COND #( WHEN lines( catalog-services ) = 1 THEN `service` ELSE `services` ) }| TO parts.
      ENDIF.
      IF catalog-transactions IS NOT INITIAL.
        APPEND |transactions { concat_lines_of( table = catalog-transactions sep = `, ` ) }| TO parts.
      ENDIF.
      IF catalog-start_objects IS NOT INITIAL.
        APPEND |S_START for { concat_lines_of( table = catalog-start_objects sep = `, ` ) }| TO parts.
      ENDIF.
      IF catalog-status = co_status-remove.
        result-summary = |{ result-summary }remove| &&
                         |{ COND #( WHEN catalog-apps > 0 THEN | ({ catalog-apps } apps)| ) }| &&
                         |{ COND #( WHEN parts IS NOT INITIAL
                                    THEN |; nodes below it: { concat_lines_of( table = parts sep = `, ` ) }| ) }; { catalog-note }|.
        CONTINUE.
      ENDIF.
      result-summary = |{ result-summary }{ catalog-apps } apps| &&
                       |{ COND #( WHEN parts IS NOT INITIAL
                                  THEN |; authorization defaults: { concat_lines_of( table = parts sep = `, ` ) }| ) }| &&
                       |{ COND #( WHEN catalog-inactive_services IS NOT INITIAL
                                  THEN |; not active: { concat_lines_of( table = catalog-inactive_services sep = `, ` ) }| ) }| &&
                       |{ COND #( WHEN catalog-note IS NOT INITIAL THEN |; { catalog-note }| ) }|.
    ENDLOOP.

    IF <payload>-critical_added IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Adds critical authorizations:** { critical_text( <payload>-critical_added ) }|.
    ELSEIF added IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nNo critical authorizations are added according to the SUIM rules|.
      IF open IS NOT INITIAL.
        result-summary = |{ result-summary } (open fields not evaluated)|.
      ENDIF.
      result-summary = |{ result-summary }.|.
    ENDIF.

    IF added IS NOT INITIAL OR covered > 0.
      result-summary = |{ result-summary }\n\n**Authorization values:** { covered } already allowed by the role|.
      IF added IS NOT INITIAL.
        result-summary = |{ result-summary }; new: { added }|.
      ENDIF.
      result-summary = |{ result-summary }.|.
    ENDIF.
    IF removed IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Start authorizations leaving the role:** { removed }.|.
    ENDIF.

    result-summary = |{ result-summary }\n\n**Steps in PFCG:**|.
    LOOP AT <payload>-steps INTO DATA(step).
      result-summary = |{ result-summary }\n{ sy-tabix }. { step }|.
    ENDLOOP.
    result-summary = |{ result-summary }\n\n**Change request text:**\n\n{ <payload>-request_text }|.
  ENDMETHOD.

  METHOD plan_catalog_removals.
    DATA removed        TYPE string_table.
    DATA still_proposed TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    DATA(fiori_repo) = zcl_accx_domain_factory=>fiori_repo( ).
    DATA(target) = CONV agr_name( payload-change_target ).

    " the role menu decides; a catalog deleted from the launchpad content can still be removed
    LOOP AT catalog_ids INTO DATA(catalog_id).
      DATA(in_menu) = ``.
      LOOP AT menu_catalogs INTO DATA(menu_catalog) WHERE role = target.
        IF to_upper( menu_catalog-catalog ) = to_upper( catalog_id ).
          in_menu = menu_catalog-catalog.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF in_menu IS INITIAL.
        APPEND VALUE #( catalog = catalog_id action = co_status-remove status = co_status-not_in_role
                        note    = `the role menu does not contain the catalog` ) TO payload-catalogs.
      ELSEIF NOT line_exists( removed[ table_line = in_menu ] ).
        APPEND in_menu TO removed.
      ENDIF.
    ENDLOOP.
    IF removed IS INITIAL.
      RETURN.
    ENDIF.

    " what stays in the menu, and the objects its entries still propose
    DATA(nodes) = fiori_repo->get_role_menu_nodes( target ).
    DATA(kept) = nodes.
    LOOP AT removed INTO DATA(removed_catalog).
      DELETE kept WHERE catalog = removed_catalog.
    ENDLOOP.
    LOOP AT kept INTO DATA(kept_node).
      LOOP AT proposals_of( name = kept_node-name type = kept_node-type )-objects INTO DATA(kept_object) WHERE proposed = abap_true.
        INSERT CONV string( kept_object-object ) INTO TABLE still_proposed.
      ENDLOOP.
    ENDLOOP.

    LOOP AT removed INTO DATA(catalog).
      DATA(entry) = VALUE ty_catalog( catalog = catalog action = co_status-remove status = co_status-remove ).
      TRY.
          DATA(content) = fiori_repo->get_catalog( catalog ).
          entry-title = content-title.
          entry-apps  = lines( content-apps ).
        CATCH zcx_accx_error ##NO_HANDLER.
          " launchpad content not readable: removed by its menu node only
      ENDTRY.
      LOOP AT fiori_repo->get_catalog_roles( VALUE #( ( catalog ) ) ) INTO DATA(other) WHERE role <> target.
        APPEND CONV string( other-role ) TO entry-other_roles.
      ENDLOOP.
      DATA(source) = |catalog { catalog }|.

      LOOP AT nodes INTO DATA(node) WHERE catalog = catalog.
        IF node-type = `TR`.
          APPEND node-name TO entry-transactions.
        ELSEIF node-object = 'IWSG'.
          APPEND node-obj_name TO entry-services.
        ELSEIF node-object <> 'IWSV' AND node-object IS NOT INITIAL.
          APPEND |{ node-object } { node-obj_name }| TO entry-start_objects.
        ENDIF.
        " another menu entry brings the same start authorization and proposals
        IF line_exists( kept[ type = node-type name = node-name ] ).
          CONTINUE.
        ENDIF.
        DATA(start) = COND #( WHEN node-type = `TR` THEN VALUE ty_value( object = `S_TCODE` field = `TCD` value = node-name )
                              WHEN node-object = 'IWSG' OR node-object = 'IWSV'
                              THEN VALUE ty_value( object = `S_SERVICE` field = `SRV_NAME` value = node-name )
                              WHEN node-obj_name IS NOT INITIAL
                              THEN VALUE ty_value( object = `S_START` field = `AUTHOBJNAM` value = node-obj_name ) ).
        IF start IS NOT INITIAL AND line_exists( before[ object = start-object field = start-field low = start-value ] )
           AND NOT line_exists( payload-authorization_values[ object = start-object field = start-field value = start-value ] ).
          start-source = source.
          start-status = co_status-remove.
          APPEND start TO payload-authorization_values.
        ENDIF.
        LOOP AT proposals_of( name = node-name type = node-type )-objects INTO DATA(own_object) WHERE proposed = abap_true.
          IF NOT line_exists( still_proposed[ table_line = CONV string( own_object-object ) ] )
             AND line_exists( before[ object = own_object-object ] )
             AND NOT line_exists( payload-authorization_values[ object = CONV string( own_object-object ) status = co_status-review ] ).
            APPEND VALUE #( object = own_object-object source = source status = co_status-review ) TO payload-authorization_values.
          ENDIF.
        ENDLOOP.
      ENDLOOP.

      entry-note = COND #( WHEN entry-other_roles IS NOT INITIAL
                           THEN |users who also hold { concat_lines_of( table = entry-other_roles sep = `, ` ) } keep its apps|
                           ELSE `no other role contains the catalog; its apps disappear from the launchpad of the users` ).
      APPEND entry TO payload-catalogs.
    ENDLOOP.
  ENDMETHOD.

  METHOD plan_composite.
    DATA before TYPE zif_accx_critical_rules=>ty_auth_values.
    DATA after  TYPE zif_accx_critical_rules=>ty_auth_values.

    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(composite) = CONV string( info-role ).
    DATA(children)  = info-children.

    LOOP AT adds INTO DATA(add).
      DATA(entry) = VALUE ty_role_entry( role = add action = co_status-add ).
      IF role_repo->exists( CONV #( add ) ) = abap_false.
        entry-status = co_status-unknown.
        entry-note   = `role does not exist`.
      ELSEIF guard->can_display_role( CONV #( add ) ) = abap_false.
        entry-status = co_status-unknown.
        entry-note   = `you may not display the role`.
      ELSEIF line_exists( info-children[ table_line = add ] ).
        entry-status = co_status-already_in_role.
        entry-note   = `the composite role contains it already`.
      ELSE.
        DATA(child) = role_repo->get_role_info( CONV #( add ) ).
        entry-description      = child-description.
        entry-other_composites = child-parents.
        IF child-composite = abap_true.
          entry-status = co_status-composite.
          entry-note   = `a composite role cannot contain composite roles`.
        ELSE.
          entry-status = co_status-add.
          IF child-generated = abap_false.
            entry-note = `its profile is not generated; the users get no authorizations from it until it is`.
          ENDIF.
          IF NOT line_exists( children[ table_line = add ] ).
            APPEND add TO children.
          ENDIF.
        ENDIF.
      ENDIF.
      APPEND entry TO payload-roles.
    ENDLOOP.

    LOOP AT removes INTO DATA(remove).
      entry = VALUE #( role = remove action = co_status-remove ).
      IF NOT line_exists( info-children[ table_line = remove ] ).
        entry-status = co_status-not_in_role.
        entry-note   = `the composite role does not contain it`.
      ELSE.
        child = role_repo->get_role_info( CONV #( remove ) ).
        entry-status           = co_status-remove.
        entry-description      = child-description.
        entry-other_composites = VALUE #( FOR parent IN child-parents WHERE ( table_line <> composite ) ( parent ) ).
        entry-note = COND #( WHEN entry-other_composites IS NOT INITIAL
                             THEN |users who also hold { concat_lines_of( table = entry-other_composites sep = `, ` ) } | &&
                                  |or the role itself keep its authorizations|
                             ELSE `users keep its authorizations only if the role is assigned to them directly` ).
        DELETE children WHERE table_line = remove.
      ENDIF.
      APPEND entry TO payload-roles.
    ENDLOOP.

    IF NOT line_exists( payload-roles[ status = co_status-add ] ) AND NOT line_exists( payload-roles[ status = co_status-remove ] ).
      RETURN.
    ENDIF.
    " a composite role grants the union of its single roles; authorization names carry the profile of their role
    LOOP AT info-children INTO DATA(old_child).
      APPEND LINES OF role_repo->get_authorization_values( CONV #( old_child ) ) TO before.
    ENDLOOP.
    LOOP AT children INTO DATA(new_child).
      APPEND LINES OF role_repo->get_authorization_values( CONV #( new_child ) ) TO after.
    ENDLOOP.
    DATA(rules) = zcl_accx_domain_factory=>critical_rules( ).
    DATA(hits_before) = critical_hits( rules = rules values = before ).
    DATA(hits_after)  = critical_hits( rules = rules values = after ).
    LOOP AT hits_after INTO DATA(gained).
      IF NOT line_exists( hits_before[ rule = gained-rule ] ).
        APPEND gained TO payload-critical_added.
      ENDIF.
    ENDLOOP.
    LOOP AT hits_before INTO DATA(lost).
      IF NOT line_exists( hits_after[ rule = lost-rule ] ).
        APPEND lost TO payload-critical_removed.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_composite_steps.
    DATA changes TYPE string_table.
    DATA request TYPE string_table.

    DATA(composite) = payload-role.
    DATA(to_add)    = concat_lines_of( table = VALUE string_table( FOR a IN payload-roles WHERE ( status = co_status-add ) ( a-role ) )
                                       sep   = `, ` ).
    DATA(to_remove) = concat_lines_of( table = VALUE string_table( FOR r IN payload-roles WHERE ( status = co_status-remove ) ( r-role ) )
                                       sep   = `, ` ).
    DATA(critical)  = critical_text( payload-critical_added ).
    DATA(lost)      = critical_text( payload-critical_removed ).

    IF composite CP 'SAP_*'.
      APPEND |Copy { composite } to the customer namespace in PFCG and change the copy; SAP template roles are overwritten by upgrades.|
        TO payload-steps.
    ENDIF.
    IF to_add IS NOT INITIAL.
      APPEND |PFCG { composite }, tab Roles: add the single roles { to_add }.| TO payload-steps.
      APPEND |add single roles { to_add }| TO changes.
    ENDIF.
    IF to_remove IS NOT INITIAL.
      APPEND |PFCG { composite }, tab Roles: remove the single roles { to_remove }.| TO payload-steps.
      APPEND |remove single roles { to_remove }| TO changes.
    ENDIF.
    LOOP AT payload-roles INTO DATA(not_generated) WHERE status = co_status-add AND note IS NOT INITIAL.
      APPEND |Generate the profile of { not_generated-role } (PFCG, tab Authorizations); otherwise its users get no | &&
             |authorizations from it.| TO payload-steps.
    ENDLOOP.
    IF to_add IS NOT INITIAL OR to_remove IS NOT INITIAL.
      APPEND |Tab User: run the user comparison so that the change reaches the { payload-assigned_users } users of { composite }.|
        TO payload-steps.
    ENDIF.
    IF to_add IS NOT INITIAL.
      APPEND |Tab Menu: the menu of a composite role is maintained separately; read the menus of { to_add } there if | &&
             |the users start transactions from the SAP Easy Access menu.| TO payload-steps.
    ENDIF.
    IF payload-for_user IS NOT INITIAL AND payload-for_user_has_role = abap_false.
      APPEND |Assign role { composite } to { payload-for_user } with a validity period; the user does not hold it today.| TO payload-steps.
    ENDIF.
    IF critical IS NOT INITIAL.
      APPEND |Have the change approved by the owner of the critical authorizations the composite role gains ({ critical }), | &&
             |or assign the single role only to the users who need it.| TO payload-steps.
    ENDIF.
    APPEND |Check the users of { composite } with run_critical_access_check.| TO payload-steps.

    APPEND |Change request for composite role { composite }| TO request.
    IF payload-description IS NOT INITIAL AND payload-description <> composite.
      APPEND |Role description: { payload-description }| TO request.
    ENDIF.
    IF payload-for_user IS NOT INITIAL.
      APPEND |Needed by: { payload-for_user }| TO request.
    ENDIF.
    IF reason IS NOT INITIAL.
      APPEND |Reason: { reason }| TO request.
    ENDIF.
    APPEND COND string( WHEN changes IS NOT INITIAL THEN |Changes: { concat_lines_of( table = changes sep = `; ` ) }|
                        ELSE `Changes: none needed` ) TO request.
    APPEND |Critical authorizations added (SUIM): { COND #( WHEN critical IS NOT INITIAL THEN critical ELSE `none` ) }| TO request.
    IF lost IS NOT INITIAL.
      APPEND |Critical authorizations the composite role no longer grants: { lost }| TO request.
    ENDIF.
    APPEND |Impact: { payload-assigned_users } users| TO request.
    IF payload-for_user IS NOT INITIAL AND payload-for_user_has_role = abap_false.
      APPEND |Also assign role { composite } to { payload-for_user }.| TO request.
    ENDIF.
    APPEND |Draft by Access Explorer { zif_accx_types=>co_release } on { sy-datum DATE = ISO }; nothing has been changed in the system.|
      TO request.
    payload-request_text = concat_lines_of( table = request sep = |\n| ).
  ENDMETHOD.

  METHOD render_composite.
    DATA(adds)    = REDUCE i( INIT n = 0 FOR a IN payload-roles WHERE ( status = co_status-add ) NEXT n = n + 1 ).
    DATA(removes) = REDUCE i( INIT n = 0 FOR r IN payload-roles WHERE ( status = co_status-remove ) NEXT n = n + 1 ).
    result = |**Draft for composite role { payload-role }**: { adds } single { COND #( WHEN adds = 1 THEN `role` ELSE `roles` ) } | &&
             |to add, { removes } to remove; { payload-assigned_users } | &&
             |{ COND #( WHEN payload-assigned_users = 1 THEN `user` ELSE `users` ) } affected. Nothing has been changed.|.
    LOOP AT payload-roles INTO DATA(entry).
      result = |{ result }\n- { entry-role }| &&
               |{ COND #( WHEN entry-description IS NOT INITIAL AND entry-description <> entry-role THEN | ({ entry-description })| ) }: | &&
               |{ COND #( WHEN entry-status = co_status-add OR entry-status = co_status-remove THEN entry-action ELSE `left out` ) }| &&
               |{ COND #( WHEN entry-status = co_status-add AND entry-other_composites IS NOT INITIAL
                          THEN |; also in { concat_lines_of( table = entry-other_composites sep = `, ` ) }| ) }| &&
               |{ COND #( WHEN entry-note IS NOT INITIAL THEN |; { entry-note }| ) }|.
    ENDLOOP.
    IF payload-critical_added IS NOT INITIAL.
      result = |{ result }\n\n**Adds critical authorizations:** { critical_text( payload-critical_added ) }|.
    ELSEIF line_exists( payload-roles[ status = co_status-add ] ).
      result = |{ result }\n\nNo critical authorizations are added according to the SUIM rules.|.
    ENDIF.
    IF payload-critical_removed IS NOT INITIAL.
      result = |{ result }\n\n**The composite role no longer grants:** { critical_text( payload-critical_removed ) }|.
    ENDIF.
    result = |{ result }\n\n**Steps in PFCG:**|.
    LOOP AT payload-steps INTO DATA(step).
      result = |{ result }\n{ sy-tabix }. { step }|.
    ENDLOOP.
    result = |{ result }\n\n**Change request text:**\n\n{ payload-request_text }|.
  ENDMETHOD.
ENDCLASS.

