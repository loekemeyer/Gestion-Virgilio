/* Póster 40x50 cm de la botonera del operario (Luis, 09/10/2026).
   Saca la captura de la botonera REAL (index.html, celular 390 px, x4) y arma el póster con un
   número sobre cada botón y su explicación al costado. Si cambia la botonera, se vuelve a correr:
     node docs/tutorial-operarios/generar.cjs
   Sale botonera-operarios-40x50.pdf (para imprimir) y botonera-operarios-40x50.png (vista previa). */
const path = require("path");
const fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { ({ chromium } = require("playwright")); }
const DIR = __dirname;
const INDEX = path.join(DIR, "..", "..", "index.html");

// número → [código del botón (data-code o id), título, explicación]. El orden es el de lectura.
const ITEMS = [
  ["sec", "Arriba de todo"],
  [".back-top", "← Volver", "Vuelve a la pantalla de inicio, con el resumen de lo que hiciste hoy."],
  ["#btnTerminarDia", "Terminar Día", "Al irte. Cierra tu día. Un picking o armado sin terminar queda guardado y se sigue mañana."],
  ["#tmMuerto", "Tiempo muerto", "Tiempo desde tu última tarea. A los 5 minutos sin marcar nada, suena la alarma en la TV."],
  ["#btnHistTareas", "Historial de tareas", "Todo lo que marcaste hoy, con cuánto duró cada tarea."],
  ["sec", "Picking"],
  ["EP", "EP · Empecé Picking", "Elegís la tanda y la app te lleva góndola por góndola. Confirmás las cajas de cada código y al final terminás (o la frenás para seguirla después)."],
  ["AP", "AP · Empecé Armado Pedido", "Elegís una tanda ya pickeada y armás NP por NP con el asistente. Al terminar cada NP sale su hoja."],
  ["sec", "Depósito y carga"],
  ["RT", "RT · Recepción Mercadería", "Cargás lo que entrega cada tallerista o proveedor: código y cajas, contra su OC."],
  ["MG", "MG · Guardado a Góndola", "Guardás lo que llegó (A guardar) o el excedente. Marcás cada código guardado y al final «Terminé de guardar»."],
  ["CC", "CC · Carga Camión", "Al empezar y al terminar de cargar el camión. Marcás cada NP que sube."],
  ["sec", "Acciones secundarias"],
  ["CR", "CR · Control Remitos", "Antes de cargar: controlás los pedidos facturados del reparto y los marcás «Controlado»."],
  ["RR", "RR · Recepción Remitos", "Cuando vuelve el reparto: marcás los remitos recibidos, o «s/salida» si el pedido volvió."],
  ["INS", "Insumos y Productos", "Recibir insumos, entregar insumos o salida a Cervantes."],
  ["CP", "CP · Completar Pedido", "Sumás cajas que llegaron tarde a un pedido ya armado que tenía faltante."],
  ["RC", "RC · Pasar a urgente", "Sacás cajas de un pedido que sale después y se las das a uno que sale antes y le faltan."],
  ["IR", "IR · Ingreso a Racks", "Subís palets a una posición de rack."],
  ["RKBM", "BR · Bajar de Racks", "Bajás cajas del rack a A guardar. La posición es obligatoria y contás lo que queda en el rack."],
  ["MOV", "Mover racks", "Pasás mercadería de una posición de rack a otra."],
  ["PPP", "PPP · Programación por día", "Para mirar qué sale los próximos días: m³, tandas y NP."],
  ["sec", "Pausas · tocá al empezar y otra vez al volver"],
  ["AT", "AT · Atendí Timbre", "Mientras atendés la puerta."],
  ["PB", "PB · Paré Baño", "Mientras estás en el baño."],
  ["Limp", "Limp · Limpieza", "Mientras limpiás."],
  ["Perm", "Perm · Permiso de Salida", "Si salís del depósito con permiso."],
  ["PC", "PC · Paré Comida", "Mientras comés."],
  ["CT", "CT · Conteo", "Mientras hacés un conteo de stock."],
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 4 });
  await p.route("**/*.supabase.co/**", (r) => {
    if (r.request().url().includes("select=ts_cliente"))
      return r.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify([{ ts_cliente: new Date(Date.now() - 125000).toISOString() }]) });
    return r.abort();
  });
  await p.goto("file://" + INDEX, { waitUntil: "domcontentloaded" });
  await p.evaluate(async () => {
    window.alert = () => {}; window.confirm = () => true;
    legajoInput.value = "999"; goToOptions();
    await new Promise((r) => setTimeout(r, 800));
    tmStop(); document.getElementById("tmMuertoVal").textContent = "0:02:05";
  });
  const sels = ITEMS.filter((i) => i[0] !== "sec").map((i) => i[0]);
  const rects = await p.evaluate((sels) => sels.map((s) => {
    const e = /^[.#]/.test(s) ? document.querySelector("#optionsScreen " + s) : document.querySelector('#optionsScreen [data-code="' + s + '"]');
    if (!e || !e.offsetParent) return null;
    const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height };
  }), sels);
  const falta = sels.filter((s, i) => !rects[i]);
  if (falta.length) { console.error("No están en la botonera:", falta.join(", ")); process.exit(1); }
  const top = Math.min(...rects.map((r) => r.y)) - 14;
  const bottom = Math.max(...rects.map((r) => r.y + r.h)) + 12;
  const clip = { x: 0, y: top, width: 390, height: bottom - top };
  const png = await p.screenshot({ clip });
  await b.close();

  // pines: arriba a la derecha de cada botón, en % de la captura
  let n = 0;
  const pins = [], notas = [];
  for (const it of ITEMS) {
    if (it[0] === "sec") { notas.push(`<div class="sec">${it[1]}</div>`); continue; }
    const r = rects[n]; n++;
    const cx = (r.x + r.w - 2) / clip.width * 100, cy = (r.y - top + 2) / clip.height * 100;
    pins.push(`<div class="pin" style="left:${cx}%;top:${cy}%">${n}</div>`);
    notas.push(`<div class="kp"><div class="num">${n}</div><div><b>${it[1]}</b><span>${it[2]}</span></div></div>`);
  }
  // izquierda: arriba + picking + depósito · derecha: secundarias · abajo, a lo ancho: las pausas
  const secs = []; notas.forEach((x, i) => { if (x.startsWith('<div class="sec"')) secs.push(i); });
  const [sArr, sPick, sDep, sSec, sPau] = secs;
  const izq = notas.slice(0, sSec).join(""), der = notas.slice(sSec, sPau).join("");
  const pausaTit = notas[sPau], pausas = notas.slice(sPau + 1).join("");
  const imgW = 168, imgH = imgW * clip.height / clip.width;
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
  @page { size: 400mm 500mm; margin: 0 }
  * { box-sizing: border-box }
  body { margin: 0; width: 400mm; height: 500mm; font-family: Arial, Helvetica, sans-serif; color: #111; background: #fff }
  .pag { width: 400mm; height: 500mm; padding: 14mm 12mm 10mm; display: flex; flex-direction: column }
  h1 { margin: 0; font-size: 22mm; text-align: center; letter-spacing: -.3mm }
  .sub { text-align: center; font-size: 8mm; margin: 3mm 0 7mm; color: #333 }
  .sub b { background: #111; color: #fff; padding: 0 2.5mm; border-radius: 2mm }
  .cuerpo { flex: 1; display: grid; grid-template-columns: 1fr ${imgW}mm 1fr; gap: 8mm; align-items: center }
  .col { display: flex; flex-direction: column; gap: 3.2mm }
  .sec { font-size: 6.2mm; font-weight: 700; text-transform: uppercase; color: #555; border-bottom: .5mm solid #999; margin-top: 3mm; padding-bottom: 1mm }
  .kp { display: flex; gap: 3mm; align-items: flex-start }
  .kp b { display: block; font-size: 6.4mm; line-height: 1.1 }
  .kp span { display: block; font-size: 5.2mm; line-height: 1.22; color: #222 }
  .num, .pin { background: #111; color: #fff; font-weight: 700; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex: none }
  .num { width: 10mm; height: 10mm; font-size: 5.6mm }
  .tel { position: relative; width: ${imgW}mm; height: ${imgH}mm; border: 1.2mm solid #111; border-radius: 6mm; overflow: visible; background: #fff }
  .tel img { width: 100%; height: 100%; border-radius: 5mm; display: block }
  .pin { position: absolute; width: 8.5mm; height: 8.5mm; font-size: 4.6mm; transform: translate(-50%,-50%); border: .6mm solid #fff; box-shadow: 0 0 0 .4mm #111 }
  .pausas { margin-top: 5mm }
  .pgrid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 3mm 8mm; margin-top: 3mm }
  .pie { margin-top: 6mm; display: flex; justify-content: space-between; align-items: flex-end; font-size: 5.4mm; color: #333; border-top: .5mm solid #999; padding-top: 3mm }
  .pie div:first-child { max-width: 300mm }
  </style></head><body><div class="pag">
  <h1>Botonera del operario</h1>
  <div class="sub">Tocá el botón y después <b>Enviar</b>. Marcá siempre lo que estás haciendo.</div>
  <div class="cuerpo">
    <div class="col">${izq}</div>
    <div class="tel"><img src="data:image/png;base64,${png.toString("base64")}">${pins.join("")}</div>
    <div class="col">${der}</div>
  </div>
  <div class="pausas">${pausaTit}<div class="pgrid">${pausas}</div></div>
  <div class="pie"><div>¿Te equivocaste? Después de enviar aparece <b>«Deshacer»</b> durante 60 segundos.</div><div>Gestión Virgilio</div></div>
  </div></body></html>`;
  
  const b2 = await chromium.launch();
  const p2 = await b2.newPage({ viewport: { width: 1512, height: 1890 } });   // 400x500 mm a 96 dpi
  await p2.setContent(html, { waitUntil: "load" });
  const desborda = await p2.evaluate(() => document.querySelector(".pag").scrollHeight > document.querySelector(".pag").clientHeight + 1);
  await p2.pdf({ path: path.join(DIR, "botonera-operarios-40x50.pdf"), width: "400mm", height: "500mm", printBackground: true });
  await p2.screenshot({ path: path.join(DIR, "botonera-operarios-40x50.png"), fullPage: false });
  await b2.close();
  console.log("listo · " + n + " botones · captura " + Math.round(clip.width) + "x" + Math.round(clip.height) + " px x4" + (desborda ? " · ⚠ SE DESBORDA" : ""));
})();
