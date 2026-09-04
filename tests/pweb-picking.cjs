/* Regresión (idea 3717): un pedido programado en la PPP Web llega al operario.
   Verifica que:
   (a) la tanda de la PPP Web aparezca en el MISMO mapa que las de ISIS, y que las
       de ISIS sigan intactas (es aditivo: si esto falla, el picking de siempre no
       se entera),
   (b) los artículos salgan de PPP_Web_Base (la foto tomada al programar),
   (c) la EMPRESA se resuelva por la etiqueta "LK 01343" y no por el número: la
       regla vieja es >90000 = LK, así que una NP web de 4 dígitos caería en Chef y
       el operario iría a buscar un pedido de Loekemeyer al sector equivocado,
   (d) una tanda que mezcla una NP de ISIS y una web quede con las dos. */
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

  // (c) la trampa de la empresa, aislada
  const emp = await p.evaluate(() => ({
    webLk:    empresaDeNp("LK 01343"),
    webCh:    empresaDeNp("CH 87"),
    isisLk:   empresaDeNp("98574"),
    isisCh:   empresaDeNp("44603"),
    sinPrefijoSeriaChef: empresaDeNp("1343")   // por eso hace falta la etiqueta
  }));

  const r = await p.evaluate(async () => {
    const json = (o) => ({ ok: true, status: 200, json: async () => o,
                           text: async () => JSON.stringify(o),
                           headers: { get: () => "0-1/1" } });
    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("PPP_Web_Programacion")) return json([
        { empresa: "lk", np: 1343, tanda: "D01A", zona: "Zona 3 - CABA Oeste",
          fecha_entrega: "2026-09-05", cod_cliente: "4109", razon_social: "Di Leo",
          direccion: "Bragado 5742", barrio: "Mataderos", m3: 0.336 },
        { empresa: "lk", np: 1344, tanda: "MIXTA", zona: "Zona 3 - CABA Oeste",
          fecha_entrega: "2026-09-05", cod_cliente: "4188", razon_social: "Orfali",
          direccion: "Juncal 2869", barrio: "Martinez", m3: 1.184 }
      ]);
      if (u.includes("PPP_Web_Base")) return json([
        { np_label: "LK 01343", articulo: "027", cajas: 2 },
        { np_label: "LK 01343", articulo: "505", cajas: 5 },
        { np_label: "LK 01344", articulo: "586", cajas: 1 }
      ]);
      return json([]);
    };
    // El mapa de ISIS ya trae una tanda propia y otra que comparte código con la web.
    window.fetchMonitorFromSupabase = async () => new Map([
      ["C03B",  { tanda: "C03B",  _key: "C03B",  m3: 0.5, pedidos: [{ np: "98574", m3: 0.5 }] }],
      ["MIXTA", { tanda: "MIXTA", _key: "MIXTA", m3: 0.2, pedidos: [{ np: "98999", m3: 0.2 }] }]
    ]);
    const acc = await fetchMonitorSheet();
    const base = new Map();
    await mergePickingBasePppWeb(base);

    const d01a  = acc.get("D01A");
    const mixta = acc.get("MIXTA");
    return {
      isisIntacta:   !!acc.get("C03B") && acc.get("C03B").pedidos[0].np === "98574",
      webAparece:    !!d01a && d01a.pedidos[0].np === "LK 01343",
      m3Web:         d01a ? Number(d01a.m3.toFixed(3)) : null,
      mixtaTieneLasDos: !!mixta && mixta.pedidos.length === 2
                        && mixta.pedidos.some(x => x.np === "98999")
                        && mixta.pedidos.some(x => x.np === "LK 01344"),
      arts1343:      (base.get("LK 01343") || []).map(x => x.art + ":" + x.cajas).join(","),
      arts1344:      (base.get("LK 01344") || []).map(x => x.art + ":" + x.cajas).join(",")
    };
  });

  const ok = emp.webLk === "LK" && emp.webCh === "CH" && emp.isisLk === "LK" && emp.isisCh === "CH"
    && emp.sinPrefijoSeriaChef === "CH"
    && r.isisIntacta && r.webAparece && r.m3Web === 0.336 && r.mixtaTieneLasDos
    && r.arts1343 === "027:2,505:5" && r.arts1344 === "586:1";
  console.log("pweb-picking:", JSON.stringify({ emp, ...r }),
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
