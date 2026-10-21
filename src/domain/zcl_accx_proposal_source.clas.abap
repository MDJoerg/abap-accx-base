"! <p class="shorttext synchronized">Access Explorer: SU24 proposals from USOBX_C/USOBT_C</p>
"! Check indicator (USOBX_C-OKFLAG): Y = checked with proposal values in
"! USOBT_C, X/V = checked without proposal, N = not checked, I = inactive.
"! Only Y objects are added by PFCG. Types: TR transaction, HT OData service hash.
CLASS zcl_accx_proposal_source DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_proposal_source.

  PROTECTED SECTION.
    "! Proposals of one SU24 application
    METHODS read
      IMPORTING !name         TYPE csequence
                !type         TYPE csequence
      RETURNING VALUE(result) TYPE zif_accx_proposal_source=>ty_proposals.

ENDCLASS.

CLASS zcl_accx_proposal_source IMPLEMENTATION.

  METHOD zif_accx_proposal_source~get_for_transaction.
    result = read( name = tcode type = 'TR' ).
  ENDMETHOD.

  METHOD zif_accx_proposal_source~get_for_service.
    result = read( name = hash type = 'HT' ).
  ENDMETHOD.

  METHOD read.
    SELECT object, okflag FROM usobx_c
      WHERE name = @name AND type = @type AND okflag IN ('Y', 'X', 'V')
      ORDER BY object
      INTO TABLE @DATA(objects).
    result-objects = VALUE #( FOR o IN objects ( object = o-object proposed = xsdbool( o-okflag = 'Y' ) ) ).

    SELECT t~object, t~field, t~low, t~high FROM usobt_c AS t
      INNER JOIN usobx_c AS x ON x~name = t~name AND x~type = t~type AND x~object = t~object
      WHERE t~name = @name AND t~type = @type AND x~okflag = 'Y'
      ORDER BY t~object, t~field, t~low
      INTO CORRESPONDING FIELDS OF TABLE @result-values.
  ENDMETHOD.

ENDCLASS.
