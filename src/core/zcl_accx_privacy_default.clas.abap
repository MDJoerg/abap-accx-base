"! <p class="shorttext synchronized">Access Explorer: privacy modes PSEUDONYMIZE and MINIMIZE</p>
"! Walks the result data by RTTI and replaces personal fields: user ids by stable
"! pseudonyms, person names and contact data by nothing, and (MINIMIZE only) last
"! logon times by their month. A field is personal if its data element (rule kind D)
"! or its component name (rule kind C, either NAME or PARENT-NAME) has a rule; the
"! defaults can be extended or switched off in table ZACCX_PII. User ids found this
"! way are also replaced in all other text of the result (strings, warnings, next
"! steps, summary). Inbound, pseudonyms in tool arguments become user ids again.
"! Redefine the TRANSFORM_* methods to change what a category turns into.
CLASS zcl_accx_privacy_default DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_privacy.

    CONSTANTS: BEGIN OF co_category,
                 user_id   TYPE string VALUE `USER_ID`,
                 "! comma or semicolon separated user ids
                 user_list TYPE string VALUE `USER_LIST`,
                 name      TYPE string VALUE `NAME`,
                 contact   TYPE string VALUE `CONTACT`,
                 timestamp TYPE string VALUE `TIMESTAMP`,
               END OF co_category.

    CONSTANTS co_data_element TYPE c LENGTH 1 VALUE 'D'.
    CONSTANTS co_component    TYPE c LENGTH 1 VALUE 'C'.

    "! Marks a name that was removed from texts
    CONSTANTS co_removed TYPE string VALUE `[removed]`.

    TYPES: BEGIN OF ty_rule,
             kind     TYPE c LENGTH 1,
             name     TYPE string,
             category TYPE string,
           END OF ty_rule,
           ty_rules TYPE HASHED TABLE OF ty_rule WITH UNIQUE KEY kind name.

    "! @parameter mode | PSEUDONYMIZE or MINIMIZE
    "! @parameter pseudonyms | Pseudonym source; default ZCL_ACCX_PSEUDONYMS
    METHODS constructor
      IMPORTING !mode       TYPE string
                !pseudonyms TYPE REF TO zif_accx_pseudonyms OPTIONAL.
    METHODS classify
      IMPORTING !descr        TYPE REF TO cl_abap_elemdescr
                !names        TYPE string_table
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
    METHODS transform_user_id
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_accx_error.

    "! Person name; empty = removed
    METHODS transform_name
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

    "! Contact data; empty = removed
    METHODS transform_contact
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

    "! Point in time (ISO text or YYYYMMDD); only used by mode MINIMIZE. Returns YYYY-MM or empty.
    METHODS transform_timestamp
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_replacement,
             clear TYPE string,
             text  TYPE string,
           END OF ty_replacement,
           ty_replacements TYPE STANDARD TABLE OF ty_replacement WITH KEY clear.

    DATA mode         TYPE string.
    DATA pseudonyms   TYPE REF TO zif_accx_pseudonyms.
    DATA rules        TYPE ty_rules.
    DATA replacements TYPE ty_replacements.
    DATA scrubbing    TYPE abap_bool.

    METHODS load_rules.

    METHODS add_rule
      IMPORTING !kind     TYPE c
                !name     TYPE string
                !category TYPE string.

    METHODS rule_of
      IMPORTING !kind         TYPE c
                !name         TYPE string
      RETURNING VALUE(result) TYPE string.


    METHODS walk
      IMPORTING !ref   TYPE REF TO data
                !names TYPE string_table
      RAISING   zcx_accx_error.

    METHODS leaf
      IMPORTING !ref   TYPE REF TO data
                !descr TYPE REF TO cl_abap_elemdescr
                !names TYPE string_table
      RAISING   zcx_accx_error.

    METHODS remember
      IMPORTING !clear TYPE string
                !text  TYPE string.

    "! Texts that repeat a rounded point in time (date or date and time) show the rounded value
    METHODS remember_time
      IMPORTING !original TYPE string
                !rounded  TYPE string.

    METHODS scrub
      CHANGING !text TYPE string.

    METHODS check_fits
      IMPORTING !descr TYPE REF TO cl_abap_elemdescr
                !text  TYPE string
      RAISING   zcx_accx_error.

    METHODS pseudonymize_list
      IMPORTING !list         TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_accx_error.

ENDCLASS.

