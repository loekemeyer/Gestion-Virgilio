/* v25.37 (30/09) — «Denegado por Cervantes».
   Lo que se recibe con destino 🏭 Cervantes le aparece a Cervantes en Recepción de Insumos de GP2 con Sí / No.
   Si dice NO, la base (trigger gv_ingreso_virgilio_denegado) vuelve a poner el pedido EN VIAJE y la pantalla lo
   marca con el chip [usuario: "en el mismo lugar que se cargaron las 3000 uni del rallador que vuelvan a
   aparecer con un cartelito de «Denegado por Cervantes»"]. Corre la pantalla de verdad con _pedImpRpc falso:
   A. la fila del código lleva el chip al lado del 📥 (y la otra fila no);
   B. 📦 Baches: el bache en curso denegado lleva «Denegado por Cervantes»;
   C. 📥 RECIBIR: el popup del pedido lo dice, con el motivo;
   D. 📜 Historial: la línea a Cervantes dice que se denegó;
   E. la lectura de denegados va con la sesión del supervisor y, si falla, la pantalla anda igual, sin chips;
   F. el mensaje de 📥 RECIBIR ya no manda a la portada de GP2.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const ITEMS = [
  { cod: "323ES", desc: "RALLADOR 4 LADOS MINI SUELTO", prov: "Hugo Wong", proyUni: 300, objetivoUni: 3000, stockUni: 0, enCurso: 3000,
    aPedirUni: 0, uniMaster: 0, fobUni: 0.3, m3Master: 0.06, det: [{ id: 167, curso: 3000, marca: "Mixto" }] },
  { cod: "026", desc: "CUCHARITA", prov: "Fujian", proyUni: 900, objetivoUni: 9000, stockUni: 5000, enCurso: 500,
    aPedirUni: 100, uniMaster: 36, fobUni: 0.1, m3Master: 0.02, det: [{ id: 12, curso: 500, marca: "LK" }] }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const fail = [];
  const r = await p.evaluate(async function (items) {
    window.__calls = [];
    const DEN = [{ bache_id: 134, importado_id: 167, cod_art: "323ES", recepcion_id: 10, unidades: 3000, motivo: "no vino nada",
      denegado_en: "2026-09-30T19:00:00Z", denegado_por: "nazareno@x" }];
    const CTX = { bache_id: 134, cod_art: "323ES", cod_stock: "323ES", descripcion: "Rallador suelto", proveedor: "Hugo Wong",
      pedido_ref: "323ES suelto", unidades: 3000, llegadas: 0, pendiente: 3000, estado: "en_curso", dual: false, empresa: "LK",
      uni_x_caja: null, es_insumo: true, gondola: [], racks: [], insumos_pos: [{ sector: "A1" }], insumos_cods: ["323ES"] };
    let denFalla = false;
    _pedImpRpc = async function (fn, body) {
      window.__calls.push(fn);
      if (fn === "gv_imp_cervantes_denegados") { if (denFalla) throw new Error("HTTP 500"); return DEN; }
      if (fn === "gv_importado_baches") return body.p_importado_id === 167
        ? [{ id: 134, estado: "en_curso", unidades: 3000, unidades_llegadas: 0, pendiente: 3000, pedido_ref: "323ES suelto" }]
        : [{ id: 90, estado: "en_curso", unidades: 500, unidades_llegadas: 0, pendiente: 500, pedido_ref: "PI 9" }];
      if (fn === "gv_imp_recibir_contexto") return CTX;
      if (fn === "gv_imp_recepcion_historial") return [{ id: 10, ts: "2026-09-30T18:31:00Z", cod_art: "323ES", descripcion: "Rallador", empresa: "LK",
        proveedor: "Hugo Wong", pedido_ref: "323ES suelto", unidades: 3000, cajas: 0, estado_bache: "llegado", por: "luis@x", es_ultima: true,
        destinos: [{ destino: "cervantes", sector: "CERVANTES", cantidad: 3000, unidad: "Uni", denegado_en: "2026-09-30T19:00:00Z",
                     denegado_unidades: 3000, denegado_motivo: "no vino nada" }] }];
      return null;
    };
    const out = {};
    const espera = () => new Promise((res) => setTimeout(res, 60));
    // A — la tabla
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    await _impCervDenRepintar(); await espera();
    out.filas = [...document.querySelectorAll(".mva-tbl.wide tbody tr")].map((tr) => tr.cells[0].textContent.trim().slice(0, 5) + "=" + !!tr.querySelector(".imp-cerv-den")).sort();
    // B — 📦 Baches
    await pedImpBaches(167, encodeURIComponent("323ES"), encodeURIComponent("Hugo Wong"));
    const bov = document.getElementById("impBachesOv");
    out.baches = /Denegado por Cervantes/.test(bov.innerHTML) && /no vino nada/.test(bov.innerHTML);
    pedImpBachesCerrar();
    // C — 📥 RECIBIR
    await impRecibirAbrir(167);
    const rov = document.getElementById("impRecOv");
    out.recibir = /Denegado por Cervantes/.test(rov.innerHTML) && /Cervantes dijo que esto no le llegó/.test(rov.innerHTML) && /no vino nada/.test(rov.innerHTML);
    impRecCerrar();
    // D — Historial
    await openImpHistRecep();
    const hb = document.getElementById("stkPopBody").innerHTML;
    out.hist = /Cervantes/.test(hb) && /Denegado por Cervantes/.test(hb);
    // E — la lectura falla: sin chips y sin error
    denFalla = true;
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    await _impCervDenRepintar(); _pedImpRender(); await espera();
    out.sinChipsSiFalla = !document.querySelector("#stkPopBody .imp-cerv-den") && _impCervDen.st === "err";
    out.llamo = window.__calls.filter((f) => f === "gv_imp_cervantes_denegados").length;
    return out;
  }, ITEMS);
  if (JSON.stringify(r.filas) !== '["026=false","323ES=true"]') fail.push("A fila del código: " + JSON.stringify(r.filas));
  if (!r.baches) fail.push("B Baches sin chip");
  if (!r.recibir) fail.push("C RECIBIR sin aviso");
  if (!r.hist) fail.push("D Historial sin «Denegado por Cervantes»");
  if (!r.sinChipsSiFalla || r.llamo < 3) fail.push("E lectura caída: " + JSON.stringify([r.sinChipsSiFalla, r.llamo]));
  const src = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
  const lista = /const _PED_IMP_RPC_ESCRITURA = \[([\s\S]*?)\];/.exec(src);
  if (!lista || !/"gv_imp_cervantes_denegados"/.test(lista[1])) fail.push("E la lectura de denegados no va con la sesión del supervisor");
  if (/portada de GP2 para que lo confirmen/.test(src)) fail.push("F el mensaje de RECIBIR sigue mandando a la portada de GP2");
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.log("imp-cervantes-denegado: ✗ " + fail.join(" · ")); process.exit(1); }
  console.log("imp-cervantes-denegado: OK — chip en la fila, en Baches, en RECIBIR y en el Historial · sin chips si la lectura falla");
})();
