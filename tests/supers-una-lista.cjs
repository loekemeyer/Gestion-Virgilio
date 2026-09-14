/* v17.72 (Luis, 2026-09-14: "no puede haber 3 y 1 en el front… fijate si se puede unificar en una")
   — LA LISTA DE SÚPER ES UNA SOLA Y VIVE EN LA BASE (`GV_Supers` → vista `gv_supers`).
   Lo que se chequea del front:
     (a) `pppEsSuper` mira (empresa, código), no el código solo: el 2444 de Chef es Cencosud y el
         2444 de LK es Relca S.R.L. — la versión vieja los confundía;
     (b) la lista se lee de la base, no del localStorage (ahí sólo queda la caché offline);
     (c) el editor escribe por RPC (gv_supers_set / gv_supers_baja), no en el localStorage;
     (d) las otras dos señales (Tipo KRIKOS y barrio Súper) siguen valiendo como red de seguridad;
     (e) el nombre corto del camión sale de la MISMA lista (ya no hay mapas hardcodeados).
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const pedidos = [];
    const LISTA = [
      { empresa: "lk",   cod: "801",  nombre: "Coto",       super_key: "coto",     cuit: "30548083156" },
      { empresa: "chef", cod: "2261", nombre: "Coto",       super_key: "coto",     cuit: "30548083156" },
      { empresa: "chef", cod: "2444", nombre: "Jumbo",      super_key: "cencosud", cuit: "30590360763" },
      { empresa: "lk",   cod: "4263", nombre: "Gigot",      super_key: "gigot",    cuit: "30627435033" },
      { empresa: "lk",   cod: "771",  nombre: "La Anonima", super_key: "laanonima", cuit: "30506730038" }
    ];
    window.fetch = async function (url, opt) {
      const u = String(url);
      pedidos.push({ u: u, body: opt && opt.body ? JSON.parse(opt.body) : null });
      if (/gv_supers\?/.test(u)) return { ok: true, status: 200, json: async () => LISTA };
      return { ok: true, status: 200, text: async () => "null", json: async () => null };
    };
    // (b) el localStorage NO es la fuente: se pisa con lo que dice la base
    try { localStorage.setItem("vir_ppp_supers_v2", JSON.stringify([{ empresa: "lk", cod: "9999", nombre: "Basura vieja" }])); } catch (_e) {}
    _pppSupers = null; _pppSupersTs = 0;
    pppLoadSupers();                                  // dispara la carga
    await new Promise((res) => setTimeout(res, 200));
    out.leeDeLaBase = pedidos.some((x) => /gv_supers\?select=empresa,cod,nombre,super_key,cuit&activo=is\.true/.test(x.u));
    out.pisaCache = _pppSupers.length === 5 && !_pppSupers.some((s) => s.cod === "9999");
    out.guardaCache = (JSON.parse(localStorage.getItem("vir_ppp_supers_v2") || "[]") || []).length === 5;

    // (a) empresa + código, no el código solo
    const mk = (o) => Object.assign({ cod: "", np: "", tipo: "", localidad: "", razon_social: "" }, o);
    out.cotoLk      = pppEsSuper(mk({ cod: "801",  np: "98630" }));                  // NP > 90000 → LK
    out.cotoCh      = pppEsSuper(mk({ cod: "2261", np: "44620" }));                  // NP 4xxxx  → Chef
    out.cencosudCh  = pppEsSuper(mk({ cod: "2444", np: "44621" }));
    out.relcaLkNoEs = pppEsSuper(mk({ cod: "2444", np: "98640" })) === false;        // el 2444 de LK NO es súper
    out.cotoChNoEnLk = pppEsSuper(mk({ cod: "2261", np: "98641" })) === false;       // el 2261 no existe en LK
    out.gigotArreglado = pppEsSuper(mk({ cod: "4263", np: "98650" }));               // antes la lista decía 5000
    out.cod5000YaNo = pppEsSuper(mk({ cod: "5000", np: "98651" })) === false;
    out.empresaExplicita = pppEsSuper(mk({ cod: "2444", empresa: "chef", np: "" })) &&
                           pppEsSuper(mk({ cod: "2444", empresa: "lk", np: "" })) === false;
    out.npWeb = pppEsSuper(mk({ cod: "801", np: "LK 0052" })) &&
                pppEsSuper(mk({ cod: "2444", np: "CH 0019" }));
    out.cualquiera = pppEsSuper(mk({ cod: "1234", np: "98660" })) === false;

    // (d) las otras dos señales siguen valiendo
    out.krikos = pppEsSuper(mk({ cod: "1234", np: "98661", tipo: "KRIKOS" }));
    out.zonaSuper = (function () {
      // un barrio cuya zona ES "Super" según la tabla de barrios (se busca uno real)
      const b = Object.keys(PPP_BARRIO_ZONA || {}).filter((k) => PPP_BARRIO_ZONA[k] === "Super")[0];
      if (!b) return false;
      out.barrioSuper = b;
      return pppEsSuper(mk({ cod: "1234", np: "98662", localidad: b }));
    })();

    // (e) el nombre corto del camión sale de la misma lista
    out.nombreCorto = _pppSuperNombre(mk({ cod: "2444", np: "44621", razon_social: "CENCOSUD S.A." })) === "Jumbo" &&
                      _pppSuperNombre(mk({ cod: "771", np: "98663", razon_social: "S.A.Imp Y Exp De La Patagonia" })) === "La Anonima";
    out.sinMapasViejos = (typeof PPP_SUPER_ALIAS === "undefined") && (typeof PPP_SUPER_LEGACY === "undefined");

    // (c) el editor escribe en la base, no en el localStorage
    window.requireSupervisor = function () { return true; };
    pedidos.length = 0;
    document.getElementById("pppSupEmp").value = "chef";
    document.getElementById("pppSupCod").value = "2686";
    document.getElementById("pppSupNom").value = "Chango Mas";
    await pppSuperAdd(); await new Promise((res) => setTimeout(res, 150));
    const alta = pedidos.find((x) => /rpc\/gv_supers_set/.test(x.u));
    out.altaRpc = !!alta && alta.body.p_empresa === "chef" && alta.body.p_cod === "2686" && alta.body.p_nombre === "Chango Mas";
    out.altaNoLocal = !(JSON.parse(localStorage.getItem("vir_ppp_supers_v2") || "[]") || []).some((s) => s.cod === "2686");

    window.confirm = function () { return true; };
    pedidos.length = 0;
    await pppSuperDel("chef", "2444"); await new Promise((res) => setTimeout(res, 150));
    const baja = pedidos.find((x) => /rpc\/gv_supers_baja/.test(x.u));
    out.bajaRpc = !!baja && baja.body.p_empresa === "chef" && baja.body.p_cod === "2444";

    // la ficha del editor muestra la empresa de cada código
    document.getElementById("pppSupersOverlay").classList.add("show");
    pppSupersRender();
    const h = document.getElementById("pppSupersList").innerHTML;
    out.listaConEmpresa = /LK 801/.test(h) && /CH 2261/.test(h) && /CUIT 30548083156/.test(h);
    return out;
  });

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(r.leeDeLaBase, "(b) la lista se lee de gv_supers (la base)");
  t(r.pisaCache, "(b) lo que dice la base pisa la caché del localStorage");
  t(r.guardaCache, "(b) y se guarda como caché para cuando no haya red");
  t(r.cotoLk, "(a) Coto LK 801 es súper");
  t(r.cotoCh, "(a) Coto CH 2261 es súper");
  t(r.cencosudCh, "(a) Cencosud CH 2444 es súper");
  t(r.relcaLkNoEs, "(a) el 2444 de LK (Relca S.R.L.) NO es súper");
  t(r.cotoChNoEnLk, "(a) un código de Chef no cuenta como súper en LK");
  t(r.gigotArreglado, "(a) Gigot es LK 4263 (Matiz SA)");
  t(r.cod5000YaNo, "(a) el cod 5000 fantasma ya no está");
  t(r.empresaExplicita, "(a) si el pedido trae empresa, manda ésa");
  t(r.npWeb, "(a) una NP web (LK 0052 / CH 0019) también resuelve su empresa");
  t(r.cualquiera, "(a) un cliente común no es súper");
  t(r.krikos, "(d) Tipo KRIKOS sigue marcando súper");
  t(r.zonaSuper, "(d) barrio de zona Súper sigue marcando súper");
  t(r.nombreCorto, "(e) el nombre corto del camión sale de la misma lista");
  t(r.sinMapasViejos, "(e) ya no existen los mapas hardcodeados PPP_SUPER_ALIAS / _LEGACY");
  t(r.altaRpc, "(c) el alta va por gv_supers_set con empresa + código");
  t(r.altaNoLocal, "(c) el alta NO se guarda en el localStorage");
  t(r.bajaRpc, "(c) la baja va por gv_supers_baja");
  t(r.listaConEmpresa, "(c) el editor muestra empresa, código y CUIT de cada uno");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  console.log(ok ? "\nOK supers-una-lista" : "\nFALLÓ supers-una-lista");
  process.exit(ok ? 0 : 1);
})();
