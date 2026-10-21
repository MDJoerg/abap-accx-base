"! <p class="shorttext synchronized">Access Explorer: origin of critical authorizations</p>
"! Reads UST04 (user profiles), USREFUS (reference user), UST10C/UST10S/UST12
"! (active profile versions, only objects used by critical rules), AGR_1016
"! (generated profile of a role) and AGR_USERS/AGR_AGRS (composite roles).
"! Profile values are cached per instance.
CLASS zcl_accx_access_origin DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_access_origin.

    METHODS constructor
      IMPORTING !rules TYPE REF TO zif_accx_critical_rules.

  PROTECTED SECTION.
    TYPES: BEGIN OF ty_source,
             profile TYPE xuprofile,
             role    TYPE agr_name,
             via     TYPE string,
           END OF ty_source,
           ty_sources TYPE STANDARD TABLE OF ty_source WITH EMPTY KEY.

    DATA rules TYPE REF TO zif_accx_critical_rules.

    "! Profiles of the user master, mapped to their role
    METHODS sources_of
      IMPORTING !user         TYPE xubname
      RETURNING VALUE(result) TYPE ty_sources.

    "! Authorization values of a profile (composite profiles expanded) for the objects used by critical rules
    METHODS values_of
      IMPORTING !profile      TYPE xuprofile
      RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

    "! Authorization values of a profile (composite profiles expanded) for the objects;
    "! all objects only when all_objects is set and no object is given
    METHODS read_values
      IMPORTING !profile      TYPE xuprofile
                !objects      TYPE string_table
                !all_objects  TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_cached_sources,
             user    TYPE xubname,
             sources TYPE ty_sources,
           END OF ty_cached_sources.
    TYPES: BEGIN OF ty_cached_values,
             profile TYPE xuprofile,
             values  TYPE zif_accx_critical_rules=>ty_auth_values,
           END OF ty_cached_values.

    DATA source_cache TYPE HASHED TABLE OF ty_cached_sources WITH UNIQUE KEY user.
    DATA value_cache  TYPE HASHED TABLE OF ty_cached_values WITH UNIQUE KEY profile.

    METHODS cached_sources
      IMPORTING !user         TYPE xubname
      RETURNING VALUE(result) TYPE ty_sources.

    METHODS cached_values
      IMPORTING !profile      TYPE xuprofile
      RETURNING VALUE(result) TYPE zif_accx_critical_rules=>ty_auth_values.

    METHODS profiles_of
      IMPORTING !user         TYPE xubname
                !via          TYPE string
      RETURNING VALUE(result) TYPE ty_sources.

ENDCLASS.

