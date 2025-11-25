METHOD build_conceptos.
  DATA: lv_attr_c TYPE string,
        lv_attr_i TYPE string.

  me->append_line( EXPORTING iv_line = '<cfdi:Conceptos>' CHANGING ct_xml = ct_xml ).

  FIELD-SYMBOLS: <d>       TYPE any,
                 <f_qty>   TYPE any,
                 <f_amt>   TYPE any,
                 <f_unit>  TYPE any,
                 <f_desc>  TYPE any,
                 <f_matnr> TYPE any,
                 <f_udm>   TYPE any,
                 <f_tasa>  TYPE any,
                 <f_noid>  TYPE any,
                 <f_kpein> TYPE any.

  LOOP AT mt_det ASSIGNING <d>.
    CLEAR: lv_attr_c, lv_attr_i.

    "---- Bind de campos
    UNASSIGN <f_qty>.   ASSIGN COMPONENT 'CANTIDAD' OF STRUCTURE <d> TO <f_qty>.
    IF <f_qty> IS NOT ASSIGNED.   ASSIGN COMPONENT 'FKIMG'  OF STRUCTURE <d> TO <f_qty>.   ENDIF.
    IF <f_qty> IS NOT ASSIGNED.   ASSIGN COMPONENT 'MENGE'  OF STRUCTURE <d> TO <f_qty>.   ENDIF.

    UNASSIGN <f_amt>.   ASSIGN COMPONENT 'IMPORTE'  OF STRUCTURE <d> TO <f_amt>.
    IF <f_amt> IS NOT ASSIGNED.   ASSIGN COMPONENT 'NETWR'  OF STRUCTURE <d> TO <f_amt>.   ENDIF.
    IF <f_amt> IS NOT ASSIGNED.   ASSIGN COMPONENT 'DMBTR'  OF STRUCTURE <d> TO <f_amt>.   ENDIF.
    IF <f_amt> IS NOT ASSIGNED.   ASSIGN COMPONENT 'TOTAL'  OF STRUCTURE <d> TO <f_amt>.   ENDIF.

    DATA(lv_unit_is_kbetr) = abap_false.
    UNASSIGN <f_unit>.
    ASSIGN COMPONENT 'VALOR_UNITARIO' OF STRUCTURE <d> TO <f_unit>.
    IF <f_unit> IS NOT ASSIGNED. ASSIGN COMPONENT 'VALOR_UNIT' OF STRUCTURE <d> TO <f_unit>. ENDIF.
    IF <f_unit> IS NOT ASSIGNED. ASSIGN COMPONENT 'PUNIT'      OF STRUCTURE <d> TO <f_unit>. ENDIF.
    IF <f_unit> IS NOT ASSIGNED.
      ASSIGN COMPONENT 'KBETR' OF STRUCTURE <d> TO <f_unit>.
      IF <f_unit> IS ASSIGNED. lv_unit_is_kbetr = abap_true. ENDIF.
    ENDIF.

    UNASSIGN <f_kpein>. ASSIGN COMPONENT 'KPEIN' OF STRUCTURE <d> TO <f_kpein>.

    UNASSIGN <f_tasa>.  ASSIGN COMPONENT 'TASAOCUOTA' OF STRUCTURE <d> TO <f_tasa>.
    IF <f_tasa> IS NOT ASSIGNED. ASSIGN COMPONENT 'TASA' OF STRUCTURE <d> TO <f_tasa>. ENDIF.

    UNASSIGN <f_noid>.  ASSIGN COMPONENT 'NOIDENTIFICACION' OF STRUCTURE <d> TO <f_noid>.
    IF <f_noid> IS NOT ASSIGNED.  ASSIGN COMPONENT 'NO_ID'   OF STRUCTURE <d> TO <f_noid>. ENDIF.
    IF <f_noid> IS NOT ASSIGNED.  ASSIGN COMPONENT 'NOIDENT' OF STRUCTURE <d> TO <f_noid>. ENDIF.

    "---- Valores numéricos
    DATA(lv_qty)    = CONV decfloat34( 0 ).
    DATA(lv_amt_in) = CONV decfloat34( 0 ). " NO se usará para @Importe salvo emergencia
    DATA(lv_unitp)  = CONV decfloat34( 0 ).
    DATA(lv_tasa)   = CONV decfloat34( 0 ).

    IF <f_qty>  IS ASSIGNED AND <f_qty>  IS NOT INITIAL. lv_qty    = CONV decfloat34( <f_qty> ).  ENDIF.
    IF <f_amt>  IS ASSIGNED AND <f_amt>  IS NOT INITIAL. lv_amt_in = CONV decfloat34( <f_amt> ).  ENDIF.
    IF <f_unit> IS ASSIGNED AND <f_unit> IS NOT INITIAL. lv_unitp  = CONV decfloat34( <f_unit> ). ENDIF.
    IF <f_tasa> IS ASSIGNED AND <f_tasa> IS NOT INITIAL. lv_tasa   = CONV decfloat34( <f_tasa> ). ENDIF.

    " Normaliza KBETR con KPEIN
    IF lv_unit_is_kbetr = abap_true AND <f_kpein> IS ASSIGNED AND <f_kpein> IS NOT INITIAL.
      DATA(lv_kpein) = CONV decfloat34( <f_kpein> ).
      IF lv_kpein > 0. lv_unitp = lv_unitp / lv_kpein. ENDIF.
    ENDIF.

    " Reglas básicas
    IF lv_qty <= 0. lv_qty = 1. ENDIF.

    " *** Importe del concepto: SIEMPRE Cantidad * ValorUnitario ***
    DATA(lv_imp_num) = lv_qty * lv_unitp.
    IF lv_imp_num = 0 AND lv_amt_in > 0.
      " Fallback solo si no hay precio válido
      lv_imp_num = lv_amt_in.
      IF lv_unitp = 0. lv_unitp = lv_imp_num / lv_qty. ENDIF.
    ENDIF.

    " Normaliza tasa ≈ 16%
    IF lv_tasa > '0.159999' AND lv_tasa < '0.160001'.
      lv_tasa = '0.16'.
    ENDIF.

    "---- Material/Descripción (idéntico a v4; omitido por brevedad salvo lo esencial)
    DATA lv_desc TYPE string.
    DATA lv_matnr TYPE matnr.
    DATA lv_noid  TYPE string.
    FIELD-SYMBOLS <f_desc> TYPE any.
    ASSIGN COMPONENT 'DESCRIPCION' OF STRUCTURE <d> TO <f_desc>.
    IF <f_desc> IS ASSIGNED AND <f_desc> IS NOT INITIAL.
      lv_desc = <f_desc>.
    ELSE.
      ASSIGN COMPONENT 'MATNR' OF STRUCTURE <d> TO <f_desc>.
      IF <f_desc> IS ASSIGNED. lv_desc = <f_desc>. ENDIF.
    ENDIF.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_desc WITH ' '.
    CONDENSE lv_desc.

    "---- ObjetoImp
    DATA(lv_obj_imp) = COND string( WHEN lv_tasa > 0 THEN '02' ELSE '01' ).

    "---- Strings
    DATA(lv_qty_s) = |{ lv_qty    DECIMALS = 6 }|.
    DATA(lv_vu_s)  = |{ lv_unitp  DECIMALS = 6 }|.
    DATA(lv_imp_s) = |{ lv_imp_num DECIMALS = 2 }|.
    REPLACE ALL OCCURRENCES OF ',' IN lv_qty_s WITH '.'.
    REPLACE ALL OCCURRENCES OF ',' IN lv_vu_s  WITH '.'.
    REPLACE ALL OCCURRENCES OF ',' IN lv_imp_s WITH '.'.

    " Concepto
    me->add_attr( EXPORTING i_name = 'Cantidad'      i_val = lv_qty_s  CHANGING cv_attr = lv_attr_c ).
    me->add_attr( EXPORTING i_name = 'Descripcion'   i_val = lv_desc   CHANGING cv_attr = lv_attr_c ).
    me->add_attr( EXPORTING i_name = 'ValorUnitario' i_val = lv_vu_s   CHANGING cv_attr = lv_attr_c ).
    me->add_attr( EXPORTING i_name = 'Importe'       i_val = lv_imp_s  CHANGING cv_attr = lv_attr_c ).
    me->add_attr( EXPORTING i_name = 'ObjetoImp'     i_val = lv_obj_imp CHANGING cv_attr = lv_attr_c ).
    me->append_line( EXPORTING iv_line = |<cfdi:Concepto { lv_attr_c }>| && '>' CHANGING ct_xml = ct_xml ).

    " Impuestos por concepto (solo si tasa > 0)
    IF lv_tasa > 0 AND lv_imp_num > 0.
      DATA(lv_base_s) = lv_imp_s. " misma cifra
      DATA(lv_iva_num) = lv_imp_num * lv_tasa.
      DATA(lv_iva_s) = |{ lv_iva_num DECIMALS = 2 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_iva_s WITH '.'.
      DATA(lv_tasa_s) = |{ lv_tasa DECIMALS = 6 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_tasa_s WITH '.'.

      me->append_line( EXPORTING iv_line = '<cfdi:Impuestos>' CHANGING ct_xml = ct_xml ).
      me->append_line( EXPORTING iv_line = '<cfdi:Traslados>' CHANGING ct_xml = ct_xml ).

      CLEAR lv_attr_i.
      me->add_attr( EXPORTING i_name = 'Base'       i_val = lv_base_s CHANGING cv_attr = lv_attr_i ).
      me->add_attr( EXPORTING i_name = 'Impuesto'   i_val = '002'     CHANGING cv_attr = lv_attr_i ).
      me->add_attr( EXPORTING i_name = 'TipoFactor' i_val = 'Tasa'    CHANGING cv_attr = lv_attr_i ).
      me->add_attr( EXPORTING i_name = 'TasaOCuota' i_val = lv_tasa_s CHANGING cv_attr = lv_attr_i ).
      me->add_attr( EXPORTING i_name = 'Importe'    i_val = lv_iva_s  CHANGING cv_attr = lv_attr_i ).
      me->append_line( EXPORTING iv_line = |<cfdi:Traslado { lv_attr_i }/>| CHANGING ct_xml = ct_xml ).

      me->append_line( EXPORTING iv_line = '</cfdi:Traslados>' CHANGING ct_xml = ct_xml ).
      me->append_line( EXPORTING iv_line = '</cfdi:Impuestos>' CHANGING ct_xml = ct_xml ).
    ENDIF.

    me->append_line( EXPORTING iv_line = '</cfdi:Concepto>' CHANGING ct_xml = ct_xml ).
  ENDLOOP.

  me->append_line( EXPORTING iv_line = '</cfdi:Conceptos>' CHANGING ct_xml = ct_xml ).
ENDMETHOD.
