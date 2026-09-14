-- ============================================================================
-- v17.24 — PRENDIDO: sales_lines ya se llena desde ISIS
--
-- Thomas (14/09): "necesita imput manual humano para arrancar? no podes guardar
-- el backup bien etiquetado vos y correr el sistema nuevo?". Se prendio.
--
-- BACKUP COMPLETO PREVIO (verificado igual a la tabla viva antes de tocar nada):
--   zz_backups."GV_Backup_sales_lines_20260914_pre_isis"
--   233.776 filas / 1.249.870 cajas — copia ENTERA de sales_lines, no solo el tramo.
--   Restaurar: delete from public.sales_lines;
--              insert into public.sales_lines select * from esa tabla;
--
-- RESULTADO DE LA PRIMERA CORRIDA:
--   {"aplicado": true, "desde": "2026-02-01", "borradas": 29125,
--    "insertadas": 31621, "cajas": 164498}
--   Todos los meses quedan en 0,0 % de diferencia contra ISIS
--   (select * from public.gv_sales_isis_vs_excel).
-- ============================================================================

update public."GV_Sales_Auto_Config"
   set valor = '1', actualizado = now(),
       nota  = 'Prendido el 2026-09-14 por pedido de Thomas. Backup completo previo en zz_backups."GV_Backup_sales_lines_20260914_pre_isis".'
 where clave = 'activo';

select public.gv_sales_lines_auto_sync(true);

-- El parche de julio/agosto quedo inerte (esos lotes ya no existen) y se borro.
-- Sobrevive UNA fila: la del batch jumbo_2026_02_20, que va de 2024-03 a
-- 2026-01 — o sea ANTES del corte, donde sigue siendo un duplicado real.
delete from public."GV_Ventas_Correccion"
 where import_batch in ('julio_26','ago-26')
   and not exists (select 1 from public.sales_lines s
                    where s.import_batch = "GV_Ventas_Correccion".import_batch);


-- ###########################################################################
-- ## DOS EFECTOS DEL DATO EN VIVO, Y SU CORRECCION
-- ##
-- ## Con el Excel mensual, sales_lines NUNCA tenia el mes en curso. Ahora
-- ## llega hasta hoy, y un mes a medias hace ver caidas que no existen.
-- ###########################################################################

-- (a) La alarma de clientes: el trimestre actual termina en el ultimo mes
--     COMPLETO. Sin esto, Cencosud pasaba de -15 % a -38 % por tener septiembre
--     a mitad de camino.
create or replace view public.gv_ventas_corte_empresa
with (security_invoker = true) as
select empresa,
       least(max(mes), (date_trunc('month', current_date) - interval '1 month')::date) as mes_corte
  from (select empresa, date_trunc('month', fecha)::date mes, count(distinct cliente_id) n
          from public.gv_ventas_cliente group by 1,2) t
 where n >= 10
 group by 1;
-- y gv_clientes_riesgo pasa a tomar su corte de ahi (ver el .sql de la v17.21,
-- bloque `corte`: `select max(mes_corte) from public.gv_ventas_corte_empresa`),
-- ademas de filtrar `m.mes <= corte` para no arrastrar el mes incompleto.

-- (b) La proyeccion de compras: `_fn_proy_window` y `_fn_proy_window_emp`
--     promedian N meses terminando en max(mes) de sales_lines. Con septiembre
--     a medias, el promedio bajaba y se pediria de menos. Se les capo el `endm`
--     al ultimo mes completo. Definiciones anteriores guardadas en
--     zz_backups."GV_Backup_defs_proy_window_20260914".
--
--     El parche, aplicado a las dos con un replace sobre pg_get_functiondef:
--       ANTES: select max(...) as endm from public.sales_lines where ...
--       AHORA: select least(max(...),
--                (extract(year from current_date)::int*12
--                 + extract(month from current_date)::int) - 1) as endm ...

-- ###########################################################################
-- ## VERIFICACION POSTERIOR (todo corrido el 14/09)
-- ###########################################################################
--  gv_sales_isis_vs_excel ........ 16 filas, TODAS en 0,0 %
--  sales_lines desde el corte .... un solo lote `isis_auto`, lk + chef separadas
--  gv_ventas_cliente sin cliente .. 0
--  gv_ventas_carga_sospechosa ..... 0 pendientes
--  alarma (pico>=300, <=-30 %) .... 41 clientes, 11 migraciones, 0 incompletos
--  Cencosud ....................... -15 %, todo Chef, FUERA de la alarma
--  _fn_proy_window_emp(6,'lk') .... 210 articulos / 18.275 cajas-mes
--  _fn_proy_window_emp(6,'chef') .. 218 / 3.827
--  GV_Proyeccion_Emp (Virgilio) ... lk 220 filas / 18.359 · chef 313 / 4.983
--     (antes: lk 383 y chef 231 — se fueron los articulos fantasma de LK)
--  refresh_estadistica_madre_cache  537 filas
--  proyeccion_madre (Virgilio) .... 461 filas, actualizada
