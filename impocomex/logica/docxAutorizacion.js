// Completa el Word "AUTORIZACIÓN de Importación - ENVASES" del gestor.
// Cada dato del formulario es un párrafo "Etiqueta:" y el valor va a continuación, en el mismo
// párrafo. El bloque "Datos de Producto" + "Datos del Lote" se repite una vez por certificado, como
// pide el propio formulario. Antes de escribir, se sacan del formulario las aclaraciones para quien lo
// llena (paréntesis salvo "(Kg)", "– solo números…", "ACLARACIÓN", "copiar y pegar…"). El resto no se toca.
// Planes: .planning/PLAN-2026-09-15-autorizacion-envases.md, PLAN-2026-09-15-autorizacion-word-limpio-y-arribo.md

import { unzipSync, zipSync, strFromU8, strToU8 } from '../vendor/fflate.js';

// Etiquetas sin aclaraciones: se comparan contra el formulario ya limpio (y sin aclaraciones, por si acaso).
export const ETIQUETAS = {
  importador: {
    razon_social: 'Nombre o Razón Social:',
    cuit: 'CUIT del importador:',
    rne: 'RNE:',
  },
  deposito: {
    provincia: 'Provincia:',
    departamento: 'Departamento:',
    localidad: 'Localidad:',
    domicilio: 'Domicilio:',
    piso_dpto: 'Piso / Dpto.:',
    factura: 'Factura n°:',
  },
  transporte: {
    fecha_arribo: 'Fecha de arribo de la mercadería:',
    bl_numero: 'Conocimiento de Embarque/Guía Aérea/CRT N°',
    pais_procedencia: 'País de procedencia:',
  },
  producto: {
    pais_origen: 'País de origen:',
    elaborador: 'Nombre o Razón social del Elaborador:',
    certificado: 'Certificado de Autorización de Envases:',
    denominacion: 'Denominación:',
    marca_codigo: 'Marca / código comercial:',
    lote: 'Lote:',
    cantidad: 'Cantidad de unidades:',
    unidad: 'Unidad de medida:',
    peso_bruto: 'Peso Bruto (Kg)',
  },
};

const INICIO_BLOQUE = 'Datos de Producto';
const FIN_BLOQUE = ETIQUETAS.producto.peso_bruto;

const escapar = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const desescapar = (s) => s
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

// ---- Aclaraciones del formulario ----
// "(obligatorio)", "(sin puntos, guiones…)", "(solo si posee)"… con el espacio de antes; "(Kg)" queda.
const PARENTESIS = /\s*\((?!\s*kg\s*\))[^()]*\)/gi;
// "Peso Bruto (Kg) – solo números con dos decimales máximo:"
const GUION_ACLARACION = /\s*[–—-]\s*solo\s[^:]*/gi;
const TITULO_ACLARACION = /^aclaraci[oó]n:?$/i;
const INSTRUCCION_COPIAR = /copiar y pegar los campos/i;

export const sinAclaraciones = (texto) => String(texto || '').replace(PARENTESIS, '').replace(GUION_ACLARACION, '');

const normal = (s) => sinAclaraciones(s).replace(/\s+/g, ' ').trim().toLowerCase();

// El renglón ya dice "RNE:": el número va sin "RNE" delante (evita "RNE: RNE 00306713").
export const numeroRne = (v) => String(v ?? '').trim().replace(/^R\.?\s*N\.?\s*E\.?\s*(N\s*[°ºo]\.?\s*)?[:\-]?\s*/i, '').trim();

const RE_TEXTO = /<w:t(?: [^>]*)?>([^<]*)<\/w:t>/g;

// Párrafos de primer nivel con su posición en el XML. <w:pPr> y <w:proofErr> no son párrafos.
function parrafos(xml) {
  return [...xml.matchAll(/<w:p(?=[ >])[^>]*>[\s\S]*?<\/w:p>/g)].map(m => ({
    xml: m[0],
    desde: m.index,
    hasta: m.index + m[0].length,
    texto: desescapar([...m[0].matchAll(RE_TEXTO)].map(t => t[1]).join('')),
  }));
}

