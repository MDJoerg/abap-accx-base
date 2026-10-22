"! <p class="shorttext synchronized">Access Explorer: user pseudonyms</p>
"! Stable pseudonyms of user ids for the privacy modes PSEUDONYMIZE and MINIMIZE.
"! The same user always gets the same pseudonym, so a client can correlate
"! several tool calls without learning who the user is.
INTERFACE zif_accx_pseudonyms PUBLIC.

  "! Pseudonym of a user id, e.g. U-7F3A9C12
  METHODS pseudonym_for
    IMPORTING !user         TYPE csequence
    RETURNING VALUE(result) TYPE string
    RAISING   zcx_accx_error.

  "! True if the text has the shape of a pseudonym (it need not belong to a user)
  METHODS is_pseudonym
    IMPORTING !text         TYPE csequence
    RETURNING VALUE(result) TYPE abap_bool.

  "! User behind a pseudonym; an unknown or ambiguous pseudonym raises an error
  METHODS user_for
    IMPORTING !pseudonym    TYPE csequence
    RETURNING VALUE(result) TYPE syuname
    RAISING   zcx_accx_error.

ENDINTERFACE.
