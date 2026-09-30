/* test_rpc_huerfanas.js — LAS RPC QUE ESCRIBEN Y QUE NADIE LLAMA (idea 7328)
 *
 * El barrido del 2026-09-11 encontró nueve funciones con EXECUTE para `anon` que ninguna
 * pantalla de este repo llama. Cada una es una puerta abierta: escriben en el ledger y la
 * clave publicable está en el HTML de todas las pantallas. Ese barrido era una consulta que
 * había que ACORDARSE de correr; esto lo vuelve parte de la suite.
 *
 * Lo que mira (offline, sin tocar la base): toda función de `db/funciones_GP2.sql` que
 * ESCRIBE (insert/update/delete) y que ninguna pantalla nombra con rpc('x') tiene que estar
 * en PERMITIDAS de abajo, CON SU MOTIVO. Una función nueva que escribe y que nadie llama
 * prende el test: o la llama alguien y falta cablearla, o no va, o es a propósito y se anota
 * acá en una línea.
 *
 * Lo que NO puede mirar: el GRANT en sí (db/ no guarda los permisos). Eso sigue siendo la
 * consulta de verificar.sql. Acá se vigila la otra mitad —"nadie la llama"— que es la que
 * se desvía sola cuando una pantalla cambia de motor y la RPC vieja queda viva.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };

/* Las que se dejan a propósito, cada una con el motivo. Sacar una de acá tiene que ser una
   decisión, no un descuido. */
const PERMITIDAS = {
  // Cliente EXTERNO con la clave anon: el contrato está en INTEGRACION_GESTION_VIRGILIO.md.
  recibir_oc_virgilio:       'la llama Gestión Virgilio (cliente externo)',
  traslado_virgilio:         'la llama Gestión Virgilio (cliente externo)',
  enviar_material_virgilio:  'la llama Gestión Virgilio (cliente externo)',
  // 2026-09-29: la app nueva de registro de produccion vive en otro repo (GP2-Registro-Produccion)
  // y manda con sesion de operario (Edge login-operario). Sin EXECUTE a anon.
  recibir_mensaje_cervantes: 'la llama GP2-Registro-Produccion (otro repo), con sesion de operario',
  // Mantenimiento: se corren a mano desde una sesión, no desde una pantalla.
  planilla_cargar:           'mantenimiento: carga el snapshot de la planilla de costos',
  planilla_snapshot_nuevo:   'mantenimiento: abre el snapshot de la planilla de costos',
  reprocesar_espejo_virgilio:'mantenimiento: reprocesa las entregas del espejo que quedaron pendientes',
  // No es el motor (idea 7316): quedó sin EXECUTE para anon y con un comment que lo dice.
  crear_entrega_tallerista:  'no es el motor de la entrega de tallerista (idea 7316), sin grant a anon',
  // Las llama algo que no es una pantalla.
  actualizar_dolar_oficial:  'la llama el cron del dólar',
  factura_lectura_permitida: 'la llama la Edge Function gp2_leer_factura (tope diario, idea 7339)',
  // 2026-09-15: la pantalla Proporciones paso a SOLO LECTURA por pedido del dueño ("que no se
  // pueda modificar la proporcion en el programa"): el % se carga por SQL con esta función, que
  // valida (suman 100, el tallerista hace ese paso) y recalcula los máximos. Sin EXECUTE a anon.
  reparto_guardar:           'mantenimiento: carga el reparto por SQL; la pantalla es solo lectura',
  // 2026-09-23: el máximo del Prov AT sale del mismo motor que el del tallerista y se recalcula a
  // mano, igual que recalcular_maximos_talleristas. Además CREA filas de inventario cuando se la
  // llama con p_crear_faltantes => true (las 12 ubicaciones de prov AT tienen cero), y eso es
  // escribir datos: lo autoriza el dueño, no una pantalla. Sin EXECUTE a anon.
  recalcular_maximos_prov_at:'mantenimiento: recalcula el máximo del Prov AT por SQL, sin grant a anon',
  // La corre fn_recalc_maximos_diferido (trigger al COMMIT); a mano solo para recalcular fuera de un cambio.
  recalcular_maximo_mp_ps:'mantenimiento: maximo de la materia prima que corta un PS (ALAMBRE, FLEJE_DESCORAZONADOR), sin grant a anon',
  // 2026-09-24: helper interno del motor de producción; la llaman registrar_produccion y
  // registrar_evento_prod (por SQL, no por rpc()) para descontar TODAS las entradas de una
  // convergencia. No es RPC de pantalla y no matchea la convención de nombres interna (_/fn_).
  fabricar_stock:            'helper interno de convergencia, la llaman registrar_produccion/registrar_evento_prod',
};

