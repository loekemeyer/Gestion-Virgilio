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

  const r = await p.evaluate(async () => {
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
      { codigo:"GV-01B", empresa:"lk", m3:0, n_np:0, n_avisos:0, avisos:null },
      // v13.58: LK y Chef juntos — una tanda de Chef con un pedido de Chef (order_id 9 también existe en LK)
      { codigo:"GV-02A", empresa:"chef", m3:0.3, n_np:1, n_avisos:0, avisos:null }
    ];
    _apr.items = { "GV-01A": [
      { codigo:"GV-01A", order_id:1117, np_idx:1, razon_social:"Riesgo Marcelo Fabian", cod_cliente:"R01", zona:"Zona 3", m3:0.121, np_total:3 },
      { codigo:"GV-01A", order_id:1117, np_idx:2, razon_social:"Riesgo Marcelo Fabian", cod_cliente:"R01", zona:"Zona 3", m3:0.121, np_total:3 },
      { codigo:"GV-01A", order_id:9,    np_idx:1, razon_social:"Distri zona 6",         cod_cliente:"C6A", zona:"Zona 6", m3:0.9,   np_total:1 }
    ], "GV-02A": [
      { codigo:"GV-02A", empresa:"chef", order_id:9, np_idx:1, razon_social:"Chen Li Yu", cod_cliente:"310", zona:"Zona 2", m3:0.3, np_total:1 }
    ] };
    _apr.cal = [
      { dia:"2026-09-09", habil:true,  m3:0.5, tandas:1, np:2, cupo:5, resta:4.5, pasado:false, m3_isis:13.451, tandas_isis:7, np_isis:11 },   // v13.18: ISIS ya tiene 13,45 m³ ese día; no cierra el cupo web
      { dia:"2026-09-12", habil:false, m3:0,   tandas:0, np:0, cupo:5, resta:5,   pasado:false },
      { dia:"2026-09-13", habil:false, m3:0,   tandas:0, np:0, cupo:5, resta:5,   pasado:false },   // v13.24: sáb + dom seguidos → una sola fila
      { dia:"2026-09-10", habil:true,  m3:5.2, tandas:3, np:9, cupo:5, resta:0,   pasado:false },
      // v13.22: antes de la anticipación mínima → "Muy pronto", cerrado aunque tenga cupo
      { dia:"2026-09-08", habil:true,  m3:0,   tandas:0, np:0, cupo:5, resta:5,   pasado:false, muy_pronto:true, dia_minimo:"2026-09-11" }
    ];

    // v13.21: qué día sale (viene del backend, gv_ppp_web_dia_salida); el 1200 todavía no tiene respuesta
    _apr.salida = { 1117: { dia: "2026-09-08", motivo: "camion", detalle: "Ya hay camión a la zona 3: D60A" } };
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

    // v13.58: un pedido de LK no entra en una tanda de Chef (sin llamar a la RPC)
    let rpcLlamada = false;
    const fetchOrig = window.fetch;
    window.fetch = function (u) { if (String(u).indexOf("/rpc/") >= 0) rpcLlamada = true; return fetchOrig.apply(this, arguments); };
    _apr.pedidos[0].empresa = "lk";
    await aprSoltarPedido("GV-02A", _apr.pedidos[0]);
    window.fetch = fetchOrig;
    const mezcla = { msg: _apr.msg, err: _apr.msgErr, rpcLlamada: rpcLlamada };
    _apr.msg = ""; _apr.msgErr = false;

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
    };

    return { izq, med, der, izqAbierta, conError, conOk, anchos, mezcla, barra: document.querySelector(".apr-bar").innerHTML };
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
  chk(r.med.includes("Arrastrá un pedido acá"),"la tanda vacía (vieja) lo dice");
  chk(r.der.includes("Miércoles") && /9<small>sep<\/small>/.test(r.der), "la lista dice el día con nombre y fecha (v13.54: número grande + mes chico)");
  chk(r.der.includes("0,50</b> / 5,00 m³"),    "muestra los m³ programados contra el cupo");
  chk((r.der.match(/apr-dia-cerrado/g) || []).length === 3, "el no hábil, el completo y el muy pronto quedan cerrados");
  chk(/apr-dia-pronto/.test(r.der) && /Muy pronto · desde el 11\/09/.test(r.der), "v13.22: el día antes de la anticipación mínima dice 'Muy pronto · desde el 11/09'");
  // v13.24: sáb 12 + dom 13 no hábiles seguidos → una sola fila "Sábado a Domingo · 12 – 13 sep · No hábil · 2 días"
  chk(/apr-dia-nohabil-run/.test(r.der) && /Sábado a Domingo/.test(r.der) && /12 – 13 sep/.test(r.der) && /No hábil · 2 días/.test(r.der), "v13.24: dos no hábiles seguidos en una fila");
  chk((r.der.match(/apr-dia-nohabil/g) || []).length === 2, "v13.24: una sola fila no hábil (clase + run)");
  chk(r.der.includes("apr-dia-lleno") && r.der.includes("completo"), "marca el día que llegó al límite");
  chk(r.der.includes("apr-dia-con"),           "marca el día que ya tiene tandas");
  // v13.18: lo de ISIS se muestra aparte y no cierra el día (el cupo sigue siendo web)
  // v13.64 (dueño: "ISIS o web no me interesa para nada"): un solo renglón "tandas · NP", sin "ISIS" ni "web"
  chk(!/ISIS|m³ web/.test(r.der), "v13.64: el día no distingue ISIS de web");
  chk(/apr-dia-sub"><span><b>1<\/b> tanda\(s\) · <b>2<\/b> NP/.test(r.der), "v13.64: renglón 'tanda(s) · NP' del día");
  // v13.21: el chip dice qué día sale, no cuándo llegó (eso queda en el title)
  // v13.47 (dueño: "mandá directo a Programación si ya está"): zona manual con camión → la programa el automático
  chk(/apr-chip-sal" title="Llegó el 2026-08-20\. Ya hay camión a la zona 3: D60A Lo programa el automático[^"]*">🚚 va al camión del mar 8\/9 · en minutos</.test(r.izq), "v13.47: chip .va al camión del mar 8/9 · en minutos. con el motivo en el title");
  chk(!/programalo/.test(r.izq), "v13.47: el chip ya no pide 'programalo'");
  chk(/apr-porque">Ninguno tiene tanda todavía · <b>1<\/b> los programa solo el automático en minutos</.test(r.izq), "v13.47: la línea dice que el automático lo programa");
  chk(!/<span class="apr-chip">2026-08-20<\/span>/.test(r.izq), "v13.21: la fecha de recepción ya no es un chip");
  chk(/apr-chip-sal esp"[^>]*>🚚 …</.test(r.izq), "v13.21: sin respuesta todavía → '🚚 …'");
  chk(r.izqAbierta.includes("bloque 1/3"),     "expandida muestra los bloques (v12.92: \"LK 1201 · bloque 1/3\")");
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
  chk(tags.length === 4, "se dibujan los 4 días (se contaron " + tags.length + ")");
  chk(cerrados.length === 3 && cerrados.every(function (t) { return t.indexOf("ondrop") < 0; }),
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
  // v13.58 (dueño: "sacá el botón Loeke/Chef; tienen que aparecer todos los pedidos a programar ahí sin filtros")
  chk(!/Loekemeyer|aprSetEmpresa/.test(r.barra), "v13.58: la barra ya no tiene el selector Loekemeyer/Chef");
  chk(/apr-tanda-emp lk">LK</.test(r.med) && /apr-tanda-emp ch">Chef</.test(r.med), "v13.58: cada tanda dice de qué empresa es");
  chk(r.med.includes("web CH 9") && r.med.includes("GV-02A"), "v13.58/v13.70: la tanda de Chef muestra el pedido de la página (web CH 9)");
  chk(!/aprNuevaTanda/.test(r.med) && /Tandas sin fecha/.test(r.med), "v13.69: sin botones de tanda LK/Chef; la columna lista sólo tandas viejas sin fecha");
  chk(/aprDragPedido\(event,'lk:1117'\)/.test(r.izq), "v13.65: el arrastre lleva empresa:pedido (LK 1350 ≠ Chef 1350)");
  chk(/Arrastrá el pedido directo al día/.test(r.der), "v13.69: la ayuda dice arrastrar el pedido directo al día");
  chk(r.mezcla.err === true && /tanda de Chef/.test(r.mezcla.msg) && /LK 1117/.test(r.mezcla.msg) && r.mezcla.rpcLlamada === false,
      "v13.58: un pedido de LK soltado en una tanda de Chef avisa y no llama a la RPC");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-programar OK");
})();
