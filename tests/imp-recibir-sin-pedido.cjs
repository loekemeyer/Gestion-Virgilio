/* v25.66 (Luis, 01/10) — «que dé la posibilidad de recibir algo por más que no haya pedido; cuando se aprieta,
   que el pop-up alerte que se está por recibir algo de lo que no hay pedido registrado».
   Corre el flujo de verdad con _pedImpRpc falso:
   A. sin pedido en curso, el 📥 abre la ALERTA «No hay pedido registrado» con «Recibir sin pedido»;
   B. el formulario de recepción repite la alerta y no muestra pendiente;
   C. revisar y grabar llaman a gv_imp_recibir_sin_pedido con p_importado_id (sin bache, sin p_cerrar);
   D. el confirm y la pantalla final dicen SIN PEDIDO.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function () {
    window.__calls = [];
    const CTX = { bache_id: null, sin_pedido: true, importado_id: 12, cod_art: "026", cod_stock: "026", descripcion: "CUCHARITA",
      proveedor: "Fujian", pedido_ref: "SIN PEDIDO", unidades: 0, llegadas: 0, pendiente: 0, estado: "en_curso", dual: false, empresa: "LK",
      uni_x_caja: 36, gondola: [], racks: [], insumos_pos: [], insumos_cods: [] };
    _pedImpRpc = async function (fn, body) {
      window.__calls.push({ fn: fn, body: JSON.parse(JSON.stringify(body || {})) });
      if (fn === "gv_importado_baches") return [{ id: 5, estado: "llegado", pendiente: 0 }];
      if (fn === "gv_imp_recibir_contexto_sin_pedido") return CTX;
      if (fn === "gv_imp_recibir_sin_pedido") return body.p_simular ? { ok: true, conflictos: [], sin_pedido: true }
        : { ok: true, sin_pedido: true, recepcion_id: 9, unidades: 360, cajas: 10, estado: "llegado", sobra: 0, faltante: 0 };
      return null;
    };
    const ov = () => document.getElementById("impRecOv");
    const out = {};
    await impRecibirCodigo(encodeURIComponent(JSON.stringify([{ id: 12, cod: "026", marca: "LK" }])));
    out.alerta = /No hay pedido registrado/.test(ov().innerHTML) && /SIN PEDIDO/.test(ov().innerHTML);
    const btn = [...ov().querySelectorAll("button")].find((x) => /Recibir sin pedido/.test(x.textContent));
    out.boton = !!btn;
    if (btn) { btn.click(); await new Promise((res) => setTimeout(res, 80)); }
    const h = ov().innerHTML;
    out.form = /No hay pedido registrado/.test(h) && /sin pedido registrado/.test(h) && !/pendiente <b>/.test(h) && !/Dar el pedido por recibido/.test(h);
    impRecLinea(0, "cantidad", 10);
    await impRecRevisar();
    window.__confirm = ""; window.confirm = (m) => { window.__confirm = m; return true; };
    await impRecGrabar();
    const calls = window.__calls.filter((c) => c.fn === "gv_imp_recibir_sin_pedido");
    out.llamadas = calls.map((c) => [c.body.p_simular, c.body.p_importado_id, "p_bache_id" in c.body, "p_cerrar" in c.body]);
    out.viejo = window.__calls.some((c) => c.fn === "gv_imp_recibir");
    out.confirm = /NO HAY PEDIDO REGISTRADO/.test(window.__confirm);
    out.final = /recepción SIN PEDIDO/.test(ov().innerHTML) && !/El pedido quedó RECIBIDO/.test(ov().innerHTML);
    return out;
  });
  const fail = [];
  if (!r.alerta || !r.boton) fail.push("A alerta: " + JSON.stringify([r.alerta, r.boton]));
  if (!r.form) fail.push("B formulario sin pedido");
  if (JSON.stringify(r.llamadas) !== '[[true,12,false,false],[false,12,false,false]]' || r.viejo) fail.push("C llamadas: " + JSON.stringify(r.llamadas) + " viejo=" + r.viejo);
  if (!r.confirm || !r.final) fail.push("D textos: " + JSON.stringify([r.confirm, r.final]));
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.log("imp-recibir-sin-pedido: ✗ " + fail.join(" · ")); process.exit(1); }
  console.log("imp-recibir-sin-pedido: OK — alerta sin pedido · formulario sin pendiente · llama a gv_imp_recibir_sin_pedido · textos SIN PEDIDO");
})();
