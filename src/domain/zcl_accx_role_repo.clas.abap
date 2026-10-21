"! <p class="shorttext synchronized">Access Explorer: role data from DB</p>
"! Sources: AGR_DEFINE, AGR_1250, AGR_1251, AGR_1252, AGR_1016, AGR_AGRS, AGR_FLAGS, AGR_TEXTS, AGR_TCODES,
"! AGR_USERS, UST04, USR02, USORG.
CLASS zcl_accx_role_repo DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_hit,
             agr_name TYPE agr_name,
             auth     TYPE xuauth,
           END OF ty_hit,
           ty_hits TYPE SORTED TABLE OF ty_hit WITH UNIQUE KEY agr_name auth.

    "! Does an authorization value (single, pattern or range) cover the checked value?
    METHODS value_matches
      IMPORTING !value        TYPE string
                !low          TYPE csequence
                !high         TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_role_repo IMPLEMENTATION.

  METHOD zif_accx_role_repo~find_roles_granting.
    DATA candidates TYPE ty_hits.
    DATA kept       TYPE ty_hits.
    DATA roles      TYPE SORTED TABLE OF agr_name WITH UNIQUE KEY table_line.

    IF check-fields IS INITIAL.
      SELECT DISTINCT agr_name, auth FROM agr_1250
        WHERE object = @check-object AND deleted = @space
        INTO CORRESPONDING FIELDS OF TABLE @candidates.
    ELSE.
      " first field: pre-filter on the database (exact value, pattern or range)
      DATA(first) = check-fields[ 1 ].
      DATA(first_value) = CONV agval( first-value ).
      SELECT agr_name, auth, low, high FROM agr_1251
        WHERE object  = @check-object
          AND field   = @first-field
          AND deleted = @space
          AND ( low = @first_value OR low LIKE '%*%' OR high <> @space )
        INTO TABLE @DATA(rows).
      LOOP AT rows INTO DATA(row).
        IF value_matches( value = first-value low = row-low high = row-high ) = abap_true.
          INSERT VALUE #( agr_name = row-agr_name auth = row-auth ) INTO TABLE candidates.
        ENDIF.
      ENDLOOP.

      " further fields: every one must be covered by the same authorization
      LOOP AT check-fields INTO DATA(field) FROM 2.
        IF candidates IS INITIAL.
          EXIT.
        ENDIF.
        SELECT agr_name, auth, low, high FROM agr_1251
          FOR ALL ENTRIES IN @candidates
          WHERE agr_name = @candidates-agr_name
            AND auth     = @candidates-auth
            AND object   = @check-object
            AND field    = @field-field
            AND deleted  = @space
          INTO TABLE @DATA(more).
        CLEAR kept.
        LOOP AT candidates INTO DATA(candidate).
          LOOP AT more INTO DATA(value_row) WHERE agr_name = candidate-agr_name AND auth = candidate-auth.
            IF value_matches( value = field-value low = value_row-low high = value_row-high ) = abap_true.
              INSERT candidate INTO TABLE kept.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
        candidates = kept.
      ENDLOOP.
    ENDIF.

    LOOP AT candidates INTO candidate.
      INSERT candidate-agr_name INTO TABLE roles.
    ENDLOOP.
    result = roles.
  ENDMETHOD.

  METHOD zif_accx_role_repo~exists.
    SELECT SINGLE @abap_true FROM agr_define WHERE agr_name = @role INTO @result.
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_role_info.
    result-role = role.
    SELECT SINGLE text FROM agr_texts
      WHERE agr_name = @role AND spras = @sy-langu AND line = 0
      INTO @result-description.
    SELECT child_agr FROM agr_agrs WHERE agr_name = @role ORDER BY child_agr INTO TABLE @DATA(children).
    result-children  = VALUE #( FOR child IN children ( CONV #( child-child_agr ) ) ).
    " PFCG marks composite roles in AGR_FLAGS; an empty composite role has no AGR_AGRS entry
    SELECT SINGLE flag_value FROM agr_flags WHERE agr_name = @role AND flag_type = 'COLL_AGR' INTO @DATA(composite_flag).
    result-composite = xsdbool( children IS NOT INITIAL OR composite_flag = abap_true ).
    SELECT SINGLE generated FROM agr_1016 WHERE agr_name = @role INTO @DATA(generated).
    result-generated = xsdbool( generated IS NOT INITIAL ).
    SELECT COUNT( DISTINCT object ) FROM agr_1250
      WHERE agr_name = @role AND deleted = @space
      INTO @result-object_count.
    SELECT SINGLE @abap_true FROM agr_1251
      WHERE agr_name = @role AND object = 'S_TCODE' AND field = 'TCD' AND low = '*' AND deleted = @space
      INTO @result-broad.
    SELECT agr_name FROM agr_agrs WHERE child_agr = @role INTO TABLE @DATA(parents).
    result-parents = VALUE #( FOR parent IN parents ( CONV #( parent-agr_name ) ) ).
    SELECT SINGLE parent_agr FROM agr_define WHERE agr_name = @role INTO @result-derived_from.
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_transactions.
    SELECT tcode FROM agr_tcodes
      WHERE agr_name = @role AND type = 'TR' AND exclude = @space
      ORDER BY tcode
      INTO TABLE @DATA(menu).
    result = VALUE #( FOR entry IN menu ( CONV #( entry-tcode ) ) ).
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_authorization_values.
    SELECT object, auth, field, low, high FROM agr_1251
      WHERE agr_name = @role AND deleted = @space
      INTO CORRESPONDING FIELDS OF TABLE @result.
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_maintenance.
    SELECT profile FROM agr_1016 WHERE agr_name = @role ORDER BY profile INTO TABLE @DATA(profiles).
    result-profiles = VALUE #( FOR p IN profiles ( CONV #( p-profile ) ) ).

    " PFCG status of an authorization: S standard, G maintained, M changed, U manual
    SELECT modified, deleted, COUNT(*) AS count FROM agr_1250 WHERE agr_name = @role
      GROUP BY modified, deleted INTO TABLE @DATA(states).
    LOOP AT states INTO DATA(state).
      IF state-deleted IS NOT INITIAL.
        result-inactive += state-count.
        CONTINUE.
      ENDIF.
      CASE state-modified.
        WHEN 'G'.
          result-maintained += state-count.
        WHEN 'M'.
          result-changed += state-count.
        WHEN 'U'.
          result-manual += state-count.
        WHEN OTHERS.
          result-standard += state-count.
      ENDCASE.
    ENDLOOP.

    SELECT DISTINCT object, field FROM agr_1251
      WHERE agr_name = @role AND deleted = @space AND low = @space AND high = @space
      ORDER BY object, field INTO TABLE @DATA(open).
    result-open_fields = VALUE #( FOR o IN open ( |{ o-object }-{ o-field }| ) ).
    SELECT varbl, low, high FROM agr_1252 WHERE agr_name = @role ORDER BY varbl, low INTO TABLE @DATA(levels).
    result-org_levels = VALUE #( FOR l IN levels ( level = condense( l-varbl ) low = condense( l-low ) high = condense( l-high ) ) ).

    " holders today without the generated profile in their user master
    IF profiles IS NOT INITIAL.
      DATA(profile) = profiles[ 1 ]-profile.
      SELECT COUNT( DISTINCT u~uname ) FROM agr_users AS u
        WHERE u~agr_name = @role AND u~from_dat <= @sy-datum AND u~to_dat >= @sy-datum
          AND NOT EXISTS ( SELECT bname FROM ust04 WHERE bname = u~uname AND profile = @profile )
        INTO @result-comparison_pending.
    ENDIF.

    SELECT SINGLE create_usr, create_dat, change_usr, change_dat FROM agr_define WHERE agr_name = @role INTO @DATA(definition).
    result-created_by = definition-create_usr.
    result-created_on = definition-create_dat.
    result-changed_by = definition-change_usr.
    result-changed_on = definition-change_dat.
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_authorizations.
    DATA objects TYPE RANGE OF xuobject.
    IF object IS NOT INITIAL.
      objects = VALUE #( ( sign = 'I' option = 'EQ' low = object ) ).
    ENDIF.
    SELECT object, auth, atext, modified, deleted FROM agr_1250
      WHERE agr_name = @role AND object IN @objects
      ORDER BY object, auth INTO TABLE @DATA(headers).
    IF headers IS INITIAL.
      RETURN.
    ENDIF.
    SELECT object, auth, field, low, high FROM agr_1251
      WHERE agr_name = @role AND object IN @objects
      ORDER BY object, auth, field, low INTO TABLE @DATA(rows).
    LOOP AT headers INTO DATA(header).
      INSERT VALUE #( object   = header-object
                      auth     = header-auth
                      text     = header-atext
                      status   = COND #( WHEN header-modified = 'G' OR header-modified = 'M' OR header-modified = 'U'
                                         THEN header-modified ELSE 'S' )
                      inactive = xsdbool( header-deleted IS NOT INITIAL )
                      values   = VALUE #( FOR row IN rows WHERE ( object = header-object AND auth = header-auth )
                                          ( CORRESPONDING #( row ) ) ) ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_role_repo~find_by_pattern.
    " literal _ and % are escaped, then * and + become the SQL wildcards
    DATA(like) = replace( val = to_upper( condense( pattern ) ) pcre = `([_%#])` with = `#$1` occ = 0 ).
    like = replace( val = replace( val = like sub = `*` with = `%` occ = 0 ) sub = `+` with = `_` occ = 0 ).
    SELECT agr_name FROM agr_define WHERE agr_name LIKE @like ESCAPE '#'
      ORDER BY agr_name INTO TABLE @result UP TO @max_count ROWS.
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_org_fields.
    SELECT DISTINCT field FROM usorg ORDER BY field INTO TABLE @DATA(fields).
    result = VALUE #( FOR f IN fields ( CONV #( f-field ) ) ).
  ENDMETHOD.

  METHOD zif_accx_role_repo~get_derived_roles.
    SELECT agr_name FROM agr_define WHERE parent_agr = @role ORDER BY agr_name INTO TABLE @result.
  ENDMETHOD.

  METHOD zif_accx_role_repo~count_holders.
    SELECT COUNT( DISTINCT agr_users~uname )
      FROM agr_users INNER JOIN usr02 ON usr02~bname = agr_users~uname
      WHERE agr_users~agr_name  = @role
        AND usr02~class         = @user_group
        AND agr_users~from_dat <= @sy-datum
        AND agr_users~to_dat   >= @sy-datum
        AND agr_users~uname    <> @exclude_user
      INTO @result.
  ENDMETHOD.

  METHOD zif_accx_role_repo~count_group_members.
    SELECT COUNT(*) FROM usr02
      WHERE class = @user_group AND bname <> @exclude_user
      INTO @result.
  ENDMETHOD.

  METHOD zif_accx_role_repo~count_assigned_users.
    DATA role_range TYPE RANGE OF agr_name.

    IF roles IS INITIAL.
      RETURN.
    ENDIF.
    role_range = VALUE #( FOR r IN roles ( sign = 'I' option = 'EQ' low = r ) ).
    " AGR_USERS also holds the single roles of an assigned composite role
    SELECT agr_name AS role, COUNT( DISTINCT uname ) AS users FROM agr_users
      WHERE agr_name IN @role_range
        AND from_dat <= @sy-datum
        AND to_dat   >= @sy-datum
      GROUP BY agr_name
      INTO CORRESPONDING FIELDS OF TABLE @result.
  ENDMETHOD.

  METHOD value_matches.
    result = zcl_accx_auth_value=>covers( value = value low = low high = high ).
  ENDMETHOD.

ENDCLASS.
