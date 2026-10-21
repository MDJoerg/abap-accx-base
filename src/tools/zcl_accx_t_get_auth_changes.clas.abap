"! <p class="shorttext synchronized">Access Explorer tool: get_authorization_changes</p>
"! Who changed what in a period: role assignments, role content (values, organizational
"! levels, authorizations, single roles of composite roles, menu, reference role), roles
"! created or deleted, user master changes (created, user group, user type, lock, validity,
"! password set by an administrator) and profiles assigned directly. Changes of one save
"! (same object, user and second) form one event.
CLASS zcl_accx_t_get_auth_changes DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_authorization_changes`.
    "! longest period without a user or role
    CONSTANTS co_max_days TYPE i VALUE 366.
    "! change lines per event in the summary
    CONSTANTS co_lines_in_summary TYPE i VALUE 6.

    CONSTANTS: BEGIN OF co_kind,
                 assignment     TYPE string VALUE `assignment`,
                 role_created   TYPE string VALUE `role_created`,
                 role_deleted   TYPE string VALUE `role_deleted`,
                 role_content   TYPE string VALUE `role_content`,
                 user_master    TYPE string VALUE `user_master`,
                 direct_profile TYPE string VALUE `direct_profile`,
               END OF co_kind.

    " values of parameter scope
    CONSTANTS: BEGIN OF co_scope,
                 assignments  TYPE string VALUE `assignments`,
                 role_content TYPE string VALUE `role_content`,
                 users        TYPE string VALUE `users`,
                 all          TYPE string VALUE `all`,
               END OF co_scope.

    TYPES: BEGIN OF ty_event,
             date        TYPE string,
             time        TYPE string,
             changed_by  TYPE string,
             tcode       TYPE string,
             "! role or user
             object_type TYPE string,
             object      TYPE string,
             kind        TYPE string,
             "! the user changed its own role assignments or user master record
             self_change TYPE abap_bool,
             changes     TYPE string_table,
           END OF ty_event,
           ty_events TYPE STANDARD TABLE OF ty_event WITH EMPTY KEY.

    TYPES: BEGIN OF ty_count,
             name   TYPE string,
             events TYPE i,
           END OF ty_count,
           ty_counts TYPE STANDARD TABLE OF ty_count WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             from           TYPE string,
             to             TYPE string,
             "! selection in words
             selection      TYPE string,
             scope          TYPE string,
             "! single changes (change document items) after authorization filtering
             changes_total  TYPE i,
             events_total   TYPE i,
             "! events per kind
             by_kind        TYPE ty_counts,
             "! events per user who made the change, most active first
             by_changer     TYPE ty_counts,
             "! events in which users changed their own assignments or user master record
             self_changes   TYPE i,
             "! critical events, e.g. SAP_ALL assigned directly
             critical       TYPE string_table,
             "! newest first
             events         TYPE ty_events,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! YYYY-MM-DD or YYYYMMDD; initial input = default
    METHODS parse_date
      IMPORTING !text         TYPE string
                !name         TYPE string
                !default      TYPE d
      RETURNING VALUE(result) TYPE d
      RAISING   zcx_accx_error.

    "! EQ, or CP when the value contains * or +
    METHODS pattern
      IMPORTING !value        TYPE string
      EXPORTING !sign         TYPE c
                !option       TYPE c.

    METHODS role_kind
      IMPORTING !change       TYPE zif_accx_change_repo=>ty_role_change
      RETURNING VALUE(result) TYPE string.

    METHODS role_text
      IMPORTING !change       TYPE zif_accx_change_repo=>ty_role_change
      RETURNING VALUE(result) TYPE string.

    METHODS user_text
      IMPORTING !change       TYPE zif_accx_change_repo=>ty_user_change
      RETURNING VALUE(result) TYPE string.

    METHODS add_to_event
      IMPORTING !date        TYPE d
                !time        TYPE t
                !changed_by  TYPE syuname
                !tcode       TYPE string
                !object_type TYPE string
                !object      TYPE string
                !kind        TYPE string
                !text        TYPE string
                !self_change TYPE abap_bool
      CHANGING  !events      TYPE ty_events.

    METHODS count
      IMPORTING !name   TYPE string
      CHANGING  !counts TYPE ty_counts.

ENDCLASS.

CLASS zcl_accx_t_get_auth_changes IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get authorization changes`
      description = |Change documents of a period (like SUIM change documents): who assigned or removed roles, | &&
                    |changed role content (authorization values, organizational levels, authorizations, single roles of | &&
                    |composite roles, menu, reference role), created or deleted roles, changed user master records | &&
                    |(created, user group, user type, lock, validity, password set by an administrator) or assigned | &&
                    |profiles directly (e.g. SAP_ALL). Filter by user, role and changed_by; changes of one save form one | &&
                    |event; users changing their own assignments are flagged. Without user or role the period is limited | &&
                    |to { co_max_days } days.|
      group       = zif_accx_types=>co_group-audit
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_AUTH_CHANGES\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `from`
                                      description = `Start of the period, YYYY-MM-DD.`
                                      required    = abap_true
                                      maximum     = 10 ) )
                             ( param( name        = `to`
                                      description = `End of the period, YYYY-MM-DD (default today).`
                                      maximum     = 10 ) )
                             ( param( name        = `user`
                                      description = |Affected user (pattern with * allowed): its role assignments, user master | &&
                                                    |changes and profiles; role content changes are left out.|
                                      maximum     = 12 ) )
                             ( param( name        = `role`
                                      description = `Role (pattern with * allowed): its assignments and content changes.`
                                      maximum     = 30 ) )
                             ( param( name        = `changed_by`
                                      description = `User who made the changes (pattern with * allowed).`
                                      maximum     = 12 ) )
                             ( param( name        = `scope`
                                      description = |{ co_scope-assignments } (role assignments), { co_scope-role_content } | &&
                                                    |(roles created, deleted or changed), { co_scope-users } (user master and | &&
                                                    |direct profiles) or { co_scope-all } (default).|
                                      enum        = VALUE #( ( co_scope-assignments ) ( co_scope-role_content ) ( co_scope-users ) ( co_scope-all ) ) ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA selection TYPE zif_accx_change_repo=>ty_selection.
    DATA hidden TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    selection-from = parse_date( text = args->get_string( `from` ) name = `from` default = '00000000' ).
    IF selection-from IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `from is required (YYYY-MM-DD).` ).
    ENDIF.
    selection-to = parse_date( text = args->get_string( `to` ) name = `to` default = sy-datum ).
    IF selection-to < selection-from.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `to is before from.` ).
    ENDIF.
    DATA(user) = to_upper( condense( args->get_string( `user` ) ) ).
    DATA(role) = to_upper( condense( args->get_string( `role` ) ) ).
    DATA(changed_by) = to_upper( condense( args->get_string( `changed_by` ) ) ).
    DATA(scope) = to_lower( condense( args->get_string( name = `scope` default = co_scope-all ) ) ).
    IF scope IS INITIAL.
      scope = co_scope-all.
    ENDIF.
    IF scope <> co_scope-assignments AND scope <> co_scope-role_content AND scope <> co_scope-users AND scope <> co_scope-all.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Unknown scope "{ scope }" - use assignments, role_content, users or all.| ).
    ENDIF.
    IF user IS INITIAL AND role IS INITIAL AND selection-to - selection-from >= co_max_days.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Without user or role the period may span at most { co_max_days } days.| ).
    ENDIF.
    IF user IS NOT INITIAL.
      APPEND INITIAL LINE TO selection-users ASSIGNING FIELD-SYMBOL(<user>).
      pattern( EXPORTING value = user IMPORTING sign = <user>-sign option = <user>-option ).
      <user>-low = user.
    ENDIF.
    IF role IS NOT INITIAL.
      APPEND INITIAL LINE TO selection-roles ASSIGNING FIELD-SYMBOL(<role>).
      pattern( EXPORTING value = role IMPORTING sign = <role>-sign option = <role>-option ).
      <role>-low = role.
    ENDIF.
    IF changed_by IS NOT INITIAL.
      APPEND INITIAL LINE TO selection-changed_by ASSIGNING FIELD-SYMBOL(<changer>).
      pattern( EXPORTING value = changed_by IMPORTING sign = <changer>-sign option = <changer>-option ).
      <changer>-low = changed_by.
    ENDIF.

    DATA(payload) = NEW ty_payload( from  = |{ selection-from DATE = ISO }|
                                    to    = |{ selection-to DATE = ISO }|
                                    scope = scope ).
    DATA(words) = VALUE string_table( ).
    IF user IS NOT INITIAL.
      APPEND |user { user }| TO words.
    ENDIF.
    IF role IS NOT INITIAL.
      APPEND |role { role }| TO words.
    ENDIF.
    IF changed_by IS NOT INITIAL.
      APPEND |changed by { changed_by }| TO words.
    ENDIF.
    payload->selection = concat_lines_of( table = words sep = `, ` ).
    result-data = payload.

    DATA(repo) = zcl_accx_domain_factory=>change_repo( ).
    DATA(guard) = ctx->guard( ).
    DATA(events) = VALUE ty_events( ).

    " role changes: assignments and content (a user filter keeps its assignments only)
    IF scope <> co_scope-users.
      DATA(role_changes) = repo->get_role_changes( selection ).
      " a new validity is logged as removal and new assignment: merge the pair
      LOOP AT role_changes ASSIGNING FIELD-SYMBOL(<removed>)
           WHERE area = zif_accx_change_repo=>co_area-assignment AND operation = zif_accx_change_repo=>co_operation-removed.
        READ TABLE role_changes ASSIGNING FIELD-SYMBOL(<added>)
             WITH KEY area = zif_accx_change_repo=>co_area-assignment operation = zif_accx_change_repo=>co_operation-added
                      role = <removed>-role user = <removed>-user date = <removed>-date time = <removed>-time
                      changed_by = <removed>-changed_by.
        IF sy-subrc = 0.
          <added>-operation = zif_accx_change_repo=>co_operation-changed.
          <added>-value_old = |{ <removed>-valid_from DATE = ISO } to { <removed>-valid_to DATE = ISO }|.
          CLEAR <removed>-operation.
        ENDIF.
      ENDLOOP.
      DELETE role_changes WHERE operation IS INITIAL.

      LOOP AT role_changes INTO DATA(role_change).
        DATA(kind) = role_kind( role_change ).
        IF ( scope = co_scope-assignments AND kind <> co_kind-assignment )
           OR ( scope = co_scope-role_content AND kind = co_kind-assignment ).
          CONTINUE.
        ENDIF.
        IF guard->can_display_role_changes( role_change-role ) = abap_false.
          INSERT |role { role_change-role }| INTO TABLE hidden.
          CONTINUE.
        ENDIF.
        payload->changes_total += 1.
        add_to_event( EXPORTING date        = role_change-date
                                time        = role_change-time
                                changed_by  = role_change-changed_by
                                tcode       = role_change-tcode
                                object_type = `role`
                                object      = CONV #( role_change-role )
                                kind        = kind
                                text        = role_text( role_change )
                                self_change = xsdbool( kind = co_kind-assignment AND role_change-user = role_change-changed_by )
                      CHANGING  events      = events ).
      ENDLOOP.
    ENDIF.

    " user master changes and profiles assigned directly
    IF ( scope = co_scope-users OR scope = co_scope-all ) AND role IS INITIAL.
      LOOP AT repo->get_user_changes( selection ) INTO DATA(user_change).
        IF guard->can_display_group_changes( user_change-user_group ) = abap_false.
          INSERT |user { user_change-user }| INTO TABLE hidden.
          CONTINUE.
        ENDIF.
        payload->changes_total += 1.
        DATA(user_kind) = COND string( WHEN user_change-area = zif_accx_change_repo=>co_area-direct_profile THEN co_kind-direct_profile
                                       ELSE co_kind-user_master ).
        add_to_event( EXPORTING date        = user_change-date
                                time        = user_change-time
                                changed_by  = user_change-changed_by
                                tcode       = user_change-tcode
                                object_type = `user`
                                object      = CONV #( user_change-user )
                                kind        = user_kind
                                text        = user_text( user_change )
                                self_change = xsdbool( user_change-changed_by = user_change-user
                                                       AND user_change-area <> zif_accx_change_repo=>co_area-created )
                      CHANGING  events      = events ).
        IF user_change-area = zif_accx_change_repo=>co_area-direct_profile
           AND user_change-operation = zif_accx_change_repo=>co_operation-added
           AND ( user_change-item = `SAP_ALL` OR user_change-item = `SAP_NEW` ).
          APPEND |{ user_change-item } assigned directly to { user_change-user } by { user_change-changed_by } on { user_change-date DATE = ISO }|
                 TO payload->critical.
        ENDIF.
      ENDLOOP.
    ENDIF.
    result-hidden_by_authorization = lines( hidden ).

    " a deleted role loses all its content: the item list adds nothing
    LOOP AT events ASSIGNING FIELD-SYMBOL(<deleted>) WHERE kind = co_kind-role_deleted.
      DATA(removed) = lines( <deleted>-changes ) - 1.
      <deleted>-changes = VALUE #( ( |Role deleted{ COND #( WHEN removed > 0 THEN | ({ removed } items removed with it)| ) }| ) ).
    ENDLOOP.
    SORT events BY date DESCENDING time DESCENDING object_type ASCENDING object ASCENDING.
    payload->events_total = lines( events ).
    LOOP AT events INTO DATA(event).
      count( EXPORTING name = event-kind CHANGING counts = payload->by_kind ).
      count( EXPORTING name = event-changed_by CHANGING counts = payload->by_changer ).
      IF event-self_change = abap_true.
        payload->self_changes += 1.
        APPEND |{ event-changed_by } changed its own { COND #( WHEN event-object_type = `role` THEN |assignment of role { event-object }|
                                                                ELSE `user master record` ) } on { event-date }| TO payload->critical.
      ENDIF.
    ENDLOOP.
    SORT payload->by_kind BY events DESCENDING name ASCENDING.
    SORT payload->by_changer BY events DESCENDING name ASCENDING.
    payload->events = events.

    result-total_count = lines( payload->events ).
    DATA(max) = ctx->max_rows( ).
    IF lines( payload->events ) > max.
      DELETE payload->events FROM max + 1.
      result-truncated = abap_true.
    ENDIF.
    IF lines( payload->by_changer ) > max.
      DELETE payload->by_changer FROM max + 1.
    ENDIF.
    IF lines( payload->critical ) > max.
      DELETE payload->critical FROM max + 1.
    ENDIF.

    result-sources = VALUE #( ( `CDHDR/CDPOS object PFCG (role assignments and role content)` )
                              ( `USH02 (logon data history)` )
                              ( `CDHDR/CDPOS object IDENTITY, AGR_1016 (profiles assigned directly)` ) ).
    IF payload->critical IS NOT INITIAL.
      APPEND `Clarify the critical events with the persons who made them; users should not maintain their own access.`
             TO result-next_steps.
    ENDIF.
    IF line_exists( payload->by_kind[ name = co_kind-role_content ] ).
      APPEND `get_role_authorizations or compare_roles show the current content of a changed role.` TO result-next_steps.
    ENDIF.
    IF payload->events IS INITIAL.
      APPEND `No changes found: widen the period or the filters; archived change documents are not read.` TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD role_kind.
    result = COND #( WHEN change-area = zif_accx_change_repo=>co_area-assignment THEN co_kind-assignment
                     WHEN change-area = zif_accx_change_repo=>co_area-role AND change-item IS INITIAL
                      AND change-operation = zif_accx_change_repo=>co_operation-added THEN co_kind-role_created
                     WHEN change-area = zif_accx_change_repo=>co_area-role AND change-item IS INITIAL
                      AND change-operation = zif_accx_change_repo=>co_operation-removed THEN co_kind-role_deleted
                     ELSE co_kind-role_content ).
  ENDMETHOD.

  METHOD role_text.
    DATA(added) = xsdbool( change-operation = zif_accx_change_repo=>co_operation-added ).
    DATA(verb) = SWITCH string( change-operation
                                WHEN zif_accx_change_repo=>co_operation-added   THEN `added`
                                WHEN zif_accx_change_repo=>co_operation-removed THEN `removed`
                                ELSE `changed` ).
    CASE change-area.
      WHEN zif_accx_change_repo=>co_area-assignment.
        result = SWITCH #( change-operation
                   WHEN zif_accx_change_repo=>co_operation-added
                   THEN |Assigned to { change-user } ({ change-valid_from DATE = ISO } to { change-valid_to DATE = ISO })|
                   WHEN zif_accx_change_repo=>co_operation-removed
                   THEN |Removed from { change-user } (was { change-valid_from DATE = ISO } to { change-valid_to DATE = ISO })|
                   ELSE COND #( WHEN change-value_old = |{ change-valid_from DATE = ISO } to { change-valid_to DATE = ISO }|
                                THEN |Assignment to { change-user } saved again, validity unchanged|
                                ELSE |Validity for { change-user } changed to { change-valid_from DATE = ISO } to | &&
                                     |{ change-valid_to DATE = ISO } (was { change-value_old })| ) ).
      WHEN zif_accx_change_repo=>co_area-role.
        IF change-item IS INITIAL.
          result = COND #( WHEN added = abap_true THEN `Role created` ELSE `Role deleted` ).
        ELSE.
          result = COND #( WHEN change-value_old IS INITIAL THEN |Derived from { change-value_new }|
                           WHEN change-value_new IS INITIAL THEN |Derivation from { change-value_old } removed|
                           ELSE |Reference role { change-value_old } replaced by { change-value_new }| ).
        ENDIF.
      WHEN zif_accx_change_repo=>co_area-value OR zif_accx_change_repo=>co_area-org_level.
        DATA(label) = COND string( WHEN change-area = zif_accx_change_repo=>co_area-org_level THEN |Organizational level { change-item }|
                                   ELSE change-item ).
        result = SWITCH #( change-operation
                   WHEN zif_accx_change_repo=>co_operation-added   THEN |{ label }: value { change-value_new } added|
                   WHEN zif_accx_change_repo=>co_operation-removed THEN |{ label }: value { change-value_old } removed|
                   ELSE |{ label }: { change-value_old } changed to { change-value_new }| ).
      WHEN zif_accx_change_repo=>co_area-authorization.
        result = |Authorization { change-item } { verb }|.
      WHEN zif_accx_change_repo=>co_area-composite.
        result = |Single role { change-item } { verb }|.
      WHEN zif_accx_change_repo=>co_area-menu.
        result = |Menu entry { change-item } { verb }|.
      WHEN zif_accx_change_repo=>co_area-profile.
        result = COND #( WHEN added = abap_true THEN |Profile { change-item } generated| ELSE |Profile { change-item } removed| ).
      WHEN zif_accx_change_repo=>co_area-text.
        result = SWITCH #( change-operation
                   WHEN zif_accx_change_repo=>co_operation-added   THEN |Description ({ change-item }) "{ change-value_new }"|
                   WHEN zif_accx_change_repo=>co_operation-removed THEN |Description ({ change-item }) "{ change-value_old }" removed|
                   ELSE |Description ({ change-item }) changed to "{ change-value_new }"| ).
      WHEN OTHERS.
        result = |{ change-area } { change-item } { verb }|.
    ENDCASE.
  ENDMETHOD.

  METHOD user_text.
    CASE change-area.
      WHEN zif_accx_change_repo=>co_area-created.
        result = |User created ({ change-value_new })|.
      WHEN zif_accx_change_repo=>co_area-user_group.
        result = |User group { COND #( WHEN change-value_old IS INITIAL THEN `(none)` ELSE change-value_old ) } changed to | &&
                 |{ COND #( WHEN change-value_new IS INITIAL THEN `(none)` ELSE change-value_new ) }|.
      WHEN zif_accx_change_repo=>co_area-user_type.
        result = |User type { change-value_old } changed to { change-value_new }|.
      WHEN zif_accx_change_repo=>co_area-lock.
        result = SWITCH #( change-operation
                   WHEN zif_accx_change_repo=>co_operation-added   THEN |Locked ({ change-value_new })|
                   WHEN zif_accx_change_repo=>co_operation-removed THEN |Unlocked (was { change-value_old })|
                   ELSE |Lock changed to { change-value_new } (was { change-value_old })| ).
      WHEN zif_accx_change_repo=>co_area-validity.
        result = |Validity changed to { change-value_new } (was { change-value_old })|.
      WHEN zif_accx_change_repo=>co_area-password.
        result = |Password: { change-value_new }|.
      WHEN zif_accx_change_repo=>co_area-direct_profile.
        result = COND #( WHEN change-operation = zif_accx_change_repo=>co_operation-added
                         THEN |Profile { change-item } assigned directly|
                         ELSE |Profile { change-item } removed| ).
      WHEN OTHERS.
        result = |{ change-area } { change-operation }: { change-value_new }|.
    ENDCASE.
  ENDMETHOD.

  METHOD add_to_event.
    DATA(date_text) = |{ date DATE = ISO }|.
    DATA(time_text) = |{ time TIME = ISO }|.
    " one save of an object is one event; its kind is the most significant one
    READ TABLE events ASSIGNING FIELD-SYMBOL(<event>)
         WITH KEY date = date_text time = time_text changed_by = CONV string( changed_by )
                  object_type = object_type object = object.
    IF sy-subrc = 0.
      DATA(order) = VALUE string_table( ( co_kind-role_created ) ( co_kind-role_deleted ) ( co_kind-role_content )
                                        ( co_kind-assignment ) ( co_kind-direct_profile ) ( co_kind-user_master ) ).
      IF line_index( order[ table_line = kind ] ) < line_index( order[ table_line = <event>-kind ] ).
        <event>-kind = kind.
      ENDIF.
    ELSE.
      APPEND VALUE #( date        = date_text
                      time        = time_text
                      changed_by  = changed_by
                      tcode       = tcode
                      object_type = object_type
                      object      = object
                      kind        = kind ) TO events ASSIGNING <event>.
    ENDIF.
    IF self_change = abap_true.
      <event>-self_change = abap_true.
    ENDIF.
    IF <event>-tcode IS INITIAL.
      <event>-tcode = tcode.
    ENDIF.
    IF NOT line_exists( <event>-changes[ table_line = text ] ).
      APPEND text TO <event>-changes.
    ENDIF.
  ENDMETHOD.

  METHOD count.
    READ TABLE counts ASSIGNING FIELD-SYMBOL(<count>) WITH KEY name = name.
    IF sy-subrc <> 0.
      APPEND VALUE #( name = name ) TO counts ASSIGNING <count>.
    ENDIF.
    <count>-events += 1.
  ENDMETHOD.

  METHOD pattern.
    sign   = 'I'.
    option = COND #( WHEN value CA '*+' THEN 'CP' ELSE 'EQ' ).
  ENDMETHOD.

  METHOD parse_date.
    DATA(digits) = replace( val = condense( text ) sub = `-` with = `` occ = 0 ).
    IF digits IS INITIAL.
      result = default.
      RETURN.
    ENDIF.
    IF strlen( digits ) <> 8 OR digits CN '0123456789'.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = |{ name } "{ text }" is not a date YYYY-MM-DD.| ).
    ENDIF.
    result = digits.
    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING  date                      = result
      EXCEPTIONS plausibility_check_failed = 1
                 OTHERS                    = 2.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = |{ name } "{ text }" is not a valid date.| ).
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |Changes from { <payload>-from } to { <payload>-to }| &&
                     |{ COND #( WHEN <payload>-selection IS NOT INITIAL THEN |, { <payload>-selection }| ) }| &&
                     |{ COND #( WHEN <payload>-scope <> co_scope-all THEN |, scope { <payload>-scope }| ) }: | &&
                     |{ COND #( WHEN <payload>-events_total = 0 THEN `no changes`
                                ELSE |**{ <payload>-events_total } events** ({ <payload>-changes_total } single changes)| ) }.|.
    IF <payload>-by_kind IS NOT INITIAL.
      result-summary = |{ result-summary }\n- By kind: { concat_lines_of( sep   = `, `
                                                                         table = VALUE string_table( FOR k IN <payload>-by_kind ( |{ k-name } { k-events }| ) ) ) }| &&
                       |\n- Changed by: { concat_lines_of( sep   = `, `
                                                            table = VALUE string_table( FOR c IN <payload>-by_changer ( |{ c-name } { c-events }| ) ) ) }|.
    ENDIF.
    IF <payload>-critical IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Critical:**|.
      LOOP AT <payload>-critical INTO DATA(critical).
        result-summary = |{ result-summary }\n- { critical }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-events IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Events, newest first:**|.
      LOOP AT <payload>-events INTO DATA(event).
        result-summary = |{ result-summary }\n- { event-date } { event-time } **{ event-changed_by }**| &&
                         |{ COND #( WHEN event-tcode IS NOT INITIAL THEN | ({ event-tcode })| ) } { event-object_type } **{ event-object }**| &&
                         |{ COND #( WHEN event-self_change = abap_true THEN ` - own access` ) }: |.
        LOOP AT event-changes INTO DATA(line) TO co_lines_in_summary.
          result-summary = |{ result-summary }{ COND #( WHEN sy-tabix > 1 THEN `; ` ) }{ line }|.
        ENDLOOP.
        IF lines( event-changes ) > co_lines_in_summary.
          result-summary = |{ result-summary }; and { lines( event-changes ) - co_lines_in_summary } more|.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nList cut to max_rows ({ result-total_count } events) - shorten the period or filter by user, role or changed_by.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\nChanges of { result-hidden_by_authorization } users or roles left out due to missing | &&
                       |authorization for change documents (S_USER_GRP / S_USER_AGR, activity 08).|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

