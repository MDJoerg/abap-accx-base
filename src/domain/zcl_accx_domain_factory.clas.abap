"! <p class="shorttext synchronized">Access Explorer: domain service factory</p>
"! Tools obtain domain services only from here. Plugins may later replace
"! implementations; tests use inject/reset.
CLASS zcl_accx_domain_factory DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS user_repo
      RETURNING VALUE(result) TYPE REF TO zif_accx_user_repo.

    CLASS-METHODS role_repo
      RETURNING VALUE(result) TYPE REF TO zif_accx_role_repo.

    CLASS-METHODS auth_evaluator
      RETURNING VALUE(result) TYPE REF TO zif_accx_auth_evaluator.

    CLASS-METHODS failure_source
      RETURNING VALUE(result) TYPE REF TO zif_accx_failure_source.

    CLASS-METHODS critical_rules
      RETURNING VALUE(result) TYPE REF TO zif_accx_critical_rules.

    CLASS-METHODS suim_gateway
      RETURNING VALUE(result) TYPE REF TO zif_accx_suim_gateway.

    CLASS-METHODS access_origin
      RETURNING VALUE(result) TYPE REF TO zif_accx_access_origin.

    CLASS-METHODS proposal_source
      RETURNING VALUE(result) TYPE REF TO zif_accx_proposal_source.

    CLASS-METHODS fiori_repo
      RETURNING VALUE(result) TYPE REF TO zif_accx_fiori_repo.

    CLASS-METHODS change_repo
      RETURNING VALUE(result) TYPE REF TO zif_accx_change_repo.

    CLASS-METHODS cds_access
      RETURNING VALUE(result) TYPE REF TO zif_accx_cds_access.

    "! Test seam: replace services (unbound parameters keep the current value)
    CLASS-METHODS inject
      IMPORTING !user_repo       TYPE REF TO zif_accx_user_repo OPTIONAL
                !role_repo       TYPE REF TO zif_accx_role_repo OPTIONAL
                !auth_evaluator  TYPE REF TO zif_accx_auth_evaluator OPTIONAL
                !failure_source  TYPE REF TO zif_accx_failure_source OPTIONAL
                !critical_rules  TYPE REF TO zif_accx_critical_rules OPTIONAL
                !suim_gateway    TYPE REF TO zif_accx_suim_gateway OPTIONAL
                !access_origin   TYPE REF TO zif_accx_access_origin OPTIONAL
                !proposal_source TYPE REF TO zif_accx_proposal_source OPTIONAL
                !fiori_repo      TYPE REF TO zif_accx_fiori_repo OPTIONAL
                !change_repo     TYPE REF TO zif_accx_change_repo OPTIONAL
                !cds_access      TYPE REF TO zif_accx_cds_access OPTIONAL.

    CLASS-METHODS reset.

  PRIVATE SECTION.
    CLASS-DATA user_repo_instance       TYPE REF TO zif_accx_user_repo.
    CLASS-DATA role_repo_instance       TYPE REF TO zif_accx_role_repo.
    CLASS-DATA auth_evaluator_instance  TYPE REF TO zif_accx_auth_evaluator.
    CLASS-DATA failure_source_instance  TYPE REF TO zif_accx_failure_source.
    CLASS-DATA critical_rules_instance  TYPE REF TO zif_accx_critical_rules.
    CLASS-DATA suim_gateway_instance    TYPE REF TO zif_accx_suim_gateway.
    CLASS-DATA access_origin_instance   TYPE REF TO zif_accx_access_origin.
    CLASS-DATA proposal_source_instance TYPE REF TO zif_accx_proposal_source.
    CLASS-DATA fiori_repo_instance      TYPE REF TO zif_accx_fiori_repo.
    CLASS-DATA change_repo_instance     TYPE REF TO zif_accx_change_repo.
    CLASS-DATA cds_access_instance      TYPE REF TO zif_accx_cds_access.

ENDCLASS.

