"! Cleanup of ZACCX_PLAN against an OpenSQL test double
CLASS ltc_cleanup DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CLASS-DATA environment TYPE REF TO if_osql_test_environment.
    DATA cut TYPE REF TO zif_accx_plan_store.

    CLASS-METHODS class_setup.
    CLASS-METHODS class_teardown.
    METHODS setup.

    "! seconds relative to now (negative = past)
    METHODS at
      IMPORTING !secs         TYPE i
      RETURNING VALUE(result) TYPE timestampl.

    METHODS state_of
      IMPORTING !plan_id      TYPE string
      RETURNING VALUE(result) TYPE string.

    METHODS actions
      IMPORTING !cleaned      TYPE zif_accx_plan_store=>ty_cleaned_list
      RETURNING VALUE(result) TYPE string.

    METHODS cleans_up FOR TESTING.
    METHODS test_only_changes_nothing FOR TESTING.
    METHODS keep_days_zero_keeps_closed FOR TESTING.

ENDCLASS.

CLASS ltc_cleanup IMPLEMENTATION.

  METHOD class_setup.
    environment = cl_osql_test_environment=>create( i_dependency_list = VALUE #( ( 'ZACCX_PLAN' ) ) ).
  ENDMETHOD.

  METHOD class_teardown.
    environment->destroy( ).
  ENDMETHOD.

  METHOD setup.
    DATA plans TYPE STANDARD TABLE OF zaccx_plan WITH EMPTY KEY.
    environment->clear_doubles( ).
    plans = VALUE #(
      ( plan_id = 'OPEN_OLD'    state = 'OPEN'     tool_name = 'apply_role_change' target = 'R1' expires_at = at( -600 ) )
      ( plan_id = 'OPEN_NEW'    state = 'OPEN'     tool_name = 'apply_role_change' target = 'R2' expires_at = at( 600 ) )
      ( plan_id = 'RUN_HANG'    state = 'RUNNING'  tool_name = 'assign_role'       target = 'U1' expires_at = at( -7200 ) )
      ( plan_id = 'RUN_RECENT'  state = 'RUNNING'  tool_name = 'assign_role'       target = 'U2' expires_at = at( -600 ) )
      ( plan_id = 'DONE_OLD'    state = 'EXECUTED' tool_name = 'assign_role'       target = 'U3' expires_at = at( -8640000 )
        closed_at = at( -8640000 ) )
      ( plan_id = 'DONE_NEW'    state = 'FAILED'   tool_name = 'assign_role'       target = 'U4' expires_at = at( -86400 )
        closed_at = at( -86400 ) ) ).
    environment->insert_test_data( plans ).
    cut = NEW zcl_accx_plan_store( ).
  ENDMETHOD.

  METHOD at.
    GET TIME STAMP FIELD DATA(now).
    result = cl_abap_tstmp=>add( tstmp = now secs = secs ).
  ENDMETHOD.

  METHOD state_of.
    result = cut->get( plan_id )-state.
  ENDMETHOD.

  METHOD actions.
    result = concat_lines_of( table = VALUE string_table( FOR c IN cleaned ( |{ c-plan_id }:{ c-action }| ) ) sep = `,` ).
  ENDMETHOD.

  METHOD cleans_up.
    DATA(cleaned) = cut->cleanup( ).

    cl_abap_unit_assert=>assert_equals( exp = `OPEN_OLD:expired,RUN_HANG:hanging,DONE_OLD:deleted` act = actions( cleaned ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'U1' act = cleaned[ 2 ]-target ).
    cl_abap_unit_assert=>assert_equals( exp = 'RUNNING' act = cleaned[ 2 ]-state ).
    cl_abap_unit_assert=>assert_equals( exp = 'CANCELLED' act = state_of( `OPEN_OLD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'OPEN' act = state_of( `OPEN_NEW` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'FAILED' act = state_of( `RUN_HANG` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `aborted: still running 60 minutes after expiry*check U1` act = cut->get( `RUN_HANG` )-outcome ).
    cl_abap_unit_assert=>assert_equals( exp = 'RUNNING' act = state_of( `RUN_RECENT` ) ).
    cl_abap_unit_assert=>assert_initial( cut->get( `DONE_OLD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'FAILED' act = state_of( `DONE_NEW` ) ).
    " a plan cancelled now is not deleted in the same run
    cl_abap_unit_assert=>assert_initial( cut->cleanup( ) ).
  ENDMETHOD.

  METHOD test_only_changes_nothing.
    DATA(cleaned) = cut->cleanup( test_only = abap_true ).

    cl_abap_unit_assert=>assert_equals( exp = `OPEN_OLD:expired,RUN_HANG:hanging,DONE_OLD:deleted` act = actions( cleaned ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'OPEN' act = state_of( `OPEN_OLD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'RUNNING' act = state_of( `RUN_HANG` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'EXECUTED' act = state_of( `DONE_OLD` ) ).
  ENDMETHOD.

  METHOD keep_days_zero_keeps_closed.
    DATA(cleaned) = cut->cleanup( hang_minutes = 5 keep_days = 0 ).

    cl_abap_unit_assert=>assert_equals( exp = `OPEN_OLD:expired,RUN_HANG:hanging,RUN_RECENT:hanging` act = actions( cleaned ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'EXECUTED' act = state_of( `DONE_OLD` ) ).
  ENDMETHOD.

ENDCLASS.
