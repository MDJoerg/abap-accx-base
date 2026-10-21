"! <p class="shorttext synchronized">Access Explorer: CDS access control from DB</p>
"! Sources: DDLDEPENDENCY, DD02B, DDHEADANNO, DDDDLSRCT, TADIR (entities), ACMDCLMETADATAEN,
"! ACMDCLMETADATA, ACMDCLSRC (DCL roles), SRVD_RT_ENTITIES, SRVB_SERVICES (exposures),
"! /IWFND/I_MED_SRH (OData V2), /IWFND/C_V4_MSGR (published OData V4 service groups).
CLASS zcl_accx_cds_access DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_cds_access.

  PROTECTED SECTION.
    "! Bindings, service names and publication state of the exposures
    METHODS complete
      CHANGING !exposures TYPE zif_accx_cds_access=>ty_exposures.

ENDCLASS.

CLASS zcl_accx_cds_access IMPLEMENTATION.

  METHOD zif_accx_cds_access~get_entities.
    SELECT DISTINCT objectname, ddlname FROM ddldependency
      WHERE objectname IN @names
        AND state      = 'A'
        AND objecttype = 'STOB'
      ORDER BY objectname
      INTO TABLE @DATA(objects).
    IF objects IS INITIAL.
      RETURN.
    ENDIF.
    SELECT strucobjn, strucobjclass FROM dd02b
      FOR ALL ENTRIES IN @objects
      WHERE strucobjn = @objects-objectname
        AND as4local  = 'A'
      INTO TABLE @DATA(kinds).
    SELECT strucobjn, value FROM ddheadanno
      FOR ALL ENTRIES IN @objects
      WHERE strucobjn = @objects-objectname
        AND name      = 'ACCESSCONTROL.AUTHORIZATIONCHECK'
      INTO TABLE @DATA(annotations).
    SELECT ddlname, ddlanguage, ddtext FROM ddddlsrct
      FOR ALL ENTRIES IN @objects
      WHERE ddlname  = @objects-ddlname
        AND as4local = 'A'
      INTO TABLE @DATA(texts).
    SELECT obj_name, devclass FROM tadir
      FOR ALL ENTRIES IN @objects
      WHERE pgmid    = 'R3TR'
        AND object   = 'DDLS'
        AND obj_name = @objects-ddlname
      INTO TABLE @DATA(packages).

    LOOP AT objects INTO DATA(object).
      DATA(check) = to_upper( condense( VALUE string( annotations[ strucobjn = object-objectname ]-value OPTIONAL ) ) ).
      DATA(text) = VALUE string( texts[ ddlname = object-ddlname ddlanguage = sy-langu ]-ddtext OPTIONAL ).
      IF text IS INITIAL.
        text = VALUE #( texts[ ddlname = object-ddlname ddlanguage = 'E' ]-ddtext OPTIONAL ).
      ENDIF.
      APPEND VALUE #( name                = object-objectname
                      ddl_source          = object-ddlname
                      description         = text
                      package             = VALUE #( packages[ obj_name = object-ddlname ]-devclass OPTIONAL )
                      kind                = VALUE #( kinds[ strucobjn = object-objectname ]-strucobjclass OPTIONAL )
                      authorization_check = replace( val = check sub = `#` with = `` ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_cds_access~get_roles.
    SELECT DISTINCT e~entity_id, e~artifactname, m~dclname, m~dcl_type
      FROM acmdclmetadataen AS e INNER JOIN acmdclmetadata AS m
        ON  m~version_id   = e~version_id
        AND m~artifactname = e~artifactname
      WHERE e~entity_id IN @entities
      ORDER BY e~entity_id, e~artifactname
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      " sources are long strings: one read per DCL source
      SELECT SINGLE source FROM acmdclsrc WHERE dclname = @row-dclname AND as4local = 'A' INTO @DATA(source).
      APPEND VALUE #( entity   = row-entity_id
                      role     = row-artifactname
                      dcl      = row-dclname
                      dcl_type = row-dcl_type
                      source   = source ) TO result.
      CLEAR source.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_accx_cds_access~get_exposures.
    SELECT srvdname, exposed_artifact, exposed_alias FROM srvd_rt_entities
      WHERE exposed_artifact     IN @entities
        AND exposed_artifact_type = 'E'
      ORDER BY exposed_artifact, srvdname
      INTO TABLE @DATA(rows).
    result = VALUE #( FOR row IN rows ( entity = row-exposed_artifact service_definition = row-srvdname alias = row-exposed_alias ) ).
    SELECT strucobjn FROM ddheadanno
      WHERE strucobjn IN @entities
        AND name       = 'ODATA.PUBLISH'
        AND value      = 'true'
      INTO TABLE @DATA(published).
    LOOP AT published INTO DATA(view).
      APPEND VALUE #( entity = view-strucobjn auto_published = abap_true ) TO result.
    ENDLOOP.
    complete( CHANGING exposures = result ).
  ENDMETHOD.

  METHOD zif_accx_cds_access~find_exposures.
    DATA definitions TYPE zif_accx_cds_access=>ty_names.

    SELECT obj_name FROM tadir
      WHERE pgmid    = 'R3TR'
        AND object   = 'SRVD'
        AND obj_name IN @names
        AND devclass IN @packages
      INTO TABLE @DATA(objects).
    definitions = VALUE #( FOR o IN objects ( sign = 'I' option = 'EQ' low = o-obj_name ) ).
    IF definitions IS NOT INITIAL.
      SELECT srvdname, exposed_artifact, exposed_alias FROM srvd_rt_entities
        WHERE srvdname             IN @definitions
          AND exposed_artifact_type = 'E'
        ORDER BY srvdname, exposed_artifact
        INTO TABLE @DATA(rows).
      result = VALUE #( FOR row IN rows ( entity = row-exposed_artifact service_definition = row-srvdname alias = row-exposed_alias ) ).
    ENDIF.

    " views published by @OData.publish: true, by entity name and package of the DDL source
    SELECT a~strucobjn, d~ddlname FROM ddheadanno AS a INNER JOIN ddldependency AS d
        ON d~objectname = a~strucobjn
      WHERE a~strucobjn IN @names
        AND a~name       = 'ODATA.PUBLISH'
        AND a~value      = 'true'
        AND d~state      = 'A'
        AND d~objecttype = 'STOB'
      INTO TABLE @DATA(views).
    IF views IS NOT INITIAL.
      SELECT obj_name, devclass FROM tadir
        FOR ALL ENTRIES IN @views
        WHERE pgmid    = 'R3TR'
          AND object   = 'DDLS'
          AND obj_name = @views-ddlname
        INTO TABLE @DATA(view_packages).
      LOOP AT views INTO DATA(view).
        DATA(package) = VALUE string( view_packages[ obj_name = view-ddlname ]-devclass OPTIONAL ).
        IF package IN packages.
          APPEND VALUE #( entity = view-strucobjn auto_published = abap_true package = package ) TO result.
        ENDIF.
      ENDLOOP.
    ENDIF.
    complete( CHANGING exposures = result ).
  ENDMETHOD.

  METHOD complete.
    DATA definitions TYPE zif_accx_cds_access=>ty_names.
    DATA services TYPE zif_accx_cds_access=>ty_names.
    DATA groups TYPE zif_accx_cds_access=>ty_names.
    DATA completed TYPE zif_accx_cds_access=>ty_exposures.

    definitions = VALUE #( FOR e IN exposures WHERE ( service_definition IS NOT INITIAL )
                           ( sign = 'I' option = 'EQ' low = e-service_definition ) ).
    SORT definitions BY low.
    DELETE ADJACENT DUPLICATES FROM definitions COMPARING low.
    IF definitions IS NOT INITIAL.
      SELECT obj_name, devclass FROM tadir
        WHERE pgmid    = 'R3TR'
          AND object   = 'SRVD'
          AND obj_name IN @definitions
        INTO TABLE @DATA(packages).
      SELECT srvb_name, service_name, service_version, srvdname FROM srvb_services
        WHERE srvdname IN @definitions
          AND version  = 'A'
        ORDER BY srvb_name, service_name
        INTO TABLE @DATA(bindings).
    ENDIF.

    LOOP AT exposures INTO DATA(exposure).
      IF exposure-auto_published = abap_true.
        exposure-service = |{ exposure-entity }_CDS|.
        APPEND exposure TO completed.
        CONTINUE.
      ENDIF.
      exposure-package = VALUE #( packages[ obj_name = exposure-service_definition ]-devclass OPTIONAL ).
      DATA(bound) = abap_false.
      LOOP AT bindings INTO DATA(binding) WHERE srvdname = exposure-service_definition.
        bound = abap_true.
        APPEND VALUE #( BASE exposure binding         = binding-srvb_name
                                      service         = binding-service_name
                                      service_version = binding-service_version ) TO completed.
      ENDLOOP.
      IF bound = abap_false.
        APPEND exposure TO completed.
      ENDIF.
    ENDLOOP.

    services = VALUE #( FOR c IN completed WHERE ( service IS NOT INITIAL ) ( sign = 'I' option = 'EQ' low = to_upper( c-service ) ) ).
    " an OData V4 binding is published as service group named like the binding
    groups = VALUE #( FOR c IN completed WHERE ( binding IS NOT INITIAL ) ( sign = 'I' option = 'EQ' low = to_upper( c-binding ) ) ).
    IF services IS NOT INITIAL.
      SELECT service_name FROM /iwfnd/i_med_srh WHERE service_name IN @services INTO TABLE @DATA(v2).
    ENDIF.
    IF groups IS NOT INITIAL.
      SELECT group_id FROM /iwfnd/c_v4_msgr WHERE group_id IN @groups INTO TABLE @DATA(v4).
    ENDIF.
    LOOP AT completed ASSIGNING FIELD-SYMBOL(<exposure>) WHERE service IS NOT INITIAL.
      DATA(service) = to_upper( <exposure>-service ).
      DATA(group) = to_upper( <exposure>-binding ).
      IF line_exists( v2[ service_name = service ] ).
        <exposure>-protocol  = `V2`.
        <exposure>-published = abap_true.
      ELSEIF group IS NOT INITIAL AND line_exists( v4[ group_id = group ] ).
        <exposure>-protocol  = `V4`.
        <exposure>-published = abap_true.
      ENDIF.
    ENDLOOP.
    exposures = completed.
  ENDMETHOD.

ENDCLASS.

