"! <p class="shorttext synchronized">Access Explorer tool: run_critical_access_check</p>
"! Runs the SUIM check for critical authorizations and critical combinations
"! (RSUSR008_009_NEW) for users or roles, per SUIM variant, and condenses the
"! result per rule. For users it names the roles and profiles each finding
"! comes from (ZIF_ACCX_ACCESS_ORIGIN).
CLASS zcl_accx_t_run_critical_check DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_finding,
             kind      TYPE string,
             rule      TYPE string,
             text      TYPE string,
             level     TYPE string,
             subject   TYPE string,
             "! roles only: single or composite
             role_type TYPE string,
             variants  TYPE string,
             "! users only: roles and profiles granting the rule (per component for combinations)
             origin    TYPE string,
           END OF ty_finding,
           ty_findings TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

    TYPES: BEGIN OF ty_rule,
             kind         TYPE string,
             rule         TYPE string,
             text         TYPE string,
             level        TYPE string,
             holder_count TYPE i,
             "! first holders, comma separated
             holders      TYPE string,
             "! users only: roles and profiles granting the rule with number of holders, most frequent first
             sources      TYPE string,
           END OF ty_rule,
           ty_rules TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             scope     TYPE string,
             variants  TYPE string_table,
             rules     TYPE ty_rules,
             findings  TYPE ty_findings,
           END OF ty_payload.

    CONSTANTS co_name TYPE string VALUE `run_critical_access_check`.

    CONSTANTS: BEGIN OF co_scope,
                 users TYPE string VALUE `users`,
                 roles TYPE string VALUE `roles`,
               END OF co_scope.

    CONSTANTS co_holders_shown TYPE i VALUE 10.
    CONSTANTS co_sources_shown TYPE i VALUE 5.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_source_count,
             kind   TYPE string,
             rule   TYPE string,
             source TYPE string,
             count  TYPE i,
           END OF ty_source_count,
           ty_source_counts TYPE SORTED TABLE OF ty_source_count WITH UNIQUE KEY kind rule source.

    METHODS level
      IMPORTING !color        TYPE c
      RETURNING VALUE(result) TYPE string.

    METHODS level_rank
      IMPORTING !level        TYPE string
      RETURNING VALUE(result) TYPE i.

    "! Single value or pattern (*) as range line
    METHODS range_line
      IMPORTING !value        TYPE string
      EXPORTING !sign         TYPE c
                !option       TYPE c
                !low          TYPE csequence.

    "! Name roles and profiles of the shown user findings and count them per rule
    METHODS add_origins
      IMPORTING !ctx     TYPE REF TO zif_accx_context
                !payload TYPE REF TO ty_payload.

    "! Source as shown: role X (via composite role Y), profile SAP_ALL; respects display authorization
    METHODS source_label
      IMPORTING !ctx          TYPE REF TO zif_accx_context
                !origin       TYPE zif_accx_access_origin=>ty_origin
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_run_critical_check IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Run critical access check`
      description = |Finds users or roles with critical authorizations and critical combinations of authorizations, | &&
                    |exactly as SUIM report RSUSR008_009_NEW does, based on the SUIM variants maintained in the system. | &&
                    |Without a variant all variants are evaluated. The result is condensed per rule (holders, criticality | &&
                    |from the SUIM color) and lists every finding. For users each finding names the roles and profiles | &&
                    |it comes from. SUIM leaves out users and roles you may not display, so | &&
                    |the result reflects your own display authorization. Filter users by user ID or user group, roles by | &&
                    |role name; patterns with * are allowed.|
      group       = zif_accx_types=>co_group-audit
      read_only   = abap_true
      idempotent  = abap_true
      long_running = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_RUN_CRITICAL_CHECK\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `scope`
                                      description = `Check users (default) or roles.`
                                      enum        = VALUE #( ( co_scope-users ) ( co_scope-roles ) ) ) )
                             ( param( name        = `variant`
                                      description = |SUIM variant of critical authorizations or combinations, e.g. SAP_RSUSR009. | &&
                                                    |Default: all variants.|
                                      maximum     = 30 ) )
                             ( param( name        = `user`
                                      description = `Scope users: user ID or pattern, e.g. ACCX*.`
                                      maximum     = 12 ) )
                             ( param( name        = `user_group`
                                      description = `Scope users: user group (authorization check group), e.g. SUPER.`
                                      maximum     = 12 ) )
                             ( param( name        = `role`
                                      description = `Scope roles: role name or pattern, e.g. Z*.`
                                      maximum     = 30 ) )
                             ( param( name        = `valid_users_only`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = `Scope users: only users valid today (default true).` ) )
                             ( param( name        = `with_origin`
                                      kind        = zif_accx_types=>co_kind-boolean
                                      description = |Scope users: name the roles and profiles each finding comes from | &&
                                                    |(default true; only for the findings returned within max_rows).| ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA users       TYPE susr_t_range_4_xubname.
    DATA user_groups TYPE susr_t_sel_opt_group.
    DATA roles       TYPE susr_t_range_4_agr_name.
    DATA run         TYPE zif_accx_suim_gateway=>ty_result.
    DATA visible     TYPE abap_bool.

    DATA(scope)       = COND string( WHEN args->has( `scope` ) THEN args->get_string( `scope` ) ELSE co_scope-users ).
    DATA(variant)     = to_upper( condense( args->get_string( `variant` ) ) ).
    DATA(user)        = to_upper( condense( args->get_string( `user` ) ) ).
    DATA(user_group)  = to_upper( condense( args->get_string( `user_group` ) ) ).
    DATA(role)        = to_upper( condense( args->get_string( `role` ) ) ).
    DATA(valid_only)  = args->get_boolean( name = `valid_users_only` default = abap_true ).
    DATA(with_origin) = args->get_boolean( name = `with_origin` default = abap_true ).

    IF scope = co_scope-roles AND ( user IS NOT INITIAL OR user_group IS NOT INITIAL ).
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `user and user_group filter users; use role with scope roles.` ).
    ENDIF.
    IF scope = co_scope-users AND role IS NOT INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = `role filters roles; set scope to roles.` ).
    ENDIF.

    DATA(gateway) = zcl_accx_domain_factory=>suim_gateway( ).
    DATA(variants) = gateway->get_variants( ).
    DELETE variants WHERE rule_count = 0.
    IF variant IS NOT INITIAL.
      DATA(available) = concat_lines_of( table = VALUE string_table( FOR v IN variants ( v-name ) ) sep = `, ` ).
      DELETE variants WHERE name <> variant.
      IF variants IS INITIAL.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                            message = |SUIM variant { variant } does not exist or is empty. Available: { available }.| ).
      ENDIF.
    ENDIF.
    IF variants IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                          message = `No SUIM variants of critical authorizations or combinations are maintained.` ).
    ENDIF.

    IF user IS NOT INITIAL.
      APPEND INITIAL LINE TO users ASSIGNING FIELD-SYMBOL(<user>).
      range_line( EXPORTING value = user IMPORTING sign = <user>-sign option = <user>-option low = <user>-low ).
    ENDIF.
    IF user_group IS NOT INITIAL.
      APPEND INITIAL LINE TO user_groups ASSIGNING FIELD-SYMBOL(<group>).
      range_line( EXPORTING value = user_group IMPORTING sign = <group>-sign option = <group>-option low = <group>-low ).
    ENDIF.
    IF role IS NOT INITIAL.
      APPEND INITIAL LINE TO roles ASSIGNING FIELD-SYMBOL(<role>).
      range_line( EXPORTING value = role IMPORTING sign = <role>-sign option = <role>-option low = <role>-low ).
    ENDIF.

    DATA(payload) = NEW ty_payload( scope = scope ).
    result-data = payload.
    DATA(findings) = VALUE ty_findings( ).

    LOOP AT variants INTO DATA(current).
      APPEND |{ current-name } ({ current-kind }s{ COND #( WHEN current-text IS NOT INITIAL THEN |: { current-text }| ) })|
        TO payload->variants.
      IF scope = co_scope-roles.
        run = gateway->critical_roles( kind = current-kind variant = current-name roles = roles ).
      ELSE.
        run = gateway->critical_users( kind        = current-kind
                                       variant     = current-name
                                       users       = users
                                       user_groups = user_groups
                                       valid_only  = valid_only ).
      ENDIF.
      LOOP AT run-messages INTO DATA(message).
        APPEND |{ current-name }: { message }| TO result-warnings.
      ENDLOOP.

      LOOP AT run-findings INTO DATA(finding).
        ASSIGN findings[ kind = finding-kind rule = finding-rule subject = finding-subject ] TO FIELD-SYMBOL(<known>).
        IF sy-subrc = 0.
          " same rule in several variants
          IF <known>-variants NS current-name.
            <known>-variants = |{ <known>-variants }, { current-name }|.
          ENDIF.
          CONTINUE.
        ENDIF.
        IF scope = co_scope-roles.
          visible = ctx->guard( )->can_display_role( CONV #( finding-subject ) ).
        ELSE.
          visible = ctx->guard( )->can_display_user( CONV #( finding-subject ) ).
        ENDIF.
        IF visible = abap_false.
          result-hidden_by_authorization += 1.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( kind      = finding-kind
                        rule      = finding-rule
                        text      = finding-text
                        level     = level( finding-color )
                        subject   = finding-subject
                        role_type = SWITCH #( finding-role_type WHEN 'C' THEN `composite` WHEN 'S' THEN `single` )
                        variants  = current-name ) TO findings.
      ENDLOOP.
    ENDLOOP.

    " one overview line per rule
    SORT findings BY kind rule subject.
    DATA(rules) = VALUE ty_rules( ).
    LOOP AT findings INTO DATA(row) GROUP BY ( kind = row-kind rule = row-rule ) INTO DATA(rule_group).
      DATA(summary) = VALUE ty_rule( ).
      LOOP AT GROUP rule_group INTO DATA(holder).
        summary = VALUE #( BASE summary kind = holder-kind rule = holder-rule text = holder-text level = holder-level ).
        summary-holder_count += 1.
        IF summary-holder_count <= co_holders_shown.
          summary-holders = |{ summary-holders }{ COND #( WHEN summary-holders IS NOT INITIAL THEN `, ` ) }{ holder-subject }|.
        ENDIF.
      ENDLOOP.
      APPEND summary TO rules.
    ENDLOOP.

    " most critical first: high, medium, low; within a level by number of holders
    SORT rules BY holder_count DESCENDING rule ASCENDING.
    DO 3 TIMES.
      DATA(rank) = sy-index.
      LOOP AT rules INTO DATA(ranked) WHERE level IS NOT INITIAL.
        IF level_rank( ranked-level ) = rank.
          APPEND ranked TO payload->rules.
          APPEND LINES OF VALUE ty_findings( FOR f IN findings WHERE ( kind = ranked-kind AND rule = ranked-rule ) ( f ) )
            TO payload->findings.
        ENDIF.
      ENDLOOP.
    ENDDO.

    result-total_count = lines( payload->findings ).
    IF lines( payload->findings ) > ctx->max_rows( ).
      DELETE payload->findings FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    IF scope = co_scope-users AND with_origin = abap_true.
      add_origins( ctx = ctx payload = payload ).
    ENDIF.

    result-sources = VALUE #( ( |{ COND #( WHEN scope = co_scope-roles THEN `SUSR_API_RSUSR008_009_NEW_ROLE`
                                            ELSE `SUSR_SUIM_API_RSUSR008_009_NEW` ) } (SUIM RSUSR008_009_NEW)| )
                              ( `USRVAR, USRVARCOM, USCRAUTHID, USRCOMB` ) ).
    IF scope = co_scope-users AND with_origin = abap_true.
      APPEND `UST04, UST10C, UST10S, UST12, AGR_1016, AGR_USERS, AGR_AGRS, USREFUS (origin)` TO result-sources.
    ENDIF.
    IF payload->rules IS NOT INITIAL.
      DATA(top) = payload->rules[ 1 ].
      IF scope = co_scope-roles.
        APPEND |Check in PFCG whether { top-text } ({ top-rule }) is intended in the listed roles; use | &&
               |scope users to see who holds it.| TO result-next_steps.
      ELSEIF top-sources IS NOT INITIAL.
        SPLIT top-sources AT `, ` INTO DATA(top_source) DATA(other_sources) ##NEEDED.
        APPEND |{ top-text } ({ top-rule }) comes mostly from { top_source }: check whether it is intended there, | &&
               |or remove the assignment for users who do not need it.| TO result-next_steps.
      ELSE.
        APPEND |Use get_user_profile for the listed users to see which roles or profiles grant | &&
               |{ top-text } ({ top-rule }).| TO result-next_steps.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD add_origins.
    TYPES ty_ranking TYPE STANDARD TABLE OF ty_source_count WITH EMPTY KEY.
    DATA counts  TYPE ty_source_counts.
    DATA labels  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
    DATA origins TYPE zif_accx_access_origin=>ty_origins.

    DATA(tracer) = zcl_accx_domain_factory=>access_origin( ).
    LOOP AT payload->findings ASSIGNING FIELD-SYMBOL(<finding>).
      DATA(combination) = xsdbool( <finding>-kind = zif_accx_suim_gateway=>co_kind-combination ).
      IF combination = abap_true.
        origins = tracer->trace_combination( user = CONV #( <finding>-subject ) combination = CONV #( <finding>-rule ) ).
      ELSE.
        origins = tracer->trace_rule( user = CONV #( <finding>-subject ) rule = CONV #( <finding>-rule ) ).
      ENDIF.
      IF origins IS INITIAL.
        <finding>-origin = `no single role or profile found (user master changed since the check?)`.
        CONTINUE.
      ENDIF.

      CLEAR labels.
      LOOP AT origins INTO DATA(origin) GROUP BY origin-rule INTO DATA(component).
        DATA(listed) = ``.
        LOOP AT GROUP component INTO DATA(source).
          DATA(label) = source_label( ctx = ctx origin = source ).
          listed = |{ listed }{ COND #( WHEN listed IS NOT INITIAL THEN `, ` ) }{ label }| &&
                   |{ COND #( WHEN source-via IS NOT INITIAL THEN | (via { source-via })| ) }| &&
                   |{ COND #( WHEN source-complete = abap_false THEN ` (partly)` ) }|.
          INSERT label INTO TABLE labels.
        ENDLOOP.
        <finding>-origin = |{ <finding>-origin }{ COND #( WHEN <finding>-origin IS NOT INITIAL THEN `; ` ) }| &&
                           |{ COND #( WHEN combination = abap_true THEN |{ component }: | ) }{ listed }|.
      ENDLOOP.

      LOOP AT labels INTO label.
        ASSIGN counts[ kind = <finding>-kind rule = <finding>-rule source = label ] TO FIELD-SYMBOL(<count>).
        IF sy-subrc <> 0.
          INSERT VALUE #( kind = <finding>-kind rule = <finding>-rule source = label ) INTO TABLE counts ASSIGNING <count>.
        ENDIF.
        <count>-count += 1.
      ENDLOOP.
    ENDLOOP.

    LOOP AT payload->rules ASSIGNING FIELD-SYMBOL(<rule>).
      DATA(ranking) = VALUE ty_ranking( FOR c IN counts WHERE ( kind = <rule>-kind AND rule = <rule>-rule ) ( c ) ).
      SORT ranking BY count DESCENDING source ASCENDING.
      LOOP AT ranking INTO DATA(entry) FROM 1 TO co_sources_shown.
        <rule>-sources = |{ <rule>-sources }{ COND #( WHEN <rule>-sources IS NOT INITIAL THEN `, ` ) }| &&
                         |{ entry-source } ({ entry-count })|.
      ENDLOOP.
      IF lines( ranking ) > co_sources_shown.
        <rule>-sources = |{ <rule>-sources }, ...|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD source_label.
    IF origin-source_type = zif_accx_access_origin=>co_source-role.
      result = COND #( WHEN ctx->guard( )->can_display_role( CONV #( origin-source ) ) = abap_true
                       THEN |role { origin-source }|
                       ELSE `role (not displayable)` ).
    ELSE.
      result = COND #( WHEN ctx->guard( )->can_display_profile( origin-profile ) = abap_true
                       THEN |profile { origin-source }|
                       ELSE `profile (not displayable)` ).
    ENDIF.
  ENDMETHOD.

  METHOD level.
    result = SWITCH #( color
                       WHEN '6' THEN zif_accx_critical_rules=>co_level-high
                       WHEN '3' THEN zif_accx_critical_rules=>co_level-medium
                       ELSE zif_accx_critical_rules=>co_level-low ).
  ENDMETHOD.

  METHOD level_rank.
    result = SWITCH #( level
                       WHEN zif_accx_critical_rules=>co_level-high   THEN 1
                       WHEN zif_accx_critical_rules=>co_level-medium THEN 2
                       ELSE 3 ).
  ENDMETHOD.

  METHOD range_line.
    sign   = 'I'.
    option = COND #( WHEN value CA '*' THEN 'CP' ELSE 'EQ' ).
    low    = value.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    DATA(what) = COND string( WHEN <payload>-scope = co_scope-roles THEN `role` ELSE `user` ).
    IF <payload>-rules IS INITIAL.
      result-summary = |No { what }s with critical authorizations or combinations found.|.
    ELSE.
      result-summary = |**{ lines( <payload>-rules ) }** critical { COND #( WHEN lines( <payload>-rules ) = 1 THEN `rule` ELSE `rules` ) } | &&
                       |met by { what }s ({ result-total_count } { COND #( WHEN result-total_count = 1 THEN `finding` ELSE `findings` ) }), | &&
                       |most critical first:|.
      LOOP AT <payload>-rules INTO DATA(rule).
        result-summary = |{ result-summary }\n- **{ rule-text }** ({ rule-rule }, { rule-kind }, { rule-level }): | &&
                         |{ rule-holder_count } { what }{ COND #( WHEN rule-holder_count <> 1 THEN `s` ) } - { rule-holders }| &&
                         |{ COND #( WHEN rule-holder_count > co_holders_shown THEN `, ...` ) }| &&
                         |{ COND #( WHEN rule-sources IS NOT INITIAL THEN |; granted by { rule-sources }| ) }|.
      ENDLOOP.
    ENDIF.
    result-summary = |{ result-summary }\n\nVariants evaluated: { concat_lines_of( table = <payload>-variants sep = `; ` ) }.|.
    IF result-truncated = abap_true.
      result-summary = |{ result-summary }\n\nFinding list truncated to max_rows; the rule overview above is complete| &&
                       |{ COND #( WHEN <payload>-scope = co_scope-users THEN `, its sources count the listed findings only` ) }.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } findings hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
