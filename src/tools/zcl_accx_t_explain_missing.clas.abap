"! <p class="shorttext synchronized">Access Explorer tool: explain_missing_access</p>
"! Explains a missing authorization and proposes existing roles that close the
"! gap. Builds on check_user_access; proposes only, never assigns. Roles that
"! grant further critical authorizations (SUIM definitions) are flagged; among
"! roles of equal standing the less critical one wins, and a less critical
"! alternative is named when the recommended role is critical. Roles granting a
"! checked field with full wildcard (*) and SAP template roles are ranked down.
"! When no role fits, or only critical, wildcard or template roles outside the
"! user group's practice, it hands a ready-made draft_role_change call over that
"! extends one of the user's own roles.
CLASS zcl_accx_t_explain_missing DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_candidate,
             role                TYPE agr_name,
             description         TYPE string,
             "! other users of the same user group with a valid assignment
             peers_with_role     TYPE i,
             "! at least one colleague of the user group holds the role
             held_by_peers       TYPE abap_bool,
             object_count        TYPE i,
             broad               TYPE abap_bool,
             composite_parents   TYPE string,
             previously_assigned TYPE abap_bool,
             assignment          TYPE string,
             "! critical authorizations the role grants beyond the requested access
             critical            TYPE zif_accx_critical_rules=>ty_hits,
             "! ranking weight of critical: high 100, medium 10, low 1 per rule
             critical_score      TYPE i,
             "! the role grants a checked field (ACTVT aside) with full wildcard *
             wildcard            TYPE abap_bool,
             "! those fields as OBJECT-FIELD, comma separated
             wildcard_fields     TYPE string,
             "! SAP delivered role (SAP_*), meant to be copied rather than assigned
             sap_template        TYPE abap_bool,
           END OF ty_candidate,
           ty_candidates TYPE STANDARD TABLE OF ty_candidate WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user                 TYPE syuname,
             target_type          TYPE string,
             target               TYPE string,
             already_granted      TYPE abap_bool,
             logon_possible       TYPE abap_bool,
             logon_issue          TYPE string,
             missing              TYPE zif_accx_auth_evaluator=>ty_check_results,
             "! critical rules met by the requested access itself
             request_critical     TYPE zif_accx_critical_rules=>ty_hits,
             user_group           TYPE string,
             peer_group_size      TYPE i,
             candidates           TYPE ty_candidates,
             "! less critical candidate, if the recommended role grants further critical authorizations
             less_critical_option TYPE agr_name,
             "! arguments for assign_role (plugin ADMIN, JSON object) that assign the recommended role once approved;
             "! empty for an SAP template to be copied, an assignment valid today or one only through a composite role
             assign_arguments     TYPE string,
             "! own role of the user to extend instead, when no role fits or only critical, wildcard or template ones
             draft_role           TYPE agr_name,
             "! colleagues of the user group holding the draft role
             draft_role_peers     TYPE i,
             "! arguments for draft_role_change (JSON object)
             draft_arguments      TYPE string,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `explain_missing_access`.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

    "! The user's own single role most used in the user group (customer roles before SAP templates);
    "! also used by diagnose_fiori_app_access
    METHODS own_role_to_extend
      IMPORTING !ctx         TYPE REF TO zif_accx_context
                !assignments TYPE zif_accx_user_repo=>ty_role_assignments
                !user_group  TYPE xuclass
                !user        TYPE syuname
      EXPORTING !role        TYPE agr_name
                !peers       TYPE i.

    "! Arguments for assign_role (plugin ADMIN) as JSON object; dates are left to its defaults
    "! (today to 9999-12-31). Also used by diagnose_fiori_app_access
    METHODS assign_arguments
      IMPORTING !user         TYPE csequence
                !role         TYPE csequence
                !reason       TYPE csequence
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    METHODS assignment_state
      IMPORTING !role                TYPE agr_name
                !assignments         TYPE zif_accx_user_repo=>ty_role_assignments
      EXPORTING !previously_assigned TYPE abap_bool
                !text                TYPE string.

    "! Critical rules of a role that the requested access does not already imply
    METHODS extra_critical
      IMPORTING !role             TYPE agr_name
                !request_critical TYPE zif_accx_critical_rules=>ty_hits
                !rules            TYPE REF TO zif_accx_critical_rules
      EXPORTING !hits             TYPE zif_accx_critical_rules=>ty_hits
                !score            TYPE i.

    "! Fields of the missing checks (ACTVT aside) the role grants with full wildcard *, as OBJECT-FIELD
    METHODS wildcard_fields
      IMPORTING !role         TYPE agr_name
                !missing      TYPE zif_accx_auth_evaluator=>ty_check_results
      RETURNING VALUE(result) TYPE string.

    METHODS hits_text
      IMPORTING !hits         TYPE zif_accx_critical_rules=>ty_hits
      RETURNING VALUE(result) TYPE string.

    "! draft_role_change arguments that add exactly the requested access to the role
    METHODS draft_arguments
      IMPORTING !payload      TYPE ty_payload
      RETURNING VALUE(result) TYPE string.

    METHODS json_string
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_explain_missing IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    DATA(params) = NEW zcl_accx_t_check_user_access( )->target_params( ).
    APPEND max_rows_param( ) TO params.
    result = VALUE #(
      name        = co_name
      title       = `Explain missing access`
      description = |Explains why a user lacks an authorization and which existing roles would close the gap. It simulates | &&
                    |the checks like check_user_access, then searches single roles whose active authorizations cover all | &&
                    |missing checks (patterns and value ranges are evaluated) and ranks them: a previously assigned, expired | &&
                    |role first, then roles already held by colleagues of the same user group, then roles without further | &&
                    |critical authorizations (as defined in SUIM), then roles granting the checked values without full | &&
                    |wildcard (*), customer roles before SAP templates, then by number of colleagues, narrow before broad. | &&
                    |Critical authorizations and wildcards of every candidate are named, a less critical alternative is | &&
                    |offered, and the tool states whether the requested access itself is critical. Composite roles | &&
                    |containing a candidate are listed. If no role fits, or only roles with further critical authorizations, | &&
                    |full wildcards or SAP templates outside the user group's practice, it proposes to extend one of the | &&
                    |user's own roles and returns the arguments for draft_role_change. | &&
                    |Colleagues are only counted, never named. The tool only proposes - roles are assigned in the access | &&
                    |request process; for the recommended role it returns the arguments for assign_role (plugin ADMIN) to | &&
                    |carry out the approved request.|
      group       = zif_accx_types=>co_group-diag
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_EXPLAIN_MISSING\TYPE=TY_PAYLOAD`
      params      = params ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA roles     TYPE SORTED TABLE OF agr_name WITH UNIQUE KEY table_line.
    DATA kept      TYPE SORTED TABLE OF agr_name WITH UNIQUE KEY table_line.
    DATA requested TYPE zif_accx_critical_rules=>ty_auth_values.
    FIELD-SYMBOLS <check> TYPE zcl_accx_t_check_user_access=>ty_payload.

    " 1 - simulate the checks (raises not_found / denied like check_user_access)
    DATA(checker) = CAST zif_accx_tool( NEW zcl_accx_t_check_user_access( ) ).
    DATA(check_result) = checker->execute( args = args ctx = ctx ).
    ASSIGN check_result-data->* TO <check>.

    DATA(payload) = NEW ty_payload( user            = <check>-user
                                    target_type     = <check>-target_type
                                    target          = <check>-target
                                    already_granted = <check>-granted
                                    logon_possible  = <check>-logon_possible
                                    logon_issue     = <check>-logon_issue ).
    result-data     = payload.
    result-sources  = check_result-sources.
    result-warnings = check_result-warnings.
    IF <check>-granted = abap_true.
      RETURN.
    ENDIF.
    payload->missing = VALUE #( FOR c IN <check>-checks WHERE ( granted = abap_false ) ( c ) ).

    " 2 - is the requested access itself critical? (each missing check as one authorization)
    DATA(rules) = zcl_accx_domain_factory=>critical_rules( ).
    LOOP AT payload->missing INTO DATA(missing).
      DATA(auth) = CONV xuauth( |REQ{ sy-tabix }| ).
      LOOP AT missing-fields INTO DATA(field_value).
        APPEND VALUE #( object = missing-object auth = auth field = field_value-field low = field_value-value )
          TO requested.
      ENDLOOP.
    ENDLOOP.
    payload->request_critical = rules->evaluate( requested ).

    " 3 - roles covering every missing check
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    DATA(first) = abap_true.
    LOOP AT payload->missing INTO missing.
      DATA(granting) = role_repo->find_roles_granting( VALUE #( object = missing-object fields = missing-fields ) ).
      IF first = abap_true.
        LOOP AT granting INTO DATA(role).
          INSERT role INTO TABLE roles.
        ENDLOOP.
        first = abap_false.
      ELSE.
        CLEAR kept.
        LOOP AT roles INTO role.
          IF line_exists( granting[ table_line = role ] ).
            INSERT role INTO TABLE kept.
          ENDIF.
        ENDLOOP.
        roles = kept.
      ENDIF.
    ENDLOOP.

    " 4 - context of the user: user group, peers, own assignments
    DATA(master) = user_repo->get_user( payload->user ).
    DATA(group) = CONV xuclass( master-user_group ).
    payload->user_group      = master-user_group.
    payload->peer_group_size = role_repo->count_group_members( user_group = group exclude_user = payload->user ).
    DATA(assignments) = user_repo->get_role_assignments( payload->user ).

    " 5 - candidates the caller may see, ranked
    LOOP AT roles INTO role.
      IF ctx->guard( )->can_display_role( role ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      DATA(info) = role_repo->get_role_info( role ).
      IF info-composite = abap_true OR info-generated = abap_false.
        " composite roles are shown as parents; roles without profile grant nothing
        CONTINUE.
      ENDIF.
      DATA(candidate) = VALUE ty_candidate(
        role              = role
        description       = info-description
        object_count      = info-object_count
        broad             = info-broad
        composite_parents = concat_lines_of( table = info-parents sep = `, ` )
        peers_with_role   = role_repo->count_holders( role = role user_group = group exclude_user = payload->user )
        sap_template      = xsdbool( role CP 'SAP_*' )
        wildcard_fields   = wildcard_fields( role = role missing = payload->missing ) ).
      candidate-held_by_peers = xsdbool( candidate-peers_with_role > 0 ).
      candidate-wildcard      = xsdbool( candidate-wildcard_fields IS NOT INITIAL ).
      assignment_state( EXPORTING role                = role
                                  assignments         = assignments
                        IMPORTING previously_assigned = candidate-previously_assigned
                                  text                = candidate-assignment ).
      extra_critical( EXPORTING role             = role
                                request_critical = payload->request_critical
                                rules            = rules
                      IMPORTING hits             = candidate-critical
                                score            = candidate-critical_score ).
      APPEND candidate TO payload->candidates.
    ENDLOOP.

    " proven practice in the user group first, then the least critical, most precise customer role
    SORT payload->candidates BY previously_assigned DESCENDING
                                held_by_peers       DESCENDING
                                critical_score      ASCENDING
                                wildcard            ASCENDING
                                sap_template        ASCENDING
                                peers_with_role     DESCENDING
                                broad               ASCENDING
                                object_count        ASCENDING
                                role                ASCENDING.

    " less critical alternative outside the user group's practice (list is sorted by score within that part)
    IF payload->candidates IS NOT INITIAL AND payload->candidates[ 1 ]-critical_score > 0.
      LOOP AT payload->candidates INTO DATA(option)
           WHERE held_by_peers = abap_false AND previously_assigned = abap_false.
        IF option-critical_score < payload->candidates[ 1 ]-critical_score.
          payload->less_critical_option = option-role.
        ENDIF.
        EXIT.
      ENDLOOP.
    ENDIF.

    " 6 - no fitting role, only critical ones without a usable alternative (SAP templates are copied,
    "     not assigned), or only a wildcard or template role nobody in the user group holds:
    "     extend one of the user's own roles
    DATA(questionable) = abap_false.
    IF payload->candidates IS NOT INITIAL.
      DATA(top) = payload->candidates[ 1 ].
      questionable = xsdbool( top-previously_assigned = abap_false AND top-held_by_peers = abap_false
                              AND ( top-wildcard = abap_true OR top-sap_template = abap_true ) ).
    ENDIF.
    IF payload->candidates IS INITIAL
       OR questionable = abap_true
       OR ( top-critical_score > 0 AND top-previously_assigned = abap_false
            AND ( payload->less_critical_option IS INITIAL OR payload->less_critical_option CP 'SAP_*' ) ).
      own_role_to_extend( EXPORTING ctx         = ctx
                                    assignments = assignments
                                    user_group  = group
                                    user        = payload->user
                          IMPORTING role        = payload->draft_role
                                    peers       = payload->draft_role_peers ).
      IF payload->draft_role IS NOT INITIAL.
        payload->draft_arguments = draft_arguments( payload->* ).
      ENDIF.
    ENDIF.

    " 7 - the recommended role, ready for assign_role once the request is approved: not an SAP template to be
    "     copied, not an assignment valid today (user comparison pending), not one held only through a composite role
    IF payload->candidates IS NOT INITIAL.
      IF NOT ( top-sap_template = abap_true AND top-held_by_peers = abap_false )
         AND NOT line_exists( assignments[ role = top-role active = abap_true ] )
         AND ( top-previously_assigned = abap_false
               OR line_exists( assignments[ role = top-role via_composite = abap_false ] ) ).
        payload->assign_arguments = assign_arguments(
          user   = payload->user
          role   = top-role
          reason = |Missing access found by explain_missing_access: { payload->target_type } { payload->target }| ).
      ENDIF.
    ENDIF.

    result-total_count = lines( payload->candidates ).
    IF lines( payload->candidates ) > ctx->max_rows( ).
      DELETE payload->candidates FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    APPEND `AGR_1251, AGR_1016, AGR_AGRS` TO result-sources.
    APPEND `AGR_USERS` TO result-sources.
    APPEND `USCRAUTHID, USCRAUTH (SUIM critical authorizations)` TO result-sources.
    IF payload->request_critical IS NOT INITIAL.
      APPEND |The requested access itself is classified as critical: { hits_text( payload->request_critical ) }.|
        TO result-warnings.
    ENDIF.
    IF payload->candidates IS INITIAL.
      APPEND |No single role you may display covers all { lines( payload->missing ) } missing checks; | &&
             |a combination of roles or a new role is needed.| TO result-warnings.
    ELSE.
      DATA(best) = payload->candidates[ 1 ].
      IF best-critical IS NOT INITIAL.
        APPEND |The recommended role { best-role } grants further critical authorizations: { hits_text( best-critical ) }.|
          TO result-warnings.
      ENDIF.
      IF best-wildcard = abap_true.
        APPEND |The recommended role { best-role } grants { best-wildcard_fields } with full wildcard (*), | &&
               |far beyond the requested values.| TO result-warnings.
      ENDIF.
      DATA(assign_step) = COND string(
        WHEN payload->assign_arguments IS NOT INITIAL
        THEN |; once approved, with write access (plugin ADMIN): assign_role { payload->assign_arguments }| &&
             |{ COND #( WHEN best-critical IS NOT INITIAL
                        THEN ` (refused for the further critical authorizations unless accept_critical is set)` ) }| ).
      APPEND COND #( WHEN best-previously_assigned = abap_true
                     THEN |Extend or renew the assignment of role { best-role } for { payload->user } via the access request | &&
                          |process{ assign_step }.|
                     WHEN best-sap_template = abap_true AND best-held_by_peers = abap_false
                     THEN |Copy the SAP template role { best-role } to a customer role and request that for { payload->user } | &&
                          |via the access request process.|
                     ELSE |Request role { best-role } for { payload->user } via the access request process{ assign_step }.| )
        TO result-next_steps.
      IF payload->less_critical_option IS NOT INITIAL.
        APPEND |If the further critical authorizations of { best-role } are not acceptable, request the less critical | &&
               |role { payload->less_critical_option } instead (not yet used in the user group| &&
               |{ COND #( WHEN payload->less_critical_option CP 'SAP_*' THEN `; an SAP template role, to be copied first` ) }).|
          TO result-next_steps.
      ENDIF.
    ENDIF.
    IF payload->draft_arguments IS NOT INITIAL.
      DATA(why) = COND string( WHEN payload->candidates IS INITIAL THEN `No existing role fits`
                               WHEN best-critical IS NOT INITIAL
                               THEN |To avoid the further critical authorizations of { best-role }|
                               WHEN best-wildcard = abap_true
                               THEN |To avoid the full wildcard ({ best-wildcard_fields }) of { best-role }|
                               ELSE |Instead of copying the SAP template role { best-role }| ).
      DATA(draft_step) = |{ why }: plan adding only the requested access to the user's role { payload->draft_role } with | &&
                         |draft_role_change { payload->draft_arguments }|.
      " for a wildcard or template role nobody in the user group holds, the precise change comes first
      IF questionable = abap_true.
        INSERT draft_step INTO result-next_steps INDEX 1.
      ELSE.
        APPEND draft_step TO result-next_steps.
      ENDIF.
    ELSEIF payload->candidates IS INITIAL.
      APPEND |No existing role fits and { payload->user } holds no single role to extend: plan a new role, or use | &&
             |draft_role_change on a role of the user group.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD wildcard_fields.
    DATA fields TYPE string_table.
    DATA(values) = zcl_accx_domain_factory=>role_repo( )->get_authorization_values( role ).
    LOOP AT missing INTO DATA(check).
      LOOP AT check-fields INTO DATA(field_value) WHERE field <> 'ACTVT'.
        DATA(name) = |{ check-object }-{ field_value-field }|.
        IF line_exists( values[ object = check-object field = field_value-field low = '*' ] )
           AND NOT line_exists( fields[ table_line = name ] ).
          APPEND name TO fields.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    result = concat_lines_of( table = fields sep = `, ` ).
  ENDMETHOD.

  METHOD own_role_to_extend.
    TYPES: BEGIN OF ty_option,
             sap_template TYPE abap_bool,
             peers        TYPE i,
             role         TYPE agr_name,
           END OF ty_option.
    DATA options TYPE STANDARD TABLE OF ty_option WITH EMPTY KEY.

    CLEAR: role, peers.
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    LOOP AT assignments INTO DATA(assignment) WHERE active = abap_true.
      IF line_exists( options[ role = assignment-role ] )
         OR ctx->guard( )->can_display_role( assignment-role ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(info) = role_repo->get_role_info( assignment-role ).
      IF info-composite = abap_true OR info-generated = abap_false.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( sap_template = xsdbool( assignment-role CP 'SAP_*' )
                      peers        = role_repo->count_holders( role = assignment-role user_group = user_group exclude_user = user )
                      role         = assignment-role ) TO options.
    ENDLOOP.
    SORT options BY sap_template ASCENDING peers DESCENDING role ASCENDING.
    IF options IS NOT INITIAL.
      role  = options[ 1 ]-role.
      peers = options[ 1 ]-peers.
    ENDIF.
  ENDMETHOD.

  METHOD draft_arguments.
    DATA values TYPE string_table.

    result = |\{"role":{ json_string( payload-draft_role ) }|.
    IF payload-target_type = zcl_accx_t_check_user_access=>co_target_type-transaction.
      result = |{ result },"add_transactions":[{ json_string( payload-target ) }]|.
    ELSE.
      LOOP AT payload-missing INTO DATA(missing).
        LOOP AT missing-fields INTO DATA(field_value).
          APPEND json_string( |{ field_value-field }={ field_value-value }| ) TO values.
        ENDLOOP.
      ENDLOOP.
      result = |{ result },"object":{ json_string( payload-target ) },"values":[{ concat_lines_of( table = values sep = `,` ) }]|.
    ENDIF.
    result = |{ result },"for_user":{ json_string( payload-user ) }| &&
             |,"reason":{ json_string( |Missing access found by explain_missing_access: { payload-target_type } { payload-target }| ) }\}|.
  ENDMETHOD.

  METHOD json_string.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD assignment_state.
    CLEAR: previously_assigned, text.
    LOOP AT assignments INTO DATA(assignment) WHERE role = role.
      previously_assigned = abap_true.
      IF assignment-active = abap_true.
        text = `assigned and valid - user comparison (PFUD) or profile generation pending`.
      ELSEIF assignment-valid_to < sy-datum.
        text = |assignment expired on { assignment-valid_to DATE = ISO }|.
      ELSE.
        text = |assignment valid only from { assignment-valid_from DATE = ISO }|.
      ENDIF.
      RETURN.
    ENDLOOP.
    text = `not assigned`.
  ENDMETHOD.

  METHOD extra_critical.
    CLEAR: hits, score.
    LOOP AT rules->evaluate_role( role ) INTO DATA(hit).
      IF line_exists( request_critical[ rule = hit-rule ] ).
        CONTINUE.
      ENDIF.
      APPEND hit TO hits.
      score += SWITCH i( hit-level
                         WHEN zif_accx_critical_rules=>co_level-high   THEN 100
                         WHEN zif_accx_critical_rules=>co_level-medium THEN 10
                         ELSE 1 ).
    ENDLOOP.
  ENDMETHOD.

  METHOD hits_text.
    LOOP AT hits INTO DATA(hit).
      result = |{ result }{ COND #( WHEN result IS NOT INITIAL THEN `; ` ) }{ hit-text } ({ hit-rule }, { hit-level })|.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    DATA(what) = COND string( WHEN <payload>-target_type = zcl_accx_t_check_user_access=>co_target_type-transaction
                              THEN |start transaction { <payload>-target }|
                              ELSE |hold authorization { <payload>-target }| ).
    DATA(logon_note) = COND string( WHEN <payload>-logon_possible = abap_false
                                    THEN | **The user cannot log on** ({ <payload>-logon_issue }).| ).

    IF <payload>-already_granted = abap_true.
      result-summary = |User **{ <payload>-user }** already { COND #( WHEN <payload>-logon_possible = abap_true THEN `may` ELSE `would be authorized to` ) } | &&
                       |{ what } - no authorization is missing.{ logon_note }|.
      RETURN.
    ENDIF.

    result-summary = |User **{ <payload>-user }** may not { what }.{ logon_note } Missing:|.
    LOOP AT <payload>-missing INTO DATA(missing).
      result-summary = |{ result-summary }\n- { missing-object } ({ missing-condition }): { missing-outcome }|.
    ENDLOOP.
    IF <payload>-request_critical IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**The requested access itself is critical:** { hits_text( <payload>-request_critical ) }.|.
    ENDIF.

    IF <payload>-candidates IS INITIAL.
      result-summary = |{ result-summary }\n\nNo role you may display covers all missing checks.|.
    ELSE.
      DATA(best) = <payload>-candidates[ 1 ].
      DATA(group) = COND string( WHEN <payload>-user_group IS INITIAL THEN `(none)` ELSE <payload>-user_group ).
      result-summary = |{ result-summary }\n\n**Recommended:** role **{ best-role }**| &&
                       |{ COND #( WHEN best-description IS NOT INITIAL THEN | ({ best-description })| ) }| &&
                       |{ COND #( WHEN best-previously_assigned = abap_true THEN | - { best-assignment }, renewing it closes the gap| ) }| &&
                       |; held by { best-peers_with_role } of { <payload>-peer_group_size } other users in user group { group }| &&
                       |, { best-object_count } authorization objects| &&
                       |{ COND #( WHEN best-broad = abap_true THEN `, grants all transactions (S_TCODE *)` ) }| &&
                       |{ COND #( WHEN best-sap_template = abap_true THEN `, SAP template role` ) }| &&
                       |{ COND #( WHEN best-composite_parents IS NOT INITIAL THEN |, also contained in { best-composite_parents }| ) }.|.
      IF best-wildcard = abap_true.
        result-summary = |{ result-summary } **Grants { best-wildcard_fields } with full wildcard (*)**, | &&
                         |far beyond the requested values.|.
      ENDIF.
      IF best-critical IS NOT INITIAL.
        result-summary = |{ result-summary } **Also grants critical authorizations:** { hits_text( best-critical ) }.|.
      ENDIF.
      IF <payload>-less_critical_option IS NOT INITIAL.
        result-summary = |{ result-summary }\n\n**Less critical alternative:** role **{ <payload>-less_critical_option }**| &&
                         | (not held by colleagues of the user group| &&
                         |{ COND #( WHEN <payload>-less_critical_option CP 'SAP_*' THEN `; SAP template role, to be copied first` ) }).|.
      ENDIF.
      IF lines( <payload>-candidates ) > 1.
        result-summary = |{ result-summary }\n\nOther candidates:|.
        LOOP AT <payload>-candidates INTO DATA(other) FROM 2 TO 6.
          result-summary = |{ result-summary }\n- { other-role }: { other-peers_with_role } peers, { other-object_count } objects| &&
                           |{ COND #( WHEN other-broad = abap_true THEN `, broad (S_TCODE *)` ) }| &&
                           |{ COND #( WHEN other-wildcard = abap_true THEN |, wildcard: { other-wildcard_fields }| ) }| &&
                           |{ COND #( WHEN other-critical IS NOT INITIAL THEN |, critical: { hits_text( other-critical ) }| ELSE `, no further critical authorizations` ) }| &&
                           |{ COND #( WHEN other-previously_assigned = abap_true THEN |, { other-assignment }| ) }|.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF <payload>-draft_role IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Alternative: change a role instead of assigning one.** Extend the user's role | &&
                       |**{ <payload>-draft_role }** (held by { <payload>-draft_role_peers } | &&
                       |{ COND #( WHEN <payload>-draft_role_peers = 1 THEN `colleague` ELSE `colleagues` ) } in the user group) by | &&
                       |exactly the requested access; draft_role_change shows the values, critical authorizations and all users | &&
                       |affected before anything is changed.|.
    ENDIF.

    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\n{ result-total_count } candidates in total, list truncated.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } further roles would also fit but you are not authorized to display them.|.
    ENDIF.
  ENDMETHOD.

  METHOD assign_arguments.
    result = |\{"user":{ json_string( user ) },"role":{ json_string( role ) },"reason":{ json_string( reason ) }\}|.
  ENDMETHOD.
ENDCLASS.
