/* Regresión v22.29 — UN PEDIDO SIN CLASIFICAR NO SE DIBUJA EN «PEDIDOS A PROGRAMAR».

   Luis, 2026-09-24: "se cambió a un límite más alto para que empiece a tirar pedidos a programar
   a clientes nuevos/cuarentena, y debido a la demora puede causar confusión. ¿Se puede hacer que
   no se muestren hasta que estén en su lugar asignado?".  La marcación (gv_cuarentena_marcar)
   tarda segundos; mientras tanto el retenido se veía en la lista normal, como si fuera programable.

   Fija: (A) durante la marcación el pedido nuevo NO está en la lista y sale el cartel ⏳;
         (B) al terminar, el retenido está en Cuarentena y el sano en la lista;
         (C) al recargar, el ya clasificado hereda su lugar (no parpadea);
         (D) si la marcación falla, el pedido se ve igual (nunca desaparece para siempre).
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
    const out = {};
    _pppTab = "otra";
    const espera = (ms) => new Promise((ok) => setTimeout(ok, ms));
    const mk = (id, cod, rs) => ({ order_id: id, empresa: "lk", cod: cod, razon_social: rs, zona: "Zona 1", localidad: "", fecha_recep: "2026-09-24", bloques: [] });
    const ret = mk(1601, "900", "RETENIDO SA"), sano = mk(1602, "901", "SANO SRL");
    let falla = false;
    window.aprRpc = async function (fn, body) {
      if (fn !== "gv_cuarentena_marcar") return [];
      await espera(150);
      if (falla) throw new Error("canceling statement due to statement timeout");
      return ((body && body.p_pedidos) || []).filter((x) => x.order_id === "1601")
        .map((x) => ({ order_id: "1601", empresa: "lk", motivos: ["deuda"], deuda: 5000 }));
    };
    _apr.listo = true;
    const col = () => aprColPedidos();

    _apr.pedidosTodos = [ret, sano]; _apr.pedidos = _apr.pedidosTodos.slice();
    const pr = cuarMarcarPedidos();
    await espera(20);
    const h1 = col();
    out.A_retOculto = h1.indexOf("RETENIDO SA") < 0;
    out.A_sanoOculto = h1.indexOf("SANO SRL") < 0;
    out.A_cartel = h1.indexOf("clasificándose") >= 0;
    await pr;
    const h2 = col();
    out.B_retFuera = h2.indexOf("RETENIDO SA") < 0 && aprEnCuarentena(ret);
    out.B_sanoVisible = h2.indexOf("SANO SRL") >= 0;
    out.B_sinCartel = h2.indexOf("clasificándose") < 0;

    // (C) recarga: objetos nuevos, heredan la clasificación mientras corre la nueva marcación
    const ret2 = mk(1601, "900", "RETENIDO SA"), sano2 = mk(1602, "901", "SANO SRL");
    _apr.pedidosTodos = aprHeredarCuar([ret2, sano2], _apr.pedidosTodos); _apr.pedidos = _apr.pedidosTodos.slice();
    const pr2 = cuarMarcarPedidos();
    await espera(20);
    const h3 = col();
    out.C_sanoSigue = h3.indexOf("SANO SRL") >= 0 && h3.indexOf("RETENIDO SA") < 0;
    await pr2;

    // (D) falla la marcación: el nuevo se ve igual
    falla = true;
    const nuevo = mk(1603, "902", "NUEVO SA");
    _apr.pedidosTodos = _apr.pedidosTodos.concat([nuevo]); _apr.pedidos = _apr.pedidosTodos.slice();
    await cuarMarcarPedidos();
    out.D_visible = col().indexOf("NUEVO SA") >= 0;
    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter((k) => r[k] !== true);
  if (errs.length) fails.push("errores de página: " + errs.join(" | "));
  if (fails.length) { console.error("apr-clasificando-oculto: FALLA " + JSON.stringify(r) + "\n  - " + fails.join("\n  - ")); process.exit(1); }
  console.log("apr-clasificando-oculto: OK — sin clasificar no se dibuja, recarga sin parpadeo, fallo visible");
})();
