"! <p class="shorttext synchronized">Access Explorer: check simulation (FOR USER)</p>
"! Uses AUTHORITY-CHECK ... FOR USER (validated in the spike against
"! SUSR_USER_AUTH_FOR_OBJ_GET: 120/120 consistent). Sources: TSTC, TSTCA, TOBJ.
CLASS zcl_accx_auth_evaluator DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator.

    CONSTANTS co_max_fields TYPE i VALUE 10.

  PROTECTED SECTION.
    METHODS outcome_text
      IMPORTING !return_code  TYPE i
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_auth_evaluator IMPLEMENTATION.

  METHOD zif_accx_auth_evaluator~transaction_exists.
    SELECT SINGLE @abap_true FROM tstc WHERE tcode = @tcode INTO @result.
  ENDMETHOD.

  METHOD zif_accx_auth_evaluator~object_exists.
    SELECT SINGLE @abap_true FROM tobj WHERE objct = @object INTO @result.
  ENDMETHOD.

  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    APPEND VALUE #( object = 'S_TCODE'
                    fields = VALUE #( ( field = 'TCD' value = tcode ) )
                    reason = `Transaction start (S_TCODE)` ) TO result.

    SELECT objct, field, value FROM tstca
      WHERE tcode = @tcode
      ORDER BY objct, field
      INTO TABLE @DATA(extra).
    LOOP AT extra INTO DATA(row) GROUP BY row-objct INTO DATA(object_group).
      DATA(check) = VALUE zif_accx_auth_evaluator=>ty_check(
                      object = object_group
                      reason = `Transaction check object (SE93)` ).
      LOOP AT GROUP object_group INTO DATA(member).
        " fields without a maintained value are not checked at transaction start
        IF member-value IS NOT INITIAL.
          APPEND VALUE #( field = member-field value = member-value ) TO check-fields.
        ENDIF.
      ENDLOOP.
      APPEND check TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_auth_evaluator~simulate.
    DATA id1  TYPE xufield.
    DATA id2  TYPE xufield.
    DATA id3  TYPE xufield.
    DATA id4  TYPE xufield.
    DATA id5  TYPE xufield.
    DATA id6  TYPE xufield.
    DATA id7  TYPE xufield.
    DATA id8  TYPE xufield.
    DATA id9  TYPE xufield.
    DATA id10 TYPE xufield.
    DATA v1   TYPE c LENGTH 40.
    DATA v2   TYPE c LENGTH 40.
    DATA v3   TYPE c LENGTH 40.
    DATA v4   TYPE c LENGTH 40.
    DATA v5   TYPE c LENGTH 40.
    DATA v6   TYPE c LENGTH 40.
    DATA v7   TYPE c LENGTH 40.
    DATA v8   TYPE c LENGTH 40.
    DATA v9   TYPE c LENGTH 40.
    DATA v10  TYPE c LENGTH 40.
    DATA conditions TYPE string_table.

    LOOP AT check-fields INTO DATA(field_value) TO co_max_fields.
      CASE sy-tabix.
        WHEN 1.  id1  = field_value-field. v1  = field_value-value.
        WHEN 2.  id2  = field_value-field. v2  = field_value-value.
        WHEN 3.  id3  = field_value-field. v3  = field_value-value.
        WHEN 4.  id4  = field_value-field. v4  = field_value-value.
        WHEN 5.  id5  = field_value-field. v5  = field_value-value.
        WHEN 6.  id6  = field_value-field. v6  = field_value-value.
        WHEN 7.  id7  = field_value-field. v7  = field_value-value.
        WHEN 8.  id8  = field_value-field. v8  = field_value-value.
        WHEN 9.  id9  = field_value-field. v9  = field_value-value.
        WHEN 10. id10 = field_value-field. v10 = field_value-value.
      ENDCASE.
      APPEND |{ field_value-field }={ field_value-value }| TO conditions.
    ENDLOOP.

    DATA(object) = check-object.
    AUTHORITY-CHECK OBJECT object FOR USER user
      ID id1 FIELD v1 ID id2 FIELD v2 ID id3 FIELD v3 ID id4 FIELD v4 ID id5 FIELD v5
      ID id6 FIELD v6 ID id7 FIELD v7 ID id8 FIELD v8 ID id9 FIELD v9 ID id10 FIELD v10.
    DATA(return_code) = sy-subrc.

    result = VALUE #( object      = check-object
                      condition   = COND #( WHEN conditions IS INITIAL THEN `any value`
                                            ELSE concat_lines_of( table = conditions sep = `, ` ) )
                      reason      = check-reason
                      granted     = xsdbool( return_code = 0 )
                      return_code = return_code
                      outcome     = outcome_text( return_code )
                      fields      = check-fields ).
  ENDMETHOD.

  METHOD outcome_text.
    result = SWITCH #( return_code
                       WHEN 0   THEN `granted`
                       WHEN 4   THEN `missing: user has the object, but not these values`
                       WHEN 12  THEN `missing: user has no authorization for this object`
                       WHEN 24  THEN `check definition error: field names do not match the object`
                       WHEN 40  THEN `user does not exist`
                       WHEN 100 THEN `user is locked`
                       ELSE |not granted (return code { return_code })| ).
  ENDMETHOD.

ENDCLASS.