// Borra las aclaraciones de un párrafo. Word parte el texto en varios <w:t>: se marca qué caracteres del
// texto del párrafo sobran y se sacan de cada <w:t>, sin tocar el formato. En un renglón "Etiqueta: valor"
// solo se mira la etiqueta (hasta el primer ":"), para no tocar respuestas ya escritas.
function limpiarParrafo(pxml) {
  const textos = [...pxml.matchAll(RE_TEXTO)].map(m => desescapar(m[1]));
  if (!textos.length) return pxml;
  const total = textos.join('');
  const dosPuntos = total.indexOf(':');
  const hasta = dosPuntos >= 0 ? dosPuntos : total.length;
  const borrar = new Uint8Array(total.length);
  for (const re of [PARENTESIS, GUION_ACLARACION]) {
    for (const m of total.matchAll(re)) if (m.index < hasta) borrar.fill(1, m.index, Math.min(m.index + m[0].length, hasta));
  }
  if (!borrar.includes(1)) return pxml;
  let pos = 0, n = 0;
  return pxml.replace(RE_TEXTO, () => {
    const t = textos[n++];
    let nuevo = '';
    for (let k = 0; k < t.length; k++) if (!borrar[pos + k]) nuevo += t[k];
    pos += t.length;
    return `<w:t xml:space="preserve">${escapar(nuevo)}</w:t>`;
  });
}

export function limpiarAclaraciones(xml) {
  const todos = parrafos(xml);
  const quitar = new Set();
  todos.forEach((p, i) => {
    const t = p.texto.replace(/\s+/g, ' ').trim();
    if (TITULO_ACLARACION.test(t)) {
      quitar.add(i);
      const siguiente = todos.findIndex((q, j) => j > i && q.texto.trim());
      if (siguiente > 0) quitar.add(siguiente);
    } else if (INSTRUCCION_COPIAR.test(t)) {
      quitar.add(i);
    }
  });
  let salida = xml;
  for (let i = todos.length - 1; i >= 0; i--) {
    const p = todos[i];
    // Un párrafo con salto de sección no se borra (se rompería el diseño): solo se vacía su texto.
    const nuevo = !quitar.has(i) ? limpiarParrafo(p.xml)
      : /<w:sectPr/.test(p.xml) ? p.xml.replace(/<w:r(?=[ >])[\s\S]*?<\/w:r>/g, '') : '';
    if (nuevo !== p.xml) salida = salida.slice(0, p.desde) + nuevo + salida.slice(p.hasta);
  }
  return salida;
}

// Pone el valor a continuación de la etiqueta. Si el renglón ya tenía algo escrito, no lo pisa.
function ponerValor(p, valor, avisos, etiqueta) {
  const v = String(valor ?? '').trim();
  if (!v) return p;
  const resto = p.texto.slice(p.texto.lastIndexOf(':') + 1).trim();
  if (resto) {
    avisos.push(`"${etiqueta}" ya tenía texto en el formulario ("${resto}"): no se modificó.`);
    return p;
  }
  const espacio = /\s$/.test(p.texto) ? '' : ' ';
  const run = `<w:r><w:t xml:space="preserve">${espacio}${escapar(v)}</w:t></w:r>`;
  return { ...p, xml: p.xml.replace(/<\/w:p>$/, `${run}</w:p>`) };
}

// Selecciona un valor del desplegable (control de contenido) que está en el párrafo.
function elegirEnLista(p, valor, avisos, etiqueta) {
  const v = String(valor ?? '').trim();
  if (!v) return p;
  const sdt = p.xml.match(/<w:sdt>[\s\S]*?<\/w:sdt>/);
  if (!sdt || !/<w:dropDownList>/.test(sdt[0])) return ponerValor(p, v, avisos, etiqueta);
  const opciones = [...sdt[0].matchAll(/<w:listItem [^>]*w:value="([^"]*)"/g)].map(m => desescapar(m[1]));
  if (!opciones.includes(v)) {
    avisos.push(`"${etiqueta}": "${v}" no es una opción del formulario (${opciones.filter(o => !o.startsWith('Elija')).join(', ')}).`);
    return p;
  }
  const nuevo = sdt[0]
    .replace(/<w:showingPlcHdr\/>/, '')
    .replace(/<w:sdtContent>[\s\S]*<\/w:sdtContent>/, `<w:sdtContent><w:r><w:t>${escapar(v)}</w:t></w:r></w:sdtContent>`);
  return { ...p, xml: p.xml.replace(sdt[0], nuevo) };
}

function llenarCampos(lista, campos, valores, avisos, faltantes, sufijo = '') {
  for (const [clave, etiqueta] of Object.entries(campos)) {
    const i = lista.findIndex(p => normal(p.texto).startsWith(normal(etiqueta)));
    if (i < 0) {
      faltantes.push(etiqueta + sufijo);
      continue;
    }
    lista[i] = clave === 'unidad'
      ? elegirEnLista(lista[i], valores?.[clave], avisos, etiqueta)
      : ponerValor(lista[i], valores?.[clave], avisos, etiqueta);
  }
}

