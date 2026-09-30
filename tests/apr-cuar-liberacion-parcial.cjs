/* Regresión v25.38 — UNA LIBERACIÓN PARCIAL NO LIBERA TODO.

   Caso LK 1576 · Hsu Ya Wen (LK 4172), 30/09: retenido por "limite_credito" + "cliente_nuevo"
   (2 pedidos facturados). Vivi liberó "limite_credito" — el botón de Cuarentena nunca libera
   "cliente_nuevo" (v20.89: eso lo hace el ✅ del pipeline). El backend lo siguió reteniendo por
   cliente nuevo, pero el front le daba prioridad a la fila de GV_Cuarentena_Liberados: el
   pedido quedaba en la lista normal con "Liberado de cuarentena" y el chip "🆕 cliente nuevo
   sin aprobar · no se arma solo", fuera del pipeline y sin forma de aprobarlo.

   Fija: (A) liberado parcial + backend que sigue reteniendo → sigue retenido y cae en el
   pipeline; (B) liberado y el backend ya no retiene → liberado como siempre; (C) liberación
   vieja sin detalle → liberado. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    _pppTab = "otra";   // que no dibuje
    const parcial = { order_id: 1576, empresa: "lk", cod: "4172", razon_social: "Hsu Ya Wen" };
    const total   = { order_id: 1577, empresa: "lk", cod: "900",  razon_social: "LIBERADO ENTERO" };
    const viejo   = { order_id: 1578, empresa: "lk", cod: "901",  razon_social: "LIBERACION VIEJA" };

    window.aprRpc = async function (fn) {
      // lo que el backend sigue reteniendo (marcar_calc ya descuenta lo liberado)
      if (fn === "gv_cuarentena_marcar") return [{ order_id: "1576", empresa: "lk", motivos: ["cliente_nuevo"], nuevo_pedidos: 2 }];
      if (fn === "gv_cuarentena_limite") return [{ order_id: "1576", empresa: "lk", exceso: 1000, limite: 500000 },
                                                 { order_id: "1577", empresa: "lk", exceso: 10, limite: 100 }];
      if (fn === "gv_cuarentena_liberados") return [{ empresa: "lk", order_id: "1576", motivos: ["limite_credito"] },
                                                    { empresa: "lk", order_id: "1577", motivos: ["limite_credito"] },
                                                    { empresa: "lk", order_id: "1578", motivos: [] }];
      return [];
    };
    _apr.pedidosTodos = [parcial, total, viejo];
    _apr.pedidos = _apr.pedidosTodos.slice();
    await cuarMarcarPedidos();

    return {
      parcialRetenido: aprEnCuarentena(parcial),
      parcialMotivos: parcial.cuarentena_motivos || null,
      parcialEnPipe: pipeLista().some((x) => x.order_id === 1576),
      totalLibre: !aprEnCuarentena(total) && total._cuarLiberado === true,
      viejoLibre: !aprEnCuarentena(viejo) && viejo._cuarLiberado === true,
    };
  });

  await b.close();
  const fails = [];
  if (r.parcialRetenido !== true) fails.push("la liberación de limite_credito liberó también cliente_nuevo (motivos: " + JSON.stringify(r.parcialMotivos) + ")");
  if (JSON.stringify(r.parcialMotivos) !== '["cliente_nuevo"]') fails.push("motivos que quedan: " + JSON.stringify(r.parcialMotivos) + " (esperado [\"cliente_nuevo\"])");
  if (r.parcialEnPipe !== true) fails.push("el pedido no cae en el pipeline de clientes nuevos");
  if (r.totalLibre !== true) fails.push("un pedido liberado que el backend ya no retiene quedó retenido");
  if (r.viejoLibre !== true) fails.push("una liberación vieja sin detalle dejó de liberar");
  if (errs.length) fails.push("errores de página: " + errs.join(" | "));

  if (fails.length) { console.error("apr-cuar-liberacion-parcial: FALLA\n  - " + fails.join("\n  - ")); process.exit(1); }
  console.log("apr-cuar-liberacion-parcial: OK — liberar limite_credito no suelta a un cliente nuevo; va al pipeline");
})();
