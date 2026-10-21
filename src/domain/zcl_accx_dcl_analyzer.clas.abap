"! <p class="shorttext synchronized">Access Explorer: DCL source analysis</p>
"! Reads the grants of a DCL role source (entity, PFCG aspects with mapped elements, fields
"! and fixed values, inherited conditions, user aspect) and decides whether a CDS entity is
"! effectively protected for SELECT. A text analysis, not the ACM runtime: conditions are
"! listed, not evaluated.
CLASS zcl_accx_dcl_analyzer DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS: BEGIN OF co_kind,
                 "! aspect pfcg_auth( object, fields, fixed values )
                 pfcg    TYPE string VALUE `pfcg`,
                 "! inheriting conditions from entity or role
                 inherit TYPE string VALUE `inherit`,
                 "! aspect user
                 user    TYPE string VALUE `user`,
               END OF co_kind.

    " protection status of an entity, unprotected ones first
    CONSTANTS: BEGIN OF co_status,
                 "! no DCL role while the annotation lets the entity be read without one
                 no_role         TYPE string VALUE `no_role`,
                 "! AccessControl.authorizationCheck: #NOT_ALLOWED - roles are ignored
                 not_allowed     TYPE string VALUE `not_allowed`,
                 "! roles grant without any condition
                 full_access     TYPE string VALUE `full_access`,
                 "! roles only filter by fixed values, the same rows for every user
                 static_filter   TYPE string VALUE `static_filter`,
                 "! custom entity: DCL does not apply, the query class must check
                 custom          TYPE string VALUE `custom`,
                 "! roles with conditions depending on the user's authorizations
                 protected       TYPE string VALUE `protected`,
                 "! #PRIVILEGED_ONLY: only privileged access
                 privileged_only TYPE string VALUE `privileged_only`,
                 "! #MANDATORY without role: every read fails
                 no_access       TYPE string VALUE `no_access`,
                 "! abstract entity: no data
                 abstract        TYPE string VALUE `abstract`,
               END OF co_status.

    TYPES: BEGIN OF ty_condition,
             kind     TYPE string,
             "! pfcg: elements of the entity mapped to the fields (empty = pure authorization check)
             elements TYPE string,
             "! pfcg: authorization object; inherit: entity or role
             object   TYPE string,
             fields   TYPE string_table,
             "! pfcg: fixed values, e.g. ACTVT = '03'
             filters  TYPE string_table,
           END OF ty_condition,
           ty_conditions TYPE STANDARD TABLE OF ty_condition WITH EMPTY KEY.

    TYPES: BEGIN OF ty_grant,
             entity        TYPE string,
             "! grant select without where clause
             unconditional TYPE abap_bool,
             "! where clause without aspects, the same rows for every user
             static_filter TYPE abap_bool,
             conditions    TYPE ty_conditions,
           END OF ty_grant,
           ty_grants TYPE STANDARD TABLE OF ty_grant WITH EMPTY KEY.

    TYPES: BEGIN OF ty_protection,
             status    TYPE string,
             protected TYPE abap_bool,
             reason    TYPE string,
           END OF ty_protection.

    "! Grants of a DCL source (comments removed, entity names upper case)
    CLASS-METHODS parse
      IMPORTING !source       TYPE string
      RETURNING VALUE(result) TYPE ty_grants.

    "! Protection of an entity from its annotation, kind and the grants of all its roles
    CLASS-METHODS protection
      IMPORTING !entity       TYPE zif_accx_cds_access=>ty_entity
                !grants       TYPE ty_grants
      RETURNING VALUE(result) TYPE ty_protection.

    "! Statuses in order of severity, unprotected first
    CLASS-METHODS status_order
      RETURNING VALUE(result) TYPE string_table.

    "! PFCG conditions with the same object, fields and fixed values merged; their elements are listed together
    CLASS-METHODS merge
      IMPORTING !conditions   TYPE ty_conditions
      RETURNING VALUE(result) TYPE ty_conditions.

    "! One line per condition, e.g. "B_BUPA_GRP: AuthorizationGroup = BEGRU (ACTVT = '03')"
    CLASS-METHODS condition_text
      IMPORTING !condition    TYPE ty_condition
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS conditions
      IMPORTING !body         TYPE string
      RETURNING VALUE(result) TYPE ty_conditions.

    CLASS-METHODS group
      IMPORTING !text         TYPE string
                !match        TYPE match_result
                !index        TYPE i
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_dcl_analyzer IMPLEMENTATION.

  METHOD parse.
    DATA(text) = source.
    REPLACE ALL OCCURRENCES OF PCRE `/\*[\s\S]*?\*/` IN text WITH ``.
    REPLACE ALL OCCURRENCES OF PCRE `//[^\n]*` IN text WITH ``.
    FIND ALL OCCURRENCES OF PCRE `(?i)grant\s+select\s+on\s+([\w/]+)([\s\S]*?);` IN text RESULTS DATA(matches).
    LOOP AT matches INTO DATA(match).
      DATA(body) = group( text = text match = match index = 2 ).
      DATA(grant) = VALUE ty_grant( entity     = to_upper( group( text = text match = match index = 1 ) )
                                    conditions = conditions( body ) ).
      DATA(has_where) = xsdbool( contains( val = body pcre = `(?i)\bwhere\b` ) ).
      grant-unconditional = xsdbool( has_where = abap_false AND grant-conditions IS INITIAL ).
      grant-static_filter = xsdbool( has_where = abap_true AND grant-conditions IS INITIAL ).
      APPEND grant TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD conditions.
    FIND ALL OCCURRENCES OF PCRE `(?i)\(([^()]*)\)\s*\??=\s*aspect\s+pfcg_auth\s*\(([^()]*)\)` IN body RESULTS DATA(aspects).
    LOOP AT aspects INTO DATA(aspect).
      DATA(condition) = VALUE ty_condition( kind     = co_kind-pfcg
                                            elements = condense( group( text = body match = aspect index = 1 ) ) ).
      SPLIT group( text = body match = aspect index = 2 ) AT `,` INTO TABLE DATA(arguments).
      LOOP AT arguments INTO DATA(argument).
        argument = condense( argument ).
        IF sy-tabix = 1.
          condition-object = to_upper( argument ).
        ELSEIF argument CS `=`.
          SPLIT argument AT `=` INTO DATA(field) DATA(value).
          APPEND |{ to_upper( condense( field ) ) } = { condense( value ) }| TO condition-filters.
        ELSEIF argument IS NOT INITIAL.
          APPEND to_upper( argument ) TO condition-fields.
        ENDIF.
      ENDLOOP.
      APPEND condition TO result.
    ENDLOOP.

    FIND ALL OCCURRENCES OF PCRE `(?i)inheriting\s+conditions\s+from\s+(?:entity\s+)?([\w/]+)` IN body RESULTS DATA(inherited).
    LOOP AT inherited INTO DATA(inheritance).
      APPEND VALUE #( kind = co_kind-inherit object = to_upper( group( text = body match = inheritance index = 1 ) ) ) TO result.
    ENDLOOP.
    FIND ALL OCCURRENCES OF PCRE `(?i)\binherit\s+([\w/]+)\s+for\s+grant` IN body RESULTS DATA(roles).
    LOOP AT roles INTO DATA(role).
      APPEND VALUE #( kind = co_kind-inherit object = to_upper( group( text = body match = role index = 1 ) ) ) TO result.
    ENDLOOP.
    IF contains( val = body pcre = `(?i)=\s*aspect\s+user\b` ).
      APPEND VALUE #( kind = co_kind-user object = `USER` ) TO result.
    ENDIF.
  ENDMETHOD.

  METHOD group.
    DATA(submatch) = VALUE #( match-submatches[ index ] OPTIONAL ).
    IF submatch-offset >= 0 AND submatch-length > 0.
      result = substring( val = text off = submatch-offset len = submatch-length ).
    ENDIF.
  ENDMETHOD.

  METHOD protection.
    DATA(check) = to_upper( entity-authorization_check ).
    DATA(check_text) = COND string( WHEN check IS INITIAL THEN `not annotated` ELSE |#{ check }| ).
    DATA(name) = to_upper( entity-name ).
    DATA(mine) = VALUE ty_grants( FOR g IN grants WHERE ( entity = name ) ( g ) ).

    IF entity-kind = `CUSTOM`.
      result = VALUE #( status = co_status-custom
                        reason = `Custom entity: DCL does not apply, the query implementation class must check authorizations.` ).
    ELSEIF entity-kind = `ABSTRACT`.
      result = VALUE #( status = co_status-abstract protected = abap_true reason = `Abstract entity: no data to read.` ).
    ELSEIF check = `NOT_ALLOWED`.
      result = VALUE #( status = co_status-not_allowed
                        reason = |authorizationCheck #NOT_ALLOWED: access control is switched off{ COND #( WHEN mine IS NOT INITIAL THEN `, its DCL roles are ignored` ) }.| ).
    ELSEIF check = `PRIVILEGED_ONLY`.
      result = VALUE #( status = co_status-privileged_only protected = abap_true
                        reason = `authorizationCheck #PRIVILEGED_ONLY: only privileged access (WITH PRIVILEGED ACCESS) reads it.` ).
    ELSEIF mine IS INITIAL AND check = `MANDATORY`.
      result = VALUE #( status = co_status-no_access protected = abap_true
                        reason = `authorizationCheck #MANDATORY without DCL role: every read fails.` ).
    ELSEIF mine IS INITIAL.
      result = VALUE #( status = co_status-no_role
                        reason = |authorizationCheck { check_text } and no DCL role: every user who may call it reads all rows.| ).
    ELSEIF line_exists( mine[ unconditional = abap_true ] ).
      " grants of several roles are combined with OR: one grant without condition opens everything
      result = VALUE #( status = co_status-full_access
                        reason = `A DCL role grants select without condition: every user reads all rows.` ).
    ELSEIF line_exists( mine[ static_filter = abap_false ] ).
      result = VALUE #( status = co_status-protected protected = abap_true
                        reason = |{ lines( mine ) } DCL { COND #( WHEN lines( mine ) = 1 THEN `grant` ELSE `grants` ) } with conditions on the user's authorizations.| ).
    ELSE.
      result = VALUE #( status = co_status-static_filter
                        reason = `DCL roles only filter by fixed values: every user reads the same rows.` ).
    ENDIF.
  ENDMETHOD.

  METHOD status_order.
    result = VALUE #( ( co_status-no_role ) ( co_status-not_allowed ) ( co_status-full_access ) ( co_status-static_filter )
                      ( co_status-custom ) ( co_status-protected ) ( co_status-privileged_only ) ( co_status-no_access )
                      ( co_status-abstract ) ).
  ENDMETHOD.

  METHOD merge.
    LOOP AT conditions INTO DATA(condition).
      DATA(index) = 0.
      IF condition-kind = co_kind-pfcg AND condition-elements IS NOT INITIAL.
        LOOP AT result INTO DATA(existing) WHERE kind = co_kind-pfcg AND object = condition-object.
          IF existing-fields = condition-fields AND existing-filters = condition-filters AND existing-elements IS NOT INITIAL.
            index = sy-tabix.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
      IF index > 0.
        result[ index ]-elements = |{ result[ index ]-elements }, { condition-elements }|.
      ELSE.
        APPEND condition TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD condition_text.
    CASE condition-kind.
      WHEN co_kind-pfcg.
        DATA(filters) = COND string( WHEN condition-filters IS NOT INITIAL
                                     THEN | ({ concat_lines_of( table = condition-filters sep = `, ` ) })| ).
        IF condition-fields IS INITIAL.
          result = |{ condition-object }: authorization check only{ filters }|.
        ELSE.
          SPLIT condition-elements AT `, ` INTO TABLE DATA(elements).
          DATA(listed) = COND string( WHEN elements IS INITIAL THEN `?`
                                      WHEN lines( elements ) > 3 THEN |{ elements[ 1 ] }, { elements[ 2 ] } and { lines( elements ) - 2 } more|
                                      ELSE condition-elements ).
          result = |{ condition-object }: { listed } = | &&
                   |{ concat_lines_of( table = condition-fields sep = `, ` ) }{ filters }|.
        ENDIF.
      WHEN co_kind-inherit.
        result = |conditions inherited from { condition-object }|.
      WHEN co_kind-user.
        result = `rows of the user itself (aspect user)`.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