// Ids que Word exige únicos al duplicar párrafos y controles.
function idsNuevos(xml, usados) {
  const hex = () => {
    let id;
    do { id = Math.floor(Math.random() * 0x7fffffff).toString(16).toUpperCase().padStart(8, '0'); } while (usados.has(id));
    usados.add(id);
    return id;
  };
  return xml
    .replace(/w14:paraId="[0-9A-Fa-f]+"/g, () => `w14:paraId="${hex()}"`)
    .replace(/w14:textId="[0-9A-Fa-f]+"/g, () => `w14:textId="${hex()}"`)
    .replace(/<w:id w:val="-?\d+"\/>/g, () => `<w:id w:val="${Math.floor(Math.random() * 2 ** 31) - 2 ** 30}"/>`);
}

export function llenarDocumento(xmlFormulario, datos) {
  const avisos = [];
  const faltantes = [];
  // Primero el formulario sin aclaraciones; después los valores (que nunca se limpian).
  const xml = limpiarAclaraciones(xmlFormulario);
  const todos = parrafos(xml);

  const inicio = todos.findIndex(p => normal(p.texto).startsWith(normal(INICIO_BLOQUE)));
  const fin = todos.findIndex((p, i) => i > inicio && normal(p.texto).startsWith(normal(FIN_BLOQUE)));
  if (inicio < 0 || fin < 0) throw new Error('El formulario no tiene el bloque "Datos de Producto" … "Peso Bruto": no es el formulario esperado.');

  // Encabezado: importador, depósito y transporte (antes del bloque de producto)
  const encabezado = todos.slice(0, inicio);
  llenarCampos(encabezado, ETIQUETAS.importador, { ...datos.importador, rne: numeroRne(datos.importador?.rne) }, avisos, faltantes);
  llenarCampos(encabezado, ETIQUETAS.deposito, datos.deposito, avisos, faltantes);
  llenarCampos(encabezado, ETIQUETAS.transporte, datos.transporte, avisos, faltantes);

  // Bloque de producto, una copia por certificado
  const bloqueXml = xml.slice(todos[inicio].desde, todos[fin].hasta);
  const productos = datos.productos?.length ? datos.productos : [null];
  const usados = new Set([...xml.matchAll(/w14:(?:paraId|textId)="([0-9A-Fa-f]+)"/g)].map(m => m[1].toUpperCase()));
  const copias = productos.map((prod, n) => {
    const base = n === 0 ? bloqueXml : idsNuevos(bloqueXml, usados);
    if (!prod) return base;
    const lista = parrafos(base);
    llenarCampos(lista, ETIQUETAS.producto, prod, avisos, n === 0 ? faltantes : [], ` (certificado ${n + 1})`);
    let salida = base;
    for (let i = lista.length - 1; i >= 0; i--) {
      const original = parrafos(base)[i];
      salida = salida.slice(0, original.desde) + lista[i].xml + salida.slice(original.hasta);
    }
    return salida;
  });
  const separador = '<w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr></w:p>';

  // Reemplazos de atrás hacia adelante para no mover las posiciones pendientes.
  let salida = xml.slice(0, todos[inicio].desde) + copias.join(separador) + xml.slice(todos[fin].hasta);
  for (let i = encabezado.length - 1; i >= 0; i--) {
    if (encabezado[i].xml !== todos[i].xml) {
      salida = salida.slice(0, todos[i].desde) + encabezado[i].xml + salida.slice(todos[i].hasta);
    }
  }
  return { xml: salida, avisos, faltantes };
}

// plantilla: ArrayBuffer | Uint8Array del .docx. Devuelve el .docx completo y los avisos.
export function llenarAutorizacion(plantilla, datos) {
  const archivos = unzipSync(plantilla instanceof Uint8Array ? plantilla : new Uint8Array(plantilla));
  if (!archivos['word/document.xml']) throw new Error('El archivo no es un Word (.docx) válido.');
  const { xml, avisos, faltantes } = llenarDocumento(strFromU8(archivos['word/document.xml']), datos);
  archivos['word/document.xml'] = strToU8(xml);
  if (faltantes.length) avisos.push(`El formulario no tiene estos renglones, quedaron sin completar: ${faltantes.join(' · ')}.`);
  return { bytes: zipSync(archivos, { level: 6 }), avisos };
}
