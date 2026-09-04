/* Regresión (v12.80) — solapa "A Programar": armado manual de tandas.

   Carga el index.html REAL y dibuja las tres columnas con datos de mentira, así
   se cazan las referencias rotas y los `undefined`/`NaN` en pantalla antes que
   el supervisor.

   Lo que se protege, que es lo que se puede romper callado:
     · la tarjeta es un PEDIDO (no una NP) y avisa en cuántas NP va a salir —
       un pedido no se puede partir entre tandas;
     · el badge del código de tanda con la CANTIDAD de avisos (no bloquean,
       marcan);
     · una tanda que se llevó sólo algunos bloques de un pedido lo dice;
     · la lista de días muestra cuánto hay programado, marca el día COMPLETO y
       el no hábil, y ésos no aceptan que les suelten nada;
     · nada de esto se cae con un pedido sin razón social ni con m³ en 0.

   La lógica de negocio NO se prueba acá: vive en Supabase (§3.j del registro) y
   se probó contra datos reales. Esto es el dibujo. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    _apr.listo = true;
    _apr.emp = "lk";
    _apr.pedidos = [
      { order_id: 1117, cod: "R01", razon_social: "Riesgo Marcelo Fabian", zona: "Zona 3",
        fecha_recep: "2026-08-20", localidad: "Mataderos", direccion: "Bragado 5742 - Mataderos",
        m3: 0.367, m3_parcial: false, lineas: 52, cajas: 120, np_total: 3,
        bloques: [ { np_idx:1, m3:0.121, lineas:17, cajas:40, items:[{art:"027",cajas:8},{art:"046",cajas:4}] },
                   { np_idx:2, m3:0.121, lineas:17, cajas:40, items:[{art:"801",cajas:6}] },
                   { np_idx:3, m3:0.125, lineas:18, cajas:40, items:[] } ] },
      // borde: un pedido sin razón social, sin zona y en 0 m³ no puede romper el dibujo
      { order_id: 1200, cod: "", razon_social: "", zona: "", fecha_recep: "", localidad: "",
        direccion: "", m3: 0, m3_parcial: true, lineas: 0, cajas: 0, np_total: 1, bloques: [] }
    ];
    _apr.tandas = [
      { codigo:"GV-01A", empresa:"lk", m3:1.4, n_np:3, n_avisos:2,
        avisos:["Mezcla 2 zonas distintas: Zonas 2+3 · Zonas 6+7","Junta 2 clientes y suma 1.400 m³"] },
      { codigo:"GV-01B", empresa:"lk", m3:0, n_np:0, n_avisos:0, avisos:null }
    ];
    _apr.items = { "GV-01A": [
      { codigo:"GV-01A", order_id:1117, np_idx:1, razon_social:"Riesgo Marcelo Fabian", cod_cliente:"R01", zona:"Zona 3", m3:0.121, np_total:3 },
      { codigo:"GV-01A", order_id:1117, np_idx:2, razon_social:"Riesgo Marcelo Fabian", cod_cliente:"R01", zona:"Zona 3", m3:0.121, np_total:3 },
      { codigo:"GV-01A", order_id:9,    np_idx:1, razon_social:"Distri zona 6",         cod_cliente:"C6A", zona:"Zona 6", m3:0.9,   np_total:1 }
    ] };
    _apr.cal = [
      { dia:"2026-09-09", habil:true,  m3:0.5, tandas:1, np:2, cupo:5, resta:4.5, pasado:false },
      { dia:"2026-09-12", habil:false, m3:0,   tandas:0, np:0, cupo:5, resta:5,   pasado:false },
      { dia:"2026-09-10", habil:true,  m3:5.2, tandas:3, np:9, cupo:5, resta:0,   pasado:false }
    ];

    const izq = aprColPedidos(), med = aprColTandas(), der = aprColDias();
    _apr.exp["p1117"] = true;
    const izqAbierta = aprColPedidos();

    // Un ERROR no puede pintarse de verde como si todo hubiera salido bien.
    _apr.msg = "Numeración de NP APAGADA."; _apr.msgErr = true;
    aprRender();
    const conError = document.getElementById("pppPreview").innerHTML;
    _apr.msg = "✅ GV-01A programada."; _apr.msgErr = false;
    aprRender();
    const conOk = document.getElementById("pppPreview").innerHTML;
    _apr.msg = "";

    // ⚠ La app tiene un `button { width:100% }` GLOBAL. Sin pisarlo, el "↩" de
    //   sacar un pedido medía 293px y aplastaba el nombre del cliente a 107px:
    //   se leía "Messina Herma…" con 380px libres al lado. Se mide de verdad,
    //   porque en el HTML no se ve.
    aprRender();
    document.getElementById("pppOverlay").classList.add("show");
    const anchoDe = function (sel) {
      const e = document.querySelector(sel);
      return e ? Math.round(e.getBoundingClientRect().width) : -1;
    };
    const anchos = {
      titem: anchoDe(".apr-titem"),
      txt:   anchoDe(".apr-titem-txt"),
      x:     anchoDe(".apr-titem-x"),
      nueva: anchoDe(".apr-nueva"),
      altoNueva: (function () { const e = document.querySelector(".apr-nueva");
        return e ? Math.round(e.getBoundingClientRect().height) : -1; })()
    };

    return { izq, med, der, izqAbierta, conError, conOk, anchos };
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };
  const todo = r.izq + r.med + r.der + r.izqAbierta;

  chk(r.izq.includes("Riesgo Marcelo Fabian"), "la tarjeta muestra el cliente");
  chk(r.izq.includes("sale en 3 NP"),          "avisa en cuántas NP sale el pedido");
  chk(r.izq.includes("0,367 m³"),              "m³ con coma decimal");
  chk(r.izq.includes('draggable="true"'),      "la tarjeta se puede arrastrar");
  chk(r.izq.includes("#1200"),                 "un pedido sin razón social no rompe");
  chk(r.med.includes("GV-01A") && r.med.includes("GV-01B"), "las dos tandas abiertas");
  chk(r.med.includes('class="apr-badge"') && r.med.includes("⚠ 2"), "el badge con la cantidad de avisos");
  chk(r.med.includes("2/3 bloques"),           "marca el pedido que entró a medias");
  chk(r.med.includes("Riesgo Marcelo Fabian"),  "el nombre del cliente entra entero en la tanda");
  chk(r.med.includes("apr-titem-txt"),          "el item va en dos renglones (el nombre no compite con el detalle)");
  chk(r.med.includes("Arrastrá un pedido acá"),"la tanda vacía lo dice");
  chk(r.der.includes("Miércoles") && r.der.includes("9 sep"), "la lista dice el día con nombre y fecha");
  chk(r.der.includes("0,50</b> / 5,00 m³"),    "muestra los m³ programados contra el cupo");
  chk((r.der.match(/apr-dia-cerrado/g) || []).length === 2, "el no hábil y el completo quedan cerrados");
  chk(r.der.includes("apr-dia-lleno") && r.der.includes("completo"), "marca el día que llegó al límite");
  chk(r.der.includes("apr-dia-con"),           "marca el día que ya tiene tandas");
  chk(r.izqAbierta.includes("Bloque 1/3"),     "expandida muestra los bloques");
  chk(r.izqAbierta.includes("027"),            "expandida muestra los artículos");
  chk(!/undefined/.test(todo),                 "sin 'undefined' en pantalla");
  chk(!/NaN/.test(todo),                       "sin 'NaN' en pantalla");
  chk(!/on\w+="[^"]*undefined/.test(todo),     "sin handlers rotos");
  // Un día cerrado que igual acepte el drop es peor que no marcarlo: promete algo
  // que el backend después rechaza.
  // Sobre el TAG de apertura de cada día. Se ancla a que la clase EMPIECE con
  // "apr-dia" seguido de espacio o comilla: partir por 'apr-dia' a secas cortaba
  // también en apr-dia-fecha/apr-dia-cuerpo, y filtrar por nombre se comía los
  // cerrados (el "cerr" del filtro matcheaba "cerrado").
  const tags = r.der.match(/<div class="apr-dia[ "][^>]*>/g) || [];
  const cerrados = tags.filter(function (t) { return /apr-dia-cerrado/.test(t); });
  const abiertos = tags.filter(function (t) { return !/apr-dia-cerrado/.test(t); });
  chk(tags.length === 3, "se dibujan los 3 días (se contaron " + tags.length + ")");
  chk(cerrados.length === 2 && cerrados.every(function (t) { return t.indexOf("ondrop") < 0; }),
      "un día cerrado NO acepta que le suelten una tanda");
  chk(abiertos.length === 1 && abiertos.every(function (t) { return t.indexOf("aprDropDia") >= 0; }),
      "un día abierto sí la acepta");
  chk(r.der.includes("aprMasDias"),            "se pueden pedir más días");
  chk(!/◀|▶/.test(r.der),                      "no hay navegación hacia atrás: se programa para adelante");
  chk(/class="apr-err"[^>]*>[^<]*APAGADA/.test(r.conError), "un error se pinta de ROJO, no de verde");
  chk(/class="apr-msg"[^>]*>[^<]*programada/.test(r.conOk),  "un mensaje bueno se pinta de verde");
  const a = r.anchos;
  chk(a.x > 0 && a.x < 40, "el botón ↩ es chico (" + a.x + "px) — el button{width:100%} global no se le cuela");
  chk(a.txt > a.titem * 0.8, "el nombre del cliente se queda con el ancho (" + a.txt + " de " + a.titem + "px)");
  chk(a.altoNueva > 28, "el botón de nueva tanda conserva su padding (alto " + a.altoNueva + "px)");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-programar OK");
})();
