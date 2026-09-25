/* Guard v20.51 — EL TOPE DE 1.000 FILAS DE PostgREST.

   Luis, 2026-09-21: *"fijate que el corte de postgress no nos joda a futuro. si no hay que
   paginar o algo"*.

   PostgREST corta toda respuesta en 1.000 filas (`db-max-rows`) y el `limit=` de la URL NO lo
   levanta: un `limit=20000` contesta 200 con las primeras 1.000 y **nada dice que falten**. No
   hay error, no hay 403, no hay header que mirar. Es lo que se comió la v20.45: `LK 0027`
   quedaba afuera del corte y el pedido a Misiones no se pintaba.

   Este guard barre `index.html`, se queda con las lecturas REST que NO tienen ningún filtro
   (las que leen el universo entero de algo) y exige que:
     · vayan por `gvRestTodo(...)`, que pagina con offset; o
     · estén en CHICAS, la lista de objetos que son chicos por naturaleza, cada uno con el
       conteo medido y la fecha. Si alguno crece, hay que sacarlo de ahí y paginarlo.

   Una lectura sin filtro que no cumpla ninguna de las dos hace fallar el test. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

/* Objetos que leemos ENTEROS y son chicos por naturaleza — conteo medido el 2026-09-21.
   No crecen con el tiempo (config, catálogos, listas de trabajo del día). */
const CHICAS = {
  Camioneros: 13, GV_Rack_CxM: 45, gv_insumo_ubicacion: 149, vista_insumos: 142, Conteo_Stock: 2, Equivalencias_Codigos: 4, Equivalencias_Familia: 18,
  GV_Krikos_OC: 0, GV_Tandas_Auto_Log: 1, Insumos_Factores: 45, PPP_Web_Config: 62,
  gv_np_prog_sin_base: 0, gv_pedido_mod_np: 8, gv_ppp_cliente_dos_dias: 0,
  gv_ppp_super_mezclado: 0, gv_vista_cola_impresion: 0, gv_vista_control_remitos: 29,
  reporte_agentes: 165, vista_cola_impresion: 0, vista_correcciones_pedido_rich: 0,
  vista_np_faltantes_secuencia: 0, vista_np_sin_programar: 0, vista_pedidos_equivalencia: 2,
  vista_prov_importacion: 153, vista_recepcion_mensual: 469,
};
/* Las que leen el universo entero de algo que SÍ crece: tienen que ir por gvRestTodo. */
const DEBEN_PAGINAR = [
  "gv_proyeccion_articulo", "vista_uxb_articulo", "vista_abastecimiento", "PPP_Geo", "GV_Clientes_Nuevos",
  "PPP_Web_Programacion", "gv_ppp_web_estado", "vista_fc_sin_salida", "Zonas_Barrios",
  // Cola de "Agregar Expreso ISIS": crece sola si nadie la vacia (v21.94).
  "gv_expreso_pendiente",
];

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const fallos = [];

if (!/async function gvRestTodo\(/.test(html)) fallos.push("no existe gvRestTodo()");
if (!/const REST_PAGINA = 1000;/.test(html)) fallos.push("REST_PAGINA tiene que ser 1000, el tope real de PostgREST");
if (!/limit=" \+ REST_PAGINA \+ "&offset=" \+ off/.test(html))
  fallos.push("gvRestTodo no pagina con offset");
if (!/replace\(\/\(\[\?&\]\)\(limit\|offset\)=/.test(html))
  fallos.push("gvRestTodo no le saca el limit= viejo al path: PostgREST se quedaria con el de la URL");

/* Las que declaramos que paginan tienen que seguir leyendose por gvRestTodo. */
for (const obj of DEBEN_PAGINAR) {
  if (!new RegExp('gvRestTodo\\("' + obj + '\\?').test(html))
    fallos.push(obj + ": ya no se lee por gvRestTodo — si la lectura se saco, borralo de DEBEN_PAGINAR");
}

/* Y el barrido: toda lectura REST sin filtro tiene que estar contemplada. */
const pat = /\/rest\/v1\/([A-Za-z0-9_]+)\?/g;
const sinFiltro = new Set();
let m;
while ((m = pat.exec(html)) !== null) {
  const obj = m[1];
  if (obj === "rpc") continue;
  const cola = html.slice(m.index + m[0].length - 1, m.index + m[0].length - 1 + 700);
  const cortes = ['", {', '",{', "{ headers", ", {\n", "cache:"]
    .map((x) => cola.indexOf(x)).filter((x) => x >= 0);
  const expr = cortes.length ? cola.slice(0, Math.min.apply(null, cortes)) : cola.slice(0, 400);
  const filtra = /[?&][a-zA-Z_]+=(eq|in|gte|lte|gt|lt|is|neq|like|ilike|cs|not|ov)\./.test(expr)
    || /[?&]or=\(/.test(expr) || expr.indexOf("on_conflict=") >= 0;
  if (!filtra) {
    sinFiltro.add(obj);
    // ⚠ y si es una de las que tienen que paginar, la lectura SIN FILTRO no puede ser un
    // fetch pelado. Se mira lo que hay ANTES del nombre: `gvRestTodo("` o `fetch(`.
    const antes = html.slice(Math.max(0, m.index - 60), m.index);
    if (DEBEN_PAGINAR.indexOf(obj) >= 0 && !/gvRestTodo\("$|gvRestTodo\("[^"]*$/.test(antes + obj))
      if (/fetch\(/.test(antes))
        fallos.push(obj + ": lectura entera con fetch pelado — tiene que ir por gvRestTodo " +
                    "(crece, y el corte de 1.000 no avisa)");
  }
}
for (const obj of sinFiltro) {
  if (DEBEN_PAGINAR.indexOf(obj) >= 0) continue;
  if (Object.prototype.hasOwnProperty.call(CHICAS, obj)) continue;
  fallos.push(obj + ": lee el universo entero y no esta ni en DEBEN_PAGINAR ni en CHICAS. " +
    "Conta sus filas: si puede pasar las 1.000 hay que pasarla por gvRestTodo; si es chica de " +
    "verdad, agregala a CHICAS con su conteo.");
}

if (fallos.length) { console.error("rest-tope-1000 FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("rest-tope-1000 OK — " + DEBEN_PAGINAR.length + " lecturas enteras paginadas, " +
  Object.keys(CHICAS).length + " chicas declaradas, 0 sueltas.");
