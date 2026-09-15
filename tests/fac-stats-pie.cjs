/* Regresión v18.57 — los contadores, los filtros y «Revertir» de Facturación, al PIE y visibles.
   La v18.00 los escondió con display:none (pedido del dueño: en el celular ocupaban media
   pantalla ANTES de ver un solo pedido) y con eso quedaron sin acceso tres cosas que se usan:
   el filtro «Con faltante», «Corregir códigos» y «Revertir» — este último es el camino para
   destildar una NP marcada facturada por error, que es justo lo que pasó con la 44619 el 15/09
   y hubo que resolver por SQL. Luis: "mandalos abajo de todo".
   Chequea que el bloque esté DENTRO del panel del Facturador, DESPUÉS del listado, que se vea,
   y que los tres controles sigan cableados a su función.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    const pie = document.querySelector(".fac-stats-pie");
    out.existeElPie = !!pie;
    if (!pie) return out;

    // está dentro del panel del Facturador y DESPUÉS del listado
    const panel = document.getElementById("facPanelFact");
    const cont  = document.getElementById("facContainer");
    out.dentroDelPanel = !!(panel && panel.contains(pie));
    out.despuesDelListado = !!(cont &&
      (cont.compareDocumentPosition(pie) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0);

    // ya NO está arriba, en la cabecera
    const top = document.querySelector(".fac-top");
    out.yaNoEstaArriba = !(top && top.querySelector(".fac-stats"));

    // se ve (el modal está oculto, así que se mide la regla, no el layout)
    const modal = document.getElementById("facturacionModal");
    const displayAntes = modal.style.display;
    modal.style.display = "block";
    out.seVe = getComputedStyle(pie).display !== "none";
    modal.style.display = displayAntes;

    // los tres controles que habían quedado sin acceso, cableados
    const rev  = document.getElementById("facBtnRevertir");
    const falt = document.getElementById("facChipFalt");
    const corr = document.getElementById("facChipCorr");
    out.revertirEstaYCableado = !!(rev && pie.contains(rev) && /facRevertir/.test(rev.getAttribute("onclick") || ""));
    out.filtroFaltante        = !!(falt && pie.contains(falt) && /facToggleSoloFalt/.test(falt.getAttribute("onclick") || ""));
    out.filtroCorregirCods    = !!(corr && pie.contains(corr) && /facCorreccOpen/.test(corr.getAttribute("onclick") || ""));
    // y los contadores que el JS actualiza por id
    out.contadores = ["facCntTandas", "facCntPend", "facCntDone", "facDot", "facStatusTxt"]
      .every(function (id) { const el = document.getElementById(id); return el && pie.contains(el); });
    // un solo bloque: no quedó duplicado al moverlo (ids repetidos romperían el JS)
    out.sinDuplicar = document.querySelectorAll("#facBtnRevertir").length === 1 &&
                      document.querySelectorAll(".fac-stats").length === 1;
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("fac-stats-pie:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
