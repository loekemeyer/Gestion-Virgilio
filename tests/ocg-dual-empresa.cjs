/* Regresión v19.84 (problema 430) — Thomas, 18/09: "LO QUE SE PIDE POR OCs TIENE QUE SER LOS
   CODIGOS CON EMPRESA. Considera que esos codigos viajan en todos lados con el codigo de
   empresa y ese se tiene que usar en las ordenes de compra para saber cual se esta comprando".

   El backend (vista_generador_oc) ahora devuelve un dual en DOS filas, `437E LK` y `437E CH`,
   cada una con su stock / capacidad / proyección / pedidos, más la columna `cod_config` con el
   código PELADO. Este test cuida los dos lugares del front que eso obliga a cambiar:

   1. la pantalla Config escribe en OC_Maximos por `cod_config`, NO por `cod`: la config
      (proveedor, %, índice, objetivo) es UNA sola para las dos mitades. Si se escribiera por
      `cod`, un PATCH a "437E CH" no matchea ninguna fila (se pierde el cambio, sin avisar) o
      el alta crea una fila basura "437E CH" en OC_Maximos.
   2. la recepción busca la OC con la LÍNEA que eligió el operario (`437E` + `CH`) y recién
      después pelada, porque la OC del dual ahora viene con la empresa pegada.

   Es de FUENTE (no necesita navegador). Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const rcp = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8");
const fallas = [];

// 1) Config: pide cod_config y escribe por él
if (idx.indexOf("select=cod,cod_config,descripcion,proveedor") < 0)
  fallas.push("la pantalla Config dejó de pedir `cod_config` a vista_generador_oc");
if (!/codCfg: String\(x\.cod_config \|\| x\.cod\)/.test(idx))
  fallas.push("las filas de Config ya no guardan codCfg (el código pelado de OC_Maximos)");
const patchPorCod = idx.match(/SUPABASE_OCMAX_ENDPOINT \+ "\?cod=eq\." \+ encodeURIComponent\(c\)/g) || [];
if (patchPorCod.length)
  fallas.push(patchPorCod.length + " PATCH a OC_Maximos siguen usando el `cod` de la fila en vez de codCfg");
if ((idx.match(/encodeURIComponent\(\(row && row\.codCfg\) \|\| c\)/g) || []).length < 2)
  fallas.push("faltan los PATCH/alta de OC_Maximos por codCfg");

// 2) Recepción: la OC del dual se busca con la línea
if (rcp.indexOf('if (lin && m[k + " " + lin]) return m[k + " " + lin];') < 0)
  fallas.push("ocDeCod ya no busca la OC con la empresa (`437E CH`) antes de la pelada");
if (rcp.indexOf("return m[k] || null;") < 0)
  fallas.push("ocDeCod perdió el fallback al código pelado (códigos comunes y OC viejas)");

if (fallas.length) { console.error("FALLA ocg-dual-empresa:\n - " + fallas.join("\n - ")); process.exit(1); }
console.log("OK ocg-dual-empresa: la OC lleva el código con empresa y la config sigue en el pelado");
