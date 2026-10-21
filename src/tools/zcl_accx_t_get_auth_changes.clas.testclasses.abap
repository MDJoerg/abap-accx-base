"! Changes on 2026-10-01: R_A created by ADMIN (10:00), R_A validity for U1 changed (11:00, logged as removal and
"! new assignment), R_A assigned to SELF by SELF (12:00), R_B deleted (13:00), R_SECRET changed (14:00, hidden);
"! U1 created with SAP_ALL assigned directly (09:00), U_HID locked (15:00, hidden group), SELF changed its own
"! user group (16:00)
CLASS ltd_change_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_change_repo.
ENDCLASS.

CLASS ltd_change_repo IMPLEMENTATION.
  METHOD zif_accx_change_repo~get_role_changes.
    DATA(all) = VALUE zif_accx_change_repo=>ty_role_changes(
      date = '20261001' changed_by = 'ADMIN'
      ( role = 'R_A' time = '100000' tcode = `PFCG` area = `role` operation = `added` )
      ( role = 'R_A' time = '100000' area = `value` operation = `added` item = `S_TCODE TCD` value_new = `SU01` )
      ( role = 'R_A' time = '100000' area = `text` operation = `added` item = `E` value_new = `Role A` )
      ( role = 'R_A' time = '110000' area = `assignment` operation = `removed` user = 'U1' valid_from = '20260101' valid_to = '99991231' )
      ( role = 'R_A' time = '110000' area = `assignment` operation = `added` user = 'U1' valid_from = '20260101' valid_to = '20261231' )
      ( role = 'R_B' time = '130000' area = `role` operation = `removed` )
      ( role = 'R_B' time = '130000' area = `authorization` operation = `removed` item = `S_TCODE` )
      ( role = 'R_B' time = '130000' area = `value` operation = `removed` item = `S_TCODE TCD` value_old = `SU01` )
      ( role = 'R_SECRET' time = '140000' area = `value` operation = `added` item = `S_TCODE TCD` value_new = `SE16` ) ).
    APPEND VALUE #( date = '20261001' changed_by = 'SELF' role = 'R_A' time = '120000' area = `assignment` operation = `added`
                    user = 'SELF' valid_from = '20261001' valid_to = '99991231' ) TO all.
    LOOP AT all INTO DATA(change) WHERE role IN selection-roles.
      IF selection-users IS NOT INITIAL AND ( change-area <> `assignment` OR change-user NOT IN selection-users ).
        CONTINUE.
      ENDIF.
      APPEND change TO result.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_change_repo~get_user_changes.
    DATA(all) = VALUE zif_accx_change_repo=>ty_user_changes(
      date = '20261001'
      ( user = 'U1' user_group = 'G1' changed_by = 'ADMIN' time = '090000' tcode = `SU01` area = `created` operation = `added`
        value_new = `Dialog user, user group G1` )
      ( user = 'U1' user_group = 'G1' changed_by = 'ADMIN' time = '090000' area = `direct_profile` operation = `added` item = `SAP_ALL` )
      ( user = 'U_HID' user_group = 'HIDDEN' changed_by = 'ADMIN' time = '150000' area = `lock` operation = `added`
        value_new = `locked: by administrator` )
      ( user = 'SELF' user_group = 'G2' changed_by = 'SELF' time = '160000' area = `user_group` operation = `changed`
        value_new = `G2` value_old = `G1` ) ).
    result = VALUE #( FOR c IN all WHERE ( user IN selection-users ) ( c ) ).
  ENDMETHOD.
ENDCLASS.

