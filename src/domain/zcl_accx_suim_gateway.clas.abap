"! <p class="shorttext synchronized">Access Explorer: SUIM report APIs via RFC NONE</p>
"! Every SUIM API runs with DESTINATION 'NONE': own session under the same
"! named user, protected against LEAVE PROGRAM, memory and SALV runtime state
"! of the reports. Variants: USRVAR/USRVARID (authorizations), USRVARCOM/
"! USRCRCOMB (combinations). Searches: RSUSR002 (users), RSUSR070 (roles).
CLASS zcl_accx_suim_gateway DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_suim_gateway.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_text,
             rule TYPE string,
             text TYPE string,
           END OF ty_text,
           ty_texts TYPE HASHED TABLE OF ty_text WITH UNIQUE KEY rule.

    DATA texts        TYPE ty_texts.
    DATA texts_loaded TYPE abap_bool.

    METHODS rule_text
      IMPORTING !rule         TYPE csequence
      RETURNING VALUE(result) TYPE string.

    METHODS kind_code
      IMPORTING !kind         TYPE string
      RETURNING VALUE(result) TYPE comb_auth_id
      RAISING   zcx_accx_error.

    METHODS messages
      IMPORTING !return       TYPE bapiret2_t
      RETURNING VALUE(result) TYPE string_table.

    "! Value criteria as SUIM selection rows (value 1 OR value 2 per field); checks the fields against TOBJ
    METHODS value_rows
      IMPORTING !object       TYPE xuobject
                !values       TYPE zif_accx_suim_gateway=>ty_value_criteria
      RETURNING VALUE(result) TYPE susr_t_sel_opt_val
      RAISING   zcx_accx_error.

ENDCLASS.

