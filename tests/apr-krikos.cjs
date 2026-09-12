/* Regresión v15.85 / v15.90 — las OC de súper de Krikos en "A Programar".

   Pedido del dueño (2026-09-11): *"yo quiero que se vea acá"* — en A Programar, no sólo en
   la Bandeja del panel de LK.

   ⚠ Una OC de Krikos NO es un pedido: no tiene NP, ni artículos cargados en Gestión, ni m³.
   Entra como AVISO separado, NO como tarjeta tildable — si entrara a la lista de pedidos se
   podría meter en una tanda sin saber qué lleva, y además mezclaría súper con clientes,
   que es justo lo que el dueño prohibió.

   Cubre:
   - sin OC pendientes el bloque NO se dibuja (no ensucia la pantalla);
   - con OC se listan todas, con cadena / nº / sucursal / fecha de entrega;
   - la cadena se acorta ("INC S.A. (CARREFOUR)" → "Carrefour", "LA ANONIMA (SAIEP)" → "La Anónima");
   - una OC con fecha de entrega ya pasada se marca como vencida;
   - una OC sin PDF se marca;
   - el bloque NO genera tarjetas de pedido ni checkboxes (no es tildable);
   - el 🔄 de la pantalla vuelve a pedir las OC;
   - v15.90 (importador automático): una OC que ENTRÓ pero con algo que no dio sale en un
     bloque ROJO aparte, con el pedido que se creó y el motivo escrito grande; una que no
     pudo entrar muestra su motivo; y el pie ya no dice que el importador no existe.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const box = (html) => { const d = document.createElement("div"); d.innerHTML = html; return d; };
    const hoy = getTodayKey();
    const dia = (n) => { const d = new Date(Date.now() + n * 864e5); return d.toISOString().slice(0, 10); };

    // ---- 1) sin OC: no se dibuja nada ----
    _apr.krikos = [];
    out.vacioNoDibuja = aprKrikosHtml() === "";

    // ---- 2) con OC: se listan todas ----
    _apr.krikos = [
      { inbox_id: 21, cadena: "LA ANONIMA (SAIEP)", sucursal: "959 Depósito MCR II",
        nro_documento: "22908256", fecha_entrega: "27/07/2026", fecha_entrega_d: dia(-30),
        link: "https://krikos360.planexware.net/x", tiene_pdf: true },
      { inbox_id: 20, cadena: "INC S.A. (CARREFOUR)", sucursal: "CD TT Tortuguitas XD",
        nro_documento: "0958095800240533", fecha_entrega: "28/07/2026 14:00", fecha_entrega_d: dia(5),
        link: "https://krikos360.planexware.net/y", tiene_pdf: true },
      { inbox_id: 6, cadena: "COTO", sucursal: "CENTRO DE DISTRIBUCION",
        nro_documento: "21842845093", fecha_entrega: "18/08/2026", fecha_entrega_d: dia(3),
        link: "", tiene_pdf: false }
    ];
    const d = box(aprKrikosHtml());
    const filas = [...d.querySelectorAll(".apr-krikos-r")];
    out.listaTodas = filas.length === 3;
    // REGLA DEL DUEÑO: si el importe automático no da, se aclara MUY GRANDE en la PPP.
    const _t = d.querySelector(".apr-krikos-t").textContent.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    out.cuentaEnTitulo = /3 ordenes de compra de super/.test(_t);
    out.diceQueNoImporto = /NO se pudo importar sola a la PPP/.test(_t);
    out.pieDiceQueCorreSolo = /corre cada 10 minutos/i.test(
      d.querySelector(".apr-krikos-pie").textContent.normalize("NFD").replace(/[\u0300-\u036f]/g, ""));

    // ---- 3) la cadena se acorta ----
    const cads = [...d.querySelectorAll(".apr-krikos-cad")].map(x => x.textContent.trim());
    out.cadenaCorta = cads[0] === "La Anónima" && cads[1] === "Carrefour" && cads[2] === "Coto";
    out.sinRazonSocialLarga = !/SAIEP|INC S\.A\./.test(d.textContent);

    // ---- 4) vencida vs a futuro ----
    out.vencidaMarcada = filas[0].classList.contains("vencida");
    out.futuraNoMarcada = !filas[1].classList.contains("vencida") && !filas[2].classList.contains("vencida");
    out.avisoVencida = /⚠/.test(filas[0].querySelector(".apr-krikos-fe").textContent);

    // ---- 5) sin PDF se marca; con link aparece el botón ----
    out.sinPdfMarcado = !!filas[2].querySelector(".apr-krikos-nopdf") &&
                        !filas[0].querySelector(".apr-krikos-nopdf");
    out.botonVerOc = d.querySelectorAll("a.apr-krikos-btn").length === 2;   // el 3º no tiene link

    // ---- 6) NO es tildable: ni tarjeta de pedido, ni checkbox, ni draggable ----
    out.noEsPedido = d.querySelectorAll(".apr-card").length === 0 &&
                     d.querySelectorAll("input[type=checkbox]").length === 0 &&
                     d.querySelectorAll("[draggable=true]").length === 0;

    // ---- 6b) v15.90: la que entró con problema va en su propio bloque rojo ----
    // REGLA DEL DUEÑO: si el importe no da, se carga igual y se aclara MUY GRANDE en la PPP.
    _apr.krikos = [
      { inbox_id: 30, cadena: "COTO", sucursal: "CD", nro_documento: "21881017093",
        fecha_entrega: "20/09/2026", fecha_entrega_d: dia(6), link: "", tiene_pdf: true,
        auto_estado: "parcial", auto_aviso: "2 de 14 renglones NO entraron (codigo sin match: 198E x 70 caj)",
        order_id: 1402 },
      { inbox_id: 31, cadena: "DIARCO", sucursal: "CD", nro_documento: "99", fecha_entrega: "21/09/2026",
        fecha_entrega_d: dia(7), link: "", tiene_pdf: true, auto_estado: "no",
        auto_aviso: "no se reconocio la cadena en el PDF" }
    ];
    const d2 = box(aprKrikosHtml());
    const bloques = [...d2.querySelectorAll(".apr-krikos")];
    out.dosBloques = bloques.length === 2 && bloques[0].classList.contains("mal");
    const t2 = bloques[0].querySelector(".apr-krikos-t").textContent.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    out.gritaQueNoDio = /1 pedido de super entro/.test(t2) && /NO DIO/.test(t2);
    out.muestraElPedido = /pedido 1402/.test(bloques[0].textContent);
    out.muestraElMotivo = /198E/.test(bloques[0].textContent) &&
                          /no se reconocio la cadena/.test(bloques[1].textContent.normalize("NFD").replace(/[\u0300-\u036f]/g, ""));
    out.laQueEntroNoEstaAbajo = !/21881017093/.test(bloques[1].textContent);

    // ---- 7) el 🔄 vuelve a pedirlas ----
    _apr.krikos = [{ inbox_id: 1 }];
    const _ar = window.aprArmarAhora, _ac = window.aprCargar;
    window.aprArmarAhora = async function () {}; window.aprCargar = async function () {};
    _apr.armando = false; _apr.cargando = false;
    await aprActualizar();
    out.reloadPideDeNuevo = _apr.krikos === undefined;
    window.aprArmarAhora = _ar; window.aprCargar = _ac;
    _apr.krikos = [];

    // ---- v16.04 — el motivo NO se repite renglón por renglón cuando es el mismo ----
    // Con 6 OC salteadas por "fecha de entrega vencida", el cartel decía seis veces la misma
    // frase a ancho completo y llenaba la pantalla. Va una sola vez arriba.
    const mismo = "fecha de entrega vencida — se carga a mano si todavía va";
    _apr.krikos = [
      { inbox_id: 1, cadena: "COTO", nro_documento: "A", fecha_entrega_d: dia(-5), tiene_pdf: true, auto_aviso: mismo },
      { inbox_id: 2, cadena: "COTO", nro_documento: "B", fecha_entrega_d: dia(-6), tiene_pdf: true, auto_aviso: mismo },
      { inbox_id: 3, cadena: "COTO", nro_documento: "C", fecha_entrega_d: dia(-7), tiene_pdf: true, auto_aviso: mismo }
    ];
    const dm = box(aprKrikosHtml());
    out.motivoUnaVez = dm.querySelectorAll(".apr-krikos-motivo").length === 1 &&
                       dm.querySelectorAll(".apr-krikos-aviso").length === 0;
    out.motivoSeLee = /Todas por lo mismo/.test(dm.textContent) && dm.textContent.includes(mismo);
    out.filasIgual = dm.querySelectorAll(".apr-krikos-r").length === 3;

    // Motivos DISTINTOS → no se agrupa, cada renglón se explica solo.
    _apr.krikos[2].auto_aviso = "el link no devolvió el PDF";
    const dd = box(aprKrikosHtml());
    out.motivosDistintosNoAgrupa = dd.querySelectorAll(".apr-krikos-motivo").length === 0 &&
                                   dd.querySelectorAll(".apr-krikos-aviso").length === 3;

    // ---- SEGURIDAD (v16.04) — sin sesión NO se pide nada y el bloque no se dibuja ----
    // Regresión del problema "las OC de Krikos se leían con la anon key pública": el cartel
    // aparecía aunque la PPP Web dijera "Iniciá sesión", y el `link` de cada OC es la URL de
    // Planexware cuyo token abre el PDF sin credenciales.
    const _fetch = window.fetch, pedidos = [];
    window.fetch = function (u) { pedidos.push(String(u)); return Promise.resolve({ ok: true, json: () => Promise.resolve([]) }); };
    const _sb = window.sbAuth;

    window.sbAuth = { getAccessToken: async () => null };          // sin sesión
    _apr.krikos = undefined; _apr.krikosLoading = false;
    await aprKrikosCargar();
    // Se cuentan SOLO las de GV_Krikos_OC: al terminar, aprKrikosCargar llama a aprRender()
    // y eso dispara los fetches del resto de la pantalla, que acá no importan.
    const krikosPedidas = () => pedidos.filter(u => /GV_Krikos_OC/.test(u)).length;
    out.sinSesionNoPide = krikosPedidas() === 0;
    out.sinSesionSinCartel = aprKrikosHtml() === "";
    out.sinSesionNoSeTrabaSolo = _apr.krikosLoading === false;     // si no, no reintenta al loguearse

    window.sbAuth = { getAccessToken: async () => "tok-abc" };     // con sesión
    _apr.krikos = undefined; _apr.krikosLoading = false;
    await aprKrikosCargar();
    out.conSesionPide = krikosPedidas() === 1;

    window.fetch = _fetch; window.sbAuth = _sb; _apr.krikos = [];

    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter(k => !r[k]);
  if (errs.length) { console.error("apr-krikos: errores de página:", errs); process.exit(1); }
  if (fails.length) { console.error("apr-krikos FALLÓ:", fails, r); process.exit(1); }
  console.log("apr-krikos OK —", Object.keys(r).length, "chequeos");
})();
