"! <p class="shorttext synchronized">Access Explorer: prompt base class</p>
"! Checks the declared arguments (required, single line, at most 100
"! characters) and hands the cleaned values to compose, which returns the
"! instruction text. Subclasses only declare the descriptor and the text; the
"! text is fixed in the class and the argument values are the only variable part.
CLASS zcl_accx_prompt_base DEFINITION PUBLIC ABSTRACT CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_prompt ABSTRACT METHODS get_descriptor.

    CONSTANTS co_max_arg_length TYPE i VALUE 100.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_value,
             name  TYPE string,
             value TYPE string,
           END OF ty_value,
           ty_values TYPE HASHED TABLE OF ty_value WITH UNIQUE KEY name.

    "! The instruction text for the checked argument values
    METHODS compose ABSTRACT
      IMPORTING !values       TYPE ty_values
      RETURNING VALUE(result) TYPE string.

    "! Value of an argument, empty if it was not given
    METHODS value_of
      IMPORTING !values       TYPE ty_values
                !name         TYPE string
      RETURNING VALUE(result) TYPE string.

    "! Joins the lines with line feeds
    METHODS join
      IMPORTING !lines        TYPE string_table
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_prompt_base IMPLEMENTATION.

  METHOD zif_accx_prompt~render.
    DATA values TYPE ty_values.

    DATA(descriptor) = zif_accx_prompt~get_descriptor( ).
    LOOP AT descriptor-arguments INTO DATA(argument).
      DATA(value) = condense( args->get_string( argument-name ) ).
      IF value IS INITIAL.
        IF argument-required = abap_true.
          result = VALUE #( status  = zif_accx_types=>co_status-invalid
                            message = |Argument '{ argument-name }' is required.| ).
          RETURN.
        ENDIF.
        CONTINUE.
      ENDIF.
      IF strlen( value ) > co_max_arg_length OR contains( val = value pcre = `\p{Cc}` ).
        result = VALUE #( status  = zif_accx_types=>co_status-invalid
                          message = |Argument '{ argument-name }' must be one line of at most | &&
                                    |{ co_max_arg_length } characters.| ).
        RETURN.
      ENDIF.
      INSERT VALUE #( name = argument-name value = value ) INTO TABLE values.
    ENDLOOP.

    result = VALUE #( status      = zif_accx_types=>co_status-ok
                      description = descriptor-description
                      messages    = VALUE #( ( role = zif_accx_prompt=>co_role-user text = compose( values ) ) ) ).
  ENDMETHOD.

  METHOD value_of.
    READ TABLE values INTO DATA(entry) WITH TABLE KEY name = name.
    IF sy-subrc = 0.
      result = entry-value.
    ENDIF.
  ENDMETHOD.

  METHOD join.
    result = concat_lines_of( table = lines sep = |\n| ).
  ENDMETHOD.

ENDCLASS.

