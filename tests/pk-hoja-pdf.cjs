// v29.65 (Luis, 13/10) — la hoja de PICKING tal como sale por el HELPER: el PDF se arma con
// html2canvas, que NO parsea calc() dentro de un linear-gradient y pinta el gradiente SÓLIDO.
// Con eso, la diagonal del parcial salía como un CUADRADO NEGRO encima del total de cajas y la
// fila sin pickear salía toda gris, ilegible. Este test RENDERIZA con html2canvas de verdad y
// mide la tinta de esas celdas: un candado de texto no se entera del próximo gradiente raro.
const fs = require("fs"), path = require("path");
const { chromium } = require("playwright");
const root = path.join(__dirname, "..");
const s = fs.readFileSync(root + "/index.html", "utf8");
const grab = n => { const i = s.indexOf("function " + n + "("); if (i < 0) throw new Error("falta " + n); let d = 0; for (let k = s.indexOf("{", i); ; k++) { if (s[k] == "{") d++; if (s[k] == "}" && !--d) return s.slice(i, k + 1); } };
global.TZ_AR = "America/Argentina/Buenos_Aires"; global.escapeHtml = x => String(x);
eval(["_padCod", "_pkHojaDia", "_pkHojaHm", "_pkHojaDm", "_pkHojaNum", "_pkHojaMinOtras", "pkHojaArmar", "pkHojaHtml"].map(grab).join("\n"));
const i0 = s.indexOf("var REMITO_SHEET_CSS ="), j0 = s.indexOf("var _remitoInner");
eval(s.slice(i0, j0));   // REMITO_SHEET_CSS + REMITO_PRINT_CSS, los mismos que usa el PDF

let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log("✗", m); } else console.log("✓", m); };
const tp = { legajo: "94", ts_inicio: "2026-10-01T08:00:00-03:00", ts_cliente: "2026-10-01T10:00:00-03:00" };
const pkc = ["E70F|505|5|5|0|LK", "E70F|501|4|2|0|LK", "E70F|809E LK|1|0|0|LK", "E70F|066|1|1|0|LK"].map(texto => ({ texto }));
const lug = [{ cod: "505", empresa: "LK", sector: "D01", orden: 298 }, { cod: "501", empresa: "LK", sector: "A11", orden: 21 }, { cod: "809E", empresa: "LK", sector: "J13", orden: 354 }, { cod: "66", empresa: "LK", sector: "A05", orden: 5 }];
const d = pkHojaArmar("E70F", tp, pkc, lug, [{ np: "LK 0001", rs: "Torres", m3: 0.5, fecha: "2026-10-05" }], [], "Juan Farias");
const html = '<!doctype html><html><head><meta charset="utf-8"><style>' + REMITO_PRINT_CSS + 'html,body{background:#fff;}</style>' +
  '<script src="' + root + '/vendor/html2canvas.min.js"></script></head><body><div class="rmt-sheet" id="rmtFit" style="font-size:15px">' + pkHojaHtml(d) + '</div></body></html>';

(async () => {
  const tmp = path.join(require("os").tmpdir(), "pk-hoja-pdf-" + process.pid + ".html");
  fs.writeFileSync(tmp, html);
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 760, height: 1200 } });
  const errs = []; p.on("pageerror", e => errs.push(String(e)));
  await p.goto("file://" + tmp);
  await p.waitForFunction("window.html2canvas", null, { timeout: 15000 });
  const r = await p.evaluate(async () => {
    const el = document.getElementById("rmtFit");
    const canvas = await window.html2canvas(el, { scale: 3, backgroundColor: "#ffffff", logging: false, windowWidth: 703, windowHeight: el.scrollHeight + 8 });
    const base = el.getBoundingClientRect(), sc = canvas.width / base.width, cx = canvas.getContext("2d");
    const tinta = function (node) {
      const rr = node.getBoundingClientRect();
      const x = Math.round((rr.left - base.left) * sc), y = Math.round((rr.top - base.top) * sc);
      const w = Math.max(1, Math.round(rr.width * sc)), h = Math.max(1, Math.round(rr.height * sc));
      const dat = cx.getImageData(x, y, w, h).data; let osc = 0;
      for (let i = 0; i < dat.length; i += 4) if (dat[i] + dat[i + 1] + dat[i + 2] < 380) osc++;
      return Math.round(osc / (w * h) * 100);
    };
    return { parcial: tinta(document.querySelector(".pkh-diag").closest("td")),
             fila: tinta(document.querySelector(".pkh-no")),
             celdaNo: tinta(document.querySelector(".pkh-no td:last-child")),
             tilde: tinta(document.querySelector(".pkh-ok")) };
  });
  await b.close(); try { fs.unlinkSync(tmp); } catch (_e) {}
  ok(!errs.length, "la hoja se dibuja sin errores de JS" + (errs.length ? " — " + errs[0] : ""));
  // Un gradiente mal parseado pinta el rectángulo ENTERO. Medido el 13/10 con html2canvas, misma
  // hoja: con el gradiente la celda del parcial da 17 % de tinta y la fila sin pickear 25 % (el
  // número tapado por un cuadrado negro, la fila gris); con la barra sólida, 6 % y 10 %.
  ok(r.parcial > 2 && r.parcial < 12, "parcial: el total va tachado con una línea y se lee (tinta " + r.parcial + "%, el bug daba 17)");
  ok(r.fila > 2 && r.fila < 16, "sin pickear: la fila va tachada, no pintada entera (tinta " + r.fila + "%, el bug daba 25)");
  ok(r.celdaNo < 14, "sin pickear: el total de esa fila se sigue leyendo (tinta " + r.celdaNo + "%, el bug daba 26)");
  ok(r.tilde > 1, "pickeado todo: el tilde se dibuja (tinta " + r.tilde + "%)");
  // Y el candado estático, para que no vuelva por otro lado.
  const css = pkHojaHtml(d).slice(0, pkHojaHtml(d).indexOf("</style>"));
  ok(!/linear-gradient\([^)]*calc\(/.test(css), "el CSS de la hoja no usa linear-gradient con calc() (html2canvas no lo parsea)");
  process.exit(bad ? 1 : 0);
})().catch(e => { console.log("✗", e.message); process.exit(1); });
