// Nombres para mostrar de Cajas vs Packing List (pantalla y PDF).
// Plan: .planning/PLAN-2026-09-18-cajas-caras-ci-pesos.md

export const CAMPOS = {
  foto: 'Foto', foto_frente: 'Foto del frente', foto_lateral: 'Foto del lateral', foto_dorso: 'Foto del dorso',
  codigo: 'Código impreso', total_cajas: 'Total de cajas (N de n/N)', caja_en_rango: 'N° de caja en el rango del PL',
  es_ultima_caja: 'Foto de la última caja', made_in: 'MADE IN',
  unidades_por_master: 'Unidades por master (QUANTITY)', unidades_por_inner: 'Unidades por inner (INNER QTY)',
  peso_bruto_kg: 'Peso bruto por caja (kg)', peso_neto_kg: 'Peso neto por caja (kg)', medidas_cm: 'Medidas (cm)',
  consignatario: 'Consignatario (Para:)', en_packing_list: 'Está en el packing list',
  fotos_con_codigos_distintos: 'Fotos con códigos distintos',
  codigo_barras: 'Código de barras (EAN13)', marca: 'Marca (frente vs barcode)', articulo: 'Artículo (nombre)',
  comercializador: 'Comercializador (nombre)', cuit_importador: 'CUIT importador', cuit_comercializador: 'CUIT comercializador',
  comercializador_cruzado: 'Comercializador (nombre y CUIT)', dos_lados: 'Los dos lados (mismo barcode)',
  parte_cruda: 'Parte cruda', cantidad_ci: 'Cantidad CI vs PL', en_ci: 'Está en la Commercial Invoice',
  en_pl: 'Está en el packing list', importador_ci: 'Comprador de la CI = importador',
};

export const CARA = {
  master_frente: 'master · frente', master_lateral: 'master · lateral', inner: 'inner',
  carton_frente: 'cartón · frente', carton_dorso: 'cartón · dorso',
};

export const TIPO_CAJA = { master: 'master', inner: 'inner', articulo_carton: 'cartón', documentos: 'documentos' };

export const SIN_ASIGNAR = '(sin asignar)';

// "Caja" que se muestra en una fila: la cara si la tiene, si no el tipo.
export const cajaDe = (f) => (f.cara ? CARA[f.cara] : TIPO_CAJA[f.tipo_caja] || f.tipo_caja);

export const pctTxt = (n) => (n === null || n === undefined ? '' : `${String(Math.round(n * 10) / 10).replace('.', ',')} %`);