CLASS zcl_accx_domain_factory IMPLEMENTATION.

  METHOD user_repo.
    IF user_repo_instance IS NOT BOUND.
      user_repo_instance = NEW zcl_accx_user_repo( ).
    ENDIF.
    result = user_repo_instance.
  ENDMETHOD.

  METHOD role_repo.
    IF role_repo_instance IS NOT BOUND.
      role_repo_instance = NEW zcl_accx_role_repo( ).
    ENDIF.
    result = role_repo_instance.
  ENDMETHOD.

  METHOD auth_evaluator.
    IF auth_evaluator_instance IS NOT BOUND.
      auth_evaluator_instance = NEW zcl_accx_auth_evaluator( ).
    ENDIF.
    result = auth_evaluator_instance.
  ENDMETHOD.

  METHOD failure_source.
    IF failure_source_instance IS NOT BOUND.
      failure_source_instance = NEW zcl_accx_failure_source( ).
    ENDIF.
    result = failure_source_instance.
  ENDMETHOD.

  METHOD critical_rules.
    " new instance per request: rules are cached in the instance and may change in SUIM
    IF critical_rules_instance IS BOUND.
      result = critical_rules_instance.
    ELSE.
      result = NEW zcl_accx_critical_rules( ).
    ENDIF.
  ENDMETHOD.

  METHOD suim_gateway.
    " new instance per request: texts are cached in the instance
    IF suim_gateway_instance IS BOUND.
      result = suim_gateway_instance.
    ELSE.
      result = NEW zcl_accx_suim_gateway( ).
    ENDIF.
  ENDMETHOD.

  METHOD access_origin.
    " new instance per request: profile values are cached in the instance
    IF access_origin_instance IS BOUND.
      result = access_origin_instance.
    ELSE.
      result = NEW zcl_accx_access_origin( critical_rules( ) ).
    ENDIF.
  ENDMETHOD.

  METHOD proposal_source.
    IF proposal_source_instance IS NOT BOUND.
      proposal_source_instance = NEW zcl_accx_proposal_source( ).
    ENDIF.
    result = proposal_source_instance.
  ENDMETHOD.

  METHOD fiori_repo.
    " new instance per request: launchpad content and role catalogs are cached in the instance
    IF fiori_repo_instance IS BOUND.
      result = fiori_repo_instance.
    ELSE.
      result = NEW zcl_accx_fiori_repo( ).
    ENDIF.
  ENDMETHOD.

  METHOD change_repo.
    IF change_repo_instance IS NOT BOUND.
      change_repo_instance = NEW zcl_accx_change_repo( ).
    ENDIF.
    result = change_repo_instance.
  ENDMETHOD.

  METHOD cds_access.
    IF cds_access_instance IS NOT BOUND.
      cds_access_instance = NEW zcl_accx_cds_access( ).
    ENDIF.
    result = cds_access_instance.
  ENDMETHOD.

  METHOD inject.
    IF user_repo IS BOUND.
      user_repo_instance = user_repo.
    ENDIF.
    IF role_repo IS BOUND.
      role_repo_instance = role_repo.
    ENDIF.
    IF auth_evaluator IS BOUND.
      auth_evaluator_instance = auth_evaluator.
    ENDIF.
    IF failure_source IS BOUND.
      failure_source_instance = failure_source.
    ENDIF.
    IF critical_rules IS BOUND.
      critical_rules_instance = critical_rules.
    ENDIF.
    IF suim_gateway IS BOUND.
      suim_gateway_instance = suim_gateway.
    ENDIF.
    IF access_origin IS BOUND.
      access_origin_instance = access_origin.
    ENDIF.
    IF proposal_source IS BOUND.
      proposal_source_instance = proposal_source.
    ENDIF.
    IF fiori_repo IS BOUND.
      fiori_repo_instance = fiori_repo.
    ENDIF.
    IF change_repo IS BOUND.
      change_repo_instance = change_repo.
    ENDIF.
    IF cds_access IS BOUND.
      cds_access_instance = cds_access.
    ENDIF.
  ENDMETHOD.

  METHOD reset.
    CLEAR: user_repo_instance, role_repo_instance, auth_evaluator_instance, failure_source_instance,
           critical_rules_instance, suim_gateway_instance, access_origin_instance, proposal_source_instance,
           fiori_repo_instance, change_repo_instance,
           cds_access_instance.
  ENDMETHOD.

ENDCLASS.
