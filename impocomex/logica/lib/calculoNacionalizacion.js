// Calculo Nacionalizacion - Verificacion IMPO COMEX 3.0
// Replica logica del Excel "Calculo Nacionalizacion VACIO.xlsx"
// 3 modos: LCL (Consolidada) / FCL_20 (Full Container 20') / AVION

// ========== Aliquotas NCM (defaults; override por NCM en DB) ==========
export const ALIQUOTAS_DEFAULT = {
  derecho_imp: 18,
  tasa_estad: 3,
  iva: 21,
  iva_adic: 20,
  ganancias: 6,
  ntl: 0,                       // Imp Pais (suspendido)
  inal: false,
};

// IIBB rate global (depende inscripcion importador, no del NCM)
export const IIBB_DEFAULT_PCT = 0;          // 0% si Exento, 0.3516% si Sujeto + Convenio Multilateral
export const ARANCEL_SIM_GLOBAL = 10;       // $10 USD una sola vez por despacho

// Aliquotas conocidas por NCM (extraido de despachos historicos)
export const ALIQUOTAS_NCM = {
  '7323.93.00.910T': { ...ALIQUOTAS_DEFAULT, derecho_imp: 35, inal: true },  // acero inox alimentos
  '8205.51.00.300Z': { ...ALIQUOTAS_DEFAULT },                               // ralladores
  '8205.51.00.400E': { ...ALIQUOTAS_DEFAULT },                               // sacacorchos
  '8205.51.00.900G': { ...ALIQUOTAS_DEFAULT },                               // herramientas mano
  '8210.00.90.400N': { ...ALIQUOTAS_DEFAULT },                               // abrelatas mecanicos
  '8210.00.90.900Q': { ...ALIQUOTAS_DEFAULT },                               // aparatos mecanicos cocina
};

// ========== Tabla Libre Circulacion (ARANCELES INAL en pesos) ==========
export const LIBRE_CIRCULACION = [
  { hasta_pesos:        500000, arancel_pesos:   52500, pct: 10.50 },
  { hasta_pesos:       5000000, arancel_pesos:  225000, pct:  4.50 },
  { hasta_pesos:      15000000, arancel_pesos:  675000, pct:  4.50 },
  { hasta_pesos:      50000000, arancel_pesos: 1200000, pct:  2.40 },
  { hasta_pesos: Infinity,      arancel_pesos: 1425000, pct:  0    },
];
export const SIQAT_HONORARIOS_PCT = 30;            // 30% del arancel
export const SIQAT_HONORARIOS_MIN_PESOS = 69800;
export const IVA_HONORARIOS = 21;

// ========== Tarifas flete (USD) ==========
export const TARIFAS_FLETE = {
  LCL: {
    'Costo Flete':         { unidad: 'CBM', precio: 40 },   // override por proveedor
    'Desconsolidado':      { unidad: 'CBM', precio: 25 },
    'Log Fee':             { unidad: 'BL',  precio: 35 },
    'Manejo':              { unidad: 'BL',  precio: 90 },
    'AGP':                 { unidad: 'TN',  precio: 4 },
    'Entrega Dep Fiscal':  { unidad: 'BL',  precio: 519 },
    'Gastos Dep Fiscal':   { unidad: 'BL',  precio: 480 },
  },
  FCL_20: {
    'Container 20P':       { unidad: 'FIJO', precio: 2000 }, // se override
    'Maritima':            { unidad: 'FIJO', precio: 750 },
    'Terminal':            { unidad: 'FIJO', precio: 800 },
  },
  AVION: {
    'Costo Avion':         { unidad: 'FIJO', precio: 0 },   // requiere input
    'Certificacion Fedex': { unidad: 'FIJO', precio: 0 },
  },
};

// ========== Tarifas Despachante ==========
export const TARIFAS_DESPACHANTE = {
  LCL: {
    'Honorarios':  { tipo: '%', valor: 1, minimo_usd: 300 },
    'Gastos desp': { tipo: 'FIJO', valor: 120 },
    'SEDI':        { tipo: 'FIJO', valor: 0 },
    'Digital':     { tipo: 'FIJO', valor: 30 },
  },
  FCL_20: {
    'Honorarios':  { tipo: '%', valor: 1, minimo_usd: 300 },
    'Gastos desp': { tipo: 'FIJO', valor: 150 },
    'SIRA':        { tipo: 'FIJO', valor: 100 },
    'Digital':     { tipo: 'FIJO', valor: 30 },
  },
  AVION: {
    'Gestion Comex':   { tipo: 'FIJO', valor: 85, iva: 21 },
    'Tasa Desembolso': { tipo: 'FIJO', valor: 50, iva: 21 },
  },
};

