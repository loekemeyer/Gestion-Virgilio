/* Regresión (idea 3717): programar desde la PPP Web — tanda, zona y fecha de entrega.
   Es lo único que no sale de LK: es una decisión del depósito, no un dato del pedido.
   Verifica que:
   (a) el barrio se derive de la sucursal de entrega (guión común y raya larga) y que
       "Retira" se reconozca aunque venga escrito de varias formas,
   (a2) el número visible sea "LK ####" y salga de la RPC de numeración, no del id
       del pedido —un pedido partido consume varios números correlativos—,
   (b) la zona se sugiera con el MISMO diccionario que usa la PPP (no un criterio nuevo),
   (c) el guardado mande SOLO las filas que la persona editó. La zona sugerida viene
       preseleccionada en el <select>, así que sin este filtro se guardaba sola en
       TODAS las filas visibles al apretar Guardar, aunque nadie las hubiera mirado:
       una sugerencia pasaba a ser una decisión sin que nadie la tomara,
   (d) escriba en PPP_Web_Programacion y NUNCA en PPP_Programacion_Diaria, que es la
       tabla viva de Producción,
   (e) un 403 de la RLS se explique como falta de permiso y no como error crudo,
   (f) NO se guarde si la NP todavía no tiene número: si la numeración falló, la
       etiqueta queda en "…" y guardar igual escribía np: null y un np_label
       "LK undefined" en la foto de artículos — una tanda que le llega rota al
       operario. */
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

  const barrios = await p.evaluate(() => ({
    guion:    pwebBarrioDe("Bragado 5742 - Mataderos"),
    rayaLarga: pwebBarrioDe("Danjor Comercial S.A.S. — LAS FLORES"),
    retira:   pwebBarrioDe("Retira"),
    retiraDep: pwebBarrioDe("Retira en depósito"),
    retiraMay: pwebBarrioDe("RETIRA"),
    suelta:   pwebBarrioDe("Calle 44 Nro 1647"),
    vacio:    pwebBarrioDe("")
  }));

  const r = await p.evaluate(async () => {
    const posts = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    // El diccionario compartido de zonas: la sugerencia tiene que salir de acá.
    window._pppZonaSupa = { "MATADEROS": "Zona 3 - CABA Oeste" };
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_Programacion")) {
        posts.push({ url: u, body: JSON.parse(opt.body) });
        return { ok: true, status: 201, json: async () => ({}), text: async () => "" };
      }
      if (u.includes("admin-login-otp"))  return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))   return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("v_pedidos_web_np")) return json([
        { np_prov: "900134201", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
          fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742 - Mataderos",
          v: "21", lineas: 1, cajas: 2, enviado_a_compras: false, items: [{ art: "027", cajas: 2 }] },
        { np_prov: "900134101", order_id: 1341, np_idx: 1, cod: "4188", razon_social: "Orfali",
          fecha_recep: "2026-09-03", hora_recep: "15:46:51", direccion: "Juncal 2869 - Martinez",
          v: "21", lineas: 1, cajas: 1, enviado_a_compras: false, items: [{ art: "027", cajas: 1 }] }
      ]);
      if (u.includes("ppp_web_np_asignar"))     return json([
        { r_order_id: 1342, r_np_idx: 1, r_np: 1343 },
        { r_order_id: 1341, r_np_idx: 1, r_np: 1344 }
      ]);
      if (u.includes("Volumen_Articulos"))       return json([{ codigo: "027", m3: 0.1 }]);
      if (u.includes("PPP_Web_Programacion"))    return json([]);   // sin nada programado todavía
      return json([]);
    };
    document.getElementById("pwebSoloPend").checked = true;
    await pwebCargar();

    const btn = document.getElementById("pwebGuardar");
    const arrancaDeshabilitado = btn.disabled;
    const zonaSugerida = document.getElementById("pwZ_1342_1").value;
    // Martinez ya está en el diccionario de fábrica: la sugerencia sale igual.
    const zonaSinDicc  = document.getElementById("pwZ_1341_1").value;

    // Se programa UNA sola: la otra no se toca.
    document.getElementById("pwT_1342_1").value = "D52B";
    document.getElementById("pwF_1342_1").value = "2026-09-05";
    pwebMarcarSucio("1342|1");
    const habilitaAlTocar = !btn.disabled;
    await pwebGuardar();

    const post = posts[0] || {};
    return {
      arrancaDeshabilitado, habilitaAlTocar, zonaSugerida, zonaSinDicc,
      posteos: posts.length,
      soloLaTocada: (post.body || []).length === 1,
      etiqueta: (document.querySelector(".pweb-np") || {}).textContent,
      orderGuardado: ((post.body || [])[0] || {}).order_id,
      npIdxGuardado: ((post.body || [])[0] || {}).np_idx,
      npGuardado: ((post.body || [])[0] || {}).np,
      tanda: ((post.body || [])[0] || {}).tanda,
      zona: ((post.body || [])[0] || {}).zona,
      fecha: ((post.body || [])[0] || {}).fecha_entrega,
      barrioGuardado: ((post.body || [])[0] || {}).barrio,
      m3Guardado: ((post.body || [])[0] || {}).m3,
      upsert: String(post.url || "").includes("on_conflict=empresa,order_id,np_idx"),
      noTocaPppProd: !posts.some(x => String(x.url).includes("PPP_Programacion_Diaria")),
      status: document.getElementById("pwebStatus").textContent
    };
  });

  // (f) sin número asignado no se guarda. Se recarga la pantalla primero: después
  // del guardado anterior la 1342 quedó con tanda y sale del listado.
  const sinNum = await p.evaluate(async () => {
    const posts = [];
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_")) { posts.push(u); return json([]); }
      if (u.includes("admin-login-otp"))  return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))   return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("v_pedidos_web_np")) return json([
        { empresa: "lk", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
          fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742 - Mataderos",
          v: "21", lineas: 1, cajas: 2, enviado_a_compras: false, items: [{ art: "027", cajas: 2 }] }
      ]);
      if (u.includes("ppp_web_np_asignar")) return { ok: false, status: 500, json: async () => ({}), text: async () => "boom" };
      if (u.includes("Volumen_Articulos"))  return json([{ codigo: "027", m3: 0.1 }]);
      return json([]);
    };
    await pwebCargar();                          // la numeración falla -> etiqueta "…"
    const etiqueta = (document.querySelector(".pweb-np") || {}).textContent;
    document.getElementById("pwT_1342_1").value = "D99Z";
    pwebMarcarSucio("1342|1");
    await pwebGuardar();
    return { etiqueta: etiqueta, posteos: posts.length,
             status: document.getElementById("pwebStatus").textContent };
  });

  // (e) 403 de la RLS -> mensaje entendible. Primero se recarga con la numeración
  // andando (si no, lo frena el guard de (f)) y recién después se cambia el stub
  // por uno que rechaza el POST.
  const permiso = await p.evaluate(async () => {
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url) => {
      const u = String(url);
      if (u.includes("admin-login-otp"))  return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))   return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("v_pedidos_web_np")) return json([
        { empresa: "lk", order_id: 1342, np_idx: 1, cod: "4109", razon_social: "Di Leo",
          fecha_recep: "2026-09-03", hora_recep: "16:03:54", direccion: "Bragado 5742 - Mataderos",
          v: "21", lineas: 1, cajas: 2, enviado_a_compras: false, items: [{ art: "027", cajas: 2 }] }
      ]);
      if (u.includes("ppp_web_np_asignar")) return json([{ r_order_id: 1342, r_np_idx: 1, r_np: 1343 }]);
      if (u.includes("Volumen_Articulos"))  return json([{ codigo: "027", m3: 0.1 }]);
      return json([]);
    };
    await pwebCargar();
    window.fetch = async (url, opt) => {
      if (opt && opt.method === "POST" && String(url).includes("PPP_Web_Programacion"))
        return { ok: false, status: 403, text: async () => "permission denied" };
      return { ok: true, status: 200, json: async () => ([]), text: async () => "[]" };
    };
    document.getElementById("pwT_1342_1").value = "D53B";
    pwebMarcarSucio("1342|1");
    await pwebGuardar();
    return document.getElementById("pwebStatus").textContent;
  });

  const okBarrios = barrios.guion === "Mataderos" && barrios.rayaLarga === "LAS FLORES"
    && barrios.retira === "Retira" && barrios.retiraDep === "Retira" && barrios.retiraMay === "Retira"
    && barrios.suelta === "Calle 44 Nro 1647" && barrios.vacio === "";
  const ok = okBarrios && r.arrancaDeshabilitado && r.habilitaAlTocar
    && r.zonaSugerida === "Zona 3 - CABA Oeste" && r.zonaSinDicc === "Zona 6 - GBA Norte"
    && r.posteos === 1 && r.soloLaTocada && r.tanda === "D52B"
    && r.etiqueta === "LK 1343" && r.orderGuardado === 1342 && r.npIdxGuardado === 1 && r.npGuardado === 1343
    && r.zona === "Zona 3 - CABA Oeste" && r.fecha === "2026-09-05"
    && r.barrioGuardado === "Mataderos" && r.m3Guardado === 0.2
    && r.upsert && r.noTocaPppProd && r.status.indexOf("✓") === 0
    && /permiso/i.test(permiso)
    && sinNum.posteos === 0 && /número/i.test(sinNum.status);

  console.log("pweb-programar:", JSON.stringify({ barrios, ...r, sinNum, permiso }),
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
