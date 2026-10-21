"! <p class="shorttext synchronized">Access Explorer: Fiori launchpad content</p>
"! Launchpad catalogs, their target mappings and tiles, references between
"! catalogs, the launchpad content of PFCG roles (catalogs, groups, spaces),
"! groups and pages with the catalogs their tiles come from, the authorization
"! defaults PFCG takes over with a catalog and the OData services of SAPUI5
"! apps with their S_SERVICE values.
"! Embedded deployment only (frontend and backend in the same system).
"! Reads without authorization checks - callers must filter with the caller guard.
INTERFACE zif_accx_fiori_repo PUBLIC.

  CONSTANTS: BEGIN OF co_app_type,
               ui5 TYPE string VALUE `UI5`,
               gui TYPE string VALUE `GUI`,
               wda TYPE string VALUE `WDA`,
               url TYPE string VALUE `URL`,
             END OF co_app_type.

  CONSTANTS: BEGIN OF co_content_type,
               catalog   TYPE string VALUE `CATALOG`,
               group     TYPE string VALUE `GROUP`,
               flp_space TYPE string VALUE `SPACE`,
             END OF co_content_type.

  CONSTANTS: BEGIN OF co_navigation,
               intent TYPE string VALUE `INTENT`,
               url    TYPE string VALUE `URL`,
               none   TYPE string VALUE `NONE`,
             END OF co_navigation.

  CONSTANTS: BEGIN OF co_item_kind,
               tile    TYPE string VALUE `TILE`,
               mapping TYPE string VALUE `TARGET_MAPPING`,
             END OF co_item_kind.

  " Target mapping of a catalog (one app in one catalog)
  TYPES: BEGIN OF ty_app,
           catalog       TYPE string,
           catalog_title TYPE string,
           mapping_id    TYPE string,
           "! semantic object-action
           intent        TYPE string,
           "! title of the target mapping or of a tile pointing to the intent
           title         TYPE string,
           "! UI5, GUI, WDA, URL
           app_type      TYPE string,
           "! UI5 component, transaction, Web Dynpro application or URL
           target        TYPE string,
           fiori_ids     TYPE string,
           desktop       TYPE abap_bool,
           tablet        TYPE abap_bool,
           phone         TYPE abap_bool,
           "! content and reference of the target mapping are consistent
           consistent    TYPE abap_bool,
           "! content or reference problem as stated by the launchpad content API
           state_text    TYPE string,
           "! original (catalog/id) if the target mapping is a reference
           reference     TYPE string,
           "! deprecated or archived by SAP, with successor
           deprecation   TYPE string,
         END OF ty_app,
         ty_apps TYPE STANDARD TABLE OF ty_app WITH EMPTY KEY.

  " Tile of a catalog
  TYPES: BEGIN OF ty_tile,
           catalog     TYPE string,
           tile_id     TYPE string,
           title       TYPE string,
           subtitle    TYPE string,
           "! STATIC, DYNAMIC or a custom tile type
           tile_type   TYPE string,
           "! INTENT, URL or NONE
           navigation  TYPE string,
           "! semantic object-action the tile navigates to
           intent      TYPE string,
           url         TYPE string,
           consistent  TYPE abap_bool,
           state_text  TYPE string,
           "! original (catalog/id) if the tile is a reference
           reference   TYPE string,
           deprecation TYPE string,
         END OF ty_tile,
         ty_tiles TYPE STANDARD TABLE OF ty_tile WITH EMPTY KEY.

  " A launchpad catalog with its target mappings and tiles; catalog initial = not found
  TYPES: BEGIN OF ty_catalog,
           catalog    TYPE string,
           title      TYPE string,
           package    TYPE string,
           changed_by TYPE string,
           "! last change, ISO date
           changed_on TYPE string,
           apps       TYPE ty_apps,
           tiles      TYPE ty_tiles,
         END OF ty_catalog.

  " Item of another catalog that refers to an item of a catalog
  TYPES: BEGIN OF ty_reference,
           "! catalog containing the reference
           catalog     TYPE string,
           "! TILE or TARGET_MAPPING
           kind        TYPE string,
           id          TYPE string,
           "! referenced item (id in the original catalog)
           original_id TYPE string,
           "! the referenced item no longer exists
           lost        TYPE abap_bool,
         END OF ty_reference,
         ty_references TYPE STANDARD TABLE OF ty_reference WITH EMPTY KEY.

  " Authorization default of a catalog: a node PFCG adds below the catalog in the role menu
  TYPES: BEGIN OF ty_default,
           "! TR transaction, HT hash of a service or application
           type     TYPE string,
           "! transaction or hash (S_SERVICE-SRV_NAME for IWSG/IWSV; SU24 name)
           name     TYPE string,
           pgmid    TYPE string,
           "! TRAN, IWSG (gateway service), IWSV (backend service), WDYA (Web Dynpro), G4BA (OData V4 group), ...
           object   TYPE string,
           obj_name TYPE string,
           "! gateway service registered and active (IWSG only; others abap_undefined)
           active   TYPE abap_bool,
         END OF ty_default,
         ty_defaults TYPE STANDARD TABLE OF ty_default WITH EMPTY KEY.

  TYPES: BEGIN OF ty_catalog_defaults,
           defaults TYPE ty_defaults,
           "! warnings and errors of the launchpad content while reading the catalog
           messages TYPE string_table,
         END OF ty_catalog_defaults.

  TYPES: BEGIN OF ty_role_catalog,
           role    TYPE agr_name,
           catalog TYPE string,
         END OF ty_role_catalog,
         ty_role_catalogs TYPE STANDARD TABLE OF ty_role_catalog WITH EMPTY KEY.

  " Start authorization node in a role menu: a transaction or the hash of a service or application
  TYPES: BEGIN OF ty_menu_node,
           "! node id in the role menu (AGR_HIER-OBJECT_ID)
           node     TYPE string,
           "! catalog whose authorization default the node is (node below a catalog node); empty otherwise
           catalog  TYPE string,
           "! TR transaction, HT hash
           type     TYPE string,
           "! transaction or hash
           name     TYPE string,
           "! hashes: IWSG, IWSV, WDYA, G4BA, ... and the object name (USOBHASH)
           object   TYPE string,
           obj_name TYPE string,
         END OF ty_menu_node,
         ty_menu_nodes TYPE STANDARD TABLE OF ty_menu_node WITH EMPTY KEY.

  " Launchpad content node in a role menu
  TYPES: BEGIN OF ty_role_content,
           role     TYPE agr_name,
           "! CATALOG, GROUP or SPACE
           type     TYPE string,
           id       TYPE string,
           "! space template (SPACET_PROVIDER) instead of a space
           template TYPE abap_bool,
         END OF ty_role_content,
         ty_role_contents TYPE STANDARD TABLE OF ty_role_content WITH EMPTY KEY.

  " Tile in a group or on a page: the launchpad shows it only if the user has its catalog
  TYPES: BEGIN OF ty_tile_ref,
           catalog TYPE string,
           tile_id TYPE string,
         END OF ty_tile_ref,
         ty_tile_refs TYPE STANDARD TABLE OF ty_tile_ref WITH EMPTY KEY.

  " Page showing a tile of a catalog
  TYPES: BEGIN OF ty_tile_page,
           catalog TYPE string,
           tile_id TYPE string,
           page    TYPE string,
         END OF ty_tile_page,
         ty_tile_pages TYPE STANDARD TABLE OF ty_tile_page WITH EMPTY KEY.

  TYPES: BEGIN OF ty_group,
           group TYPE string,
           title TYPE string,
           tiles TYPE ty_tile_refs,
         END OF ty_group,
         ty_groups TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.

  TYPES: BEGIN OF ty_page,
           page   TYPE string,
           title  TYPE string,
           "! assigned to the space, but hidden
           hidden TYPE abap_bool,
           tiles  TYPE ty_tile_refs,
         END OF ty_page,
         ty_pages TYPE STANDARD TABLE OF ty_page WITH EMPTY KEY.

  " A space with its pages; id initial = not found
  TYPES: BEGIN OF ty_space,
           id    TYPE string,
           title TYPE string,
           pages TYPE ty_pages,
         END OF ty_space.

  TYPES: BEGIN OF ty_settings,
           "! launchpad setting SPACES: spaces and pages instead of groups (home page)
           spaces      TYPE abap_bool,
           "! setting SPACES_ENABLE_USER: users may switch between spaces and groups themselves
           user_switch TYPE abap_bool,
         END OF ty_settings.

  TYPES: BEGIN OF ty_hash,
           "! IWSG (gateway service, frontend), IWSV (backend service), G4BA (OData V4 service group)
           object   TYPE string,
           "! value of S_SERVICE-SRV_NAME (type HT)
           hash     TYPE xupname,
           "! object name: service identifier, backend service with version, or service group
           obj_name TYPE string,
         END OF ty_hash,
         ty_hashes TYPE STANDARD TABLE OF ty_hash WITH EMPTY KEY.

  TYPES: BEGIN OF ty_service,
           url           TYPE string,
           "! namespace and name, e.g. /UI2/FDM_TRANSPORT_SRV
           name          TYPE string,
           version       TYPE string,
           odata_version TYPE string,
           "! registered and active in the gateway (/IWFND/MAINT_SERVICE)
           active        TYPE abap_bool,
           hashes        TYPE ty_hashes,
           "! gateway service identifier (OData V2)
           identifier    TYPE string,
           "! registered in the gateway, active or not (OData V2)
           registered    TYPE abap_bool,
           "! system aliases the service is routed to (/IWFND/C_MGDEAM); empty = local
           aliases       TYPE string_table,
           "! ICF node /sap/opu/odata (V2) or /sap/opu/odata4 (V4) active; abap_undefined if not found
           icf_active    TYPE abap_bool,
         END OF ty_service,
         ty_services TYPE STANDARD TABLE OF ty_service WITH EMPTY KEY.

  "! Apps whose intent, Fiori ID, transaction or title matches the query (title: part of the text)
  METHODS find_apps
    IMPORTING !query        TYPE string
    RETURNING VALUE(result) TYPE ty_apps
    RAISING   zcx_accx_error.

  "! Catalog by its id (exact, else ignoring case) with all its target mappings and tiles
  METHODS get_catalog
    IMPORTING !catalog      TYPE string
    RETURNING VALUE(result) TYPE ty_catalog
    RAISING   zcx_accx_error.

  "! Items of other catalogs that refer to an item of the catalog, also lost references
  METHODS get_references
    IMPORTING !catalog      TYPE string
    RETURNING VALUE(result) TYPE ty_references
    RAISING   zcx_accx_error.

  "! Authorization defaults PFCG adds with the catalog (same source as the PFCG menu)
  METHODS get_catalog_defaults
    IMPORTING !catalog      TYPE string
    RETURNING VALUE(result) TYPE ty_catalog_defaults.

  "! Launchpad catalogs in the menus of the roles (PFCG, CAT_PROVIDER)
  METHODS get_role_catalogs
    IMPORTING !roles        TYPE zif_accx_role_repo=>ty_roles
    RETURNING VALUE(result) TYPE ty_role_catalogs.

  "! Roles whose menu contains one of the catalogs
  METHODS get_catalog_roles
    IMPORTING !catalogs     TYPE string_table
    RETURNING VALUE(result) TYPE ty_role_catalogs.

  "! Transactions and service or application hashes in the menu of a role, each with the
  "! catalog it is an authorization default of (as PFCG adds them below the catalog node)
  METHODS get_role_menu_nodes DEFAULT IGNORE
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE ty_menu_nodes.

  "! Catalogs, groups and spaces in the menus of the roles (PFCG)
  METHODS get_role_content
    IMPORTING !roles        TYPE zif_accx_role_repo=>ty_roles
    RETURNING VALUE(result) TYPE ty_role_contents.

  "! Groups with their tiles; groups that do not exist are left out
  METHODS get_groups
    IMPORTING !groups       TYPE string_table
    RETURNING VALUE(result) TYPE ty_groups
    RAISING   zcx_accx_error.

  "! All groups with their tiles
  METHODS get_all_groups
    RETURNING VALUE(result) TYPE ty_groups
    RAISING   zcx_accx_error.

  "! Pages (client-specific) showing one of the tiles
  METHODS get_tile_pages
    IMPORTING !tiles        TYPE ty_tile_refs
    RETURNING VALUE(result) TYPE ty_tile_pages.

  "! Space (or space template) with its pages and their tiles
  METHODS get_space
    IMPORTING !id           TYPE string
              !template     TYPE abap_bool DEFAULT abap_false
    RETURNING VALUE(result) TYPE ty_space.

  "! Launchpad settings for spaces (/UI2/FLP_CUS_CONF, /UI2/FLP_SYS_CONF)
  METHODS get_settings
    RETURNING VALUE(result) TYPE ty_settings.

  "! OData service by name (V2: namespace and name, e.g. /UI2/PAGE_BUILDER_PERS; version 0001 if empty) or by
  "! its /sap/opu/... URL (also V4), with registration, routing, ICF node and S_SERVICE values
  METHODS get_service DEFAULT IGNORE
    IMPORTING !name         TYPE string
              !version      TYPE string OPTIONAL
    RETURNING VALUE(result) TYPE ty_service.

  "! OData services an SAPUI5 component uses (UI5 app index), with activation and S_SERVICE values
  METHODS get_app_services
    IMPORTING !component    TYPE string
    RETURNING VALUE(result) TYPE ty_services
    RAISING   zcx_accx_error.

ENDINTERFACE.
