*&---------------------------------------------------------------------*
*& Reveals the user behind a pseudonym of the privacy modes PSEUDONYMIZE and
*& MINIMIZE, or the pseudonym of a user. For people only - there is no tool
*& for it, so a client cannot undo its own pseudonyms. The caller needs
*& display authorization for the user (S_USER_GRP, activity 03) and every
*& lookup is written to the audit log ZACCX_LOG.
*&---------------------------------------------------------------------*
REPORT zaccx_pseudonym_resolve.

PARAMETERS p_pseud TYPE c LENGTH 20 LOWER CASE.
PARAMETERS p_user  TYPE xubname.

START-OF-SELECTION.
  IF ( p_pseud IS INITIAL AND p_user IS INITIAL ) OR ( p_pseud IS NOT INITIAL AND p_user IS NOT INITIAL ).
    MESSAGE 'Enter either a pseudonym or a user' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA(pseudonyms) = NEW zcl_accx_pseudonyms( ).
  DATA user TYPE syuname.
  DATA pseudonym TYPE string.
  DATA(outcome) = zif_accx_types=>co_status-ok.

  TRY.
      IF p_pseud IS NOT INITIAL.
        user      = pseudonyms->zif_accx_pseudonyms~user_for( p_pseud ).
        pseudonym = to_upper( condense( p_pseud ) ).
      ELSE.
        user      = p_user.
        pseudonym = pseudonyms->zif_accx_pseudonyms~pseudonym_for( user ).
      ENDIF.
      IF zcl_accx_factory=>guard( )->can_display_user( user ) = abap_false.
        outcome = zif_accx_types=>co_status-denied.
        MESSAGE |You are not authorized to display user { user } (S_USER_GRP, activity 03).| TYPE 'S' DISPLAY LIKE 'E'.
      ELSE.
        WRITE: / pseudonym, '=', user.
      ENDIF.
    CATCH zcx_accx_error INTO DATA(error).
      outcome = error->status.
      MESSAGE error->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

  " reveals are logged; the pseudonym is logged, never the clear user of a denied lookup
  NEW zcl_accx_logger_db( )->zif_accx_logger~log(
    VALUE #( caller    = sy-uname
             profile   = `report`
             system_id = sy-sysid
             tool_name = `pseudonym_resolve`
             status    = outcome
             message   = COND #( WHEN pseudonym IS NOT INITIAL THEN |pseudonym { pseudonym }| ) ) ).
  COMMIT WORK.
