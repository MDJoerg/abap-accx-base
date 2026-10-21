"! <p class="shorttext synchronized">Access Explorer: SUIM-like caller checks</p>
"! Display checks of the calling (named) user, cached per request.
CLASS zcl_accx_caller_guard DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.

  PRIVATE SECTION.
    CONSTANTS co_display TYPE activ_auth VALUE '03'.
    CONSTANTS co_change_documents TYPE activ_auth VALUE '08'.

    TYPES: BEGIN OF ty_decision,
             key     TYPE string,
             allowed TYPE abap_bool,
           END OF ty_decision.

    DATA decisions TYPE HASHED TABLE OF ty_decision WITH UNIQUE KEY key.

    METHODS cached
      IMPORTING !key          TYPE string
      EXPORTING !found        TYPE abap_bool
                !allowed      TYPE abap_bool.

    METHODS remember
      IMPORTING !key          TYPE string
                !allowed      TYPE abap_bool
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_caller_guard IMPLEMENTATION.

  METHOD zif_accx_caller_guard~can_display_user.
    DATA(key) = |U:{ user }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    SELECT SINGLE class FROM usr02 WHERE bname = @user INTO @DATA(group).
    IF sy-subrc <> 0.
      " unknown user: nothing that could be displayed
      result = remember( key = key allowed = abap_false ).
      RETURN.
    ENDIF.
    result = remember( key = key allowed = zif_accx_caller_guard~can_display_group( group ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_group.
    DATA(key) = |G:{ user_group }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP' ID 'CLASS' FIELD user_group ID 'ACTVT' FIELD co_display.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_group_changes.
    DATA(key) = |GC:{ user_group }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_GRP' ID 'CLASS' FIELD user_group ID 'ACTVT' FIELD co_change_documents.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_role_changes.
    DATA(key) = |RC:{ role }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD role ID 'ACTVT' FIELD co_change_documents.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_role.
    DATA(key) = |R:{ role }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_AGR' ID 'ACT_GROUP' FIELD role ID 'ACTVT' FIELD co_display.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_profile.
    DATA(key) = |P:{ profile }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    AUTHORITY-CHECK OBJECT 'S_USER_PRO' ID 'PROFILE' FIELD profile ID 'ACTVT' FIELD co_display.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_display_authorization.
    DATA(key) = |A:{ object }/{ auth }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    IF auth IS INITIAL.
      AUTHORITY-CHECK OBJECT 'S_USER_AUT' ID 'OBJECT' FIELD object ID 'AUTH' DUMMY ID 'ACTVT' FIELD co_display.
    ELSE.
      AUTHORITY-CHECK OBJECT 'S_USER_AUT' ID 'OBJECT' FIELD object ID 'AUTH' FIELD auth ID 'ACTVT' FIELD co_display.
    ENDIF.
    result = remember( key = key allowed = xsdbool( sy-subrc = 0 ) ).
  ENDMETHOD.

  METHOD zif_accx_caller_guard~can_preview_privileged.
    DATA(key) = |DP:{ entity }|.
    cached( EXPORTING key = key IMPORTING found = DATA(found) allowed = result ).
    IF found = abap_true.
      RETURN.
    ENDIF.
    TRY.
        cl_data_prev_auth_chk_factory=>get_auth_check_instance( )->check_authorization(
          EXPORTING iv_object_name  = entity
                    iv_override_dcl = abap_true
          IMPORTING ev_authorized   = DATA(authorized) ).
      CATCH cx_root ##CATCH_ALL.
        " the check raises an exception when the caller is not authorized
        authorized = abap_false.
    ENDTRY.
    result = remember( key = key allowed = authorized ).
  ENDMETHOD.

  METHOD cached.
    READ TABLE decisions INTO DATA(decision) WITH TABLE KEY key = key.
    found   = xsdbool( sy-subrc = 0 ).
    allowed = decision-allowed.
  ENDMETHOD.

  METHOD remember.
    INSERT VALUE #( key = key allowed = allowed ) INTO TABLE decisions.
    result = allowed.
  ENDMETHOD.

ENDCLASS.

