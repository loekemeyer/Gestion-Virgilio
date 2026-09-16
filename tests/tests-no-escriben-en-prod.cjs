/* Guard v18.72 — ningún test puede escribir en la base REAL.

   Los tests corren sobre `file://index.html` con la anon key adentro, y el contenedor tiene
   red hacia Supabase: si un test ejecuta `send()` (o cualquier cosa que postee) sin cortar la
   red, la corrida escribe en producción.

   No es teórico. La suite del 15/09 dejó dos filas en `GV_Tandas_Lock` con el legajo de prueba
   999 — C72F/picking y D11X/armado, de `ap-resume.cjs` — y con el lock sin TTL de la v18.65
   esas dos tandas quedaron BLOQUEADAS para los operarios de verdad hasta que se limpiaron a
   mano al día siguiente. Antes el TTL de 10 h las borraba solo y por eso nadie lo había visto:
   el bug estaba, pero se autolimpiaba.

   La regla: un test que llama a `send()`, `tandaReservar`, `stockMover` o similar tiene que
   cortar la red antes, con

       await p.route("**''/*.supabase.co/**", (r) => r.abort());

   o mockeando `window.fetch` dentro del evaluate. Cualquiera de las dos sirve; lo que no vale
   es dejar que salga.

   Sale 1 si aparece un test que dispara escrituras y no corta nada. */
const fs = require("fs");
const path = require("path");

const dir = __dirname;
/* Lo que puede escribir en la base si se lo deja suelto. `send()` es el principal: postea el
   evento Y reserva la tanda. */
const ESCRIBEN = /\b(await\s+send\(\)|\bsend\(\)\s*;|tandaReservar\(|tandaLiberar\(|tandaLockAnular\()/;
/* Formas válidas de cortar: interceptar con Playwright, o pisar fetch en el navegador. */
const CORTA = /p\.route\(|window\.fetch\s*=|globalThis\.fetch\s*=/;

const culpables = [];
for (const f of fs.readdirSync(dir)) {
  if (!f.endsWith(".cjs") || f === path.basename(__filename)) continue;
  const src = fs.readFileSync(path.join(dir, f), "utf8");
  if (!/playwright/.test(src)) continue;         // los estáticos no abren navegador
  if (!ESCRIBEN.test(src)) continue;
  if (CORTA.test(src)) continue;
  culpables.push(f);
}

if (culpables.length) {
  console.log("tests-no-escriben-en-prod: ✗ FAIL\n  Estos tests disparan escrituras y NO cortan " +
    "la red — van a escribir en la base REAL:\n    - " + culpables.join("\n    - ") +
    '\n  Agregá antes del evaluate:  await p.route("**/*.supabase.co/**", (r) => r.abort());');
  process.exit(1);
}
console.log("tests-no-escriben-en-prod: ningún test escribe en la base real · ✓ OK");