CLASS zcl_accx_access_origin IMPLEMENTATION.

  METHOD constructor.
    me->rules = rules.
  ENDMETHOD.

  METHOD zif_accx_access_origin~trace_rule.
    DATA(groups) = rules->rule_groups( rule ).
    IF groups IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT cached_sources( user ) INTO DATA(source).
      DATA(met) = rules->met_groups( rule = rule values = cached_values( source-profile ) ).
      IF met IS INITIAL.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( rule        = rule
                      source_type = COND #( WHEN source-role IS NOT INITIAL
                                            THEN zif_accx_access_origin=>co_source-role
                                            ELSE zif_accx_access_origin=>co_source-profile )
                      source      = COND #( WHEN source-role IS NOT INITIAL THEN source-role ELSE source-profile )
                      profile     = source-profile
                      via         = source-via
                      complete    = xsdbool( lines( met ) = lines( groups ) ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_access_origin~trace_combination.
    LOOP AT rules->combination_rules( combination ) INTO DATA(rule).
      APPEND LINES OF zif_accx_access_origin~trace_rule( user = user rule = rule ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_access_origin~get_user_sources.
    result = CORRESPONDING #( cached_sources( user ) ).
  ENDMETHOD.

  METHOD zif_accx_access_origin~get_profile_values.
    result = read_values( profile = profile objects = objects all_objects = all_objects ).
  ENDMETHOD.

  METHOD cached_sources.
    ASSIGN source_cache[ user = user ] TO FIELD-SYMBOL(<cached>).
    IF sy-subrc <> 0.
      INSERT VALUE #( user = user sources = sources_of( user ) ) INTO TABLE source_cache ASSIGNING <cached>.
    ENDIF.
    result = <cached>-sources.
  ENDMETHOD.

  METHOD cached_values.
    ASSIGN value_cache[ profile = profile ] TO FIELD-SYMBOL(<cached>).
    IF sy-subrc <> 0.
      INSERT VALUE #( profile = profile values = values_of( profile ) ) INTO TABLE value_cache ASSIGNING <cached>.
    ENDIF.
    result = <cached>-values.
  ENDMETHOD.

  METHOD sources_of.
    result = profiles_of( user = user via = `` ).
    SELECT SINGLE refuser FROM usrefus WHERE bname = @user INTO @DATA(reference_user).
    IF sy-subrc = 0 AND reference_user IS NOT INITIAL.
      APPEND LINES OF profiles_of( user = reference_user via = |reference user { reference_user }| ) TO result.
    ENDIF.
  ENDMETHOD.

  METHOD profiles_of.
    DATA via_composite TYPE string.

    SELECT profile FROM ust04 WHERE bname = @user INTO TABLE @DATA(profiles).
    IF profiles IS INITIAL.
      RETURN.
    ENDIF.
    SELECT agr_name, profile FROM agr_1016
      FOR ALL ENTRIES IN @profiles
      WHERE profile = @profiles-profile
      INTO TABLE @DATA(generated).
    SELECT agr_name, col_flag FROM agr_users
      WHERE uname    = @user
        AND from_dat <= @sy-datum
        AND to_dat   >= @sy-datum
      INTO TABLE @DATA(assignments).

    LOOP AT profiles INTO DATA(profile).
      DATA(source) = VALUE ty_source( profile = profile-profile via = via ).
      LOOP AT generated INTO DATA(role) WHERE profile = profile-profile.
        source-role = role-agr_name.
        " prefer the role the user holds today
        IF line_exists( assignments[ agr_name = role-agr_name ] ).
          EXIT.
        ENDIF.
      ENDLOOP.
      IF source-role IS NOT INITIAL AND NOT line_exists( assignments[ agr_name = source-role col_flag = space ] ).
        " assigned only through composite roles
        SELECT agr_name FROM agr_agrs WHERE child_agr = @source-role INTO TABLE @DATA(parents).
        CLEAR via_composite.
        LOOP AT parents INTO DATA(parent) WHERE agr_name IS NOT INITIAL.
          IF line_exists( assignments[ agr_name = parent-agr_name ] ).
            via_composite = |{ via_composite }{ COND #( WHEN via_composite IS NOT INITIAL THEN `, ` ) }{ parent-agr_name }|.
          ENDIF.
        ENDLOOP.
        IF via_composite IS NOT INITIAL.
          source-via = |{ COND #( WHEN via IS NOT INITIAL THEN |{ via }, | ) }composite role { via_composite }|.
        ENDIF.
      ENDIF.
      APPEND source TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD values_of.
    " only objects used by critical rules (SAP_ALL holds thousands of authorizations)
    result = read_values( profile = profile objects = VALUE #( FOR o IN rules->rule_objects( ) ( o ) ) ).
  ENDMETHOD.

  METHOD read_values.
    TYPES ty_profiles TYPE SORTED TABLE OF xuprofile WITH UNIQUE KEY table_line.
    DATA singles TYPE ty_profiles.
    DATA object_range TYPE RANGE OF xuobject.

    " expand composite profiles (UST10C) down to single profiles
    DATA(open) = VALUE ty_profiles( ( profile ) ).
    DATA(seen) = open.
    WHILE open IS NOT INITIAL.
      SELECT profn, subprof FROM ust10c
        FOR ALL ENTRIES IN @open
        WHERE profn = @open-table_line
          AND aktps = 'A'
        INTO TABLE @DATA(children).
      LOOP AT open INTO DATA(current).
        IF NOT line_exists( children[ profn = current ] ).
          INSERT current INTO TABLE singles.
        ENDIF.
      ENDLOOP.
      CLEAR open.
      LOOP AT children INTO DATA(child).
        INSERT child-subprof INTO TABLE seen.
        IF sy-subrc = 0.
          INSERT child-subprof INTO TABLE open.
        ENDIF.
      ENDLOOP.
    ENDWHILE.

    LOOP AT objects INTO DATA(object).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = object ) TO object_range.
    ENDLOOP.
    IF singles IS INITIAL OR ( object_range IS INITIAL AND all_objects = abap_false ).
      RETURN.
    ENDIF.

    SELECT DISTINCT objct, auth FROM ust10s
      FOR ALL ENTRIES IN @singles
      WHERE profn = @singles-table_line
        AND aktps = 'A'
        AND objct IN @object_range
      INTO TABLE @DATA(authorizations).
    IF authorizations IS INITIAL.
      RETURN.
    ENDIF.

    SELECT objct AS object, auth, field, von AS low, bis AS high FROM ust12
      FOR ALL ENTRIES IN @authorizations
      WHERE objct = @authorizations-objct
        AND auth  = @authorizations-auth
        AND aktps = 'A'
      INTO CORRESPONDING FIELDS OF TABLE @result.
  ENDMETHOD.

ENDCLASS.
