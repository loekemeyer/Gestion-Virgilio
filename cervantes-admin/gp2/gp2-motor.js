"use strict";
/* ============================================================
   gp2-motor.js — el motor de GP2, extraido de la vieja pantalla
   Movimientos/Registrar_Movimiento.html (borrada 2026-08-30: sus dos
   flujos propios, Ajuste y Armado en fabrica, viven ahora en
   Stocks General/StockGeneral_GP2.html sobre este mismo motor) para
   que los modulos del menu usen LA MISMA logica y no una copia propia.

   Lee GP2.movimientos_bundle() y escribe con GP2.registrar_movimientos(jsonb).
   Los triggers fn_movimiento_calc / fn_movimiento_aplicar convierten a
   canonico y actualizan GP2.inventario: la app NO calcula stock.

   Uso:
     await GP2M.cargar(SB);
     var r = GP2M.recepcionTall({tall:6, comp_id:70, cantidad:50, fecha:'2026-08-28'});
     if (r.elegir) { ...preguntar cual de r.elegir... }
     else await GP2M.registrar(SB, r.rows);
   ============================================================ */

(function(global){

var D = null;
var UB = {};
var UBIC_VIRGILIO = null;
var SECTOR_TERMINADO = 12;   // los terminados NO pasan por recepcion de tallerista
var TALL_FABRICA = 3;

/* ---------- carga ---------- */
async function cargar(SB){
  var res = await SB.rpc("movimientos_bundle");
  if (res.error) throw res.error;
  D = res.data;
  for (var rid in D.rp) D.rp[rid].sort(function(a,b){ return a.o - b.o; });
  UB = {}; UBIC_VIRGILIO = null;
  for (var uid in D.ubic){
    var u = D.ubic[uid], id = parseInt(uid);
    if (u.tipo === "sector") UB["sector:" + u.ref] = id;
    else if (u.tipo === "proveedor_servicio") UB["prov:" + u.ref] = id;
    else if (u.tipo === "tallerista") UB["tall:" + u.ref] = id;
    else if (u.tipo === "virgilio") UBIC_VIRGILIO = id;
  }
  // Override: si un tallerista comparte depósito con otro actor (típicamente
  // un proveedor_servicio: Pedernera / Carlos Aguirre son el mismo taller),
  // tallerista.ubicacion_stock_id apunta a la ubi compartida. Se resuelve acá
  // para que todo el motor (ubicTall, envíos, stock) use esa ubi sin saber
  // que hubo redirección.
  if (D.tall){
    for (var tid in D.tall){
      var t = D.tall[tid];
      if (t && t.ubi_stock) UB["tall:" + parseInt(tid)] = parseInt(t.ubi_stock);
    }
  }
  return D;
}

/* ---------- lookups ---------- */
function comp(cid){ return (D && D.comp[String(cid)]) || { cod:"?", d:"" }; }
function sectorNom(sid){ return ((D && D.sect[String(sid)]) || { nom:"" }).nom; }
function ubicSector(s){ return UB["sector:" + parseInt(s)] || null; }
function ubicProvServ(p){ return UB["prov:" + parseInt(p)] || null; }
function ubicTall(t){ return UB["tall:" + parseInt(t)] || null; }

/* stock de un componente en una ubicacion, leido del inventario del bundle */
function stock(cid, ubicId){
  var k = String(cid) + ":" + String(ubicId);
  var i = (D && D.inv && D.inv[k]) || null;
  return i ? Number(i.cant || 0) : 0;
}

/* ---------- derivaciones sobre ruta_paso ----------
   Identicas a las de Registrar_Movimiento.html. */

/* La entrada efectiva de un paso: si el paso no declara comp_entrada,
   se hereda la salida del paso anterior que si la tenga. */
function entradaEfectiva(ps, i){
  var p = ps[i], j;
  if (p.ce) return p.ce;
  for (j = i - 1; j >= 0; j--) if (ps[j].cs) return ps[j].cs;
  for (j = i - 1; j >= 0; j--)
    if ((ps[j].tipo === "insumo" || ps[j].tipo === "ingreso") && ps[j].ce) return ps[j].ce;
  return null;
}

/* side 'para' = lo que se le manda; side 'de' = lo que devuelve. */
function compsFor(role, keyVal, side){
  var set = {};
  for (var rid in D.rp){
    var ps = D.rp[rid];
    for (var i = 0; i < ps.length; i++){
      var p = ps[i];
      var match = (role === "tall" && p.tipo === "tallerista" && p.tall == keyVal) ||
                  (role === "prov" && p.tipo === "proveedor_servicio" && p.prov == keyVal);
      if (!match) continue;
      if (side === "para"){ var ce = entradaEfectiva(ps, i); if (ce) set[ce] = 1; }
      else if (p.cs) set[p.cs] = 1;
    }
  }
  return Object.keys(set).map(Number);
}

/* Lo que un tallerista devuelve por recepcion de tallerista.
   Excluye los TERMINADOS: esos entran por Recepcion Virgilio.
   (mismo filtro que onTallRec() en Registrar_Movimiento.html) */
function compsRecepcionTall(t){
  return compsFor("tall", t, "de").filter(function(id){
    var c = D.comp[String(id)];
    return c && c.s !== SECTOR_TERMINADO;
  });
}

/* Las entradas que un tallerista pudo consumir para devolver cid.
   0 = paso in-place (devuelve lo mismo que recibe)
   1 = transformacion univoca
   >1 = hay que preguntar cual consumio (en Movimientos es un prompt) */
function entradasPosibles(t, cid){
  var hayInPlace = false;
  for (var rid in D.rp) D.rp[rid].forEach(function(pp){
    if (pp.tipo === "tallerista" && pp.tall == t && pp.cs == cid && pp.ce == cid) hayInPlace = true;
  });
  if (hayInPlace) return [];
  var set = {};
  for (var rid2 in D.rp){
    var ps = D.rp[rid2];
    for (var i = 0; i < ps.length; i++){
      var pp2 = ps[i];
      if (pp2.tipo === "tallerista" && pp2.tall == t && pp2.cs == cid){
        var ce = entradaEfectiva(ps, i);
        if (ce && ce !== cid) set[ce] = 1;
      }
    }
  }
  return Object.keys(set).map(Number);
}

/* Lo que se le descuenta al tallerista al recibir cid (sin la entrada principal) */
function bomDe(cid){ return (D.bom_comp && D.bom_comp[String(cid)]) || []; }

/* La entrada principal del movimiento, deducida — NO se le pregunta al usuario.
   Cuando un armado tiene varias "entradas posibles" en ruta_paso, esas no son
   alternativas: son TODAS las partes del armado, y el tallerista las consume a
   todas. El BOM ya dice cuales y en que cantidad, asi que alcanza con elegir
   una como principal (el resto sale por la cascada consumo_tall) y el neto es
   el mismo cualquiera sea la elegida. Se elige la de menor id para que el
   resultado sea estable entre corridas.
   Devuelve null si de verdad no se puede deducir (varias entradas y sin BOM). */
function entradaPrincipal(t, cid){
  var ces = entradasPosibles(t, cid);
  if (!ces.length) return null;            // in-place: devuelve lo mismo que recibe
  if (ces.length === 1) return ces[0];
  var bom = bomDe(cid);
  if (!bom.length) return null;            // ambiguo de verdad
  var enBom = ces.filter(function(id){
    return bom.some(function(b){ return b.c === id; });
  });
  var cand = enBom.length ? enBom : ces;
  return cand.slice().sort(function(a,b){ return a - b; })[0];
}

function talleristas(incFabrica){
  return Object.keys(D.tall)
    .filter(function(k){ return incFabrica || parseInt(k) !== TALL_FABRICA; })
    .map(function(k){ return { id: parseInt(k), nombre: D.tall[k].nom }; })
    .sort(function(a,b){ return a.nombre.localeCompare(b.nombre); });
}

/* Articulos que arma Cervantes directo (ninguna ruta suya pasa por un
   tallerista externo). Identico a artsFabricaDirecto() de Registrar_Movimiento. */
function artsFabricaDirecto(){
  var arts = {};
  for (var rid in D.rp){
    var ps = D.rp[rid];
    var t = ps.some(function(p){ return p.tipo === "tallerista" && p.tall && p.tall != TALL_FABRICA; });
    if (t) continue;
    ps.forEach(function(p){
      if (p.tipo === "virgilio" && p.ce){
        var c = D.comp[String(p.ce)];
        if (c && c.s === SECTOR_TERMINADO) arts[p.ce] = 1;
      }
    });
  }
  return Object.keys(arts).map(Number);
}

/* Ubicaciones donde un componente puede tener stock: su sector + cada
   tallerista/PS/Virgilio que lo recibe segun ruta_paso (para el Ajuste).
   Identico a ubicsDeComp() de Registrar_Movimiento. */
function ubicacionesDeComp(cid){
  var set = {}; var c = D.comp[String(cid)] || {};
  if (c.s && ubicSector(c.s)) set[ubicSector(c.s)] = 1;
  for (var rid in D.rp) D.rp[rid].forEach(function(p){
    if (p.ce != cid) return;
    if (p.tipo === "tallerista" && p.tall){ var u = ubicTall(p.tall); if (u) set[u] = 1; }
    else if (p.tipo === "proveedor_servicio" && p.prov){ var u2 = ubicProvServ(p.prov); if (u2) set[u2] = 1; }
    else if (p.tipo === "virgilio" && UBIC_VIRGILIO) set[UBIC_VIRGILIO] = 1;
  });
  return Object.keys(set).map(Number).filter(function(u){ return D.ubic[String(u)]; });
}

/* ---------- constructor: ajuste de inventario (+/-) ----------
   Mismo payload que el tipo 'ajuste' de Registrar_Movimiento: una sola fila
   con destino en la ubicacion elegida; el trigger aplica el delta. */
function ajuste(o){
  var cid = parseInt(o.comp_id), u = parseInt(o.ubic_id), q = Number(o.cantidad);
  if (!cid) throw new Error("Falta el componente");
  if (!u) throw new Error("Falta la ubicación");
  if (!q) throw new Error("La cantidad no puede ser 0");
  return { rows: [{
    tipo: "ajuste", fecha: o.fecha || null, comp_id: cid,
    ubic_origen_id: null, ubic_destino_id: u, cantidad: q,
    comp_transformado_id: null, cantidad_transformada: null,
    unidad_origen: "uni", unidad_destino: "uni"
  }] };
}

/* ---------- constructor: armado en fabrica ----------
   Consume el BOM del articulo (consumo_prod desde el sector de cada parte)
   y crea el terminado en la ubicacion de Fabrica. Identico al tipo
   'armado_fabrica' de Registrar_Movimiento. */
function armadoFabrica(o){
  var cid = parseInt(o.comp_id), qty = Number(o.cantidad), fecha = o.fecha || null;
  if (!cid) throw new Error("Falta el artículo");
  if (!(qty > 0)) throw new Error("Las unidades deben ser mayores a 0");
  var rows = [];
  var art_id = (D.c2a && D.c2a[String(cid)]) || cid;
  var bomA = (D.bom_art && D.bom_art[String(art_id)]) || [];
  bomA.forEach(function(b){
    var qC = Math.round(b.q * qty * 100) / 100;
    var c = D.comp[String(b.c)] || {};
    var ubic_c = c.s ? ubicSector(c.s) : null;
    rows.push({
      tipo: "consumo_prod", fecha: fecha, comp_id: b.c,
      ubic_origen_id: ubic_c, ubic_destino_id: null, cantidad: qC,
      comp_transformado_id: null, cantidad_transformada: null,
      unidad_origen: "uni", unidad_destino: "uni"
    });
  });
  rows.push({
    tipo: "armado_fabrica", fecha: fecha, comp_id: cid,
    ubic_origen_id: null, ubic_destino_id: ubicTall(TALL_FABRICA), cantidad: qty,
    comp_transformado_id: null, cantidad_transformada: null,
    unidad_origen: "uni", unidad_destino: "uni"
  });
  return { rows: rows };
}

/* ---------- constructor de movimientos: recepcion de tallerista ----------
   Reproduce el bloque tipo==='entrega_tallerista' (ex recepcion_tall) de saveMov().

   Devuelve { rows:[...] } listo para registrar, o
            { elegir:[comp_ids] } cuando el componente recibido puede venir
            de mas de una entrada y hay que preguntar cual consumio.        */
function recepcionTall(o){
  var t = parseInt(o.tall);
  var cid = parseInt(o.comp_id);
  var qty = Number(o.cantidad);
  var fecha = o.fecha || null;
  var rows = [];

  if (!t) throw new Error("Falta el tallerista");
  if (!cid) throw new Error("Falta el componente");
  if (!(qty > 0)) throw new Error("La cantidad debe ser mayor a 0");

  var recibido = cid;
  var comp_transformado = null, cant_transformada = null;

  // ¿el tallerista devuelve el MISMO componente que recibe? (paso in-place)
  var hayInPlace = false;
  for (var rid in D.rp) D.rp[rid].forEach(function(pp){
    if (pp.tipo === "tallerista" && pp.tall == t && pp.cs == cid && pp.ce == cid) hayInPlace = true;
  });

  // si no, buscar que entrada consumio para producirlo
  var ce_set = {};
  if (!hayInPlace){
    for (var rid2 in D.rp){
      var ps = D.rp[rid2];
      for (var i = 0; i < ps.length; i++){
        var pp2 = ps[i];
        if (pp2.tipo === "tallerista" && pp2.tall == t && pp2.cs == cid){
          var ce_c = entradaEfectiva(ps, i);
          if (ce_c && ce_c !== cid) ce_set[ce_c] = 1;
        }
      }
    }
  }
  var ce_arr = Object.keys(ce_set).map(Number);

  /* No se pregunta cual consumio: se deduce. Varias entradas en un armado no
     son alternativas, son todas sus partes, y el BOM las descuenta igual. */
  var elegida = null;
  if (o.comp_entrada_id && ce_arr.indexOf(parseInt(o.comp_entrada_id)) >= 0){
    elegida = parseInt(o.comp_entrada_id);        // override explicito, si lo pasan
  } else if (ce_arr.length === 1){
    elegida = ce_arr[0];
  } else if (ce_arr.length > 1){
    elegida = entradaPrincipal(t, recibido);
    if (elegida == null) return { elegir: ce_arr };   // ambiguo de verdad: sin BOM
  }
  if (elegida != null){
    cid = elegida; comp_transformado = recibido; cant_transformada = qty;
  }

  var ubic_o = ubicTall(t);
  var ubic_d = ubicSector(comp(comp_transformado || cid).s);
  if (!ubic_o) throw new Error("El tallerista no tiene ubicación");
  if (!ubic_d) throw new Error("El componente no tiene ubicación de sector");

  // cascada BOM: lo demas que el tallerista consumio se le descuenta
  if (comp_transformado){
    var bom = D.bom_comp[String(comp_transformado)] || [];
    var used = cid;
    var principal = bom.filter(function(b){ return b.c === used; })[0];
    // Guard invertido: las demas lineas del BOM multiplican SIEMPRE por su q, pero la
    // principal solo lo hacia si q > 1. Hoy zafa porque el unico caso distinto de 1 es
    // GRJ10/GRJ10A -> IE4 x3, pero apenas se cargue un BOM con q fraccionario (una
    // entrada que rinde dos salidas, q = 0,5) la recepcion consumiria el DOBLE de esa
    // entrada. Con q > 0 el caso q = 1 sigue dando lo mismo.
    if (principal && principal.q > 0) qty = qty * principal.q;
    bom.forEach(function(b){
      if (b.c === used) return;
      rows.push({
        tipo: "consumo_tall", fecha: fecha, comp_id: b.c,
        ubic_origen_id: ubic_o, ubic_destino_id: null,
        cantidad: b.q * cant_transformada,
        comp_transformado_id: null, cantidad_transformada: null,
        unidad_origen: "uni", unidad_destino: "uni"
      });
    });
  }

  rows.push({
    tipo: "entrega_tallerista", fecha: fecha, comp_id: cid,
    ubic_origen_id: ubic_o, ubic_destino_id: ubic_d,
    cantidad: qty,
    comp_transformado_id: comp_transformado, cantidad_transformada: cant_transformada,
    unidad_origen: "uni", unidad_destino: "uni"
  });

  return { rows: rows };
}

/* ---------- escritura ---------- */
async function registrar(SB, rows){
  if (!rows || !rows.length) throw new Error("No hay movimientos para registrar");
  var payload = rows.map(function(m){
    return {
      fecha: m.fecha ? (m.fecha + "T12:00:00") : null,
      tipo_mov: m.tipo,
      comp_id: m.comp_id == null ? null : m.comp_id,
      ubic_origen_id: m.ubic_origen_id == null ? null : m.ubic_origen_id,
      ubic_destino_id: m.ubic_destino_id == null ? null : m.ubic_destino_id,
      cantidad: m.cantidad,
      unidad_origen: m.unidad_origen || "uni",
      comp_transformado_id: m.comp_transformado_id == null ? null : m.comp_transformado_id,
      cantidad_transformada: m.cantidad_transformada == null ? null : m.cantidad_transformada,
      unidad_destino: m.unidad_destino || "uni",
      cajones: m.cajones == null ? null : m.cajones,
      faltante: !!m.faltante
    };
  });
  var res = await SB.rpc("registrar_movimientos", { p_rows: payload });
  if (res.error) throw res.error;
  return res.data;
}

/* Se exporta solo lo que alguna pantalla llama (StockGeneral_GP2,
   EntregasTalleristas_GP2). Lo interno del motor (ubicSector, ubicProvServ,
   entradaEfectiva, compsFor, entradaPrincipal, SECTOR_TERMINADO, el bundle D)
   dejo de exportarse el 2026-09-04: nadie lo llamaba de afuera. */
global.GP2M = {
  cargar: cargar,
  registrar: registrar,
  comp: comp,
  sectorNom: sectorNom,
  ubicTall: ubicTall,
  stock: stock,
  compsRecepcionTall: compsRecepcionTall,
  entradasPosibles: entradasPosibles,
  bomDe: bomDe,
  talleristas: talleristas,
  recepcionTall: recepcionTall,
  artsFabricaDirecto: artsFabricaDirecto,
  ubicacionesDeComp: ubicacionesDeComp,
  ajuste: ajuste,
  armadoFabrica: armadoFabrica
};

})(window);
