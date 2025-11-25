METHOD build_cabecera.

    DATA: lv_attr        TYPE string,
          lv_fecha       TYPE string,
          lv_metpag      TYPE string,
          lv_usocfdi     TYPE string,
          lv_nombre      TYPE string,
          lv_regfiscal   TYPE string,
          lv_domfiscal   TYPE string,
          lv_exportacion TYPE string,
          lv_tc_str      TYPE string,
          lv_cp_emisor   TYPE adrc-post_code1,
          lv_formapago   TYPE string.

    CLEAR lv_attr.

    " Fecha CFDI 4.0 → AAAA-MM-DDThh:mm:ss
    lv_fecha = |{ sy-datum+0(4) }-{ sy-datum+4(2) }-{ sy-datum+6(2) }T{ sy-uzeit+0(2) }:{ sy-uzeit+2(2) }:{ sy-uzeit+4(2) }|.

    " Trae datos del receptor
    me->recuperar_datos_cfdi_receptor(
      EXPORTING
        iv_kunnr     = is_head-kunnr
      IMPORTING
        ev_metpag    = lv_metpag
        ev_usocfdi   = lv_usocfdi
        ev_nombre    = lv_nombre
        ev_regfiscal = lv_regfiscal
        ev_domfiscal = lv_domfiscal
        ev_formapago = lv_formapago
    ).

    " --- Exportacion: requerido en 4.0; si no aplica, '01'
    lv_exportacion = COND string( WHEN is_head-exportacion IS INITIAL THEN '01' ELSE CONV string( is_head-exportacion ) ).

    " --- LugarExpedicion desde ADRC (o fallback)
    CLEAR lv_cp_emisor.
    IF is_head-bukrs IS NOT INITIAL.
      SELECT SINGLE a~post_code1
        INTO lv_cp_emisor
        FROM t001 AS t INNER JOIN adrc AS a ON a~addrnumber = t~adrnr
        WHERE t~bukrs = is_head-bukrs.
    ENDIF.
    IF lv_cp_emisor IS INITIAL.
      lv_cp_emisor = CONV adrc-post_code1( is_head-lugar_exp ).
    ENDIF.
    REPLACE ALL OCCURRENCES OF REGEX '[^0-9]' IN lv_cp_emisor WITH ''.
    IF strlen( lv_cp_emisor ) = 4.
      lv_cp_emisor = |0{ lv_cp_emisor }|.
    ELSEIF strlen( lv_cp_emisor ) > 5.
      lv_cp_emisor = lv_cp_emisor(5).
    ENDIF.

    " --- TipoCambio: si MXN omitir; de lo contrario informar
    CLEAR lv_tc_str.
    IF is_head-waers <> 'MXN'.
      lv_tc_str = |{ is_head-tipo_cambio DECIMALS = 6 }|.
      REPLACE ALL OCCURRENCES OF ',' IN lv_tc_str WITH '.'.
    ENDIF.

    " --- Recalcular SubTotal e IVAs desde mt_det (misma lógica que conceptos/totales)
    DATA(lv_subtotal)   = CONV decfloat34( 0 ).
    DATA(lv_tras_total) = CONV decfloat34( 0 ).

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
        ASSIGN COMPONENT 'KBETR'      OF STRUCTURE <d> TO <f_unit>.
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

      DATA(lv_base) = lv_qty * lv_unitp.
      lv_subtotal = lv_subtotal + lv_base.

      IF lv_tasa > 0 AND lv_base > 0.
        lv_tras_total = lv_tras_total + ( lv_base * lv_tasa ).
      ENDIF.
    ENDLOOP.

    " --- Formatos (punto decimal)
    DATA(lv_subt_str) = |{ lv_subtotal DECIMALS = 2 }|.
    DATA(lv_tot_str)  = |{ ( lv_subtotal + lv_tras_total ) DECIMALS = 2 }|.
    REPLACE ALL OCCURRENCES OF ',' IN lv_subt_str WITH '.'.
    REPLACE ALL OCCURRENCES OF ',' IN lv_tot_str  WITH '.'.

    " --- Nombre de emisor (igual al registrado ante SAT)
    DATA lv_nom_emisor TYPE string.
    lv_nom_emisor = me->get_param_value(
                      iv_program = 'ZCFDI40_MONITOR_LOG'
                      iv_param   = 'EMISOR'
                      iv_field   = 'NOMBRE'
                      iv_bukrs   = is_head-bukrs ).
    IF lv_nom_emisor IS INITIAL.
      SELECT SINGLE butxt INTO lv_nom_emisor FROM t001 WHERE bukrs = is_head-bukrs.
    ENDIF.

    " --- FormaPago solo si MetodoPago='PUE' y viene informada
    IF is_head-metodo_pago = 'PUE' AND lv_formapago IS NOT INITIAL.
      me->add_attr( EXPORTING i_name = 'FormaPago' i_val  = lv_formapago CHANGING  cv_attr = lv_attr ).
    ENDIF.

    " --- Atributos del nodo <cfdi:Comprobante>
    me->add_attr( EXPORTING i_name = 'xsi:schemaLocation'
                            i_val  = 'http://www.sat.gob.mx/cfd/4 http://www.sat.gob.mx/sitio_internet/cfd/4/cfdv40.xsd'
                            CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'xmlns:xsi'         i_val = 'http://www.w3.org/2001/XMLSchema-instance' CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'xmlns:cfdi'        i_val = 'http://www.sat.gob.mx/cfd/4'                CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Fecha'             i_val = lv_fecha                                    CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'MetodoPago'        i_val = CONV string( is_head-metodo_pago )          CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Exportacion'       i_val = lv_exportacion                              CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'TipoDeComprobante' i_val = CONV string( is_head-tipo_comp )            CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Serie'             i_val = CONV string( is_head-serie_xml )            CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Folio'             i_val = CONV string( is_head-folio_xml )            CHANGING cv_attr = lv_attr ).

    " >>> SubTotal y Total recalculados para cuadrar con conceptos
    me->add_attr( EXPORTING i_name = 'SubTotal'          i_val = lv_subt_str                                 CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Total'             i_val = lv_tot_str                                  CHANGING cv_attr = lv_attr ).

    me->add_attr( EXPORTING i_name = 'Moneda'            i_val = CONV string( is_head-waers )                CHANGING cv_attr = lv_attr ).
    IF lv_tc_str IS NOT INITIAL.
      me->add_attr( EXPORTING i_name = 'TipoCambio'      i_val = lv_tc_str                                   CHANGING cv_attr = lv_attr ).
    ENDIF.
    me->add_attr( EXPORTING i_name = 'LugarExpedicion'   i_val = CONV string( lv_cp_emisor )                 CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Version'           i_val = '4.0'                                       CHANGING cv_attr = lv_attr ).

    " Abrir nodo <cfdi:Comprobante>
    me->append_line( EXPORTING iv_line = |<cfdi:Comprobante { lv_attr }>| && '>' CHANGING ct_xml = ct_xml ).

    " Nodo <cfdi:Emisor>
    CLEAR lv_attr.
    me->add_attr( EXPORTING i_name = 'Nombre'        i_val = CONV string( lv_nom_emisor )  CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Rfc'           i_val = CONV string( is_head-rfc_emisor )     CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'RegimenFiscal' i_val = CONV string( is_head-regimen_fiscal ) CHANGING cv_attr = lv_attr ).
    me->append_line( EXPORTING iv_line = |<cfdi:Emisor { lv_attr }>| && '>' CHANGING ct_xml = ct_xml ).
    me->append_line( EXPORTING iv_line = '</cfdi:Emisor>' CHANGING ct_xml = ct_xml ).

    " Nodo <cfdi:Receptor>
    CLEAR lv_attr.
    me->add_attr( EXPORTING i_name = 'Nombre'                   i_val = lv_nombre                         CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'Rfc'                      i_val = CONV string( is_head-rfc_receptor ) CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'RegimenFiscalReceptor'    i_val = lv_regfiscal                      CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'DomicilioFiscalReceptor'  i_val = lv_domfiscal                      CHANGING cv_attr = lv_attr ).
    me->add_attr( EXPORTING i_name = 'UsoCFDI'                  i_val = lv_usocfdi                        CHANGING cv_attr = lv_attr ).
    me->append_line( EXPORTING iv_line = |<cfdi:Receptor { lv_attr }>| && '>' CHANGING ct_xml = ct_xml ).
    me->append_line( EXPORTING iv_line = '</cfdi:Receptor>' CHANGING ct_xml = ct_xml ).

  ENDMETHOD.
