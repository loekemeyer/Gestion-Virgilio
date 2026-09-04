/* Regresión (idea 3717): los pedidos de la página entran a la PPP COMÚN.
   No hay pantalla aparte: se ven igual que los de ISIS porque son la misma tabla.
   Verifica que:
   (a) pppTraerPedidosWeb devuelva filas con la MISMA forma que las de la PPP
       (np rotulada "LK 1343", m³ propio, barrio y zona resueltos, programmed),
   (b) el m³ NO sume 0 en silencio cuando un artículo no está medido,
   (c) Chef vaya por su RPC (FDW ~3,3 s) y Loekemeyer NO la toque,
   (d) pppGuardarWeb escriba la cabecera y la FOTO de artículos, y que sin número
       no guarde nada — una NP sin número le llega rota al operario,
   (e) un 403 de la RLS se explique como falta de permiso. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());          // hermético: sin datos vivos
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const urls = [], posts = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    window._pppZonaSupa = {};
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    const NPS = [
      { empresa: "lk", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
        fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742 - Mataderos",
        v: "21", lineas: 3, cajas: 10, enviado_a_compras: false,
        items: [{ art: "027", cajas: 2 }, { art: "505", cajas: 5 }, { art: "ZZZ", cajas: 3 }],
        // v12.76 — el m³ viene calculado del backend. 027×2 (0,1) + 505×5 (0,02) = 0,3;
        // ZZZ tiene fila pero sin valor, así que la vista lo marca parcial.
        m3: 0.3, m3_parcial: true }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); urls.push(u);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_")) { posts.push({ u, b: JSON.parse(opt.body) }); return json([]); }
      if (u.includes("admin-login-otp"))    return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))     return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("v_pedidos_web_np"))   return json(NPS);
      if (u.includes("ppp_web_np_asignar")) return json([{ r_order_id: 1342, r_np_idx: 1, r_np: 1343 }]);
      // v12.76 — el m³ ya no se pide desde el front: viene en la fila de la NP.
      if (u.includes("vista_volumen_articulo_resuelto")) return json([]);
      if (u.includes("rpc/ppp_web_resync")) return json([]);
      if (u.includes("PPP_Web_Programacion")) return json([]);
      return json([]);
    };

    const filas = await pppTraerPedidosWeb("lk");
    const f = filas[0] || {};

    // (d) guardar
    f.tanda = "D01A"; f.fecha_entrega = "2026-09-05";
    const n = await pppGuardarWeb(filas);
    const cab = posts.find(x => x.u.includes("PPP_Web_Programacion")) || {};
    const base = posts.find(x => x.u.includes("PPP_Web_Base")) || {};

    // (d2) sin número no guarda
    let sinNum = "";
    try { const g = Object.assign({}, f); g._wNum = null; await pppGuardarWeb([g]); }
    catch (e) { sinNum = e.message; }

    return {
      filas: filas.length,
      np: f.np, cod: f.cod, localidad: f.localidad, zona: f.zona,
      m3: f.m3, parcial: f._wM3Parcial, programmed: f.programmed,
      formaPpp: ["np","tanda","tipo","fecha","cod","razon_social","m3","localidad","fecha_entrega","zona","programmed"].every(k => k in f),
      guardadas: n,
      cabNp: (cab.b || [])[0] ? cab.b[0].np : null,
      cabTanda: (cab.b || [])[0] ? cab.b[0].tanda : null,
      cabM3Parcial: (cab.b || [])[0] ? cab.b[0].m3_parcial : null,
      arts: (base.b || []).map(x => x.articulo + ":" + x.cajas).join(","),
      artsNpLabel: (base.b || [])[0] ? base.b[0].np_label : null,
      sinNum: sinNum,
      lkNoTocaChef: !urls.some(u => u.includes("chef"))
    };
  });

  // (c) Chef por su RPC
  const chef = await p.evaluate(async () => {
    const urls = [];
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url, opt) => {
      const u = String(url); urls.push(u);
      if (u.includes("admin-login-otp"))    return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))     return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("get_pedidos_web_np_chef")) return json([
        { empresa: "chef", order_id: 213, np_idx: 2, cod: "2393", razon_social: "Addoumie",
          fecha_recep: "2026-09-02", hora_recep: "10:25", direccion: "San Luis 1524 - Rosario Norte",
          enviado_a_compras: null, lineas: 2, cajas: 2, items: [{ art: "052", cajas: 1 }],
          m3: 0.01, m3_parcial: false }
      ]);
      if (u.includes("ppp_web_np_asignar")) return json([{ r_order_id: 213, r_np_idx: 2, r_np: 7 }]);
      if (u.includes("vista_volumen_articulo_resuelto")) return json([]);
      if (u.includes("rpc/ppp_web_resync")) return json([]);
      return json([]);
    };
    const filas = await pppTraerPedidosWeb("chef");
    return { np: (filas[0] || {}).np, usaRpc: urls.some(u => u.includes("get_pedidos_web_np_chef")),
             noUsaVistaLk: !urls.some(u => u.includes("v_pedidos_web_np")) };
  });

  // (e) 403 de la RLS
  const permiso = await p.evaluate(async () => {
    window.sbAuth = { getAccessToken: async () => "tok" };
    window.fetch = async (url, opt) => {
      if (opt && opt.method === "POST" && String(url).includes("PPP_Web_Programacion"))
        return { ok: false, status: 403, text: async () => "denied" };
      return { ok: true, status: 200, json: async () => ([]), text: async () => "[]" };
    };
    try {
      await pppGuardarWeb([{ _web: true, tanda: "D01A", _wNum: 1343, _wEmp: "lk", _wOrder: 1, _wIdx: 1, _wItems: [] }]);
      return "no falló";
    } catch (e) { return e.message; }
  });

  const ok = r.filas === 1 && r.np === "LK 1343" && r.localidad === "Mataderos" && r.formaPpp
    && r.m3 === 0.3 && r.parcial === true && r.programmed === false && r.lkNoTocaChef
    && r.guardadas === 1 && r.cabNp === 1343 && r.cabTanda === "D01A" && r.cabM3Parcial === true
    && r.arts === "027:2,505:5,ZZZ:3" && r.artsNpLabel === "LK 1343"
    && /número/i.test(r.sinNum)
    && chef.np === "CH 7" && chef.usaRpc && chef.noUsaVistaLk
    && /permiso/i.test(permiso);
  console.log("pweb-en-ppp:", JSON.stringify({ ...r, chef, permiso }),
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