// ========== Tarifas varios ==========
export const TARIFAS_VARIOS = {
  LCL:    { 'Flete a deposito': 30,  'Gastos bancarios': 40 },
  FCL_20: { 'Flete a deposito': 150, 'Gastos bancarios': 40 },
  AVION:  { },
};

// ========== Helpers ==========
function lookupAliquotas(ncm) {
  return ALIQUOTAS_NCM[ncm] || ALIQUOTAS_DEFAULT;
}

function calcularLibreCirculacion(fobConInalUsd, tipoCambio) {
  if (!fobConInalUsd || fobConInalUsd <= 0) {
    return { arancel_pesos: 0, arancel_usd: 0, honorarios_pesos: 0, honorarios_usd: 0, iva_honorarios_usd: 0, total_usd: 0 };
  }
  const fobPesos = fobConInalUsd * tipoCambio;
  const tramo = LIBRE_CIRCULACION.find(t => fobPesos <= t.hasta_pesos);
  const arancel_pesos = tramo.arancel_pesos;
  const honorarios_pesos = Math.max(arancel_pesos * SIQAT_HONORARIOS_PCT / 100, SIQAT_HONORARIOS_MIN_PESOS);
  const iva_honorarios_pesos = honorarios_pesos * IVA_HONORARIOS / 100;
  return {
    arancel_pesos,
    arancel_usd: arancel_pesos / tipoCambio,
    honorarios_pesos,
    honorarios_usd: honorarios_pesos / tipoCambio,
    iva_honorarios_pesos,
    iva_honorarios_usd: iva_honorarios_pesos / tipoCambio,
    total_usd: (arancel_pesos + honorarios_pesos + iva_honorarios_pesos) / tipoCambio,
  };
}

// ========== Calculo Flete por modo ==========
function calcularFlete(modo, params) {
  const t = TARIFAS_FLETE[modo];
  const items = [];
  if (modo === 'LCL') {
    const cbm = params.cbm || 0;
    const tn = params.tn || 0;
    const flete_cbm_override = params.flete_cbm_usd_override; // si proveedor cobra distinto a $40
    items.push({ concepto: 'Costo Flete',        usd: cbm * (flete_cbm_override ?? t['Costo Flete'].precio) });
    items.push({ concepto: 'Desconsolidado',     usd: cbm * t['Desconsolidado'].precio });
    items.push({ concepto: 'Log Fee',            usd: t['Log Fee'].precio });
    items.push({ concepto: 'Manejo',             usd: t['Manejo'].precio });
    items.push({ concepto: 'AGP',                usd: tn * t['AGP'].precio });
    items.push({ concepto: 'Entrega Dep Fiscal', usd: t['Entrega Dep Fiscal'].precio });
    items.push({ concepto: 'Gastos Dep Fiscal',  usd: t['Gastos Dep Fiscal'].precio });
  } else if (modo === 'FCL_20') {
    const container_override = params.container_usd_override;
    items.push({ concepto: 'Container 20P', usd: container_override ?? t['Container 20P'].precio });
    items.push({ concepto: 'Maritima',      usd: t['Maritima'].precio });
    items.push({ concepto: 'Terminal',      usd: t['Terminal'].precio });
  } else if (modo === 'AVION') {
    items.push({ concepto: 'Costo Avion',         usd: params.costo_avion_usd || 0 });
    items.push({ concepto: 'Certificacion Fedex', usd: params.certif_fedex_usd || 0 });
  }
  const total = items.reduce((s,i) => s + i.usd, 0);
  return { items, total };
}

// ========== Calculo Despachante ==========
function calcularDespachante(modo, fobUsd) {
  const t = TARIFAS_DESPACHANTE[modo];
  const items = [];
  for (const [concepto, def] of Object.entries(t)) {
    let usd;
    if (def.tipo === '%') {
      usd = Math.max(fobUsd * def.valor / 100, def.minimo_usd || 0);
    } else {
      usd = def.valor;
    }
    items.push({ concepto, usd, iva_usd: def.iva ? usd * def.iva / 100 : 0 });
  }
  const total = items.reduce((s,i) => s + i.usd, 0);
  const total_iva = items.reduce((s,i) => s + (i.iva_usd||0), 0);
  return { items, total, total_iva };
}

