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

  CONSTANTS: BEGIN OF co_access,
               full       TYPE string VALUE `full`,
               none       TYPE string VALUE `none`,
               restricted TYPE string VALUE `restricted`,
             END OF co_access.

  TYPES: BEGIN OF ty_evaluation,
           "! see CO_ACCESS; empty when the runtime failed
           access          TYPE string,
           "! restricted: WHERE condition of the ACM runtime with the user's values inserted
           condition       TYPE string,
           "! restricted, but the condition needs a join (runtime CTE) and is not given as WHERE condition
           join_only       TYPE abap_bool,
           "! elements masked by cell rules (grant select ... for elements)
           masked_elements TYPE string_table,
           error           TYPE string,
         END OF ty_evaluation.

  TYPES: BEGIN OF ty_row_count,
           "! rows the user sees
           visible TYPE int8,
           "! rows without access control (WITH PRIVILEGED ACCESS)
           total   TYPE int8,
           error   TYPE string,
         END OF ty_row_count.

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

  "! Access restrictions of the ACM runtime for a user on an entity (SELECT), as SACMSEL
  "! shows them with enforcement layer None; reads no data
  METHODS evaluate DEFAULT IGNORE
    IMPORTING !user         TYPE syuname
              !entity       TYPE string
    RETURNING VALUE(result) TYPE ty_evaluation.

  "! Number of rows of the entity in total and under the condition (empty condition = all rows,
  "! none = no visible rows); access control is bypassed, no row content is read
  METHODS count_rows DEFAULT IGNORE
    IMPORTING !entity       TYPE string
              !access       TYPE string
              !condition    TYPE string OPTIONAL
    RETURNING VALUE(result) TYPE ty_row_count.

ENDINTERFACE.
