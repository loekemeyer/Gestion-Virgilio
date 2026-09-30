/* Caracterizacion de Tablet/Tablet_GP2.html (2026-09-13, ideas 7342/7343; reescrito 2026-09-14
   con el flujo por TIPO), con Supabase STUBEADO (tablet_bundle devuelve un fixture chico con la
   forma REAL del bundle de la base; tablet_registrar anota lo que recibe y contesta como la base).
   Fija:
     1. primero el TIPO y despues la contraparte de ese tipo — en Enviar los tres tipos a los que
        se les manda desde Cervantes (Virgilio no), y adentro de un tipo solo sus contrapartes;
     2. en Recibir NO esta el prov. de art. terminado (entrega en Virgilio, no en Cervantes),
        SI esta "Prov. de insumos" y es un link a Recepcion Insumos, y un tipo con una sola
        contraparte (Virgilio) entra derecho a la carga;
     3. el Conteo no es un modo: es un link al modulo de Relevamientos;
     4. el buscador filtra la tabla;
     5. la trampa de unidad que queda: una pieza en kg se carga en kg (teclado decimal) y viaja
        'kg' (la carga en CAJAS se fue con el prov. AT);
     6. la alerta de "recibi de mas" AVISA pero NO BLOQUEA: la fila se marca, el boton sigue
        habilitado, el confirm lo dice, y el exito muestra lo que la base devolvio en alertas;
     7. a 390px no hay scroll horizontal y los campos son tocables (>= 44px). */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// misma forma que "GP2".tablet_bundle() (claves reales, verificadas contra la base 2026-09-13)
