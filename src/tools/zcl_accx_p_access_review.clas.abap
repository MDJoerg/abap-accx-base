"! <p class="shorttext synchronized">Access Explorer prompt: quarterly_access_review</p>
"! Guided flow for the periodic access review (user hygiene, critical authorizations,
"! changes, outliers, role health).
CLASS zcl_accx_p_access_review DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_prompt_base.

  PUBLIC SECTION.
    METHODS zif_accx_prompt~get_descriptor REDEFINITION.

  PROTECTED SECTION.
    METHODS compose REDEFINITION.

ENDCLASS.

CLASS zcl_accx_p_access_review IMPLEMENTATION.

  METHOD zif_accx_prompt~get_descriptor.
    result = VALUE #( name        = `quarterly_access_review`
                      title       = `Quarterly access review`
                      description = `Prepares the periodic access review: user hygiene, critical authorizations, authorization changes, outliers per user group and role health, as one findings table.`
                      arguments   = VALUE #(
                          ( name = `user_group` description = `User group to review, e.g. SUPER (default: all users)` )
                          ( name = `period_days` description = `Days to look back for authorization changes, 1 to 366 (default 90)` )
                          )
                      tools       = VALUE #(
                          ( `get_user_hygiene_report` )
                          ( `run_critical_access_check` )
                          ( `get_authorization_changes` )
                          ( `analyze_user_group` )
                          ( `check_role_health` )
                          ) ).
  ENDMETHOD.

  METHOD compose.
    DATA(user_group) = value_of( values = values name = `user_group` ).
    DATA(period_days) = value_of( values = values name = `period_days` ).
    DATA(days) = `90`.
    IF matches( val = period_days pcre = `\d{1,3}` ) AND CONV i( period_days ) >= 1 AND CONV i( period_days ) <= 366.
      days = period_days.
    ENDIF.
    DATA(group_text) = COND string( WHEN user_group IS NOT INITIAL THEN | for user group "{ user_group }"| ELSE | for all users| ).
    DATA(group_arg) = COND string( WHEN user_group IS NOT INITIAL THEN | with user_group "{ user_group }"| ).
    DATA(group_arg2) = COND string( WHEN user_group IS NOT INITIAL THEN | and user_group "{ user_group }"| ).
    DATA(lines) = VALUE string_table( ).
    APPEND |Prepare a quarterly access review{ group_text }.| TO lines.
    APPEND `` TO lines.
    APPEND |Run these steps in this order and keep the identifiers exactly as the tools return them:| TO lines.
    APPEND |1. get_user_hygiene_report{ group_arg }: profiles assigned directly (e.g. SAP_ALL), inactive and never-used dialog users, initial passwords, expired | &&
      |users that still hold roles, and the standard users SAP*, DDIC, SAPCPIC, EARLYWATCH and TMSADM.| TO lines.
    APPEND |2. run_critical_access_check with scope users{ group_arg2 }: critical authorizations and critical combinations as defined by the SUIM variants of | &&
      |this system. Report per rule with the number of holders; name individual users only for rules with few holders.| TO lines.
    APPEND |3. get_authorization_changes with scope all for the last { days } days (derive from and to from today's date; ask for the date if you do not know | &&
      |it): role assignments, role content and user master changes. Flag users who changed their own assignments.| TO lines.
    APPEND |4. analyze_user_group for the user groups with the most findings (at most three), to find outliers and members without a role concept.| TO lines.
    APPEND |5. check_role_health with role_pattern Z* (or the customer namespace) for roles that are not generated, not in sync or held by nobody.| TO lines.
    APPEND `` TO lines.
    APPEND |Answer with a table: area, finding, number affected, severity (critical, high, medium, low), proposed action. Then name the three most urgent items | &&
      |and say which checks are incomplete because of missing display authorizations (the tools count hidden entries, quote those counts). Only read and | &&
      |analyse, do not change anything.| TO lines.
    result = join( lines ).
  ENDMETHOD.

ENDCLASS.

