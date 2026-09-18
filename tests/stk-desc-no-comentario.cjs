/* Regresión v19.77 (problema 422) — la DESCRIPCIÓN de un artículo es su NOMBRE, nunca el
   comentario de un ajuste manual.

   Qué salió mal: la tabla de Stock mostraba el 505I como "Esta en racks", el 503E como
   "Para pedido Np 98690" y el 518 como "Devolucin de Nexxo". Dos causas encadenadas:

   1. `stockAjustar` / `stockFijar` guardaban el comentario libre del operario en
      `Movimientos_Stock.descripcion` (además del `ref`, donde sí corresponde), y
      `vista_saldos_stock` elige la descripción MÁS CORTA del código → un comentario corto
      le gana al nombre real y queda como nombre del artículo para siempre.
   2. El merge en background de `openStockAdmin` pisaba la descripción que ya venía resuelta
      de `stocks_carga_rapida` —que hace COALESCE(vista_nombres_articulos, …), o sea el
      catálogo PRIMERO— con la de `vista_stock_procesada`, que hace el COALESCE al revés.

   Este test es de FUENTE (no necesita navegador): cuida que ninguna de las dos vuelva.
   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const fallas = [];

// 1) el comentario del ajuste NO va en `descripcion` (va en `ref`, que se arma aparte)
const comentEnDesc = src.match(/descripcion:\s*comentario\s*\|\|/g) || [];
if (comentEnDesc.length) fallas.push(comentEnDesc.length + " lugar(es) escriben `descripcion: comentario || …` — el comentario va SOLO en `ref`");
const descComent = src.match(/desc\s*=\s*comentario\s*\|\|/g) || [];
if (descComent.length) fallas.push(descComent.length + " lugar(es) hacen `desc = comentario || …` (stockFijar insumos) — el comentario va SOLO en `ref`");

// …pero sí tiene que seguir yendo al `ref`, que es lo que se ve en el detalle del movimiento
if (src.indexOf('var ref = "ajuste manual" + (comentario ? " | " + comentario : "");') < 0)
  fallas.push("stockAjustar ya no manda el comentario al `ref` — se perdería el motivo del ajuste");

// 2) el merge en background no pisa una descripción ya resuelta
if (src.indexOf("if (vr.descripcion && !r.descripcion) r.descripcion = vr.descripcion;") < 0)
  fallas.push("el merge de openStockAdmin volvió a pisar la descripción de stocks_carga_rapida con la de vista_stock_procesada");

// 3) un mapa de nombres VACÍO no se cachea (si no, artNombre() queda inútil toda la sesión)
if (!/if \(Object\.keys\(m\)\.length\) _artNombres = m;/.test(src))
  fallas.push("loadArtNombres volvió a cachear el mapa vacío cuando el fetch falla");

if (fallas.length) { console.error("FALLA stk-desc-no-comentario:\n - " + fallas.join("\n - ")); process.exit(1); }
console.log("OK stk-desc-no-comentario: el comentario del ajuste no contamina el nombre del artículo");
