// Carga masiva de fotos de cajas: una carpeta (o .zip / .rar) con muchas fotos se reparte por código y
// por tipo de caja (master / inner) según los nombres de las carpetas y de los archivos.
// Ej.: "437E/master.jpg", "Inner/437E.jpg", "437E inner 2.jpg", "Familia cuchillos › 438E_MB.jpg".
// Lo que no se puede deducir queda para asignar a mano; nunca se adivina un código.
// Plan: .planning/PLAN-2026-09-15-correcciones-y-archivos.md (fase A)

import { SEP } from './archivos.js';

// "CARTON" / "CTN" NO es master: en estas cargas "carton" es el rótulo del artículo (r54). Igual la pista de
// tipo ya no se manda a la IA: qué cara es cada foto lo decide su contenido.
const TIPO_MASTER = /^(MASTER|MASTERBOX|MB|EXTERIOR|EXT|OUTER|CAJA ?MADRE|MADRE)$/;
const TIPO_INNER = /^(INNER|INNERBOX|IB|INTERIOR|INT|INBOX|CAJA ?INTERIOR)$/;
// Prefijos de cámaras y celulares: "IMG_1234" no es el código 1234.
const PREFIJO_CAMARA = /^(IMG|DSC|DSCN|PXL|WA|VID|PHOTO|FOTO|SCAN|SCREENSHOT|CAPTURA)$/;
// 3 o 4 dígitos con sufijo opcional. Quedan afuera números de carga ("China 41") y años ("Fotos 2026").
const CODIGO = /^\d{3,4}[A-Z]{0,3}$/;
const ANIO = /^(19|20)\d{2}$/;

const palabras = (texto) => String(texto).toUpperCase().replace(/\.[A-Z0-9]{1,5}$/, '')
  .split(/[^A-Z0-9]+/).filter(Boolean);

function tipoDe(partes) {
  for (let i = partes.length - 1; i >= 0; i--) {
    const tokens = palabras(partes[i]);
    const unidos = String(partes[i]).toUpperCase().replace(/\.[A-Z0-9]{1,5}$/, '').replace(/[^A-Z]+/g, ' ').trim();
    if (tokens.some(t => TIPO_MASTER.test(t)) || TIPO_MASTER.test(unidos)) return 'master';
    if (tokens.some(t => TIPO_INNER.test(t)) || TIPO_INNER.test(unidos)) return 'inner';
  }
  return null;
}

function codigoDe(partes) {
  // Primero el archivo, después las carpetas de adentro hacia afuera.
  for (let i = partes.length - 1; i >= 0; i--) {
    const tokens = palabras(partes[i]);
    for (let k = 0; k < tokens.length; k++) {
      if (k > 0 && PREFIJO_CAMARA.test(tokens[k - 1])) continue;
      if (CODIGO.test(tokens[k]) && !ANIO.test(tokens[k])) return tokens[k];
    }
  }
  return null;
}

// nombre con ruta ("A › 437E › master.jpg", "405E.zip › foto1.jpg", "familia.rar › 405E › x.jpg")
// → { codigo, tipo } (null si no se puede deducir). El nombre del .zip/.rar y el de las carpetas también
// cuentan: si el archivo tiene un nombre ilegible (ej. "ladf72574a"), el código sale de la carpeta o del
// zip que lo contiene (ej. "405E"). Se busca del archivo hacia afuera; gana lo más cercano al archivo.
export function interpretarFoto(nombre, tipoPorDefecto = null) {
  const partes = String(nombre).split(SEP).map(p => p.replace(/\.(zip|rar)$/i, '')).filter(Boolean);
  return { codigo: codigoDe(partes), tipo: tipoDe(partes) || tipoPorDefecto };
}

// Suma las fotos a los artículos (por código). Devuelve los artículos nuevos y las fotos sin asignar.
export function repartirFotos(articulos, files, tipoPorDefecto = null) {
  const lista = articulos.map(a => ({ ...a, master: [...a.master], inner: [...a.inner] }));
  const sinAsignar = [];
  for (const file of files) {
    const { codigo, tipo } = interpretarFoto(file.name, tipoPorDefecto);
    if (!codigo || !tipo) { sinAsignar.push({ file, codigo: codigo || '', tipo: tipo || '' }); continue; }
    agregar(lista, codigo, tipo, file);
  }
  return { articulos: lista, sinAsignar };
}

export function agregar(lista, codigo, tipo, file) {
  const cod = String(codigo).toUpperCase().trim();
  let art = lista.find(a => a.codigo.trim().toUpperCase() === cod);
  if (!art) {
    // Reusar una fila vacía antes de crear otra.
    art = lista.find(a => !a.codigo.trim() && !a.master.length && !a.inner.length);
    if (art) art.codigo = cod;
    else { art = { codigo: cod, master: [], inner: [] }; lista.push(art); }
  }
  art[tipo].push(file);
  return lista;
}
