"! <p class="shorttext synchronized">Access Explorer resource: accx://faq</p>
"! Fixed text, no system data.
CLASS zcl_accx_r_faq DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_resource.

ENDCLASS.

CLASS zcl_accx_r_faq IMPLEMENTATION.

  METHOD zif_accx_resource~get_descriptor.
    result = VALUE #( uri         = `accx://faq`
                      name        = `faq`
                      title       = `Access Explorer FAQ`
                      description = `Answers to frequent questions about results, hidden entries, pseudonyms, the SU53 and write tools.`
                      mime_type   = `text/markdown` ).
  ENDMETHOD.

  METHOD zif_accx_resource~read.
    DATA(lines) = VALUE string_table(
        ( |# Access Explorer FAQ| )
        ( `` )
        ( |**Why do I see identifiers like U-1A2B3C4D instead of user names?**| )
        ( |This server runs with a privacy mode (PSEUDONYMIZE or MINIMIZE). Use the pseudonym as the user argument of the tools, it is resolved on the server. | &&
            |The same user always gets the same pseudonym. In mode MINIMIZE, dates such as the last logon are reduced to the month. An administrator can look up | &&
            |the user with the report ZACCX_PSEUDONYM_RESOLVE.| )
        ( `` )
        ( |**A result says that entries are hidden or counted. Is the result complete?**| )
        ( |No. The tools run with the display authorizations of the calling user, like the SUIM reports: users of other user groups, roles and change documents | &&
            |the caller may not display are not shown but counted. Quote the counts and say that the result is incomplete; someone with broader display | &&
            |authorizations can repeat the analysis.| )
        ( `` )
        ( |**A result says SUIM reports an incomplete result. What does that mean?**| )
        ( |The underlying SUIM report could not evaluate every user or role because of the caller's authorizations. Treat the figures as a lower bound.| )
        ( `` )
        ( |**Why does the SU53 of the calling user show failed checks after an analysis?**| )
        ( |check_user_access and explain_missing_access simulate the checks for the analyzed user, and the system records failed simulations in the SU53 buffer | &&
            |of the user who calls. get_failed_authorization_checks filters these simulations out when it reads the failures of the analyzed user.| )
        ( `` )
        ( |**get_failed_authorization_checks finds nothing. What now?**| )
        ( |The SU53 buffer only holds recent failures and is lost when the application server restarts. Ask the user to repeat the failing action and call the | &&
            |tool again. The user trace reaches further back but only exists while it is switched on for the user; reading it needs a separate authorization.| )
        ( `` )
        ( |**What is the difference between check_user_access and get_user_authorizations?**| )
        ( |check_user_access simulates an authorization check and answers yes or no for one transaction or object with given values. get_user_authorizations | &&
            |lists the values a user holds for one authorization object and the role each comes from.| )
        ( `` )
        ( |**Why are some roles or users missing in a comparison or a list?**| )
        ( |Lists are limited by max_rows and say so when they are truncated. Expired assignments and users that are not valid today are left out and counted, | &&
            |unless the tool has an option to include them.| )
        ( `` )
        ( |**What does critical mean?**| )
        ( |The system defines it: the SUIM variants of critical authorizations and combinations (report RSUSR008_009_NEW). Access Explorer reports a role as | &&
            |critical when it would grant such a rule and names the rule.| )
        ( `` )
        ( |**Can Access Explorer change roles or assignments?**| )
        ( |Only through write tools of the ADMIN plugin, and only on a server whose profile allows writing and outside productive clients. A write tool first | &&
            |returns a plan. Show the plan to the user and run it with plan_id and confirm set to true only after the user approved exactly this plan.| )
        ( `` )
        ( |**How current is the data?**| )
        ( |It is read live from the system when you call a tool. Role changes are only effective for users after the user comparison; get_role_details and | &&
            |get_role_authorizations show whether it is pending.| )
        ( `` )
        ( |**Where do I find more?**| )
        ( |The resource accx://tool-guide lists the right tool for each question, accx://glossary explains the terms.| )
        ).
    result = concat_lines_of( table = lines sep = |\n| ).
  ENDMETHOD.

ENDCLASS.

