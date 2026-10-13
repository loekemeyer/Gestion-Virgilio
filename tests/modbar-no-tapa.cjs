/* v29.81 (Luis, 13/10: «la barra de abajo con "Anular" y "Terminé" tapa opciones y botones (aparece
   arriba de algo que esté al fondo de la lista) … que no tape nada, priorizá la visión de smartphone»).

   Se corre la pantalla en un celular (390 x 740) con la tarea abierta y el módulo en pantalla, y se mide:
     a) la barra está pegada abajo y se ve;
     b) el overlay del módulo TERMINA arriba de la barra (bottom = alto de la barra), así su scroll llega
        hasta el final y el último renglón de la lista no queda tapado;
     c) con el scroll al fondo, el último elemento del módulo queda por encima de la barra;
     d) el body lleva el mismo colchón (la botonera de atrás no queda tapada);
     e) al cerrarse la barra, el overlay y el body vuelven como estaban (sin colchón pegado).
   Vale para los 4 módulos de MOD_TAREA (Mover racks, Completar Pedido, Pasar a urgente, Insumos).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 740 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const sl = (ms) => new Promise((res) => setTimeout(res, ms)); const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    legajoInput.value = "237"; goToOptions(); await sl(400);
    const box = (c) => document.querySelector('#optionsScreen [data-code="' + c + '"]');
    const OV = { MOV: "mvModal", CP: "cpModal", RC: "rcModal", INS: "insChooserModal" };
    const H = window.innerHeight;
    for (const c of ["MOV", "CP", "RC", "INS"]) {
      box(c).click(); await sl(120); send(); await sl(500);
      const bar = document.getElementById("modTareaBar"), ov = document.getElementById(OV[c]);
      const rb = bar.getBoundingClientRect(), ro = ov.getBoundingClientRect();
      out[c + "_barraAbajo"] = getComputedStyle(bar).display !== "none" && Math.abs(rb.bottom - H) < 2 && rb.height > 20;
      out[c + "_overlayTermina"] = Math.abs(ro.bottom - rb.top) < 2;   // el overlay llega justo hasta la barra
      const scrollea = /auto|scroll/.test(getComputedStyle(ov).overflowY);
      if (scrollea) {
        // lista LARGA + scroll al fondo: lo último tiene que quedar arriba de la barra
        const fin = document.createElement("div");
        fin.style.cssText = "height:900px;display:flex;align-items:flex-end;";
        fin.innerHTML = '<button style="width:100%;height:46px">último de la lista</button>';
        ov.appendChild(fin);
        ov.scrollTop = ov.scrollHeight; await sl(80);
        const ult = fin.querySelector("button").getBoundingClientRect();
        out[c + "_ultimoVisible"] = ult.height > 10 && ult.bottom <= rb.top + 1;
        ov.removeChild(fin);
      } else {
        /* overlay sin scroll (la tarjeta va centrada): la tarjeta ENTERA tiene que entrar arriba de la
           barra. Si algún día crece y no entra, este chequeo se pone rojo y hay que darle scroll. */
        const card = ov.firstElementChild.getBoundingClientRect();
        out[c + "_ultimoVisible"] = card.height > 10 && card.bottom <= rb.top + 1;
      }
      out[c + "_bodyColchon"] = parseFloat(getComputedStyle(document.body).paddingBottom || "0") >= rb.height - 1;
      modTareaBoton(c, false); await sl(700);
      out[c + "_vuelve"] = ov.style.bottom === "" && (document.body.style.paddingBottom || "") === "" &&
        getComputedStyle(document.getElementById("modTareaBar")).display === "none";
    }
    return out;
  });
  await b.close();
  const malos = Object.keys(r).filter((k) => !r[k]);
  const pass = !malos.length && !errs.length;
  console.log("modbar-no-tapa:", malos.length ? "fallan " + malos.join(", ") : Object.keys(r).length + " chequeos",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  process.exit(pass ? 0 : 1);
})();