const BUNDLE = {
  generado_en: '2026-09-13T12:00:00Z',
  alertas_abiertas: 0,
  contrapartes: [
    { tipo: 'tallerista', ref: '6', nombre: 'Martin Cornejo', n_env: 5, n_rec: 2 },
    { tipo: 'tallerista', ref: '9', nombre: 'Lucho', n_env: 1, n_rec: 0 },
    // TALLERISTA CON O.C. DE VIRGILIO (2026-09-23): mismo tipo 'tallerista' en la base, con el flag
    // `oc` que manda tablet_bundle desde GP2.tallerista.pedido_por_oc_virgilio. En ENVIAR sale en
    // su propia baldosa y su sugerido es 0; en RECIBIR sigue adentro de Talleristas.
    { tipo: 'tallerista', ref: '14', nombre: 'Carlos Aguirre', oc: true, n_env: 1, n_rec: 1 },
    { tipo: 'proveedor_at', ref: '1', nombre: 'Cabral', n_env: 2, n_rec: 1 },
    // el PS "comun", sin unidad de envio propia. Al 2026-09-18 ya NINGUN P.S. con piezas quedo
    // asi (los 7 que las tienen van por el cajon de cada pieza, AJ por paquetes y Julio por peso):
    // Blist-Pack es de los que siguen sin unidad definida, y aca se le dan piezas para cubrir el
    // render comun, que es el que ven los talleristas y el que quedaria si se suma un P.S. nuevo.
    { tipo: 'proveedor_servicio', ref: '20', nombre: 'Blist-Pack', n_env: 1, n_rec: 1 },
    // AJ es la EXCEPCION de la entrega: envia en paquetes de 100 y ENTREGA en paquetes de 200
    { tipo: 'proveedor_servicio', ref: '12', nombre: 'AJ Adhesivos', envio_unidad: 'paquetes', envio_uni_x: 100, entrega_unidad: 'paquetes', entrega_uni_x: 200, n_env: 1, n_rec: 1 },
    { tipo: 'proveedor_servicio', ref: '8', nombre: 'Hernandez Julio', envio_unidad: 'kg', envio_uni_x: null, n_env: 2, n_rec: 0 },
    { tipo: 'proveedor_servicio', ref: '14', nombre: 'Ester', envio_unidad: 'bolsas', envio_uni_x: 1800, envio_carga_unidad: 'kg', n_env: 1, n_rec: 0 },
    // Guazzaroni: el envase es el CAJON de cada pieza (envio_uni_x null), no uno del proveedor
    { tipo: 'proveedor_servicio', ref: '4', nombre: 'Guazzaroni Patricio', envio_unidad: 'cajones', envio_uni_x: null, envio_carga_unidad: 'kg', n_env: 2, n_rec: 2 },
    { tipo: 'inyector', ref: 'Pat Bet Plast', nombre: 'Pat Bet Plast', n_env: 2, n_rec: 0 },
    { tipo: 'proveedor_insumo', ref: 'Corrugadora del Plata', nombre: 'Corrugadora del Plata', n_env: 0, n_rec: 3 },
    { tipo: 'virgilio', ref: 'virgilio', nombre: 'Virgilio', n_env: 0, n_rec: 1 },
  ],
  // PS y tallerista traen ademas maximo/stock_dest/sugerido de la pieza PROCESADA/ARMADA (la
  // salida): la tablet MUESTRA el sugerido y lo precarga en Cantidad SOLO para talleristas (a los
  // P.S. y a los inyectores no: el campo arranca vacio, usuario 2026-09-17). El Prov. AT muestra el
  // renglon con sugerido 0 (desde 2026-09-24, igual que talleristas O.C.: la O.C. la hace Virgilio);
  // solo el carton de OTRO articulo (sust_de) viene con sugerido null y cae a "Online sector".
  enviar: [
    // AL TALLERISTA la unidad de envio la pone la PIEZA, y la manda la base en cada fila
    // [usuario 2026-09-18]: carton y caja en PAQUETES (el paqueton del formato / los 25 de la
    // caja) y el resto con el sugerido en CAJONES y la cantidad en KG.
    { tipo: 'tallerista', ref: '6', comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'Sector Crudo', um: 'unidad', uxc: 1000, kg_x_uni: 0.01, online_sector: 120, saldo_dest: 42, maximo: 200, stock_dest: 50, sugerido: 150, env_unidad: 'cajones', env_factor: 1000, env_carga: 'kg' },
    { tipo: 'tallerista', ref: '6', comp_id: 75, cod: 'F7', desc: 'Fleje doblado', sector: 'Sector Fleje', um: 'kg', uxc: null, kg_x_uni: 0.0134, online_sector: 30.5, saldo_dest: 7.5, maximo: 40, stock_dest: 10, sugerido: 12.5, env_unidad: 'cajones', env_factor: null, env_carga: 'kg' },
    // carton: 2.500 uni / paqueton de 1.000 (carton_formato.uni_x_bolsa del formato C) -> 3 paquetes
    { tipo: 'tallerista', ref: '6', comp_id: 300, cod: 'C10', desc: 'Carton Pelapapa 505', sector: 'Sector Cartón', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 0, saldo_dest: 0, maximo: 3000, stock_dest: 0, sugerido: 2500, env_unidad: 'paquetes', env_factor: 1000, env_carga: 'envase' },
    // caja: paquetes de 25 (parametro caja_uni_x_paquete) -> 60 uni = 3 paquetes (techo)
    { tipo: 'tallerista', ref: '6', comp_id: 310, cod: 'CJ7', desc: 'Caja N°7', sector: 'Sector Caja', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 0, saldo_dest: 0, maximo: 100, stock_dest: 0, sugerido: 60, env_unidad: 'paquetes', env_factor: 25, env_carga: 'envase' },
    // carton cuyo formato NO tiene paqueton cargado: se carga en unidades y la tarjeta lo dice
    { tipo: 'tallerista', ref: '6', comp_id: 320, cod: 'BANDITA', desc: 'Bandita Palo de Amasar', sector: 'Sector Cartón', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 0, saldo_dest: 0, maximo: 900, stock_dest: 0, sugerido: 900, env_unidad: 'paquetes', env_factor: null, env_carga: 'envase' },
    // BOMBILLA: existe en el fixture para fijar DOS cosas del orden por rubro — que Bombilla es el
    // ultimo bloque y que el "➕ Otro carton" NO queda al final de la grilla sino cerrando el carton
    // [usuario 2026-09-23]. Sin una pieza despues del carton, las dos cosas se ven iguales.
    { tipo: 'tallerista', ref: '6', comp_id: 330, cod: 'BOM10', desc: 'Resorte Biconico', sector: 'Sector Bombilla', um: 'unidad', uxc: null, kg_x_uni: 0.00963, online_sector: 500, saldo_dest: 0, maximo: 400, stock_dest: 0, sugerido: 400, env_unidad: 'cajones', env_factor: null, env_carga: 'kg' },
    { tipo: 'tallerista', ref: '9', comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'Sector Crudo', um: 'unidad', uxc: 1000, kg_x_uni: 0.01, online_sector: 120, saldo_dest: 0, maximo: 200, stock_dest: 0, sugerido: 200, env_unidad: 'cajones', env_factor: 1000, env_carga: 'kg' },
    // el TALLERISTA O.C. viene con maximo y sugerido en 0: su pedido sale de una O.C. de Gestion
    // Virgilio que GP2 no lee, asi que el techo de tablet_bundle es 0 [usuario 2026-09-23]
    { tipo: 'tallerista', ref: '14', comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'Sector Crudo', um: 'unidad', uxc: 1000, kg_x_uni: 0.01, online_sector: 120, saldo_dest: 0, maximo: 0, stock_dest: 0, sugerido: 0, env_unidad: 'cajones', env_factor: 1000, env_carga: 'kg' },
    { tipo: 'proveedor_servicio', ref: '20', comp_id: 90, cod: 'D5', desc: 'Mitad rompenuez', sector: 'Sector Crudo', um: 'unidad', uxc: 500, kg_x_uni: 0.05, online_sector: 40, saldo_dest: 0, maximo: 100, stock_dest: 20, sugerido: 80 },
    // AJ Adhesivos manda por PAQUETES de 100: sugerido 250 uni -> 3 paquetes (techo)
    { tipo: 'proveedor_servicio', ref: '12', comp_id: 564, cod: 'Pliego 506', desc: 'Sin adhesivar', sector: 'Sector Procesado', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 0, saldo_dest: 0, maximo: 500, stock_dest: 0, sugerido: 250 },
    // Hernandez Julio recibe PESADO (envio_unidad 'kg'): las metalicas van en cajones y las
    // plasticas en bolsas — el bulto sale del sector, no del proveedor.
    { tipo: 'proveedor_servicio', ref: '8', comp_id: 80, cod: 'A1', desc: 'Mgo Plano 501 Pint.', sector: 'Sector Procesado', um: 'unidad', uxc: 750, kg_x_uni: 0.04, online_sector: 0, saldo_dest: 0, maximo: 2000, stock_dest: 0, sugerido: 1000 },
    { tipo: 'proveedor_servicio', ref: '8', comp_id: 231, cod: 'PA10B', desc: 'Capuchon ф 8 S/Serig', sector: 'Sector Plástico', um: 'unidad', uxc: 1000, kg_x_uni: 0.002, online_sector: 0, saldo_dest: 0, maximo: 8000, stock_dest: 0, sugerido: 5000 },
    // Ester manda de a BOLSAS de 1800 mangos pero PESA lo que carga: el sugerido va en bolsas
    // (112.432 mangos -> 63 bolsas, techo) y la cantidad en kg (63 x 1800 x 0,0054 = 612,36 kg)
    { tipo: 'proveedor_servicio', ref: '14', comp_id: 622, cod: 'PC2', desc: 'Mgo Pelapapa 505 Sin Calar', sector: 'Sector Plástico', um: 'unidad', uxc: 1852, kg_x_uni: 0.0054, online_sector: 0, saldo_dest: 0, maximo: 112432, stock_dest: 0, sugerido: 112432 },
    // Guazzaroni Patricio: sugerido en CAJONES (el uni_x_cajon de cada pieza) y cantidad en kg.
    // CV1 tiene cajon (57.143) -> 34.992 remaches = 1 cajon = 20,00 kg. CV9 NO tiene cajon
    // cargado: esa fila NO se convierte, queda en unidades.
    { tipo: 'proveedor_servicio', ref: '4', comp_id: 601, cod: 'CV1', desc: 'Remache Espiral p/Niquelar', sector: 'Sector Remache', um: 'unidad', uxc: 57143, kg_x_uni: 0.00035, online_sector: 0, saldo_dest: 0, maximo: 34992, stock_dest: 0, sugerido: 34992 },
    { tipo: 'proveedor_servicio', ref: '4', comp_id: 609, cod: 'CV9', desc: 'Remache uña niq. p/Niquelar', sector: 'Sector Remache', um: 'unidad', uxc: null, kg_x_uni: 0.000567, online_sector: 0, saldo_dest: 0, maximo: 113304, stock_dest: 0, sugerido: 113304 },
    // el prov. de art. terminado recibe cartones y cajas: los dos van en PAQUETES (mismo envase por
    // pieza que el tallerista). Desde el 2026-09-24 su sugerido es SIEMPRE 0 (igual que el tallerista
    // O.C.): el pedido sale de una O.C. de Gestion Virgilio que GP2 no lee, no del maximo de la casa.
    { tipo: 'proveedor_at', ref: '1', comp_id: 456, cod: 'A1', desc: 'Caja N°1', sector: 'Sector Caja', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 988, saldo_dest: 0, maximo: 0, stock_dest: null, sugerido: 0, env_unidad: 'paquetes', env_factor: 25, env_carga: 'envase' },
    { tipo: 'proveedor_at', ref: '1', comp_id: 457, cod: 'C20', desc: 'Carton Colador N°8', sector: 'Sector Cartón', um: 'unidad', uxc: null, kg_x_uni: null, online_sector: 4200, saldo_dest: 0, maximo: 0, stock_dest: null, sugerido: 0, env_unidad: 'paquetes', env_factor: 1000, env_carga: 'envase' },
    { tipo: 'inyector', ref: 'Pat Bet Plast', comp_id: 742, cod: '2405', desc: 'PP 2630', sector: 'Sector Bolsas Plásticas', um: 'kg', uxc: null, kg_x_uni: null, online_sector: 100, saldo_dest: 40, maximo: 300, stock_dest: 100, sugerido: 200 },
    { tipo: 'inyector', ref: 'Pat Bet Plast', comp_id: 743, cod: '2455', desc: 'ABS GP 22', sector: 'Sector Bolsas Plásticas', um: 'kg', uxc: null, kg_x_uni: null, online_sector: 50, saldo_dest: 8, maximo: 50, stock_dest: 20, sugerido: 30 },
  ],
  recibir: [
    // ENTREGA de tallerista: el esperado se mira en CAJONES y la cantidad se escribe en KG
    // [usuario 2026-09-18]. 1.000 uni / 500 por cajon = 2 cajones; esos 1.000 pesan 10 kg.
    { tipo: 'tallerista', ref: '6', comp_id: 71, comp_entrada_id: 70, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'A11', desc: 'Una Armada', sector: 'Sector Procesado', um: 'unidad', uxc: 500, kg_x_uni: 0.01, por_caja: null, ent_cod: 'A10', ent_desc: 'Cpo Una', esperado: 1000, esperado_origen: 'online_tall', env_unidad: 'cajones', env_factor: 500, env_carga: 'kg' },
    // la UNICA excepcion: las bombillas GRJ5/GRJ6 entregan BOLSAS de 120 (componente.entrega_*)
    { tipo: 'tallerista', ref: '6', comp_id: 541, comp_entrada_id: null, n_entradas: 0, tiene_bom: false, cod_art: null, cod: 'GRJ5', desc: 'Bombilla Resorte Trad 558', sector: 'Sector Garage', um: 'unidad', uxc: 960, kg_x_uni: 0.0147, por_caja: null, ent_cod: null, ent_desc: null, esperado: 360, esperado_origen: 'online_tall', env_unidad: 'bolsas', env_factor: 120, env_carga: 'kg' },
    // el tallerista NO tiene nada nuestro de esta pieza: la base manda esperado 0 (coalesce), y la
    // pantalla tiene que DECIR 0, no dejar el lugar en blanco [usuario 2026-09-21]
    // LA CUCHILLA VIENE PESADA y las bombillas contadas, las dos del mismo tallerista
    // [usuario 2026-09-23: "El remito de las bombillas en uni... El remito de la cuchilla en kg"]:
    // lo dice la pieza, en componente.remito_unidad, que el bundle manda en la fila.
    { tipo: 'tallerista', ref: '6', comp_id: 73, comp_entrada_id: 74, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'X4', desc: 'Cuchilla Pelapapa Cerrada', sector: 'Sector Crudo', um: 'unidad', uxc: 4004, kg_x_uni: 0.00492, por_caja: null, ent_cod: 'X1', ent_desc: 'Cuchilla Pelapapa Abierta', esperado: 4004, esperado_origen: 'online_tall', env_unidad: 'cajones', env_factor: 4004, env_carga: 'kg', remito_unidad: 'kg' },
    { tipo: 'tallerista', ref: '6', comp_id: 72, comp_entrada_id: null, n_entradas: 0, tiene_bom: false, cod_art: null, cod: 'A12', desc: 'Una Armada Chica', sector: 'Sector Procesado', um: 'unidad', uxc: 500, kg_x_uni: 0.01, por_caja: null, ent_cod: null, ent_desc: null, esperado: 0, esperado_origen: 'online_tall', env_unidad: 'cajones', env_factor: 500, env_carga: 'kg' },
    // el tallerista O.C. entrega como cualquier otro: en RECIBIR no se lo separa [usuario 2026-09-23]
    { tipo: 'tallerista', ref: '14', comp_id: 71, comp_entrada_id: 70, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'A11', desc: 'Una Armada', sector: 'Sector Procesado', um: 'unidad', uxc: 500, kg_x_uni: 0.01, por_caja: null, ent_cod: 'A10', ent_desc: 'Cpo Una', esperado: 500, esperado_origen: 'online_tall', env_unidad: 'cajones', env_factor: 500, env_carga: 'kg' },
    { tipo: 'proveedor_at', ref: '1', comp_id: null, comp_entrada_id: null, n_entradas: 0, tiene_bom: false, cod_art: '026', cod: '026', desc: 'Colador N°8', sector: null, um: null, uxc: null, kg_x_uni: null, por_caja: 36, ent_cod: null, ent_desc: null, esperado: 72, esperado_origen: 'oc' },
    { tipo: 'proveedor_servicio', ref: '20', comp_id: 91, comp_entrada_id: 90, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'D5-P', desc: 'Mitad pintada', sector: 'Sector Procesado', um: 'unidad', uxc: 500, kg_x_uni: 0.05, por_caja: null, ent_cod: 'D5', ent_desc: 'Mitad rompenuez', esperado: 40, esperado_origen: 'online_ps' },
    // Guazzaroni envia por el CAJON de cada pieza y kg: la entrega copia esa misma logica, pero EL
    // CAJON ES EL DE LA PIEZA QUE SE LE MANDO (ent_uxc / ent_kgu, que la base manda solo para los
    // remaches): 1.000 uni / 500 por cajon de CV1 = 2 cajones, y esos 1.000 pesan 50 kg. El uxc de
    // la pieza NIQUELADA (50) es la bolsa en la que se fracciona despues, no un cajon: con ese
    // numero el esperado daba 20 cajones donde habian salido 2 (el caso real fue CV11 -> V11, 5
    // cajones mostrados como 50). [usuario 2026-09-18]
    { tipo: 'proveedor_servicio', ref: '4', comp_id: 601, comp_entrada_id: 600, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'CV1N', desc: 'Remache Espiral Niquelado', sector: 'Sector Remache', um: 'unidad', uxc: 50, kg_x_uni: 0.05, por_caja: null, ent_cod: 'CV1', ent_desc: 'Remache Espiral p/Niquelar', ent_uxc: 500, ent_kgu: 0.05, esperado: 1000, esperado_origen: 'online_ps' },
    // ...Y EL CAJON QUE VALE ES EL QUE ANOTO LOGISTICA (ent_uxc_anot, 2026-09-21). El caso real:
    // se le mandaron 60.000 remaches ANOTADOS COMO 1 CAJON (pesaron 21 kg), pero el cajon teorico
    // de la pieza son 57.143 (20 kg justos) -> la tarjeta decia 1,05 cajones. Con el anotado da 1.
    // el esperado con DECIMALES es el caso real: el saldo del P.S. arrastra la conversion
    // kg <-> uni, y media unidad de diferencia NO es "recibi de mas" (usuario 2026-09-23)
    { tipo: 'proveedor_servicio', ref: '4', comp_id: 611, comp_entrada_id: 610, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'CV2N', desc: 'Remache Pizza Niquelado', sector: 'Sector Remache', um: 'unidad', uxc: 50, kg_x_uni: 0.00035, por_caja: null, ent_cod: 'CV2', ent_desc: 'Remache Pizza p/Niquelar', ent_uxc: 57143, ent_kgu: 0.00035, ent_uxc_anot: 60000, esperado: 59999.851851851, esperado_origen: 'online_ps' },
    // AJ: 600 pliegos esperados / 200 por paquete de ENTREGA = 3 paquetes (no 6, que serian de envio)
    { tipo: 'proveedor_servicio', ref: '12', comp_id: 565, comp_entrada_id: 564, n_entradas: 1, tiene_bom: false, cod_art: null, cod: 'Pliego Ad 506', desc: 'Adhesivado', sector: 'Sector Procesado', um: 'unidad', uxc: null, kg_x_uni: null, por_caja: null, ent_cod: 'Pliego 506', ent_desc: 'Sin adhesivar', esperado: 600, esperado_origen: 'online_ps' },
    { tipo: 'virgilio', ref: 'virgilio', comp_id: 373, comp_entrada_id: null, n_entradas: 0, tiene_bom: false, cod_art: null, cod: 'IC3V', desc: 'Fleje N° 90 LARGO', sector: 'Sector Fleje', um: 'kg', uxc: 24, kg_x_uni: 0.0134, por_caja: null, ent_cod: null, ent_desc: null, esperado: 20, esperado_origen: 'online_virgilio' },
  ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    // ademas en sessionStorage: desde que Recibir de un P.S. salta solo a la pantalla de control
    // (2026-09-21), window.__calls se pierde en la navegacion y el payload hay que leerlo despues.
    try { var ss = JSON.parse(sessionStorage.getItem('__calls') || '[]');
          ss.push({name:name, args:args});
          sessionStorage.setItem('__calls', JSON.stringify(ss)); } catch(e){}
    if(name==='tablet_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(BUNDLE)})), error: null };
    // ➕ Otro cartón (2026-09-21): las dos listas del reemplazo. "oficiales" son los cartones/cajas
    // que ESE destino usa (a los que se puede reemplazar) y "otros" el resto del catálogo.
    if(name==='cartones_para_reemplazo'){
      var CAT = {
        'tallerista:6': { oficiales: [
            { comp_id: 300, cod: 'C10', desc: 'Carton Pelapapa 505', sec_id: 10 },
            { comp_id: 320, cod: 'BANDITA', desc: 'Bandita Palo de Amasar', sec_id: 10 },
            { comp_id: 310, cod: 'CJ7', desc: 'Caja N°7', sec_id: 11 } ] },
        'proveedor_at:1': { oficiales: [
            { comp_id: 457, cod: 'C20', desc: 'Carton Colador N°8', sec_id: 10 },
            { comp_id: 456, cod: 'A1', desc: 'Caja N°1', sec_id: 11 } ] }
      };
      var OTROS = [
        { comp_id: 800, cod: 'C55', desc: 'Carton Sacacorchos 540', sec_id: 10, sector: 'Sector Cartón', factor: 1000, online_sector: 7000 },
        { comp_id: 801, cod: 'C77', desc: 'Carton Abrelatas 512', sec_id: 10, sector: 'Sector Cartón', factor: 2000, online_sector: 0 },
        { comp_id: 810, cod: 'CJ9', desc: 'Caja N°9', sec_id: 11, sector: 'Sector Caja', factor: 25, online_sector: 300 }
      ];
      var c = CAT[args.p_tipo + ':' + args.p_ref] || { oficiales: [] };
      return { data: { oficiales: c.oficiales, otros: OTROS }, error: null };
    }
    if(name==='tablet_registrar'){
      // igual que la base: alerta por item recibido con esperado y recibido > esperado + 5 %, y
      // NUNCA para un P.S. ni para un tallerista, que tienen su pantalla de control [2026-09-23]
      var p = args.p, al = [];
      (p.items||[]).forEach(function(it){
        if(p.modo==='recibir' && p.tipo !== 'proveedor_servicio' && p.tipo !== 'tallerista' &&
           it.esperado != null && it.cantidad > it.esperado * 1.05)
          al.push({ id: 900+al.length, cod: it.cod_art || ('comp'+it.comp_id), esperado: it.esperado, recibido: it.cantidad, exceso: it.cantidad-it.esperado });
      });
      return { data: { ok:true, n:(p.items||[]).length, contraparte:'X', modo:p.modo, items:[], alertas: al }, error: null };
    }
    // el contador del boton Control (v1.39.0): 1 entrega de P.S. + 2 recepciones de Importado con
    // control = 3; los 3 cartones NO suman porque no tienen pantalla de control a donde ir
    if(name==='control_entrega_bundle') return { data: { tol_pct: 5, hechos: [],
      pend: [{ mov_id: 1, cp_tipo: 'proveedor_servicio', cp_nombre: 'Ester', sp_cod: 'PC1A', declarado: 10, unidad: 'kg' }],
      insumos_pend: [
        { via: 'control', sector_id: 2, sector: 'Sector Procesado', proveedor: 'Importado', n: 2, codigos: ['C13', 'E13'], desde: '2026-09-30T12:00:00-03:00' },
        { via: 'control', sector_id: 10, sector: 'Sector Carton', proveedor: 'Cartocor', n: 3, codigos: ['C1'], desde: '2026-09-29T12:00:00-03:00' }
      ] }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const dialogs = [];
  page.on('dialog', d => { dialogs.push({ type: d.type(), msg: d.message() }); d.accept(); });
  await page.route('**/@supabase/supabase-js@2**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };
  const calls = async (n) => page.evaluate(n => (window.__calls || []).filter(c => c.name === n), n);
  // el mismo registro pero en sessionStorage: sobrevive a la navegacion (ver el STUB).
  const callsSS = async (n) => page.evaluate(n => {
    try { return JSON.parse(sessionStorage.getItem('__calls') || '[]').filter(c => c.name === n); }
    catch (e) { return []; }
  }, n);
  const tipos = () => page.$$eval('#tipoGrid .tipo-btn', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  // Enviar -> Prov. de servicio (y los inyectores, que se eligen ahi adentro) muestra las partes
  // como TARJETAS y la carga en una vista aparte [usuario 2026-09-18]. Estos helpers son ese flujo.
  // las PIEZAS de la contraparte. La tarjeta "➕ Otro cartón" (2026-09-21) no es una pieza: es la
  // puerta para agregar una, así que queda afuera de este helper y tiene el suyo.
  const cards = () => page.$$eval('#cardsGrid .parte-card:not(.otro)', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  const cardOtro = () => page.$$eval('#cardsGrid .parte-card.otro', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  const ultimaCard = () => page.$eval('#cardsGrid', g => {
    const u = g.lastElementChild;
    return u ? { otro: u.classList.contains('otro'), txt: u.textContent.replace(/\s+/g, ' ').trim() } : null;
  });
  const abrir = async (cod) => {
    await page.click('#cardsGrid .parte-card:has-text("' + cod + '")');
    await page.waitForSelector('#detCard input[data-f="q"]');
  };
  const det = () => page.$eval('#detCard', e => e.textContent.replace(/\s+/g, ' ').trim());
  const DQ = '#detCard input[data-f="q"]', DC = '#detCard input[data-f="c"]';
  const DEQ = '#detCard .det-eq';   // el renglon chico con el equivalente en bultos
  const cargarParte = async (cod, valor) => { await abrir(cod); await page.fill(DQ, valor); await page.click('#btnVolverPartes'); };

  await page.goto(ROOT + '/Tablet/Tablet_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);

  // ── 1) modo ENVIAR: primero el TIPO ──────────────────────────────────────
  ok(await page.$eval('#modos .modo-btn.active', b => b.dataset.modo) === 'enviar', 'arranca en Enviar');
  let ts = await tipos();
  // "Virgilio afuera" se mira por el data-tipo del botón, no por la palabra: desde que existe la
  // baldosa "Talleristas O.C." el texto dice quién emite la O.C. (Gestión Virgilio) sin que eso
  // signifique que Virgilio sea un destino de Enviar.
  ok(ts.length === 5 && !(await page.$('#tipoGrid .tipo-btn[data-tipo="virgilio"]')),
     'Enviar: 5 tipos, Virgilio afuera — ' + ts.join(' | '));
  ok(ts.some(t => t.includes('Inyectores')), 'Enviar: los Inyectores tienen su propio tipo — ' + ts.join(' | '));
  ok(ts[0].includes('Talleristas') && ts[0].includes('· 2') && !ts.join('|').includes('contraparte'),
     'el tipo dice cuántas hay sin la palabra "contraparte" — ' + ts[0]);
  ok(await page.$eval('#cpBox', e => e.classList.contains('hidden')), 'todavía no se listan las contrapartes');

  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  let btns = await page.$$eval('#cpGrid .prov-btn', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(btns.length === 2 && btns[0].startsWith('Martin Cornejo') && btns[1].startsWith('Lucho') && !btns.join('|').includes('tallerista'),
     'adentro de Talleristas solo talleristas (2) y sin repetir el tipo en cada chip — ' + btns.join(' | '));
  ok((await page.$eval('#fase0Title', e => e.textContent)) === 'Talleristas', 'el título dice el tipo elegido');

  // el "← Cambiar tipo" vuelve a los tipos sin recargar
  await page.click('#btnVolverTipo');
  ok((await tipos()).length === 5 && await page.$eval('#cpBox', e => e.classList.contains('hidden')), 'Cambiar tipo vuelve a los tipos');

  /* ── TALLERISTAS O.C.: BALDOSA PROPIA EN ENVIAR ────────────────────────────────
     [usuario 2026-09-23, con la foto: "a Blist-Pack SA y Carlos Aguirre quiero que me los saques
     afuera de talleristas y me los pongas en un modulo nuevo de talleristas o.c." + "No es o.c. de
     insumos. Es orden de compra que se hace desde Gestion Virgilio que hoy no esta modelado aca.
     Por ahora sugeri 0"]. En la base siguen siendo 'tallerista' (sacarlos de la tabla volteaba 32 y
     38 pasos de ruta): lo que los parte es el flag `oc` de cada contraparte. */
  ok(ts.some(t => t.includes('Talleristas O.C.')), 'Enviar: existe la baldosa Talleristas O.C. — ' + ts.join(' | '));
  ok(!btns.join('|').includes('Carlos Aguirre'),
     'el tallerista O.C. NO sale adentro de Talleristas — ' + btns.join(' | '));
  // una sola contraparte con el flag: la baldosa entra derecho a su carga
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista_oc"]');
  await page.waitForFunction(() => !document.getElementById('fase1').classList.contains('hidden'));
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Carlos Aguirre · O.C. Virgilio',
     'el título dice de dónde sale el pedido, así un sugerido 0 no se lee como "no mandarle nada"');
  // su pieza se carga igual que la de cualquier tallerista (tarjetas), pero con el sugerido en 0
  const ocCards = await cards();
  ok(ocCards.length === 1 && ocCards[0].includes('A10') && ocCards[0].includes('Sugerido 0'),
     'el tallerista O.C. viene con sugerido 0 (la O.C. la hace Virgilio) — ' + ocCards.join(' | '));
  await page.click('#btnVolver');   // una sola contraparte: vuelve directo a los tipos
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);

  // Los INYECTORES tienen su PROPIO tipo y NO aparecen bajo "Prov. de servicio" [usuario
  // 2026-09-18]. Su envio son las RESINAS (bolsas) en kg.
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  const soloPS = await page.$$eval('#cpGrid .prov-btn', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(soloPS.some(b => b.startsWith('Blist-Pack')) && !soloPS.some(b => b.startsWith('Pat Bet Plast')),
     'bajo "Prov. de servicio" ya no sale el inyector — ' + soloPS.join(' | '));
  await page.click('#btnVolverTipo');
  // un solo inyector en el fixture: el tipo entra directo a su carga (no se elige entre uno)
  await page.click('#tipoGrid .tipo-btn[data-tipo="inyector"]');
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Pat Bet Plast',
     'Inyectores abre el inyector (Pat Bet Plast)');
  // el inyector se carga igual que un P.S., asi que tambien va en TARJETAS (aunque desde v1.14.0
  // se lo elija en su propio boton): la vista cuelga de envSinMemoria, que incluye a los dos
  ok(await page.$eval('#tblWrap', e => e.classList.contains('hidden')) &&
     !(await page.$eval('#cardsGrid', e => e.classList.contains('hidden'))),
     'inyector: la tabla no se usa, las partes van en tarjetas');
  const resinas = await cards();
  ok(resinas.length === 2 && resinas.some(r => r.includes('2405')) && resinas.every(r => r.includes('kg')),
     'el inyector manda sus resinas (bolsas) en kg — ' + resinas.join(' | '));
  // el sugerido de bolsas (kg) se VE en la tarjeta, pero la cantidad arranca sin cargar: el campo
  // lo escribe la persona [usuario 2026-09-17: "no me preescribas ... la cantidad que voy a enviar"]
  ok(resinas[0].includes('Sugerido 200 kg') && resinas[1].includes('Sugerido 30 kg'),
     'inyector: cada tarjeta muestra su sugerido — ' + resinas.join(' | '));
  ok(resinas.every(r => r.includes('sin cargar')), 'inyector: las tarjetas arrancan sin cargar — ' + resinas.join(' | '));
  // v1.38.0: el inyector tambien va por rubro [usuario 2026-09-28] — sus resinas son un solo bloque
  const rubIny = await page.$$eval('#cardsGrid .pc-rubro', xs => xs.map(e => e.textContent.trim()));
  ok(rubIny.join(' | ') === 'Sector Bolsas Plásticas', 'inyector: rotulo de sector arriba del bloque — ' + rubIny.join(' | '));
  ok((await page.$$eval('#cardsGrid .parte-card.cargada', xs => xs.length)) === 0,
     'inyector: ninguna tarjeta se pinta como cargada');
  ok((await page.$eval('#btnEnviar', e => e.disabled)) === true, 'inyector: sin nada cargado el boton Enviar no habilita');
  // la vista de UNA parte: codigo, descripcion, el sugerido y el campo de la cantidad efectiva
  await abrir('2405');
  const detIny = await det();
  ok(detIny.includes('2405') && detIny.includes('PP 2630') && detIny.includes('Sugerido a enviar') &&
     detIny.includes('200 kg') && detIny.includes('Cantidad a enviar'),
     'inyector: la vista de la parte trae codigo, descripcion, sugerido y el campo — ' + detIny);
  ok((await page.$eval(DQ, e => e.value)) === '', 'inyector: el campo de la vista arranca vacio');
  ok((await page.$eval(DQ, e => e.getAttribute('inputmode'))) === 'decimal', 'inyector: teclado decimal (resina en kg)');
  // adentro de una parte no se cierra la carga: ni Fecha ni el boton de registrar [usuario 2026-09-18]
  ok(await page.$eval('#accBox', e => e.classList.contains('hidden')),
     'Enviar: adentro de la parte no se ve ni la Fecha ni el boton de enviar');
  await page.click('#btnVolverPartes');
  ok(!(await page.$eval('#accBox', e => e.classList.contains('hidden'))),
     'Enviar: "← Partes" devuelve la Fecha y el boton de enviar');
  ok((await page.$$eval('#cardsGrid .parte-card', xs => xs.length)) === 2, 'inyector: "← Partes" vuelve a la grilla');
  await page.click('#btnVolver');        // un solo inyector: vuelve directo a los tipos
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);

  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  await page.click('#cpGrid .prov-btn:has-text("Martin")');

  // ── el TALLERISTA tambien va en tarjetas, y cada pieza trae su unidad de envio ──────────
  ok(await page.$eval('#tblWrap', e => e.classList.contains('hidden')) &&
     !(await page.$eval('#cardsGrid', e => e.classList.contains('hidden'))),
     'tallerista: las partes van en tarjetas, no en la tabla');
  let tcards = await cards();
  ok(tcards.length === 6, 'tallerista: una tarjeta por pieza (6) — ' + tcards.length);
  // ── EL ORDEN ES POR RUBRO, NO ALFANUMERICO [usuario 2026-09-23: "primero todo lo que se le manda
  // de sector crudo, despues todo lo de sector procesado, despues todo los remaches, despues todo
  // lo de partes plasticas, despues todo lo de cajas y despues todo lo de cartones" + "me refiero
  // dentro de cada tallerista" + "Garage ponelo primero, fleje segundo y bombilla ultimo"].
  // [usuario 2026-09-24: "que despues de sector procesado venga sector plastico, no sector remache"]
  // -> PLASTICO pasa ANTES que REMACHE. La secuencia completa queda GARAGE, FLEJE, CRUDO, PROCESADO,
  // PLASTICAS, REMACHES, CAJAS, CARTONES, BOMBILLA. Alfabetico daria A10, BANDITA, C10, CJ7, F7 — el
  // carton partido en dos con la caja en el medio y el fleje al fondo, que es justo lo contrario de
  // lo que se pidio.
  // La SECUENCIA ENTERA se fija contra rubroDe(), no contra el fixture: Martin no recibe piezas de
  // Garage ni de Bombilla, asi que la grilla sola no puede probar que Garage va primero y Bombilla
  // ultimo. Aca tambien queda fijado que un sector fuera de la lista cae al fondo.
  const ordenRubros = await page.evaluate(() => ['Sector Garage', 'Sector Fleje', 'Sector Crudo',
    'Sector Procesado', 'Sector Plástico', 'Sector Remache', 'Sector Caja', 'Sector Cartón',
    'Sector Bombilla', 'Sector Movimiento'].map(s => rubroDe({ sector: s })));
  ok(ordenRubros.join(',') === '0,1,2,3,4,5,6,7,8,9',
     'rubros: garage, fleje, crudo, procesado, plasticas, remaches, cajas, cartones, bombilla, y lo que no esta en la lista al fondo — ' + ordenRubros.join(','));
  const codsDeGrilla = () => page.$$eval('#cardsGrid .parte-card:not(.otro) .pc-cod',
    xs => xs.map(e => (e.childNodes[0] ? e.childNodes[0].textContent : '').trim()));
  let ordT = await codsDeGrilla();
  ok(ordT.join(',') === 'F7,A10,CJ7,BANDITA,C10,BOM10',
     'tallerista: orden por rubro — fleje arriba, los dos cartones juntos y la bombilla al final — ' + ordT.join(','));
  // y el rotulo de cada bloque, sin el que el orden nuevo se lee como un desorden
  const rubrosT = () => page.$$eval('#cardsGrid .pc-rubro', xs => xs.map(e => e.textContent.trim()));
  ok((await rubrosT()).join(' | ') === 'Sector Fleje | Sector Crudo | Sector Caja | Sector Cartón | Sector Bombilla',
     'tallerista: un rotulo por rubro, en el orden pedido — ' + (await rubrosT()).join(' | '));
  // LA GRILLA ENTERA, rotulos y "➕ Otro carton" incluidos: es el unico chequeo que prueba que el
  // boton cierra el CARTON y no la grilla [usuario 2026-09-23], porque despues de el hay bombilla.
  const secuenciaT = () => page.$$eval('#cardsGrid > *', xs => xs.map(e =>
    e.classList.contains('pc-rubro') ? '#' + e.textContent.trim()
      : e.classList.contains('otro') ? '+OTRO'
      : (e.querySelector('.pc-cod').childNodes[0].textContent || '').trim()));
  ok((await secuenciaT()).join(' ') ===
     '#Sector Fleje F7 #Sector Crudo A10 #Sector Caja CJ7 #Sector Cartón BANDITA C10 +OTRO #Sector Bombilla BOM10',
     'tallerista: "➕ Otro carton" cierra el bloque de cartones, no la grilla — ' + (await secuenciaT()).join(' '));
  ok((await page.$eval('#cardsGrid', g => g.firstElementChild.className)).includes('pc-rubro') &&
     (await page.$eval('#cardsGrid', g => g.firstElementChild.className)).includes('primero'),
     'tallerista: el primer rotulo no lleva la linea de separacion arriba');
  // el rotulo ocupa el ancho entero de la grilla: a 390px (el viewport de todo este test) eso no
  // tiene que empujar la pagina a scrollear de costado
  ok(!(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)),
     '390px: los bloques por rubro no hacen scrollear la pagina de costado');
  const cardDe = (cod) => tcards.find(c => c.startsWith(cod));
  // el resto de las piezas: el sugerido se mira en CAJONES y la cantidad se escribe en KG
  ok(cardDe('A10').includes('Cpo Una') && cardDe('A10').includes('Sugerido 1 caj\u00f3n') &&
     cardDe('A10').includes('kg'),
     'A10: sugerido 150 uni -> 1 cajon (techo, en singular) y se carga en kg — ' + cardDe('A10'));
  // carton: el paqueton lo pone el FORMATO (1.000) -> 2.500 uni = 3 paquetes
  ok(cardDe('C10').includes('Sugerido 3 paquetes'),
     'C10 (carton): 2.500 uni / paqueton de 1.000 -> 3 paquetes — ' + cardDe('C10'));
  // caja: paquetes de 25
  ok(cardDe('CJ7').includes('Sugerido 3 paquetes'),
     'CJ7 (caja): 60 uni / 25 por paquete -> 3 paquetes — ' + cardDe('CJ7'));
  // lo que no tiene el dato NO se convierte: queda en unidades y lo dice
  ok(cardDe('BANDITA').includes('900') && cardDe('BANDITA').includes('sin paquete cargado'),
     'BANDITA: sin paqueton cargado queda en unidades y avisa — ' + cardDe('BANDITA'));
  ok(cardDe('F7').includes('12,5') && !cardDe('F7').includes('sin caj\u00f3n cargado'),
     'F7 (fleje): va en kg y NO avisa sin cajon cargado, se manda pesado [usuario 2026-09-24] — ' + cardDe('F7'));
  // NADA viene precargado: desde el 2026-09-18 tampoco al tallerista [usuario: "igual que P.S."]
  ok(tcards.every(c => c.includes('sin cargar')), 'tallerista: las tarjetas arrancan sin cargar');
  ok((await page.$eval('#btnEnviar', e => e.disabled)) === true, 'tallerista: sin nada cargado no se puede enviar');

  // la vista de la parte: el sugerido en cajones arriba, los kg abajo, y la equivalencia
  // LAS DOS UNIDADES: primero los cajones y despues los kg [usuario 2026-09-18], y "Listo" no se
  // habilita hasta que esten las dos.
  await abrir('A10');
  const detA10 = await det();
  ok(detA10.includes('Sugerido a enviar') && detA10.includes('1 caj\u00f3n') &&
     detA10.includes('Cantidad (cajones)') && detA10.includes('Cantidad (kg)'),
     'A10: la vista pide los cajones Y los kg — ' + detA10);
  ok((await page.$eval(DC, e => e.value)) === '' && (await page.$eval(DQ, e => e.value)) === '',
     'A10: los dos campos arrancan vacios');
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === true,
     'A10: sin nada cargado no se puede cerrar la parte');
  await page.fill(DC, '3');
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === true,
     'A10: con los cajones solos tampoco: falta el kg');
  ok((await page.$eval('#detCard .det-falta', e => e.textContent.trim())) === 'Falta anotar los kg',
     'A10: y la vista dice que falta');
  ok((await page.$eval('#btnEnviar', e => e.textContent)) === 'Enviar',
     'A10: una fila a medias NO se cuenta para registrar');
  // EL PUNTO TIPEADO ENTRA COMO COMA [usuario 2026-09-18: "quiero que me deje poner . o , para
  // poner decimales"]. Se tipea tecla por tecla: con page.fill no pasa por beforeinput.
  await page.click(DQ);
  await page.type(DQ, '10.5');
  ok((await page.$eval(DQ, e => e.value)) === '10,5',
     'el punto tipeado en un campo con decimales entra como coma — ' + (await page.$eval(DQ, e => e.value)));
  await page.fill(DQ, '');
  await page.fill(DC, '');
  await page.click(DC);
  await page.type(DC, '2.5');
  ok((await page.$eval(DC, e => e.value)) === '25',
     'en un campo de enteros (cajones) el punto no entra — ' + (await page.$eval(DC, e => e.value)));
  await page.fill(DC, '3');
  await page.fill(DQ, '25');
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === false,
     'A10: con las dos, Listo se habilita');
  // 3 cajones contra los 2,5 que dan los kg: media unidad de desvio, NO avisa
  ok((await page.$eval('#detCard .det-eq', e => e.textContent.trim())) === '= 2,5 cajones' &&
     !(await page.$eval('#detCard .det-eq', e => e.classList.contains('mal'))),
     'A10: 3 cajones contra 2,5 es medio envase de diferencia y NO salta alerta');
  // 4 contra 2,5: se pasa de media unidad, avisa — pero deja cerrar igual
  await page.fill(DC, '4');
  ok((await page.$eval('#detCard .det-eq', e => e.classList.contains('mal'))) &&
     (await page.$eval('#detCard .det-eq', e => e.textContent)).includes('anotaste 4 cajones'),
     'A10: 4 cajones contra 2,5 SI avisa — ' + (await page.$eval('#detCard .det-eq', e => e.textContent.trim())));
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === false,
     'A10: la alerta avisa pero NO frena: Listo sigue habilitado');
  // los dos campos van UNO AL LADO DEL OTRO, no apilados [usuario 2026-09-18]
  const dos = await page.evaluate(() => {
    const c = document.querySelector('#detCard input[data-f="c"]').getBoundingClientRect();
    const q = document.querySelector('#detCard input[data-f="q"]').getBoundingClientRect();
    return { mismaFila: Math.abs(c.top - q.top) < 4, envaseIzq: c.left < q.left,
             ancho: Math.round(document.querySelector('#detCard').getBoundingClientRect().width) };
  });
  ok(dos.mismaFila && dos.envaseIzq,
     'los dos campos van al lado, con el envase a la izquierda \u2014 ' + JSON.stringify(dos));
  await page.fill(DC, '3');
  await page.click('#btnVolverPartes');
  ok((await cards()).find(c => c.startsWith('A10')).includes('env\u00eda 25 kg') &&
     (await cards()).find(c => c.startsWith('A10')).includes('(3 cajones)'),
     'A10: la tarjeta muestra las dos unidades — ' + (await cards()).find(c => c.startsWith('A10')));

  // el carton se escribe EN PAQUETES (no en kg): no lleva el renglon de equivalencia
  await abrir('C10');
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'paquetes',
     'C10: la cantidad se escribe en paquetes');
  ok((await page.$eval('#detCard .det-eq', e => e.textContent.trim())) === '',
     'C10: sin equivalencia: el campo YA esta en paquetes');
  ok((await page.$eval(DQ, e => e.getAttribute('inputmode'))) === 'numeric', 'C10: teclado numerico (paquetes enteros)');
  await page.fill(DQ, '3');
  await page.click('#btnVolverPartes');
  await cargarParte('CJ7', '2');

  // UNA PIEZA QUE NO ES CARTON NI CAJA PUEDE IR EN SU ENVASE CERRADO [usuario 2026-09-25, Z21 Cuchillo
  // Torta a Martin Cornejo: "Que se le mande en cajas"]. La pieza lo dice con componente.envio_carga
  // ='envase' y tablet_bundle manda env_carga='envase': aunque tenga kg_x_uni, la cantidad se escribe
  // en CAJAS (no en kg) y se guarda en unidades (2 cajas de 450 = 900). Con env_carga='kg' la misma
  // pieza vuelve a la regla de siempre.
  const z21 = await page.evaluate(() => {
    const x = { tipo: 'tallerista', ref: '6', comp_id: 757, cod: 'Z21', desc: 'Cuchillo Torta CH/LK',
      sector: 'Sector Bombilla', um: 'unidad', uxc: null, kg_x_uni: 6.5 / 450, sugerido: 4,
      env_unidad: 'cajas', env_factor: 450, env_carga: 'envase' };
    const ev = envaseDe(x);
    const enKg = Object.assign({}, x, { env_carga: 'kg' });
    return { kg: cargaEnKg(x), label: ev && ev.label, f: ev && ev.factor, uni: canonDe(x, 2),
             kgSiPide: cargaEnKg(enKg) };
  });
  ok(z21.kg === false && z21.label === 'cajas' && z21.f === 450 && z21.uni === 900 && z21.kgSiPide === true,
     'Z21: env_carga=envase -> se escribe en cajas y 2 cajas = 900 uni; con kg vuelve a kg — ' + JSON.stringify(z21));

  // ── 2) el buscador filtra las tarjetas ────────────────────────────────
  await page.fill('#q', 'fleje');
  tcards = await cards();
  ok(tcards.length === 1 && tcards[0].includes('F7'), 'buscador "fleje" deja solo F7');
  await page.fill('#q', '');
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card:not(.otro)').length === 6);

  // se registra lo que se cargo a mano: A10 25 kg, C10 3 paquetes, CJ7 2 paquetes
  const fecha = await page.$eval('#fFecha', e => e.value);
  ok((await page.$eval('#btnEnviar', e => e.textContent)) === 'Enviar (3)', 'tallerista: las 3 piezas cargadas');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  let reg = await calls('tablet_registrar');
  ok(reg.length === 1, 'una llamada tablet_registrar');
  let p = reg[0].args.p;
  ok(p.modo === 'enviar' && p.tipo === 'tallerista' && p.ref === '6' && p.fecha === fecha + 'T12:00:00' && p.remito === null,
     'payload enviar: modo/tipo/ref/fecha — ' + JSON.stringify({ modo: p.modo, tipo: p.tipo, ref: p.ref, fecha: p.fecha }));
  ok(p.items.length === 3, 'se envian las 3 piezas cargadas');
  const itA10 = p.items.find(i => i.comp_id === 70), itC10 = p.items.find(i => i.comp_id === 300),
        itCJ = p.items.find(i => i.comp_id === 310);
  // el inventario nunca ve paquetes ni cajones: lo que viaja es kg o unidades
  // el bulto que se anota es el MISMO numero que se ve en pantalla, con decimales
  ok(itA10 && itA10.cantidad === 25 && itA10.unidad === 'kg' && itA10.cajones === 3,
     'A10: viajan los 25 kg y los 3 cajones que ANOTO el operario — ' + JSON.stringify(itA10));
  ok(itC10 && itC10.cantidad === 3000 && itC10.unidad === 'uni',
     'C10: 3 paquetes se guardan como 3.000 cartones (uni) — ' + JSON.stringify(itC10));
  ok(itCJ && itCJ.cantidad === 50 && itCJ.unidad === 'uni',
     'CJ7: 2 paquetes se guardan como 50 cajas (uni) — ' + JSON.stringify(itCJ));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('Enviar a Martin Cornejo') &&
                       d.msg.includes('3 paquetes') && d.msg.includes('25 kg')),
     'confirm de envio con resumen en la unidad de cada pieza');
  ok((await page.$eval('#successTitle', e => e.textContent)).includes('Enviado'), 'exito de envio');
  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_tablet_buffer') || '{}'));
  ok(!buf['enviar:tallerista:6'], 'buffer limpio tras enviar');

  // ── PROV. DE ART. TERMINADO: tarjetas tambien, en PAQUETES, y CON SUGERIDO 0 ──────────────
  // Recibe cartones y cajas (las dos cosas que van en paquetes). Desde el 2026-09-24 va IGUAL QUE
  // TALLERISTAS O.C.: su sugerido es 0 —la O.C. la hace Gestion Virgilio, que GP2 no lee— y el
  // titulo lo dice con "· O.C. Virgilio", asi un 0 no se lee como "no hay que mandarle nada".
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_at"]');   // una sola contraparte: entra derecho
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Cabral · O.C. Virgilio',
     'prov. AT: el titulo dice "· O.C. Virgilio" (igual que talleristas O.C.)');
  ok(await page.$eval('#tblWrap', e => e.classList.contains('hidden')),
     'prov. AT: en Enviar ya no queda tabla, van en tarjetas');
  const atCards = await cards();
  ok(atCards.length === 2, 'prov. AT: una tarjeta por pieza (2) — ' + atCards.length);
  // v1.38.0: el prov. AT va por rubro como el tallerista [usuario 2026-09-28]: cajas antes que cartones
  const rubAt = await page.$$eval('#cardsGrid .pc-rubro', xs => xs.map(e => e.textContent.trim()));
  ok(rubAt.join(' | ') === 'Sector Caja | Sector Cartón', 'prov. AT: un rotulo por rubro, cajas y despues cartones — ' + rubAt.join(' | '));
  ok(atCards.every(c => c.includes('Sugerido 0')),
     'prov. AT: todas las piezas vienen con sugerido 0 (la O.C. la hace Virgilio) — ' + atCards.join(' | '));
  ok(atCards.every(c => c.includes('paquetes')), 'prov. AT: cartones y cajas se mandan en paquetes — ' + atCards.join(' | '));
  await abrir('A1');
  const detAt = await det();
  ok(detAt.includes('Sugerido a enviar') && detAt.includes('Cantidad a enviar'),
     'prov. AT: la vista de la parte muestra el sugerido (0) y pide la cantidad — ' + detAt);
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'paquetes',
     'prov. AT: la cantidad se escribe en paquetes (de 25 la caja)');
  ok((await page.$eval(DQ, e => e.value)) === '', 'prov. AT: el campo arranca vacio');
  await page.fill(DQ, '2');
  await page.click('#btnVolverPartes');
  await cargarParte('C20', '3');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const regAt = await calls('tablet_registrar');
  const itsAt = regAt[regAt.length - 1].args.p.items;
  const itCaja = itsAt.find(i => i.comp_id === 456), itCart = itsAt.find(i => i.comp_id === 457);
  ok(itCaja && itCaja.cantidad === 50 && itCaja.unidad === 'uni',
     'prov. AT: 2 paquetes de caja se guardan como 50 cajas (uni) — ' + JSON.stringify(itCaja));
  ok(itCart && itCart.cantidad === 3000 && itCart.unidad === 'uni',
     'prov. AT: 3 paquetones de carton se guardan como 3.000 cartones (uni) — ' + JSON.stringify(itCart));

  // ── AJ Adhesivos manda por PAQUETES de 100: sugerido y cantidad EN paquetes, se guarda en pliegos ──
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("AJ Adhesivos")');
  const ajCards = await cards();
  ok(ajCards.length === 1 && ajCards[0].includes('Pliego 506') && ajCards[0].includes('Sin adhesivar'),
     'AJ: la parte es una tarjeta con su codigo y su descripcion — ' + ajCards[0]);
  ok(ajCards[0].includes('Sugerido 3 paquetes'),
     'AJ: sugerido 250 uni -> 3 paquetes (techo), en la unidad del proveedor — ' + ajCards[0]);
  await abrir('Pliego 506');
  const detAj = await det();
  ok(detAj.includes('Sugerido a enviar') && detAj.includes('3 paquetes') && detAj.includes('Cantidad a enviar'),
     'AJ: la vista de la parte muestra el sugerido en paquetes y el campo — ' + detAj);
  ok((await page.$eval(DQ, e => e.value)) === '',
     'AJ (P.S.): la cantidad NO viene precargada, la escribe la persona');
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'paquetes',
     'AJ: el campo dice que se escribe en paquetes');
  // NO hay atajo para copiar el sugerido al campo [usuario 2026-09-18: "no quiero que aparezca la
  // opcion de enviar sugerido"]: el unico boton de la vista es "Listo"
  const btnsDet = await page.$$eval('#detCard button', xs => xs.map(b => b.textContent.trim()));
  ok(btnsDet.join('|') === 'Listo', 'la vista de la parte no ofrece copiar el sugerido — ' + btnsDet.join(' | '));
  await page.fill(DQ, '3');
  await page.click('#btnVolverPartes');
  const ajCard2 = (await cards())[0];
  ok(ajCard2.includes('envía 3 paquetes') && (await page.$$eval('#cardsGrid .parte-card.cargada', xs => xs.length)) === 1,
     'AJ: al volver, la tarjeta muestra lo que se va a mandar y queda marcada — ' + ajCard2);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const regAj = await calls('tablet_registrar');
  const itAj = regAj[regAj.length - 1].args.p.items[0];
  ok(itAj.comp_id === 564 && itAj.cantidad === 300 && itAj.unidad === 'uni',
     'AJ: 3 paquetes se guardan como 300 pliegos (uni), no como paquetes — ' + JSON.stringify(itAj));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('3 paquetes')), 'AJ: el confirm resume en paquetes');

  // ── Hernandez Julio recibe PESADO: sugerido en bultos enteros + Cantidad (kg) con el bulto abajo ──
  // Desde el 2026-09-18 Julio NO tiene columna de bulto: sus bolsas/cajones salen como el renglon
  // chico de debajo del campo de kg, igual que en Ester y en los que van por el cajon de la pieza
  // [usuario: "esta bien que me lo ponga chiquito abajo, pero modifica hernandez julio asi quedan
  // todos asi"]. El bulto se calcula de los kg y ya no se corrige a mano.
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Hernandez Julio")');
  const juCards = await cards();
  // el sugerido se mira en BULTOS enteros (techo), no en kilos: 1000 uni / 750 por cajon -> 2
  ok(juCards.length === 2 && juCards[0].includes('A1') && juCards[0].includes('Sugerido 2 cajones'),
     'Julio metalica: sugerido 1000 uni -> 2 cajones (techo), sin kilos en la tarjeta — ' + juCards[0]);
  ok(juCards[1].includes('PA10B') && juCards[1].includes('Sugerido 5 bolsas'),
     'Julio plastica: sugerido 5000 uni -> 5 bolsas — ' + juCards[1]);
  ok(juCards.every(c => c.includes('sin cargar')), 'Julio: las dos tarjetas arrancan sin cargar (P.S.)');
  // v1.38.0: el P.S. tambien va por rubro [usuario 2026-09-28]: procesado antes que plasticas
  const rubJu = await page.$$eval('#cardsGrid .pc-rubro', xs => xs.map(e => e.textContent.trim()));
  ok(rubJu.join(' | ') === 'Sector Procesado | Sector Plástico', 'P.S.: un rotulo por rubro, en el orden del tallerista — ' + rubJu.join(' | '));
  // desde el 2026-09-18 (tarde) Julio vuelve a tener DOS campos, como todos los que se mandan
  // pesados: el bulto se ANOTA (no se calcula) y despues los kg [usuario: "tengo que poder poner
  // cajones primero y despues los kg"]. El renglon chico pasa a ser el CRUCE de los dos.
  await abrir('PA10B');
  const detJu = await det();
  ok(detJu.includes('Sugerido a enviar') && detJu.includes('5 bolsas') &&
     detJu.includes('Cantidad (bolsas)') && detJu.includes('Cantidad (kg)'),
     'Julio: la vista pide las bolsas Y los kg — ' + detJu);
  ok((await page.$eval(DQ, e => e.value)) === '' && (await page.$eval(DC, e => e.value)) === '',
     'Julio plastica: los dos campos arrancan vacios (P.S.: no se precarga)');
  ok((await page.$eval(DEQ, e => e.textContent.trim())) === '',
     'Julio: con el campo vacio el renglon del bulto no dice "= 0"');
  await page.fill(DC, '10');
  await page.fill(DQ, '21');
  ok((await page.$eval(DEQ, e => e.textContent.trim())) === '= 10,5 bolsas',
     'Julio plastica: 21 kg -> 10,5 bolsas, sin redondear — ' + (await page.$eval(DEQ, e => e.textContent.trim())));
  ok(!(await page.$eval(DEQ, e => e.classList.contains('mal'))),
     'Julio plastica: 10 bolsas contra 10,5 es medio envase, no avisa');
  await page.click('#btnVolverPartes');
  await abrir('A1');
  await page.fill(DC, '3');
  await page.fill(DQ, '82');
  ok((await page.$eval(DEQ, e => e.textContent.trim())) === '= 2,73 cajones',
     'Julio metalica: 82 kg -> 2,73 cajones, con decimales — ' + (await page.$eval(DEQ, e => e.textContent.trim())));
  await page.click('#btnVolverPartes');
  const juCards2 = await cards();
  ok(juCards2[0].includes('envía 82 kg') && juCards2[1].includes('envía 21 kg'),
     'Julio: las tarjetas muestran los kg cargados — ' + juCards2.join(' | '));
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const regJu = await calls('tablet_registrar');
  const itsJu = regJu[regJu.length - 1].args.p.items;
  ok(itsJu[0].comp_id === 80 && itsJu[0].cantidad === 82 && itsJu[0].unidad === 'kg' && itsJu[0].cajones === 3,
     'Julio metalica: viajan los KG y los cajones ANOTADOS — ' + JSON.stringify(itsJu[0]));
  ok(itsJu[1].comp_id === 231 && itsJu[1].cantidad === 21 && itsJu[1].unidad === 'kg' && itsJu[1].cajones === 10,
     'Julio plastica: 21 kg con las 10 bolsas anotadas — ' + JSON.stringify(itsJu[1]));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('82 kg (3 cajones)')),
     'Julio: el confirm resume las dos unidades');
  // ── Ester: el sugerido en BOLSAS de 1800 pero la cantidad EN KG, con las bolsas al lado ──
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Ester")');
  const esCard = (await cards())[0];
  ok(esCard.includes('PC2') && esCard.includes('Sugerido 63 bolsas'),
     'Ester: 112.432 mangos / 1800 -> 63 bolsas (techo) en la tarjeta — ' + esCard);
  await abrir('PC2');
  const detEs = await det();
  ok(detEs.includes('63 bolsas') && detEs.includes('Cantidad (bolsas)') && detEs.includes('Cantidad (kg)'),
     'Ester: el sugerido se mira en bolsas, y se anotan las bolsas Y los kg — ' + detEs);
  ok((await page.$eval(DQ, e => e.value)) === '',
     'Ester (P.S.): los kg NO vienen precargados con esas 63 bolsas, los escribe la persona');
  await page.fill(DC, '63');
  await page.fill(DQ, '612,36');
  ok((await page.$eval('#detCard .det-eq', e => e.textContent.trim())) === '= 63 bolsas',
     'Ester: debajo del campo dice a cuántas bolsas equivale lo tipeado');
  await page.fill(DQ, '100');
  ok((await page.$eval('#detCard .det-eq', e => e.textContent)).includes('10,29 bolsas'),
     'Ester: 100 kg / 9,72 = 10,29 bolsas, tal cual (usuario 2026-09-18) — ' +
     (await page.$eval('#detCard .det-eq', e => e.textContent.trim())));
  // y si no llega a un envase se dice el decimal, no una frase
  await page.fill(DQ, '3');
  ok((await page.$eval('#detCard .det-eq', e => e.textContent)).includes('0,31 bolsas'),
     'Ester: 3 kg = 0,31 bolsas, en numero y no en palabras — ' +
     (await page.$eval('#detCard .det-eq', e => e.textContent.trim())));
  await page.fill(DQ, '612,36');
  await page.click('#btnVolverPartes');
  ok((await cards())[0].includes('envía 612,36 kg') && (await cards())[0].includes('(63 bolsas)'),
     'Ester: la tarjeta muestra las dos unidades — ' + (await cards())[0]);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const regEs = await calls('tablet_registrar');
  const itEs = regEs[regEs.length - 1].args.p.items[0];
  ok(itEs.comp_id === 622 && itEs.cantidad === 612.36 && itEs.unidad === 'kg' && itEs.cajones === 63,
     'Ester: viaja el KG tal cual (la base lo pasa a mangos con kg_x_uni) y las 63 bolsas quedan anotadas — ' + JSON.stringify(itEs));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('612,36 kg (63 bolsas)')),
     'Ester: el confirm dice los kg y las bolsas');

  // ── Guazzaroni: el sugerido en CAJONES (el de cada pieza) y la cantidad en kg ──────
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Guazzaroni")');
  const gzCards = await cards();
  ok(gzCards[0].includes('Sugerido 1 caj\u00f3n'),
     'Guazzaroni: 34.992 remaches / 57.143 por cajón -> 1 cajón (techo, en singular) — ' + gzCards[0]);
  ok(gzCards[1].includes('113.304') && gzCards[1].includes('sin cajón cargado'),
     'Guazzaroni: la pieza sin uni_x_cajon NO se convierte, queda en unidades y lo dice — ' + gzCards[1]);
  ok(gzCards.every(c => c.includes('sin cargar')), 'Guazzaroni (P.S.): las tarjetas arrancan sin cargar');
  await page.click('#cardsGrid .parte-card:first-of-type');
  await page.waitForSelector(DQ);
  ok((await page.$eval('#detCard .det-eq', e => e.textContent.trim())) === '',
     'Guazzaroni: con el campo vacio la equivalencia no dice nada');
  await page.fill(DC, '4');
  await page.fill(DQ, '70');
  ok((await page.$eval('#detCard .det-eq', e => e.textContent.trim())) === '= 3,5 cajones',
     'Guazzaroni: los cajones van con decimales (70 kg / 20 = 3,5) — ' +
     (await page.$eval('#detCard .det-eq', e => e.textContent.trim())));
  await page.click('#btnVolverPartes');
  // la pieza sin cajon se carga en unidades, a mano como el resto
  await page.click('#cardsGrid .parte-card:nth-of-type(2)');
  await page.waitForSelector(DQ);
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'uni',
     'Guazzaroni: la pieza sin cajón se escribe en unidades, no en kg');
  ok((await page.$$eval('#detCard .det-eq', xs => xs.map(x => x.textContent.trim()))).join('') === '',
     'Guazzaroni: y no muestra equivalencia a cajones');
  await page.fill(DQ, '113.304');
  await page.click('#btnVolverPartes');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const regGz = await calls('tablet_registrar');
  const itsGz = regGz[regGz.length - 1].args.p.items;
  ok(itsGz[0].comp_id === 601 && itsGz[0].cantidad === 70 && itsGz[0].unidad === 'kg' && itsGz[0].cajones === 4,
     'Guazzaroni: viaja el KG y los 4 cajones ANOTADOS — ' + JSON.stringify(itsGz[0]));
  ok(itsGz[1].comp_id === 609 && itsGz[1].cantidad === 113304 && itsGz[1].unidad === 'uni' && itsGz[1].cajones === null,
     'Guazzaroni: la pieza sin cajón viaja en unidades, sin inventar factor — ' + JSON.stringify(itsGz[1]));

  // ── 3) modo RECIBIR: sin prov. AT, con Insumos que es un link ─────────────
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#modos .modo-btn[data-modo="recibir"]');
  ts = await tipos();
  ok(ts.length === 4 && !ts.join('|').includes('art. terminado'),
     'Recibir: 4 tipos y el prov. de art. terminado NO esta (entrega en Virgilio) — ' + ts.join(' | '));
  ok(ts.some(t => t.includes('Prov. de insumos')) && ts.some(t => t.includes('Virgilio')), 'Recibir: estan Insumos y Virgilio');
  const hrefInsumos = await page.$eval('#tipoGrid .tipo-btn[data-tipo="proveedor_insumo"]', a => a.getAttribute('href'));
  ok(hrefInsumos === '../StockFlejes/RecepcionInsumos_GP2.html?volver=tablet',
     'Insumos abre Recepcion Insumos (una sola copia del flujo) — ' + hrefInsumos);

  // Virgilio es una sola contraparte: se entra derecho a la carga
  await page.click('#tipoGrid .tipo-btn[data-tipo="virgilio"]');
  await page.waitForFunction(() => !document.getElementById('fase1').classList.contains('hidden'));
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Virgilio', 'un tipo con una sola contraparte entra derecho');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(rows.length === 1 && rows[0].includes('IC3V') && rows[0].includes('20 kg') && rows[0].includes('online Virgilio'),
     'Virgilio: IC3V con esperado 20 kg del online — ' + rows[0]);
  // Virgilio NO es tallerista ni P.S.: su columna sigue diciendo "Esperado" (el rotulo nuevo es
  // solo para los dos que el usuario nombro el 2026-09-21)
  ok((await page.$eval('#thead', e => e.textContent)).includes('Esperado'),
     'Virgilio: la columna sigue siendo Esperado — ' + (await page.$eval('#thead', e => e.textContent)));
  await page.click('#btnVolver');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  ok(true, 'volver desde un tipo de una sola contraparte cae en los tipos');

  // tallerista: en Recibir entregan Martin y el tallerista O.C. (Lucho tiene n_rec 0). EL O.C. NO
  // SE SEPARA AL RECIBIR [usuario 2026-09-23: "Solo en la version tablet dentro del modulo
  // enviar"]: no hay baldosa "Talleristas O.C." en Recibir y Carlos Aguirre sale acá adentro.
  ok(!(await tipos()).join('|').includes('O.C.'), 'Recibir: no hay baldosa de Talleristas O.C. — ' + (await tipos()).join(' | '));
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  let rTall = await page.$$eval('#cpGrid .prov-btn', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(rTall.length === 2 && rTall.some(b => b.startsWith('Carlos Aguirre')) && rTall.some(b => b.startsWith('Martin')),
     'Recibir: el tallerista O.C. entrega adentro de Talleristas, como cualquier otro — ' + rTall.join(' | '));
  await page.click('#cpGrid .prov-btn:has-text("Martin")');
  await page.waitForFunction(() => !document.getElementById('fase1').classList.contains('hidden'));
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Martin Cornejo',
     'en Recibir solo el tallerista que entrega algo (Lucho no), y el título no lleva el rótulo O.C.');
  ok(!(await page.$eval('#fRemito', e => e.classList.contains('hidden'))), 'en Recibir se pide el remito');
  // las partes tambien en TARJETAS, con ESPERADO y CANTIDAD en vez de sugerido y cantidad
  ok(await page.$eval('#tblWrap', e => e.classList.contains('hidden')),
     'Recibir de tallerista: tarjetas, no tabla');
  let rcards = await cards();
  ok(rcards.length === 4, 'Recibir: una tarjeta por pieza (4) — ' + rcards.length);
  const rDe = (cod) => rcards.find(c => c.startsWith(cod));
  // el rotulo del numero de referencia dice DE QUIEN es el stock [usuario 2026-09-21: "en vez de
  // esperado quiero que diga Stock tallerista o stock proveedor de servicio segun corresponda"]
  // EL REMITO DEL TALLERISTA TAMBIEN VA EN UNIDADES [usuario 2026-09-23: "Ahora seguimos con las
  // recepciones de talleristas. Lucho. Remito en unidades y control en kg y cajones"]: el cajon y
  // el kilo se cuentan en el control, no acá.
  ok(rDe('A11').includes('Una Armada') && rDe('A11').includes('Stock tallerista 1.000 uni'),
     'A11: el stock del tallerista se mira en UNIDADES, como el remito — ' + rDe('A11'));
  ok(!rDe('A11').includes('Esperado'), 'A11: ya no dice "Esperado" — ' + rDe('A11'));
  ok(!rDe('A11').includes('cajones') && !rDe('A11').includes('cajón'),
     'A11: el cajón no aparece en el remito (es del control) — ' + rDe('A11'));
  // sin stock la tarjeta dice 0, no queda en blanco [usuario 2026-09-21: "pero que me diga 0 si
  // no tiene stock"].
  ok(rDe('A12').includes('Stock tallerista 0 uni'),
     'A12: sin stock el numero es 0, no se deja en blanco — ' + rDe('A12'));
  ok(rDe('GRJ5').includes('Stock tallerista 360 uni'),
     'GRJ5: las bolsas de 120 tampoco mandan en el remito (360 uni) — ' + rDe('GRJ5'));
  // Y LA CUCHILLA, DEL MISMO TALLERISTA, VIENE PESADA: 4.004 uni x 0,00492 = 19,70 kg
  ok(rDe('X4').includes('Stock tallerista 19,7 kg'),
     'X4: la pieza con remito_unidad kg se mira en kilos — ' + rDe('X4'));
  await page.fill('#fRemito', 'R-0001');
  // y el 0 tambien se ve adentro de la parte, que es donde el numero va grande
  await abrir('A12');
  const detA12 = await det();
  ok(detA12.includes('Stock tallerista') && detA12.includes('0 uni'),
     'A12: la vista de la parte tambien dice 0, en unidades — ' + detA12);
  await page.click('#btnVolverPartes');
  await abrir('A11');
  const detA11 = await det();
  ok(detA11.includes('Stock tallerista') && detA11.includes('1.000 uni') && detA11.includes('Cantidad') &&
     !detA11.includes('Esperado') && !detA11.includes('Sugerido') && !detA11.includes('Recibido'),
     'A11: la vista dice Stock tallerista y Cantidad (no esperado, sugerido ni recibido) — ' + detA11);
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'uni',
     'A11: la cantidad del remito se escribe en unidades');
  // EL REMITO DEL TALLERISTA TAMPOCO SE JUZGA ACÁ [usuario 2026-09-23]: desde que el tallerista
  // tiene su control, cargar más de lo que la base cree que tiene no dispara ningún cartel. La
  // diferencia se mira en ControlEntregaPS, contra el remito.
  await page.fill(DQ, '1300');
  ok((await page.$$eval('#detCard .det-eq', ns => ns.map(n => n.textContent.trim()).join(''))) === '',
     'A11: en unidades no hay renglón de equivalencia (el cajón se cuenta en el control)');
  await page.click('#btnVolverPartes');
  rcards = await cards();
  ok(!/de m[aá]s/i.test((await cards()).find(c => c.startsWith('A11')) || ''),
     'tallerista: 1.300 contra 1.000 ya no es "de más" — el juicio va al control');
  ok(await page.$eval('#alertaBox', e => e.classList.contains('hidden')),
     'tallerista: tampoco aparece el cartel de "recibiendo más de lo esperado"');
  ok((await page.$eval('#btnEnviar', e => !e.disabled && e.textContent === 'Recibir (1)')), 'el boton Recibir sigue habilitado');

  dialogs.length = 0;
  await page.click('#btnEnviar');
  // DESPUÉS DEL REMITO VIENE EL CONTROL, también en el tallerista: la tablet se va sola a la
  // pantalla de control, igual que con el P.S. [usuario 2026-09-23].
  await page.waitForFunction(() => location.pathname.endsWith('ControlEntregaPS_GP2.html'));
  ok(true, 'tallerista: al registrar el remito la tablet manda al control');
  reg = await callsSS('tablet_registrar');
  p = reg[reg.length - 1].args.p;
  ok(p.modo === 'recibir' && p.tipo === 'tallerista' && p.ref === '6' && p.remito === 'R-0001', 'payload recibir con remito');
  const it = p.items[0];
  // viaja la UNIDAD de la pieza y el esperado en la misma unidad: la base los compara crudos. El
  // kilo y el cajón se cuentan en el control, no en el remito [usuario 2026-09-23].
  ok(it.comp_id === 71 && it.comp_entrada_id === 70 && it.cantidad === 1300 && it.unidad === 'uni' &&
     it.esperado === 1000 && it.esperado_origen === 'online_tall',
     'item tallerista: 1.300 uni contra 1.000 esperadas, mismo idioma — ' + JSON.stringify(it));

  // ── RECIBIR DE UN P.S.: tarjetas, y EL REMITO EN UNIDADES ──────────────
  // [usuario 2026-09-23, sobre cinco proveedores el mismo dia: "cuando voy a recibir de AJ adhesivos
  // el remito marca en unidades de pliego y despues cuando voy a controlar si, marco paquetes";
  // idem Ester, Hernandez Julio, Jade y Maspoli]. Lo que se carga aca es EL REMITO y va en unidades
  // de la pieza; el envase (bolsas, paquetes, cajones) y los kilos son del CONTROL, la pantalla
  // siguiente. Da vuelta la regla de v1.20.0, que es de antes de que el control existiera.
  // se vuelve del control con un goto: la recepcion del tallerista ya no termina en la fase
  // de exito, se va derecho a controlar [2026-09-23]
  await page.goto(ROOT + '/Tablet/Tablet_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#modos button').length > 0);
  await page.click('#modos button[data-modo="recibir"]');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Guazzaroni")');
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  ok(await page.$eval('#tblWrap', e => e.classList.contains('hidden')),
     'Recibir de P.S.: tarjetas, no tabla');
  const gzRec = (await cards())[0];
  ok(gzRec.includes('CV1N') && gzRec.includes('consume CV1'),
     'P.S.: la tarjeta dice la pieza y que SC consume — ' + gzRec);
  ok(gzRec.includes('Stock prov. de servicio 1.000 uni'),
     'Guazzaroni: el stock del P.S. se mira en UNIDADES, como el remito — ' + gzRec);
  ok(!gzRec.includes('Esperado'), 'Guazzaroni: ya no dice "Esperado" — ' + gzRec);
  ok(!gzRec.includes('cajones') && !gzRec.includes('cajón'),
     'Guazzaroni: en el remito no aparece el cajón (es del control) — ' + gzRec);
  // El cajón anotado por logística (ent_uxc_anot, 2026-09-21) sigue viajando en el bundle, pero ya
  // no decide nada acá: el remito va en unidades y el envase se mira en ControlEntregaPS.
  const gzAnot = (await cards()).find(c => c.includes('CV2N')) || '';
  ok(gzAnot.includes('Stock prov. de servicio 60.000 uni'),
     'Guazzaroni: el otro remache también en unidades — ' + gzAnot);
  // EN UN P.S. NO SE COMPARA CONTRA SU STOCK [usuario 2026-09-23: "esta alerta me tiene que
  // aparecer no a la hora de recibir, sino a la hora de hacer el control... puede haber 1.800
  // unidades de stock de proveedor de servicio y capaz recibo menos"]. Acá se carga el REMITO: una
  // entrega parcial —o una de más— no es una anomalía, y el juicio vive en ControlEntregaPS.
  await cargarParte('CV2N', '100000');   // 66 % más que las 59.999,85 que tiene en su poder
  const gzTol = (await cards()).find(c => c.includes('CV2N')) || '';
  ok(!/de m[aá]s/i.test(gzTol),
     'P.S.: la tarjeta no juzga el remito contra el stock del proveedor — ' + gzTol);
  ok(await page.$eval('#alertaBox', e => e.classList.contains('hidden')),
     'P.S.: y el cartel de "recibiendo más de lo esperado" tampoco aparece');
  await cargarParte('CV2N', '');
  await abrir('CV1N');
  const detPs = await det();
  ok(detPs.includes('Stock prov. de servicio') && detPs.includes('1.000 uni') && detPs.includes('Cantidad') &&
     !detPs.includes('Esperado') && !detPs.includes('Recibido'),
     'P.S.: la vista dice Stock prov. de servicio y Cantidad — ' + detPs);
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'uni',
     'Guazzaroni: la cantidad del remito se escribe en unidades');
  ok(await page.$eval('#accBox', e => e.classList.contains('hidden')),
     'Recibir: adentro de la parte tampoco se ve la Fecha, el Remito ni el boton de registrar');
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === true,
     'P.S.: con el campo vacio no se puede cerrar la parte');
  await page.fill(DQ, '1000');   // 1.000 uni = exactamente lo que el proveedor tiene en su poder
  ok((await page.$$eval('#detCard .det-eq', ns => ns.map(n => n.textContent.trim()).join(''))) === '',
     'Guazzaroni: en unidades no hay renglón de equivalencia (el envase se mira en el control)');
  // Y EL BOTON SE HABILITA CON LA CANTIDAD ESCRITA, aunque la parte lleve UNA sola unidad. Hasta el
  // 2026-09-21 el repintado del boton vivia adentro del if de las dos unidades, que en Recibir nunca
  // se cumple: la tarjeta se dibujaba con "Listo" gris y ahi se quedaba [usuario, con 40 kg ya
  // tipeados: "No me deja cargar la recepción"].
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === false,
     'Guazzaroni: con la cantidad escrita, Listo se habilita');
  await page.fill(DQ, '');
  ok((await page.$eval('#detCard button[data-a="listo"]', b => b.disabled)) === true,
     'Guazzaroni: y si se borra la cantidad se vuelve a deshabilitar');
  await page.fill(DQ, '1000');
  await page.click('#btnVolverPartes');
  ok((await cards())[0].includes('recibe'), 'P.S.: la tarjeta muestra lo que se va a recibir');
  await page.click('#btnEnviar');
  // RECIBIR DE UN P.S. TERMINA EN EL CONTROL [usuario 2026-09-21: "Despues de recepcionar tengo que
  // ir al control"]: lo que se acaba de registrar es el REMITO, y la tablet se va SOLA a la pantalla
  // de control (mismo criterio que la recepcion de insumos, que salta al control sin cartel). Por
  // eso aca ya no se espera la fase 3: se espera la navegacion.
  await page.waitForFunction(() => location.pathname.endsWith('ControlEntregaPS_GP2.html'));
  ok(true, 'Guazzaroni: al registrar el remito la tablet manda al control');
  // el payload se lee de sessionStorage porque window.__calls se lo llevo la navegacion
  const regPs = await callsSS('tablet_registrar');
  const itPs = regPs[regPs.length - 1].args.p.items[0];
  // viaja la UNIDAD de la pieza, y el esperado en la misma unidad, para que la base compare igual
  // contra igual. Los kilos son del control, que despues pisa la cantidad del movimiento.
  ok(itPs.comp_id === 601 && itPs.comp_entrada_id === 600 && itPs.cantidad === 1000 && itPs.unidad === 'uni' &&
     itPs.esperado === 1000,
     'Guazzaroni: 1.000 uni contra 1.000 uni esperadas — ' + JSON.stringify(itPs));

  // AJ tampoco es excepcion desde el 2026-09-23: su remito viene en pliegos (unidades), y los
  // paquetes de 200 con los que entrega se cuentan en el control.
  await page.goto(ROOT + '/Tablet/Tablet_GP2.html');   // volver del control (antes: "Cargar otra")
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("AJ Adhesivos")');
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  const ajRec = (await cards())[0];
  ok(ajRec.includes('Pliego Ad 506') && ajRec.includes('Stock prov. de servicio 600 uni'),
     'AJ: el remito va en pliegos (unidades), no en los paquetes de 200 de la entrega — ' + ajRec);
  await abrir('Pliego Ad 506');
  ok((await page.$eval('#detCard .det-uni', e => e.textContent.trim())) === 'uni',
     'AJ: la cantidad del remito se escribe en unidades');
  await page.fill(DQ, '600');
  await page.click('#btnVolverPartes');
  await page.click('#btnEnviar');
  // AJ tambien es un P.S.: al registrar el remito se va al control, igual que Guazzaroni
  await page.waitForFunction(() => location.pathname.endsWith('ControlEntregaPS_GP2.html'));
  const regAjR = await callsSS('tablet_registrar');
  const itAjR = regAjR[regAjR.length - 1].args.p.items[0];
  ok(itAjR.comp_id === 565 && itAjR.cantidad === 600 && itAjR.unidad === 'uni',
     'AJ: los 600 pliegos del remito viajan tal cual — ' + JSON.stringify(itAjR));

  // y un P.S. SIN unidad definida sigue como estaba: esperado y cantidad en la unidad de la pieza
  await page.goto(ROOT + '/Tablet/Tablet_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Blist-Pack")');
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  ok((await cards())[0].includes('Stock prov. de servicio 40 uni'),
     'P.S. sin unidad definida: el stock del P.S. queda en la unidad de la pieza — ' + (await cards())[0]);

  // ── 4) el CONTEO es el modulo de Relevamientos ──────────────────────────────
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  ok(await page.$eval('#modos .modo-btn.active', b => b.dataset.modo) === 'recibir', 'el modo se recuerda al recargar');
  const hrefConteo = await page.$eval('#modoConteo', a => a.getAttribute('href'));
  ok(hrefConteo === '../Relevamiento/Relevamiento_GP2.html?volver=tablet', 'Conteo abre Relevamientos — ' + hrefConteo);
  ok((await page.$$('#modos .modo-btn')).length === 3, 'siguen los tres modos arriba');

  // las dos pantallas que se abren desde acá devuelven el "Atrás" a la tablet
  for (const [url, vuelve] of [['/StockFlejes/RecepcionInsumos_GP2.html?volver=tablet', '../Tablet/Tablet_GP2.html?modo=recibir'],
                               ['/Relevamiento/Relevamiento_GP2.html?volver=tablet', '../Tablet/Tablet_GP2.html']]) {
    await page.goto(ROOT + url);
    await page.waitForSelector('#btnAtrasHeader');
    ok((await page.$eval('#btnAtrasHeader', a => a.getAttribute('href'))) === vuelve, 'con ?volver=tablet el Atrás vuelve a la tablet — ' + url.split('/')[1]);
  }

  // ── en un P.S. NADA sobrevive: ni lo que dejo la precarga vieja ni lo que anoto la persona
  //    [usuario 2026-09-18: "si cargue algo yo, cuando salgo quiero que desaparezca"] ──
  for (const [guardado, etiq] of [['250', 'el sugerido viejo que dejo la precarga'],
                                  ['2',   'lo que anoto la persona a mano']]) {
    await page.goto(ROOT + '/Tablet/Tablet_GP2.html?modo=enviar');
    await page.evaluate(q => localStorage.setItem('gp2_tablet_buffer',
      JSON.stringify({ 'enviar:proveedor_servicio:12': { '564::': { q: q } } })), guardado);
    await page.reload();
    await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
    await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
    await page.click('#cpGrid .prov-btn:has-text("AJ Adhesivos")');
    ok((await cards())[0].includes('sin cargar'),
       'AJ: ' + etiq + ' (' + guardado + ') no aparece, la tarjeta arranca sin cargar');
    await abrir('Pliego 506');
    ok((await page.$eval(DQ, e => e.value)) === '', 'AJ: y el campo de la vista tambien arranca vacio');
    await page.click('#btnVolverPartes');
    const bufAj = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_tablet_buffer') || '{}'));
    ok(!bufAj['enviar:proveedor_servicio:12'],
       'AJ: y tampoco queda en el buffer de la tablet — ' + JSON.stringify(bufAj));
  }
  // y lo que se tipea AHORA se olvida al salir de la contraparte (sin registrar)
  await cargarParte('Pliego 506', '4');
  ok((await page.$eval('#btnEnviar', e => e.textContent)) === 'Enviar (1)',
     'AJ: mientras la contraparte esta abierta, lo tipeado se usa (Enviar (1))');
  await page.click('#btnVolver');
  const bufSalida = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_tablet_buffer') || '{}'));
  ok(!bufSalida['enviar:proveedor_servicio:12'],
     'AJ: al salir con "← Cambiar" lo tipeado se borra — ' + JSON.stringify(bufSalida));
  await page.click('#cpGrid .prov-btn:has-text("AJ Adhesivos")');
  ok((await cards())[0].includes('sin cargar'),
     'AJ: al volver a entrar la tarjeta esta sin cargar, no con los 4 paquetes de antes');
  // y al TALLERISTA tampoco se le precarga ni se le guarda nada [usuario 2026-09-18: "igual que P.S."]
  await page.click('#btnVolver');        // vuelve a las contrapartes del tipo
  await page.click('#btnVolverTipo');    // y de ahi a los tipos
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  await page.click('#cpGrid .prov-btn:has-text("Martin")');
  ok((await cards()).every(c => c.includes('sin cargar')),
     'tallerista: las tarjetas arrancan sin cargar, ya no se precarga el sugerido');
  await cargarParte('A10', '30');
  await page.click('#btnVolver');
  const bufT = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_tablet_buffer') || '{}'));
  ok(!bufT['enviar:tallerista:6'], 'tallerista: al salir sin registrar no queda nada — ' + JSON.stringify(bufT));

  // ── 5) render a 390px ────────────────────────────────────────────────────
  await page.goto(ROOT + '/Tablet/Tablet_GP2.html?modo=enviar');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  // en Enviar ya no queda ninguna tabla (los cuatro destinos van en tarjetas): la tabla que se
  // mide es la de Recibir.
  await page.click('#modos .modo-btn[data-modo="recibir"]');
  await page.click('#tipoGrid .tipo-btn[data-tipo="virgilio"]');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);
  const m = await page.evaluate(() => {
    const ins = [...document.querySelectorAll('#tbody input.cell-in, #modos .modo-btn, #btnEnviar')];
    return {
      horizontal: document.documentElement.scrollWidth > window.innerWidth,
      altoMin: Math.min(...ins.map(i => i.getBoundingClientRect().height)),
      fuenteMin: Math.min(...[...document.querySelectorAll('#tbody input.cell-in')].map(i => parseFloat(getComputedStyle(i).fontSize))),
    };
  });
  ok(!m.horizontal, '390px: la pagina no scrollea horizontal');
  ok(m.altoMin >= 44, '390px: campos y botones tocables (' + Math.round(m.altoMin) + 'px, minimo 44)');
  ok(m.fuenteMin >= 19, '390px: letra grande en los campos de carga (' + m.fuenteMin + 'px)');

  // las TARJETAS de un P.S. a 390px: una columna, sin desborde, y la vista de la parte con la
  // letra grande que pide la casa (el campo de carga nunca baja de 19px)
  await page.click('#btnVolver');   // Virgilio es una sola contraparte: vuelve a los tipos
  await page.waitForFunction(() => !document.getElementById('tipoGrid').classList.contains('hidden'));
  await page.click('#modos .modo-btn[data-modo="enviar"]');
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Ester")');
  await page.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  const mc = await page.evaluate(() => {
    const cs = [...document.querySelectorAll('#cardsGrid .parte-card')];
    return { horizontal: document.documentElement.scrollWidth > window.innerWidth,
             alto: Math.min(...cs.map(c => c.getBoundingClientRect().height)),
             cod: parseFloat(getComputedStyle(cs[0].querySelector('.pc-cod')).fontSize) };
  });
  ok(!mc.horizontal, '390px (tarjetas): la pagina no scrollea horizontal');
  ok(mc.alto >= 44, '390px: las tarjetas son tocables (' + Math.round(mc.alto) + 'px)');
  ok(mc.cod >= 19, '390px: el codigo de la tarjeta se lee de lejos (' + mc.cod + 'px)');
  await abrir('PC2');
  const md = await page.evaluate(() => {
    const i = document.querySelector('#detCard input[data-f="q"]');
    const r = i.getBoundingClientRect();
    return { horizontal: document.documentElement.scrollWidth > window.innerWidth,
             alto: r.height, fuente: parseFloat(getComputedStyle(i).fontSize),
             im: i.getAttribute('inputmode') };
  });
  ok(!md.horizontal, '390px (vista de la parte): no scrollea horizontal');
  ok(md.alto >= 44 && md.fuente >= 19,
     '390px: el campo de la cantidad es grande y tocable (' + Math.round(md.alto) + 'px, ' + md.fuente + 'px de letra)');
  ok(md.im === 'decimal', '390px: y con teclado numerico (Ester carga en kg)');
  await page.click('#btnVolver');
  await page.click('#btnVolverTipo');

  // y los botones de TIPO tambien se tocan con el dedo
  await page.waitForFunction(() => !document.getElementById('tipoGrid').classList.contains('hidden'));
  const tMin = await page.$$eval('#tipoGrid .tipo-btn', xs => Math.min(...xs.map(x => x.getBoundingClientRect().height)));
  ok(tMin >= 44, '390px: los botones de tipo son tocables (' + Math.round(tMin) + 'px)');

  // ── 6) a lo ancho de una TABLET la tabla no se estira: columnas pegadas, sin blanco muerto ──
  // [usuario 2026-09-17: "optimizame todos los espacios en blanco que hay entre las columnas en
  // todas las pantallas de envio a ps en la version tablet"]. table.t viene a width:100%, asi que
  // sin el encogido el navegador repartia el sobrante y dejaba media pantalla de blanco entre la
  // pieza y su numero. Se mide en la tablet real (1280px), no a 390.
  const ctxT = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const pT = await ctxT.newPage();
  pT.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await pT.route('**/@supabase/supabase-js@2**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await pT.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  // Desde 2026-09-18 van en TARJETAS los cuatro destinos de Enviar y el tallerista en Recibir: la
  // tabla que queda viva es la del resto de Recibir, y es la que se mide aca (Virgilio, que ademas
  // tiene una sola contraparte y se entra derecho).
  for (const [modo, tipo, etiq] of [['recibir', 'virgilio', 'Virgilio (Recibir)']]) {
    await pT.goto(ROOT + '/Tablet/Tablet_GP2.html?modo=' + modo);
    await pT.evaluate(() => localStorage.clear());
    await pT.reload();
    await pT.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
    await pT.click('#tipoGrid .tipo-btn[data-tipo="' + tipo + '"]');
    await pT.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);
    const g = await pT.evaluate(() => {
      const t = document.querySelector('table.t').getBoundingClientRect();
      const paso = document.querySelector('.steps').getBoundingClientRect();
      const bus = document.querySelector('#q').closest('.search-box').getBoundingClientRect();
      // el blanco muerto ENTRE columnas = lo que la tabla mide de mas que su propio contenido
      // (max-content es el ancho al que las columnas quedan pegadas a lo que tienen adentro)
      const tab = document.querySelector('table.t');
      const prev = tab.style.width;
      tab.style.width = 'max-content';
      const ideal = Math.round(tab.getBoundingClientRect().width);
      tab.style.width = prev;
      return { tabla: Math.round(t.width), ideal: ideal, disponible: Math.round(paso.width), buscador: Math.round(bus.width) };
    });
    ok(g.tabla < g.disponible * 0.75, etiq + ': la tabla ocupa lo que necesita, no todo el ancho (' + g.tabla + ' de ' + g.disponible + 'px)');
    ok(g.tabla - g.ideal <= 4, etiq + ': las columnas quedan pegadas a su contenido, sin blanco repartido (' + g.tabla + ' vs ' + g.ideal + 'px de contenido)');
    ok(Math.abs(g.buscador - g.tabla) <= 4, etiq + ': el buscador mide lo mismo que la tabla (' + g.buscador + ' vs ' + g.tabla + 'px)');
  }
  // ── las TARJETAS de un P.S. en la tablet real: grilla de varias columnas, nada desbordado y
  //    tarjetas bien tocables. Se mide en Julio, que tiene dos partes. ──
  await pT.goto(ROOT + '/Tablet/Tablet_GP2.html?modo=enviar');
  await pT.evaluate(() => localStorage.clear());
  await pT.reload();
  await pT.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  // el inyector y no Julio: desde v1.38.0 el P.S. va en bloques por sector y las dos piezas de
  // Julio son de sectores distintos (dos bloques = dos filas a proposito); las resinas son un bloque
  await pT.click('#tipoGrid .tipo-btn[data-tipo="inyector"]');
  await pT.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  const gT = await pT.evaluate(() => {
    const cs = [...document.querySelectorAll('#cardsGrid .parte-card')].map(c => c.getBoundingClientRect());
    const paso = document.querySelector('.steps').getBoundingClientRect();
    return { horizontal: document.documentElement.scrollWidth > window.innerWidth,
             filas: new Set(cs.map(c => Math.round(c.top))).size, alto: Math.min(...cs.map(c => c.height)),
             ancho: Math.round(document.querySelector('#cardsGrid').getBoundingClientRect().width),
             disponible: Math.round(paso.width) };
  });
  ok(!gT.horizontal, '1280px (tarjetas): la pagina no scrollea horizontal');
  ok(gT.filas === 1, '1280px: las tarjetas se acomodan en columnas, no una abajo de la otra');
  ok(gT.alto >= 44, '1280px: las tarjetas son tocables (' + Math.round(gT.alto) + 'px)');
  ok(gT.ancho > gT.disponible * 0.9,
     '1280px: la grilla usa el ancho entero, no el de la tabla (' + gT.ancho + ' de ' + gT.disponible + 'px)');
  // EL TEXTO DE LA TARJETA NO SE PUEDE CORTAR CONTRA EL BORDE. Se mide a 1.280px, que es donde
  // la tarjeta es angosta (grilla de 230px), con la linea mas larga que produce la pantalla:
  // "Sugerido 113.304 uni · sin cajón cargado" de Guazzaroni. Se compara el ancho REAL del
  // texto (Range) contra el de su caja: con white-space:nowrap la caja mide bien y el texto se va
  // afuera igual, asi que scrollWidth no alcanza para verlo.
  await pT.click('#btnVolver');           // un solo inyector: vuelve a los tipos
  await pT.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await pT.click('#cpGrid .prov-btn:has-text("Guazzaroni")');
  await pT.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  const gzCorte = await pT.evaluate(() => Math.max(...[...document.querySelectorAll('#cardsGrid .parte-card span')]
    .map(x => { const r = document.createRange(); r.selectNodeContents(x);
                return r.getBoundingClientRect().width - x.getBoundingClientRect().width; })));
  ok(gzCorte <= 1,
     '1280px: el texto de la tarjeta baja de renglon, no queda cortado (desborde ' + Math.round(gzCorte) + 'px)');
  // el MISMO corte en RECIBIR, que desde el 2026-09-21 tiene el rotulo mas largo de la pantalla
  // ("Stock prov. de servicio"): va en su propio renglon chico, asi que tampoco se corta.
  await pT.click('#modos .modo-btn[data-modo="recibir"]');
  await pT.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await pT.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await pT.click('#cpGrid .prov-btn:has-text("Guazzaroni")');
  await pT.waitForFunction(() => document.querySelectorAll('#cardsGrid .parte-card').length > 0);
  const rec1280 = await pT.evaluate(() => {
    const corte = Math.max(...[...document.querySelectorAll('#cardsGrid .parte-card span')]
      .map(x => { const r = document.createRange(); r.selectNodeContents(x);
                  return r.getBoundingClientRect().width - x.getBoundingClientRect().width; }));
    const rot = document.querySelector('#cardsGrid .pc-sug .pc-rot');
    return { corte: corte, txt: rot && rot.textContent,
             bloque: rot && getComputedStyle(rot).display === 'block',
             chico: rot && parseFloat(getComputedStyle(rot).fontSize) <
                    parseFloat(getComputedStyle(rot.parentNode).fontSize) };
  });
  ok(rec1280.corte <= 1,
     '1280px (Recibir): "Stock prov. de servicio" tampoco corta la tarjeta (desborde ' +
     Math.round(rec1280.corte) + 'px)');
  ok(rec1280.txt === 'Stock prov. de servicio' && rec1280.bloque && rec1280.chico,
     'el rotulo va en su renglon y mas chico que el numero — ' + JSON.stringify(rec1280));
  // ── lo que quedo GUARDADO de otro dia no aparece en ningun destino de Enviar ────────────
  // Antes el tallerista precargaba el sugerido y esa precarga se refrescaba sola (firma qAuto).
  // Desde el 2026-09-18 no se precarga en ningun lado y el buffer se borra al entrar, asi que
  // tanto la precarga vieja como lo anotado a mano tienen que desaparecer igual.
  for (const [guardado, etiq] of [[{ q: '99', qAuto: '99' }, 'la precarga vieja'],
                                  [{ q: '77', qAuto: '99' }, 'lo anotado a mano']]) {
    await page.evaluate(g => {
      localStorage.setItem('gp2_tablet_buffer', JSON.stringify({ 'enviar:tallerista:6': { '70::': g } }));
    }, guardado);
    await page.reload();
    await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
    await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
    await page.click('#cpGrid .prov-btn:has-text("Martin")');
    ok((await cards()).find(c => c.startsWith('A10')).includes('sin cargar'),
       'tallerista: ' + etiq + ' de otro dia no aparece, la tarjeta arranca sin cargar');
  }
  // el mismo caso en un P.S.: la precarga firmada de otro día se BORRA y lo editado sobrevive
  await page.evaluate(() => {
    localStorage.setItem('gp2_tablet_buffer', JSON.stringify({
      'enviar:proveedor_servicio:20': { '90::': { q: '99', qAuto: '99' } }
    }));
  });
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Blist-Pack")');
  ok((await cards())[0].includes('sin cargar'),
     'P.S.: la precarga firmada de otro día se limpia, no se refresca');
  await page.evaluate(() => {
    localStorage.setItem('gp2_tablet_buffer', JSON.stringify({
      'enviar:proveedor_servicio:20': { '90::': { q: '77', qAuto: '99' } }
    }));
  });
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_servicio"]');
  await page.click('#cpGrid .prov-btn:has-text("Blist-Pack")');
  ok((await cards())[0].includes('sin cargar'),
     'P.S.: lo editado a mano tampoco sobrevive a la salida (usuario 2026-09-18)');

  // ── ➕ OTRO CARTÓN: mandar el de otro artículo cuando no hay stock del que va ────────────
  // [usuario 2026-09-21: "puede pasar de que no haya stock del cartón que quiero mandar y le mande
  // el cartón de otro artículo y se le pegue la etiqueta del artículo correspondiente. Entonces lo
  // tengo que modelar para que baje el stock del cartón que le mando realmente"]. Lo que se
  // registra es el cartón que SALE, con el oficial al que reemplaza al lado.
  const sustItems = () => page.$$eval('#detCard .sust-item', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  ok((await cardOtro()).length === 0,
     'P.S.: no hay "Otro cartón" (al prov. de servicio no se le manda cartón)');

  await page.click('#btnVolver');
  await page.click('#btnVolverTipo');
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  await page.click('#cpGrid .prov-btn:has-text("Martin")');
  // VA A LO ULTIMO DE LOS CARTONES, no al final de la grilla [usuario 2026-09-23]: con los bloques
  // por rubro, "al final" lo dejaba tres bloques abajo de los cartones. La tarjeta que le sigue ya
  // no es una pieza sino el rotulo del bloque siguiente.
  let sigOtro = await page.$eval('#cardsGrid .parte-card.otro', e => {
    const p = e.previousElementSibling, s = e.nextElementSibling;
    return { antes: p ? (p.querySelector('.pc-cod') || {}).textContent : null,
             despues: s ? s.className + '|' + s.textContent.trim() : null };
  });
  ok(sigOtro.antes && sigOtro.antes.indexOf('C10') === 0 &&
     sigOtro.despues && sigOtro.despues.indexOf('pc-rubro') === 0 && sigOtro.despues.includes('Bombilla'),
     'tallerista: "➕ Otro cartón" va a lo último de los cartones, con la bombilla después — ' + JSON.stringify(sigOtro));

  await page.click('#cardsGrid .parte-card.otro');
  await page.waitForSelector('#detCard .sust-item');
  let its = await sustItems();
  ok(its.length === 3 && its[0].includes('C55') && its[0].includes('7.000'),
     'el catálogo lista los cartones que NO usa, con el stock del sector — ' + its.join(' | '));
  ok(!its.join('|').includes('C10'), 'los suyos no están en el catálogo (esos ya tienen tarjeta)');
  await page.fill('#sustQ', 'sacacorchos');
  its = await sustItems();
  ok(its.length === 1 && its[0].includes('C55'), 'el buscador filtra el catálogo — ' + its.join(' | '));

  await page.click('#detCard .sust-item:has-text("C55")');
  await page.waitForSelector('#detCard .sust-item');
  its = await sustItems();
  ok(its.length === 2 && its.join('|').includes('C10') && its.join('|').includes('BANDITA') &&
     !its.join('|').includes('CJ7'),
     'el paso 2 pregunta a cuál reemplaza, y sólo con cartones (la caja no) — ' + its.join(' | '));

  await page.click('#detCard .sust-item:has-text("C10")');
  await page.waitForSelector(DQ);
  let d = await det();
  ok(d.includes('C55') && d.includes('en lugar de') && d.includes('C10'),
     'la vista de la parte dice qué cartón sale y a cuál reemplaza — ' + d);
  ok(d.includes('Online en el sector') && d.includes('7.000'),
     'el cartón de otro artículo no tiene sugerido: la referencia es el online del sector — ' + d);
  await page.fill(DQ, '2');
  await page.click('#btnVolverPartes');
  const tSust = (await cards()).find(c => c.includes('C55'));
  ok(tSust && tSust.includes('en lugar de C10') && tSust.includes('✓ envía 2 paquetes'),
     'la tarjeta queda cargada y marcada con el reemplazo — ' + tSust);

  await page.click('#btnEnviar');
  await page.waitForFunction(() => document.querySelector('#fase3') && !document.querySelector('#fase3').classList.contains('hidden'));
  let regS = (await calls('tablet_registrar')).slice(-1)[0].args.p;
  let itSust = regS.items.filter(i => i.comp_id === 800)[0];
  ok(itSust && itSust.cantidad === 2000 && itSust.unidad === 'uni',
     'viaja el cartón que SALE, en la unidad canónica (2 paquetes de 1.000) — ' + JSON.stringify(itSust));
  ok(itSust && itSust.sustituye_comp_id === 300,
     'y con el cartón OFICIAL al que reemplaza (C10 = 300) — sustituye_comp_id ' +
     (itSust ? itSust.sustituye_comp_id : '—'));
  ok(dialogs.slice(-1)[0].msg.includes('EN LUGAR DE C10'),
     'el confirm dice el reemplazo antes de registrar — ' + dialogs.slice(-1)[0].msg.replace(/\n/g, ' / '));

  // registrado, la fila agregada a mano no queda dando vueltas en la grilla
  await page.click('#btnOtro');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  await page.click('#cpGrid .prov-btn:has-text("Martin")');
  ok(!(await cards()).some(c => c.includes('C55')),
     'después de registrar, el cartón agregado a mano ya no está en la grilla');

  // PROV. DE ART. TERMINADO: mismo botón, y con un solo oficial del mismo tipo no pregunta nada
  await page.click('#btnVolver');
  await page.click('#btnVolverTipo');
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_at"]');
  ult = await ultimaCard();
  ok(ult && ult.otro, 'prov. AT: también tiene "➕ Otro cartón"');
  await page.click('#cardsGrid .parte-card.otro');
  await page.waitForSelector('#detCard .sust-item');
  await page.click('#detCard .sust-item:has-text("CJ9")');
  await page.waitForSelector(DQ);
  d = await det();
  ok(d.includes('CJ9') && d.includes('en lugar de') && d.includes('A1'),
     'con un solo oficial del mismo sector entra derecho, sin preguntar — ' + d);
  await page.fill(DQ, '3');
  await page.click('#btnVolverPartes');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => document.querySelector('#fase3') && !document.querySelector('#fase3').classList.contains('hidden'));
  regS = (await calls('tablet_registrar')).slice(-1)[0].args.p;
  itSust = regS.items.filter(i => i.comp_id === 810)[0];
  ok(itSust && itSust.cantidad === 75 && itSust.sustituye_comp_id === 456,
     'prov. AT: 3 paquetes de 25 cajas en lugar de A1 — ' + JSON.stringify(itSust));

  // ── EL BOTON CONTROL: solo en Recibir, y cuenta P.S. + talleristas + prov. de insumos ──
  // [Nazareno 2026-09-30: "Tendrias que poner los de talleristas, p.s. y prov de insumo. Ademas
  // quiero que este boton sea visible cuando estoy en el modulo recibir (lo que traen): si estoy en
  // enviar no quiero que aparezca"]
  await page.goto(ROOT + '/Tablet/Tablet_GP2.html?modo=enviar');
  await page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  ok(!(await page.isVisible('#lnkControl')), 'Enviar: el boton Control no aparece');
  await page.click('#modos .modo-btn[data-modo="recibir"]');
  await page.waitForFunction(() => document.getElementById('lnkControl').textContent === 'Control (3)');
  ok(await page.isVisible('#lnkControl'),
     'Recibir: aparece "Control (3)" = 1 de P.S. + 2 de Importado (los cartones, sin control, no suman)');
  await page.click('#modos .modo-btn[data-modo="enviar"]');
  ok(!(await page.isVisible('#lnkControl')), 'volver a Enviar lo esconde de nuevo');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
