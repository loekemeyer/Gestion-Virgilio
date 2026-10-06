-- v27.32 (Luis, 06/10, D11): ADS Stock — los saldos a 10/20/30 días van en CAJAS ENTERAS
-- (round(x, 0)): quiebre sólo si falta media caja o más. Antes −0,3 caja (Est. Madre de 1 caja/mes
-- a 10 días) contaba como quiebre y se mostraba «−0». Rojo 45 → 40; naranja y amarillo igual.
-- Se aplicó sobre la definición viva (replace '/ 30.0, 1),' → '/ 30.0, 0),' en los 3 saldos).
-- Lo leen gv_ads_stock3 (pantalla) y gv_ads_badge_stock (semáforo). Rollback: volver a 1 decimal.
do $$ declare d text := pg_get_functiondef('public.gv_ads_stock2()'::regprocedure); n text;
begin
  if d like '%v27.32%' then return; end if;
  n := replace(d, '/ 30.0, 1),', '/ 30.0, 0),');
  if n = d or (length(n) - length(replace(n, '/ 30.0, 0),', ''))) / length('/ 30.0, 0),') <> 3 then raise exception 'no matcheó 3 saldos'; end if;
  n := replace(n, '-- v27.23 (Luis', '-- v27.32 (Luis D11): saldos en cajas ENTERAS: quiebre sólo si falta media caja o más
     -- v27.23 (Luis');
  execute n;
end $$;