CLASS zcl_accx_privacy_default IMPLEMENTATION.

  METHOD constructor.
    me->mode       = to_upper( condense( mode ) ).
    me->pseudonyms = COND #( WHEN pseudonyms IS BOUND THEN pseudonyms ELSE NEW zcl_accx_pseudonyms( ) ).
    load_rules( ).
  ENDMETHOD.

  METHOD load_rules.
    " data elements
    LOOP AT VALUE string_table( ( `SYUNAME` ) ( `XUBNAME` ) ( `UNAME` ) ( `BNAME` ) ( `USNAM` ) ) INTO DATA(element).
      add_rule( kind = co_data_element name = element category = co_category-user_id ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `AD_NAMTEXT` ) ( `AD_NAMELAST` ) ( `AD_NAMEFIR` ) ( `AD_NAMEMID` ) ) INTO element.
      add_rule( kind = co_data_element name = element category = co_category-name ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `AD_SMTPADR` ) ( `AD_TLNMBR` ) ( `AD_TLNMBR1` ) ( `AD_FXNMBR1` ) ) INTO element.
      add_rule( kind = co_data_element name = element category = co_category-contact ).
    ENDLOOP.
    " component names (also PARENT-NAME) of fields typed as plain strings
    LOOP AT VALUE string_table( ( `USER` ) ( `CHANGED_BY` ) ( `CREATED_BY` ) ( `MODIFIED_BY` ) ( `FOR_USER` )
                                ( `REFERENCE_USER` ) ( `BY_CHANGER-NAME` ) ) INTO DATA(component).
      add_rule( kind = co_component name = component category = co_category-user_id ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `USERS` ) ( `HOLDERS` ) ) INTO component.
      add_rule( kind = co_component name = component category = co_category-user_list ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `FULL_NAME` ) ( `PERSON_NAME` ) ( `USERS-NAME` ) ) INTO component.
      add_rule( kind = co_component name = component category = co_category-name ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `EMAIL` ) ( `E_MAIL` ) ( `PHONE_NUMBER` ) ) INTO component.
      add_rule( kind = co_component name = component category = co_category-contact ).
    ENDLOOP.
    add_rule( kind = co_component name = `LAST_LOGON` category = co_category-timestamp ).

    " customer additions and overrides (an empty category switches a rule off)
    SELECT kind, name, category FROM zaccx_pii INTO TABLE @DATA(customer).
    LOOP AT customer INTO DATA(row).
      add_rule( kind = row-kind name = to_upper( condense( row-name ) ) category = to_upper( condense( row-category ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_rule.
    DELETE TABLE rules WITH TABLE KEY kind = kind name = name.
    IF category IS NOT INITIAL.
      INSERT VALUE #( kind = kind name = name category = category ) INTO TABLE rules.
    ENDIF.
  ENDMETHOD.

  METHOD rule_of.
    READ TABLE rules ASSIGNING FIELD-SYMBOL(<rule>) WITH TABLE KEY kind = kind name = name.
    IF sy-subrc = 0.
      result = <rule>-category.
    ENDIF.
  ENDMETHOD.

  METHOD classify.
    DATA(absolute) = descr->absolute_name.
    IF matches( val = absolute pcre = '^\\TYPE=\w+$' ).
      result = rule_of( kind = co_data_element name = substring_after( val = absolute sub = '\TYPE=' ) ).
      IF result IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.
    DATA(depth) = lines( names ).
    IF depth = 0.
      RETURN.
    ENDIF.
    DATA(own) = names[ depth ].
    IF depth >= 2.
      DATA(parent) = names[ depth - 1 ].
      result = rule_of( kind = co_component name = |{ parent }-{ own }| ).
      IF result IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.
    result = rule_of( kind = co_component name = own ).
  ENDMETHOD.

  METHOD walk.
    FIELD-SYMBOLS <struct>    TYPE any.
    FIELD-SYMBOLS <table>     TYPE ANY TABLE.
    FIELD-SYMBOLS <reference> TYPE REF TO data.
    DATA child   TYPE REF TO data.
    DATA row_ref TYPE REF TO data.

    DATA(descr) = cl_abap_typedescr=>describe_by_data_ref( ref ).
    CASE descr->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        DATA(struct) = CAST cl_abap_structdescr( descr ).
        ASSIGN ref->* TO <struct>.
        LOOP AT struct->components INTO DATA(component).
          ASSIGN COMPONENT component-name OF STRUCTURE <struct> TO FIELD-SYMBOL(<field>).
          IF sy-subrc = 0.
            GET REFERENCE OF <field> INTO child.
            walk( ref = child names = VALUE #( BASE names ( to_upper( component-name ) ) ) ).
          ENDIF.
        ENDLOOP.

      WHEN cl_abap_typedescr=>kind_table.
        ASSIGN ref->* TO <table>.
        IF <table> IS INITIAL.
          RETURN.
        ENDIF.
        DATA(table_descr) = CAST cl_abap_tabledescr( descr ).
        IF table_descr->table_kind <> cl_abap_tabledescr=>tablekind_std.
          RAISE EXCEPTION NEW zcx_accx_error( message = `Result data contains a sorted or hashed table; privacy processing is not possible.` ).
        ENDIF.
        LOOP AT <table> ASSIGNING FIELD-SYMBOL(<row>).
          GET REFERENCE OF <row> INTO row_ref.
          walk( ref = row_ref names = names ).
        ENDLOOP.

      WHEN cl_abap_typedescr=>kind_ref.
        IF descr->type_kind = cl_abap_typedescr=>typekind_dref.
          ASSIGN ref->* TO <reference>.
          IF <reference> IS BOUND.
            walk( ref = <reference> names = names ).
          ENDIF.
        ENDIF.

      WHEN cl_abap_typedescr=>kind_elem.
        leaf( ref = ref descr = CAST cl_abap_elemdescr( descr ) names = names ).
    ENDCASE.
  ENDMETHOD.

  METHOD leaf.
    FIELD-SYMBOLS <value> TYPE any.

    CASE descr->type_kind.
      WHEN cl_abap_typedescr=>typekind_char OR cl_abap_typedescr=>typekind_string OR cl_abap_typedescr=>typekind_date.
        ASSIGN ref->* TO <value>.
      WHEN OTHERS.
        RETURN.
    ENDCASE.
    IF <value> IS INITIAL.
      RETURN.
    ENDIF.

    DATA(category) = classify( descr = descr names = names ).

    " second pass: other texts of the result may mention users or names found in the first
    IF scrubbing = abap_true.
      IF category IS INITIAL AND descr->type_kind = cl_abap_typedescr=>typekind_string.
        DATA(text) = CONV string( <value> ).
        scrub( CHANGING text = text ).
        <value> = text.
      ENDIF.
      RETURN.
    ENDIF.

    CASE category.
      WHEN co_category-user_id.
        DATA(user) = condense( CONV string( <value> ) ).
        DATA(pseudonym) = transform_user_id( user ).
        check_fits( descr = descr text = pseudonym ).
        remember( clear = user text = pseudonym ).
        <value> = pseudonym.

      WHEN co_category-user_list.
        DATA(list) = CONV string( <value> ).
        DATA(protected_list) = pseudonymize_list( list ).
        check_fits( descr = descr text = protected_list ).
        <value> = protected_list.

      WHEN co_category-name.
        DATA(person) = condense( CONV string( <value> ) ).
        remember( clear = person text = co_removed ).
        <value> = transform_name( person ).

      WHEN co_category-contact.
        DATA(contact) = condense( CONV string( <value> ) ).
        remember( clear = contact text = co_removed ).
        <value> = transform_contact( contact ).

      WHEN co_category-timestamp.
        IF mode = zcl_accx_factory=>co_privacy_mode-minimize.
          DATA(original) = condense( CONV string( <value> ) ).
          DATA(rounded) = transform_timestamp( original ).
          remember_time( original = original rounded = rounded ).
          IF descr->type_kind = cl_abap_typedescr=>typekind_date.
            IF rounded IS INITIAL.
              CLEAR <value>.
            ELSE.
              <value> = |{ rounded(4) }{ rounded+5(2) }01|.
            ENDIF.
          ELSE.
            <value> = rounded.
          ENDIF.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD pseudonymize_list.
    DATA tokens TYPE string_table.
    FIND ALL OCCURRENCES OF PCRE '[^,;\s]+' IN list RESULTS DATA(hits).
    LOOP AT hits INTO DATA(hit).
      DATA(user) = substring( val = list off = hit-offset len = hit-length ).
      DATA(pseudonym) = transform_user_id( user ).
      remember( clear = user text = pseudonym ).
      APPEND pseudonym TO tokens.
    ENDLOOP.
    result = concat_lines_of( table = tokens sep = `, ` ).
  ENDMETHOD.

  METHOD remember.
    IF strlen( clear ) < 2 OR line_exists( replacements[ clear = clear ] ).
      RETURN.
    ENDIF.
    APPEND VALUE #( clear = clear text = text ) TO replacements.
  ENDMETHOD.

  METHOD remember_time.
    IF original IS INITIAL OR original = rounded OR rounded IS INITIAL.
      RETURN.
    ENDIF.
    remember( clear = original text = rounded ).
    IF find( val = original pcre = '^\d{4}-\d{2}-\d{2}.' ) = 0.
      remember( clear = substring( val = original len = 10 ) text = rounded ).
    ELSEIF find( val = original pcre = '^\d{8}$' ) = 0.
      remember( clear = |{ substring( val = original len = 4 ) }-{ substring( val = original off = 4 len = 2 ) }-{ substring( val = original off = 6 len = 2 ) }| text = rounded ).
    ENDIF.
  ENDMETHOD.

  METHOD scrub.
    IF text IS INITIAL OR replacements IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT replacements INTO DATA(replacement).
      IF text NS replacement-clear.
        CONTINUE.
      ENDIF.
      " every character is escaped, so ids like $ABC or A/B are literal
      DATA(pattern) = replace( val = replacement-clear pcre = '([^A-Za-z0-9])' with = '\\$1' occ = 0 ).
      REPLACE ALL OCCURRENCES OF PCRE |(?<![A-Za-z0-9_]){ pattern }(?![A-Za-z0-9_])| IN text WITH replacement-text.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_fits.
    IF descr->type_kind = cl_abap_typedescr=>typekind_char
       AND descr->length / cl_abap_char_utilities=>charsize < strlen( text ).
      RAISE EXCEPTION NEW zcx_accx_error( message = |A personal field is too short for its pseudonym; the result is withheld.| ).
    ENDIF.
  ENDMETHOD.

  METHOD transform_user_id.
    result = pseudonyms->pseudonym_for( value ).
  ENDMETHOD.

  METHOD transform_name ##NEEDED.
    CLEAR result.
  ENDMETHOD.

  METHOD transform_contact ##NEEDED.
    CLEAR result.
  ENDMETHOD.

  METHOD transform_timestamp.
    DATA(text) = condense( CONV string( value ) ).
    IF find( val = text pcre = '^\d{4}-\d{2}' ) = 0.
      result = text(7).
    ELSEIF find( val = text pcre = '^\d{8}' ) = 0.
      result = |{ text(4) }-{ text+4(2) }|.
    ELSEIF NOT contains( val = text pcre = '\d' ).
      " no point in time in it, e.g. "never": nothing to round
      result = text.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_privacy~protect_result.
    TRY.
        IF result-data_json IS NOT INITIAL AND result-data IS NOT BOUND.
          RAISE EXCEPTION NEW zcx_accx_error( message = `Serialized result data cannot be protected.` ).
        ENDIF.
        IF result-data IS BOUND.
          scrubbing = abap_false.
          walk( ref = result-data names = VALUE #( ) ).
          scrubbing = abap_true.
          walk( ref = result-data names = VALUE #( ) ).
          scrubbing = abap_false.
        ENDIF.
        scrub( CHANGING text = result-summary ).
        LOOP AT result-next_steps ASSIGNING FIELD-SYMBOL(<step>).
          scrub( CHANGING text = <step> ).
        ENDLOOP.
        LOOP AT result-warnings ASSIGNING FIELD-SYMBOL(<warning>).
          scrub( CHANGING text = <warning> ).
        ENDLOOP.
      CATCH zcx_accx_error INTO DATA(error).
        scrubbing = abap_false.
        CLEAR: result-data, result-data_json, result-summary, result-next_steps, result-sources.
        result-status = zif_accx_types=>co_status-error.
        result-warnings = VALUE #( ( |Result data withheld by privacy policy: { error->get_text( ) }| ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD zif_accx_privacy~resolve_args.
    result = args.
    DATA(map) = NEW zcl_accx_args_map( ).
    DATA(changed) = abap_false.
    LOOP AT args->get_names( ) INTO DATA(name).
      DATA(values) = args->get_strings( name ).
      IF values IS INITIAL AND args->has( name ) = abap_true.
        values = VALUE #( ( args->get_string( name ) ) ).
      ENDIF.
      LOOP AT values ASSIGNING FIELD-SYMBOL(<value>).
        IF pseudonyms->is_pseudonym( <value> ) = abap_true.
          DATA(user) = pseudonyms->user_for( <value> ).
          remember( clear = CONV string( user ) text = to_upper( condense( <value> ) ) ).
          <value> = user.
          changed = abap_true.
        ENDIF.
      ENDLOOP.
      map->set_list( name = name values = values ).
    ENDLOOP.
    IF changed = abap_true.
      result = map.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

