-- v20.63 — Centinela: el destino dice RETIRA y el pedido va en camion (o al reves)
-- Problema 470. Pedido de Thomas, 2026-09-21.
--
-- QUE PASO
-- Iro Iro SRL (cod 4223, NP 98626/98627, tandas E39A/E40A) figuraba como RETIRA en la PPP
-- mientras se repartia en camion a Burgwardt 903, Longchamps (Zona 4 - GBA Sur), ya facturado
-- el 16/09 con salida el 17/09. La ficha de entrega de LK tenia, EN LA MISMA FILA, la etiqueta
-- y la direccion del domicilio real y el modo de envio viejo:
--     etiqueta / direccion / zona_expreso -> Burgwardt 903 · Longchamps
--     nombre_expreso / direccion_expreso  -> Retira · "Virgilio 2788, Retira"
-- gv_np_destino publica nombre_expreso como `expreso`, asi que el badge decia "Retira · CABA".
-- Mismo arrastre en Osa Distribuidora (2533), 1435 (Moreno) y 4111 (Constitucion): los tres
-- tienen ADEMAS su fila de retiro legitimo aparte, lo que confirma que en la fila con barrio el
-- "Retira" era resto y no condicion. Los datos se limpiaron el 21/09 (ver el problema 470).
--
-- POR QUE ESTE ARCHIVO
-- Limpiar el dato sin centinela es cambiar un error que se ve por uno que no se ve. La regla del
-- repo: el tapon va junto con la forma nueva de enterarse.
--
-- QUE MIRA, Y POR QUE ESAS DOS FUENTES
--   gv_np_prog_reparto.es_retira -> como se esta REPARTIENDO de verdad (zona de la programacion)
--   gv_np_destino.expreso        -> lo que se MUESTRA como destino (nombre_expreso del padron)
-- Si las dos no dicen lo mismo, una esta mal. Vacia = todo bien.
--
-- GRANTS: solo service_role, calcado de gv_destino_sin_provincia. Cuelga de gv_np_destino, que
-- anon no puede leer: con SELECT abierto contestaria "vacia" por RLS, o sea mentiria diciendo
-- que todo esta bien. Un centinela que no puede ver nada no puede avisar nada.

create or replace view public.gv_retira_contradictorio as
with _rc as (
  select r.np, r.origen, r.zona, r.tanda, r.direccion, r.barrio, r.es_retira, r.m3,
         d.empresa, d.cod, d.expreso, d.como, d.provincia, d.localidad_destino
    from public.gv_np_prog_reparto r
    join public.gv_np_destino d on d.np = r.np
   where d.programada
)
select np, origen, empresa, cod, zona, tanda, m3, direccion, barrio,
       expreso, como, provincia, localidad_destino,
       case when not es_retira then 'DESTINO RETIRA EN ZONA DE REPARTO'
            else 'PROGRAMADA RETIRA PERO LA FICHA MANDA POR EXPRESO' end as problema,
       case when not es_retira
            then 'va en camion a ' || zona || ' y el badge de destino dice Retira: nombre_expreso viejo en la direccion del padron (GV_Clientes_Direcciones / customer_delivery_addresses de LK)'
            else 'la zona dice Retira y la ficha manda por el expreso ' || coalesce(expreso,'') || ': una de las dos esta mal'
       end as detalle
  from _rc
 where (not es_retira and coalesce(expreso,'') ~* '^retira$')
    or (es_retira and coalesce(expreso,'') <> '' and coalesce(expreso,'') !~* '^retira$');

alter view public.gv_retira_contradictorio set (security_invoker = true);
revoke all on public.gv_retira_contradictorio from anon, authenticated;

comment on view public.gv_retira_contradictorio is
  'Centinela (v20.63): NP programada cuyo destino y cuya zona se contradicen sobre el retiro. Vacia = todo bien. Nace del problema 470 (Iro Iro 4223 y Osa 2533 mostraban Retira mientras iban en camion). Solo service_role: cuelga de gv_np_destino, que anon no puede leer.';

-- que no le saquen el corazon en un CREATE OR REPLACE
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_retira_contradictorio','vista','es_retira',
        'El centinela compara el destino que se MUESTRA (gv_np_destino.expreso) contra como se esta REPARTIENDO de verdad (gv_np_prog_reparto.es_retira). Si se le saca ese cruce deja de ver el caso del problema 470: un pedido que va en camion con el badge Retira por nombre_expreso viejo en el padron.',
        'Thomas','v20.63')
on conflict do nothing;

-- ── CHEQUEO ────────────────────────────────────────────────────────────────────
-- select * from public.gv_retira_contradictorio;   -- vacia = todo bien
-- select * from public.gv_retira_sin_etiqueta;     -- el otro lado: retiro que no se ve
-- select * from public.gv_reglas_perdidas;         -- vacia = la regla sigue en la vista
--
-- ── COMO SE PROBO (21/09, las dos ramas) ───────────────────────────────────────
-- Leer la vista no prueba nada. Se inyecto el dato sucio en el padron derivado de Gestion
-- (GV_Clientes_Direcciones, que el sync de LK reescribe, nunca en la madre de LK) y se revirtio:
--   update public."GV_Clientes_Direcciones" set nombre_expreso='Retira'
--    where empresa='lk' and cod='4223';                  -- rama A
--   -- caza 98626 y 98627: DESTINO RETIRA EN ZONA DE REPARTO, Zona 4 - GBA Sur
--   update public."GV_Clientes_Direcciones" set nombre_expreso='__PRUEBA_EXPRESO__'
--    where empresa='lk' and cod='2533' and etiqueta ilike '%Zuviria%';   -- rama B
--   -- caza LK 0024 (zona Retira): PROGRAMADA RETIRA PERO LA FICHA MANDA POR EXPRESO
--   update public."GV_Clientes_Direcciones" set nombre_expreso=null
--    where nombre_expreso='__PRUEBA_EXPRESO__';           -- revertido, centinela en 0
--
-- ── POR QUE NO MARCA EL TERCER CASO ────────────────────────────────────────────
-- Una NP con zona Retira cuyo destino no resuelve NINGUN expreso (expreso null) NO se marca:
-- al 21/09 son 7 (LK 0011, 0024, 0067, 0097, 0143, 0144, 0157) y la zona ya dice Retira, asi que
-- no falta ningun dato operativo. Un centinela que nace en rojo no lo mira nadie.
--
-- ── ALCANCE MEDIDO AL 21/09 ────────────────────────────────────────────────────
-- 331 NP programadas, 0 en cada rama. En el padron de LK, de 140 direcciones con
-- nombre_expreso='Retira' quedan 136 (las 4 sucias se limpiaron) y 128 tienen tambien
-- zona_expreso='Retira', que es el retiro real.
