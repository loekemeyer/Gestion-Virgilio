-- v21.23 — 544 y 560 pasan a Pedernera en OC_Maximos (Luis, 2026-09-22)
--
-- Luis, textual: "si, corregí 544 y 560 a Pedernera".
--
-- Contexto: `OC_Maximos.proveedor` dice QUIEN FABRICA (regla del dueno del 15/09,
-- caso Oscar: "dejalo ahi"). Para los tres fabricantes de `GV_OC_Fabrica_Para`
-- la OC se EMITE a `Log/ Fabr` — eso ya lo resuelve `gv_oc_emite_a()` (v21.22),
-- no el campo `proveedor`.
--
-- Lo que estaba mezclado: de los 7 codigos que fabrica Pedernera, la config decia
-- `Pedernera` en 5 (115, 561, 800, 801, 802) y `Log/ Fabr` en 2 (544, 560).
-- Medido el 22/09 sobre entregas desde el 01/06: Pedernera entrego 115, 544, 560
-- y 802 — o sea que los dos que decian `Log/ Fabr` son suyos igual.
--
-- Backup: zz_backups."GV_Backup_OCMaximos_20260922"  (clave: cod, unica — 360/360)
--
--   create table zz_backups."GV_Backup_OCMaximos_20260922" as
--     select * from public."OC_Maximos";
--   alter table zz_backups."GV_Backup_OCMaximos_20260922" enable row level security;
--   revoke insert, update, delete, truncate
--     on zz_backups."GV_Backup_OCMaximos_20260922" from anon, authenticated;

update public."OC_Maximos" set proveedor = 'Pedernera'
 where regexp_replace(upper(btrim(cod)), '^0+(.)', '\1') in ('544', '560');
-- 2 filas

-- verificacion: los 7 codigos de Pedernera dicen Pedernera en la config,
-- y la OC de los 7 se emite igual a Log/ Fabr.
select m.cod, m.proveedor, public.gv_oc_emite_a(m.proveedor) emite_a
  from public."OC_Maximos" m
 where regexp_replace(upper(btrim(m.cod)), '^0+(.)', '\1')
       in ('115','544','560','561','800','801','802')
 order by 1;
-- 7 filas: proveedor = Pedernera, emite_a = Log/ Fabr

-- rollback:
--   update public."OC_Maximos" m set proveedor = b.proveedor
--     from zz_backups."GV_Backup_OCMaximos_20260922" b
--    where b.cod = m.cod and m.cod in ('544','560');

------------------------------------------------------------------------------
-- El BARRIDO limpio: que OTROS pares (OC a uno, entrega otro) quedan sin imputar
------------------------------------------------------------------------------
-- Luis: "2 cuales son? Que tiene que ver basconia???"
--
-- ⚠ El barrido anterior ("25 pares") estaba CONTAMINADO: cruzaba por NUMERO de
-- codigo, y Basconia compra ACERO EN KILOS (rubro Flejes, unidad Kg) con codigos
-- que chocan con los de articulo terminado — su `0635` es "Arandela Gde/Chica
-- Afila (77 x 1,25)", no el articulo 635. Basconia tiene UNA sola tanda, del
-- 13/07, 10 lineas, 7.650 Kg, y CERO entregas en `Entregas Tallerista Virgilio`:
-- no entra en esto por ningun lado.
--
-- El barrido que vale filtra rubro = 'Art Term' y unidad = 'Cajas', y deja afuera
-- los alias que `gv_prov_match` ya resuelve (Martin C = Martin, Carlos E = Carlos,
-- Pettofrezza = Rafael) y los tres fabricantes de `GV_OC_Fabrica_Para`.
--
-- Resultado al 22/09: **22 pares, 19 codigos, 4.654 cajas de OC sin imputar**.
-- Luis: "2 no necesariamente, tengo que ver caso x caso" → NO se toca ninguno.

with oc as (
  select public.gv_norm_prov_key(o.proveedor) pk_oc, o.proveedor prov_oc,
         regexp_replace(upper(btrim(o.codigo)),'^0+(.)','\1') cod,
         sum(o.cantidad) cajas_oc, count(*) n_oc, max(o.fecha::date) ult_oc
    from public."Ordenes_Compra" o
   where o.rubro = 'Art Term' and o.unidad = 'Cajas'
     and coalesce(o.cantidad_recibida,0) = 0
     and o.fecha >= date '2026-07-01'
   group by 1,2,3),
ent as (
  select public.gv_norm_prov_key(e."Nombre_Tall") pk_ent, e."Nombre_Tall" prov_ent,
         regexp_replace(upper(btrim(e."Cod")),'^0+(.)','\1') cod,
         sum(e."Cajas") cajas_ent, max(e."Fecha"::date) ult_ent
    from public."Entregas Tallerista Virgilio" e
   where e."Fecha" >= '2026-07-01'
   group by 1,2,3),
cfg as (
  select regexp_replace(upper(btrim(m.cod)),'^0+(.)','\1') cod, m.proveedor prov_cfg
    from public."OC_Maximos" m)
select oc.cod, oc.prov_oc oc_a, ent.prov_ent entrega, cfg.prov_cfg config,
       oc.cajas_oc, oc.n_oc, oc.ult_oc, ent.cajas_ent, ent.ult_ent,
       case when public.gv_norm_prov_key(coalesce(cfg.prov_cfg,'')) = ent.pk_ent
              then 'config = el que ENTREGA'
            when public.gv_norm_prov_key(coalesce(cfg.prov_cfg,'')) = oc.pk_oc
              then 'config = el de la OC'
            else 'config = ninguno de los dos' end situacion
  from oc
  join ent on ent.cod = oc.cod and ent.pk_ent <> oc.pk_oc
  left join cfg on cfg.cod = oc.cod
 where oc.pk_oc  not in (select public.gv_norm_prov_key(f.fabricante) from public."GV_OC_Fabrica_Para" f)
   and ent.pk_ent not in (select public.gv_norm_prov_key(f.fabricante) from public."GV_OC_Fabrica_Para" f)
   and not public.gv_prov_match(public.gv_norm_prov_keys(oc.prov_oc),
                                public.gv_norm_prov_keys(ent.prov_ent))
 order by oc.cajas_oc desc;
