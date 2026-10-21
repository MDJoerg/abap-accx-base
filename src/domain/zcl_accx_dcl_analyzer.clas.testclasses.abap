CLASS ltc_dcl_analyzer DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS source RETURNING VALUE(result) TYPE string.

    METHODS parse_grants        FOR TESTING.
    METHODS protection_statuses FOR TESTING.
    METHODS any_open_grant_wins FOR TESTING.
    METHODS merge_and_text      FOR TESTING.
ENDCLASS.

CLASS ltc_dcl_analyzer IMPLEMENTATION.

  METHOD source.
    result = |@EndUserText.label: 'Test'\n| &&
             |define role ZR_A \{\n| &&
             |  // grant select on ZI_COMMENTED;\n| &&
             |  grant select on zi_a\n| &&
             |    where ( CompanyCode ) = aspect pfcg_auth( F_BKPF_BUK, BUKRS, ACTVT = '03' )\n| &&
             |      and ( ) = aspect pfcg_auth( S_TABU_NAM, actvt='03', table='ZT' )\n| &&
             |      or CreatedBy ?= aspect user;\n| &&
             |  grant select on ZI_B;\n| &&
             |  grant select on ZI_C where Status = 'A';\n| &&
             |  grant select on ZI_D where inheriting conditions from entity ZI_A;\n| &&
             |  /* grant select on ZI_BLOCK; */\n| &&
             |\}\n|.
  ENDMETHOD.

  METHOD parse_grants.
    DATA(grants) = zcl_accx_dcl_analyzer=>parse( source( ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZI_A` ) ( `ZI_B` ) ( `ZI_C` ) ( `ZI_D` ) )
                                        act = VALUE string_table( FOR g IN grants ( g-entity ) ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zcl_accx_dcl_analyzer=>ty_conditions(
              ( kind = `pfcg` elements = `CompanyCode` object = `F_BKPF_BUK` fields = VALUE #( ( `BUKRS` ) ) filters = VALUE #( ( `ACTVT = '03'` ) ) )
              ( kind = `pfcg` object = `S_TABU_NAM` filters = VALUE #( ( `ACTVT = '03'` ) ( `TABLE = 'ZT'` ) ) )
              ( kind = `user` object = `USER` ) )
      act = grants[ 1 ]-conditions ).
    cl_abap_unit_assert=>assert_false( grants[ 1 ]-unconditional ).
    cl_abap_unit_assert=>assert_true( grants[ 2 ]-unconditional ).
    cl_abap_unit_assert=>assert_true( grants[ 3 ]-static_filter ).
    cl_abap_unit_assert=>assert_initial( grants[ 3 ]-conditions ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_dcl_analyzer=>ty_conditions( ( kind = `inherit` object = `ZI_A` ) )
                                        act = grants[ 4 ]-conditions ).
  ENDMETHOD.

  METHOD protection_statuses.
    DATA(grants) = zcl_accx_dcl_analyzer=>parse( source( ) ).
    DATA(cases) = VALUE string_table( ( `ZI_A/VIEWENTITY/CHECK/protected/X` )
                                      ( `ZI_B/VIEWENTITY/CHECK/full_access/ ` )
                                      ( `ZI_C//NOT_REQUIRED/static_filter/ ` )
                                      ( `ZI_D/PROJ_STD//protected/X` )
                                      ( `ZI_X/VIEWENTITY/NOT_REQUIRED/no_role/ ` )
                                      ( `ZI_X/VIEWENTITY//no_role/ ` )
                                      ( `ZI_X/VIEWENTITY/MANDATORY/no_access/X` )
                                      ( `ZI_A/VIEWENTITY/NOT_ALLOWED/not_allowed/ ` )
                                      ( `ZI_X/VIEWENTITY/PRIVILEGED_ONLY/privileged_only/X` )
                                      ( `ZI_X/CUSTOM//custom/ ` )
                                      ( `ZI_X/ABSTRACT//abstract/X` ) ).
    LOOP AT cases INTO DATA(case).
      SPLIT case AT `/` INTO DATA(name) DATA(kind) DATA(check) DATA(status) DATA(protected).
      DATA(result) = zcl_accx_dcl_analyzer=>protection( entity = VALUE #( name = name kind = kind authorization_check = check )
                                                        grants = grants ).
      cl_abap_unit_assert=>assert_equals( exp = status act = result-status msg = case ).
      cl_abap_unit_assert=>assert_equals( exp = condense( protected ) act = CONV string( result-protected ) msg = case ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_char_cp( exp = `authorizationCheck ##NOT_REQUIRED and no DCL role*`
                                         act = zcl_accx_dcl_analyzer=>protection( entity = VALUE #( name = `ZI_X` authorization_check = `NOT_REQUIRED` )
                                                                                 grants = grants )-reason ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*its DCL roles are ignored*`
                                         act = zcl_accx_dcl_analyzer=>protection( entity = VALUE #( name = `zi_a` authorization_check = `NOT_ALLOWED` )
                                                                                 grants = grants )-reason ).
  ENDMETHOD.

  METHOD any_open_grant_wins.
    " roles are combined with OR: one grant without condition opens all rows
    DATA(grants) = zcl_accx_dcl_analyzer=>parse( `define role R1 { grant select on ZI_A where ( X ) = aspect pfcg_auth( Z_OBJ, F ); }` &&
                                                 `define role R2 { grant select on ZI_A; }` ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( grants ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zcl_accx_dcl_analyzer=>co_status-full_access
      act = zcl_accx_dcl_analyzer=>protection( entity = VALUE #( name = `ZI_A` kind = `VIEWENTITY` ) grants = grants )-status ).
  ENDMETHOD.

  METHOD merge_and_text.
    DATA(merged) = zcl_accx_dcl_analyzer=>merge( VALUE #(
                     ( kind = `pfcg` elements = `A` object = `Z_OBJ` fields = VALUE #( ( `F` ) ) )
                     ( kind = `pfcg` elements = `B` object = `Z_OBJ` fields = VALUE #( ( `F` ) ) )
                     ( kind = `pfcg` elements = `C` object = `Z_OBJ` fields = VALUE #( ( `F` ) ) )
                     ( kind = `pfcg` elements = `D` object = `Z_OBJ` fields = VALUE #( ( `F` ) ) )
                     ( kind = `pfcg` elements = `E` object = `Z_OBJ` fields = VALUE #( ( `G` ) ) )
                     ( kind = `inherit` object = `ZI_A` ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( merged ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Z_OBJ: A, B and 2 more = F` act = zcl_accx_dcl_analyzer=>condition_text( merged[ 1 ] ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Z_OBJ: E = G` act = zcl_accx_dcl_analyzer=>condition_text( merged[ 2 ] ) ).
    cl_abap_unit_assert=>assert_equals( exp = `conditions inherited from ZI_A` act = zcl_accx_dcl_analyzer=>condition_text( merged[ 3 ] ) ).
    cl_abap_unit_assert=>assert_equals( exp = `S_TABU_NAM: authorization check only (ACTVT = '03')`
                                        act = zcl_accx_dcl_analyzer=>condition_text( VALUE #( kind = `pfcg` object = `S_TABU_NAM`
                                                                                              filters = VALUE #( ( `ACTVT = '03'` ) ) ) ) ).
  ENDMETHOD.

ENDCLASS.
