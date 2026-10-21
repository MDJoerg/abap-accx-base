"! <p class="shorttext synchronized">Access Explorer: change documents of users and roles</p>
"! Reads without authorization checks - callers must filter with the caller guard
"! (change documents: activity 08).
INTERFACE zif_accx_change_repo PUBLIC.

  TYPES ty_user_range TYPE RANGE OF syuname.
  TYPES ty_role_range TYPE RANGE OF agr_name.

  TYPES: BEGIN OF ty_selection,
           from       TYPE d,
           to         TYPE d,
           "! affected users; role changes are then limited to assignments of these users
           users      TYPE ty_user_range,
           roles      TYPE ty_role_range,
           changed_by TYPE ty_user_range,
         END OF ty_selection.

  " what was changed
  CONSTANTS: BEGIN OF co_area,
               "! role assigned to or removed from a user
               assignment     TYPE string VALUE `assignment`,
               "! role created or deleted, reference role changed
               role           TYPE string VALUE `role`,
               "! authorization field value of a role
               value          TYPE string VALUE `value`,
               "! organizational level value of a role
               org_level      TYPE string VALUE `org_level`,
               "! authorization of a role
               authorization  TYPE string VALUE `authorization`,
               "! single role of a composite role
               composite      TYPE string VALUE `composite`,
               "! role menu entry
               menu           TYPE string VALUE `menu`,
               "! generated profile of a role
               profile        TYPE string VALUE `profile`,
               "! role description
               text           TYPE string VALUE `text`,
               "! user master record created (first entry of its logon data history)
               created        TYPE string VALUE `created`,
               user_group     TYPE string VALUE `user_group`,
               user_type      TYPE string VALUE `user_type`,
               lock           TYPE string VALUE `lock`,
               validity       TYPE string VALUE `validity`,
               "! password set by another user (administrator)
               password       TYPE string VALUE `password`,
               "! profile assigned directly to a user (not generated for a role)
               direct_profile TYPE string VALUE `direct_profile`,
             END OF co_area.

  CONSTANTS: BEGIN OF co_operation,
               added   TYPE string VALUE `added`,
               removed TYPE string VALUE `removed`,
               changed TYPE string VALUE `changed`,
             END OF co_operation.

  TYPES: BEGIN OF ty_role_change,
           role       TYPE agr_name,
           changed_by TYPE syuname,
           date       TYPE d,
           time       TYPE t,
           tcode      TYPE string,
           area       TYPE string,
           operation  TYPE string,
           "! assignment: user and validity
           user       TYPE syuname,
           valid_from TYPE d,
           valid_to   TYPE d,
           "! value: OBJECT FIELD; org_level: variable; authorization: object;
           "! composite: single role; menu: entry; profile: profile; text: language
           item       TYPE string,
           value_new  TYPE string,
           value_old  TYPE string,
         END OF ty_role_change,
         ty_role_changes TYPE STANDARD TABLE OF ty_role_change WITH EMPTY KEY.

  TYPES: BEGIN OF ty_user_change,
           user       TYPE syuname,
           "! user group at the time of the change; for profile changes the current one
           user_group TYPE xuclass,
           changed_by TYPE syuname,
           date       TYPE d,
           time       TYPE t,
           tcode      TYPE string,
           area       TYPE string,
           operation  TYPE string,
           "! direct_profile: profile
           item       TYPE string,
           value_new  TYPE string,
           value_old  TYPE string,
         END OF ty_user_change,
         ty_user_changes TYPE STANDARD TABLE OF ty_user_change WITH EMPTY KEY.

  "! Changes of roles (change document object PFCG) in the period: assignments, creation and
  "! deletion, reference role, authorizations, values, organizational levels, single roles of
  "! composite roles, menu, generated profile, description; oldest first
  METHODS get_role_changes
    IMPORTING !selection    TYPE ty_selection
    RETURNING VALUE(result) TYPE ty_role_changes.

  "! Changes of user master records in the period: logon data (USH02 - created, user group,
  "! user type, lock, validity, password set by another user) and profiles assigned directly
  "! (change document object IDENTITY, profiles not generated for a role); oldest first
  METHODS get_user_changes
    IMPORTING !selection    TYPE ty_selection
    RETURNING VALUE(result) TYPE ty_user_changes.

ENDINTERFACE.
