"! <p class="shorttext synchronized">Access Explorer: tool base class</p>
"! Optional base for tools: generic summary rendering and descriptor/paging helpers.
CLASS zcl_accx_tool_base DEFINITION PUBLIC ABSTRACT CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_tool ABSTRACT METHODS get_descriptor execute.

  PROTECTED SECTION.
    "! Build a parameter definition
    METHODS param
      IMPORTING !name         TYPE string
                !kind         TYPE string DEFAULT zif_accx_types=>co_kind-string
                !description  TYPE string
                !required     TYPE abap_bool DEFAULT abap_false
                !enum         TYPE string_table OPTIONAL
                !default      TYPE string OPTIONAL
                !minimum      TYPE i DEFAULT 0
                !maximum      TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_param.

    "! Standard max_rows parameter (uniform across all tools)
    METHODS max_rows_param
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_param.

    "! Cut a standard-table payload to max_rows; sets truncated and total_count
    METHODS apply_row_limit
      IMPORTING !max_rows TYPE i
      CHANGING  !result   TYPE zif_accx_types=>ty_result.

ENDCLASS.

CLASS zcl_accx_tool_base IMPLEMENTATION.

  METHOD zif_accx_tool~render_summary.
    IF result-summary IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(title) = zif_accx_tool~get_descriptor( )-title.
    result-summary = |{ title }: { result-status }, { result-total_count } { COND #( WHEN result-total_count = 1 THEN `entry` ELSE `entries` ) }.|.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary } Result truncated - refine the selection or raise max_rows.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary } { result-hidden_by_authorization } entries hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

  METHOD param.
    result = VALUE #( name        = name
                      kind        = kind
                      description = description
                      required    = required
                      enum        = enum
                      default     = default
                      minimum     = minimum
                      maximum     = maximum ).
  ENDMETHOD.

  METHOD max_rows_param.
    result = param( name        = zif_accx_types=>co_param-max_rows
                    kind        = zif_accx_types=>co_kind-integer
                    description = `Maximum number of rows to return (1-500, default 50).`
                    minimum     = 1
                    maximum     = 500 ).
  ENDMETHOD.

  METHOD apply_row_limit.
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    IF result-data IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA(descr) = cl_abap_typedescr=>describe_by_data_ref( result-data ).
    IF descr->kind <> cl_abap_typedescr=>kind_table.
      RETURN.
    ENDIF.
    IF CAST cl_abap_tabledescr( descr )->table_kind <> cl_abap_tabledescr=>tablekind_std.
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <table>.
    IF result-total_count < lines( <table> ).
      result-total_count = lines( <table> ).
    ENDIF.
    IF max_rows > 0 AND lines( <table> ) > max_rows.
      DELETE <table> FROM max_rows + 1.
      result-truncated = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
