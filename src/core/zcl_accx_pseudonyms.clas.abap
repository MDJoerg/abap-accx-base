"! <p class="shorttext synchronized">Access Explorer: keyed-hash user pseudonyms</p>
"! Pseudonym = prefix + first characters of HMAC-SHA256(key, client:user). The key
"! is a random value kept per client in table ZACCX_SECRET; it is created on first
"! use and committed with the request. No user-to-pseudonym mapping is stored: the
"! reverse lookup compares the pseudonym with those of all users of the client.
"! A customer class may redefine GET_KEY to keep the key somewhere else.
CLASS zcl_accx_pseudonyms DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_pseudonyms.

    CONSTANTS co_prefix     TYPE string VALUE `U-`.
    CONSTANTS co_hex_length TYPE i      VALUE 8.
    CONSTANTS co_key_name   TYPE zaccx_secret-name VALUE 'PSEUDONYM_KEY'.

  PROTECTED SECTION.
    "! Hex key (64 characters); created on first use
    METHODS get_key
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_accx_error.

    "! Ids of all users of the client
    METHODS all_users
      RETURNING VALUE(result) TYPE string_table.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_pair,
             pseudonym TYPE string,
             user      TYPE syuname,
           END OF ty_pair,
           ty_pairs TYPE SORTED TABLE OF ty_pair WITH NON-UNIQUE KEY pseudonym.

    DATA key       TYPE string.
    DATA pairs     TYPE ty_pairs.
    DATA pairs_set TYPE abap_bool.

    METHODS mac_of
      IMPORTING !secret       TYPE string
                !user         TYPE csequence
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_accx_error.

ENDCLASS.

CLASS zcl_accx_pseudonyms IMPLEMENTATION.

  METHOD zif_accx_pseudonyms~pseudonym_for.
    DATA(mac) = mac_of( secret = get_key( ) user = user ).
    result = co_prefix && mac(co_hex_length).
  ENDMETHOD.

  METHOD zif_accx_pseudonyms~is_pseudonym.
    DATA(value) = to_upper( condense( CONV string( text ) ) ).
    result = xsdbool( matches( val = value pcre = |^{ co_prefix }[0-9A-F]\{{ co_hex_length }\}$| ) ).
  ENDMETHOD.

  METHOD zif_accx_pseudonyms~user_for.
    DATA(wanted) = to_upper( condense( CONV string( pseudonym ) ) ).
    IF zif_accx_pseudonyms~is_pseudonym( wanted ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-invalid
                                          message = |'{ pseudonym }' is not a pseudonym.| ).
    ENDIF.
    IF pairs_set = abap_false.
      DATA(secret) = get_key( ).
      LOOP AT all_users( ) INTO DATA(user).
        DATA(mac) = mac_of( secret = secret user = user ).
        INSERT VALUE #( pseudonym = co_prefix && mac(co_hex_length) user = CONV #( user ) ) INTO TABLE pairs.
      ENDLOOP.
      pairs_set = abap_true.
    ENDIF.
    DATA(found) = VALUE string_table( FOR pair IN pairs WHERE ( pseudonym = wanted ) ( CONV string( pair-user ) ) ).
    CASE lines( found ).
      WHEN 0.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-not_found
                                            message = |Pseudonym { wanted } belongs to no user of this client.| ).
      WHEN 1.
        result = found[ 1 ].
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_accx_error( status  = zif_accx_types=>co_status-ambiguous
                                            message = |Pseudonym { wanted } belongs to { lines( found ) } users and cannot be resolved.| ).
    ENDCASE.
  ENDMETHOD.

  METHOD get_key.
    IF key IS NOT INITIAL.
      result = key.
      RETURN.
    ENDIF.
    SELECT SINGLE value FROM zaccx_secret WHERE name = @co_key_name INTO @DATA(stored).
    IF sy-subrc <> 0 OR stored IS INITIAL.
      DATA random TYPE xstring.
      CALL FUNCTION 'GENERATE_SEC_RANDOM'
        EXPORTING
          length         = 32
        IMPORTING
          random         = random
        EXCEPTIONS
          invalid_length = 1
          no_memory      = 2
          internal_error = 3
          OTHERS         = 4.
      IF sy-subrc <> 0 OR xstrlen( random ) <> 32.
        RAISE EXCEPTION NEW zcx_accx_error( message = `The pseudonym key could not be generated.` ).
      ENDIF.
      DATA(new_key) = CONV zaccx_secret-value( |{ random }| ).
      INSERT zaccx_secret FROM @( VALUE #( name = co_key_name value = new_key created_on = sy-datum ) ).
      " a parallel first call may have created the key already: use the stored one
      SELECT SINGLE value FROM zaccx_secret WHERE name = @co_key_name INTO @stored.
      IF sy-subrc <> 0 OR stored IS INITIAL.
        RAISE EXCEPTION NEW zcx_accx_error( message = `The pseudonym key could not be stored.` ).
      ENDIF.
    ENDIF.
    key    = condense( stored ).
    result = key.
  ENDMETHOD.

  METHOD all_users.
    SELECT bname FROM usr02 INTO TABLE @DATA(users).
    result = VALUE #( FOR u IN users ( CONV string( u-bname ) ) ).
  ENDMETHOD.

  METHOD mac_of.
    TRY.
        cl_abap_hmac=>calculate_hmac_for_char( EXPORTING if_algorithm   = 'SHA256'
                                                         if_key         = CONV xstring( secret )
                                                         if_data        = |{ sy-mandt }:{ to_upper( condense( CONV string( user ) ) ) }|
                                               IMPORTING ef_hmacstring = result ).
      CATCH cx_abap_message_digest INTO DATA(error).
        RAISE EXCEPTION NEW zcx_accx_error( message = |Pseudonym could not be computed: { error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
