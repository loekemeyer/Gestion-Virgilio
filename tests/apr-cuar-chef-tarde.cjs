/* Regresión v21.32 — UNA RESPUESTA NO OPINA SOBRE LO QUE NO PREGUNTÓ.

   Luis, 2026-09-23: "primero revisá por qué Ierakuin no está en el submódulo de cuarentena.
   Se sigue escapando".  Síntoma: `web CH 218 · Ierakuin Srl (CH 1665)` se dibuja en la lista
   normal de «Pedidos a programar» CON el chip "🚧 retenido en cuarentena · no se arma solo"
   (que lo pinta el backend, `gv_ppp_web_dia_salida`), mientras el submódulo Cuarentena no lo
   tiene.  Backend medido: `gv_cuarentena_marcar` devuelve ese pedido con motivos ["deuda"]
   y $2.062.528,58 — o sea que lo que falla es cómo el front aplica la respuesta.

   POR QUÉ.  Los pedidos de Chef llegan TARDE (otra vuelta de red), así que `cuarMarcarPedidos`
   corre DOS veces por carga (v20.98): la primera con LK+ISIS y la segunda, cuando Chef llegó,
   con la lista completa.  Las dos terminaban recorriendo `_apr.pedidosTodos` —que para entonces
   YA incluye a Chef— y BORRANDO la marca de todo pedido que su respuesta no nombrara.  La
   corrida de LK no preguntó por Chef, así que si contesta última le borra la cuarentena al único
   pedido de Chef.  Es una carrera: por eso aparece y desaparece.

   ⚠ Lo que el test fija es la regla, no el orden de llegada: cada respuesta toca SÓLO los
   pedidos de su propio lote.

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { lotes: [] };
    _pppTab = "otra";                       // que no dibuje

    const lk   = { order_id: 1529, empresa: "lk",   cod: "738",  razon_social: "UN CLIENTE LK" };
    const sano = { order_id: 1530, empresa: "lk",   cod: "111",  razon_social: "SANO" };
    const chef = { order_id: 218,  empresa: "chef", cod: "1665", razon_social: "Ierakuin Srl" };

    // el backend retiene al de LK y al de Chef, cada uno cuando se lo preguntan
    const RET = { "lk:1529": ["deuda"], "chef:218": ["deuda"] };
    const espera = (ms) => new Promise((ok) => setTimeout(ok, ms));

    window.aprRpc = async function (fn, body) {
      if (fn === "gv_cuarentena_liberados") return [];
      if (fn === "gv_cuarentena_limite") return [];
      if (fn !== "gv_cuarentena_marcar") return [];
      const peds = (body && body.p_pedidos) || [];
      out.lotes.push(peds.map((x) => x.empresa + ":" + x.order_id).join(","));
      // La corrida de LK (sin Chef) tarda MÁS y contesta última: es la carrera real
      // (la de LK se reintenta ante un timeout, v20.96, y llega después).
      const tieneChef = peds.some((x) => x.empresa === "chef");
      await espera(tieneChef ? 10 : 120);
      return peds.filter((x) => RET[x.empresa + ":" + x.order_id])
                 .map((x) => ({ order_id: String(x.order_id), empresa: x.empresa,
                                motivos: RET[x.empresa + ":" + x.order_id].slice(),
                                deuda: 2062528.58 }));
    };

    // (1) primera corrida: todavía NO llegó Chef
    _apr.pedidosTodos = [lk, sano];
    _apr.pedidos = _apr.pedidosTodos.slice();
    const pA = cuarMarcarPedidos();

    // (2) Chef llega y se vuelve a controlar con la lista completa (v20.98)
    await espera(5);
    _apr.pedidosTodos = [lk, sano, chef];
    _apr.pedidos = _apr.pedidosTodos.slice();
    const pB = cuarMarcarPedidos();

    await Promise.all([pA, pB]);

    out.chefRetenido = aprEnCuarentena(chef);
    out.chefMotivos  = chef.cuarentena_motivos || null;
    out.lkRetenido   = aprEnCuarentena(lk);
    out.sanoLibre    = !aprEnCuarentena(sano);

    // (3) y lo que SÍ tiene que seguir pasando: si el lote lo incluye y ya no está retenido,
    //     la marca se limpia (si no, un pedido liberado quedaría retenido para siempre).
    RET["chef:218"] = null; delete RET["chef:218"];
    _apr.pedidos = _apr.pedidosTodos.slice();
    await cuarMarcarPedidos();
    out.seLimpia = !aprEnCuarentena(chef);
    return out;
  });

  await b.close();
  const fails = [];
  if (r.chefRetenido !== true)
    fails.push("el pedido de Chef perdió su cuarentena cuando contestó la corrida de LK (motivos: " + JSON.stringify(r.chefMotivos) + ")");
  if (r.lkRetenido !== true) fails.push("el retenido de LK quedó sin marcar");
  if (r.sanoLibre !== true)  fails.push("un pedido sano quedó marcado");
  if (r.seLimpia !== true)   fails.push("la marca no se limpia cuando el pedido SÍ estaba en el lote y ya no retiene");
  if ((r.lotes || []).length < 2) fails.push("no corrieron las dos marcaciones: " + JSON.stringify(r.lotes));
  if (errs.length) fails.push("errores de página: " + errs.join(" | "));

  if (fails.length) { console.error("apr-cuar-chef-tarde: FALLA\n  - " + fails.join("\n  - ")); process.exit(1); }
  console.log("apr-cuar-chef-tarde: OK — la corrida de LK ya no le borra la cuarentena al pedido de Chef; lotes: " + JSON.stringify(r.lotes));
})();