CLASS zcl_accx_suim_gateway IMPLEMENTATION.

  METHOD zif_accx_suim_gateway~get_variants.
    SELECT v~varname, COUNT( i~auth_id ) AS rules FROM usrvar AS v
      LEFT OUTER JOIN usrvarid AS i ON i~varname = v~varname
      GROUP BY v~varname
      INTO TABLE @DATA(auth_variants).
    SELECT varname, langu, vtext FROM usrvart WHERE langu = @sy-langu OR langu = 'E' INTO TABLE @DATA(auth_texts).
    SORT auth_texts BY varname.
    LOOP AT auth_variants INTO DATA(auth_variant).
      APPEND VALUE #( kind       = zif_accx_suim_gateway=>co_kind-authorization
                      name       = auth_variant-varname
                      rule_count = auth_variant-rules ) TO result ASSIGNING FIELD-SYMBOL(<variant>).
      " own language wins over English
      LOOP AT auth_texts INTO DATA(auth_text) WHERE varname = auth_variant-varname.
        IF <variant>-text IS INITIAL OR auth_text-langu = sy-langu.
          <variant>-text = auth_text-vtext.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    SELECT v~varname, COUNT( c~comb_id ) AS rules FROM usrvarcom AS v
      LEFT OUTER JOIN usrcrcomb AS c ON c~varname = v~varname
      GROUP BY v~varname
      INTO TABLE @DATA(comb_variants).
    SELECT varname, langu, vtext FROM usrvarcomt WHERE langu = @sy-langu OR langu = 'E' INTO TABLE @DATA(comb_texts).
    LOOP AT comb_variants INTO DATA(comb_variant).
      APPEND VALUE #( kind       = zif_accx_suim_gateway=>co_kind-combination
                      name       = comb_variant-varname
                      rule_count = comb_variant-rules ) TO result ASSIGNING <variant>.
      LOOP AT comb_texts INTO DATA(comb_text) WHERE varname = comb_variant-varname.
        IF <variant>-text IS INITIAL OR comb_text-langu = sy-langu.
          <variant>-text = comb_text-vtext.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_suim_gateway~critical_users.
    DATA auth_output TYPE usvca_t.
    DATA comb_output TYPE usvcc_t.
    DATA return      TYPE bapiret2_t.
    DATA message     TYPE c LENGTH 255.

    DATA(code)        = kind_code( kind ).
    DATA(user_range)  = users.
    DATA(group_range) = user_groups.

    CALL FUNCTION 'SUSR_SUIM_API_RSUSR008_009_NEW'
      DESTINATION 'NONE'
      EXPORTING
        iv_auth_or_comb       = code
        iv_var_name           = CONV varnameca( variant )
        iv_val_usrs           = valid_only
        no_additional_data    = abap_true
      IMPORTING
        et_auth_output        = auth_output
        et_comb_output        = comb_output
        return                = return
      CHANGING
        it_user               = user_range
        it_group              = group_range
      EXCEPTIONS
        system_failure        = 1 MESSAGE message
        communication_failure = 2 MESSAGE message
        OTHERS                = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( message = |SUIM critical access report failed: { message }| ).
    ENDIF.

    " lines without user are the rule headers of the SUIM list
    LOOP AT auth_output INTO DATA(auth) WHERE bname IS NOT INITIAL.
      APPEND VALUE #( kind    = kind
                      rule    = auth-auth_id
                      text    = rule_text( auth-auth_id )
                      color   = auth-color
                      subject = auth-bname ) TO result-findings.
    ENDLOOP.
    LOOP AT comb_output INTO DATA(comb) WHERE bname IS NOT INITIAL.
      APPEND VALUE #( kind    = kind
                      rule    = comb-comb_id
                      text    = rule_text( comb-comb_id )
                      color   = comb-color
                      subject = comb-bname ) TO result-findings.
    ENDLOOP.
    result-messages = messages( return ).
  ENDMETHOD.

  METHOD zif_accx_suim_gateway~critical_roles.
    DATA auth_output TYPE usrcrit_ca_role_t.
    DATA comb_output TYPE usrcrit_cc_role_t.
    DATA return      TYPE bapiret2_t.
    DATA message     TYPE c LENGTH 255.

    DATA(code)       = kind_code( kind ).
    DATA(role_range) = roles.

    CALL FUNCTION 'SUSR_API_RSUSR008_009_NEW_ROLE'
      DESTINATION 'NONE'
      EXPORTING
        iv_auth_or_comb       = code
        iv_var_name           = CONV varnameca( variant )
      IMPORTING
        et_auth_output        = auth_output
        et_comb_output        = comb_output
        return                = return
      CHANGING
        it_role               = role_range
      EXCEPTIONS
        system_failure        = 1 MESSAGE message
        communication_failure = 2 MESSAGE message
        OTHERS                = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( message = |SUIM critical access report failed: { message }| ).
    ENDIF.

    " lines without role are the rule headers of the SUIM list
    LOOP AT auth_output INTO DATA(auth) WHERE agr_name IS NOT INITIAL.
      APPEND VALUE #( kind      = kind
                      rule      = auth-auth_id
                      text      = rule_text( auth-auth_id )
                      color     = auth-color
                      subject   = auth-agr_name
                      role_type = auth-type ) TO result-findings.
    ENDLOOP.
    LOOP AT comb_output INTO DATA(comb) WHERE agr_name IS NOT INITIAL.
      APPEND VALUE #( kind      = kind
                      rule      = comb-comb_id
                      text      = rule_text( comb-comb_id )
                      color     = comb-color
                      subject   = comb-agr_name
                      role_type = comb-type ) TO result-findings.
    ENDLOOP.
    result-messages = messages( return ).
  ENDMETHOD.

  METHOD zif_accx_suim_gateway~find_users.
    DATA users   TYPE sim_t_rsusr002_alv.
    DATA objects TYPE susr_t_sel_opt_object.
    DATA return  TYPE bapiret2_t.
    DATA message TYPE c LENGTH 255.

    DATA(values) = value_rows( object = query-object values = query-values ).
    IF query-object IS NOT INITIAL AND values IS INITIAL.
      " any authorization for the object
      objects = VALUE #( ( sign = 'I' option = 'EQ' low = query-object ) ).
    ENDIF.

    CALL FUNCTION 'SUSR_SUIM_API_RSUSR002'
      DESTINATION 'NONE'
      EXPORTING
        it_user               = query-users
        it_group              = query-user_groups
        it_actgrps            = query-roles
        it_prof1              = query-profiles
        iv_tcode              = query-transaction
        iv_start_tx           = xsdbool( query-transaction IS NOT INITIAL )
        iv_unlock             = query-unlocked_only
        it_objct              = objects
        it_values             = values
      IMPORTING
        et_users              = users
        return                = return
      EXCEPTIONS
        wrong_parameter_set   = 1
        system_failure        = 2 MESSAGE message
        communication_failure = 3 MESSAGE message
        OTHERS                = 4.
    IF sy-subrc = 1.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `SUIM rejected the combination of search criteria.` ).
    ELSEIF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( message = |SUIM user search (RSUSR002) failed: { message }| ).
    ENDIF.

    LOOP AT users INTO DATA(user) WHERE bname IS NOT INITIAL.
      APPEND VALUE #( user           = user-bname
                      name           = condense( user-name_text )
                      user_type      = user-ustyp
                      user_group     = user-class
                      valid_from     = user-gltgv
                      valid_to       = user-gltgb
                      lock           = condense( user-lockreason )
                      reference_user = user-refuser ) TO result-users.
    ENDLOOP.
    result-messages = messages( return ).
  ENDMETHOD.

  METHOD zif_accx_suim_gateway~find_roles.
    DATA roles   TYPE sim_t_agr.
    DATA objects TYPE susr_t_sel_opt_object.
    DATA return  TYPE bapiret2_t.
    DATA message TYPE c LENGTH 255.

    DATA(values) = value_rows( object = query-object values = query-values ).
    IF query-object IS NOT INITIAL AND values IS INITIAL.
      objects = VALUE #( ( sign = 'I' option = 'EQ' low = query-object ) ).
    ENDIF.

    CALL FUNCTION 'SUSR_SUIM_API_RSUSR070'
      DESTINATION 'NONE'
      EXPORTING
        it_actgrps            = query-roles
        it_text1              = query-descriptions
        iv_s_roles            = query-single
        iv_c_roles            = query-composite
        iv_all_user           = xsdbool( query-users IS INITIAL )
        iv__user              = xsdbool( query-users IS NOT INITIAL )
        it_user               = query-users
        it_tcode1             = query-transactions
        it_objct              = objects
        it_values             = values
      IMPORTING
        et_roles              = roles
        return                = return
      EXCEPTIONS
        wrong_parameter_set   = 1
        system_failure        = 2 MESSAGE message
        communication_failure = 3 MESSAGE message
        OTHERS                = 4.
    IF sy-subrc = 1.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `SUIM rejected the combination of search criteria.` ).
    ELSEIF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( message = |SUIM role search (RSUSR070) failed: { message }| ).
    ENDIF.

    LOOP AT roles INTO DATA(role) WHERE agr_name IS NOT INITIAL.
      APPEND VALUE #( role      = role-agr_name
                      text      = condense( role-atext )
                      role_type = role-agr_type ) TO result-roles.
    ENDLOOP.
    result-messages = messages( return ).
  ENDMETHOD.

  METHOD value_rows.
    DATA fields TYPE STANDARD TABLE OF xufield WITH EMPTY KEY.

    IF values IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE * FROM tobj WHERE objct = @object INTO @DATA(definition).
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |Authorization object { object } does not exist.| ).
    ENDIF.
    DO 10 TIMES.
      ASSIGN COMPONENT |FIEL{ sy-index MOD 10 }| OF STRUCTURE definition TO FIELD-SYMBOL(<field>).
      IF sy-subrc = 0 AND <field> IS NOT INITIAL.
        APPEND <field> TO fields.
      ENDIF.
    ENDDO.

    LOOP AT values INTO DATA(criterion).
      IF NOT line_exists( fields[ table_line = criterion-field ] ).
        RAISE EXCEPTION NEW zcx_accx_error(
          status  = zif_accx_types=>co_status-invalid
          message = |{ criterion-field } is not a field of { object }. Fields: { concat_lines_of( table = fields sep = `, ` ) }.| ).
      ENDIF.
      IF lines( criterion-values ) > zif_accx_suim_gateway=>co_max_alternatives.
        RAISE EXCEPTION NEW zcx_accx_error(
          status  = zif_accx_types=>co_status-invalid
          message = |SUIM accepts at most { zif_accx_suim_gateway=>co_max_alternatives } alternative values per field ({ criterion-field }).| ).
      ENDIF.
      APPEND VALUE #( objct = object
                      field = criterion-field
                      val1  = VALUE #( criterion-values[ 1 ] OPTIONAL )
                      val2  = VALUE #( criterion-values[ 2 ] OPTIONAL ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD rule_text.
    IF texts_loaded = abap_false.
      texts_loaded = abap_true.
      SELECT auth_id AS rule, text, langu FROM uscrauidt WHERE langu = @sy-langu OR langu = 'E'
        INTO TABLE @DATA(auth_texts).
      SELECT comb_id AS rule, ctext AS text, langu FROM usrcombt WHERE langu = @sy-langu OR langu = 'E'
        APPENDING TABLE @auth_texts.
      " own language first; INSERT keeps the first text per rule; SAP texts are aligned with blanks
      LOOP AT auth_texts INTO DATA(own) WHERE langu = sy-langu.
        INSERT VALUE #( rule = own-rule text = condense( own-text ) ) INTO TABLE texts.
      ENDLOOP.
      LOOP AT auth_texts INTO DATA(english) WHERE langu <> sy-langu.
        INSERT VALUE #( rule = english-rule text = condense( english-text ) ) INTO TABLE texts.
      ENDLOOP.
    ENDIF.
    result = VALUE #( texts[ rule = rule ]-text DEFAULT rule ).
  ENDMETHOD.

  METHOD kind_code.
    result = SWITCH #( kind
                       WHEN zif_accx_suim_gateway=>co_kind-authorization THEN 'VCA'
                       WHEN zif_accx_suim_gateway=>co_kind-combination   THEN 'VCC' ).
    IF result IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |Unknown variant kind { kind }.| ).
    ENDIF.
  ENDMETHOD.

  METHOD messages.
    LOOP AT return INTO DATA(line).
      " 01/707: no data found - an empty result, not a problem
      IF line-id = '01' AND line-number = '707'.
        CONTINUE.
      ENDIF.
      " SAP aligns numbers in some texts with blanks
      APPEND |SUIM { line-type } { line-id }/{ line-number }: { condense( line-message ) }| TO result.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
