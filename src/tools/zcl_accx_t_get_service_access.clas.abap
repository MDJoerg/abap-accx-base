"! <p class="shorttext synchronized">Access Explorer tool: get_service_access</p>
"! Access view of one OData service: registration and activation in the
"! gateway, system alias routing, ICF node, the S_SERVICE values (hashes of the
"! gateway and backend service), their SU24 proposals and the roles granting
"! them with their users. Embedded deployment (gateway in the same system).
CLASS zcl_accx_t_get_service_access DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `get_service_access`.

    TYPES: BEGIN OF ty_hash,
             "! IWSG gateway service, IWSV backend service, G4BA OData V4 service group
             object          TYPE string,
             "! S_SERVICE-SRV_NAME (SRV_TYPE HT)
             hash            TYPE string,
             obj_name        TYPE string,
             "! SU24: objects checked by the service, values proposed as OBJECT FIELD=VALUE
             checked_objects TYPE string_table,
             proposals       TYPE string_table,
           END OF ty_hash,
           ty_hashes TYPE STANDARD TABLE OF ty_hash WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role,
             role           TYPE string,
             "! users holding the role today (directly or through a composite role)
             assigned_users TYPE i,
             "! hashes the role grants
             hashes         TYPE string_table,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             service       TYPE string,
             version       TYPE string,
             odata_version TYPE string,
             url           TYPE string,
             identifier    TYPE string,
             registered    TYPE abap_bool,
             active        TYPE abap_bool,
             "! system aliases (empty = local)
             aliases       TYPE string_table,
             "! yes, no or unknown
             icf_node      TYPE string,
             hashes        TYPE ty_hashes,
             "! roles granting S_SERVICE for one of the hashes, most users first
             roles         TYPE ty_roles,
           END OF ty_payload.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

ENDCLASS.