// ========== Calculo Varios ==========
function calcularVarios(modo) {
  const t = TARIFAS_VARIOS[modo] || {};
  const items = Object.entries(t).map(([concepto, usd]) => ({ concepto, usd }));
  return { items, total: items.reduce((s,i) => s + i.usd, 0) };
}

// ========== MAIN: Calculo Nacionalizacion ==========
/**
 * @param {Object} params
 * @param {'LCL'|'FCL_20'|'AVION'} params.modo
 * @param {Array<{codigo, descripcion, ncm, fob_usd, cantidad, peso_kg?, cbm?}>} params.items
 * @param {number} params.cbm_total            (total carga, m3)
 * @param {number} params.tn_total             (total carga, toneladas)
 * @param {number} [params.fob_con_inal_usd]   (FOB de items con INAL para Libre Circulacion)
 * @param {number} [params.tipo_cambio]        (TC peso/usd para Libre Circ y reportes)
 * @param {number} [params.flete_cbm_usd_override]
 * @param {number} [params.container_usd_override]
 * @param {number} [params.flete_real_usd]     (si lo declaro despachante, usar este)
 * @param {number} [params.seguro_real_usd]
 * @param {boolean} [params.prorrateo_por_peso] (default false → por FOB)
 * @returns {Object} desglose completo
 */
export function calcularNacionalizacion(params) {
  const {
    modo,
    items,
    cbm_total,
    tn_total,
    fob_con_inal_usd = 0,
    tipo_cambio = 1200,
    flete_real_usd,
    seguro_real_usd,
    prorrateo_por_peso = false,
  } = params;

  // 1. FOB total
  const FOB_total = items.reduce((s,i) => s + (i.fob_usd || 0), 0);

  // 2. Flete (real o estimado)
  const fleteCalc = calcularFlete(modo, { cbm: cbm_total, tn: tn_total,
                                          flete_cbm_usd_override: params.flete_cbm_usd_override,
                                          container_usd_override: params.container_usd_override,
                                          costo_avion_usd: params.costo_avion_usd,
                                          certif_fedex_usd: params.certif_fedex_usd });
  // "Flete (info Despacho)" del Excel = solo Costo Flete + Desconsolidado + LogFee + Manejo + AGP (sin Dep Fiscal)
  // Pero para CIF el flete que cuenta es solo el maritimo (Costo Flete) + el flete oficial declarado en despacho
  const flete_para_cif = flete_real_usd ?? (modo === 'LCL'
    ? fleteCalc.items.filter(i => ['Costo Flete','Desconsolidado','Log Fee','Manejo','AGP'].includes(i.concepto)).reduce((s,i)=>s+i.usd,0)
    : modo === 'FCL_20' ? fleteCalc.total : 0);

  // 3. Seguro (real o 0.5%)
  const seguro = seguro_real_usd ?? (FOB_total * 0.005);

  // 4. CIF total
  const CIF_total = FOB_total + flete_para_cif + seguro;

  // 5. Prorrata por item segun FOB o peso
  const baseProrrata = prorrateo_por_peso
    ? items.reduce((s,i) => s + (i.peso_kg || 0), 0)
    : FOB_total;

  // 6. Calculo por NCM (agrupar items por NCM = 1 item SIM)
  const porNcm = {};
  for (const it of items) {
    const ncm = it.ncm || '__sin_ncm__';
    if (!porNcm[ncm]) porNcm[ncm] = { ncm, items: [], fob: 0, peso: 0, cantidad: 0 };
    porNcm[ncm].items.push(it);
    porNcm[ncm].fob += it.fob_usd || 0;
    porNcm[ncm].peso += it.peso_kg || 0;
    porNcm[ncm].cantidad += it.cantidad || 0;
  }

  const ncmsResultado = [];
  for (const grupo of Object.values(porNcm)) {
    const a = lookupAliquotas(grupo.ncm);
    const ratio = baseProrrata > 0
      ? (prorrateo_por_peso ? grupo.peso / baseProrrata : grupo.fob / baseProrrata)
      : 0;
    const prorrata_flete_seguro = ratio * (flete_para_cif + seguro);
    const cif = grupo.fob + prorrata_flete_seguro;

    const derechos = cif * a.derecho_imp / 100;
    const ntl = cif * a.ntl / 100;
    const tasa_estad = cif * a.tasa_estad / 100;        // 3% × CIF
    const base_iva = cif + derechos + ntl + tasa_estad;
    const iva = base_iva * a.iva / 100;
    const iva_adic = base_iva * a.iva_adic / 100;
    const ganancias = base_iva * a.ganancias / 100;
    const iibb = base_iva * (params.iibb_pct ?? IIBB_DEFAULT_PCT) / 100;

    ncmsResultado.push({
      ncm: grupo.ncm,
      items_count: grupo.items.length,
      fob: grupo.fob,
      cif,
      prorrata_flete_seguro,
      derechos,
      ntl,
      tasa_estad,
      base_iva,
      iva, iva_adic, ganancias, iibb,
      total_impuestos: derechos + ntl + tasa_estad + iva + iva_adic + ganancias + iibb,
      recuperable: iva + iva_adic + ganancias + iibb,
      no_recuperable: derechos + ntl + tasa_estad,
      inal: a.inal,
    });
  }

  // 7. Libre Circulacion (sobre FOB con INAL)
  const libreCirc = calcularLibreCirculacion(fob_con_inal_usd, tipo_cambio);

  // 8. Despachante
  const despachante = calcularDespachante(modo, FOB_total);

  // 9. Varios
  const varios = calcularVarios(modo);

  // 10. Totales (SIM = $10 global, una sola vez)
  const arancel_sim_global = ARANCEL_SIM_GLOBAL;
  const total_impuestos = ncmsResultado.reduce((s,n) => s + n.total_impuestos, 0) + arancel_sim_global;
  const total_recuperable = ncmsResultado.reduce((s,n) => s + n.recuperable, 0);
  const total_no_recup_impuestos = ncmsResultado.reduce((s,n) => s + n.no_recuperable, 0) + arancel_sim_global;
  const seguro_nr = seguro;
  const flete_total_nr = fleteCalc.total;
  const libre_circ_nr = libreCirc.total_usd;
  const despachante_nr = despachante.total;
  const varios_nr = varios.total;

  const total_no_recuperable = total_no_recup_impuestos + seguro_nr + flete_total_nr + libre_circ_nr + despachante_nr + varios_nr;
  const total_a_pagar = FOB_total + total_no_recuperable + total_recuperable;
  const costo_nacionalizacion_pct = (total_no_recuperable / FOB_total) * 100;

  return {
    modo,
    fob_total: FOB_total,
    cbm_total, tn_total,
    flete: { ...fleteCalc, para_cif: flete_para_cif },
    seguro,
    cif_total: CIF_total,
    prorrateo: prorrateo_por_peso ? 'PESO' : 'FOB',
    ncms: ncmsResultado,
    libre_circulacion: libreCirc,
    despachante,
    varios,
    arancel_sim: arancel_sim_global,
    totales: {
      impuestos: total_impuestos,
      recuperable: total_recuperable,
      no_recuperable: total_no_recuperable,
      a_pagar: total_a_pagar,
      costo_nacionalizacion_pct,
    },
  };
}

