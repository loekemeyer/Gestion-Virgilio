-- v30.05 · 2026-10-13 · EL PADRÓN DE LA GRILLA DE SC/SP: 76 celdas, IN-A1 … IN-L7
--
-- Luis, 13/10 (textual): "esos sectores deberían ser «IN-» letras de la A a la L con la
-- siguiente logica / De la A a la E van del 1 al 6 (ej. IN-A1, IN-E6) / F es del 1 al 5 /
-- G del 1 al 6 / De H a L son del 1 al 7".
--
--   A·B·C·D·E × 1..6 = 30 · F × 1..5 = 5 · G × 1..6 = 6 · H·I·J·K·L × 1..7 = 35  ->  76
--
-- Antes de esto había 55 celdas (las que la v29.98 renombró de la grilla de un dígito + las
-- 3 que se dieron de alta ahí). Esto es SÓLO el alta de las 22 que faltaban: no se tocó ni
-- un objeto, ni una fila de Insumos_Ubicaciones, ni el front.
--
-- NO hace falta DDL: el CHECK del nombre ya acepta IN-xx con uno o dos dígitos (v29.98).
--
-- ⚠ IN-F6 queda viva y FUERA del padrón: tiene anotado D14 (Resorte 520 Niq., cantidad 0, su
--   stock lo lleva GP2). Sacarla manda esa pieza a la alerta "insumo con stock y sin posición",
--   que Luis dejó para después (D1 del 13/10). La decide él.

-- ========== EL ALTA (idempotente) ==========
insert into public."GV_Lugar" (sector, tipo, empresa)
select 'IN-'||l||n::text, 'scp', 'IN'
  from (values ('A',6),('B',6),('C',6),('D',6),('E',6),('F',5),('G',6),
               ('H',7),('I',7),('J',7),('K',7),('L',7)) v(l,hasta)
  cross join lateral generate_series(1, v.hasta) n
 where not exists (select 1 from public."GV_Lugar" g where g.sector = 'IN-'||l||n::text)
returning sector;
-- 13/10: 22 filas (A4, C3, C4, D2, E3, E4, F3, F4, F5, I1, I2, I3, I5, I6, I7,
--                  J5, J7, K1, K2, K3, K7, L7), todas vacías.

-- el espejo a GP2 corre cada 10 min; para que lo vea ya:
select public.gv_gp2_espejo_sync();

-- ========== VERIFICACIÓN ==========
-- lo que falta del padrón y lo que sobra (al 13/10: 0 faltantes y 1 fuera = IN-F6)
with padron as (
  select 'IN-'||l||n::text as sector
    from (values ('A',6),('B',6),('C',6),('D',6),('E',6),('F',5),('G',6),
                 ('H',7),('I',7),('J',7),('K',7),('L',7)) v(l,hasta)
    cross join lateral generate_series(1, v.hasta) n
), viva as (select sector, activo from public."GV_Lugar" where tipo = 'scp')
select coalesce(p.sector, v.sector) sector,
       case when p.sector is null then 'FUERA DEL PADRON'
            when v.sector is null then 'FALTA DAR DE ALTA'
            when not v.activo then 'EXISTE PERO INACTIVA' end estado,
       (select count(*) from public."Insumos_Ubicaciones" u
         where upper(btrim(u.sector)) = coalesce(p.sector, v.sector)) piezas
  from padron p full outer join viva v on v.sector = p.sector
 where p.sector is null or v.sector is null or not v.activo
 order by 2, 1;

-- los números (13/10: 77 / 77 / 77 / 55 con pieza / 22 libres / GP2 77)
select (select count(*) from public."GV_Lugar" where tipo='scp')                  scp_total,
       (select count(*) from public."GV_Lugar" where tipo='scp' and activo)       scp_activas,
       (select count(*) from public.gv_scp_celda)                                 celdas,
       (select count(*) from public.gv_scp_celda where cod is not null)           con_pieza,
       (select count(*) from public.gv_scp_celda where cod is null)               libres,
       (select count(*) from "GP2".virgilio_lugar where tipo='scp')               gp2_scp;

select * from public.gv_reglas_perdidas;    -- vacía
select * from public.gv_endpoints_rotos;    -- vacía

-- ========== ROLLBACK (deshace SÓLO el alta de las 22, que están vacías) ==========
-- update public."GV_Lugar" set activo = false
--  where tipo = 'scp' and sector in ('IN-A4','IN-C3','IN-C4','IN-D2','IN-E3','IN-E4','IN-F3',
--        'IN-F4','IN-F5','IN-I1','IN-I2','IN-I3','IN-I5','IN-I6','IN-I7','IN-J5','IN-J7',
--        'IN-K1','IN-K2','IN-K3','IN-K7','IN-L7');
