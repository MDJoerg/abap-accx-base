"! <p class="shorttext synchronized">Access Explorer: search criteria of find tools</p>
"! Shared by find_users and find_roles: patterns as range lines and
"! FIELD=VALUE pairs as SUIM value criteria (same field twice = OR).
CLASS zcl_accx_search_criteria DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    "! Single value or pattern (*) as range line
    CLASS-METHODS range_line
      IMPORTING !value  TYPE string
      EXPORTING !sign   TYPE c
                !option TYPE c
                !low    TYPE csequence.

    "! FIELD=VALUE pairs; a repeated field adds an alternative value (OR)
    CLASS-METHODS value_criteria
      IMPORTING !pairs        TYPE string_table
      RETURNING VALUE(result) TYPE zif_accx_suim_gateway=>ty_value_criteria
      RAISING   zcx_accx_error.

    "! e.g. S_DEVELOP with OBJTYPE=DEBUG, ACTVT=02 or 03
    CLASS-METHODS describe_values
      IMPORTING !object       TYPE csequence
                !criteria     TYPE zif_accx_suim_gateway=>ty_value_criteria
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_search_criteria IMPLEMENTATION.

  METHOD range_line.
    sign   = 'I'.
    option = COND #( WHEN value CA '*' THEN 'CP' ELSE 'EQ' ).
    low    = value.
  ENDMETHOD.

  METHOD value_criteria.
    LOOP AT pairs INTO DATA(pair).
      SPLIT pair AT '=' INTO DATA(field) DATA(value).
      field = to_upper( condense( field ) ).
      value = condense( value ).
      IF field IS INITIAL OR value IS INITIAL.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                            message = |Value "{ pair }" is not of the form FIELD=VALUE.| ).
      ENDIF.
      ASSIGN result[ field = field ] TO FIELD-SYMBOL(<criterion>).
      IF sy-subrc <> 0.
        APPEND VALUE #( field = field ) TO result ASSIGNING <criterion>.
      ENDIF.
      APPEND value TO <criterion>-values.
    ENDLOOP.
  ENDMETHOD.

  METHOD describe_values.
    result = object.
    LOOP AT criteria INTO DATA(criterion).
      result = |{ result }{ COND #( WHEN sy-tabix = 1 THEN ` with ` ELSE `, ` ) }{ criterion-field }=| &&
               |{ concat_lines_of( table = criterion-values sep = ` or ` ) }|.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
