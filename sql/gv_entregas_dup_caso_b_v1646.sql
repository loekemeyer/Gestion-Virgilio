-- ============================================================================
-- v16.46 — Se borran las 46 filas duplicadas de "Entregas_Virgilio" (caso B).
--          Cierra el problema 72. Con el OK del dueno.
-- Proyecto Supabase: hrxfctzncixxqmpfhskv
--
-- EL HALLAZGO ORIGINAL ESTABA MAL
-- --------------------------------
-- El problema 72 decia "62 filas duplicadas" y proponia un indice unico sobre
-- (np, cod_art). Ese indice habria RECHAZADO pedidos legitimos.
-- Los 60 pares se parten en dos casos opuestos, y el discriminante es el
-- timestamp `creado`:
--
-- CASO A - 16 pares - NO SON DUPLICADOS - NO SE TOCAN
--   Las dos filas comparten el MISMO creado al microsegundo: entraron en la
--   misma carga. Son DOS LINEAS DE PEDIDO del mismo articulo.
--   Comprobado contra la fuente: en 9 de los 16, "PPP_Base_Pedidos" (hoy
--   "GV_PPP_Base_Pedidos") trae exactamente las mismas dos lineas con las mismas
--   cantidades: 44496/713 = 2+8 · 97966/590E = 4+7 · 97971/590E = 2+4 ·
--   97996/323E = 1+2 · 97996/440E = 2+2 · 98293/574 = 2+4 · 98332/323E = 3+3 ·
--   98336/590E = 1+2. Borrarlas destruia 34 cajas entregadas REALES.
--   Unica excepcion conocida: 98139/590E, donde la base trae 1 linea de 10 y
--   Entregas tiene 8+10 -> ahi el 8 sobra. Se dejo: es 1 caso y no hay segunda
--   fuente que lo confirme.
--
-- CASO B - 44 pares, 46 filas - RE-INSERT - ESTAS SI SE BORRARON
--   `creado` distinto. Los 44 pares tienen la MISMA tanda (0 con tandas
--   distintas) y 30 de los 44 son byte a byte identicos.
--
-- CRITERIO: por par se conserva la fila con tanda y el `creado` mas nuevo
--   (desempate por id mas alto).
--
-- MEDICION (antes -> despues, todos los valores predichos se cumplieron exacto)
-- -----------------------------------------------------------------------------
--   filas                            10.652 -> 10.606   (-46)
--   cajas_entregadas              53.272,33 -> 53.110,33 (-162)
--   cajas_pedidas                 56.802,33 -> 56.622,33 (-180)
--   pares duplicados (np,cod_art)        60 -> 16        (solo el caso A)
--   gv_venta_mensual_cliente cajas   52.893 -> 52.753    (-140; la vista filtra
--       fecha_salida valida y cajas<>0, por eso no baja los 162 enteros)
--   Verificado despues: de los 16 pares que quedan, los 16 son caso A y 0 son B.
--
-- NO SE PUSO INDICE UNICO sobre (np, cod_art) y no hay que ponerlo: el caso A
-- demuestra que un pedido PUEDE traer el mismo articulo dos veces. Un guard real
-- tendria que incluir un numero de linea del pedido, que la tabla hoy no tiene.
--
-- Backups: zz_backups."GV_Backup_Entregas_Virgilio_20260912"      (tabla entera,
--            10.652 filas, con su PK id)
--          zz_backups."GV_Backup_Entregas_dup_borradas_20260912"  (las 46 exactas,
--            46 ids unicos, con el motivo)
-- Rollback: insert into public."Entregas_Virgilio" select <cols> from
--           zz_backups."GV_Backup_Entregas_dup_borradas_20260912";
-- ============================================================================

-- 1) backup de las filas a borrar (se ejecuto antes del delete)
create table zz_backups."GV_Backup_Entregas_dup_borradas_20260912" as
with dup as (select np, cod_art from public."Entregas_Virgilio" group by 1,2 having count(*) > 1),
b as (
  select e.np, e.cod_art from public."Entregas_Virgilio" e join dup d using (np, cod_art)
  group by 1,2 having count(distinct e.creado) > 1          -- caso B
),
r as (
  select e.*, row_number() over (partition by e.np, e.cod_art
           order by (e.tanda is not null and btrim(e.tanda) <> '') desc, e.creado desc, e.id desc) rn
  from public."Entregas_Virgilio" e join b using (np, cod_art)
)
select r.*, 'caso B: re-insert, misma tanda, se queda la de creado mas nuevo con tanda'::text as motivo
from r where rn > 1;
alter table zz_backups."GV_Backup_Entregas_dup_borradas_20260912" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_Entregas_dup_borradas_20260912"
  from anon, authenticated;

-- 2) el borrado, con guards: aborta si se colo una fila del caso A o si el conteo no da 46
do $do$
declare n_a int; n_del int; n_ids int;
begin
  select count(*) into n_a
  from zz_backups."GV_Backup_Entregas_dup_borradas_20260912" d
  where exists (select 1 from public."Entregas_Virgilio" e
                 where e.np = d.np and e.cod_art = d.cod_art
                 group by e.np, e.cod_art having count(distinct e.creado) = 1);
  if n_a <> 0 then raise exception 'ABORTA: % filas del caso A entraron en la lista', n_a; end if;

  select count(*) into n_ids from zz_backups."GV_Backup_Entregas_dup_borradas_20260912";
  if n_ids <> 46 then raise exception 'ABORTA: la lista tiene % filas, esperaba 46', n_ids; end if;

  delete from public."Entregas_Virgilio" e
   where e.id in (select id from zz_backups."GV_Backup_Entregas_dup_borradas_20260912");
  get diagnostics n_del = row_count;
  if n_del <> 46 then raise exception 'ABORTA: se borraron % filas, esperaba 46', n_del; end if;
end $do$;

-- 3) chequeo: de los pares que queden, TODOS tienen que ser caso A
-- with dup as (select np, cod_art from "Entregas_Virgilio" group by 1,2 having count(*)>1)
-- select count(*) filter (where n=1) caso_a, count(*) filter (where n>1) caso_b
--   from (select e.np, e.cod_art, count(distinct e.creado) n
--           from "Entregas_Virgilio" e join dup using (np,cod_art) group by 1,2) x;
-- -> 16 | 0
