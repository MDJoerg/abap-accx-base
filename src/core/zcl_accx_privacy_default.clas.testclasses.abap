CLASS ltd_pseudonyms DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_accx_pseudonyms.
ENDCLASS.

CLASS ltd_pseudonyms IMPLEMENTATION.

  METHOD zif_accx_pseudonyms~pseudonym_for.
    result = |U-{ to_upper( condense( CONV string( user ) ) ) }|.
  ENDMETHOD.

  METHOD zif_accx_pseudonyms~is_pseudonym.
    result = xsdbool( to_upper( condense( CONV string( text ) ) ) CP 'U-*' ).
  ENDMETHOD.

  METHOD zif_accx_pseudonyms~user_for.
    DATA(value) = to_upper( condense( CONV string( pseudonym ) ) ).
    IF value = 'U-NOBODY'.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |No user for { value }| ).
    ENDIF.
    result = substring_after( val = value sub = 'U-' ).
  ENDMETHOD.

ENDCLASS.

CLASS ltd_real_pseudonyms DEFINITION FINAL INHERITING FROM zcl_accx_pseudonyms.
  PROTECTED SECTION.
    METHODS get_key   REDEFINITION.
    METHODS all_users REDEFINITION.
ENDCLASS.

CLASS ltd_real_pseudonyms IMPLEMENTATION.

  METHOD get_key.
    result = `00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF`.
  ENDMETHOD.

  METHOD all_users.
    result = VALUE #( ( `JDOE` ) ( `ASMITH` ) ( `ACCX_T_DEV` ) ).
  ENDMETHOD.

ENDCLASS.

CLASS ltc_privacy DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_member,
             user       TYPE string,
             full_name  TYPE string,
             last_logon TYPE string,
             role       TYPE string,
           END OF ty_member,
           ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             owner      TYPE syuname,
             changed_by TYPE string,
             members    TYPE ty_members,
             holders    TYPE string,
             users      TYPE string_table,
             note       TYPE string,
             valid_to   TYPE d,
           END OF ty_payload.

    TYPES: BEGIN OF ty_dated,
             last_logon TYPE d,
           END OF ty_dated.

    TYPES ty_sorted TYPE SORTED TABLE OF string WITH NON-UNIQUE KEY table_line.

    METHODS new_privacy
      IMPORTING !mode         TYPE string
      RETURNING VALUE(result) TYPE REF TO zcl_accx_privacy_default.

    METHODS sample
      RETURNING VALUE(result) TYPE REF TO ty_payload.

    METHODS user_ids_become_pseudonyms FOR TESTING.
    METHODS names_are_removed FOR TESTING.
    METHODS texts_use_pseudonyms FOR TESTING.
    METHODS lists_are_pseudonymized FOR TESTING.
    METHODS logon_kept_when_pseudonymizing FOR TESTING.
    METHODS logon_rounded_when_minimizing FOR TESTING.
    METHODS date_rounded_when_minimizing FOR TESTING.
    METHODS times_in_texts_are_rounded FOR TESTING.
    METHODS serialized_data_is_withheld FOR TESTING.
    METHODS sorted_table_is_withheld FOR TESTING.
    METHODS resolve_replaces_pseudonyms FOR TESTING RAISING zcx_accx_error.
    METHODS resolve_keeps_clear_args FOR TESTING RAISING zcx_accx_error.
    METHODS resolve_rejects_unknown FOR TESTING.
    METHODS error_text_hides_resolved_user FOR TESTING RAISING zcx_accx_error.

ENDCLASS.

