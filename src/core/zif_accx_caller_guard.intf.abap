"! <p class="shorttext synchronized">Access Explorer: data-level checks for the caller</p>
"! Most SAP read APIs do not check the caller's authorization (see spike).
"! Every domain service without its own SAP check must filter its rows with
"! this guard. Semantics mirror SUIM (S_USER_GRP/S_USER_AGR/S_USER_PRO/S_USER_AUT, ACTVT 03;
"! change documents ACTVT 08).
INTERFACE zif_accx_caller_guard PUBLIC.

  "! Caller may display user master data of the given user (S_USER_GRP 03 on its group)
  METHODS can_display_user
    IMPORTING !user         TYPE syuname
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display the given role (S_USER_AGR 03)
  METHODS can_display_role
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display the given profile (S_USER_PRO 03)
  METHODS can_display_profile
    IMPORTING !profile      TYPE xuprofile
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display authorizations of the given object (S_USER_AUT 03)
  METHODS can_display_authorization
    IMPORTING !object       TYPE xuobject
              !auth         TYPE xuauth OPTIONAL
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display user master data of the users of a user group (S_USER_GRP 03)
  METHODS can_display_group DEFAULT IGNORE
    IMPORTING !user_group   TYPE xuclass
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display change documents of the users of a user group (S_USER_GRP 08)
  METHODS can_display_group_changes DEFAULT IGNORE
    IMPORTING !user_group   TYPE xuclass
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may display change documents of the given role (S_USER_AGR 08)
  METHODS can_display_role_changes DEFAULT IGNORE
    IMPORTING !role         TYPE agr_name
    RETURNING VALUE(result) TYPE abap_bool.

  "! Caller may preview the data of the CDS entity in ADT bypassing its access control
  "! (S_DEVELOP on the package, as SACMSEL and the ADT data preview check it)
  "! - required before rows are counted for another user
  METHODS can_preview_privileged DEFAULT IGNORE
    IMPORTING !entity       TYPE string
    RETURNING VALUE(result) TYPE abap_bool.

ENDINTERFACE.
