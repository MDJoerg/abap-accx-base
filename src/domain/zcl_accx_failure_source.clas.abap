"! <p class="shorttext synchronized">Access Explorer: failed checks from SU53 buffer</p>
"! Reads the SU53 buffers of all application servers via SUSR_USER_SU53_READ,
"! which checks the caller itself (S_USER_GRP 03 for other users), and the user
"! trace STUSERTRACE via SUAUTH_READ_USER_TRACE (caller needs S_ADMI_FCD STUR).
"! <p class="shorttext synchronized">Access Explorer: failed checks from SU53 buffer</p>
"! Reads the SU53 buffers of all application servers via SUSR_USER_SU53_READ,
"! which checks the caller itself (S_USER_GRP 03 for other users), and the user
"! trace STUSERTRACE via SUAUTH_READ_USER_TRACE (caller needs S_ADMI_FCD STUR).
CLASS zcl_accx_failure_source DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_failure_source.

    "! Most trace entries read per call
    CONSTANTS co_trace_max TYPE i VALUE 2000.

  PROTECTED SECTION.
    METHODS to_failure
      IMPORTING !user         TYPE syuname
                !entry        TYPE usr07_ext
      RETURNING VALUE(result) TYPE zif_accx_failure_source=>ty_failure.

    "! Trace rows with field names from TOBJ and gateway services resolved from USOBHASH
    METHODS trace_to_failures
      IMPORTING !user         TYPE syuname
                !trace        TYPE suauthvaltrc_t
      RETURNING VALUE(result) TYPE zif_accx_failure_source=>ty_failures.

    "! Check run by ACCX itself (program in the ACCX namespace or one of the function
    "! modules ACCX calls by RFC, application type RF), or on behalf of another user
    METHODS is_simulation
      IMPORTING !user         TYPE syuname
                !failure      TYPE zif_accx_failure_source=>ty_failure
                !app_type     TYPE usobtype OPTIONAL
                !app_name     TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.

