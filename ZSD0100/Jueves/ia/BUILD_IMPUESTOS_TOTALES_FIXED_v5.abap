METHOD build_impuestos_totales.
  " * IMPORTING: is_head TYPE zet_head_40  iv_version TYPE string
  " * CHANGING : ct_xml  TYPE string

  TYPES: BEGIN OF ty_tot,
           tasa6   TYPE string,      " clave: TasaOCuota con 6 decimales, p.ej. '0.160000'
           base    TYPE decfloat34,  " suma de bases
           importe TYPE decfloat34,  " suma de IVAs
         END OF ty_tot.

  DATA: lt_tot  TYPE HASHED TABLE OF ty_tot WITH UNIQUE KEY tasa6,
        ls_tot  TYPE ty_tot,
        lv_attr TYPE string.

  FIELD-SYMBOLS: <d>       TYPE any,
                 <f_qty>   TYPE any,
                 <f_unit>  TYPE any,
                 <f_tasa>  TYPE any,
                 <f_kpein> TYPE any.

  LOOP AT mt_det ASSIGNING <d>.
    UNASSIGN: <f_qty>, <f_unit>, <f_tasa>, <f_kpein>.
    ASSIGN COMPONENT 'CANTIDAD' OF STRUCTURE <d> TO <f_qty>.
    IF <f_qty> IS NOT ASSIGNED. ASSIGN COMPONENT 'FKIMG' OF STRUCTURE <d> TO <f_qty>. ENDIF.
    IF <f_qty> IS NOT ASSIGNED. ASSIGN COMPONENT 'MENGE' OF STRUCTURE <d> TO <f_qty>. ENDIF.

    DATA(lv_unit_is_kbetr) = abap_false.
    ASSIGN COMPONENT 'VALOR_UNITARIO' OF STRUCTURE <d> TO <f_unit>.
    IF <f_unit> IS NOT ASSIGNED. ASSIGN COMPONENT 'VALOR_UNIT' OF STRUCTURE <d> TO <f_unit>. ENDIF.
    IF <f_unit> IS NOT ASSIGNED. ASSIGN COMPONENT 'PUNIT'      OF STRUCTURE <d> TO <f_unit>. ENDIF.
    IF <f_unit> IS NOT ASSIGNED.
      ASSIGN COMPONENT 'KBETR' OF STRUCTURE <d> TO <f_unit>.
      IF <f_unit> IS ASSIGNED. lv_unit_is_kbetr = abap_true. ENDIF.
    ENDIF.
    ASSIGN COMPONENT 'KPEIN' OF STRUCTURE <d> TO <f_kpein>.

    ASSIGN COMPONENT 'TASAOCUOTA' OF STRUCTURE <d> TO <f_tasa>.
    IF <f_tasa> IS NOT ASSIGNED. ASSIGN COMPONENT 'TASA' OF STRUCTURE <d> TO <f_tasa>. ENDIF.

    DATA(lv_qty)   = CONV decfloat34( 0 ).
    DATA(lv_unitp) = CONV decfloat34( 0 ).
    DATA(lv_tasa)  = CONV decfloat34( 0 ).

    IF <f_qty>  IS ASSIGNED AND <f_qty>  IS NOT INITIAL. lv_qty   = CONV decfloat34( <f_qty> ).  ENDIF.
    IF <f_unit> IS ASSIGNED AND <f_unit> IS NOT INITIAL. lv_unitp = CONV decfloat34( <f_unit> ). ENDIF.
    IF <f_tasa> IS ASSIGNED AND <f_tasa> IS NOT INITIAL. lv_tasa  = CONV decfloat34( <f_tasa> ). ENDIF.

    IF lv_qty <= 0. lv_qty = 1. ENDIF.

    IF lv_unit_is_kbetr = abap_true AND <f_kpein> IS ASSIGNED AND <f_kpein> IS NOT INITIAL.
      DATA(lv_kpein) = CONV decfloat34( <f_kpein> ).
      IF lv_kpein > 0. lv_unitp = lv_unitp / lv_kpein. ENDIF.
    ENDIF.

    IF lv_tasa > '0.159999' AND lv_tasa < '0.160001'.
      lv_tasa = '0.16'.
    ENDIF.

    " Base por línea
    DATA(lv_base) = lv_qty * lv_unitp.

    " Acumular solo conceptos con tasa > 0
    IF lv_base > 0 AND lv_tasa > 0.
      DATA(lv_tasa6) = |{ lv_tasa DECIMALS = 6 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_tasa6 WITH '.'.
      DATA(lv_iva) = lv_base * lv_tasa.

      CLEAR ls_tot.
      ls_tot-tasa6   = lv_tasa6.
      ls_tot-base    = lv_base.
      ls_tot-importe = lv_iva.
      COLLECT ls_tot INTO lt_tot.
    ENDIF.
  ENDLOOP.

  " Nodo Impuestos a nivel comprobante (solo si hay traslados)
  DATA(lv_tot_tras) = CONV decfloat34( 0 ).
  LOOP AT lt_tot INTO ls_tot.
    lv_tot_tras = lv_tot_tras + ls_tot-importe.
  ENDLOOP.

  IF lv_tot_tras > 0.
    DATA(lv_tot_tras_s) = |{ lv_tot_tras DECIMALS = 2 }|.
    REPLACE ALL OCCURRENCES OF ',' IN lv_tot_tras_s WITH '.'.

    CLEAR lv_attr.
    me->add_attr( EXPORTING i_name = 'TotalImpuestosTrasladados' i_val = lv_tot_tras_s CHANGING cv_attr = lv_attr ).
    me->append_line( EXPORTING iv_line = |<cfdi:Impuestos { lv_attr }>| && '>' CHANGING ct_xml = ct_xml ).

    me->append_line( EXPORTING iv_line = '<cfdi:Traslados>' CHANGING ct_xml = ct_xml ).

    LOOP AT lt_tot INTO ls_tot.
      DATA(lv_base_s) = |{ ls_tot-base    DECIMALS = 2 }|.
      DATA(lv_iva_s)  = |{ ls_tot-importe DECIMALS = 2 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_base_s WITH '.'.
      REPLACE ALL OCCURRENCES OF ',' IN lv_iva_s  WITH '.'.

      CLEAR lv_attr.
      me->add_attr( EXPORTING i_name = 'Base'       i_val = lv_base_s    CHANGING cv_attr = lv_attr ).
      me->add_attr( EXPORTING i_name = 'Impuesto'   i_val = '002'        CHANGING cv_attr = lv_attr ).
      me->add_attr( EXPORTING i_name = 'TipoFactor' i_val = 'Tasa'       CHANGING cv_attr = lv_attr ).
      me->add_attr( EXPORTING i_name = 'TasaOCuota' i_val = ls_tot-tasa6 CHANGING cv_attr = lv_attr ).
      me->add_attr( EXPORTING i_name = 'Importe'    i_val = lv_iva_s     CHANGING cv_attr = lv_attr ).

      me->append_line( EXPORTING iv_line = |<cfdi:Traslado { lv_attr }/>| CHANGING ct_xml = ct_xml ).
    ENDLOOP.

    me->append_line( EXPORTING iv_line = '</cfdi:Traslados>' CHANGING ct_xml = ct_xml ).
    me->append_line( EXPORTING iv_line = '</cfdi:Impuestos>' CHANGING ct_xml = ct_xml ).
  ENDIF.
ENDMETHOD.
