/* v23.45 (Luis, 28/09) — 📥 RECIBIR una importación desde el panel.
   Corre el flujo de verdad en el navegador, con _pedImpRpc falso (sin red):
   A. la tabla muestra 📥 RECIBIR en TODAS las líneas (v25.66: sin pedido también; lo mide imp-recibir-sin-pedido);
   B. dual: sin elegir empresa no deja revisar (ni llama a gv_imp_recibir);
   C. góndola llena → avisa y ofrece cómo resolver; «Poner N en góndola y el resto a A guardar»
      parte la carga en 2 destinos y vuelve a revisar;
   D. confirmar manda p_simular=false con los 2 destinos y la empresa elegida;
   E. la solapa 📜 Historial recepción dibuja la recepción (cuándo, qué, dónde).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const ITEMS = [
  { cod: "438E", key: "438E|CH", desc: "RALLADOR 4 CARAS", prov: "Fujian", proyUni: 300, objetivoUni: 3000, stockUni: 100, enCurso: 1224,
    aPedirUni: 0, uniMaster: 72, fobUni: 0.9, m3Master: 0.06, det: [{ id: 11, curso: 1224, marca: "CH" }] },
  { cod: "026", desc: "CUCHARITA", prov: "Fujian", proyUni: 900, objetivoUni: 9000, stockUni: 5000, enCurso: 0,
    aPedirUni: 100, uniMaster: 36, fobUni: 0.1, m3Master: 0.02, det: [{ id: 12, curso: 0, marca: "LK" }] }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const fail = [];
  const r = await p.evaluate(async function (items) {
    window.__calls = [];
    const CTX = { bache_id: 77, cod_art: "438E", cod_stock: "438E", descripcion: "RALLADOR 4 CARAS", proveedor: "Fujian",
      pedido_ref: "PI HT26", unidades: 1224, llegadas: 0, pendiente: 1224, estado: "en_curso", dual: true, empresa: "CH",
      uni_x_caja: 24, uni_master: 72, gondola: [{ sector: "F13", empresa: "LK", cajas_max: 16 }, { sector: "L05", empresa: "CH", cajas_max: 15 }],
      racks: [{ sector: "AD01", empresa: "LK", estado: "libre" }], insumos_pos: [], insumos_cods: [] };
    _pedImpRpc = async function (fn, body) {
      window.__calls.push({ fn: fn, body: JSON.parse(JSON.stringify(body || {})) });
      if (fn === "gv_importado_baches") return [{ id: 77, estado: "en_curso", pendiente: 1224, pedido_ref: "PI HT26" }];
      if (fn === "gv_imp_recibir_contexto") return CTX;
      if (fn === "gv_imp_recepcion_historial") return [{ id: 1, ts: "2026-09-28T15:00:00Z", cod_art: "438E", descripcion: "RALLADOR", empresa: "CH",
        proveedor: "Fujian", pedido_ref: "PI HT26", unidades: 1224, cajas: 51, estado_bache: "llegado", por: "luis@x",
        es_ultima: true, destinos: [{ destino: "gondola", sector: "L05", cantidad: 5, unidad: "cajas" }, { destino: "a_guardar", cantidad: 46, unidad: "cajas" }] }];
      if (fn === "gv_imp_recepcion_anular") return { ok: true };
      if (fn === "gv_imp_recibir") {
        const d = body.p_destinos;
        if (body.p_simular) {
          const g = d.find((x) => x.destino === "gondola");
          if (g && g.cantidad > 5 && g.resolucion !== "forzar")
            return { ok: false, conflictos: [{ destino: "gondola", sector: "L05", cantidad: g.cantidad, conflicto: "gondola_llena: capacidad 15 cajas, hay 10, entran 5 de " + g.cantidad }] };
          return { ok: true, conflictos: [] };
        }
        return { ok: true, recepcion_id: 1, unidades: 1224, cajas: 51, estado: "llegado", sobra: 0 };
      }
      return null;
    };
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const out = {};
    out.botones = [...document.querySelectorAll(".mva-tbl.wide tbody tr")].map((tr) => tr.cells[0].textContent.trim().slice(0, 4) + "=" + /impRecibirCodigo/.test(tr.innerHTML)).sort();
    await impRecibirAbrir(11);
    const ov = () => document.getElementById("impRecOv");
    out.pideEmpresa = /¿De qué empresa es\?/.test(ov().innerHTML);
    // B — viene elegida la empresa del pedido (CH); cambiarla avisa; sin empresa no deja revisar
    out.empDefault = _impRec.empresa;
    impRecSet("empresa", "LK");
    out.avisaOtraEmpresa = /Este pedido se hizo para/.test(ov().innerHTML);
    impRecSet("empresa", "");
    await impRecRevisar();
    out.sinEmpresaBloquea = /Elegí de qué empresa/.test(ov().innerHTML) && !window.__calls.some((c) => c.fn === "gv_imp_recibir");
    impRecSet("empresa", "CH");
    impRecLinea(0, "destino", "gondola");
    out.celdas = [...ov().querySelectorAll("select option")].map((o) => o.value).filter((v) => /^[A-Z]\d/.test(v));
    impRecLinea(0, "sector", "L05");
    impRecLinea(0, "cantidad", 51);
    await impRecRevisar();
    out.avisaConflicto = /La góndola no alcanza/.test(ov().innerHTML) && /¿Cómo lo resolvés\?/.test(ov().innerHTML);
    const partir = [...ov().querySelectorAll("button")].find((x) => /Poner 5 en góndola/.test(x.textContent));
    out.hayPartir = !!partir;
    if (partir) { partir.click(); await new Promise((res) => setTimeout(res, 50)); }
    out.lineas = _impRec ? _impRec.lineas.map((l) => l.destino + ":" + (l.sector || "") + ":" + l.cantidad) : [];
    out.revisadoOk = /no hay conflictos de espacio/.test(ov().innerHTML);
    window.__confirm = ""; window.confirm = (m) => { window.__confirm = m; return true; };
    await impRecGrabar();
    out.confirmo = /queda RECIBIDO/.test(window.__confirm);
    const real = window.__calls.filter((c) => c.fn === "gv_imp_recibir" && c.body.p_simular === false)[0];
    out.real = real ? { emp: real.body.p_empresa, dest: real.body.p_destinos.map((x) => x.destino + ":" + (x.sector || "") + ":" + x.cantidad), cerrar: real.body.p_cerrar, cid: !!real.body.p_client_id } : null;
    // parcial: aparece la casilla «dar por recibido» (marcada) y al desmarcarla manda p_cerrar=false
    await impRecibirBache(77);
    impRecSet("empresa", "CH"); impRecLinea(0, "cantidad", 10);
    out.casilla = /Dar el pedido por recibido/.test(ov().innerHTML);
    impRecSet("cerrar", false);
    out.sigueEnViaje = /El resto sigue en viaje/.test(ov().innerHTML);
    await impRecRevisar(); await impRecGrabar();
    const parcial = window.__calls.filter((c) => c.fn === "gv_imp_recibir" && c.body.p_simular === false).pop();
    out.parcialCerrar = parcial ? parcial.body.p_cerrar : null;
    out.grabada = /Recepción grabada/.test(ov().innerHTML);
    impRecCerrar();
    await openImpHistRecep();
    const hb = document.getElementById("stkPopBody").innerHTML;
    // v23.91: la solapa pasó a llamarse «Historial» y abre con dos vistas (Pedidos /
    // Recepciones). La de recepciones, que es la que mide este test, es la de arranque.
    out.hist = /📥 Recepciones/.test(hb) && /L05/.test(hb) && /A guardar/.test(hb) && /1\.224 u|1224 u/.test(hb);
    window.prompt = () => "prueba"; 
    await impHistAnular(1);
    out.anulo = window.__calls.some((c) => c.fn === "gv_imp_recepcion_anular" && c.body.p_id === 1 && c.body.p_motivo === "prueba");
    return out;
  }, ITEMS);
  if (JSON.stringify(r.botones) !== '["026=true","438E=true"]') fail.push("A botón RECIBIR: " + JSON.stringify(r.botones));
  if (!r.pideEmpresa || !r.sinEmpresaBloquea || r.empDefault !== "CH" || !r.avisaOtraEmpresa) fail.push("B empresa dual: " + JSON.stringify([r.empDefault, r.avisaOtraEmpresa, r.sinEmpresaBloquea]));
  if (JSON.stringify(r.celdas) !== '["L05"]') fail.push("B celdas por empresa: " + JSON.stringify(r.celdas));
  if (!r.avisaConflicto || !r.hayPartir) fail.push("C conflicto góndola");
  if (JSON.stringify(r.lineas) !== '["gondola:L05:5","a_guardar::46"]' || !r.revisadoOk) fail.push("C partir: " + JSON.stringify(r.lineas));
  if (!r.real || r.real.emp !== "CH" || JSON.stringify(r.real.dest) !== '["gondola:L05:5","a_guardar::46"]' || !r.grabada || r.real.cerrar !== true || !r.real.cid || !r.confirmo) fail.push("D grabar: " + JSON.stringify(r.real));
  if (!r.casilla || !r.sigueEnViaje || r.parcialCerrar !== false) fail.push("D2 parcial: " + JSON.stringify([r.casilla, r.sigueEnViaje, r.parcialCerrar]));
  if (!r.hist || !r.anulo) fail.push("E historial/anular: " + JSON.stringify([r.hist, r.anulo]));
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.log("imp-recibir: ✗ " + fail.join(" · ")); process.exit(1); }
  console.log("imp-recibir: OK — botón en todas las líneas · dual pide empresa · góndola llena avisa y parte · graba 2 destinos · historial");
})();
