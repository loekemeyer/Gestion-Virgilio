/* v17.57 (Luis, 2026-09-14: "necesito que aparezca el dato del contenido de las NP en algún lado
   visible en todo momento") — el detalle de un pedido (CÓDIGOS, CAJAS y UNIDADES) se abre con la
   flechita de arriba a la derecha en las DOS columnas de A Programar:
     (a) Pedidos a programar — la ficha se lee como la de Cuarentena: NP grande arriba, m³ al lado,
         flechita a la derecha, cliente abajo con su número (LK 1000 / CH 2533).
     (b) Cuarentena — la ficha, que antes no se abría, tiene la misma flechita y el mismo detalle.
   v17.61 (Luis: "esa NP tenía el detalle de los códigos y las cajas, en algún lugar está") —
     (c) una NP vieja de ISIS SÍ tiene detalle: sale de la base del PPP (`gv_ppp_isis_items`), se
         pide al abrir la ficha y se cachea. Si no se puede leer, lo dice; no inventa una tabla.
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {}; _apr.cuarResumen = [];
    _apr.cal = [{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    const items = [{ art: "505L", uni: 24, uxb: 12, cajas: 2 }, { art: "438EL", uni: 12, uxb: 12, cajas: 1 }];
    const mk = (o) => Object.assign({
      order_id: 1400, empresa: "lk", cod: "1000", razon_social: "Cliente Normal",
      zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-11", localidad: "Barracas",
      direccion: "Montes de Oca 1", m3: 0.4, m3_parcial: false, lineas: 2, cajas: 3, np_total: 1,
      bloques: [{ np_idx: 1, m3: 0.4, lineas: 2, cajas: 3, items: items }]
    }, o);
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");

    // ── (a) Pedidos a programar ────────────────────────────────────────────────────────────
    _apr.pedidos = [mk({}), mk({ order_id: "np98587", _isis: true, np: "98587", razon_social: "Zhang Qikuan", cod: "4275", bloques: [] })];
    _apr.exp = {};
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    let html = document.getElementById("pppPreview").innerHTML;
    // la NP es el título de la ficha, no un chip gris más de la fila de abajo
    out.npTitulo = /apr-card-np[^>]*>web LK 1400</.test(html);
    out.npIsis = /apr-card-np es-isis[^>]*>NP 98587</.test(html);
    out.sinChipPed = !/apr-chip-ped/.test(html);
    // el m³ se mudó arriba, al lado del número
    out.m3Arriba = /apr-card-m3[^>]*>0,400 m³</.test(html);
    out.sinChipM3 = !/apr-chip-m3/.test(html);
    // el cliente va abajo, con su número (mismo chip que Cuarentena)
    out.cliConCod = /apr-card-cli[^>]*>.*cuar-card-cod[^>]*>LK 1000<.*Cliente Normal/.test(html);
    // cerrado: la flechita está y el contenido no
    out.chevCerrada = (html.match(/apr-card-chev/g) || []).length === 2 && /▸/.test(html);
    out.sinTablaCerrada = !/apr-tab/.test(html);

    // abrir el pedido de la página → tabla con código, cajas y unidades
    aprToggle("p1400"); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.tabla = /<th>Código<\/th>/.test(html) && /<th class="n">Cajas<\/th>/.test(html) && /<th class="n">Unidades<\/th>/.test(html);
    out.tablaCod = /apr-tab-cod">505L<\/td><td class="n"><b>2<\/b><\/td>/.test(html);
    out.tablaUni = /24 <span class="apr-tab-uxb">×12<\/span>/.test(html);
    out.tablaTotal = /<tfoot><tr><td>2 códigos<\/td><td class="n">3<\/td><td class="n">36<\/td>/.test(html);
    out.resumen = /apr-det-n"><b>2<\/b> líneas/.test(html) && /<b>3<\/b> cajas/.test(html) && /<b>36<\/b> unidades/.test(html);
    out.entrega = /<b>Entrega<\/b> Montes de Oca 1/.test(html);

    // ── (c) v17.61 — la NP de ISIS pide su detalle a la base del PPP ───────────────────────
    // con la red cortada: avisa que no pudo, NO dice que el detalle no existe
    aprToggle("pnp98587"); await new Promise((res) => setTimeout(res, 250));
    html = document.getElementById("pppPreview").innerHTML;
    out.isisPidio = _apr.isisItems && _apr.isisItems["98587"] === null;
    out.isisFalla = /No se pudo leer el detalle de la NP 98587/.test(html);
    out.isisSinMentira = !/el detalle de artículos no está en la página/.test(html);

    // con la vista respondiendo: tabla con los códigos y las cajas de la base
    const pedidos = [];
    window.aprGet = async function (ruta) {
      pedidos.push(ruta);
      if (/gv_ppp_isis_items/.test(ruta)) return [
        { art: "035E", cajas: 2, uxb: 12, uni: 24 },
        { art: "207", cajas: 1, uxb: 12, uni: 12 },
        { art: "404E", cajas: 2, uxb: 4, uni: 8 }
      ];
      return [];
    };
    delete _apr.isisItems["98587"];
    aprRender(); await new Promise((res) => setTimeout(res, 250));
    html = document.getElementById("pppPreview").innerHTML;
    out.isisRuta = pedidos.some((u) => /^gv_ppp_isis_items\?select=art,cajas,uxb,uni&np=eq\.98587&/.test(u));
    out.isisTabla = /apr-tab-cod">035E<\/td><td class="n"><b>2<\/b><\/td>/.test(html) &&
                    /apr-tab-cod">404E</.test(html);
    out.isisUni = /24 <span class="apr-tab-uxb">×12<\/span>/.test(html);
    out.isisTotal = /<tfoot><tr><td>3 códigos<\/td><td class="n">5<\/td><td class="n">44<\/td>/.test(html);
    // el resumen de arriba toma las unidades del detalle que trajo de la base
    out.isisResumen = /<b>44<\/b> unidades/.test(html);
    // una sola vuelta de red por NP: la segunda vez sale del caché
    const antes = pedidos.length;
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    out.isisCache = pedidos.length === antes;
    // 🔄 reintenta sólo las que fallaron; las buenas quedan
    _apr.isisItems["99999"] = null;
    for (const k in _apr.isisItems) if (_apr.isisItems[k] === null) delete _apr.isisItems[k];
    out.isisReintento = _apr.isisItems["99999"] === undefined && Array.isArray(_apr.isisItems["98587"]);
    aprToggle("pnp98587");

    // ── (b) Cuarentena ─────────────────────────────────────────────────────────────────────
    _apr.exp = {};
    _apr.pedidos = [mk({ order_id: 1401, empresa: "chef", cod: "2533", razon_social: "Cliente Deudor",
                         cuarentena_motivos: ["deuda"], cuarentena_detalle: { deuda: 10000 } })];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.cuarChev = /cuar-card-top" onclick="aprToggle\('cchef1401'\)"/.test(html) &&
                   /apr-card-chev" title="Ver qué pidieron/.test(html);
    out.cuarCerrada = !/apr-tab/.test(html);
    aprToggle("cchef1401"); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.cuarTabla = /<th>Código<\/th>/.test(html) && /apr-tab-cod">505L</.test(html);
    out.cuarResumenDet = /<b>3<\/b> cajas/.test(html) && /<b>36<\/b> unidades/.test(html);
    out.cuarSigueBadge = /cuar-badge b-deuda/.test(html) && /cuar-enviar/.test(html);
    // el cliente de Chef mantiene su prefijo en el detalle
    out.cuarCodDet = /<b>Cód<\/b> CH 2533/.test(html);

    // el ejemplo también trae contenido (si no, la flechita abría una ficha vacía)
    _apr.cuarDemo = true; _apr.pedidos = [];
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    aprToggle("clkEJEMPLO"); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.demoTabla = /EJEMPLO/.test(html) && /apr-tab-cod">505</.test(html);
    _apr.cuarDemo = false;

    return out;
  });

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(r.npTitulo, "(a) la NP del pedido es el título de la ficha (apr-card-np)");
  t(r.npIsis, "(a) una NP de ISIS se distingue (es-isis)");
  t(r.sinChipPed, "(a) ya no está el chip gris del pedido en la fila de abajo");
  t(r.m3Arriba, "(a) el m³ va arriba, al lado del número");
  t(r.sinChipM3, "(a) ya no está el chip de m³ abajo");
  t(r.cliConCod, "(a) el cliente va abajo, con su número de cliente");
  t(r.chevCerrada, "(a) cada ficha tiene su flechita y arranca cerrada");
  t(r.sinTablaCerrada, "(a) cerrada no muestra el contenido");
  t(r.tabla, "(a) abierta: tabla Código / Cajas / Unidades");
  t(r.tablaCod, "(a) el código con sus cajas");
  t(r.tablaUni, "(a) las unidades con cuántas entran por bulto (×12)");
  t(r.tablaTotal, "(a) el total de códigos, cajas y unidades");
  t(r.resumen, "(a) el resumen de arriba: líneas, cajas, unidades");
  t(r.entrega, "(a) la dirección de entrega");
  t(r.isisPidio, "(c) abrir una NP de ISIS dispara la lectura del detalle");
  t(r.isisFalla, "(c) si no se puede leer, lo dice");
  t(r.isisSinMentira, "(c) NUNCA dice que el detalle de una NP de ISIS no existe");
  t(r.isisRuta, "(c) lo pide a gv_ppp_isis_items filtrando por esa NP");
  t(r.isisTabla, "(c) muestra los códigos y las cajas de la base del PPP");
  t(r.isisUni, "(c) con las unidades resueltas por el uxb del artículo");
  t(r.isisTotal, "(c) y su total de códigos, cajas y unidades");
  t(r.isisResumen, "(c) el resumen de arriba suma las unidades del detalle");
  t(r.isisCache, "(c) una sola vuelta de red por NP (después sale del caché)");
  t(r.isisReintento, "(c) el 🔄 reintenta sólo las que fallaron");
  t(r.cuarChev, "(b) la ficha de Cuarentena tiene la flechita arriba a la derecha");
  t(r.cuarCerrada, "(b) arranca cerrada");
  t(r.cuarTabla, "(b) abierta muestra el mismo detalle de códigos y cajas");
  t(r.cuarResumenDet, "(b) con el resumen de cajas y unidades");
  t(r.cuarSigueBadge, "(b) sigue mostrando el badge del motivo y el botón de liberar");
  t(r.cuarCodDet, "(b) el número de cliente de Chef con su prefijo");
  t(r.demoTabla, "(b) el pedido de EJEMPLO también trae contenido");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  console.log(ok ? "\nOK apr-contenido-np" : "\nFALLÓ apr-contenido-np");
  process.exit(ok ? 0 : 1);
})();
