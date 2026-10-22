"! <p class="shorttext synchronized">Access Explorer prompt: fiori_app_not_working</p>
"! Guided flow for questions like "the app is missing in the launchpad" or "the app
"! fails with an authorization error".
CLASS zcl_accx_p_fiori_app DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_prompt_base.

  PUBLIC SECTION.
    METHODS zif_accx_prompt~get_descriptor REDEFINITION.

  PROTECTED SECTION.
    METHODS compose REDEFINITION.

ENDCLASS.

CLASS zcl_accx_p_fiori_app IMPLEMENTATION.

  METHOD zif_accx_prompt~get_descriptor.
    result = VALUE #( name        = `fiori_app_not_working`
                      title       = `Fiori app is missing or does not start`
                      description = `Guided analysis of why a user cannot see or start a Fiori launchpad app: catalog, role, target mapping, start authorization and OData services.`
                      arguments   = VALUE #(
                          ( name = `user` description = `SAP user ID of the person who has the problem` required = abap_true )
                          ( name = `app` description = `Fiori ID (e.g. F4512), intent (SemanticObject-action), transaction of a GUI app, or words of the tile title` required = abap_true )
                          )
                      tools       = VALUE #(
                          ( `diagnose_fiori_app_access` )
                          ( `find_fiori_app` )
                          ( `get_user_launchpad` )
                          ( `get_service_access` )
                          ) ).
  ENDMETHOD.

  METHOD compose.
    DATA(user) = value_of( values = values name = `user` ).
    DATA(app) = value_of( values = values name = `app` ).
    DATA(lines) = VALUE string_table( ).
    APPEND |Find out why the SAP user "{ user }" cannot see or start the Fiori launchpad app "{ app }". Use both values exactly as given.| TO lines.
    APPEND `` TO lines.
    APPEND |1. Call diagnose_fiori_app_access with user and app. It checks the whole chain: a catalog with a target mapping for the app, a role of the user | &&
      |containing that catalog (valid today), the target mapping itself, and the start authorization (transaction, S_START for Web Dynpro, or activation and | &&
      |S_SERVICE of every OData service of an SAPUI5 app).| TO lines.
    APPEND |2. If the app is unknown or several apps match, call find_fiori_app with the same text, show the candidates and let the requester choose.| TO lines.
    APPEND |3. If a catalog or role is missing, use the roles the tool proposes. Name the role, say why it is the best choice and mention the critical | &&
      |authorizations it would add.| TO lines.
    APPEND |4. If an OData service is reported as inactive or not registered, or the app fails with HTTP 403 on a service, call get_service_access for that | &&
      |service.| TO lines.
    APPEND |5. If the user holds the catalog but the tile is still missing, call get_user_launchpad to see the catalogs, groups, spaces and pages the user gets | &&
      |through each role.| TO lines.
    APPEND `` TO lines.
    APPEND |Answer with: the first broken link of the chain and the evidence from the tool; the fix in order of preference; what could not be checked. Only read | &&
      |and analyse, do not change roles. If the administrator wants a fix, draft_role_change can plan it without changing anything.| TO lines.
    result = join( lines ).
  ENDMETHOD.

ENDCLASS.

