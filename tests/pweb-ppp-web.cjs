/* Regresión (idea 3717): PPP Web — la programación calculada en vivo sobre los
   pedidos que llegan a la página LK. Verifica que pwebCargar():
   (a) pida a LK SOLO lo que todavía no salió por mail cuando el check está puesto,
   (b) resuelva el m³ contra Volumen_Articulos de ESTA base (LK no lo tiene),
   (c) avise cuando un artículo no tiene m³ en vez de sumar 0 en silencio,
   (d) NO toque PPP_Programacion_Diaria, que es la tabla viva de Producción. */
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
    window.sbAuth = { getAccessToken: async () => "vjwt-falso" };
    window.fetch = async (url, opt) => {
      urls.push(String(url));
      const u = String(url);
      const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
      if (u.includes("admin-login-otp"))       return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))        return json({ access_token: "lk-tok", expires_in: 3600 });
      if (u.includes("v_pedidos_web_np"))      return json([
        { np_prov: "900134201", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
          fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742", v: "21",
          lineas: 3, cajas: 10, enviado_a_compras: false,
          items: [{ art: "027", cajas: 2 }, { art: "505", cajas: 5 }, { art: "ZZZ", cajas: 3 }] }
      ]);
      if (u.includes("Volumen_Articulos"))     return json([{ codigo: "027", m3: 0.1 }, { codigo: "505", m3: 0.02 }]);
      return json([]);
    };
    document.getElementById("pwebSoloPend").checked = true;
    await pwebCargar();
    const html = document.getElementById("pwebTabla").innerHTML;
    const res  = document.getElementById("pwebResumen").innerHTML;
    return {
      pidePendientes:  urls.some(u => u.includes("v_pedidos_web_np") && u.includes("enviado_a_compras=eq.false")),
      pideVolumen:     urls.some(u => u.includes("Volumen_Articulos")),
      noTocaPppProd:  !urls.some(u => u.includes("PPP_Programacion_Diaria")),
      m3Correcto:      html.includes("0.300"),   // 2*0.1 + 5*0.02 = 0.30 ; ZZZ no suma
      avisaSinM3:      res.includes("ZZZ"),
      muestraNp:       html.includes("900134201"),
      status:          document.getElementById("pwebStatus").textContent
    };
  });
  const ok = r.pidePendientes && r.pideVolumen && r.noTocaPppProd && r.m3Correcto && r.avisaSinM3 && r.muestraNp && !r.status;
  console.log("pweb-ppp-web:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
