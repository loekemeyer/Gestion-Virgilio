// v25.51 (Luis) — HOJA DE PICKING por tanda (modelo planilla «Limpio»): orden del recorrido,
// Pickeo ✓ / número, NP con m³, m³/hora neto (descuenta otras tareas del legajo en la ventana),
// y sale sola por la estación (TP) y por la Cola de impresión.
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "utf8");
const grab = n => { const i = s.indexOf("function " + n + "("); if (i < 0) throw new Error("falta " + n); let d = 0; for (let k = s.indexOf("{", i); ; k++) { if (s[k] == "{") d++; if (s[k] == "}" && !--d) return s.slice(i, k + 1); } };
global.TZ_AR = "America/Argentina/Buenos_Aires"; global.escapeHtml = x => String(x);
eval(["_pkHojaDia", "_pkHojaHm", "_pkHojaDm", "_pkHojaNum", "_pkHojaMinOtras", "pkHojaArmar", "pkHojaHtml"].map(grab).join("\n") + ";global.A=pkHojaArmar;global.H=pkHojaHtml;");
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log("✗", m); } else console.log("✓", m); };
const tp = { legajo: "94", ts_inicio: "2026-10-01T08:00:00-03:00", ts_cliente: "2026-10-01T10:00:00-03:00" };
const pkc = ["E70F|505|5|5|0|LK", "E70F|501|4|2|0|LK", "E70F|809E LK|1|0|0|LK", "E70F|066|1|1|0|LK"].map(texto => ({ texto }));
const lug = [{ cod: "505", empresa: "LK", sector: "D18", orden: 281 }, { cod: "505", empresa: "LK", sector: "D01", orden: 298 }, { cod: "501", empresa: "LK", sector: "A11", orden: 21 }, { cod: "809E", empresa: "CH", sector: "M13", orden: 458 }, { cod: "809E", empresa: "LK", sector: "J13", orden: 354 }, { cod: "66", empresa: "LK", sector: "A05", orden: 5 }];
const nps = [{ np: "LK 0002", rs: "OSA", m3: 0.5, fecha: "2026-10-05" }, { np: "LK 0001", rs: "Torres", m3: 0.5, fecha: "2026-10-05" }];
const otras = [{ opcion: "Baño", ts_inicio: "2026-10-01T08:30:00-03:00", ts_cliente: "2026-10-01T08:45:00-03:00" }, { opcion: "RKB", ts_inicio: "2026-10-01T08:40:00-03:00", ts_cliente: "2026-10-01T09:00:00-03:00" }, { opcion: "TP", ts_inicio: tp.ts_inicio, ts_cliente: tp.ts_cliente }];
const d = A("E70F", tp, pkc, lug, nps, otras, "Juan Farias");
ok(d.lineas.map(x => x.cod).join() === "066,501,505,809E", "orden del recorrido y el código pelado (809E, no «809E LK»; su góndola J13, no M13)");
ok(d.lineas[3].lug.sector === "J13", "dual con su empresa");
ok(d.lineas[2].lug.sector === "D01" && d.lineas[0].lug.sector === "A05", "sector = el primero del código (D01, no D18) y el 066 encuentra su celda «66»");
ok(!/Orden/.test(H(d)) && !/background/.test(H(d)), "sin columna Orden, blanco y negro");
ok(d.minOtras === 30 && d.minNeto === 120, "muestra otras tareas (30 min, sin contar dos veces lo que se pisa) y NO las descuenta");
ok(Math.abs(d.m3h - 0.5) < 1e-9, "m³/hora = m³ ÷ horas del picking (sin descontar)");
const h = H(d);
ok(/Tanda E70F \(Sale Lun 5\/10\)/.test(h) && /Leg 94 Juan Farias/.test(h), "cabecera como la planilla");
ok(/08:00 a 10:00 hs \(30 min en otras tareas\)/.test(h), "horario con descuento");
ok(/<td>4<\/td><td>2<\/td>/.test(h) && /<td>5<\/td><td>✓<\/td>/.test(h), "Pickeo: ✓ si salió todo, si no el número");
ok(h.indexOf("LK 0001") < h.indexOf("LK 0002") && /Total m³ 1,00/.test(h) && /0,50 m³\/hora/.test(h), "NP, total m³ y m³/hora");
ok(s.indexOf("await pkHojaImprimir(nuevas)") > 0 && s.indexOf("pkHojaPendientes()") > 0, "sale sola por la estación (TP) y por la Cola de impresión");
process.exit(bad ? 1 : 0);
