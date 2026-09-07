-- BACKUP + CAMBIO · GV_PPP_Prog_Override + PPP_Web_* — ningún camión repetido en dos días
-- 2026-09-07 ~15:10 ART · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ SE PIDIÓ. Dueño 07/09, con captura de la búsqueda "d66" en Programación: *"ahora quedó D66B
-- en miércoles y jueves, no puede quedar la misma tanda en dos días. corregí. porque cuando hagan
-- el picking, tienen que pickear lo correcto"*.
--
-- QUÉ ERA EN REALIDAD. La tanda `D66B` estaba en UN solo día (miércoles 09/09, verificado en
-- `PPP_Programacion_Diaria`, en el override y en la vista). Lo que estaba partido era el **CAMIÓN**:
-- la app agrupa por el NÚMERO de tanda (`_pppTandaNum`: D66B → camión 66), así que
--   mié 09/09 → camión 66 = D66B (Osa)                     ← movida el sábado, a pedido del dueño
--   jue 10/09 → camión 66 = D66A · D66C · D66D · D66E · D66F
-- eran DOS camiones distintos con el mismo número, en días distintos. Mismo problema, sin mirar,
-- con el **camión 60**: D60A/B/C/F el jue 10 y D60E el vie 11 (la reprogramación del 06 y del 07).
--
-- Las dos roturas las causaron reprogramaciones pedidas por el dueño:
--   · sáb 06: "la tanda del cliente 2533 adelantala para el miércoles"  → D66B se fue del 66
--   · dom 07: "pasala al viernes 11"                                     → D60E se fue del 60
--
-- QUÉ SE HIZO. Renombrar la tanda que quedó SOLA, para que el número de camión no se repita. Se
-- usa `GV_PPP_Prog_Override.tanda`, que es exactamente para esto y ya se había usado antes (44619
-- Chango Mas → E07A, v13.50): **no se toca `PPP_Programacion_Diaria`, que es de Producción.**
--
--   98650 · 98667  D66B → **E09A**   (mié 09/09, Osa Distribuidora, 4,041 m³, de ISIS)
--   1354 (LK 0024) D66G → **E09B**   (mié 09/09, el agregado de Osa, 0,026 m³, de la página)
--   98532 · 98533  D60E → **E10A**   (vie 11/09, Betbeze Gimenez, 0,214 m³, de ISIS)
--
-- POR QUÉ E09 y E10: los códigos `D` son de ISIS y llegan hasta D71; los `E` son los de Gestión y
-- llegaban hasta E08. E09 y E10 estaban libres en las cuatro tablas donde vive una tanda
-- (programación, web, entregados, facturación). El miércoles Osa queda con camión propio (E09A +
-- E09B, mismo cliente y misma dirección, se pickean por separado) y el **camión 66 vuelve a estar
-- entero el jueves**.
--
-- SEGURO PARA EL PICKING: ninguna de las tandas renombradas tenía un solo evento de operarios
-- (verificado sobre `Registros_Produccion_Virgilio`, legajos ≠ 0/1). Desde el lunes 08 los operarios
-- pickean desde Gestión, no desde el papel de ISIS.
--
-- VERIFICACIÓN FINAL (de hoy en adelante, ISIS + web): **ningún número de camión en dos días**.
--
-- BACKUPS:
--   public."GV_Backup_Override_20260907_d66b"   (98650, 98667 — override antes del renombre)
--   public."GV_Backup_Override_20260907_d60e"   (98532, 98533 — idem)
--   public."GV_Backup_WebProg_20260907_osa"     (order_id 1354 — antes de todo, con tanda D66B)
--
-- ROLLBACK:
--   update public."GV_PPP_Prog_Override" set tanda = null where np in ('98650','98667','98532','98533');
--   update public."PPP_Web_Programacion" set tanda = 'D66G' where order_id = 1354;
--   update public."PPP_Web_Tandas" set codigo = 'D66G' where codigo = 'E09B';

-- ===== LO QUE SE EJECUTÓ =====

create table if not exists public."GV_Backup_Override_20260907_d66b" as
select *, now() as respaldado_at from public."GV_PPP_Prog_Override" where np in ('98650','98667');

create table if not exists public."GV_Backup_Override_20260907_d60e" as
select *, now() as respaldado_at from public."GV_PPP_Prog_Override" where np in ('98532','98533');

update public."GV_PPP_Prog_Override" set tanda = 'E09A' where np in ('98650','98667');
update public."GV_PPP_Prog_Override" set tanda = 'E10A' where np in ('98532','98533');
update public."PPP_Web_Programacion" set tanda  = 'E09B' where order_id = 1354;
update public."PPP_Web_Tandas"        set codigo = 'E09B' where codigo = 'D66G' and fecha_entrega = '2026-09-09';

-- el chequeo que tiene que dar "ninguno"
with t as (
  select nullif(fecha_entrega,'')::date fe, upper(tanda) tanda from public.gv_ppp_programacion_diaria
    where nullif(fecha_entrega,'')::date >= current_date and nullif(tanda,'') is not null
  union all
  select fecha_entrega, upper(tanda) from public."PPP_Web_Programacion"
    where fecha_entrega >= current_date and nullif(tanda,'') is not null
),
c as (select distinct fe, (regexp_match(tanda,'^([A-Z]+)(\d+)[A-Z]+$'))[1] || (regexp_match(tanda,'^([A-Z]+)(\d+)[A-Z]+$'))[2] camion
      from t where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$')
select camion, count(distinct fe) dias from c group by camion having count(distinct fe) > 1;
