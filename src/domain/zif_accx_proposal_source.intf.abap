"! <p class="shorttext synchronized">Access Explorer: SU24 authorization proposals</p>
"! Authorization default values of an application as PFCG uses them when the
"! application is added to a role menu (customer tables of SU24).
INTERFACE zif_accx_proposal_source PUBLIC.

  TYPES: BEGIN OF ty_object,
           object   TYPE xuobject,
           "! values are proposed (check indicator Y); otherwise only checked
           proposed TYPE abap_bool,
         END OF ty_object,
         ty_objects TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

  TYPES: BEGIN OF ty_value,
           object TYPE xuobject,
           field  TYPE xufield,
           "! empty = open field to be maintained in PFCG; $... = organizational level
           low    TYPE xuval,
           high   TYPE xuval,
         END OF ty_value,
         ty_values TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.

  TYPES: BEGIN OF ty_proposals,
           objects TYPE ty_objects,
           values  TYPE ty_values,
         END OF ty_proposals.

  "! Checked objects and proposed values of a transaction
  METHODS get_for_transaction
    IMPORTING !tcode        TYPE tcode
    RETURNING VALUE(result) TYPE ty_proposals.

  "! Checked objects and proposed values of an OData service (S_SERVICE hash, SU24 type HT)
  METHODS get_for_service
    IMPORTING !hash         TYPE xupname
    RETURNING VALUE(result) TYPE ty_proposals.

ENDINTERFACE.
