"! <p class="shorttext synchronized">Access Explorer: factory and test seam</p>
"! Single place that instantiates core implementations. Transport adapters and
"! tools obtain collaborators only from here.
CLASS zcl_accx_factory DEFINITION PUBLIC FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CONSTANTS co_default_max_rows TYPE i VALUE 50.
    CONSTANTS co_limit_max_rows   TYPE i VALUE 500.

    CONSTANTS: BEGIN OF co_privacy_mode,
                 none         TYPE string VALUE `NONE`,
                 pseudonymize TYPE string VALUE `PSEUDONYMIZE`,
                 minimize     TYPE string VALUE `MINIMIZE`,
               END OF co_privacy_mode.

    CLASS-METHODS registry
      RETURNING VALUE(result) TYPE REF TO zif_accx_registry.

    CLASS-METHODS runtime
      RETURNING VALUE(result) TYPE REF TO zif_accx_runtime.

    "! Privacy strategy of a profile; fails closed for unsupported modes
    CLASS-METHODS privacy
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE REF TO zif_accx_privacy.

    "! Usage authorization of a profile (ZACCX_PROFILE-AUTHORIZER_CLASS);
    "! default ZCL_ACCX_AUTHORIZER, fails closed if the class is not usable
    CLASS-METHODS authorizer
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE REF TO zif_accx_authorizer.

    CLASS-METHODS guard
      RETURNING VALUE(result) TYPE REF TO zif_accx_caller_guard.

    "! Plans of write tools (ZACCX_PLAN)
    CLASS-METHODS plan_store
      RETURNING VALUE(result) TYPE REF TO zif_accx_plan_store.

    "! Why write tools may not run for a profile: ZACCX_PROFILE-ALLOW_WRITE not set,
    "! or production client (T000-CCCATEGORY P); empty = allowed
    CLASS-METHODS write_problem
      IMPORTING !profile      TYPE string
      RETURNING VALUE(result) TYPE string.

    "! Request context; max_rows taken from args (reserved parameter) and clamped
    CLASS-METHODS context
      IMPORTING !profile           TYPE string
                !args              TYPE REF TO zif_accx_args OPTIONAL
                !client_can_elicit TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result)      TYPE REF TO zif_accx_context.

    "! Test seam: replace collaborators (unbound parameters keep the current value)
    CLASS-METHODS inject
      IMPORTING !registry   TYPE REF TO zif_accx_registry OPTIONAL
                !runtime    TYPE REF TO zif_accx_runtime OPTIONAL
                !privacy    TYPE REF TO zif_accx_privacy OPTIONAL
                !authorizer TYPE REF TO zif_accx_authorizer OPTIONAL
                !guard      TYPE REF TO zif_accx_caller_guard OPTIONAL
                !plan_store TYPE REF TO zif_accx_plan_store OPTIONAL.

    CLASS-METHODS reset.

  PRIVATE SECTION.
    CLASS-DATA registry_instance   TYPE REF TO zif_accx_registry.
    CLASS-DATA runtime_instance    TYPE REF TO zif_accx_runtime.
    CLASS-DATA privacy_override    TYPE REF TO zif_accx_privacy.
    CLASS-DATA authorizer_override TYPE REF TO zif_accx_authorizer.
    CLASS-DATA guard_override      TYPE REF TO zif_accx_caller_guard.
    CLASS-DATA plan_store_override TYPE REF TO zif_accx_plan_store.

ENDCLASS.