// ========== Helper: formato salida tipo Excel ==========
export function formatearReporte(r) {
  const fmt = (n) => '$' + (n||0).toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const lines = [];
  lines.push(`=== Calculo Nacionalizacion (${r.modo}) ===`);
  lines.push(`Carga: ${r.cbm_total} CBM | ${r.tn_total} TN`);
  lines.push(`FOB total: ${fmt(r.fob_total)}`);
  lines.push(`Flete (CIF): ${fmt(r.flete.para_cif)} | Seguro: ${fmt(r.seguro)}`);
  lines.push(`CIF: ${fmt(r.cif_total)}`);
  lines.push('');
  lines.push('Por NCM:');
  for (const n of r.ncms) {
    lines.push(`  ${n.ncm} (${n.items_count} items): CIF ${fmt(n.cif)} → Imp ${fmt(n.total_impuestos)}${n.inal?' [INAL]':''}`);
  }
  lines.push('');
  if (r.libre_circulacion.total_usd > 0)
    lines.push(`Libre Circulacion: ${fmt(r.libre_circulacion.total_usd)}`);
  lines.push(`Despachante: ${fmt(r.despachante.total)}`);
  lines.push(`Flete total (NR): ${fmt(r.flete.total)}`);
  lines.push(`Varios: ${fmt(r.varios.total)}`);
  lines.push('');
  lines.push(`No Recuperable: ${fmt(r.totales.no_recuperable)}`);
  lines.push(`Recuperable:    ${fmt(r.totales.recuperable)}`);
  lines.push(`COSTO NAC:      ${r.totales.costo_nacionalizacion_pct.toFixed(1)}% del FOB`);
  lines.push(`TOTAL A PAGAR:  ${fmt(r.totales.a_pagar)}`);
  return lines.join('\n');
}
