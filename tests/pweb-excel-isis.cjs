/* Regresión (idea 3717): el Excel para ISIS también sirve para las NP de la PPP Web.
   Es el último paso del circuito: se pickea el pedido web y después hay que
   importarlo a ISIS para facturar. Verifica que:
   (a) las NP vayan ENTRECOMILLADAS en el in.() — "LK 01343" tiene un espacio y sin
       comillas PostgREST no lo resuelve: esas filas se caían del archivo EN SILENCIO,
   (b) la fecha de una NP web salga de PPP_Web_Programacion.fecha_recep, porque
       PPP_Base_Pedidos (de donde sale la de ISIS) no tiene las NP web,
   (c) una NP de ISIS siga sacando su fecha de PPP_Base_Pedidos, como siempre. */
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
    const urls = [];
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o),
                           headers: { get: () => "0-0/1" } });
    window.fetch = async (url) => {
      const u = String(url); urls.push(u);
      if (u.includes("Entregas_Virgilio")) return json([
        { id: 1, np: "LK 01343", cod_art: "027", cajas_pedidas: 2, cajas_entregadas: 2 },
        { id: 2, np: "98574",   cod_art: "505", cajas_pedidas: 1, cajas_entregadas: 1 }
      ]);
      if (u.includes("PPP_Base_Pedidos"))       return json([{ pedido: "98574", fecha: "2026-08-30" }]);
      if (u.includes("PPP_Web_Programacion"))   return json([{ np: 1343, empresa: "lk", fecha_recep: "2026-09-03" }]);
      if (u.includes("vista_uxb_articulo"))     return json([{ cod: "027", uxb: 24 }, { cod: "505", uxb: 12 }]);
      if (u.includes("clientes_vendedor"))      return json([{ cod_cliente: "4109", vend: "21" }]);
      if (u.includes("lk_pedidos_match"))       return json([]);
      return json([]);
    };
    window._facLastTandas = [{ pedidos: [
      { np: "LK 01343", cod: "4109", razonSocial: "Di Leo" },
      { np: "98574",   cod: "1792", razonSocial: "Otro" }
    ] }];
    const filas = await _facXlsArmar(["LK 01343", "98574"]);
    const inUrl = urls.find(u => u.includes("Entregas_Virgilio")) || "";
    const byNp = {}; filas.forEach(f => { byNp[f.np] = f; });
    return {
      npEntrecomillada: inUrl.includes('%22LK%201343%22') || inUrl.includes('"LK 01343"'),
      pidioWebProg:     urls.some(u => u.includes("PPP_Web_Programacion")),
      filas:            filas.length,
      fechaWeb:         byNp["LK 01343"] ? byNp["LK 01343"].fechaTxt : null,
      fechaIsis:        byNp["98574"]   ? byNp["98574"].fechaTxt   : null
    };
  });

  // fechaTxt sale en dd/MM/yyyy
  const ok = r.npEntrecomillada && r.pidioWebProg && r.filas === 2
    && /03\/09\/2026/.test(String(r.fechaWeb)) && /30\/08\/2026/.test(String(r.fechaIsis));
  console.log("pweb-excel-isis:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
