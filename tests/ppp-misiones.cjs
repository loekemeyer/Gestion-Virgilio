/* Regresión v20.45 — EL DESTINO DEL EXPRESO Y EL AVISO DE MISIONES EN LA PROGRAMACIÓN.

   Luis, 2026-09-21: *"Tenemos que traer el dato de las dos paginas, tiene que viajar con los
   pedidos. Esta bueno que muestre la zona así para los expresos (expreso y provincia destino).
   Pero particularmente para los pedido de misiones necesito que la fila del día que tenga
   programado un pedido de misiones se ponga naranja y aparezca una medalla que diga (Hay pedido
   misiones). Lo mismo para tandas. Que las NPs de ese tipo de pedidos tambien se coloreen de
   naranja y tengan el badge "MISIONES"*.

   Corre el árbol de la Programación con filas de prueba y un mapa de destinos inyectado —sin
   red— y chequea sobre el HTML que sale:
   - la NP marcada lleva la clase `mis` y el badge con el nombre de la provincia;
   - la tanda que la contiene y el día que la contiene también (la marca SUBE, no se calcula
     aparte: las partes tienen que sumar el todo, igual que los m³ y los estados);
   - una NP sin alerta NO se pinta, y su tanda tampoco;
   - el destino del expreso ("Snaider · Misiones") se muestra sólo cuando HAY expreso;
   - la provincia NO está hardcodeada en el front: sale del flag `alerta` que manda el backend
     (`PPP_Web_Config.provincias_alerta`). Con otra provincia marcada tiene que andar igual.
   - el feed de LK pide `provincia` (sin eso el dato no viaja desde la página).
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];

  // ── guard estático: el dato tiene que salir de la página ──────────────────────────────
  const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
  if (!/select=[a-z_,0-9]*localidad,provincia,zona_expreso/.test(html))
    fallos.push("el feed de LK no pide `provincia`: el destino no viaja desde la página");
  // v20.47: por RPC, NO por la vista. `GV_Clientes_Direcciones` tiene RLS y anon no ve una
  // sola fila, asi que la vista leida desde el navegador devolvia "sin padron" para TODO:
  // HTTP 200, sin error, y la Programacion sin pintar nada.
  if (!/rest\/v1\/rpc\/gv_np_destino_lista/.test(html))
    fallos.push("no se llama la RPC gv_np_destino_lista");
  // v20.49: se pide POR LISTA DE NP. PostgREST corta en 1.000 filas y contesta 200 sin avisar:
  // con el universo entero (1.482 NP) "LK 0027" quedaba afuera del corte y no se pintaba.
  if (!/p_nps: lote/.test(html))
    fallos.push("la RPC se llama sin p_nps: con mas de 1.000 NP PostgREST corta en silencio");
  if (/rest\/v1\/gv_np_destino\?select=/.test(html))
    fallos.push("se lee la VISTA gv_np_destino desde el front: anon no ve el padron y devuelve 'sin padron' para todo");
  // la provincia no se decide en el front
  if (/["']Misiones["']/.test(html.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "")))
    fallos.push("aparece 'Misiones' hardcodeado fuera de los comentarios: tiene que salir de PPP_Web_Config.provincias_alerta");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // tres NP: una a Misiones por expreso, una a Santa Fe por expreso (no marcada) y una de
    // CABA sin expreso. Dos tandas, en dos días distintos.
    const filas = [
      { fecha: "2026-09-25", tanda: "E90A", np: "LK 0027", cod: "958", razon_social: "Albalandia S.R.L. (M)",
        localidad: "Soldati", barrio: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1",
        empresa: "LK", origen: "web", m3: 0.709, estado: "pendiente", estado_orden: 1, clave: "1357" },
      { fecha: "2026-09-25", tanda: "E90B", np: "LK 0028", cod: "2394", razon_social: "Clapera Alicia",
        localidad: "Soldati", barrio: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1",
        empresa: "LK", origen: "web", m3: 0.2, estado: "pendiente", estado_orden: 1, clave: "1358" },
      { fecha: "2026-09-26", tanda: "E91A", np: "LK 0029", cod: "3797", razon_social: "Oranhogar SRL",
        localidad: "Villa Urquiza", barrio: "Villa Urquiza", zona: "Zona 6 - GBA Norte", zona_corta: "Zona 6",
        empresa: "LK", origen: "web", m3: 0.3, estado: "pendiente", estado_orden: 1, clave: "1359" },
    ];
    const dest = new Map([
      ["LK 0027", { np: "LK 0027", provincia: "Misiones", expreso: "Snaider", alerta: true,  destino_txt: "Snaider · Misiones" }],
      ["LK 0028", { np: "LK 0028", provincia: "Santa Fe", expreso: "Avellaneda", alerta: false, destino_txt: "Avellaneda · Santa Fe" }],
      ["LK 0029", { np: "LK 0029", provincia: "CABA", expreso: null, alerta: false, destino_txt: "CABA" }],
    ]);
    // ⚠ `_pgaDest`, `_pgaOpenD` y `_pgaOpenT` se declaran con `let` en el script inline: NO
    // viven en `window`. Se asignan directo, que desde acá cae en el mismo binding.
    _pgaDest = dest;
    _pppSearch = "";
    _pgaOpenD = { "20260925": true, "20260926": true };
    _pgaOpenT = { "20260925|E90A": true, "20260925|E90B": true, "20260926|E91A": true };

    const arbol = _pgaArbol(filas);
    out.dias = arbol.map(function (d) {
      return { key: d.key, mis: d.mis, provs: [...d.misProv],
               tandas: d.tandasArr.map(function (t) { return { tanda: t.tanda, mis: t.mis }; }) };
    });
    const h = _pgaCuerpoHtml(arbol, {});
    out.html = h;

    // ¿qué filas quedaron marcadas?
    const trs = h.split("<tr ").slice(1);
    out.filasMis = trs.filter(function (x) { return / mis"/.test(x.split(">")[0]); }).length;
    out.npMis   = trs.filter(function (x) { return /pga-n[^"]* mis"/.test(x.split(">")[0]); }).length;
    out.tMis    = trs.filter(function (x) { return /pga-t [^"]*mis"/.test(x.split(">")[0]); }).length;
    out.dMis    = trs.filter(function (x) { return /pga-d[^"]* mis"/.test(x.split(">")[0]); }).length;

    // ── y ahora con OTRA provincia marcada: el front no puede tener Misiones adentro ──────
    dest.set("LK 0029", { np: "LK 0029", provincia: "Chubut", expreso: "Cruz Del Sur", alerta: true, destino_txt: "Cruz Del Sur · Chubut" });
    const h2 = _pgaCuerpoHtml(_pgaArbol(filas), {});
    out.chubut = /CHUBUT/.test(h2) && /Hay pedido Chubut/.test(h2);
    return out;
  });

  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  const d25 = (r.dias || []).find((x) => x.key === "20260925") || {};
  const d26 = (r.dias || []).find((x) => x.key === "20260926") || {};
  if (d25.mis !== 1) fallos.push("el día 25/09 tendría que contar 1 pedido marcado, cuenta " + d25.mis);
  if ((d25.provs || []).join() !== "Misiones") fallos.push("el día no guardó la provincia: " + JSON.stringify(d25.provs));
  if (d26.mis !== 0) fallos.push("el día 26/09 no tiene pedidos marcados y cuenta " + d26.mis);
  const t90a = (d25.tandas || []).find((x) => x.tanda === "E90A") || {};
  const t90b = (d25.tandas || []).find((x) => x.tanda === "E90B") || {};
  if (t90a.mis !== 1) fallos.push("la tanda E90A tendría que contar 1, cuenta " + t90a.mis);
  if (t90b.mis !== 0) fallos.push("la tanda E90B no lleva Misiones y cuenta " + t90b.mis);

  if (r.dMis !== 1) fallos.push("filas de DÍA en naranja: " + r.dMis + " (esperado 1)");
  if (r.tMis !== 1) fallos.push("filas de TANDA en naranja: " + r.tMis + " (esperado 1)");
  if (r.npMis !== 1) fallos.push("filas de NP en naranja: " + r.npMis + " (esperado 1)");

  const h = r.html || "";
  if (!/class="pga-mis"[^>]*>MISIONES</.test(h)) fallos.push("falta el badge MISIONES en la fila de la NP");
  if (!/Hay pedido Misiones/.test(h)) fallos.push("falta la medalla «Hay pedido Misiones» en el día y la tanda");
  if ((h.match(/Hay pedido Misiones/g) || []).length < 2) fallos.push("la medalla tiene que estar en el día Y en la tanda");
  if (!/Snaider · Misiones/.test(h)) fallos.push("falta el destino del expreso en la fila de la NP");
  if (!/Avellaneda · Santa Fe/.test(h)) fallos.push("el destino del expreso sólo se muestra para la provincia marcada; tiene que mostrarse siempre que haya expreso");
  if (/pga-dest[^<]*>🚚 CABA</.test(h)) fallos.push("un pedido SIN expreso no tiene que mostrar chip de destino");
  if (!r.chubut) fallos.push("con otra provincia marcada el front no reacciona: la provincia está hardcodeada");

  // ── A Programar (v20.51) ──────────────────────────────────────────────────────────────
  const b2 = await chromium.launch();
  const p2 = await b2.newPage();
  const errs2 = [];
  p2.on("pageerror", (e) => errs2.push(e.message));
  await p2.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const a = await p2.evaluate(() => {
    const out = {};
    _aprProvAlerta = new Set(["misiones"]);
    const web  = { order_id: 1357, empresa: "lk", cod: "958", razon_social: "Albalandia S.R.L. (M)",
                   zona: "Zona 1 - CABA Sur", localidad: "Soldati", provincia: "Misiones", expreso: "Snaider" };
    const web2 = { order_id: 1358, empresa: "lk", cod: "2394", razon_social: "Clapera",
                   zona: "Zona 1 - CABA Sur", localidad: "Soldati", provincia: "Santa Fe", expreso: "Avellaneda" };
    const caba = { order_id: 1359, empresa: "lk", cod: "3797", razon_social: "Oranhogar",
                   zona: "Zona 6 - GBA Norte", localidad: "Villa Urquiza", provincia: "CABA", expreso: "" };
    // un pedido de ISIS: no trae provincia, la saca del mapa de gv_np_destino_lista
    const isis = { order_id: 0, np: "98615", _isis: true, empresa: "lk", cod: "958",
                   razon_social: "Albalandia S.R.L. (M)", zona: "Zona 1 - CABA Sur", provincia: "", expreso: "" };
    _pgaDest = new Map([["98615", { np: "98615", provincia: "Misiones", expreso: "Snaider", alerta: true,
                                    destino_txt: "Snaider · Misiones" }]]);
    out.web   = { marcada: aprEsProvMarcada(web),  chip: aprDestinoChip(web),  badge: aprMisBadge(web) };
    out.web2  = { marcada: aprEsProvMarcada(web2), chip: aprDestinoChip(web2), badge: aprMisBadge(web2) };
    out.caba  = { marcada: aprEsProvMarcada(caba), chip: aprDestinoChip(caba) };
    out.isis  = { marcada: aprEsProvMarcada(isis), chip: aprDestinoChip(isis), badge: aprMisBadge(isis) };
    // y con la provincia marcada cambiada, el front tiene que seguir a la config
    _aprProvAlerta = new Set(["santa fe"]);
    out.cambia = { web: aprEsProvMarcada(web), web2: aprEsProvMarcada(web2) };
    return out;
  });
  await b2.close();
  if (errs2.length) fallos.push("errores de página (A Programar): " + errs2.join(" | "));

  if (!a.web.marcada) fallos.push("A Programar: el pedido web a Misiones no queda marcado");
  if (!/apr-chip-mis[^>]*>MISIONES</.test(a.web.badge)) fallos.push("A Programar: falta el badge MISIONES");
  if (!/Snaider · Misiones/.test(a.web.chip)) fallos.push("A Programar: falta el destino del expreso");
  if (a.web2.marcada) fallos.push("A Programar: Santa Fe no está marcada y se pintó igual");
  if (!/Avellaneda · Santa Fe/.test(a.web2.chip)) fallos.push("A Programar: el chip de destino tiene que salir siempre que haya expreso");
  if (a.caba.chip) fallos.push("A Programar: un pedido sin expreso no lleva chip de destino");
  if (!a.isis.marcada) fallos.push("A Programar: la NP de ISIS no resuelve su destino por gv_np_destino_lista");
  if (!/apr-chip-mis[^>]*>MISIONES</.test(a.isis.badge)) fallos.push("A Programar: falta el badge en la NP de ISIS");
  if (a.cambia.web || !a.cambia.web2) fallos.push("A Programar: la provincia marcada está hardcodeada, no sigue la config");
  // el naranja en la tarjeta y que el chip esté enganchado al render
  if (!/apr-card\.mis\{/.test(html)) fallos.push("falta el CSS .apr-card.mis");
  if (!/aprDestinoChip\(p\) \+ aprMisBadge\(p\)/.test(html)) fallos.push("la tarjeta de A Programar no pinta los chips");
  if (!/aprEsProvMarcada\(p\) \? ' mis' : ''/.test(html)) fallos.push("la tarjeta de A Programar no se pinta de naranja");

  if (fallos.length) { console.error("ppp-misiones FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("ppp-misiones OK — Programación y A Programar en naranja, badge y destino por dato.");
})();
