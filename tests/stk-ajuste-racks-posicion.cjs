// v29.05 (Luis, 09/10): Stock → Ajustar / Fijar / Stock inicial en RACKS exigen la POSICIÓN.
// Caso 606 (09/10): el −10 de la corrección quedó «bajado de racks sin decir de qué posición».
// Corre _stkRackPosElegir de verdad con fetch / prompt / confirm mockeados, y candados sobre los tres llamadores.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "utf8");
let fails = 0; const ok = (c, m) => { console.log((c ? "  ok  " : "  FALLA ") + m); if (!c) fails++; };
const i = src.indexOf("function _stkEsRacks(");
ok(i > 0, "existe _stkEsRacks");
const fin = src.indexOf("\nasync function stockAjustar()", i);
const fnSrc = src.slice(i, fin);
const cuerpo = (n) => { const a = src.indexOf("\nasync function " + n + "("); return src.slice(a, src.indexOf("\n}\n", a)); };
const aj = cuerpo("stockAjustar"), fj = cuerpo("stockFijar"), ini = cuerpo("stockGuardarInicial");
ok(/_stkEsRacks\(dep\)[\s\S]*_stkRackPosElegir\(cod, "stkAjPos", cant\)[\s\S]*row\.ubicacion = rp\.ubic/.test(aj) && aj.indexOf("_stkRackPosElegir") < aj.indexOf("stkInsertMov"), "Ajustar: en racks pide la posición antes de grabar y la manda en ubicacion");
ok(/_stkRackPosElegir\(cod, "stkAjPos2", null\)[\s\S]*actual = rp\.saldo[\s\S]*_fRow\.ubicacion = rackUbic/.test(fj), "Fijar: en racks fija la posición (saldo de esa posición) y manda ubicacion");
ok(/_stkEsRacks\(dep\)[\s\S]*Sin posición[\s\S]*_stkRackSectorDe\(r\._pos\)[\s\S]*r\.ubicacion = s/.test(ini), "Stock inicial: en racks cada línea lleva posición validada");
ok(/id="stkAjPos"/.test(src) && /id="stkAjPos2"/.test(src), "inputs de posición en la pantalla");
(async () => {
  const st = { pos: [], sector: "X22", prompt: null, confirm: true, alerts: [], confirms: [], sectorFalla: false };
  const fetchMock = async (url) => {
    if (/gv_rack_sector/.test(url)) { if (st.sectorFalla) throw new Error("red"); return { ok: true, json: async () => st.sector }; }
    if (/Racks_Planimetria/.test(url)) return { ok: true, json: async () => st.pos };
    throw new Error("url " + url);
  };
  const docMock = { getElementById: () => ({ value: st.inp || "" }) };
  const f = new Function("SUPABASE_URL", "SUPABASE_KEY", "fetch", "prompt", "confirm", "alert", "document",
    fnSrc + "\nreturn _stkRackPosElegir;")("https://x", "k", fetchMock, () => st.prompt,
      (m) => { st.confirms.push(m); return st.confirm; }, (m) => st.alerts.push(m), docMock);
  st.pos = [{ sector: "X22", innercajas: 10, emp: "LK", fuente: "stock" }, { sector: "Y04", innercajas: 5, emp: "LK", fuente: "a_contar" }];
  st.prompt = "x22";
  let r = await f("606", "stkAjPos", -10);
  ok(r && r.ubic === "X22" && r.saldo === 10 && !st.confirms.length, "resta lo que hay: graba en X22 sin preguntar");
  st.prompt = null;
  r = await f("606", "stkAjPos", -10);
  ok(r === null, "sin posición (canceló el prompt): no graba");
  st.prompt = "Z99"; st.sector = null;
  r = await f("606", "stkAjPos", -10);
  ok(r === null && /no es una posici.n de rack/.test(st.alerts.pop()), "posición que no está en el Mapa: no graba");
  st.sector = "Y04"; st.prompt = "Y04"; st.confirm = false;
  r = await f("606", "stkAjPos", -3);
  ok(r === null && /quedar.a en negativo/.test(st.confirms.pop()), "resta en una posición sin esas cajas: avisa y, si cancela, no graba (la fila «a contar» no cuenta)");
  st.confirm = true; r = await f("606", "stkAjPos", -3);
  ok(r && r.ubic === "Y04", "…y si confirma, graba");
  st.sector = "X22"; st.inp = "X22"; st.prompt = "NO DEBE PREGUNTAR";
  r = await f("606", "stkAjPos", 4);
  ok(r && r.ubic === "X22", "con la posición tipeada en la pantalla no pregunta");
  st.sectorFalla = true; r = await f("606", "stkAjPos", 4);
  ok(r === null && /No pude verificar/.test(st.alerts.pop()), "sin respuesta del Mapa: no graba");
  console.log(fails ? "\n" + fails + " falla(s)" : "\nOK");
  process.exit(fails ? 1 : 0);
})();
