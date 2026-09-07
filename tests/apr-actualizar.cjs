/* v14.07 — El 🔄 de A Programar arma lo que se pueda ANTES de releer.
   Dueño 07/09: "si toco el botón de las flechitas para actualizar, no sólo que traiga las NP que
   fueron llegando sino que también programe si tiene para programar automático". Antes sólo releía:
   un pedido nuevo quedaba en A Programar hasta que pasara el cron intradía (cada 15 min).
   (a) el botón llama a aprActualizar, no a aprCargar;
   (b) aprActualizar dispara la Edge Function del armado (la misma del cron: {"intradia": true}) y
       RECIÉN DESPUÉS relee;
   (c) mientras arma lo dice en la barra;
   (d) si el armado falla, igual relee — nunca deja la pantalla vieja;
   (e) no se puede disparar dos veces a la vez;
   (f) va con el token del supervisor (la función tiene verify_jwt), no con ninguna clave de servicio.
   Sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { orden: [] };
    window.facAuthWriteHeaders = async () => ({ apikey: "anon-key", Authorization: "Bearer TOKEN-SUPERVISOR", "Content-Type": "application/json" });
    let armados = 0, releidos = 0;
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (u.indexOf("/functions/v1/gv-ppp-web-tandas-diarias") >= 0) {
        armados++; out.orden.push("armar");
        out.llamada = { metodo: (opt && opt.method) || "", body: (opt && opt.body) || "", auth: (opt && opt.headers && opt.headers.Authorization) || "" };
        if (window.__fallaArmado) throw new Error("boom");
        await new Promise((r) => setTimeout(r, 30));
        return { ok: true, status: 200, json: async () => ({ ok: true, tandas: 1 }), text: async () => "{}", headers: { get: () => null } };
      }
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => null } };
    };
    window.aprCargar = async () => { releidos++; out.orden.push("releer"); };

    // (a) el botón
    _apr.listo = true; _apr.pedidos = []; _apr.cargando = false; _apr.err = null;
    // (b)+(f) armar y después releer
    await aprActualizar();
    out.armados = armados; out.releidos = releidos;
    out.metodo = out.llamada.metodo;
    out.body = out.llamada.body;
    out.auth = out.llamada.auth;

    // (d) si el armado falla, igual relee
    window.__fallaArmado = true; out.orden.length = 0;
    await aprActualizar();
    out.trasFallar = out.orden.slice();
    window.__fallaArmado = false;

    // (e) no dispara dos veces a la vez
    _apr.armando = true; out.orden.length = 0;
    await aprActualizar();
    out.reentrada = out.orden.length;
    _apr.armando = false;

    // (c) el cartel mientras arma
    _apr.armando = true;
    const bar = (typeof aprRender === "function") ? (function () { aprRender(); const el = document.getElementById("pppPreview"); return el ? el.innerHTML : ""; })() : "";
    out.cartel = /Armando lo que se pueda…/.test(bar);
    out.botonEnBarra = /onclick="aprActualizar\(\)"/.test(bar);
    _apr.armando = false;
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.botonEnBarra, "el 🔄 de la barra llama a aprActualizar (antes era aprCargar)");
  chk(r.armados === 1 && r.releidos === 1, "una pasada = un armado + una relectura (" + r.armados + "/" + r.releidos + ")");
  chk(JSON.stringify(r.orden.slice(0, 2)) !== '["releer","armar"]', "no relee antes de armar");
  chk(r.metodo === "POST" && /"intradia":true/.test(String(r.body).replace(/\s/g, "")), "dispara el armado intradía, el mismo del cron (" + r.body + ")");
  chk(r.auth === "Bearer TOKEN-SUPERVISOR", "con el token del supervisor, sin claves de servicio");
  chk(JSON.stringify(r.trasFallar) === '["armar","releer"]', "si el armado falla, releé igual (" + JSON.stringify(r.trasFallar) + ")");
  chk(r.reentrada === 0, "no se dispara dos veces a la vez");
  chk(r.cartel, "mientras arma, la barra lo dice");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\napr-actualizar OK");
})();
