/* Regresión v11.70 — la tabla de "📦 Pedidos Importación" no se pisa.

   El bug: las 14 columnas heredaban el layout genérico de `.mva-tbl`
   (`table-layout:fixed` + `.mva-tbl th.num{width:15%}`) → 11 columnas numéricas
   × 15% = 165% del ancho, así que Código y Descripción quedaban en ~0 px y se
   imprimían una encima de la otra, y `.mva-tblwrap{overflow-x:hidden}` cortaba
   m³ y Acciones (los botones ✏️/📥 no se veían).

   Chequea, con un _stkPop de laboratorio (sin red), renderizando de verdad en
   el navegador y midiendo el layout:
   - la tabla usa el modificador `.wide` + `<colgroup>` (14 columnas);
   - NINGUNA celda tiene el contenido más ancho que su columna (= texto pisado),
     salvo la Descripción, que recorta a propósito con «…» y tiene el nombre
     completo en el `title`;
   - la última columna (Acciones, con ✏️/📥) queda DENTRO del área visible;
   - en pantalla angosta (390px) la tabla se desliza al costado (no se achica)
     y la columna Código queda fija (sticky).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const ITEMS = [
  { cod: "102E927", desc: "MACETA PLASTICA 20CM SURTIDA COLORES", prov: "Hugo Wong", proyUni: 19270, objetivoUni: 1056,
    stockUni: 9360, enCurso: 8854, aPedirUni: 8928, aPedirCajas: 62, uniMaster: 144, fobUni: 0.38, m3Master: 0.0742,
    esParte: true, stockParteU: 120, stockParteCods: "102E", det: [{ id: 1, curso: 8854, marca: "TN" }] },
  { cod: "529E397", desc: "REGADERA 5 LITROS COLORES", prov: "Hugo Wong", proyUni: 23970, objetivoUni: 0,
    stockUni: 20736, enCurso: 4482, aPedirUni: 4608, aPedirCajas: 32, uniMaster: 144, fobUni: 0.465, m3Master: 0.1,
    esParte: false, stockParteU: 0, det: [{ id: 2, curso: 4482, marca: "" }] },
  { cod: "838E96", desc: "RASTRILLO MANO 3 DIENTES", prov: "Becky", proyUni: 960, objetivoUni: 0,
    stockUni: 0, enCurso: 960, aPedirUni: 1008, aPedirCajas: 7, uniMaster: 144, fobUni: 0.225, m3Master: 0.0857,
    esParte: false, stockParteU: 0, det: [{ id: 3, curso: 960, marca: "" }] }
];

(async () => {
  const b = await chromium.launch();
  const out = {}; const errs = [];
  for (const [w, tag] of [[1440, "ancho"], [390, "cel"]]) {
    const p = await b.newPage({ viewport: { width: w, height: 900 } });
    p.on("pageerror", (e) => errs.push(e.message));
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    const r = await p.evaluate(function (items) {
      _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
      _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: true, mcOverride: {} };
      _pedImpRender();
      const tbl = document.querySelector(".mva-tbl.wide");
      if (!tbl) return { sinTabla: true };
      const wrap = tbl.closest(".mva-tblwrap");
      const cols = tbl.querySelectorAll("colgroup col").length;
      // celdas con el contenido más ancho que la columna = texto pisado (col 1 = Descripción, recorta a propósito)
      const pisadas = [...tbl.querySelectorAll("th,td")]
        .filter((c) => c.cellIndex !== 1 && c.scrollWidth > c.clientWidth + 1)
        .map((c) => c.cellIndex + ":" + c.textContent.trim().slice(0, 20));
      // la columna Acciones (última) tiene que entrar en el área visible del wrapper
      const last = tbl.querySelector("tbody tr:last-child td:last-child");
      const accVisible = last.getBoundingClientRect().right <= wrap.getBoundingClientRect().right + 1;
      const codSticky = getComputedStyle(tbl.querySelector("tbody td:first-child")).position === "sticky";
      return {
        cols: cols,
        pisadas: pisadas,
        tablaW: Math.round(tbl.getBoundingClientRect().width),
        wrapW: Math.round(wrap.clientWidth),
        scrollX: wrap.scrollWidth - wrap.clientWidth,
        accVisible: accVisible,
        codSticky: codSticky,
        tieneBotones: /pedImpSetCurso/.test(tbl.innerHTML) && /pedImpLlego/.test(tbl.innerHTML),
        paginaScrollX: document.documentElement.scrollWidth > document.documentElement.clientWidth
      };
    }, ITEMS);
    out[tag] = r;
    await p.close();
  }
  const A = out.ancho || {}, C = out.cel || {};
  const pass =
    A.cols === 14 && A.pisadas && A.pisadas.length === 0 &&   // nada pisado en monitor
    A.scrollX === 0 && A.accVisible && A.tieneBotones &&      // entra entera, con los botones ✏️/📥
    C.pisadas && C.pisadas.length === 0 &&                    // ni en celular
    C.scrollX > 0 && C.codSticky &&                           // en celular se desliza, con Código fijo
    C.tablaW >= 1200 &&                                       // no se achica hasta pisarse
    !A.paginaScrollX && !C.paginaScrollX &&                   // el scroll es de la tabla, no de la página
    errs.length === 0;
  console.log("imp-tabla:", JSON.stringify(out), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