/* Internas: helpers de otras funciones, cuerpos de trigger y simuladores. No son RPC de
   pantalla y no se esperan llamadas. Se reconocen por el nombre, que es la convención de
   la casa: "_" y "__" para lo interno, "fn_" para lo que cuelga de un trigger. */
const esInterna = (n) => /^_/.test(n) || /^fn_/.test(n) || n === 'inv_delta';

const sql = fs.readFileSync(path.join(ROOT, 'db', 'funciones_GP2.sql'), 'utf8');
const cuerpo = {};   // nombre -> texto de la funcion
for (const b of sql.split(/(?=CREATE OR REPLACE FUNCTION "GP2"\.)/)) {
  const m = /^CREATE OR REPLACE FUNCTION "GP2"\.(\w+)\(/.exec(b);
  if (m) cuerpo[m[1]] = b;
}
const definidas = new Set(Object.keys(cuerpo));
/* Escribe = lo hace con sus manos... */
const escribe = new Set(definidas.size ? [...definidas].filter(n =>
  /\binsert\s+into\b|\bdelete\s+from\b|\bupdate\s+"?GP2"?\.|\bupdate\s+\w+\s+set\b/i.test(cuerpo[n])) : []);
/* ...o llama a una que escribe. `enviar_material_virgilio` es el caso: no toca una tabla, arma
   las filas y las manda por otra RPC — y escribe igual. Sin este cierre, un envoltorio nuevo
   alrededor de registrar_movimientos pasaba por debajo del test. Dos vueltas alcanzan para el
   encadenado que hay hoy (pantalla -> envoltorio -> motor). */
for (let v = 0; v < 2; v++) {
  for (const n of definidas) {
    if (escribe.has(n)) continue;
    for (const w of escribe) {
      // El llamado puede venir sin calificar ("v_res := enviar_material_inyector(...)"), asi
      // que se busca el nombre seguido de parentesis en cualquier parte del cuerpo, salteando
      // la linea del CREATE (que es el nombre de la funcion misma).
      if (w !== n && new RegExp('\\b' + w + '\\s*\\(', 'i').test(cuerpo[n].replace(/^CREATE[\s\S]*?\n/, ''))) { escribe.add(n); break; }
    }
  }
}
const escriben = [...escribe];
ok(escriben.length > 40, 'db/funciones_GP2.sql se pudo leer (' + escriben.length + ' funciones que escriben)');

/* Lo que llaman las pantallas. Se recorre el repo entero menos los tests: una RPC nombrada
   en un test no cuenta como usada. */
const llamadas = new Set();
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (e.name === '.git' || e.name === 'node_modules') continue;
    const f = path.join(d, e.name);
    if (e.isDirectory()) { if (f !== path.join(ROOT, 'tests')) walk(f); continue; }
    if (!/\.(html|js)$/.test(e.name)) continue;
    const t = fs.readFileSync(f, 'utf8');
    for (const m of t.matchAll(/rpc\(\s*[`'"]([A-Za-z0-9_]+)/g)) llamadas.add(m[1]);
  }
})(ROOT);
ok(llamadas.size > 60, 'las pantallas llaman ' + llamadas.size + ' RPC distintas');

const huerfanas = escriben.filter(n => !llamadas.has(n) && !esInterna(n));
const sinPermiso = huerfanas.filter(n => !PERMITIDAS[n]);
sinPermiso.forEach(n => console.log('     ' + n + ': escribe, ninguna pantalla la llama y no está en PERMITIDAS'));
ok(sinPermiso.length === 0,
   'ninguna RPC que escribe queda sin llamar y sin permiso escrito (' + huerfanas.length + ' permitidas)');

/* Y al revés: un permiso que sobra también es ruido. Si la función dejó de existir o alguna
   pantalla la empezó a llamar, la línea de PERMITIDAS se saca. */
const sobran = Object.keys(PERMITIDAS).filter(n => !escriben.includes(n) || llamadas.has(n));
sobran.forEach(n => console.log('     ' + n + ': está en PERMITIDAS pero ya no hace falta (o no existe, o alguien la llama)'));
ok(sobran.length === 0, 'la lista de permitidas no tiene sobrantes');

console.log(fallas ? 'HAY FALLOS' : 'TODO OK');
