"! <p class="shorttext synchronized">Access Explorer tool: get_user_launchpad</p>
"! What does a user see in the Fiori launchpad, and through which role? Reads
"! the launchpad content of the user's roles (catalogs, groups, spaces with
"! their pages) and checks for every tile on a page or in a group whether the
"! user has the catalog the tile comes from - the launchpad hides it otherwise.
"! Missing catalogs are handed over to draft_role_change for the role that
"! brings the page or group. Embedded launchpad only; content of role menus
"! (PFCG), not personalization.
CLASS zcl_accx_t_get_user_launchpad DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_user_launchpad`.

    CONSTANTS: BEGIN OF co_state,
                 active          TYPE string VALUE `active`,
                 not_valid_today TYPE string VALUE `not_valid_today`,
                 missing         TYPE string VALUE `missing`,
               END OF co_state.

    CONSTANTS: BEGIN OF co_home,
                 spaces TYPE string VALUE `spaces`,
                 groups TYPE string VALUE `groups`,
               END OF co_home.

    TYPES: BEGIN OF ty_catalog,
             catalog TYPE string,
             title   TYPE string,
             "! target mappings (apps) in the catalog
             apps    TYPE i,
             "! roles bringing the catalog; roles not valid today with their validity
             roles   TYPE string_table,
             "! active, not_valid_today (only through assignments not valid today), missing (does not exist)
             state   TYPE string,
           END OF ty_catalog,
           ty_catalogs TYPE STANDARD TABLE OF ty_catalog WITH EMPTY KEY.

    TYPES: BEGIN OF ty_page,
             page             TYPE string,
             title            TYPE string,
             "! hidden in the space
             hidden           TYPE abap_bool,
             tiles            TYPE i,
             "! tiles whose catalog the user has
             visible_tiles    TYPE i,
             "! catalogs of the other tiles: none of the user's roles valid today brings them
             missing_catalogs TYPE string_table,
           END OF ty_page,
           ty_pages TYPE STANDARD TABLE OF ty_page WITH EMPTY KEY.

    TYPES: BEGIN OF ty_group,
             group            TYPE string,
             title            TYPE string,
             roles            TYPE string_table,
             state            TYPE string,
             tiles            TYPE i,
             visible_tiles    TYPE i,
             missing_catalogs TYPE string_table,
           END OF ty_group,
           ty_groups TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.

    TYPES: BEGIN OF ty_space,
             space_id TYPE string,
             title    TYPE string,
             "! space template (SPACET_PROVIDER)
             template TYPE abap_bool,
             roles    TYPE string_table,
             state    TYPE string,
             pages    TYPE ty_pages,
           END OF ty_space,
           ty_spaces TYPE STANDARD TABLE OF ty_space WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user             TYPE string,
             "! spaces (spaces and pages) or groups (classic home page): launchpad setting SPACES
             home             TYPE string,
             "! users may switch between spaces and groups (SPACES_ENABLE_USER)
             user_switch      TYPE abap_bool,
             "! distinct apps (intents) in the user's catalogs valid today
             apps             TYPE i,
             catalogs         TYPE ty_catalogs,
             groups           TYPE ty_groups,
             spaces           TYPE ty_spaces,
             "! catalogs of hidden tiles on the user's pages or in the user's groups
             missing_catalogs TYPE string_table,
             "! role to add missing catalogs to: the role that brings the page or group with hidden tiles
             draft_role       TYPE string,
             "! arguments for draft_role_change (JSON object)
             draft_arguments  TYPE string,
           END OF ty_payload.

    CONSTANTS co_catalogs_shown TYPE i VALUE 20.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_role_state,
             role   TYPE agr_name,
             active TYPE abap_bool,
             "! the role, with its validity if not valid today
             label  TYPE string,
           END OF ty_role_state,
           ty_role_states TYPE STANDARD TABLE OF ty_role_state WITH EMPTY KEY.

    "! Roles bringing a content node; state active if one of them is valid today
    METHODS roles_of
      IMPORTING !contents     TYPE zif_accx_fiori_repo=>ty_role_contents
                !roles        TYPE ty_role_states
                !type         TYPE string
                !id           TYPE string
      EXPORTING !labels       TYPE string_table
                !active_roles TYPE zif_accx_role_repo=>ty_roles
                !state        TYPE string.

    "! Tiles the user sees (catalog brought by a role valid today) and the catalogs of the others
    METHODS check_tiles
      IMPORTING !tiles         TYPE zif_accx_fiori_repo=>ty_tile_refs
                !user_catalogs TYPE string_table
      EXPORTING !total         TYPE i
                !visible       TYPE i
                !missing       TYPE string_table.

    "! Collects missing catalogs; the first non-composite role bringing affected content becomes the draft target
    METHODS collect_missing
      IMPORTING !missing      TYPE string_table
                !active_roles TYPE zif_accx_role_repo=>ty_roles
      CHANGING  !payload      TYPE ty_payload
                !draft        TYPE string_table.

    METHODS json_string
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_get_user_launchpad IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get user launchpad`
      description = |Shows what a user sees in the Fiori launchpad and through which role: the catalogs (with number of | &&
                    |apps), groups and spaces with their pages from the menus of the user's roles, and whether the home page | &&
                    |uses spaces or groups. For every tile on a page or in a group it checks whether one of the user's roles | &&
                    |valid today brings the catalog the tile comes from; the launchpad hides the tile otherwise. Content of | &&
                    |assignments not valid today and content that does not exist are flagged. Missing catalogs are handed over | &&
                    |to draft_role_change for the role that brings the page or group. Embedded launchpad only; role content, | &&
                    |not personalization.|
      group       = zif_accx_types=>co_group-fiori
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_USER_LAUNCHPAD\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `User ID whose launchpad content is shown.`
                                      required    = abap_true
                                      maximum     = 12 ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA roles     TYPE ty_role_states.
    DATA all_roles TYPE zif_accx_role_repo=>ty_roles.
    DATA draft     TYPE string_table.

    DATA(user) = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    IF user_repo->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { user } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-denied message = |You may not display user { user }.| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( user = user ).
    result-data = payload.
    result-sources = VALUE #( ( `AGR_USERS (role assignments), AGR_HIER and AGR_BUFFI (catalogs, groups and spaces in role menus)` )
                              ( `/UI2/FDM_PUBLIC_API (catalogs, groups)` )
                              ( `/UI2/CL_FDM_SPACE_API_FACTORY, /UI2/CL_FDM_PAGE_API_FACTORY (spaces, pages)` )
                              ( `/UI2/CL_FLP_SETTINGS_API (launchpad settings SPACES, SPACES_ENABLE_USER)` ) ).

    DATA(fiori_repo) = zcl_accx_domain_factory=>fiori_repo( ).
    DATA(settings) = fiori_repo->get_settings( ).
    payload->home        = COND #( WHEN settings-spaces = abap_true THEN co_home-spaces ELSE co_home-groups ).
    payload->user_switch = settings-user_switch.

    " a role can be assigned several times; valid today wins
    LOOP AT user_repo->get_role_assignments( user ) INTO DATA(assignment).
      READ TABLE roles ASSIGNING FIELD-SYMBOL(<role>) WITH KEY role = assignment-role.
      IF sy-subrc <> 0.
        APPEND VALUE #( role = assignment-role ) TO roles ASSIGNING <role>.
        APPEND assignment-role TO all_roles.
      ENDIF.
      IF <role>-active = abap_true.
        CONTINUE.
      ENDIF.
      <role>-active = assignment-active.
      <role>-label  = COND #( WHEN assignment-active = abap_true THEN CONV string( assignment-role )
                              WHEN assignment-valid_to < sy-datum
                              THEN |{ assignment-role } (expired on { assignment-valid_to DATE = ISO })|
                              ELSE |{ assignment-role } (valid from { assignment-valid_from DATE = ISO })| ).
    ENDLOOP.

    " what the launchpad shows depends on all roles valid today ...
    DATA(contents) = fiori_repo->get_role_content( all_roles ).
    DATA(user_catalogs) = VALUE string_table( ).
    LOOP AT contents INTO DATA(content) WHERE type = zif_accx_fiori_repo=>co_content_type-catalog.
      IF line_exists( roles[ role = content-role active = abap_true ] )
         AND NOT line_exists( user_catalogs[ table_line = content-id ] ).
        APPEND content-id TO user_catalogs.
      ENDIF.
    ENDLOOP.
    " ... but only the content of roles the caller may display is reported
    LOOP AT roles INTO DATA(role_state).
      IF line_exists( contents[ role = role_state-role ] ) AND ctx->guard( )->can_display_role( role_state-role ) = abap_false.
        result-hidden_by_authorization += 1.
        DELETE contents WHERE role = role_state-role.
      ENDIF.
    ENDLOOP.

    " catalogs
    DATA(intents) = VALUE string_table( ).
    LOOP AT contents INTO content WHERE type = zif_accx_fiori_repo=>co_content_type-catalog.
      IF line_exists( payload->catalogs[ catalog = content-id ] ).
        CONTINUE.
      ENDIF.
      DATA(catalog) = VALUE ty_catalog( catalog = content-id ).
      roles_of( EXPORTING contents = contents roles = roles type = content-type id = content-id
                IMPORTING labels = catalog-roles state = catalog-state ).
      DATA(found_catalog) = fiori_repo->get_catalog( content-id ).
      IF found_catalog-catalog IS INITIAL.
        catalog-state = co_state-missing.
      ELSE.
        catalog-title = found_catalog-title.
        catalog-apps  = lines( found_catalog-apps ).
        IF catalog-state = co_state-active.
          LOOP AT found_catalog-apps INTO DATA(app).
            IF NOT line_exists( intents[ table_line = app-intent ] ).
              APPEND app-intent TO intents.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDIF.
      APPEND catalog TO payload->catalogs.
    ENDLOOP.
    payload->apps = lines( intents ).

    " hidden tiles count where the user's home page shows them
    DATA(spaces_shown) = xsdbool( payload->home = co_home-spaces OR payload->user_switch = abap_true ).
    DATA(groups_shown) = xsdbool( payload->home = co_home-groups OR payload->user_switch = abap_true ).

    " spaces and their pages
    LOOP AT contents INTO content WHERE type = zif_accx_fiori_repo=>co_content_type-flp_space.
      IF line_exists( payload->spaces[ space_id = content-id template = content-template ] ).
        CONTINUE.
      ENDIF.
      DATA(space_entry) = VALUE ty_space( space_id = content-id template = content-template ).
      roles_of( EXPORTING contents = contents roles = roles type = content-type id = content-id
                IMPORTING labels = space_entry-roles active_roles = DATA(space_roles) state = space_entry-state ).
      DATA(found_space) = fiori_repo->get_space( id = content-id template = content-template ).
      IF found_space-id IS INITIAL.
        space_entry-state = co_state-missing.
      ELSE.
        space_entry-title = found_space-title.
        LOOP AT found_space-pages INTO DATA(found_page).
          DATA(page) = VALUE ty_page( page = found_page-page title = found_page-title hidden = found_page-hidden ).
          check_tiles( EXPORTING tiles = found_page-tiles user_catalogs = user_catalogs
                       IMPORTING total = page-tiles visible = page-visible_tiles missing = page-missing_catalogs ).
          IF spaces_shown = abap_true AND space_entry-state = co_state-active AND page-hidden = abap_false.
            collect_missing( EXPORTING missing = page-missing_catalogs active_roles = space_roles
                             CHANGING  payload = payload->* draft = draft ).
          ENDIF.
          APPEND page TO space_entry-pages.
        ENDLOOP.
      ENDIF.
      APPEND space_entry TO payload->spaces.
    ENDLOOP.

    " groups
    DATA(group_ids) = VALUE string_table( FOR c IN contents WHERE ( type = zif_accx_fiori_repo=>co_content_type-group ) ( c-id ) ).
    SORT group_ids.
    DELETE ADJACENT DUPLICATES FROM group_ids.
    DATA(found_groups) = fiori_repo->get_groups( group_ids ).
    LOOP AT group_ids INTO DATA(group_id).
      DATA(group) = VALUE ty_group( group = group_id ).
      roles_of( EXPORTING contents = contents roles = roles type = zif_accx_fiori_repo=>co_content_type-group id = group_id
                IMPORTING labels = group-roles active_roles = DATA(group_roles) state = group-state ).
      DATA(found_group) = VALUE #( found_groups[ group = group_id ] OPTIONAL ).
      IF found_group IS INITIAL.
        group-state = co_state-missing.
      ELSE.
        group-title = found_group-title.
        check_tiles( EXPORTING tiles = found_group-tiles user_catalogs = user_catalogs
                     IMPORTING total = group-tiles visible = group-visible_tiles missing = group-missing_catalogs ).
        IF groups_shown = abap_true AND group-state = co_state-active.
          collect_missing( EXPORTING missing = group-missing_catalogs active_roles = group_roles
                           CHANGING  payload = payload->* draft = draft ).
        ENDIF.
      ENDIF.
      APPEND group TO payload->groups.
    ENDLOOP.

    " next steps
    IF payload->draft_role IS NOT INITIAL.
      payload->draft_arguments =
        |\{"role":{ json_string( payload->draft_role ) },"add_catalogs":[| &&
        |{ concat_lines_of( table = VALUE string_table( FOR d IN draft ( json_string( d ) ) ) sep = `,` ) }]| &&
        |,"for_user":{ json_string( payload->user ) }| &&
        |,"reason":{ json_string( |Tiles on the launchpad of { payload->user } come from catalogs none of the user's | &&
                                  |roles brings, found by get_user_launchpad| ) }\}|.
      APPEND |Plan adding catalog { concat_lines_of( table = draft sep = `, ` ) } to role { payload->draft_role } (it brings | &&
             |the page or group with the hidden tiles; PFCG adds the start authorizations with the catalog) with | &&
             |draft_role_change { payload->draft_arguments }| TO result-next_steps.
    ENDIF.
    IF lines( payload->missing_catalogs ) > lines( draft ).
      APPEND |Tiles from { concat_lines_of( table = payload->missing_catalogs sep = `, ` ) } stay hidden until a role of | &&
             |{ payload->user } brings the catalog; run diagnose_fiori_app_access for an app of the catalog to find a | &&
             |role that contains it.| TO result-next_steps.
    ENDIF.
    IF payload->home = co_home-spaces AND NOT line_exists( payload->spaces[ state = co_state-active ] ).
      APPEND |No role of { payload->user } valid today brings a space; the launchpad uses spaces, so the user sees no pages | &&
             |(at most My Home). Assign a role with a space or add a space to one of the user's roles.| TO result-next_steps.
    ENDIF.
    DATA(inactive) = VALUE string_table( ).
    LOOP AT roles INTO role_state WHERE active = abap_false.
      IF line_exists( contents[ role = role_state-role ] ).
        APPEND role_state-label TO inactive.
      ENDIF.
    ENDLOOP.
    IF inactive IS NOT INITIAL.
      APPEND |Launchpad content of { concat_lines_of( table = inactive sep = `, ` ) } is not shown: extend the role | &&
             |assignment via the access request process if it is still needed.| TO result-next_steps.
    ENDIF.
    DATA(missing_content) = VALUE string_table(
      FOR m IN payload->catalogs WHERE ( state = co_state-missing ) ( |catalog { m-catalog }| ) ).
    LOOP AT payload->groups INTO DATA(missing_group) WHERE state = co_state-missing.
      APPEND |group { missing_group-group }| TO missing_content.
    ENDLOOP.
    LOOP AT payload->spaces INTO DATA(missing_space) WHERE state = co_state-missing.
      APPEND |space { missing_space-space_id }| TO missing_content.
    ENDLOOP.
    IF missing_content IS NOT INITIAL.
      APPEND |Role menus refer to launchpad content that does not exist ({ concat_lines_of( table = missing_content sep = `, ` ) }); | &&
             |remove the menu node in PFCG or restore the content.| TO result-warnings.
    ENDIF.
    result-total_count = lines( payload->catalogs ) + lines( payload->groups ) + lines( payload->spaces ).
  ENDMETHOD.

  METHOD roles_of.
    CLEAR: labels, active_roles.
    state = co_state-not_valid_today.
    LOOP AT contents INTO DATA(content) WHERE type = type AND id = id.
      DATA(role) = roles[ role = content-role ].
      IF line_exists( labels[ table_line = role-label ] ).
        CONTINUE.
      ENDIF.
      APPEND role-label TO labels.
      IF role-active = abap_true.
        state = co_state-active.
        APPEND role-role TO active_roles.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_tiles.
    CLEAR: visible, missing.
    total = lines( tiles ).
    LOOP AT tiles INTO DATA(tile).
      IF tile-catalog IS INITIAL OR line_exists( user_catalogs[ table_line = tile-catalog ] ).
        visible += 1.
      ELSEIF NOT line_exists( missing[ table_line = tile-catalog ] ).
        APPEND tile-catalog TO missing.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD collect_missing.
    IF missing IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT missing INTO DATA(catalog).
      IF NOT line_exists( payload-missing_catalogs[ table_line = catalog ] ).
        APPEND catalog TO payload-missing_catalogs.
      ENDIF.
    ENDLOOP.
    IF payload-draft_role IS INITIAL.
      LOOP AT active_roles INTO DATA(role).
        IF zcl_accx_domain_factory=>role_repo( )->get_role_info( role )-composite = abap_false.
          payload-draft_role = role.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF payload-draft_role IS INITIAL OR NOT line_exists( active_roles[ table_line = CONV agr_name( payload-draft_role ) ] ).
      RETURN.
    ENDIF.
    LOOP AT missing INTO catalog.
      IF NOT line_exists( draft[ table_line = catalog ] ).
        APPEND catalog TO draft.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD json_string.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    DATA(active_catalogs) = REDUCE i( INIT n = 0 FOR c IN <payload>-catalogs WHERE ( state = co_state-active ) NEXT n = n + 1 ).
    result-summary = |Launchpad of **{ <payload>-user }**: home page with **{ <payload>-home }**| &&
                     |{ COND #( WHEN <payload>-user_switch = abap_true THEN ` (users may switch between spaces and groups)` ) }; | &&
                     |{ <payload>-apps } apps in { active_catalogs } catalogs valid today.|.

    IF <payload>-spaces IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Spaces**{ COND #( WHEN <payload>-home = co_home-groups AND <payload>-user_switch = abap_false
                                                                THEN ` (not shown: the home page uses groups)` ) }:|.
      LOOP AT <payload>-spaces INTO DATA(space_entry).
        result-summary = |{ result-summary }\n- { space_entry-title } ({ space_entry-space_id }| &&
                         |{ COND #( WHEN space_entry-template = abap_true THEN `, template` ) }) via | &&
                         |{ concat_lines_of( table = space_entry-roles sep = `, ` ) }| &&
                         |{ SWITCH string( space_entry-state WHEN co_state-missing THEN ` - **does not exist**`
                                                             WHEN co_state-not_valid_today THEN ` - **not valid today**` ) }|.
        LOOP AT space_entry-pages INTO DATA(page).
          result-summary = |{ result-summary }\n  - page { page-title } ({ page-page }): { page-visible_tiles } of { page-tiles } | &&
                           |tiles visible{ COND #( WHEN page-hidden = abap_true THEN `, hidden in the space` ) }| &&
                           |{ COND #( WHEN page-missing_catalogs IS NOT INITIAL
                                      THEN |; catalogs missing: { concat_lines_of( table = page-missing_catalogs sep = `, ` ) }| ) }|.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    IF <payload>-groups IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Groups**{ COND #( WHEN <payload>-home = co_home-spaces AND <payload>-user_switch = abap_false
                                                                THEN ` (not shown: the home page uses spaces)` ) }:|.
      LOOP AT <payload>-groups INTO DATA(group).
        result-summary = |{ result-summary }\n- { group-title } ({ group-group }) via { concat_lines_of( table = group-roles sep = `, ` ) }| &&
                         |{ SWITCH string( group-state WHEN co_state-missing THEN ` - **does not exist**`
                                                       WHEN co_state-not_valid_today THEN ` - **not valid today**`
                                                       ELSE |: { group-visible_tiles } of { group-tiles } tiles visible| ) }| &&
                         |{ COND #( WHEN group-missing_catalogs IS NOT INITIAL
                                    THEN |; catalogs missing: { concat_lines_of( table = group-missing_catalogs sep = `, ` ) }| ) }|.
      ENDLOOP.
    ENDIF.

    IF <payload>-catalogs IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Catalogs** ({ lines( <payload>-catalogs ) }):|.
      LOOP AT <payload>-catalogs INTO DATA(catalog) TO co_catalogs_shown.
        result-summary = |{ result-summary }\n- { catalog-catalog }{ COND #( WHEN catalog-title IS NOT INITIAL THEN | ({ catalog-title })| ) }| &&
                         |{ SWITCH string( catalog-state WHEN co_state-missing THEN ` - **does not exist**`
                                                         ELSE |: { catalog-apps } { COND #( WHEN catalog-apps = 1 THEN `app` ELSE `apps` ) }| ) } | &&
                         |via { concat_lines_of( table = catalog-roles sep = `, ` ) }| &&
                         |{ COND #( WHEN catalog-state = co_state-not_valid_today THEN ` - **not valid today**` ) }|.
      ENDLOOP.
      IF lines( <payload>-catalogs ) > co_catalogs_shown.
        result-summary = |{ result-summary }\n- ... { lines( <payload>-catalogs ) - co_catalogs_shown } more|.
      ENDIF.
    ELSE.
      result-summary = |{ result-summary }\n\nNo role of the user contains a launchpad catalog.|.
    ENDIF.

    IF <payload>-draft_role IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Hidden tiles:** add catalog { concat_lines_of( table = <payload>-missing_catalogs sep = `, ` ) } | &&
                       |to role **{ <payload>-draft_role }**; draft_role_change shows the apps, authorizations and users | &&
                       |affected before anything is changed.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } further roles with launchpad content are hidden | &&
                       |due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
