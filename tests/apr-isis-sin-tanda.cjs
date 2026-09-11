/* v14.35 — las NP de ISIS SIN tanda entran a "A Programar" y se programan CON SU NÚMERO.
   Dueño (08/09): 98686-98694 / 44618 (web que ISIS ya numeró) y 44609-44617 (Cencosud, KRIKOS) quedaron con
   fecha de entrega y sin tanda, y esta solapa no las mostraba (lista pedidos de la página; las saca
   gv_pedidos_web_excluidos, y las de Krikos ni siquiera tienen pedido web).
   (a) salen como tarjeta, con la NP real y el chip "de ISIS";
   (b) la línea "por qué siguen acá" las cuenta aparte;
   (c) NO se pueden juntar con un pedido de la página en la misma tanda;
   (d) programarlas llama gv_ppp_isis_programar con las NP — NUNCA gv_ppp_web_tanda_nueva/agregar
       (eso les daría una NP web nueva y al facturar se duplicarían en ISIS);
   (e) si la RPC falla, el error se muestra y no se pierde la selección.
   RPC y feeds interceptados por fetch. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  // v15.40: sin este fallback el test muere en CI (el runner instala playwright con npm,
  // no tiene /opt/node22) y, como run.sh corta en el primero que falla, todo lo que venía
  // después NUNCA se corrió en GitHub. Mismo patrón que ya tenían los demás tests.
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => "0-0/0" } });
    window.confirm = () => true; window.alert = () => {};
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "test@x" })) + ".s" };
    window.pwebLkToken = async () => "tok";
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_ppp_isis_programar") {
          if (window.__falla) return { ok: false, status: 400, json: async () => ({ message: "Un súper no se junta con clientes en la misma tanda: separalas en dos." }), text: async () => '{"message":"Un súper no se junta con clientes en la misma tanda: separalas en dos."}', headers: { get: () => null } };
          return ok([{ codigo: "E13A", np_programadas: 2, m3: 0.27, aviso: null }]);
        }
        if (m[1] === "gv_ppp_web_calendario") return ok([{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 1, cupo: 6, resta: 5 }]);
        if (m[1] === "gv_pedidos_web_np_chef_admin") return ok([]);
        return ok([]);
      }
      if (u.indexOf("gv_ppp_isis_sin_tanda") >= 0) return ok([
        { np: "98686", cod: "1792", razon_social: "Dapelo Claudio Marcelo", tipo: "WEB", fecha_recep: "2026-09-02", fecha_entrega: "2026-09-14", zona: "Zona 2 - CABA Centro", barrio: "Almagro", direccion: "x", m3: 0.163, lineas: 18, cajas: 20, es_super: false, empresa: "lk" },
        { np: "98687", cod: "1792", razon_social: "Dapelo Claudio Marcelo", tipo: "WEB", fecha_recep: "2026-09-02", fecha_entrega: "2026-09-14", zona: "Zona 2 - CABA Centro", barrio: "Almagro", direccion: "x", m3: 0.107, lineas: 18, cajas: 12, es_super: false, empresa: "lk" }
      ]);
      if (u.indexOf("v_pedidos_web_np") >= 0) return ok([
        { empresa: "lk", order_id: 1401, np_idx: 1, cod: "111", razon_social: "Bazar Colucci S.A.", fecha_recep: "2026-09-08", direccion: "x", lineas: 5, cajas: 6, items: [{ art: "027", cajas: 2 }], m3: 0.25, m3_parcial: false, localidad: "Barracas" }
      ]);
      return ok([]);
    };
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    for (let i = 0; i < 40 && _apr.cargando; i++) await new Promise((res) => setTimeout(res, 100));
    _apr.cargando = false; _apr.listo = false; _apr.err = "";
    await aprCargar();
    await new Promise((res) => setTimeout(res, 200));
    const prev = document.getElementById("pppPreview");

    // (a) están en la lista, con su NP real
    out.n = (_apr.pedidos || []).length;
    out.isis = (_apr.pedidos || []).filter((x) => x._isis).map((x) => x.np);
    out.html = prev.innerHTML;
    out.chipNp = [...prev.querySelectorAll(".apr-chip-ped")].map((e) => e.textContent.trim());
    out.chipIsis = [...prev.querySelectorAll(".apr-chip-sal")].map((e) => e.textContent.trim());
    // (b) la línea de por qué siguen acá
    out.porque = (prev.querySelector(".apr-porque") || {}).textContent || "";

    // (c) mezclada con un pedido de la página → no pasa
    aprSel("lk:np98686"); aprSel("lk:1401"); aprPasoDia();
    out.mixta = { paso: _apr.paso, msg: _apr.msg };
    aprSel("lk:1401"); _apr.msg = ""; _apr.msgErr = false;

    // (d) sólo NP de ISIS → gv_ppp_isis_programar con las NP
    aprSel("lk:np98687"); aprPasoDia();
    out.paso = _apr.paso;
    aprElegirDia("2026-09-14");
    calls.length = 0;
    await aprConfirmar();
    out.calls = calls.map((c) => c.fn);
    out.cuerpo = (calls.find((c) => c.fn === "gv_ppp_isis_programar") || {}).body || null;
    out.msg = _apr.msg; out.msgErr = _apr.msgErr;

    // (e) error del backend: se muestra tal cual
    window.__falla = true;
    aprSel("lk:np98686"); aprPasoDia(); aprElegirDia("2026-09-14");
    await aprConfirmar();
    out.err = { msg: _apr.msg, msgErr: _apr.msgErr };
    return { out, errs: [] };
  });

  const o = r.out; let fallas = 0;
  const t = (cond, txt) => { console.log((cond ? "  ok    · " : "  FALLA · ") + txt); if (!cond) fallas++; };
  t(o.isis.join(",") === "98686,98687", "(a) las 2 NP de ISIS sin tanda entran a la lista");
  t(o.n === 3, "(a) conviven con el pedido de la página (3 tarjetas)");
  t(o.chipNp.indexOf("NP 98686") >= 0 && o.chipNp.indexOf("NP 98687") >= 0, "(a) la tarjeta muestra la NP real, no 'web LK …'");
  t(o.html.indexOf("Dapelo Claudio Marcelo") >= 0, "(a) con la razón social del cliente");
  t(o.chipIsis.some((x) => x.indexOf("de ISIS") >= 0), "(a) chip 'de ISIS · la programás vos' (el automático no las toca)");
  t(/2\s*<\/b>?\s*con número de ISIS|>2<\/b> con número de ISIS/.test(o.porque) || o.porque.indexOf("con número de ISIS y sin tanda") >= 0, "(b) la línea de arriba las cuenta aparte");
  t(o.mixta.paso === 1 && /ISIS y un pedido de la página/.test(o.mixta.msg), "(c) NP de ISIS + pedido de la página en una tanda → bloqueado");
  t(o.paso === 2, "(d) sólo NP de ISIS: pasa al paso 2");
  t(o.calls.indexOf("gv_ppp_isis_programar") >= 0, "(d) programa por gv_ppp_isis_programar");
  t(o.calls.indexOf("gv_ppp_web_tanda_nueva") < 0 && o.calls.indexOf("gv_ppp_web_tanda_agregar") < 0, "(d) NUNCA por la vía web (no las renumera → no duplica en ISIS)");
  t(!!o.cuerpo && String(o.cuerpo.p_nps) === "98686,98687" && o.cuerpo.p_fecha === "2026-09-14", "(d) manda las NP y el día");
  t(!o.msgErr && /E13A/.test(o.msg) && /2 NP de ISIS/.test(o.msg), "(d) confirma con el código de tanda que devolvió la base");
  t(o.err.msgErr === true && /súper no se junta/.test(o.err.msg), "(e) el error del backend se muestra tal cual");
  t(errs.length === 0, "sin errores de página");
  if (errs.length) console.log("  errores:", errs.join(" | "));
  console.log("  detalle:", JSON.stringify({ isis: o.isis, chipNp: o.chipNp, porque: o.porque.slice(0, 120), calls: o.calls, cuerpo: o.cuerpo, msg: o.msg }));
  await b.close();
  console.log(fallas ? "apr-isis-sin-tanda: " + fallas + " FALLA(S)" : "apr-isis-sin-tanda: OK (14 chequeos)");
  process.exit(fallas ? 1 : 0);
})();
