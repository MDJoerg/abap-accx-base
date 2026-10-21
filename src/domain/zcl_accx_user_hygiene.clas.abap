"! <p class="shorttext synchronized">Access Explorer: user hygiene rules</p>
"! Hygiene findings of one user master record, shared by analyze_user_group and
"! get_user_hygiene_report. Logon findings (inactive, never logged on, initial password)
"! apply only to dialog users that can log on - not locked and not expired.
CLASS zcl_accx_user_hygiene DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    "! default number of days without logon after which a dialog user counts as inactive
    CONSTANTS co_inactive_days TYPE i VALUE 90.

    CONSTANTS: BEGIN OF co_finding,
                 direct_profile   TYPE string VALUE `direct_profile`,
                 inactive         TYPE string VALUE `inactive`,
                 never_logged_on  TYPE string VALUE `never_logged_on`,
                 initial_password TYPE string VALUE `initial_password`,
                 no_roles         TYPE string VALUE `no_roles`,
                 expired          TYPE string VALUE `expired`,
                 not_yet_valid    TYPE string VALUE `not_yet_valid`,
                 locked           TYPE string VALUE `locked`,
               END OF co_finding.

    TYPES: BEGIN OF ty_assessment,
             "! position of the worst finding in the severity order (1 = most severe); 0 = no findings
             severity      TYPE i,
             findings      TYPE string_table,
             finding_codes TYPE string_table,
           END OF ty_assessment.

    "! Finding codes, most severe first
    CLASS-METHODS severity_order
      RETURNING VALUE(result) TYPE string_table.

    "! Findings of one user
    "! @parameter roles           | number of roles assigned today
    "! @parameter direct_profiles | profiles assigned directly (not generated for a role)
    CLASS-METHODS assess
      IMPORTING !member          TYPE zif_accx_user_repo=>ty_member
                !roles           TYPE i
                !direct_profiles TYPE string_table
                !inactive_days   TYPE i DEFAULT co_inactive_days
                !today           TYPE d DEFAULT sy-datum
      RETURNING VALUE(result)    TYPE ty_assessment.

    CLASS-METHODS user_type_text
      IMPORTING !code         TYPE c
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS add
      IMPORTING !code   TYPE string
                !text   TYPE string
      CHANGING  !result TYPE ty_assessment.

ENDCLASS.

CLASS zcl_accx_user_hygiene IMPLEMENTATION.

  METHOD severity_order.
    result = VALUE #( ( co_finding-direct_profile )
                      ( co_finding-inactive )
                      ( co_finding-never_logged_on )
                      ( co_finding-initial_password )
                      ( co_finding-no_roles )
                      ( co_finding-expired )
                      ( co_finding-not_yet_valid )
                      ( co_finding-locked ) ).
  ENDMETHOD.

  METHOD assess.
    DATA(dialog) = xsdbool( member-user_type_code = 'A' ).
    DATA(expired) = xsdbool( member-valid_to IS NOT INITIAL AND member-valid_to < today ).
    DATA(can_log_on) = xsdbool( member-locked = abap_false AND expired = abap_false ).
    IF direct_profiles IS NOT INITIAL.
      add( EXPORTING code   = co_finding-direct_profile
                     text   = |Profiles assigned directly: { concat_lines_of( table = direct_profiles sep = `, ` ) }.|
           CHANGING  result = result ).
    ENDIF.
    IF dialog = abap_true AND can_log_on = abap_true AND member-last_logon IS NOT INITIAL
       AND today - member-last_logon > inactive_days.
      add( EXPORTING code   = co_finding-inactive
                     text   = |No logon for { today - member-last_logon } days (last { member-last_logon DATE = ISO }), not locked.|
           CHANGING  result = result ).
    ENDIF.
    IF dialog = abap_true AND can_log_on = abap_true AND member-last_logon IS INITIAL.
      add( EXPORTING code = co_finding-never_logged_on text = `Never logged on, not locked.` CHANGING result = result ).
    ENDIF.
    IF dialog = abap_true AND can_log_on = abap_true AND member-initial_password = abap_true.
      add( EXPORTING code = co_finding-initial_password text = `Initial password not changed yet.` CHANGING result = result ).
    ENDIF.
    IF roles = 0 AND direct_profiles IS INITIAL.
      add( EXPORTING code = co_finding-no_roles text = `No role assigned today.` CHANGING result = result ).
    ENDIF.
    IF expired = abap_true.
      add( EXPORTING code = co_finding-expired text = |Valid until { member-valid_to DATE = ISO }.| CHANGING result = result ).
    ENDIF.
    IF member-valid_from IS NOT INITIAL AND member-valid_from > today.
      add( EXPORTING code = co_finding-not_yet_valid text = |Valid from { member-valid_from DATE = ISO }.| CHANGING result = result ).
    ENDIF.
    IF member-locked = abap_true.
      add( EXPORTING code = co_finding-locked text = `Locked.` CHANGING result = result ).
    ENDIF.
    IF result-finding_codes IS NOT INITIAL.
      LOOP AT severity_order( ) INTO DATA(code).
        IF line_exists( result-finding_codes[ table_line = code ] ).
          result-severity = sy-tabix.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD user_type_text.
    result = SWITCH #( code
                       WHEN 'A' THEN `Dialog`
                       WHEN 'B' THEN `System`
                       WHEN 'C' THEN `Communication`
                       WHEN 'L' THEN `Reference`
                       WHEN 'S' THEN `Service`
                       ELSE |Unknown ({ code })| ).
  ENDMETHOD.

  METHOD add.
    APPEND code TO result-finding_codes.
    APPEND text TO result-findings.
  ENDMETHOD.

ENDCLASS.

