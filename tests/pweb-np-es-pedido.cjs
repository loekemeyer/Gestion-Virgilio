/* Regresión (v12.92): LA NP WEB ES EL NÚMERO DE PEDIDO DE LA PÁGINA.

   Dueño (2026-09-05): "tiene que ser automático: ya cuando llegan a página LK y a Gestión
   Virgilio, ya vienen con numeración. En página LK ya tienen numeración. En Gestión
   Virgilio, con la lógica de los 18 ítems para LK y 15 para CH".

   Fuente de verdad: gv_ppp_web_np_label(empresa, np, np_idx) en Supabase
   (sql/gv_np_es_pedido.sql). Acá se verifica la copia del front y que la pantalla la use:
   (a) pwebNpLabel arma "LK 1350", "LK 1350-2" (bloque 2), "CH 0217" (4 dígitos), y pasado
       9999 crece ("LK 10000"),
   (b) "A Programar" muestra la NP de cada pedido APENAS llega, sin numerar nada: el
       pedido 1348 (2 bloques) se ve como LK 1348 y LK 1348-2; el 1350 como LK 1350,
   (c) la PPP etiqueta lo programado con el bloque (np_idx 2 → "-2"),
   (d) Facturación acepta el TAP de una etiqueta con bloque ("LK 1348-2"),
   (e) empresaDeNp("LK 1348-2") = LK (el prefijo manda, el sufijo no molesta). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => "0-3/4" } });

    // (a) la etiqueta
    out.l1 = pwebNpLabel("lk", 1350);
    out.l2 = pwebNpLabel("lk", 1350, 2);
    out.l3 = pwebNpLabel("chef", 217);
    out.l4 = pwebNpLabel("chef", 217, 3);
    out.l5 = pwebNpLabel("lk", 12345, 1);
    out.l6 = pwebNpLabel("lk", "1350", "1");

    // (b) A Programar: NP visible sin numerar
    window.pwebLkToken = async () => "tok";
    window.facAuthWriteHeaders = async () => ({ apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" });
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("rpc/gv_pedidos_web_excluidos") >= 0) return json([]);
      if (u.indexOf("v_pedidos_web_np") >= 0) return json([
        { empresa: "lk", order_id: 1348, np_idx: 1, cod: "4109", razon_social: "Di Leo", fecha_recep: "2026-09-04", direccion: "Bragado 5742 - Mataderos", lineas: 18, cajas: 20, items: [], m3: 0.5, m3_parcial: false, localidad: "", zona_expreso: "Zona 1" },
        { empresa: "lk", order_id: 1348, np_idx: 2, cod: "4109", razon_social: "Di Leo", fecha_recep: "2026-09-04", direccion: "Bragado 5742 - Mataderos", lineas: 4,  cajas: 5,  items: [], m3: 0.1, m3_parcial: false, localidad: "", zona_expreso: "Zona 1" },
        { empresa: "lk", order_id: 1350, np_idx: 1, cod: "1651", razon_social: "Inc SA", fecha_recep: "2026-09-04", direccion: "Corrientes 500 - Centro",  lineas: 2,  cajas: 2,  items: [], m3: 0.05, m3_parcial: false, localidad: "", zona_expreso: "Zona 2" }
      ]);
      return json([]);
    };
    _apr.emp = "lk";
    _apr.pedidos = await aprTraerPedidos();
    _apr.exp["p1348"] = true;
    _apr.tandas = _apr.tandas || [];
    let html = "";
    try { aprRender(); html = (document.getElementById("pppProgBody") || document.body).innerHTML; } catch (e) { out.errApr = String(e && e.message || e); }
    out.aprMuestra1348   = html.indexOf("LK 1348") >= 0;
    out.aprMuestra1348b2 = html.indexOf("LK 1348-2") >= 0;
    out.aprMuestra1350   = html.indexOf("LK 1350") >= 0;
    out.aprSinNumeroRpc  = true;   // no hay RPC de numerar en el fetch stub: si se llamara, aprTraerPedidos igual no la necesita

    // (c) lo programado, con bloque (content-range exacto: si no, supaFetchAll pagina y duplica)
    const json3 = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => "0-2/3" } });
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("PPP_Web_Programacion") >= 0) return json3([
        { empresa: "lk", order_id: 1348, np_idx: 1, np: 1348, cod_cliente: "4109", razon_social: "Di Leo", tanda: "GV-01A", zona: "Zona 1", fecha_entrega: "2026-09-08", m3: 0.5 },
        { empresa: "lk", order_id: 1348, np_idx: 2, np: 1348, cod_cliente: "4109", razon_social: "Di Leo", tanda: "GV-01A", zona: "Zona 1", fecha_entrega: "2026-09-08", m3: 0.1 },
        { empresa: "chef", order_id: 217, np_idx: 1, np: null, cod_cliente: "55", razon_social: "Osa", tanda: "GV-01B", zona: "Zona 1", fecha_entrega: "2026-09-08", m3: 0.2 }
      ]);
      return json([]);
    };
    const prog = await pppTraerWebProgramados();
    out.progNps = prog.map((x) => x.np).sort().join(",");

    // (d) Facturación acepta el TAP con bloque
    window.fetch = async (url) => {
      const u = String(url);
      if (u.indexOf("opcion=in.(TAL,TAP)") >= 0) return json([{ opcion: "TAP", texto: "LK 1348-2|55|GV-01A|A=586X1|NADA" }, { opcion: "TAP", texto: "LK 1350|3|GV-01A|A=1X1|NADA" }]);
      return json([]);
    };
    _facArmEvTs = 0;
    await facFetchArmadosEventos();
    out.armada1348b2 = facEstaArmada("LK 1348-2");
    out.armada1350   = facEstaArmada("LK 1350");

    // (e) la empresa sale del prefijo
    out.emp = empresaDeNp("LK 1348-2") + "/" + empresaDeNp("CH 0217-3") + "/" + empresaDeNp("98694");
    return out;
  });

  const checks = [
    ["LK 1350 (bloque 1, sin sufijo)",                         r.l1 === "LK 1350"],
    ["LK 1350-2 (bloque 2)",                                    r.l2 === "LK 1350-2"],
    ["CH 0217 (4 dígitos)",                                     r.l3 === "CH 0217"],
    ["CH 0217-3",                                               r.l4 === "CH 0217-3"],
    ["pasado 9999 crece: LK 12345",                             r.l5 === "LK 12345"],
    ["acepta strings",                                          r.l6 === "LK 1350"],
    ["A Programar muestra LK 1348 apenas llega",                r.aprMuestra1348 === true],
    ["y el bloque 2 como LK 1348-2",                            r.aprMuestra1348b2 === true],
    ["y LK 1350",                                               r.aprMuestra1350 === true],
    ["la PPP etiqueta lo programado con bloque (y CH 0217)",    r.progNps === "CH 0217,LK 1348,LK 1348-2"],
    ["Facturación toma el TAP de LK 1348-2 como armada",        r.armada1348b2 === true],
    ["y el de LK 1350",                                         r.armada1350 === true],
    ["empresaDeNp: LK / CH / LK",                               r.emp === "LK/CH/LK"],
    ["sin errores de página",                                   errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pweb-np-es-pedido: " + bad + " FALLA(S)" : "pweb-np-es-pedido: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
