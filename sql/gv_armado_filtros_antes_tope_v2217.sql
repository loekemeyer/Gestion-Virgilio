-- v22.19 (Luis, 24/09) — ARMADO: los filtros baratos van ANTES del tope de 120.
-- Lo diferido por importado (a0), lo retenido a mano (a0b) y lo cancelado a mano (a0c) no se
-- programa en esta corrida pase lo que pase, pero hoy entra al conteo del tope (a00) y le saca
-- lugar a pedidos que si se pueden programar. Se mueven arriba del tope, justo despues de (a000).
-- La (a00) de v19.55 decia que los filtros tenian que ir DESPUES del tope porque con 496 filas
-- tardaban 9,6 s; eso era con lo ya programado adentro. Desde (a000) v21.61 lo programado sale
-- primero y a los filtros llegan solo los pendientes (hoy 2 a 5 por corrida, pico 185).
-- Cuarentena (a0d) queda DESPUES del tope: es la cara (gv_cuarentena_marcar_calc).
-- Parche sobre pg_get_functiondef (definicion viva), idempotente por la marca 'v22.17-filtros',
-- y falla con raise si el texto no matchea (varias sesiones tocan esta funcion).
do $parche$
declare d text; i_tope int; i_a0 int; i_a0d int; pre text; tope text; filtros text; resto text; n text;
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if d ~ 'v22\.17-filtros' then raise notice 'ya aplicado'; return; end if;
  i_tope := position('  v_entraron := jsonb_array_length' in d);
  i_a0   := position('  -- (a0) v15.67' in d);
  i_a0d  := position('  -- (a0d)' in d);
  if i_tope = 0 or i_a0 = 0 or i_a0d = 0 or not (i_tope < i_a0 and i_a0 < i_a0d) then
    raise exception 'armador: no encuentro los bloques (tope %, a0 %, a0d %)', i_tope, i_a0, i_a0d;
  end if;
  pre     := substr(d, 1, i_tope - 1);
  tope    := substr(d, i_tope, i_a0 - i_tope);
  filtros := substr(d, i_a0, i_a0d - i_a0);
  resto   := substr(d, i_a0d);
  if filtros !~ '\(a0b\)' or filtros !~ '\(a0c\)' or tope !~ 'armado_tope_pedidos' then
    raise exception 'armador: los bloques no son los esperados';
  end if;
  n := pre || filtros ||
       '  -- (a00b) v22.17-filtros (Luis, 24/09): diferido, retenido y cancelado salen ANTES del tope;' || chr(10) ||
       '  --   el tope cuenta solo lo que esta corrida puede programar.' || chr(10) ||
       tope || resto;
  if length(n) <> length(d) + length('  -- (a00b) v22.17-filtros (Luis, 24/09): diferido, retenido y cancelado salen ANTES del tope;' || chr(10) ||
       '  --   el tope cuenta solo lo que esta corrida puede programar.' || chr(10)) then
    raise exception 'armador: el largo no cierra';
  end if;
  execute n;
end $parche$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_armar_pendientes','funcion','"GV_PPP_Web_NP_Cancelada"[\s\S]*armado_tope_pedidos',
        'diferido, retenido y cancelado se sacan antes del tope de pedidos por corrida','Luis','v22.17');
