"! <p class="shorttext synchronized">Access Explorer: CDS access control and exposure</p>
"! Technical metadata of CDS entities: authorization check annotation, DCL roles
"! protecting an entity with their source, and the OData services exposing it.
INTERFACE zif_accx_cds_access PUBLIC.

  TYPES ty_name TYPE c LENGTH 40.
  TYPES ty_names TYPE RANGE OF ty_name.

  TYPES: BEGIN OF ty_entity,
           name                TYPE string,
           ddl_source          TYPE string,
           description         TYPE string,
           package             TYPE string,
           "! DD02B class: VIEWENTITY, PROJ_STD, PROJ_TRA, CUSTOM, ABSTRACT, HIER_*; empty = DDIC-based view
           kind                TYPE string,
           "! value of AccessControl.authorizationCheck without #, e.g. CHECK; empty = not annotated
           authorization_check TYPE string,
         END OF ty_entity,
         ty_entities TYPE STANDARD TABLE OF ty_entity WITH EMPTY KEY.

  TYPES: BEGIN OF ty_role,
           "! protected entity
           entity   TYPE string,
           "! DCL role
           role     TYPE string,
           dcl      TYPE string,
           dcl_type TYPE string,
           source   TYPE string,
         END OF ty_role,
         ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

  TYPES: BEGIN OF ty_exposure,
           entity             TYPE string,
           "! service definition; empty for OData.publish
           service_definition TYPE string,
           alias              TYPE string,
           "! package of the service definition (or of the DDL source for OData.publish)
           package            TYPE string,
           "! service binding; empty when the service definition is not bound
           binding            TYPE string,
           "! service name of the binding, or the entity name plus _CDS for OData.publish
           service            TYPE string,
           service_version    TYPE string,
           "! V2 or V4 when published, else empty
           protocol           TYPE string,
           published          TYPE abap_bool,
           "! exposed by OData.publish: true
           auto_published     TYPE abap_bool,
         END OF ty_exposure,
         ty_exposures TYPE STANDARD TABLE OF ty_exposure WITH EMPTY KEY.

  "! CDS entities by name (upper case), with annotation, kind and package; unknown names are left out
  METHODS get_entities
    IMPORTING !names        TYPE ty_names
    RETURNING VALUE(result) TYPE ty_entities.

  "! Active DCL roles protecting the given entities, with their DCL source
  METHODS get_roles
    IMPORTING !entities     TYPE ty_names
    RETURNING VALUE(result) TYPE ty_roles.

  "! Services exposing the given entities (service definitions and OData.publish), with
  "! bindings and publication state
  METHODS get_exposures
    IMPORTING !entities     TYPE ty_names
    RETURNING VALUE(result) TYPE ty_exposures.

  "! Exposures of service definitions matching the pattern, plus entities with OData.publish
  "! matching the pattern; optionally limited to packages
  METHODS find_exposures
    IMPORTING !names        TYPE ty_names
              !packages     TYPE ty_names OPTIONAL
    RETURNING VALUE(result) TYPE ty_exposures.

ENDINTERFACE.
