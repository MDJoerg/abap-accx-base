"! <p class="shorttext synchronized">Access Explorer: user master data from DB</p>
"! Sources: USR02, USR21/ADRP, AGR_USERS, AGR_TEXTS, UST04, USR11, AGR_1016, profile parameters.
CLASS zcl_accx_user_repo DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo.

  PROTECTED SECTION.
    METHODS user_type_text
      IMPORTING !code         TYPE xuustyp
      RETURNING VALUE(result) TYPE string.

    METHODS lock_reasons
      IMPORTING !flag         TYPE xuuflag
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_user_repo IMPLEMENTATION.

  METHOD zif_accx_user_repo~exists.
    SELECT SINGLE @abap_true FROM usr02 WHERE bname = @user INTO @result.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_user.
    SELECT SINGLE bname, ustyp, class, gltgv, gltgb, uflag, trdat, ltime,
                  pwdinitial, bcode, passcode, pwdsaltedhash
      FROM usr02
      WHERE bname = @user
      INTO @DATA(master).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SELECT SINGLE adrp~name_first, adrp~name_last
      FROM usr21 INNER JOIN adrp ON adrp~persnumber = usr21~persnumber
      WHERE usr21~bname = @user
        AND adrp~nation = @space
      INTO @DATA(name).

    result = VALUE #( user           = master-bname
                      full_name      = condense( |{ name-name_first } { name-name_last }| )
                      user_type      = user_type_text( master-ustyp )
                      user_type_code = master-ustyp
                      user_group     = master-class
                      valid_from     = master-gltgv
                      valid_to       = master-gltgb
                      locked         = xsdbool( master-uflag <> 0 )
                      lock_reasons   = lock_reasons( master-uflag ) ).

    result-last_logon = COND #( WHEN master-trdat IS INITIAL
                                THEN `never`
                                ELSE |{ master-trdat DATE = ISO } { master-ltime TIME = ISO }| ).

    IF master-pwdsaltedhash IS INITIAL AND master-passcode IS INITIAL AND master-bcode IS INITIAL.
      result-password_state = `no password (password logon not possible)`.
    ELSEIF master-pwdinitial = 1.  " IBOOLEAN3: 1 initial, 2 not initial
      result-password_state = `initial (must be changed at next logon)`.
    ELSE.
      result-password_state = `productive`.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_role_assignments.
    SELECT agr_name, from_dat, to_dat, col_flag
      FROM agr_users
      WHERE uname = @user
      ORDER BY agr_name, from_dat
      INTO TABLE @DATA(assignments).
    IF assignments IS INITIAL.
      RETURN.
    ENDIF.

    SELECT agr_name, text FROM agr_texts
      FOR ALL ENTRIES IN @assignments
      WHERE agr_name = @assignments-agr_name
        AND spras    = @sy-langu
        AND line     = 0
      INTO TABLE @DATA(texts).

    LOOP AT assignments INTO DATA(assignment).
      APPEND VALUE #( role          = assignment-agr_name
                      description   = VALUE #( texts[ agr_name = assignment-agr_name ]-text OPTIONAL )
                      valid_from    = assignment-from_dat
                      valid_to      = assignment-to_dat
                      active        = xsdbool( sy-datum BETWEEN assignment-from_dat AND assignment-to_dat )
                      via_composite = xsdbool( assignment-col_flag IS NOT INITIAL ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_profile_assignments.
    SELECT profile FROM ust04 WHERE bname = @user ORDER BY profile INTO TABLE @DATA(profiles).
    IF profiles IS INITIAL.
      RETURN.
    ENDIF.

    SELECT profn, ptext FROM usr11
      FOR ALL ENTRIES IN @profiles
      WHERE profn = @profiles-profile
        AND langu = @sy-langu
        AND aktps = 'A'
      INTO TABLE @DATA(texts).

    LOOP AT profiles INTO DATA(profile).
      APPEND VALUE #( profile     = profile-profile
                      description = VALUE #( texts[ profn = profile-profile ]-ptext OPTIONAL ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_group_members.
    result = zif_accx_user_repo~get_users( VALUE #( ( sign = 'I' option = 'EQ' low = user_group ) ) ).
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_users.
    SELECT bname, ustyp, class, gltgv, gltgb, uflag, trdat, pwdinitial, bcode, passcode, pwdsaltedhash
      FROM usr02
      WHERE class IN @user_groups
      ORDER BY bname
      INTO TABLE @DATA(masters).
    LOOP AT masters INTO DATA(master).
      APPEND VALUE #( user             = master-bname
                      user_type_code   = master-ustyp
                      user_group       = master-class
                      valid_from       = master-gltgv
                      valid_to         = master-gltgb
                      locked           = xsdbool( master-uflag <> 0 )
                      last_logon       = master-trdat
                      initial_password = xsdbool( master-pwdinitial = 1
                                                  AND ( master-pwdsaltedhash IS NOT INITIAL
                                                        OR master-passcode IS NOT INITIAL
                                                        OR master-bcode IS NOT INITIAL ) ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_group_assignments.
    SELECT DISTINCT agr_users~uname, agr_users~agr_name
      FROM agr_users INNER JOIN usr02 ON usr02~bname = agr_users~uname
      WHERE usr02~class         = @user_group
        AND agr_users~from_dat <= @sy-datum
        AND agr_users~to_dat   >= @sy-datum
      ORDER BY agr_users~uname, agr_users~agr_name
      INTO TABLE @DATA(rows).
    result = VALUE #( FOR row IN rows ( user = row-uname role = row-agr_name ) ).
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_group_direct_profiles.
    result = zif_accx_user_repo~get_direct_profiles( VALUE #( ( sign = 'I' option = 'EQ' low = user_group ) ) ).
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_role_counts.
    SELECT agr_users~uname, COUNT( DISTINCT agr_users~agr_name ) AS roles
      FROM agr_users INNER JOIN usr02 ON usr02~bname = agr_users~uname
      WHERE usr02~class         IN @user_groups
        AND agr_users~from_dat <= @sy-datum
        AND agr_users~to_dat   >= @sy-datum
      GROUP BY agr_users~uname
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      INSERT VALUE #( user = row-uname roles = row-roles ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_profile_parameter.
    DATA parameter TYPE c LENGTH 60.
    DATA value TYPE c LENGTH 128.
    parameter = name.
    CALL 'C_SAPGPARAM' ID 'NAME' FIELD parameter ID 'VALUE' FIELD value.
    result = condense( value ).
  ENDMETHOD.

  METHOD zif_accx_user_repo~get_direct_profiles.
    SELECT ust04~bname, ust04~profile
      FROM ust04 INNER JOIN usr02 ON usr02~bname = ust04~bname
      WHERE usr02~class IN @user_groups
        AND NOT EXISTS ( SELECT profile FROM agr_1016 WHERE profile = ust04~profile )
      ORDER BY ust04~bname, ust04~profile
      INTO TABLE @DATA(rows).
    result = VALUE #( FOR row IN rows ( user = row-bname profile = row-profile ) ).
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

  METHOD lock_reasons.
    DATA reasons TYPE string_table.
    DATA(value) = CONV i( flag ).
    IF value DIV 128 MOD 2 = 1.
      APPEND `too many failed logon attempts` TO reasons.
    ENDIF.
    IF value DIV 64 MOD 2 = 1.
      APPEND `locked by administrator` TO reasons.
    ENDIF.
    IF value DIV 32 MOD 2 = 1.
      APPEND `locked globally (CUA)` TO reasons.
    ENDIF.
    IF value DIV 16 MOD 2 = 1.
      APPEND `locked due to inactivity / no valid password` TO reasons.
    ENDIF.
    IF reasons IS INITIAL AND value <> 0.
      APPEND |lock flag { value }| TO reasons.
    ENDIF.
    result = concat_lines_of( table = reasons sep = `, ` ).
  ENDMETHOD.

ENDCLASS.
