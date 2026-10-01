// v25.28 (Thomas, 30/09): un ajuste / fijar a mano sobre un código que NO existe pide confirmación.
// Caso 365ED (tipeado en vez de 865ED, −47 fantasma). Corre _stkCodExisteConfirmar de verdad con fetch y confirm mockeados.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
let fails = 0; const ok = (c, m) => { console.log((c ? "  ok  " : "  FALLA ") + m); if (!c) fails++; };
const i = src.indexOf("async function _stkCodExisteConfirmar(");
ok(i > 0, "existe _stkCodExisteConfirmar");
const fin = src.indexOf("\nasync function stockAjustar()", i);
const fnSrc = src.slice(i, fin);
const aj = src.slice(fin, src.indexOf("\nasync function stockFijar()", fin));
const fj = src.slice(src.indexOf("\nasync function stockFijar()"), src.indexOf("\nasync function stockFijar()") + 4000);
ok(/_stkCodExisteConfirmar\(cod,/.test(aj) && aj.indexOf("_stkCodExisteConfirmar") < aj.indexOf("stkInsertMov"), "stockAjustar pregunta ANTES de grabar");
ok(/_stkCodExisteConfirmar\(cod,/.test(fj), "stockFijar pregunta");
(async () => {
  const mk = (resp) => new Function("SUPABASE_URL", "SUPABASE_KEY", "fetch", "confirm",
    fnSrc + "\nreturn _stkCodExisteConfirmar;")("https://x", "k", resp, (m) => { mk.last = m; return mk.ans; });
  let f = mk(async () => ({ ok: true, json: async () => true })); mk.last = null;
  ok(await f("865ED", "pongo -47") === true && mk.last === null, "código que existe: graba sin preguntar");
  f = mk(async () => ({ ok: true, json: async () => false })); mk.ans = false;
  ok(await f("999FT", "pongo -40") === false && /No existe el c.digo 999FT[\s\S]*Lo creo y le pongo -40\?/.test(mk.last), "no existe + cancela: no graba, y el cartel dice «¿Lo creo y le pongo -40?»");
  mk.ans = true;
  ok(await f("999FT", "pongo -40") === true, "no existe + confirma: graba");
  f = mk(async () => { throw new Error("red"); }); mk.ans = false;
  ok(await f("501", "pongo +1") === false && /No pude verificar/.test(mk.last), "sin respuesta: pregunta (no asume que existe)");
  console.log(fails ? "\n" + fails + " falla(s)" : "\nOK");
  process.exit(fails ? 1 : 0);
})();
