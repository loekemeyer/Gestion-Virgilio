-- BACKUP + CAMBIO · PPP_Web_Programacion — el agregado de Osa vuelve a tanda propia
-- 2026-09-07 ~14:40 ART · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ SE PIDIÓ. Dueño 07/09, textual: *"osa no puede quedar en D66B el pedidito chiquito del
-- agregado. tiene que ir en una nueva tanda"*.
--
-- CONTEXTO. Antes el dueño había dicho *"si todavía ni se pickeó, el agregado se agrega a la tanda
-- actual del cliente"* y después *"me da igual"*, y la otra sesión aplicó esa regla: metió el 1354
-- (NP web `LK 0024`, 0,026 m³) DENTRO de `D66B`. Esta instrucción lo revierte para ESTE caso: el
-- agregado va aparte.
--
-- QUÉ SE HIZO.
--   1) backup del registro a public."GV_Backup_WebProg_20260907_osa" (1 fila, con la tanda D66B);
--   2) PPP_Web_Programacion: order_id 1354 pasa de tanda `D66B` a `D66G` (misma fecha, 2026-09-09);
--   3) PPP_Web_Tandas: se recrea la fila de `D66G` (lk, programada, 2026-09-09).
--
-- CÓMO QUEDA EL MIÉRCOLES 09/09 para el cliente 2533 (Osa Distribuidora, Villa Lugano, Zona 1):
--   D66B → 98650 (2,710) + 98667 (1,331) = 4,041 m³   [de ISIS]
--   D66G → LK 0024 (0,026)                            [de la página]
--   Las dos van al mismo camión y a la misma dirección; se pickean por separado.
--
-- SOBRE "LA MISMA TANDA EN DOS DÍAS". El dueño también dijo: *"ahora quedó D66B en miércoles y
-- jueves, no puede quedar la misma tanda en dos días"*. **Se verificó y en la base NO pasa**:
--   PPP_Programacion_Diaria  → 98650 y 98667, tanda D66B, fecha 2026-09-09 (las dos)
--   GV_PPP_Prog_Override     → 98650 y 98667 → 2026-09-09
--   gv_ppp_programacion_diaria (lo que ve la app) → D66B sólo el 09/09
-- Lo que SÍ está partido en dos días es la FAMILIA D66, por la reprogramación del sábado (dueño:
-- "la tanda del cliente 2533 adelantala para el miércoles"): D66B quedó el miércoles y sus
-- hermanas D66A · D66C · D66D · D66E · D66F siguen el jueves 10/09. El código de tanda es único por
-- día, así que el picking no es ambiguo — pero conviene mirarlo con él.
--
-- ROLLBACK:
--   update public."PPP_Web_Programacion" set tanda = 'D66B' where order_id = 1354;
--   delete from public."PPP_Web_Tandas" where codigo = 'D66G' and fecha_entrega = '2026-09-09';
--   -- o, la foto completa:
--   -- select * from public."GV_Backup_WebProg_20260907_osa";

-- ===== LO QUE SE EJECUTÓ =====

create table if not exists public."GV_Backup_WebProg_20260907_osa" as
select *, now() as respaldado_at from public."PPP_Web_Programacion" where order_id = 1354;

update public."PPP_Web_Programacion" set tanda = 'D66G' where order_id = 1354 and tanda = 'D66B';

insert into public."PPP_Web_Tandas" (empresa, codigo, estado, fecha_entrega, creado_por, creado_at, programada_por, programada_at)
values ('lk','D66G','programada','2026-09-09','chat 07/09 (dueño: el agregado de Osa va en tanda propia)', now(), 'chat 07/09', now())
on conflict do nothing;

-- verificación
select 'web' fuente, np::text, tanda, fecha_entrega::text, m3::text from public."PPP_Web_Programacion" where order_id = 1354
union all
select 'ISIS', np::text, tanda, fecha_entrega::text, m3::text from public.gv_ppp_programacion_diaria where upper(tanda) in ('D66B','D66G');
