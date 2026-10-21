"! <p class="shorttext synchronized">Access Explorer: differences between roles</p>
"! Compares authorization values and name lists (menus, catalogs, single roles) of two roles.
"! Values are compared per object and field, independent of the authorization they belong to.
CLASS zcl_accx_role_diff DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES ty_set TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    TYPES: BEGIN OF ty_diff,
             only_a TYPE string_table,
             only_b TYPE string_table,
             "! entries in both
             common TYPE i,
           END OF ty_diff.

    "! Values as OBJECT FIELD=LOW, OBJECT FIELD=LOW-HIGH or OBJECT FIELD=(open), without the skipped fields
    CLASS-METHODS value_set
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
                !skip_fields  TYPE string_table OPTIONAL
      RETURNING VALUE(result) TYPE ty_set.

    CLASS-METHODS diff
      IMPORTING !a            TYPE ty_set
                !b            TYPE ty_set
      RETURNING VALUE(result) TYPE ty_diff.

    CLASS-METHODS diff_lists
      IMPORTING !a            TYPE string_table
                !b            TYPE string_table
      RETURNING VALUE(result) TYPE ty_diff.

    "! Objects of the values (first word of each entry)
    CLASS-METHODS objects_of
      IMPORTING !entries      TYPE string_table
      RETURNING VALUE(result) TYPE ty_set.

ENDCLASS.

CLASS zcl_accx_role_diff IMPLEMENTATION.

  METHOD value_set.
    LOOP AT values INTO DATA(value).
      IF line_exists( skip_fields[ table_line = CONV string( value-field ) ] ).
        CONTINUE.
      ENDIF.
      INSERT |{ value-object } { value-field }=| &&
             |{ COND #( WHEN value-low IS INITIAL AND value-high IS INITIAL THEN `(open)`
                        WHEN value-high IS INITIAL THEN condense( value-low )
                        ELSE |{ condense( value-low ) }-{ condense( value-high ) }| ) }| INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD diff.
    LOOP AT a INTO DATA(entry).
      IF line_exists( b[ table_line = entry ] ).
        result-common += 1.
      ELSE.
        APPEND entry TO result-only_a.
      ENDIF.
    ENDLOOP.
    LOOP AT b INTO entry.
      IF NOT line_exists( a[ table_line = entry ] ).
        APPEND entry TO result-only_b.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD diff_lists.
    DATA set_a TYPE ty_set.
    DATA set_b TYPE ty_set.
    LOOP AT a INTO DATA(entry).
      INSERT entry INTO TABLE set_a.
    ENDLOOP.
    LOOP AT b INTO entry.
      INSERT entry INTO TABLE set_b.
    ENDLOOP.
    result = diff( a = set_a b = set_b ).
  ENDMETHOD.

  METHOD objects_of.
    LOOP AT entries INTO DATA(entry).
      INSERT segment( val = entry index = 1 sep = ` ` ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

