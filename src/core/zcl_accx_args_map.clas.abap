"! <p class="shorttext synchronized">Access Explorer: in-memory tool arguments</p>
"! Adapter-independent argument container for unit tests, the RFC facade
"! and internal tool-to-tool calls.
CLASS zcl_accx_args_map DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_args.

    "! Set a scalar argument (chainable)
    METHODS set
      IMPORTING !name         TYPE string
                !value        TYPE simple
      RETURNING VALUE(result) TYPE REF TO zcl_accx_args_map.

    "! Set a list argument (chainable)
    METHODS set_list
      IMPORTING !name         TYPE string
                !values       TYPE string_table
      RETURNING VALUE(result) TYPE REF TO zcl_accx_args_map.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_entry,
             name   TYPE string,
             values TYPE string_table,
           END OF ty_entry.

    DATA entries TYPE HASHED TABLE OF ty_entry WITH UNIQUE KEY name.

ENDCLASS.

CLASS zcl_accx_args_map IMPLEMENTATION.

  METHOD set.
    DELETE TABLE entries WITH TABLE KEY name = name.
    INSERT VALUE #( name = name values = VALUE #( ( |{ value }| ) ) ) INTO TABLE entries.
    result = me.
  ENDMETHOD.

  METHOD set_list.
    DELETE TABLE entries WITH TABLE KEY name = name.
    INSERT VALUE #( name = name values = values ) INTO TABLE entries.
    result = me.
  ENDMETHOD.

  METHOD zif_accx_args~has.
    result = xsdbool( line_exists( entries[ name = name ] ) ).
  ENDMETHOD.

  METHOD zif_accx_args~get_string.
    READ TABLE entries ASSIGNING FIELD-SYMBOL(<entry>) WITH TABLE KEY name = name.
    IF sy-subrc = 0 AND <entry>-values IS NOT INITIAL.
      result = <entry>-values[ 1 ].
    ELSE.
      result = default.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_args~get_integer.
    IF zif_accx_args~has( name ) = abap_false.
      result = default.
      RETURN.
    ENDIF.
    TRY.
        result = CONV i( zif_accx_args~get_string( name ) ).
      CATCH cx_sy_conversion_error.
        result = default.
    ENDTRY.
  ENDMETHOD.

  METHOD zif_accx_args~get_boolean.
    IF zif_accx_args~has( name ) = abap_false.
      result = default.
      RETURN.
    ENDIF.
    DATA(value) = to_lower( condense( zif_accx_args~get_string( name ) ) ).
    result = xsdbool( value = `x` OR value = `true` OR value = `1` OR value = `yes` ).
  ENDMETHOD.

  METHOD zif_accx_args~get_strings.
    READ TABLE entries ASSIGNING FIELD-SYMBOL(<entry>) WITH TABLE KEY name = name.
    IF sy-subrc = 0.
      result = <entry>-values.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_args~get_names.
    result = VALUE #( FOR entry IN entries ( entry-name ) ).
  ENDMETHOD.

ENDCLASS.
