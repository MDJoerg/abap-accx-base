"! <p class="shorttext synchronized">Access Explorer tool: check_user_access</p>
"! Simulates the authorization checks of a transaction start or of a given
"! authorization for another user. Also reports whether the user can log on at
"! all, because AUTHORITY-CHECK ... FOR USER ignores lock and validity.
CLASS zcl_accx_t_check_user_access DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_payload,
             user           TYPE syuname,
             target_type    TYPE string,
             target         TYPE string,
             granted        TYPE abap_bool,
             logon_possible TYPE abap_bool,
             logon_issue    TYPE string,
             checks         TYPE zif_accx_auth_evaluator=>ty_check_results,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `check_user_access`.

    CONSTANTS: BEGIN OF co_target_type,
                 transaction   TYPE string VALUE `transaction`,
                 authorization TYPE string VALUE `authorization`,
               END OF co_target_type.

    CONSTANTS co_max_fields TYPE i VALUE 10.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

    "! Parameters shared with tools building on this one (explain_missing_access)
    METHODS target_params
      RETURNING VALUE(result) TYPE zif_accx_types=>ty_params.

  PRIVATE SECTION.
    METHODS logon_issue
      IMPORTING !user         TYPE syuname
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_check_user_access IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Check user access`
      description = |Checks whether a user may start a transaction or holds an authorization, by simulating the SAP | &&
                    |authorization checks for that user (AUTHORITY-CHECK FOR USER). For a transaction, the start check S_TCODE | &&
                    |and the check object maintained for the transaction (SE93) are evaluated. For an authorization, pass the | &&
                    |authorization object as target and optional FIELD=VALUE pairs in values. Every check is reported with its | &&
                    |outcome, so the missing authorization can be named precisely. The result also states whether the user can | &&
                    |log on at all (lock, validity). Note: failed simulated checks are also recorded in the SU53 buffer of the | &&
                    |calling user.|
      group       = zif_accx_types=>co_group-diag
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_CHECK_USER_ACCESS\TYPE=TY_PAYLOAD`
      params      = target_params( ) ).
  ENDMETHOD.

  METHOD target_params.
    result = VALUE #( ( param( name        = `user`
                               description = `SAP user ID to check, e.g. JDOE (case-insensitive).`
                               required    = abap_true
                               maximum     = 12 ) )
                      ( param( name        = `target_type`
                               description = `What to check: transaction (start authorization) or authorization (object with field values).`
                               required    = abap_true
                               enum        = VALUE #( ( co_target_type-transaction ) ( co_target_type-authorization ) ) ) )
                      ( param( name        = `target`
                               description = `Transaction code (e.g. SU01) or authorization object (e.g. S_TABU_DIS).`
                               required    = abap_true
                               maximum     = 40 ) )
                      ( param( name        = `values`
                               kind        = zif_accx_types=>co_kind-string_list
                               description = |Only for target_type authorization: field values as FIELD=VALUE, e.g. ACTVT=02 or DICBERCLS=SC. | &&
                                             |Fields that are not given are not checked (max. 10 fields).| ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA checks TYPE zif_accx_auth_evaluator=>ty_checks.
    DATA check  TYPE zif_accx_auth_evaluator=>ty_check.

    DATA(user)        = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(target_type) = args->get_string( `target_type` ).
    DATA(target)      = to_upper( condense( args->get_string( `target` ) ) ).
    DATA(evaluator)   = zcl_accx_domain_factory=>auth_evaluator( ).

    IF zcl_accx_domain_factory=>user_repo( )->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = |User { user } does not exist in system { sy-sysid }, client { sy-mandt }.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-denied
                                          message = |You are not authorized to display user { user } (S_USER_GRP, activity 03).| ).
    ENDIF.

    CASE target_type.
      WHEN co_target_type-transaction.
        DATA(tcode) = CONV tcode( target ).
        IF evaluator->transaction_exists( tcode ) = abap_false.
          RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                              message = |Transaction { target } does not exist.| ).
        ENDIF.
        checks = evaluator->get_transaction_checks( tcode ).

      WHEN co_target_type-authorization.
        DATA(object) = CONV xuobject( target ).
        IF evaluator->object_exists( object ) = abap_false.
          RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                              message = |Authorization object { target } does not exist.| ).
        ENDIF.
        check = VALUE #( object = object reason = `Requested authorization` ).
        LOOP AT args->get_strings( `values` ) INTO DATA(pair).
          SPLIT pair AT '=' INTO DATA(field) DATA(value).
          field = to_upper( condense( field ) ).
          IF field IS NOT INITIAL.
            APPEND VALUE #( field = field value = condense( value ) ) TO check-fields.
          ENDIF.
        ENDLOOP.
        IF lines( check-fields ) > co_max_fields.
          APPEND |Only the first { co_max_fields } field values were checked.| TO result-warnings.
        ENDIF.
        APPEND check TO checks.
    ENDCASE.

    DATA(payload) = NEW ty_payload( user = user target_type = target_type target = target granted = abap_true ).
    LOOP AT checks INTO check.
      DATA(outcome) = evaluator->simulate( user = user check = check ).
      APPEND outcome TO payload->checks.
      IF outcome-granted = abap_false.
        payload->granted = abap_false.
      ENDIF.
    ENDLOOP.

    payload->logon_issue    = logon_issue( user ).
    payload->logon_possible = xsdbool( payload->logon_issue IS INITIAL ).

    result-data        = payload.
    result-total_count = lines( payload->checks ).
    result-sources     = VALUE #( ( `AUTHORITY-CHECK FOR USER` )
                                  ( COND #( WHEN target_type = co_target_type-transaction THEN `TSTC, TSTCA` ELSE `TOBJ` ) )
                                  ( `USR02` ) ).
    IF payload->logon_possible = abap_false.
      APPEND |{ user } cannot log on ({ payload->logon_issue }); the authorizations are not usable until this is resolved.|
        TO result-warnings.
    ENDIF.
    IF payload->granted = abap_false.
      APPEND |Failed simulated checks are also recorded in the SU53 buffer of the calling user { ctx->caller( ) }, not of { user }.|
        TO result-warnings.
      APPEND |Use explain_missing_access to find roles that would close the gap for { user }.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD logon_issue.
    DATA(master) = zcl_accx_domain_factory=>user_repo( )->get_user( user ).
    IF master-locked = abap_true.
      result = |locked: { master-lock_reasons }|.
    ELSEIF master-valid_from IS NOT INITIAL AND sy-datum < master-valid_from.
      result = |user valid only from { master-valid_from DATE = ISO }|.
    ELSEIF master-valid_to IS NOT INITIAL AND sy-datum > master-valid_to.
      result = |user validity ended on { master-valid_to DATE = ISO }|.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    DATA(what) = COND string( WHEN <payload>-target_type = co_target_type-transaction
                              THEN |start transaction { <payload>-target }|
                              ELSE |hold authorization { <payload>-target }| ).
    DATA(verdict) = COND string( WHEN <payload>-granted = abap_true AND <payload>-logon_possible = abap_true THEN `**may**`
                                 WHEN <payload>-granted = abap_true THEN `**would be authorized to**`
                                 ELSE `**may not**` ).
    result-summary = |User **{ <payload>-user }** { verdict } { what }.|.
    IF <payload>-logon_possible = abap_false.
      result-summary = |{ result-summary } **The user cannot log on** ({ <payload>-logon_issue }).|.
    ENDIF.

    LOOP AT <payload>-checks INTO DATA(check).
      result-summary = |{ result-summary }\n- { check-object } ({ check-condition }), { check-reason }: { check-outcome }|.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
