/* Regresion v30.05 (Luis, 13/10/2026) — "hay que darles la opcion de poder crear codigos
   nuevos cuando reciben si no estan en la lista (antes tenian un boton abajo que les
   permitia hacer eso no, poneselos)".

   El boton VUELVE (la v29.56 lo habia sacado), pero con la leccion del dia puesta: el 13/10
   el legajo 104 recibio 144 Kg de un fleje "13.6 x 0.8" y ese fleje YA existia como `N°19`
   ("13,6 x 0,8 · Fleje N° 19"), asi que se creo un TMP y los Kg quedaron en un codigo que no
   existe para nadie. Antes de crear, el alta busca los parecidos por los NUMEROS del detalle
   —sin importar coma/punto— y los ofrece.

   Mide:
     (a) el detalle que repite una medida que ya existe AVISA con el candidato, y cancelando
         NO crea nada y deja la lista filtrada
     (b) "crear igual" (el confirm en si) SI crea: el aviso no bloquea
     (c) un detalle de algo que de verdad no esta (6 x 2,75) no avisa y crea derecho
   Sin red (fetch mockeado). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const creados = [];
    const J = function (data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } }); };
    const CAT = [
      { cod: "N°19", nombre: "13,6 x 0,8 · Fleje N° 19", sector: null, categoria: "fleje", ubicacion: "R6At" },
      { cod: "N°13", nombre: "84 x 1,75 · Fleje N° 13", sector: null, categoria: "fleje", ubicacion: "R1Ad" }
    ];
    window.fetch = function (url, opt) {
      url = String(url);
      if (url.indexOf("/rpc/nuevo_insumo_tmp") >= 0) {
        try { creados.push(JSON.parse(opt.body)); } catch (_e) {}
        return J("TMP-0099");
      }
      if (url.indexOf("Insumos_Categorias") >= 0) return J([{ clave: "fleje", nombre: "Flejes y alambres", emoji: "🧵", unidades: ["Kg"], orden: 1 }]);
      if (url.indexOf("Insumos_Unidades") >= 0) return J([{ nombre: "Kg", orden: 1 }]);
      if (url.indexOf("vista_insumos") >= 0 || url.indexOf("/Insumos") >= 0) return J(CAT);
      return J([]);
    };

    const alta = async function (det, decir) {
      await showInsumoModal("RI", "104");
      insSetCat("fleje");
      insNuevoOpen("fleje");
      // los campos de texto se leen del DOM al confirmar (_insNuevoLeerCampos), no del objeto
      document.getElementById("insNvDet").value = det;
      document.getElementById("insNvQty").value = "10";
      _ins.nuevo.uni = "Kg";
      let visto = "";
      const _cf = window.confirm, _al = window.alert;
      window.confirm = function (m) { visto = String(m); return decir; };
      window.alert = function () {};
      insNuevoOk();
      await new Promise(function (r2) { setTimeout(r2, 40); });
      window.confirm = _cf; window.alert = _al;
      return visto;
    };

    // (a) la medida que ya existe: avisa con el candidato y, al cancelar, no crea nada
    const n0 = creados.length;
    const avisoA = await alta("13.6 x 0.8", false);
    out.avisa = /ya exista/i.test(avisoA) && /N°19/.test(avisoA);
    out.noCreo = creados.length === n0;
    out.dejaFiltro = String(_ins && _ins.filtro) === "13.6";
    out.cerroElAlta = !(_ins && _ins.nuevo);

    // (b) el mismo caso diciendo "crear igual": el aviso NO bloquea
    const avisoB = await alta("13.6 x 0.8", true);
    out.avisaDeNuevo = /ya exista/i.test(avisoB);
    out.creoIgual = creados.length === n0 + 1;

    // (c) algo que de verdad no esta: ni aviso ni freno
    const avisoC = await alta("6 x 2,75", false);
    out.sinAvisoSiNoEsta = avisoC === "";
    out.creoElNuevo = creados.length === n0 + 2;
    out.detGuardado = (creados[creados.length - 1] || {}).p_detalle;
    return out;
  });

  const malas = Object.keys(r).filter((k) => r[k] !== true && k !== "detGuardado");
  const pass = malas.length === 0 && r.detGuardado === "6 x 2,75" && errs.length === 0;
  console.log(pass ? "OK ins-alta-duplicado" : "FALLA ins-alta-duplicado");
  if (!pass) { console.log(JSON.stringify(r, null, 2)); if (errs.length) console.log("pageerror:", errs.join(" | ")); }
  await b.close(); process.exit(pass ? 0 : 1);
})();