"! Hides change documents of role R_SECRET and of user group HIDDEN
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role_changes.
    result = xsdbool( role <> 'R_SECRET' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_group_changes.
    result = xsdbool( user_group <> 'HIDDEN' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_auth_changes DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !from     TYPE string DEFAULT `2026-09-01`
                !to       TYPE string DEFAULT `2026-10-31`
                !user     TYPE string OPTIONAL
                !role     TYPE string OPTIONAL
                !scope    TYPE string OPTIONAL
                !max_rows TYPE i DEFAULT 50
      EXPORTING !result   TYPE zif_accx_types=>ty_result
                !payload  TYPE zcl_accx_t_get_auth_changes=>ty_payload
      RAISING   zcx_accx_error.

    METHODS events_and_critical FOR TESTING RAISING zcx_accx_error.
    METHODS scopes_and_filters  FOR TESTING RAISING zcx_accx_error.
    METHODS refusals            FOR TESTING.
ENDCLASS.

CLASS ltc_get_auth_changes IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( change_repo = NEW ltd_change_repo( ) ).
    cut = NEW zcl_accx_t_get_auth_changes( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_auth_changes=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `from` value = from ).
    args->set( name = `to` value = to ).
    IF user IS NOT INITIAL.
      args->set( name = `user` value = user ).
    ENDIF.
    IF role IS NOT INITIAL.
      args->set( name = `role` value = role ).
    ENDIF.
    IF scope IS NOT INITIAL.
      args->set( name = `scope` value = scope ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD events_and_critical.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    " role R_SECRET and user U_HID
    cl_abap_unit_assert=>assert_equals( exp = 2 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 11 act = payload-changes_total ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = payload-events_total ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SELF 16:00:00 user_master` ) ( `R_B 13:00:00 role_deleted` )
                                                                  ( `R_A 12:00:00 assignment` ) ( `R_A 11:00:00 assignment` )
                                                                  ( `R_A 10:00:00 role_created` ) ( `U1 09:00:00 direct_profile` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( |{ e-object } { e-time } { e-kind }| ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Role created` ) ( `S_TCODE TCD: value SU01 added` )
                                                                  ( `Description (E) "Role A"` ) )
                                        act = payload-events[ 5 ]-changes ).
    cl_abap_unit_assert=>assert_equals( exp = `PFCG` act = payload-events[ 5 ]-tcode ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Validity for U1 changed to 2026-01-01 to 2026-12-31 (was 2026-01-01 to 9999-12-31)` ) )
                                        act = payload-events[ 4 ]-changes ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Role deleted (2 items removed with it)` ) )
                                        act = payload-events[ 2 ]-changes ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `User created (Dialog user, user group G1)` ) ( `Profile SAP_ALL assigned directly` ) )
                                        act = payload-events[ 6 ]-changes ).
    cl_abap_unit_assert=>assert_true( payload-events[ 3 ]-self_change ).
    cl_abap_unit_assert=>assert_true( payload-events[ 1 ]-self_change ).
    cl_abap_unit_assert=>assert_false( payload-events[ 4 ]-self_change ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-self_changes ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_get_auth_changes=>ty_counts(
                                                  ( name = `assignment` events = 2 ) ( name = `direct_profile` events = 1 )
                                                  ( name = `role_created` events = 1 ) ( name = `role_deleted` events = 1 )
                                                  ( name = `user_master` events = 1 ) )
                                        act = payload-by_kind ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_get_auth_changes=>ty_counts( ( name = `ADMIN` events = 4 ) ( name = `SELF` events = 2 ) )
                                        act = payload-by_changer ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SAP_ALL assigned directly to U1 by ADMIN on 2026-10-01` )
                                                                  ( `SELF changed its own user master record on 2026-10-01` )
                                                                  ( `SELF changed its own assignment of role R_A on 2026-10-01` ) )
                                        act = payload-critical ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Changes from 2026-09-01 to 2026-10-31: **6 events** (11 single changes).*- Changed by: ADMIN 4, SELF 2*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- 2026-10-01 12:00:00 **SELF** role **R_A** - own access: Assigned to SELF (2026-10-01 to 9999-12-31)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Changes of 2 users or roles left out*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Clarify the critical events*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD scopes_and_filters.
    run( EXPORTING scope = `assignments` IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `R_A 12:00:00` ) ( `R_A 11:00:00` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( |{ e-object } { e-time }| ) ) ).
    run( EXPORTING scope = `role_content` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `R_B` ) ( `R_A` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( e-object ) ) ).
    run( EXPORTING scope = `users` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SELF` ) ( `U1` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( e-object ) ) ).
    " a user: its assignments and user master changes
    run( EXPORTING user = `u*` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `user U*` act = payload-selection ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `R_A 11:00:00` ) ( `U1 09:00:00` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( |{ e-object } { e-time }| ) ) ).
    " a role: no user master changes; a long period is fine with a role
    run( EXPORTING role = `R_B` from = `2020-01-01` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `R_B` ) )
                                        act = VALUE string_table( FOR e IN payload-events ( e-object ) ) ).
    run( EXPORTING max_rows = 2 IMPORTING result = DATA(result) payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-events ) ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( result-truncated ).
  ENDMETHOD.

  METHOD refusals.
    DATA(cases) = VALUE string_table( ( `from= ` ) ( `from=2026-13-01` ) ( `from=20261` ) ( `to=2026-08-01` )
                                      ( `from=2025-01-01` ) ( `scope=everything` ) ).
    LOOP AT cases INTO DATA(case).
      SPLIT case AT `=` INTO DATA(name) DATA(value).
      TRY.
          CASE name.
            WHEN `from`.
              run( from = value ).
            WHEN `to`.
              run( to = value ).
            WHEN `scope`.
              run( scope = value ).
          ENDCASE.
          cl_abap_unit_assert=>fail( |invalid expected for { case }| ).
        CATCH zcx_accx_error INTO DATA(error).
          cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status msg = case ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
