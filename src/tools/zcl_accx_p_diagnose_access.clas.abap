"! <p class="shorttext synchronized">Access Explorer prompt: diagnose_access_problem</p>
"! Guided flow for questions like "why can the user not do X": status, failed checks,
"! simulation, candidate roles.
CLASS zcl_accx_p_diagnose_access DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_prompt_base.

  PUBLIC SECTION.
    METHODS zif_accx_prompt~get_descriptor REDEFINITION.

  PROTECTED SECTION.
    METHODS compose REDEFINITION.

ENDCLASS.

CLASS zcl_accx_p_diagnose_access IMPLEMENTATION.

  METHOD zif_accx_prompt~get_descriptor.
    result = VALUE #( name        = `diagnose_access_problem`
                      title       = `Diagnose an access problem`
                      description = `Guided analysis of why a user cannot start a transaction or use an authorization: user status, failed checks, simulation, roles that would close the gap.`
                      arguments   = VALUE #(
                          ( name = `user` description = `SAP user ID of the person who has the problem` required = abap_true )
                          ( name = `problem` description = `What fails: transaction code, authorization object or app, and the error text if known` )
                          )
                      tools       = VALUE #(
                          ( `get_user_profile` )
                          ( `get_failed_authorization_checks` )
                          ( `check_user_access` )
                          ( `explain_missing_access` )
                          ) ).
  ENDMETHOD.

  METHOD compose.
    DATA(user) = value_of( values = values name = `user` ).
    DATA(problem) = value_of( values = values name = `problem` ).
    DATA(lines) = VALUE string_table( ).
    APPEND |Diagnose why the SAP user "{ user }" cannot do what they need, and report the cause precisely.| TO lines.
    IF problem IS NOT INITIAL.
      APPEND |Reported problem: { problem }| TO lines.
    ENDIF.
    APPEND `` TO lines.
    APPEND |Work through these steps and stop as soon as the cause is clear. Use the user ID exactly as given.| TO lines.
    APPEND |1. Call get_user_profile for the user. Check that the user exists, is not locked and is valid today, and that the expected roles are assigned and | &&
      |valid today. A lock, an expired validity or an expired role assignment is often the whole answer: report it and stop.| TO lines.
    APPEND |2. Call get_failed_authorization_checks for the user. Failed checks name the authorization object and the field values that were missing. If the list | &&
      |is empty, ask the user to repeat the failing action and call it again, because the SU53 buffer only holds recent failures.| TO lines.
    APPEND |3. Test the access that fails with check_user_access: target_type transaction for a transaction code, or target_type authorization with the object | &&
      |and the FIELD=VALUE pairs from step 2. Never guess values, use the reported ones.| TO lines.
    APPEND |4. If access is missing, call explain_missing_access with the same arguments. It ranks existing roles that would close the gap, names their critical | &&
      |authorizations and offers a less critical alternative.| TO lines.
    APPEND |5. If the problem is a Fiori app or a launchpad tile, use the prompt fiori_app_not_working instead.| TO lines.
    APPEND `` TO lines.
    APPEND |Answer with: the cause in one sentence; the missing authorization object with its fields and values; the roles that would close the gap, preferring | &&
      |the one with the fewest critical authorizations, and why; what the requester or the administrator should do next. Explain in plain language what each | &&
      |authorization object protects.| TO lines.
    APPEND |Only read and analyse. Do not change roles or assignments; if write tools exist, use them only after an administrator has approved the exact plan.| TO lines.
    result = join( lines ).
  ENDMETHOD.

ENDCLASS.

