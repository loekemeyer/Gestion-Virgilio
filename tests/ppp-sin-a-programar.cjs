/* v20.80 (Thomas, 2026-09-21) — CANDADO: desde Programacion no se manda un pedido a «A Programar».
   Pedido textual: *"saca del modulo programacion la opcion de mandar pedidos a 'A programar'. una
   vez programados o se eliminan o se reprograman para otra fecha"*.

   Un pedido ya programado tiene DOS salidas y ninguna mas:
     · se reprograma  -> 📅 Cambiar de dia  (pgaNpMoverAbrir)
     · se elimina     -> ✕ Cancelar pedido  (pppVencCancelar / el pop-up de cancelar)

   Por que un candado ESTATICO y no de pantalla: las puertas eran TRES y estaban en dos modulos
   distintos (la fila de la NP en el arbol, y los dos paneles de la NP: el de pedido sin empezar y
   el de vencidos). Un test de pantalla prueba la que renderiza ese caso y deja pasar las otras
   dos; esto barre el archivo entero y no se le escapa ninguna.

   Falla si vuelve a aparecer un boton (un onclick) que llame a pgaEnviarAProgramar,
   pppVencVolver o pppVencSinProgramar. Las funciones SIGUEN EN EL ARCHIVO a proposito —igual que
   `gv_ppp_np_desarmar` del backend cuando se saco el boton de Desarmar en la v18.77—: lo que no
   puede volver es la PUERTA. Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const HTML = path.join(__dirname, "..", "index.html");
// latin1: index.html tiene un byte NUL adentro y leerlo como utf8 lo rompe (CLAUDE.md).
const s = fs.readFileSync(HTML, "latin1");

const PROHIBIDAS = ["pgaEnviarAProgramar", "pppVencVolver", "pppVencSinProgramar"];
const fallas = [];

/* ⚠ Nada de regex con [^"']* : el onclick vive DENTRO de un string de JS, con las comillas
   escapadas (onclick="event.stopPropagation();fn(\'...). Un regex asi no matchea NUNCA y el test
   pasa siempre — falso verde. Se busca la subcadena tal cual aparece. */
const enOnclick = (fn) => {
  let n = 0, i = 0;
  const aguja = "stopPropagation();" + fn + "(";
  while ((i = s.indexOf(aguja, i)) >= 0) { n++; i += aguja.length; }
  return n;
};

for (const fn of PROHIBIDAS) {
  const n = enOnclick(fn);
  if (n) fallas.push("volvio la puerta a «A Programar»: " + n + " onclick llama a " + fn + "()");
}

// y los textos de boton que delataban la opcion
for (const txt of [" A Programar</button>", ">Sin programar</button>"]) {
  if (s.indexOf("'" + txt) >= 0 || s.indexOf('"' + txt) >= 0) fallas.push("volvio un boton con el texto " + JSON.stringify(txt));
}

// los dos caminos que SI tienen que estar (si se van, el pedido programado se queda sin salida)
for (const [fn, nombre] of [["pgaNpMoverAbrir", "Cambiar de dia (reprogramar)"],
                            ["pppVencCancelar", "Cancelar pedido (eliminar)"]]) {
  const n = enOnclick(fn);
  if (!n) fallas.push("no quedo ningun boton de " + nombre + ": el pedido programado se quedo sin salida");
  else console.log("ok   " + nombre + " sigue: " + n + " boton(es)");
}

for (const f of fallas) console.log("FALLA " + f);
if (fallas.length) { console.error("\nppp-sin-a-programar: " + fallas.length + " falla(s)."); process.exit(1); }
console.log("\nppp-sin-a-programar OK — desde Programacion solo se reprograma o se cancela.");
