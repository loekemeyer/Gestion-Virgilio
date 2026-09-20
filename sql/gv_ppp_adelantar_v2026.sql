-- ═══════════════════════════════════════════════════════════════════════════════════════
-- LA PAUTA PARA ADELANTAR TANDAS · v20.26 (2026-09-20)
--
-- Luis, 20/09, sobre los pedidos que ya pasaron los 10 días hábiles: *"tendría que marcar la
-- pauta para adelantar tandas"*. Es el punto 5 de su lógica — *"si hay más demora, o se
-- priorizan pedidos, o se trae más gente al depósito"* — y la decisión de priorizar es suya,
-- no del sistema: la vista MARCA, no mueve nada.
--
-- QUÉ MARCA
--   dias_habiles      · de fecha_recep hasta el día en que sale. No los transcurridos: los que
--                       va a tardar. Así avisa antes y no después.
--   estado            · TARDE (> 10) · AL LIMITE (9 o 10). Menos de 9 no aparece.
--   dia_ancla_antes   · el día ANTERIOR a su fecha en que ya va un camión a su zona. Es a dónde
--                       se la puede mover sin pagar un viaje nuevo.
--   dias_que_adelanta · cuántos días hábiles gana ese movimiento.
--   accionable        · todavía NO está armada Y hay camión antes. Lo que ya está armado sale
--                       igual: marcarlo no sirve para nada.
--
-- QUÉ DEJA AFUERA, A PROPÓSITO
--   · Los SÚPER. Luis, 19/09: *"Matiz es como un súper que se pide con mucha anticipación y
--     ellos definen la fecha de entrega"*. Sus 64 y 51 días hábiles (NP 97964 y 98426) no son
--     demora nuestra, y en la primera versión encabezaban la lista. Se filtran con gv_es_super
--     Y gv_es_super_np (una es NP de ISIS, la otra web) Y por zona, porque un súper puede venir
--     con zona numérica.
--   · Retira y expreso: la fecha la pone el cliente o el transporte.
--
-- ⚠ dia_ancla_antes dice que HAY CAMIÓN ese día, no que haya cupo. Mover la tanda es decisión
--   de armado y la toma Marianela (regla "QUIÉN ORGANIZA LA PROGRAMACIÓN" del CLAUDE.md).
--
-- Medido el 20/09: 37 NP TARDE (7,23 m³) y 48 AL LÍMITE (11,61 m³); 50 de las 85 accionables.
-- El peor accionable: LK 0066 (MRG Soluciones, zona 2, 0,082 m³) sale el 29/09 con 13 días
-- hábiles y hay camión a zona 2 el 21/09 — 6 días de adelanto por 82 litros.
-- ═══════════════════════════════════════════════════════════════════════════════════════

drop view if exists public.gv_ppp_adelantar;
create view public.gv_ppp_adelantar as
with d as (
  select d.fecha, d.np, d.np_num, d.empresa, d.origen, d.tanda, d.zona_corta, d.m3,
         d.razon_social, d.cod, d.pickeado, d.armado, d.facturado,
         coalesce(
           (select p.fecha_recep::date from public."PPP_Web_Programacion" p
             where lower(p.empresa) = lower(d.empresa) and p.np = d.np_num limit 1),
           (select g.fecha_recep::date from public."GV_PPP_Programacion_Diaria" g
             where g.np = d.np limit 1)) as fecha_recep
    from public.gv_ppp_detalle_dia d
   where d.fecha >= current_date
     and not public.gv_es_super(d.empresa, d.cod)
     and not public.gv_es_super_np(d.np, d.cod)
     and coalesce(d.zona_corta,'') !~* 'super|retira|expo'),
h as (
  select d.*, (select count(*) from generate_series(d.fecha_recep, d.fecha - 1, '1 day') x
                where public.gv_es_dia_habil(x::date)) as habiles
    from d where d.fecha_recep is not null),
a as (
  select h.*, (select min(x) from unnest(public.gv_ppp_web_dias_ancla(h.zona_corta, current_date + 1, 20)) x
                where x < h.fecha and x >= current_date + 1) as dia_ancla_antes
    from h)
select fecha as sale, np, tanda, zona_corta as zona, razon_social, cod, empresa, origen,
       round(m3, 3) as m3, fecha_recep, habiles as dias_habiles,
       case when habiles > 10 then 'TARDE'
            when habiles between 9 and 10 then 'AL LIMITE' end as estado,
       (coalesce(armado, false) = false and dia_ancla_antes is not null) as accionable,
       dia_ancla_antes,
       case when dia_ancla_antes is not null
            then (select count(*) from generate_series(dia_ancla_antes, fecha - 1, '1 day') x
                   where public.gv_es_dia_habil(x::date)) end as dias_que_adelanta,
       pickeado, armado, facturado
  from a
 where habiles >= 9
 order by (coalesce(armado,false) = false and dia_ancla_antes is not null) desc, habiles desc, m3 desc;

-- ⚠ sin esto la vista corre como postgres y saltea la RLS
alter view public.gv_ppp_adelantar set (security_invoker = true);
grant select on public.gv_ppp_adelantar to anon, authenticated, service_role;

-- chequeo
-- select estado, count(*), count(*) filter (where accionable) from public.gv_ppp_adelantar group by 1;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v20.28 (2026-09-20) — REVISIÓN: la pauta proponía días imposibles
--
-- Luis, 20/09: *"3 revisa"*. El repaso encontró que **las 36 recomendaciones apuntaban al
-- lunes 21**, o sea mañana, con el lunes ya 100 % armado y sin nada que pickear. Un pedido
-- "sin armar" no se pickea y se arma para el día siguiente: la vista buscaba el camión más
-- cercano sin mirar si había **tiempo de prepararlo** ni **cupo** ese día.
--
-- Dos columnas nuevas y un piso:
--   piso_real           · armado o pickeado → puede salir mañana; sin armar → 2.º día hábil
--                         (se pickea y arma un día, sale el siguiente).
--   lugar_libre_destino · el cupo que le queda al día propuesto, de `gv_ppp_dia_carga`.
--   accionable          · ahora exige las tres: no armada + hay camión antes + **entra en el
--                         cupo de ese día**.
--
-- LO QUE MOSTRÓ EL ARREGLO, y es el dato que importa: **de las 35 NP TARDE, 0 se pueden
-- adelantar.** 17 tienen camión a su zona antes, pero ese día no tiene cupo de picking. El
-- cuello no son los camiones: es el depósito. Con 1 picker (3,67 m³/día medidos) y 34,09 m³
-- por pickear en 10 días hábiles, la utilización es del **93 %**. No hay holgura para
-- adelantar nada, y un día de ausencia empuja todo.
--
-- Eso pone la decisión donde Luis la puso en su punto 5: *"o se priorizan pedidos, o se trae
-- más gente al depósito"*. El sistema ya no puede resolverlo solo.
-- ═══════════════════════════════════════════════════════════════════════════════════════
