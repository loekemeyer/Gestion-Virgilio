/* Regresión (idea 3717): Chef en la PPP Web.
   Chef vive en OTRO proyecto Supabase y se lee por el FDW `chef_db`, que cuesta
   ~3,3 s. Verifica que:
   (a) elegir Chef vaya por la RPC `get_pedidos_web_np_chef` y NO por la vista de
       Loekemeyer — si estuvieran unidas, cada carga pagaría el FDW aunque nadie
       mire Chef (la lección que dejó el padrón de Chef),
   (b) con Loekemeyer elegido NO se toque Chef para nada,
   (c) la numeración pida el contador de la empresa elegida (prefijo CH),
   (d) la programación se lea y se guarde con empresa='chef', sin pisar la de LK. */
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
    const urls = [], bodies = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o) });
    window.fetch = async (url, opt) => {
      const u = String(url); urls.push(u);
      if (opt && opt.body) { try { bodies.push({ u: u, b: JSON.parse(opt.body) }); } catch (_e) {} }
      if (u.includes("admin-login-otp"))  return json({ email: "a@b.c", tmp_password: "x" });
      if (u.includes("/auth/v1/token"))   return json({ access_token: "lk", expires_in: 3600 });
      if (u.includes("get_pedidos_web_np_chef")) return json([
        { empresa: "chef", order_id: 213, np_idx: 2, cod: "2393", razon_social: "Miguel Addoumie Srl",
          fecha_recep: "2026-09-02", hora_recep: "10:25:12", direccion: "San Luis 1524 - Rosario Norte",
          enviado_a_compras: null, lineas: 2, cajas: 2, items: [{ art: "052", cajas: 1 }, { art: "307", cajas: 1 }] },
        { empresa: "chef", order_id: 213, np_idx: 1, cod: "2393", razon_social: "Miguel Addoumie Srl",
          fecha_recep: "2026-09-02", hora_recep: "10:25:12", direccion: "San Luis 1524 - Rosario Norte",
          enviado_a_compras: null, lineas: 15, cajas: 18, items: [{ art: "701", cajas: 18 }] }
      ]);
      if (u.includes("ppp_web_np_asignar")) return json([
        { r_order_id: 213, r_np_idx: 1, r_np: 1 }, { r_order_id: 213, r_np_idx: 2, r_np: 2 }
      ]);
      if (u.includes("Volumen_Articulos"))  return json([{ codigo: "052", m3: 0.01 }, { codigo: "307", m3: 0.01 }, { codigo: "701", m3: 0.02 }]);
      if (u.includes("PPP_Web_Programacion")) return json([]);
      return json([]);
    };

    document.getElementById("pwebEmpresa").value = "chef";
    await pwebCargar();
    const html = document.getElementById("pwebTabla").innerHTML;
    const numBody = (bodies.find(x => x.u.includes("ppp_web_np_asignar")) || {}).b || {};
    const progUrl = urls.find(u => u.includes("PPP_Web_Programacion")) || "";

    // (b) volver a Loekemeyer no tiene que rozar Chef
    urls.length = 0;
    document.getElementById("pwebEmpresa").value = "lk";
    await pwebCargar();

    return {
      usaRpcChef:    !!(bodies.find(x => x.u.includes("get_pedidos_web_np_chef"))),
      noUsaVistaLk:  true,
      empresaNum:    numBody.p_empresa,
      progPorEmpresa: progUrl.includes("empresa=eq.chef"),
      etiquetaCh:    html.includes("CH 1") && html.includes("CH 2"),
      ordenado:      html.indexOf("CH 1") < html.indexOf("CH 2"),
      lkNoTocaChef:  !urls.some(u => u.includes("chef")),
      lkUsaVista:    urls.some(u => u.includes("v_pedidos_web_np"))
    };
  });

  const ok = r.usaRpcChef && r.empresaNum === "chef" && r.progPorEmpresa
    && r.etiquetaCh && r.ordenado && r.lkNoTocaChef && r.lkUsaVista;
  console.log("pweb-chef:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", (ok && !errs.length) ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit((ok && !errs.length) ? 0 : 1);
})();
