"! <p class="shorttext synchronized">Access Explorer: critical authorizations from SUIM</p>
"! Rules: USCRAUTHID (id, color), USCRAUTH (values), USCRAUIDT (texts). All
"! maintained ids count, independent of SUIM variants. Semantics as in
"! RSUSR008_009_NEW: all groups (CR_AUTH) of an id must be met; within a group
"! objects and values are combined with the group's search type (AND/OR);
"! the fields of one object must be met by the same authorization.
"! Combinations: USRCOMB (id, color), USCRCOMID (components), USRCOMBT (texts).
CLASS zcl_accx_critical_rules DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_critical_rules.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_rule,
             id    TYPE auth_id,
             color TYPE auth_color,
             text  TYPE string,
           END OF ty_rule,
           ty_rules TYPE SORTED TABLE OF ty_rule WITH UNIQUE KEY id.

    TYPES: BEGIN OF ty_rule_value,
             id         TYPE auth_id,
             group      TYPE cr_auth,
             object     TYPE xuobject,
             field      TYPE xufield,
             low        TYPE xuval,
             high       TYPE xuval,
             searchtype TYPE xandor,
           END OF ty_rule_value,
           ty_rule_values TYPE STANDARD TABLE OF ty_rule_value WITH EMPTY KEY.

    TYPES: BEGIN OF ty_combination,
             id         TYPE comb_id,
             rule       TYPE auth_id,
             searchtype TYPE xandor,
           END OF ty_combination,
           ty_combinations TYPE SORTED TABLE OF ty_combination WITH UNIQUE KEY id rule.

    DATA rules             TYPE ty_rules.
    DATA rule_values       TYPE ty_rule_values.
    DATA combinations      TYPE ty_combinations.
    "! combination headers: id, color and text (id in field id)
    DATA combination_rules TYPE ty_rules.
    DATA loaded            TYPE abap_bool.

    "! Read the rule definitions (once per instance)
    METHODS load_rules.

    METHODS level
      IMPORTING !color        TYPE auth_color
      RETURNING VALUE(result) TYPE string.

    METHODS group_met
      IMPORTING !group_values TYPE ty_rule_values
                !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS object_met
      IMPORTING !object       TYPE xuobject
                !criteria     TYPE ty_rule_values
                !or_search    TYPE abap_bool
                !values       TYPE zif_accx_critical_rules=>ty_auth_values
      RETURNING VALUE(result) TYPE abap_bool.

    "! Is a critical value (low/high of a rule) granted by an authorization value?
    METHODS value_granted
      IMPORTING !criterion    TYPE ty_rule_value
                !value        TYPE zif_accx_critical_rules=>ty_auth_value
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_critical_rules IMPLEMENTATION.

  METHOD load_rules.
    IF loaded = abap_true.
      RETURN.
    ENDIF.
    loaded = abap_true.

    SELECT auth_id AS id, auth_color AS color FROM uscrauthid
      INTO CORRESPONDING FIELDS OF TABLE @rules.
    SELECT auth_id, text, langu FROM uscrauidt
      WHERE langu = @sy-langu OR langu = 'E'
      INTO TABLE @DATA(texts).
    SORT texts BY auth_id langu.
    LOOP AT rules ASSIGNING FIELD-SYMBOL(<rule>).
      READ TABLE texts INTO DATA(text) WITH KEY auth_id = <rule>-id langu = sy-langu BINARY SEARCH.
      IF sy-subrc <> 0.
        READ TABLE texts INTO text WITH KEY auth_id = <rule>-id langu = 'E' BINARY SEARCH.
      ENDIF.
      <rule>-text = condense( COND #( WHEN sy-subrc = 0 THEN text-text ELSE <rule>-id ) ).
    ENDLOOP.

    SELECT auth_id AS id, cr_auth AS group, objct AS object, field, low, high, searchtype FROM uscrauth
      INTO CORRESPONDING FIELDS OF TABLE @rule_values.
    SORT rule_values BY id group object field low.

    SELECT comb_id AS id, auth_id AS rule, searchtype FROM uscrcomid
      INTO CORRESPONDING FIELDS OF TABLE @combinations.
    SELECT comb_id AS id, comb_col AS color FROM usrcomb
      INTO CORRESPONDING FIELDS OF TABLE @combination_rules.
    SELECT comb_id, ctext, langu FROM usrcombt
      WHERE langu = @sy-langu OR langu = 'E'
      INTO TABLE @DATA(comb_texts).
    SORT comb_texts BY comb_id langu.
    LOOP AT combination_rules ASSIGNING FIELD-SYMBOL(<combination>).
      READ TABLE comb_texts INTO DATA(comb_text) WITH KEY comb_id = <combination>-id langu = sy-langu BINARY SEARCH.
      IF sy-subrc <> 0.
        READ TABLE comb_texts INTO comb_text WITH KEY comb_id = <combination>-id langu = 'E' BINARY SEARCH.
      ENDIF.
      <combination>-text = condense( COND #( WHEN sy-subrc = 0 THEN comb_text-ctext ELSE <combination>-id ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD level.
    result = SWITCH #( color
                       WHEN '6' THEN zif_accx_critical_rules=>co_level-high
                       WHEN '3' THEN zif_accx_critical_rules=>co_level-medium
                       ELSE zif_accx_critical_rules=>co_level-low ).
  ENDMETHOD.

  METHOD zif_accx_critical_rules~evaluate.
    load_rules( ).
    LOOP AT rules INTO DATA(rule).
      DATA(groups) = zif_accx_critical_rules~rule_groups( rule-id ).
      IF groups IS INITIAL
         OR lines( zif_accx_critical_rules~met_groups( rule = rule-id values = values ) ) < lines( groups ).
        CONTINUE.
      ENDIF.
      APPEND VALUE #( rule = rule-id text = rule-text level = level( rule-color ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~evaluate_combinations.
    load_rules( ).
    LOOP AT combination_rules INTO DATA(combination).
      IF NOT line_exists( combinations[ id = combination-id ] ).
        " combination without components
        CONTINUE.
      ENDIF.
      DATA(and_met) = abap_true.
      DATA(or_parts) = 0.
      DATA(or_met) = abap_false.
      LOOP AT combinations INTO DATA(component) WHERE id = combination-id.
        DATA(held) = xsdbool( line_exists( hits[ rule = component-rule ] ) ).
        IF component-searchtype = 'OR'.
          or_parts += 1.
          IF held = abap_true.
            or_met = abap_true.
          ENDIF.
        ELSEIF held = abap_false.
          and_met = abap_false.
        ENDIF.
      ENDLOOP.
      IF and_met = abap_true AND ( or_parts = 0 OR or_met = abap_true ).
        APPEND VALUE #( rule = combination-id text = combination-text level = level( combination-color ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~rule_groups.
    load_rules( ).
    LOOP AT rule_values INTO DATA(rule_value) WHERE id = rule.
      IF NOT line_exists( result[ table_line = rule_value-group ] ).
        APPEND rule_value-group TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~met_groups.
    load_rules( ).
    LOOP AT zif_accx_critical_rules~rule_groups( rule ) INTO DATA(group).
      IF group_met( group_values = VALUE #( FOR v IN rule_values WHERE ( id = rule AND group = group ) ( v ) )
                    values       = values ) = abap_true.
        APPEND group TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~rule_objects.
    load_rules( ).
    LOOP AT rule_values INTO DATA(rule_value).
      IF NOT line_exists( result[ table_line = rule_value-object ] ).
        APPEND CONV string( rule_value-object ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~combination_rules.
    load_rules( ).
    LOOP AT combinations INTO DATA(combination_rule) WHERE id = combination.
      APPEND combination_rule-rule TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD group_met.
    DATA objects TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.

    IF group_values IS INITIAL.
      RETURN.
    ENDIF.
    DATA(or_search) = xsdbool( group_values[ 1 ]-searchtype = 'OR' ).
    LOOP AT group_values INTO DATA(group_value).
      INSERT group_value-object INTO TABLE objects.
    ENDLOOP.
    result = xsdbool( or_search = abap_false ).
    LOOP AT objects INTO DATA(object).
      DATA(met) = object_met( object    = object
                              criteria  = VALUE #( FOR c IN group_values WHERE ( object = object ) ( c ) )
                              or_search = or_search
                              values    = values ).
      IF or_search = abap_true AND met = abap_true.
        result = abap_true.
        RETURN.
      ELSEIF or_search = abap_false AND met = abap_false.
        result = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_critical_rules~evaluate_role.
    DATA objects TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.
    DATA values  TYPE zif_accx_critical_rules=>ty_auth_values.

    load_rules( ).
    LOOP AT rule_values INTO DATA(rule_value).
      INSERT rule_value-object INTO TABLE objects.
    ENDLOOP.
    IF objects IS INITIAL.
      RETURN.
    ENDIF.
    SELECT object, auth, field, low, high FROM agr_1251
      FOR ALL ENTRIES IN @objects
      WHERE agr_name = @role
        AND object   = @objects-table_line
        AND deleted  = @space
      INTO CORRESPONDING FIELDS OF TABLE @values.
    result = zif_accx_critical_rules~evaluate( values ).
  ENDMETHOD.

  METHOD object_met.
    DATA auths  TYPE SORTED TABLE OF xuauth WITH UNIQUE KEY table_line.
    DATA fields TYPE SORTED TABLE OF xufield WITH UNIQUE KEY table_line.

    LOOP AT values INTO DATA(candidate) WHERE object = object.
      INSERT candidate-auth INTO TABLE auths.
    ENDLOOP.
    LOOP AT criteria INTO DATA(criterion) WHERE field IS NOT INITIAL.
      INSERT criterion-field INTO TABLE fields.
    ENDLOOP.
    IF fields IS INITIAL.
      " object only: any authorization of the object is critical
      result = xsdbool( auths IS NOT INITIAL ).
      RETURN.
    ENDIF.

    " per authorization (as SUIM CHECK_VALUE): OR = any criterion granted, AND = every criterion granted
    LOOP AT auths INTO DATA(auth).
      DATA(auth_met) = xsdbool( or_search = abap_false ).
      LOOP AT criteria INTO criterion WHERE field IS NOT INITIAL.
        DATA(granted) = abap_false.
        LOOP AT values INTO DATA(value) WHERE object = object AND auth = auth AND field = criterion-field.
          IF value_granted( criterion = criterion value = value ) = abap_true.
            granted = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF or_search = abap_true AND granted = abap_true.
          auth_met = abap_true.
          EXIT.
        ELSEIF or_search = abap_false AND granted = abap_false.
          auth_met = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF auth_met = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD value_granted.
    IF value-low CP '$*'.
      " organizational level placeholder, not resolved
      RETURN.
    ENDIF.
    IF criterion-low = '#*' OR criterion-low = '#**'.
      " the full authorization * itself is critical
      result = xsdbool( value-low = '*' ).
    ELSEIF criterion-low IS INITIAL AND criterion-high IS INITIAL.
      " SUIM: blank criterion searches for an unmaintained field
      result = xsdbool( value-low IS INITIAL AND value-high IS INITIAL ).
    ELSEIF criterion-high IS NOT INITIAL.
      result = xsdbool( zcl_accx_auth_value=>covers( value = criterion-low  low = value-low high = value-high ) = abap_true
                    AND zcl_accx_auth_value=>covers( value = criterion-high low = value-low high = value-high ) = abap_true ).
    ELSEIF criterion-low CA '*'.
      result = xsdbool( value-low = '*' OR value-low CP criterion-low OR value-low = criterion-low ).
    ELSE.
      result = zcl_accx_auth_value=>covers( value = criterion-low low = value-low high = value-high ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