CLASS zcl_accx_failure_source IMPLEMENTATION.

  METHOD zif_accx_failure_source~read_su53.
    DATA entries    TYPE usr07_ext_tt.
    DATA return     TYPE bapiret2.
    DATA rfc_errors TYPE bapirettab.

    CALL FUNCTION 'SUSR_USER_SU53_READ'
      EXPORTING
        iv_bname       = user
        iv_from        = from
        iv_to          = to
        iv_all_servers = 'X'
      IMPORTING
        et_usr07_ext   = entries
        es_return      = return
        et_rfc_error   = rfc_errors.

    IF return-type CA 'EAX'.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = zif_accx_types=>co_status-denied
        message = |SU53 of user { user } cannot be read: { return-message }| ).
    ENDIF.

    LOOP AT entries INTO DATA(entry) WHERE bname = user.
      APPEND to_failure( user = user entry = entry ) TO result-failures.
    ENDLOOP.
    LOOP AT rfc_errors INTO DATA(rfc_error).
      APPEND rfc_error-message TO result-errors.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_failure_source~read_trace.
    DATA trace  TYPE suauthvaltrc_t.
    DATA errors TYPE bapirettab.
    DATA ranges TYPE STANDARD TABLE OF bapiussrge WITH EMPTY KEY.
    DATA first  TYPE timestamp.
    DATA last   TYPE timestamp VALUE '99991231235959'.

    first = cl_abap_tstmp=>move_to_short_trunc( from ).
    IF to IS NOT INITIAL.
      last = cl_abap_tstmp=>move_to_short_trunc( to ).
    ENDIF.
    ranges = VALUE #( parameter = 'SUAUTHVALTRC' sign = 'I'
                      ( field = 'USERNAME'  option = 'EQ' low = user )
                      ( field = 'RC'        option = 'NE' low = '0' )
                      ( field = 'FIRSTCALL' option = 'BT' low = |{ first }| high = |{ last }| ) ).

    " the function module reads the trace in an RFC session of its own (as SAP's STUSERTRACE does)
    CALL FUNCTION 'SUAUTH_READ_USER_TRACE'
      EXPORTING
        iv_function    = 'USTC'
        iv_destination = 'NONE'
        iv_max_rec     = co_trace_max
      IMPORTING
        et_user_trace  = trace
        et_error       = errors
      TABLES
        ct_sel_range   = ranges.

    LOOP AT errors INTO DATA(error) WHERE type CA 'EAX'.
      RAISE EXCEPTION NEW zcx_accx_error(
        status  = COND #( WHEN error-id = 'TC' AND error-number = '053'
                          THEN zif_accx_types=>co_status-denied
                          ELSE zif_accx_types=>co_status-error )
        message = COND #( WHEN error-id = 'TC' AND error-number = '053'
                          THEN `Reading the user trace (STUSERTRACE) requires authorization S_ADMI_FCD with value STUR.`
                          ELSE |The user trace (STUSERTRACE) cannot be read: { error-message }| ) ).
    ENDLOOP.

    result-failures = trace_to_failures( user = user trace = trace ).
    IF lines( trace ) >= co_trace_max.
      APPEND |User trace: only the first { co_trace_max } entries were read; narrow the time range.| TO result-errors.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_failure_source~trace_status.
    result-mode = cl_susr_tools_kernel=>auth_user_trace_get_status( ).
    IF result-mode NA 'XF'.
      result-mode = zif_accx_failure_source=>co_trace_mode-inactive.
      RETURN.
    ENDIF.
    result-covers_user = abap_true.
    IF result-mode <> zif_accx_failure_source=>co_trace_mode-filtered.
      RETURN.
    ENDIF.

    " user filter of STUSERTRACE: EQ/CP include, NE/NP exclude; no include = all users
    SELECT select_option, value FROM suauthvalfilter
      WHERE filterfield = 'USER'
      INTO TABLE @DATA(filters).
    DATA(included) = abap_undefined.
    LOOP AT filters INTO DATA(filter).
      DATA(pattern) = condense( CONV string( filter-value ) ).
      CASE filter-select_option.
        WHEN 'NE'.
          IF user = pattern.
            result-covers_user = abap_false.
            RETURN.
          ENDIF.
        WHEN 'NP'.
          IF user CP pattern.
            result-covers_user = abap_false.
            RETURN.
          ENDIF.
        WHEN 'CP'.
          included = COND #( WHEN user CP pattern OR included = abap_true THEN abap_true ELSE abap_false ).
        WHEN OTHERS.
          included = COND #( WHEN user = pattern OR included = abap_true THEN abap_true ELSE abap_false ).
      ENDCASE.
    ENDLOOP.
    result-covers_user = xsdbool( included <> abap_false ).
  ENDMETHOD.

  METHOD trace_to_failures.
    TYPES ty_hashes TYPE SORTED TABLE OF xupname WITH UNIQUE KEY table_line.
    TYPES ty_objects TYPE SORTED TABLE OF xuobject WITH UNIQUE KEY table_line.
    DATA hashes  TYPE ty_hashes.
    DATA objects TYPE ty_objects.
    DATA field   TYPE xufield.

    IF trace IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT trace INTO DATA(row).
      INSERT row-object INTO TABLE objects.
      IF row-type = 'HT'.
        INSERT CONV xupname( row-name ) INTO TABLE hashes.
      ENDIF.
    ENDLOOP.

    SELECT objct, fiel1, fiel2, fiel3, fiel4, fiel5, fiel6, fiel7, fiel8, fiel9, fiel0 FROM tobj
      FOR ALL ENTRIES IN @objects
      WHERE objct = @objects-table_line
      INTO TABLE @DATA(object_fields).
    IF hashes IS NOT INITIAL.
      SELECT name, object, obj_name FROM usobhash
        FOR ALL ENTRIES IN @hashes
        WHERE name = @hashes-table_line AND type = 'HT'
        INTO TABLE @DATA(services).
    ENDIF.

    LOOP AT trace INTO row.
      DATA(failure) = VALUE zif_accx_failure_source=>ty_failure(
        timestamp   = row-firstcall
        object      = row-object
        return_code = row-rc
        transaction = COND #( WHEN row-type = 'TR' THEN row-name )
        program     = row-abapprog
        line        = row-abapline
        for_user    = row-foruser
        source      = zif_accx_failure_source=>co_source-trace ).
      DATA(hash) = CONV xupname( row-name ).
      failure-application = COND #( WHEN row-cds IS NOT INITIAL THEN |CDS view { row-cds }|
                                    WHEN row-type = 'TR' THEN ``
                                    WHEN row-type = 'HT' AND line_exists( services[ name = hash ] )
                                    THEN |{ services[ name = hash ]-object } { services[ name = hash ]-obj_name }|
                                    ELSE |{ row-type } { row-name }| ).
      failure-application = condense( failure-application ).

      READ TABLE object_fields INTO DATA(names) WITH KEY objct = row-object.
      IF sy-subrc <> 0.
        CLEAR names.
      ENDIF.
      DO 10 TIMES.
        DATA(index) = sy-index MOD 10.
        ASSIGN COMPONENT |FIEL{ index }| OF STRUCTURE names TO FIELD-SYMBOL(<name>).
        ASSIGN COMPONENT |FIELD{ index }| OF STRUCTURE row TO FIELD-SYMBOL(<value>).
        IF <name> IS NOT ASSIGNED OR <value> IS NOT ASSIGNED.
          CONTINUE.
        ENDIF.
        field = <name>.
        IF field IS NOT INITIAL.
          APPEND VALUE #( field = field value = condense( CONV string( <value> ) ) ) TO failure-fields.
        ENDIF.
        UNASSIGN: <name>, <value>.
      ENDDO.

      failure-is_simulation = is_simulation( user     = user
                                             failure  = failure
                                             app_type = row-type
                                             app_name = row-name ).
      APPEND failure TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD to_failure.
    DATA field TYPE xufield.
    DATA value TYPE xuval.

    result = VALUE #( timestamp   = entry-timestamp
                      instance    = entry-instance
                      object      = entry-objct
                      return_code = entry-rc
                      transaction = entry-p_tcode
                      program     = entry-abapprog
                      line        = entry-abapline
                      for_user    = entry-foruser
                      source      = zif_accx_failure_source=>co_source-su53
                      application = COND #( WHEN entry-disp_name IS NOT INITIAL
                                            THEN |{ entry-typetext } { entry-disp_name }|
                                            WHEN entry-name IS NOT INITIAL
                                            THEN |{ entry-type } { entry-name }| ) ).
    result-application = condense( result-application ).

    DO 10 TIMES.
      DATA(index) = sy-index MOD 10.
      ASSIGN COMPONENT |FIEL{ index }| OF STRUCTURE entry TO FIELD-SYMBOL(<field>).
      ASSIGN COMPONENT |VAL{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }| OF STRUCTURE entry TO FIELD-SYMBOL(<value>).
      IF <field> IS NOT ASSIGNED OR <value> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.
      field = <field>.
      value = <value>.
      UNASSIGN: <field>, <value>.
      IF field IS NOT INITIAL.
        APPEND VALUE #( field = field value = condense( value ) ) TO result-fields.
      ENDIF.
    ENDDO.

    result-is_simulation = is_simulation( user     = user
                                          failure  = result
                                          app_type = entry-type
                                          app_name = entry-name ).
  ENDMETHOD.

  METHOD is_simulation.
    " checks run by ACCX itself or on behalf of another user are no failures of this user;
    " the SUIM and trace APIs run in an RFC session of their own (DESTINATION 'NONE'), so their
    " checks carry the function module as application, not an ACCX program
    result = xsdbool( failure-program CP 'ZCL_ACCX*'
                   OR failure-program CP 'ZACCX*'
                   OR ( failure-for_user IS NOT INITIAL AND failure-for_user <> user )
                   OR ( app_type = 'RF' AND ( app_name = 'SUSR_SUIM_API_RSUSR002'
                                           OR app_name = 'SUSR_SUIM_API_RSUSR070'
                                           OR app_name = 'SUSR_SUIM_API_RSUSR008_009_NEW'
                                           OR app_name = 'SUSR_API_RSUSR008_009_NEW_ROLE'
                                           OR app_name = 'SUAUTH_READ_TRACE_VALUES' ) ) ).
  ENDMETHOD.

ENDCLASS.
