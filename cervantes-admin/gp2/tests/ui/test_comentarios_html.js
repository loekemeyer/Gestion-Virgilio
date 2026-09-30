/* Guardia de COMENTARIOS HTML. No abre navegador: lee el repo.
 *
 * Existe por un bug real que paso DOS veces el 2026-09-18 en la misma pantalla: un changelog
 * de la Tablet traia adentro de su texto el cierre de comentario (guion guion mayor) porque
 * estaba citando el pedido del usuario. Para el navegador eso CIERRA el comentario ahi, y todo
 * lo que seguia hasta el cierre real se pinto como texto arriba de los modulos, en la pantalla
 * que usan los operarios. El fix de la primera vez volvio a escribirlo literal para explicarlo
 * y el cartel reaparecio.
 *
 * La regla que vigila: en estos HTML el cierre de comentario se NOMBRA, no se escribe. Se
 * detecta buscando un cierre que quede FUERA de un comentario: si el texto de un comentario
 * lo contiene, el cierre verdadero del bloque termina afuera y aca salta.
 *
 * Los _backup_* quedan afuera: son fotos congeladas.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
let fallos = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) fallos++; };

function htmls(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) htmls(p, acc);
    else if (e.name.endsWith('.html') && !e.name.startsWith('_backup_')) acc.push(p);
  }
  return acc;
}

/* Recorre el archivo como lo hace el navegador: <!-- abre, el PRIMER --> cierra. Devuelve la
   linea de cada cierre que aparece cuando no hay comentario abierto (o sea, de mas). */
function cierresHuerfanos(txt) {
  const fuera = [];
  let i = 0, dentro = false;
  while (i < txt.length) {
    if (!dentro) {
      const a = txt.indexOf('<!--', i);
      const c = txt.indexOf('-->', i);
      if (c !== -1 && (a === -1 || c < a)) { fuera.push(txt.slice(0, c).split('\n').length); i = c + 3; continue; }
      if (a === -1) break;
      dentro = true; i = a + 4;
    } else {
      const c = txt.indexOf('-->', i);
      if (c === -1) break;              // comentario sin cerrar: lo agarra el navegador, no este test
      dentro = false; i = c + 3;
    }
  }
  return fuera;
}

const malos = [];
for (const f of htmls(ROOT)) {
  const huerfanos = cierresHuerfanos(fs.readFileSync(f, 'utf8'));
  if (huerfanos.length) malos.push(path.relative(ROOT, f) + ' (lineas ' + huerfanos.join(', ') + ')');
}
ok(malos.length === 0,
   'ningun HTML tiene un cierre de comentario suelto (el texto de un comentario no lo escribe)' +
   (malos.length ? ' — ' + malos.join(' | ') : ''));

console.log(fallos ? 'HAY FALLOS' : 'TODO OK');
process.exitCode = fallos ? 1 : 0;