CLASS zcl_accx_t_get_service_access IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Get service access`
      description = |Shows the access side of one OData service: whether it is registered and active in the gateway | &&
                    |(/IWFND/MAINT_SERVICE), its system aliases, whether the ICF node /sap/opu/odata (or odata4) is | &&
                    |active, the S_SERVICE values a user needs (hashes of the gateway and the backend service, SRV_TYPE | &&
                    |HT), the SU24 proposals of these hashes and the roles granting them with the number of users | &&
                    |holding them today. Give the service as /NAMESPACE/NAME (OData V2, e.g. /UI2/PAGE_BUILDER_PERS) | &&
                    |with an optional version, or as its /sap/opu/... URL (also V4). Typical questions: "who may call | &&
                    |service X", "which role do I need for X", "why does an app get 403 on its service". For one | &&
                    |user use diagnose_fiori_app_access or check_user_access.|
      group       = zif_accx_types=>co_group-data
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_GET_SERVICE_ACCESS\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `service`
                                      description = |OData service: /NAMESPACE/NAME or NAME (namespace SAP) for V2, or the | &&
                                                    |service URL /sap/opu/odata/... or /sap/opu/odata4/...|
                                      required    = abap_true
                                      maximum     = 255 ) )
                             ( param( name        = `version`
                                      description = `Service version for V2 names (default 0001).`
                                      maximum     = 4 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(name)    = condense( args->get_string( `service` ) ).
    DATA(version) = condense( args->get_string( `version` ) ).
    DATA(role_repo) = zcl_accx_domain_factory=>role_repo( ).
    DATA(proposal_source) = zcl_accx_domain_factory=>proposal_source( ).

    DATA(service) = zcl_accx_domain_factory=>fiori_repo( )->get_service( name = name version = version ).
    IF service-name IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |"{ name }" is neither an OData service name nor a /sap/opu/odata URL.| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( service       = service-name
                                    version       = service-version
                                    odata_version = service-odata_version
                                    url           = service-url
                                    identifier    = service-identifier
                                    registered    = service-registered
                                    active        = service-active
                                    aliases       = service-aliases
                                    icf_node      = SWITCH #( service-icf_active WHEN abap_true THEN `yes`
                                                                                 WHEN abap_false THEN `no`
                                                                                 ELSE `unknown` ) ).
    result-data = payload.

    LOOP AT service-hashes INTO DATA(hash).
      DATA(entry) = VALUE ty_hash( object = hash-object hash = hash-hash obj_name = hash-obj_name ).
      DATA(proposals) = proposal_source->get_for_service( hash-hash ).
      entry-checked_objects = VALUE #( FOR o IN proposals-objects ( |{ o-object }{ COND #( WHEN o-proposed = abap_false THEN ` (check only)` ) }| ) ).
      entry-proposals = VALUE #( FOR p IN proposals-values
                                 ( |{ p-object } { p-field }={ COND #( WHEN p-low IS INITIAL THEN `(open)` ELSE p-low ) }| &&
                                   |{ COND #( WHEN p-high IS NOT INITIAL THEN |-{ p-high }| ) }| ) ).
      APPEND entry TO payload->hashes.

      " roles allowing S_SERVICE for the hash (patterns and ranges evaluated)
      LOOP AT role_repo->find_roles_granting( VALUE #( object = 'S_SERVICE'
                                                       fields = VALUE #( ( field = 'SRV_NAME' value = hash-hash )
                                                                         ( field = 'SRV_TYPE' value = `HT` ) ) ) ) INTO DATA(role).
        READ TABLE payload->roles ASSIGNING FIELD-SYMBOL(<role>) WITH KEY role = CONV string( role ).
        IF sy-subrc <> 0.
          IF ctx->guard( )->can_display_role( role ) = abap_false.
            result-hidden_by_authorization += 1.
            CONTINUE.
          ENDIF.
          APPEND VALUE #( role = role ) TO payload->roles ASSIGNING <role>.
        ENDIF.
        APPEND CONV string( hash-hash ) TO <role>-hashes.
      ENDLOOP.
    ENDLOOP.

    DATA(counts) = role_repo->count_assigned_users( VALUE #( FOR r IN payload->roles ( CONV #( r-role ) ) ) ).
    LOOP AT payload->roles ASSIGNING <role>.
      <role>-assigned_users = VALUE #( counts[ role = CONV agr_name( <role>-role ) ]-users OPTIONAL ).
    ENDLOOP.
    SORT payload->roles BY assigned_users DESCENDING role ASCENDING.
    result-total_count = lines( payload->roles ).
    IF lines( payload->roles ) > ctx->max_rows( ).
      DELETE payload->roles FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    result-sources = VALUE #( ( `/IWFND/I_MED_SRH, /IWFND/C_MGDEAM (gateway registration, system aliases)` )
                              ( `ICFSERVICE, ICFSERVLOC (ICF node)` ) ( `USOBHASH (S_SERVICE hashes)` )
                              ( `USOBX_C, USOBT_C (SU24 proposals)` ) ( `AGR_1251, AGR_USERS (roles and users)` ) ).
    IF service-odata_version = `2.0` AND service-registered = abap_false.
      APPEND |{ service-name } (version { service-version }) is not registered in the gateway; register it in /IWFND/MAINT_SERVICE.|
        TO result-warnings.
    ELSEIF service-odata_version = `2.0` AND service-active = abap_false.
      APPEND |{ service-name } is registered but not active; activate it in /IWFND/MAINT_SERVICE.| TO result-warnings.
    ENDIF.
    IF service-icf_active = abap_false.
      APPEND |The ICF node of the OData protocol is inactive (SICF); no OData service of this protocol can be called.| TO result-warnings.
    ENDIF.
    IF service-odata_version = `4.0`.
      APPEND `OData V4: the publication of the service group is not checked (/IWFND/V4_ADMIN).` TO result-warnings.
    ENDIF.
    IF service-hashes IS INITIAL.
      APPEND |No S_SERVICE hash found for { service-name }: the service was never added to a role menu or SU24 (USOBHASH).|
        TO result-warnings.
    ENDIF.

    IF payload->roles IS INITIAL AND service-hashes IS NOT INITIAL.
      APPEND |No role grants the service. Add it to a role with draft_role_change (object S_SERVICE, values | &&
             |{ concat_lines_of( sep = `, ` table = VALUE string_table( FOR h IN service-hashes ( |SRV_NAME={ h-hash }| ) ) ) }, | &&
             |SRV_TYPE=HT) or add a launchpad catalog with an app of the service.| TO result-next_steps.
    ELSEIF payload->roles IS NOT INITIAL.
      APPEND |Use find_users with role { payload->roles[ 1 ]-role } to see who holds it, or check_user_access for one user.|
        TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    result-summary = |OData service **{ <payload>-service }** (version { <payload>-version }, OData { <payload>-odata_version }): | &&
                     |{ COND #( WHEN <payload>-odata_version = `4.0` THEN `gateway publication not checked`
                                WHEN <payload>-active = abap_true THEN `registered and active`
                                WHEN <payload>-registered = abap_true THEN `registered, **not active**`
                                ELSE `**not registered**` ) }| &&
                     |{ COND #( WHEN <payload>-aliases IS NOT INITIAL THEN |, system alias { concat_lines_of( table = <payload>-aliases sep = `, ` ) }| ) }| &&
                     |, ICF node { <payload>-icf_node }.|.
    IF <payload>-hashes IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**S_SERVICE values** (SRV_TYPE HT):|.
      LOOP AT <payload>-hashes INTO DATA(hash).
        result-summary = |{ result-summary }\n- { hash-hash } ({ hash-object } { hash-obj_name })| &&
                         |{ COND #( WHEN hash-proposals IS NOT INITIAL THEN |; SU24 proposes { concat_lines_of( table = hash-proposals sep = `, ` ) }|
                                    WHEN hash-checked_objects IS NOT INITIAL THEN |; SU24 checks { concat_lines_of( table = hash-checked_objects sep = `, ` ) }| ) }|.
      ENDLOOP.
    ENDIF.
    IF <payload>-roles IS INITIAL.
      result-summary = |{ result-summary }\n\nNo role grants the service.|.
    ELSE.
      result-summary = |{ result-summary }\n\n**{ result-total_count }** { COND #( WHEN result-total_count = 1 THEN `role grants` ELSE `roles grant` ) } | &&
                       |the service, most used first:|.
      LOOP AT <payload>-roles INTO DATA(role) TO 15.
        result-summary = |{ result-summary }\n- { role-role }: { role-assigned_users } { COND #( WHEN role-assigned_users = 1 THEN `user` ELSE `users` ) }| &&
                         |{ COND #( WHEN lines( role-hashes ) < lines( <payload>-hashes ) THEN | (only { concat_lines_of( table = role-hashes sep = `, ` ) })| ) }|.
      ENDLOOP.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } roles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

