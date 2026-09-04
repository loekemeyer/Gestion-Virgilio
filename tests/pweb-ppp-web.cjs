/* Regresión (idea 3717): PPP Web — la programación calculada en vivo sobre los
   pedidos que llegan a la página LK. Verifica que pwebCargar():
   (a) pida a LK una VENTANA de días (no el histórico) y que el check "solo los que
       faltan programar" saque de la lista lo que ya tiene tanda — el filtro ya no
       mira si salió el mail, porque así un pedido se sellaba al día siguiente y
       desaparecía de la pantalla sin que nadie lo hubiera programado,
   (a2) marque con "ISIS" lo que ya salió por mail: programarlo acá durante la
       transición lo haría pickear dos veces,
   (b) resuelva el m³ contra Volumen_Articulos de ESTA base (LK no lo tiene),
   (c) trate una fila de Volumen_Articulos SIN VALOR como dato faltante —avisando y
       marcando la NP— en vez de sumarle 0 en silencio (1.613 de 2.547 filas de esa
       tabla están así, o sea que no es un caso raro),
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
        { empresa: "lk", order_id: 1341, np_idx: 1, cod: "4188", razon_social: "Orfali",
          fecha_recep: "2026-09-03", hora_recep: "15:46:51", direccion: "Juncal 2869",
          lineas: 1, cajas: 1, enviado_a_compras: false, items: [{ art: "027", cajas: 1 }] },
        { empresa: "lk", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
          fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742", v: "21",
          lineas: 3, cajas: 10, enviado_a_compras: false,
          items: [{ art: "027", cajas: 2 }, { art: "505", cajas: 5 }, { art: "ZZZ", cajas: 3 }] }
      ]);
      // ZZZ tiene FILA pero sin valor: no tiene que sumar 0 en silencio, tiene que avisar.
      if (u.includes("ppp_web_np_asignar"))    return json([{ r_order_id: 1342, r_np_idx: 1, r_np: 1343 }]);
      if (u.includes("Volumen_Articulos"))     return json([{ codigo: "027", m3: 0.1 }, { codigo: "505", m3: 0.02 }, { codigo: "ZZZ", m3: null }]);
      // La 1341 YA está programada acá: con el check puesto no tiene que aparecer.
      if (u.includes("PPP_Web_Programacion"))  return json([
        { order_id: 1341, np_idx: 1, tanda: "D01A", zona: null, fecha_entrega: null }
      ]);
      return json([]);
    };
    document.getElementById("pwebSoloPend").checked = true;
    await pwebCargar();
    const html = document.getElementById("pwebTabla").innerHTML;
    const res  = document.getElementById("pwebResumen").innerHTML;
    return {
      pideVentana:     urls.some(u => u.includes("v_pedidos_web_np") && u.includes("fecha_recep=gte.")),
      noFiltraPorMail: !urls.some(u => u.includes("enviado_a_compras=eq.")),
      ocultaProgramada: !html.includes("Orfali"),   // 1341 ya tiene tanda
      pideVolumen:     urls.some(u => u.includes("Volumen_Articulos")),
      noTocaPppProd:  !urls.some(u => u.includes("PPP_Programacion_Diaria")),
      m3Correcto:      html.includes("0.300"),   // 2*0.1 + 5*0.02 = 0.30 ; ZZZ no suma
      avisaSinM3:      res.includes("ZZZ"),
      marcaParcial:    html.includes("~0.300"),  // la NP queda marcada como incompleta
      totalEsPiso:     res.includes("≥0.300"),   // el total se muestra como mínimo, no como valor
      muestraNp:       html.includes("LK 1343"),   // etiqueta corta, no la NP larga de antes
      status:          document.getElementById("pwebStatus").textContent
    };
  });
  const ok = r.pideVentana && r.noFiltraPorMail && r.ocultaProgramada && r.pideVolumen && r.noTocaPppProd && r.m3Correcto && r.avisaSinM3
          && r.marcaParcial && r.totalEsPiso && r.muestraNp && !r.status;
  console.log("pweb-ppp-web:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
