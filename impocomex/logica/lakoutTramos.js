// Une lo que la IA leyó en cada tramo (de a 5 páginas) de un despacho / lakout escaneado.
// Antes cada pantalla unía una lista fija de campos de cabecera y se perdían BL, CI, PL, HKINV, Libre
// Circulación, pesaje, despachante, legibilidad e ítems esperados: esos controles no corrían.
// Lo usan "Verificar Lakout" y "Verificar Docs Separados".
// Plan: .planning/PLAN-2026-09-15-correcciones-y-archivos.md (fase B)

const esObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
// Un 0 es un dato; un objeto sin ningún dato adentro ({ items: [] }) cuenta como vacío.
const vacio = (v) => v === null || v === undefined || v === '' || (Array.isArray(v) && v.length === 0) ||
  (esObjeto(v) && Object.values(v).every(vacio));
const PEOR_LEGIBILIDAD = { mala: 3, media: 2, buena: 1 };

// Completa `destino` con lo que falte de `origen`. Listas: se suman sin repetir. Objetos: campo a campo.
function completar(destino, origen) {
  for (const [k, v] of Object.entries(origen || {})) {
    if (vacio(v)) continue;
    if (vacio(destino[k])) { destino[k] = Array.isArray(v) ? [...v] : esObjeto(v) ? { ...v } : v; continue; }
    if (Array.isArray(destino[k]) && Array.isArray(v)) {
      const vistos = new Set(destino[k].map(x => JSON.stringify(x)));
      for (const x of v) if (!vistos.has(JSON.stringify(x))) { destino[k].push(x); vistos.add(JSON.stringify(x)); }
    } else if (esObjeto(destino[k]) && esObjeto(v)) {
      completar(destino[k], v);
    }
  }
  return destino;
}

// Ítems: sin repetidos, sin filas de HKINV/CI con NCM mal escrito y sin subtotales por NCM.
export function limpiarItems(itemsAcc) {
  const canonNcm = (n) => String(n || '').replace(/\.\d{3}[A-Z]$/, '').toUpperCase();
  const vistos = new Set();
  const itemsDedup = [];
  for (const it of itemsAcc) {
    const key = it.codigo
      ? `c:${String(it.codigo).toUpperCase().trim()}-${String(it.marca || '').toUpperCase().trim()}`
      : `n:${canonNcm(it.ncm)}-${String(it.descripcion || '').slice(0, 30)}`;
    if (vistos.has(key)) continue;
    vistos.add(key);
    itemsDedup.push(it);
  }

  // Los ítems del despacho tienen NCM con sufijo SIM; si el mismo código aparece sin sufijo, es de HKINV/CI.
  const ncmValidoSim = (n) => !!n && /^\d{4}\.\d{2}\.\d{2}\.\d{3}[A-Z]$/.test(String(n).trim());
  const canonNcm10 = (n) => { const s = String(n || '').toUpperCase().trim(); return /[A-Z]$/.test(s) ? s.slice(0, -1) : s; };
  const conSim = new Set(itemsDedup.filter(it => it.codigo && ncmValidoSim(it.ncm)).map(it => String(it.codigo).toUpperCase().trim()));
  let items = itemsDedup.filter(it => {
    const cod = String(it.codigo || '').toUpperCase().trim();
    return !cod || !(conSim.has(cod) && !ncmValidoSim(it.ncm));
  });

  // Subtotales: fila sin código cuyo FOB coincide (±2 %) con la suma de un grupo de NCM.
  const sumasPorNcm = {};
  for (const it of items) {
    if (!it.codigo) continue;
    const k = canonNcm10(it.ncm);
    sumasPorNcm[k] = (sumasPorNcm[k] || 0) + (Number(it.valor_fob) || 0);
  }
  const sumas = Object.values(sumasPorNcm);
  items = items.filter(it => {
    if (it.codigo) return true;
    const fob = Number(it.valor_fob) || 0;
    if (fob <= 0) return true;
    const suma = sumasPorNcm[canonNcm10(it.ncm)] || 0;
    if (suma > 0 && Math.abs(suma - fob) / Math.max(suma, 1) < 0.02) return false;
    return !sumas.some(s => s > 0 && Math.abs(s - fob) / Math.max(s, 1) < 0.02);
  });
  return items;
}

// datos: el JSON devuelto por cada tramo, en orden. Devuelve el despacho unido.
export function unirTramos(datos) {
  const unido = {};
  const itemsAcc = [];
  let legibilidad = null;
  let esperados = null;
  for (const d of datos) {
    if (!d) continue;
    const { items, legibilidad: leg, items_expected_count: exp, ...resto } = d;
    completar(unido, resto);
    for (const it of items || []) itemsAcc.push(it);
    if (leg && (!legibilidad || (PEOR_LEGIBILIDAD[leg] || 0) > (PEOR_LEGIBILIDAD[legibilidad] || 0))) legibilidad = leg;
    if (Number(exp) > 0) esperados = Math.max(esperados || 0, Number(exp));
  }
  unido.items = limpiarItems(itemsAcc);
  if (legibilidad) unido.legibilidad = legibilidad;
  if (esperados) unido.items_expected_count = esperados;
  return unido;
}

// Campos de cabecera que, si faltan después de unir, justifican releer el primer tramo.
export const CABECERA_CRITICA = ['flete_total', 'seguro_total', 'valor_cif_total'];
export const CABECERA_RELEER = ['flete_total', 'seguro_total', 'cotiz_dolar', 'peso_bruto_total', 'total_bultos', 'modo_envio',
  'iibb_inscripcion', 'derecho_importacion_total', 'tasa_estadistica_total', 'iva_total', 'iva_adic_total', 'ganancias_total',
  'iibb_total', 'canal_selectivo', 'valor_cif_total'];
