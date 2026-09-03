/* Regresión (idea 3717): "Armar tandas" en la PPP Web.
   No es un algoritmo nuevo: reusa el de la PPP (súper 1×cliente; el resto por zona
   → cliente, empacado en 0,60–1,00 m³). Verifica que:
   (a) NO pise una tanda ya escrita a mano,
   (b) no mezcle zonas dentro de una tanda,
   (c) los códigos SIGAN desde la última letra usada en las DOS tablas (la de la PPP
       Web y la de Producción): comparten espacio de nombres y dos tandas distintas
       con el mismo código serían un lío en el depósito,
   (d) llene los campos pero NO guarde: el reparto se revisa antes de existir,
   (e) avise las NP que quedan sin zona en vez de meterlas en cualquier tanda. */
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
    const posts = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    window._pppZonaSupa = { "MATADEROS": "Zona 3 - CABA Oeste", "MARTINEZ": "Zona 6 - GBA Norte" };
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    const mk = (oid, dir, m3) => ({
      empresa: "lk", order_id: oid, np_idx: 1, cod: String(4000 + oid), razon_social: "Cli " + oid,
      fecha_recep: "2026-09-03", hora_recep: "16:00:00", direccion: dir, v: "21",
      lineas: 1, cajas: 1, enviado_a_compras: false, items: [{ art: "027", cajas: m3 * 10 }]
    });
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_Programacion")) { posts.push(u); return { ok: true, status: 201, json: async () => ({}), text: async () => "" }; }
      if (u.includes("admin-login-otp"))  return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))   return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("ppp_web_np_asignar")) return json([
        { r_order_id: 1, r_np_idx: 1, r_np: 1343 }, { r_order_id: 2, r_np_idx: 1, r_np: 1344 },
        { r_order_id: 3, r_np_idx: 1, r_np: 1345 }, { r_order_id: 4, r_np_idx: 1, r_np: 1346 }
      ]);
      if (u.includes("v_pedidos_web_np")) return json([
        mk(1, "Av Falsa 1 - Mataderos", 0.5), mk(2, "Av Falsa 2 - Mataderos", 0.5),
        mk(3, "Av Falsa 3 - Martinez",  0.9), mk(4, "Av Falsa 4 - Pueblo Ignoto", 0.4)
      ]);
      // cada caja de 027 = 0.1 m³ -> cajas = m3*10
      if (u.includes("Volumen_Articulos"))          return json([{ codigo: "027", m3: 0.1 }]);
      // Producción ya llegó hasta la letra C: los códigos nuevos tienen que arrancar en D.
      if (u.includes("PPP_Programacion_Diaria"))    return json([{ tanda: "C03B" }, { tanda: "A01A" }]);
      if (u.includes("PPP_Web_Programacion"))       return json([]);
      return json([]);
    };
    document.getElementById("pwebSoloPend").checked = true;
    await pwebCargar();

    // (a) una tanda puesta a mano no se pisa
    document.getElementById("pwT_4_1").value = "MANUAL";
    await pwebSugerirTandas();

    const t = (o) => (document.getElementById("pwT_" + o + "_1") || {}).value;
    return {
      manualIntacta: t(4) === "MANUAL",
      t1: t(1), t2: t(2), t3: t(3),
      mismaZonaJuntos: t(1) === t(2),          // los dos de Mataderos, 0.5+0.5 = 1.00
      zonaDistintaSeparada: t(3) !== t(1),     // Martinez no entra con Mataderos
      arrancaEnD: /^D/.test(t(1)) && /^D/.test(t(3)),
      noGuardo: posts.length === 0,
      botonHabilitado: !document.getElementById("pwebGuardar").disabled,
      status: document.getElementById("pwebStatus").textContent,
      // (e) segunda pasada: sin la tanda manual, la NP de zona desconocida no se
      // mete en cualquier tanda — queda sin tanda y se avisa.
      ...(await (async () => {
        document.getElementById("pwT_4_1").value = "";
        await pwebSugerirTandas();
        return {
          sinZonaQuedaVacia: !(document.getElementById("pwT_4_1").value || "").trim(),
          statusSinZona: document.getElementById("pwebStatus").textContent
        };
      })())
    };
  });

  const ok = r.manualIntacta && r.mismaZonaJuntos && r.zonaDistintaSeparada && r.arrancaEnD
    && r.noGuardo && r.botonHabilitado && /tandas armadas/.test(r.status)
    && r.sinZonaQuedaVacia && /sin zona/.test(r.statusSinZona);
  console.log("pweb-tandas:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
