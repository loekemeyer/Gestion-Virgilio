/* Regresión v21.94 — MÓDULO "AGREGAR EXPRESO ISIS".

   Thomas, 2026-09-23: el cliente elige o cambia su expreso desde el checkout de la
   página, y eso tiene que figurar acá para cargarlo a mano en ISIS.

   ⚠ Lo que este test cuida NO es que la lista se vea linda: es que la fila que
     necesita LLAMAR AL CLIENTE se distinga de la que se carga sola. Un expreso
     que no está en nuestro padrón Y que vino sin dirección no se puede dar de
     alta — la dirección es opcional a propósito, porque la regla es que el
     cliente nunca se frene por una carga administrativa.

   Chequea, con la red simulada (sin tocar Supabase):
   - el badge cuenta los pendientes, y se pone ROJO si alguno no tiene dirección;
   - el módulo abre y lista los tres casos (cambio, alta con dirección, alta sin);
   - la fila sin dirección se marca en rojo y dice que hay que preguntársela;
   - el alta de un expreso que no tenemos lleva el cartel NUEVO;
   - el texto del módulo aclara que el pedido YA SALIÓ (esto no frena nada);
   - marcar "Cargado" pasa por la RPC gv_expreso_marcar, no por un UPDATE suelto.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const FILAS = [
  { id: 7, empresa: "lk", cod_cliente: "4042", razon_social: "Multi Bazar S.A.",
    sucursal_label: "Ruta 12 km 4 - Puerto Rico", slot: 2,
    expreso_anterior: "ALBO", expreso_nuevo: "LA SEVILLANITA",
    direccion_nueva: "PERGAMINO 3751", localidad_nueva: "Soldati", provincia_nueva: "Capital Federal",
    del_padron: true, estado: "pendiente", dias: 1,
    que_hacer: "cambiar el expreso del cliente en ISIS", falta_direccion: false },
  { id: 8, empresa: "lk", cod_cliente: "2533", razon_social: "Osa S.R.L.",
    sucursal_label: "Mitre 900 - Rosario", slot: 1,
    expreso_anterior: null, expreso_nuevo: "TRANSPORTE DEL LITORAL",
    direccion_nueva: "Av. Suarez 2590", localidad_nueva: "Barracas", provincia_nueva: "Capital Federal",
    del_padron: false, estado: "pendiente", dias: 2,
    que_hacer: "ALTA de expreso nuevo en ISIS", falta_direccion: false },
  { id: 9, empresa: "lk", cod_cliente: "1448", razon_social: "Silvano Lucas Martin",
    sucursal_label: "San Martin 50 - Posadas", slot: 1,
    expreso_anterior: null, expreso_nuevo: "EXPRESO DEL NORTE",
    direccion_nueva: null, localidad_nueva: null, provincia_nueva: null,
    del_padron: false, estado: "pendiente", dias: 5,
    que_hacer: "ALTA de expreso nuevo en ISIS — FALTA la direccion, hay que preguntarsela al cliente",
    falta_direccion: true },
];

(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  p.on("dialog", (d) => d.accept().catch(() => {}));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (filas) => {
    const out = { rpc: [] };
    window.fetch = async function (url, opts) {
      const u = String(url);
      if (u.indexOf("/rpc/gv_expreso_marcar") >= 0) {
        out.rpc.push(JSON.parse((opts && opts.body) || "{}"));
        return { ok: true, status: 200, text: async () => JSON.stringify({ ok: true }) };
      }
      if (u.indexOf("gv_expreso_pendiente") >= 0) {
        // gvRestTodo pagina: la 2ª página tiene que venir vacía o no corta.
        const off = Number((u.match(/offset=(\d+)/) || [])[1] || 0);
        return { ok: true, status: 200, json: async () => (off ? [] : filas) };
      }
      return { ok: true, status: 200, json: async () => [], text: async () => "[]" };
    };
    // el guard de supervisor vive en el backend; acá sólo se mide el front
    window.facAuthWriteHeaders = async () => ({ apikey: "x", Authorization: "Bearer x",
      "Content-Type": "application/json" });

    // 1) BADGE
    await window.expIsisLoadBadge();
    const bg = document.getElementById("expIsisBadge");
    out.badgeTexto = bg ? bg.textContent : "(no existe)";
    out.badgeVisible = bg ? bg.style.display !== "none" : false;
    out.badgeRojo = bg ? bg.style.background : "";

    // 2) MÓDULO
    await window.openExpresoIsis();
    const body = document.getElementById("expIsisBody");
    out.html = body ? body.innerHTML : "";
    out.texto = body ? body.textContent : "";
    const filasTr = body ? body.querySelectorAll("tbody tr") : [];
    out.nFilas = filasTr.length;
    out.rojas = Array.from(filasTr).filter((t) => /fef2f2/.test(t.getAttribute("style") || "")).length;

    // 3) marcar cargado el primero
    const btn = body ? body.querySelector('button[onclick*="cargado_isis"]') : null;
    if (btn) { btn.click(); await new Promise((r) => setTimeout(r, 300)); }
    return out;
  }, FILAS);

  const t = r.texto || "";
  if (!r.badgeVisible) fallos.push("el badge no se ve con 3 pendientes");
  if (r.badgeTexto !== "⚠ 3") fallos.push('el badge tenía que decir "⚠ 3" (hay uno sin dirección), dice "' + r.badgeTexto + '"');
  if (r.badgeRojo !== "rgb(185, 28, 28)") fallos.push("el badge tenía que estar en rojo con un expreso sin dirección, está " + r.badgeRojo);

  if (r.nFilas !== 3) fallos.push("tenía que listar las 3 filas, listó " + r.nFilas);
  if (r.rojas !== 1) fallos.push("tenía que marcar en rojo SÓLO la que no tiene dirección, marcó " + r.rojas);
  if (!/sin dirección/.test(t)) fallos.push('la fila sin dirección tenía que decirlo');
  if (!/preguntársela al cliente|preguntarsela al cliente/.test(t)) fallos.push("no dice que hay que preguntarle la dirección al cliente");
  if (!/NUEVO/.test(r.html)) fallos.push("falta el cartel NUEVO en los expresos que no están en el padrón");
  if (!/ya salió con el expreso nuevo/.test(t)) fallos.push("el módulo no aclara que el pedido YA SALIÓ — sin eso alguien lo lee como un freno");
  if (!/LA SEVILLANITA/.test(t) || !/ALBO/.test(t)) fallos.push("no muestra el cambio (de qué expreso a cuál)");

  if (r.rpc.length !== 1) fallos.push("marcar 'Cargado' tenía que llamar a gv_expreso_marcar 1 vez, llamó " + r.rpc.length);
  else {
    if (Number(r.rpc[0].p_id) !== 7) fallos.push("marcó el id equivocado: " + JSON.stringify(r.rpc[0]));
    if (r.rpc[0].p_estado !== "cargado_isis") fallos.push("no mandó estado cargado_isis: " + JSON.stringify(r.rpc[0]));
  }
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  await b.close();
  if (fallos.length) {
    console.error("exp-isis-modulo FALLA:\n - " + fallos.join("\n - "));
    process.exit(1);
  }
  console.log("exp-isis-modulo: OK — badge rojo con 3, la fila sin dirección se distingue, cartel NUEVO, aclara que el pedido ya salió, y marcar pasa por la RPC.");
})().catch((e) => { console.error("exp-isis-modulo ERROR: " + (e && e.stack ? e.stack : e)); process.exit(1); });