CLASS ltc_privacy IMPLEMENTATION.

  METHOD new_privacy.
    result = NEW #( mode = mode pseudonyms = NEW ltd_pseudonyms( ) ).
  ENDMETHOD.

  METHOD sample.
    result = NEW #( owner      = 'JDOE'
                    changed_by = 'ASMITH'
                    members    = VALUE #( ( user = 'JDOE' full_name = 'Jane Doe' last_logon = '2026-10-21 13:45:02' role = 'JDOE_ROLE' )
                                          ( user = 'ASMITH' full_name = 'Alex Smith' last_logon = '2026-09-02 08:00:00' role = 'ZACCX_T_DEV' ) )
                    holders    = 'JDOE, ASMITH;BOB'
                    users      = VALUE #( ( `JDOE` ) ( `BOB` ) )
                    note       = 'Jane Doe asked JDOE about it'
                    valid_to   = '20261231' ).
  ENDMETHOD.

  METHOD user_ids_become_pseudonyms.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = sample( ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    DATA(payload) = CAST ty_payload( result-data ).
    cl_abap_unit_assert=>assert_equals( act = CONV string( payload->owner ) exp = `U-JDOE` ).
    cl_abap_unit_assert=>assert_equals( act = payload->changed_by exp = `U-ASMITH` ).
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 1 ]-user exp = `U-JDOE` ).
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 2 ]-user exp = `U-ASMITH` ).
    " not a user field: kept, and an id inside a longer name is not touched
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 1 ]-role exp = `JDOE_ROLE` ).
    cl_abap_unit_assert=>assert_equals( act = payload->valid_to exp = CONV d( '20261231' ) ).
  ENDMETHOD.

  METHOD names_are_removed.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = sample( ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    DATA(payload) = CAST ty_payload( result-data ).
    cl_abap_unit_assert=>assert_initial( payload->members[ 1 ]-full_name ).
    cl_abap_unit_assert=>assert_initial( payload->members[ 2 ]-full_name ).
    " the name is also removed from free text, the user id is replaced
    cl_abap_unit_assert=>assert_equals( act = payload->note exp = `[removed] asked U-JDOE about it` ).
  ENDMETHOD.

  METHOD texts_use_pseudonyms.
    DATA(result) = VALUE zif_accx_types=>ty_result( data     = sample( )
                                                    summary  = `JDOE has 2 roles; ACCX_T_DEV is unrelated`
                                                    warnings = VALUE #( ( `Check ASMITH.` ) )
                                                    next_steps = VALUE #( ( `Ask JDOE or ASMITH` ) ( `JDOE_ROLE stays` ) ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = result-summary exp = `U-JDOE has 2 roles; ACCX_T_DEV is unrelated` ).
    cl_abap_unit_assert=>assert_equals( act = result-warnings[ 1 ] exp = `Check U-ASMITH.` ).
    cl_abap_unit_assert=>assert_equals( act = result-next_steps[ 1 ] exp = `Ask U-JDOE or U-ASMITH` ).
    cl_abap_unit_assert=>assert_equals( act = result-next_steps[ 2 ] exp = `JDOE_ROLE stays` ).
  ENDMETHOD.

  METHOD lists_are_pseudonymized.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = sample( ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    DATA(payload) = CAST ty_payload( result-data ).
    cl_abap_unit_assert=>assert_equals( act = payload->holders exp = `U-JDOE, U-ASMITH, U-BOB` ).
    cl_abap_unit_assert=>assert_equals( act = payload->users exp = VALUE string_table( ( `U-JDOE` ) ( `U-BOB` ) ) ).
  ENDMETHOD.

  METHOD logon_kept_when_pseudonymizing.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = sample( ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    DATA(payload) = CAST ty_payload( result-data ).
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 1 ]-last_logon exp = `2026-10-21 13:45:02` ).
  ENDMETHOD.

  METHOD logon_rounded_when_minimizing.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = sample( ) ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-minimize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    DATA(payload) = CAST ty_payload( result-data ).
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 1 ]-last_logon exp = `2026-10` ).
    cl_abap_unit_assert=>assert_equals( act = payload->members[ 2 ]-last_logon exp = `2026-09` ).
    " pseudonyms and removed names work as in the other mode
    cl_abap_unit_assert=>assert_equals( act = CONV string( payload->owner ) exp = `U-JDOE` ).
    cl_abap_unit_assert=>assert_initial( payload->members[ 1 ]-full_name ).
  ENDMETHOD.

  METHOD date_rounded_when_minimizing.
    " a date field cannot hold a month: it is set to the first day; unreadable values are dropped
    DATA(dated) = NEW ty_dated( last_logon = '20261021' ).
    DATA(result) = VALUE zif_accx_types=>ty_result( data = dated ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-minimize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = dated->last_logon exp = CONV d( '20261001' ) ).

    DATA(text) = NEW ty_member( last_logon = '13:45 yesterday' ).
    result = VALUE #( data = text ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-minimize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_initial( text->last_logon ).

    " text without a point in time is no personal detail
    DATA(never) = NEW ty_member( last_logon = 'never' ).
    result = VALUE #( data = never ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-minimize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = never->last_logon exp = `never` ).
  ENDMETHOD.

  METHOD times_in_texts_are_rounded.
    " a text that repeats a rounded logon time must not give the exact time away
    DATA(payload) = sample( ).
    payload->note = `Seen 2026-10-21 13:45:02, again on 2026-10-21 and 20261021.`.
    DATA(result) = VALUE zif_accx_types=>ty_result( data = payload summary = `Last logon 2026-10-21 13:45:02` ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-minimize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = payload->note exp = `Seen 2026-10, again on 2026-10 and 20261021.` ).
    cl_abap_unit_assert=>assert_equals( act = result-summary exp = `Last logon 2026-10` ).
  ENDMETHOD.

  METHOD serialized_data_is_withheld.
    DATA(result) = VALUE zif_accx_types=>ty_result( status = zif_accx_types=>co_status-ok
                                                    summary = `JDOE`
                                                    data_json = `{"user":"JDOE"}` ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = zif_accx_types=>co_status-error ).
    cl_abap_unit_assert=>assert_initial( result-data_json ).
    cl_abap_unit_assert=>assert_initial( result-summary ).
    cl_abap_unit_assert=>assert_not_initial( result-warnings ).
  ENDMETHOD.

  METHOD sorted_table_is_withheld.
    DATA(sorted) = NEW ty_sorted( ( `JDOE` ) ).
    DATA(result) = VALUE zif_accx_types=>ty_result( status = zif_accx_types=>co_status-ok data = sorted ).
    new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = zif_accx_types=>co_status-error ).
    cl_abap_unit_assert=>assert_not_bound( result-data ).
  ENDMETHOD.

  METHOD resolve_replaces_pseudonyms.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = `u-jdoe` )->set( name = `max_rows` value = 20 )->set_list( name = `users` values = VALUE #( ( `U-ASMITH` ) ( `BOB` ) ) ).
    DATA(clear) = new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~resolve_args( args ).
    cl_abap_unit_assert=>assert_equals( act = clear->get_string( `user` ) exp = `JDOE` ).
    cl_abap_unit_assert=>assert_equals( act = clear->get_integer( `max_rows` ) exp = 20 ).
    cl_abap_unit_assert=>assert_equals( act = clear->get_strings( `users` ) exp = VALUE string_table( ( `ASMITH` ) ( `BOB` ) ) ).
  ENDMETHOD.

  METHOD resolve_keeps_clear_args.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = `JDOE` ).
    DATA(same) = new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~resolve_args( args ).
    cl_abap_unit_assert=>assert_true( xsdbool( same = CAST zif_accx_args( args ) ) ).
  ENDMETHOD.

  METHOD resolve_rejects_unknown.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = `U-NOBODY` ).
    TRY.
        new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize )->zif_accx_privacy~resolve_args( args ).
        cl_abap_unit_assert=>fail( `An unknown pseudonym must be rejected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->status exp = zif_accx_types=>co_status-not_found ).
    ENDTRY.
  ENDMETHOD.

  METHOD error_text_hides_resolved_user.
    " the same privacy object resolves the argument and protects the failure message
    DATA(privacy) = new_privacy( zcl_accx_factory=>co_privacy_mode-pseudonymize ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = `U-JDOE` ).
    privacy->zif_accx_privacy~resolve_args( args ).
    DATA(result) = VALUE zif_accx_types=>ty_result( status  = zif_accx_types=>co_status-not_found
                                                    summary = `User JDOE does not exist in system A4H.` ).
    privacy->zif_accx_privacy~protect_result( CHANGING result = result ).
    cl_abap_unit_assert=>assert_equals( act = result-summary exp = `User U-JDOE does not exist in system A4H.` ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = zif_accx_types=>co_status-not_found ).
  ENDMETHOD.

ENDCLASS.

CLASS ltc_pseudonyms DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_pseudonyms.

    METHODS setup.
    METHODS has_prefix_and_hex FOR TESTING RAISING zcx_accx_error.
    METHODS is_stable_and_ignores_case FOR TESTING RAISING zcx_accx_error.
    METHODS differs_per_user FOR TESTING RAISING zcx_accx_error.
    METHODS resolves_back FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_pseudonym_is_rejected FOR TESTING.
    METHODS recognizes_pseudonyms FOR TESTING.

ENDCLASS.

CLASS ltc_pseudonyms IMPLEMENTATION.

  METHOD setup.
    cut = NEW ltd_real_pseudonyms( ).
  ENDMETHOD.

  METHOD has_prefix_and_hex.
    DATA(pseudonym) = cut->pseudonym_for( `JDOE` ).
    cl_abap_unit_assert=>assert_true( xsdbool( matches( val = pseudonym pcre = '^U-[0-9A-F]{8}$' ) ) ).
    cl_abap_unit_assert=>assert_true( cut->is_pseudonym( pseudonym ) ).
  ENDMETHOD.

  METHOD is_stable_and_ignores_case.
    cl_abap_unit_assert=>assert_equals( act = cut->pseudonym_for( `jdoe` ) exp = cut->pseudonym_for( `JDOE` ) ).
    cl_abap_unit_assert=>assert_equals( act = cut->pseudonym_for( ` JDOE ` ) exp = cut->pseudonym_for( `JDOE` ) ).
  ENDMETHOD.

  METHOD differs_per_user.
    cl_abap_unit_assert=>assert_differs( act = cut->pseudonym_for( `JDOE` ) exp = cut->pseudonym_for( `ASMITH` ) ).
  ENDMETHOD.

  METHOD resolves_back.
    cl_abap_unit_assert=>assert_equals( act = cut->user_for( cut->pseudonym_for( `ASMITH` ) ) exp = `ASMITH` ).
    cl_abap_unit_assert=>assert_equals( act = cut->user_for( to_lower( cut->pseudonym_for( `ACCX_T_DEV` ) ) ) exp = `ACCX_T_DEV` ).
  ENDMETHOD.

  METHOD unknown_pseudonym_is_rejected.
    TRY.
        cut->user_for( `U-00000000` ).
        cl_abap_unit_assert=>fail( `A pseudonym of no user must be rejected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->status exp = zif_accx_types=>co_status-not_found ).
    ENDTRY.
    TRY.
        cut->user_for( `JDOE` ).
        cl_abap_unit_assert=>fail( `A user id is not a pseudonym` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( act = error->status exp = zif_accx_types=>co_status-invalid ).
    ENDTRY.
  ENDMETHOD.

  METHOD recognizes_pseudonyms.
    cl_abap_unit_assert=>assert_true( cut->is_pseudonym( `U-7F3A9C12` ) ).
    cl_abap_unit_assert=>assert_true( cut->is_pseudonym( `u-7f3a9c12` ) ).
    cl_abap_unit_assert=>assert_false( cut->is_pseudonym( `U-7F3A9C1` ) ).
    cl_abap_unit_assert=>assert_false( cut->is_pseudonym( `U-7F3A9C123` ) ).
    cl_abap_unit_assert=>assert_false( cut->is_pseudonym( `JDOE` ) ).
  ENDMETHOD.

ENDCLASS.

CLASS ltc_audit DEFINITION FINAL FOR TESTING DURATION MEDIUM RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA privacy TYPE REF TO zcl_accx_privacy_default.
    DATA issues  TYPE string_table.

    METHODS audit_type
      IMPORTING !descr TYPE REF TO cl_abap_typedescr
                !names TYPE string_table
                !tool  TYPE string.

    "! Component names that point at people but are no personal data, with the reason
    METHODS not_personal
      IMPORTING !path         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS all_payloads_are_covered FOR TESTING.

ENDCLASS.

CLASS ltc_audit IMPLEMENTATION.

  METHOD not_personal.
    " These describe a user but identify nobody: groups and types, a reason text (user ids
    " inside it are replaced as in every text), and role/catalog names
    result = xsdbool( contains( val = path pcre = '(^|-)(USER_GROUP|USER_TYPE|USER_TYPES|USER_GROUPS|PEER_GROUP|LOGON_ISSUE|ENTITLED_BY)$' ) ).
  ENDMETHOD.

  METHOD audit_type.
    CASE descr->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        DATA(struct) = CAST cl_abap_structdescr( descr ).
        LOOP AT struct->get_components( ) INTO DATA(component).
          audit_type( descr = component-type
                      names = COND #( WHEN component-as_include = abap_true THEN names
                                      ELSE VALUE #( BASE names ( to_upper( component-name ) ) ) )
                      tool  = tool ).
        ENDLOOP.
      WHEN cl_abap_typedescr=>kind_table.
        DATA(table_descr) = CAST cl_abap_tabledescr( descr ).
        IF table_descr->table_kind <> cl_abap_tabledescr=>tablekind_std.
          APPEND |{ tool }: sorted or hashed table { concat_lines_of( table = names sep = `-` ) }| TO issues.
        ENDIF.
        audit_type( descr = table_descr->get_table_line_type( ) names = names tool = tool ).
      WHEN cl_abap_typedescr=>kind_elem.
        DATA(element) = CAST cl_abap_elemdescr( descr ).
        IF element->type_kind <> cl_abap_typedescr=>typekind_char AND element->type_kind <> cl_abap_typedescr=>typekind_string
           AND element->type_kind <> cl_abap_typedescr=>typekind_date.
          RETURN.
        ENDIF.
        " one-character fields are flags and codes
        IF privacy->classify( descr = element names = names ) IS NOT INITIAL OR names IS INITIAL
           OR element->length <= cl_abap_char_utilities=>charsize.
          RETURN.
        ENDIF.
        DATA(path) = concat_lines_of( table = names sep = `-` ).
        DATA(leaf) = names[ lines( names ) ].
        IF contains( val = leaf pcre = '(^|_)(USER|USERS|HOLDER|HOLDERS|PEER|PEERS|OWNER|MEMBER|MEMBERS|LOGON|MAIL|PHONE|PERSON|CHANGER|AUTHOR|CREATOR|BY)(_|$)' )
           AND not_personal( path ) = abap_false.
          APPEND |{ tool }: { path } looks personal but has no privacy rule| TO issues.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD all_payloads_are_covered.
    privacy = NEW #( mode = zcl_accx_factory=>co_privacy_mode-pseudonymize pseudonyms = NEW ltd_pseudonyms( ) ).
    " a profile without settings offers every tool of the active plugins
    DATA(tools) = zcl_accx_factory=>registry( )->get_tools( `ZACCX_UNIT_TEST_AUDIT` ).
    cl_abap_unit_assert=>assert_not_initial( act = tools msg = `no tools found` ).
    LOOP AT tools INTO DATA(tool).
      DATA(descriptor) = tool->get_descriptor( ).
      IF descriptor-output_type IS INITIAL.
        CONTINUE.
      ENDIF.
      TRY.
          audit_type( descr = cl_abap_typedescr=>describe_by_name( descriptor-output_type ) names = VALUE #( ) tool = descriptor-name ).
        CATCH cx_root INTO DATA(error).
          APPEND |{ descriptor-name }: output type { descriptor-output_type } not readable: { error->get_text( ) }| TO issues.
      ENDTRY.
    ENDLOOP.
    cl_abap_unit_assert=>assert_initial( act = issues msg = concat_lines_of( table = issues sep = `; ` ) ).
  ENDMETHOD.

ENDCLASS.
