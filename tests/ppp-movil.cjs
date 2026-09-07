/* v14.25 — la fila de la PPP en un teléfono: nada cortado y sin scroll horizontal. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { ({ chromium } = require("playwright")); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    try { localStorage.clear(); } catch (_e) {}
    const J = (data) => { const n = Array.isArray(data) ? data.length : 0; return Promise.resolve({ ok: true, status: 200,
      headers: { get: (h) => String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null },
      json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)) }); };
    const hab = _pppDiasHabiles(6).map((d) => d.date);
    const iso = (dt) => dt.getFullYear() + "-" + String(dt.getMonth()+1).padStart(2,"0") + "-" + String(dt.getDate()).padStart(2,"0");
    const mk = (np,tanda,cod,rs,m3,barrio,dir,dt,zona) => ({ np,tanda,tipo:"",fecha_recep:"2026-09-01",cod,razon_social:rs,m3,direccion:dir,barrio,fecha_entrega:iso(dt),zona });
    const rows = [
      mk("98701","E03A","45","Distribuidora Cuyana S.A",0.41,"Villa Soldati","B DE ASTRADA 2796",hab[0],"Zona 1 - CABA Sur"),
      mk("98702","E03B","1665","Ierakuin Srl",0.32,"Barracas","Montes de Oca 1000",hab[0],"Zona 1 - CABA Sur"),
      mk("98703","E03C","846","Maira S.R.L.",0.9,"Pompeya","Sáenz 1100",hab[0],"Zona 1 - CABA Sur")
    ];
    const origFetch = window.fetch;
    window.fetch = (u) => { u = String(u);
      if (u.includes("gv_ppp_programacion_diaria")) return J(rows);
      if (u.includes("gv_ppp_np_valor")) return J(rows.map((x)=>({ np:x.np, np_txt:x.np, valor: 514290, total: 514290 })));
      return J([]); };
    await pppLoadProgFromSupabase();
    // Valores a mano: lo que se está probando es el layout, no la carga del importe.
    _pppValor = new Map([["98701",{valor:514290}],["98702",{valor:2414815}],["98703",{valor:997640}]]
      .map(([np,v]) => [_pppNpNorm(np), v]));
    _pppTab = "plan"; _pppPlanClasica = false; pppRenderProg();
    pppPlanAbrir(_pppDateKey(hab[0]));
    window.fetch = origFetch;

    // Mostrar el overlay: es donde vive la pantalla que sacó la captura el dueño.
    const ov = document.getElementById("pppOverlay");
    if (ov) { ov.classList.add("show"); ov.style.display = "block"; }
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    const filas = [...document.querySelectorAll(".pn-ped")];
    out.filas = filas.length;
    out.overflowBody = document.documentElement.scrollWidth > window.innerWidth + 1;
    out.anchoDoc = document.documentElement.scrollWidth;
    out.viewport = window.innerWidth;
    out.cortadas = filas.filter((f) => f.scrollWidth > f.clientWidth + 1).length;
    const pp = filas.map((f) => f.querySelector(".pp")).filter(Boolean);
    out.importes = pp.map((e) => {
      const r = e.getBoundingClientRect();
      return { txt: e.textContent.trim(), derecha: Math.round(r.right), visible: r.right <= window.innerWidth + 1 && r.width > 10 };
    });
    return out;
  });

  await b.close();
  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.filas === 3, "las 3 filas del día se dibujan: " + r.filas);
  chk(!r.overflowBody, "el documento no desborda a 390 px (ancho " + r.anchoDoc + " vs viewport " + r.viewport + ")");
  chk(r.cortadas === 0, "ninguna fila queda cortada: " + r.cortadas);
  chk(r.importes.length === 3 && r.importes.every((i) => i.visible),
      "los 3 importes entran enteros en pantalla (" + r.importes.map((i) => i.txt).join(" · ") + ")");
  chk(r.importes.every((i) => i.derecha <= 390), "y ninguno se pasa del borde derecho");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs.join(" | ") : ""));
  console.log(fails.length ? ("\nppp-movil: " + fails.length + " FALLA(S)") : "\nppp-movil OK");
  process.exit(fails.length ? 1 : 0);
})();