CLASS zcl_accx_factory IMPLEMENTATION.

  METHOD registry.
    IF registry_instance IS NOT BOUND.
      registry_instance = NEW zcl_accx_registry( ).
    ENDIF.
    result = registry_instance.
  ENDMETHOD.

  METHOD runtime.
    IF runtime_instance IS NOT BOUND.
      runtime_instance = NEW zcl_accx_runtime_local( registry = registry( )
                                                     logger   = NEW zcl_accx_logger_db( ) ).
    ENDIF.
    result = runtime_instance.
  ENDMETHOD.

  METHOD privacy.
    IF privacy_override IS BOUND.
      result = privacy_override.
      RETURN.
    ENDIF.
    SELECT SINGLE privacy_mode, privacy_class FROM zaccx_profile
      WHERE profile = @profile
      INTO @DATA(settings).
    IF settings-privacy_class IS NOT INITIAL.
      TRY.
          CREATE OBJECT result TYPE (settings-privacy_class).
        CATCH cx_root INTO DATA(error).
          result = NEW zcl_accx_privacy_withhold( |privacy class { settings-privacy_class } not usable: { error->get_text( ) }| ).
      ENDTRY.
      RETURN.
    ENDIF.
    DATA(mode) = to_upper( condense( CONV string( settings-privacy_mode ) ) ).
    CASE mode.
      WHEN space OR co_privacy_mode-none.
        result = NEW zcl_accx_privacy_none( ).
      WHEN co_privacy_mode-pseudonymize OR co_privacy_mode-minimize.
        result = NEW zcl_accx_privacy_default( mode ).
      WHEN OTHERS.
        result = NEW zcl_accx_privacy_withhold( |privacy mode { mode } is not available| ).
    ENDCASE.
  ENDMETHOD.

  METHOD authorizer.
    IF authorizer_override IS BOUND.
      result = authorizer_override.
      RETURN.
    ENDIF.
    SELECT SINGLE authorizer_class FROM zaccx_profile
      WHERE profile = @profile
      INTO @DATA(class_name).
    IF class_name IS INITIAL.
      result = NEW zcl_accx_authorizer( ).
      RETURN.
    ENDIF.
    TRY.
        CREATE OBJECT result TYPE (class_name).
      CATCH cx_root.
        " a broken customer check must never open access
        result = NEW zcl_accx_authorizer_deny( ).
    ENDTRY.
  ENDMETHOD.

  METHOD guard.
    IF guard_override IS BOUND.
      result = guard_override.
    ELSE.
      result = NEW zcl_accx_caller_guard( ).
    ENDIF.
  ENDMETHOD.

  METHOD plan_store.
    IF plan_store_override IS BOUND.
      result = plan_store_override.
    ELSE.
      result = NEW zcl_accx_plan_store( ).
    ENDIF.
  ENDMETHOD.

  METHOD write_problem.
    SELECT SINGLE allow_write FROM zaccx_profile WHERE profile = @profile INTO @DATA(allow_write).
    IF allow_write <> abap_true.
      result = |Server profile { profile } does not allow write tools (ZACCX_PROFILE-ALLOW_WRITE).|.
      RETURN.
    ENDIF.
    SELECT SINGLE cccategory FROM t000 WHERE mandt = @sy-mandt INTO @DATA(category).
    IF category = 'P'.
      result = |Client { sy-mandt } is a production client; write tools are refused.|.
    ENDIF.
  ENDMETHOD.

  METHOD context.
    SELECT SINGLE max_rows FROM zaccx_profile WHERE profile = @profile INTO @DATA(profile_rows).
    DATA(max_rows) = COND i( WHEN profile_rows > 0 THEN profile_rows ELSE co_default_max_rows ).
    IF args IS BOUND AND args->has( zif_accx_types=>co_param-max_rows ) = abap_true.
      max_rows = args->get_integer( name = zif_accx_types=>co_param-max_rows default = max_rows ).
    ENDIF.
    max_rows = nmax( val1 = 1 val2 = nmin( val1 = max_rows val2 = co_limit_max_rows ) ).
    result = NEW zcl_accx_context( profile           = profile
                                   max_rows          = max_rows
                                   guard             = guard( )
                                   privacy           = privacy( profile )
                                   authorizer        = authorizer( profile )
                                   client_can_elicit = client_can_elicit
                                   write_problem     = write_problem( profile ) ).
  ENDMETHOD.

  METHOD inject.
    IF registry IS BOUND.
      registry_instance = registry.
    ENDIF.
    IF runtime IS BOUND.
      runtime_instance = runtime.
    ENDIF.
    IF privacy IS BOUND.
      privacy_override = privacy.
    ENDIF.
    IF authorizer IS BOUND.
      authorizer_override = authorizer.
    ENDIF.
    IF guard IS BOUND.
      guard_override = guard.
    ENDIF.
    IF plan_store IS BOUND.
      plan_store_override = plan_store.
    ENDIF.
  ENDMETHOD.

  METHOD reset.
    CLEAR: registry_instance, runtime_instance, privacy_override, authorizer_override, guard_override, plan_store_override.
  ENDMETHOD.

ENDCLASS.
