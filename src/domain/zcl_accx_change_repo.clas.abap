"! <p class="shorttext synchronized">Access Explorer: change documents from DB</p>
"! Sources: CDHDR/CDPOS (objects PFCG and IDENTITY), USH02, USR02, AGR_1016.
"! Table keys of the change document items are cut by the key layout of the logged tables.
CLASS zcl_accx_change_repo DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_change_repo.

  PROTECTED SECTION.
    "! added, removed or changed from the change indicator of a change document item
    METHODS operation
      IMPORTING !indicator    TYPE cdchngind
      RETURNING VALUE(result) TYPE string.

    METHODS lock_text
      IMPORTING !flag         TYPE xuuflag
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_change_repo IMPLEMENTATION.

  METHOD zif_accx_change_repo~get_role_changes.
    DATA roles TYPE RANGE OF cdobjectv.
    DATA seen TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    roles = VALUE #( FOR r IN selection-roles ( sign = r-sign option = r-option low = r-low high = r-high ) ).
    SELECT h~objectid, h~changenr, h~username, h~udate, h~utime, h~tcode,
           p~tabname, p~tabkey, p~fname, p~chngind, p~value_new, p~value_old
      FROM cdhdr AS h INNER JOIN cdpos AS p
        ON  p~objectclas = h~objectclas
        AND p~objectid   = h~objectid
        AND p~changenr   = h~changenr
      WHERE h~objectclas = 'PFCG'
        AND h~objectid  IN @roles
        AND h~udate     BETWEEN @selection-from AND @selection-to
        AND h~username  IN @selection-changed_by
        AND p~tabname   IN ('AGR_USERS', 'AGR_DEFINE', 'CD1250', 'CD1251', 'CD1252', 'AGR_AGRS', 'AGR_OBJ', 'CD1016', 'AGR_TEXTS')
      ORDER BY h~udate, h~utime, h~changenr, p~tabname, p~tabkey, p~fname
      INTO TABLE @DATA(rows).

    LOOP AT rows INTO DATA(row).
      DATA(change) = VALUE zif_accx_change_repo=>ty_role_change( role       = row-objectid
                                                                  changed_by = row-username
                                                                  date       = row-udate
                                                                  time       = row-utime
                                                                  tcode      = condense( row-tcode )
                                                                  operation  = operation( row-chngind ) ).
      IF change-operation IS INITIAL.
        CONTINUE.
      ENDIF.
      " a key-level change is logged once per field of the record: report it once
      DATA(key_level) = abap_false.
      CASE row-tabname.
        WHEN 'AGR_USERS'.
          IF row-fname <> 'KEY'.
            CONTINUE.
          ENDIF.
          change-area      = zif_accx_change_repo=>co_area-assignment.
          change-user      = row-tabkey+33(12).
          change-valid_from = row-tabkey+45(8).
          change-valid_to   = row-tabkey+53(8).
          key_level = abap_true.
        WHEN 'AGR_DEFINE'.
          " creation is logged as key insert, deletion as field deletions of the record
          IF row-fname = 'KEY' OR row-chngind = 'E' OR row-chngind = 'J'.
            change-area = zif_accx_change_repo=>co_area-role.
            key_level = abap_true.
          ELSEIF row-fname = 'PARENT_AGR'.
            change-area      = zif_accx_change_repo=>co_area-role.
            change-item      = `reference role`.
            change-operation = zif_accx_change_repo=>co_operation-changed.
            change-value_new = condense( row-value_new ).
            change-value_old = condense( row-value_old ).
            IF change-value_new = change-value_old.
              CONTINUE.
            ENDIF.
          ELSE.
            CONTINUE.
          ENDIF.
        WHEN 'CD1250'.
          " the authorization name is a placeholder until the profile is generated: object only
          change-area = zif_accx_change_repo=>co_area-authorization.
          change-item = condense( row-tabkey+30(10) ).
          key_level = abap_true.
        WHEN 'CD1251' OR 'CD1252'.
          IF row-fname <> 'LOW' AND row-fname <> 'HIGH'.
            CONTINUE.
          ENDIF.
          IF row-tabname = 'CD1251'.
            change-area = zif_accx_change_repo=>co_area-value.
            change-item = |{ condense( row-tabkey+30(10) ) } { condense( row-tabkey+52(10) ) }|.
          ELSE.
            change-area = zif_accx_change_repo=>co_area-org_level.
            change-item = condense( row-tabkey+30(30) ).
          ENDIF.
          IF row-fname = 'HIGH'.
            change-item = |{ change-item } (upper limit)|.
          ENDIF.
          change-value_new = condense( row-value_new ).
          change-value_old = condense( row-value_old ).
          IF change-value_new IS INITIAL AND change-value_old IS INITIAL.
            CONTINUE.
          ENDIF.
        WHEN 'AGR_AGRS'.
          IF row-fname <> 'KEY'.
            CONTINUE.
          ENDIF.
          change-area = zif_accx_change_repo=>co_area-composite.
          change-item = condense( row-tabkey+33(30) ).
          key_level = abap_true.
        WHEN 'AGR_OBJ'.
          IF row-fname <> 'KEY'.
            CONTINUE.
          ENDIF.
          change-area = zif_accx_change_repo=>co_area-menu.
          change-item = |{ row-tabkey+41(2) } { condense( row-tabkey+43 ) }|.
          key_level = abap_true.
        WHEN 'CD1016'.
          IF row-fname <> 'KEY'.
            CONTINUE.
          ENDIF.
          change-area = zif_accx_change_repo=>co_area-profile.
          change-item = condense( row-tabkey+30(12) ).
          key_level = abap_true.
        WHEN 'AGR_TEXTS'.
          " short description only (line 00000)
          IF row-fname <> 'TEXT' OR row-tabkey+34(5) <> '00000'.
            CONTINUE.
          ENDIF.
          change-area      = zif_accx_change_repo=>co_area-text.
          change-item      = row-tabkey+33(1).
          change-value_new = condense( row-value_new ).
          change-value_old = condense( row-value_old ).
      ENDCASE.
      IF selection-users IS NOT INITIAL
         AND ( change-area <> zif_accx_change_repo=>co_area-assignment OR change-user NOT IN selection-users ).
        CONTINUE.
      ENDIF.
      IF key_level = abap_true.
        INSERT |{ row-changenr }/{ row-tabname }/{ row-tabkey }/{ change-operation }| INTO TABLE seen.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.
      APPEND change TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_change_repo~get_user_changes.
    DATA users TYPE RANGE OF cdobjectv.
    DATA profiles TYPE RANGE OF xuprofile.

    " logon data: diff each history record in the period against the one before
    SELECT bname, modda, modti, modbe, tcode, class, ustyp, uflag, gltgv, gltgb,
           pwdinitial, bcode, passcode, pwdsaltedhash
      FROM ush02
      WHERE bname IN @selection-users
        AND modda <= @selection-to
        AND bname IN ( SELECT bname FROM ush02 WHERE modda BETWEEN @selection-from AND @selection-to )
      ORDER BY bname, modda, modti
      INTO TABLE @DATA(history).
    DATA before LIKE LINE OF history.
    LOOP AT history INTO DATA(record).
      DATA(index) = sy-tabix.
      IF record-modda < selection-from OR record-modbe NOT IN selection-changed_by.
        CONTINUE.
      ENDIF.
      DATA(change) = VALUE zif_accx_change_repo=>ty_user_change( user       = record-bname
                                                                  user_group = record-class
                                                                  changed_by = record-modbe
                                                                  date       = record-modda
                                                                  time       = record-modti
                                                                  tcode      = condense( record-tcode ) ).
      CLEAR before.
      IF index > 1.
        before = history[ index - 1 ].
      ENDIF.
      IF before-bname <> record-bname.
        change-area      = zif_accx_change_repo=>co_area-created.
        change-operation = zif_accx_change_repo=>co_operation-added.
        change-value_new = |{ zcl_accx_user_hygiene=>user_type_text( record-ustyp ) } user| &&
                           |{ COND #( WHEN record-class IS NOT INITIAL THEN |, user group { record-class }| ) }|.
        APPEND change TO result.
        CONTINUE.
      ENDIF.
      IF record-class <> before-class.
        APPEND VALUE #( BASE change area = zif_accx_change_repo=>co_area-user_group
                                    operation = zif_accx_change_repo=>co_operation-changed
                                    value_new = record-class value_old = before-class ) TO result.
      ENDIF.
      IF record-ustyp <> before-ustyp.
        APPEND VALUE #( BASE change area = zif_accx_change_repo=>co_area-user_type
                                    operation = zif_accx_change_repo=>co_operation-changed
                                    value_new = zcl_accx_user_hygiene=>user_type_text( record-ustyp )
                                    value_old = zcl_accx_user_hygiene=>user_type_text( before-ustyp ) ) TO result.
      ENDIF.
      IF record-uflag <> before-uflag.
        APPEND VALUE #( BASE change area = zif_accx_change_repo=>co_area-lock
                                    operation = COND #( WHEN record-uflag = 0 THEN zif_accx_change_repo=>co_operation-removed
                                                        WHEN before-uflag = 0 THEN zif_accx_change_repo=>co_operation-added
                                                        ELSE zif_accx_change_repo=>co_operation-changed )
                                    value_new = lock_text( record-uflag )
                                    value_old = lock_text( before-uflag ) ) TO result.
      ENDIF.
      IF record-gltgv <> before-gltgv OR record-gltgb <> before-gltgb.
        APPEND VALUE #( BASE change area = zif_accx_change_repo=>co_area-validity
                                    operation = zif_accx_change_repo=>co_operation-changed
                                    value_new = |{ record-gltgv DATE = ISO } to { record-gltgb DATE = ISO }|
                                    value_old = |{ before-gltgv DATE = ISO } to { before-gltgb DATE = ISO }| ) TO result.
      ENDIF.
      " own password changes are routine; a password set by someone else is an administrator action
      IF record-modbe <> record-bname
         AND ( record-pwdsaltedhash <> before-pwdsaltedhash OR record-passcode <> before-passcode OR record-bcode <> before-bcode ).
        APPEND VALUE #( BASE change area = zif_accx_change_repo=>co_area-password
                                    operation = zif_accx_change_repo=>co_operation-changed
                                    value_new = COND #( WHEN record-pwdsaltedhash IS INITIAL AND record-passcode IS INITIAL AND record-bcode IS INITIAL
                                                        THEN `password deactivated`
                                                        WHEN record-pwdinitial = 1 THEN `initial password set`
                                                        ELSE `productive password set` ) ) TO result.
      ENDIF.
    ENDLOOP.

    " profiles assigned directly
    users = VALUE #( FOR u IN selection-users ( sign = u-sign option = u-option low = u-low high = u-high ) ).
    SELECT h~objectid, h~username, h~udate, h~utime, h~tcode, p~tabkey, p~chngind
      FROM cdhdr AS h INNER JOIN cdpos AS p
        ON  p~objectclas = h~objectclas
        AND p~objectid   = h~objectid
        AND p~changenr   = h~changenr
      WHERE h~objectclas = 'IDENTITY'
        AND h~objectid  IN @users
        AND h~udate     BETWEEN @selection-from AND @selection-to
        AND h~username  IN @selection-changed_by
        AND p~tabname    = 'SUSR_UST04'
        AND p~fname      = 'KEY'
      ORDER BY h~udate, h~utime, h~objectid, p~tabkey
      INTO TABLE @DATA(rows).
    IF rows IS NOT INITIAL.
      profiles = VALUE #( FOR row IN rows ( sign = 'I' option = 'EQ' low = row-tabkey(12) ) ).
      SELECT DISTINCT profile FROM agr_1016 WHERE profile IN @profiles INTO TABLE @DATA(generated).
      SELECT bname, class FROM usr02 WHERE bname IN @selection-users INTO TABLE @DATA(groups).
    ENDIF.
    LOOP AT rows INTO DATA(item).
      IF line_exists( generated[ profile = item-tabkey(12) ] ).
        CONTINUE.
      ENDIF.
      DATA(user) = CONV syuname( item-objectid ).
      DATA(group) = VALUE xuclass( groups[ bname = user ]-class OPTIONAL ).
      IF NOT line_exists( groups[ bname = user ] ).
        " deleted user: last user group of its history
        SELECT class FROM ush02 WHERE bname = @user ORDER BY modda DESCENDING, modti DESCENDING
          INTO @group UP TO 1 ROWS.
        ENDSELECT.
      ENDIF.
      APPEND VALUE #( user       = user
                      user_group = group
                      changed_by = item-username
                      date       = item-udate
                      time       = item-utime
                      tcode      = condense( item-tcode )
                      area       = zif_accx_change_repo=>co_area-direct_profile
                      operation  = operation( item-chngind )
                      item       = condense( item-tabkey(12) ) ) TO result.
    ENDLOOP.
    SORT result BY date time user area.
  ENDMETHOD.

  METHOD operation.
    result = SWITCH #( indicator
                       WHEN 'I' OR 'J' THEN zif_accx_change_repo=>co_operation-added
                       WHEN 'D' OR 'E' THEN zif_accx_change_repo=>co_operation-removed
                       WHEN 'U'        THEN zif_accx_change_repo=>co_operation-changed ).
  ENDMETHOD.

  METHOD lock_text.
    DATA reasons TYPE string_table.
    DATA(value) = CONV i( flag ).
    IF value = 0.
      result = `not locked`.
      RETURN.
    ENDIF.
    IF value DIV 128 MOD 2 = 1.
      APPEND `too many failed logon attempts` TO reasons.
    ENDIF.
    IF value DIV 64 MOD 2 = 1.
      APPEND `by administrator` TO reasons.
    ENDIF.
    IF value DIV 32 MOD 2 = 1.
      APPEND `globally (CUA)` TO reasons.
    ENDIF.
    IF value DIV 16 MOD 2 = 1.
      APPEND `inactivity / no valid password` TO reasons.
    ENDIF.
    result = COND #( WHEN reasons IS INITIAL THEN |locked (flag { value })|
                     ELSE |locked: { concat_lines_of( table = reasons sep = `, ` ) }| ).
  ENDMETHOD.

ENDCLASS.

