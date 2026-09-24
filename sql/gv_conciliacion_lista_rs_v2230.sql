-- v22.30 (Luis, 24/09): Conciliación mostraba "4181 —" en LK 0034 / LK 0035.
-- Causa: GV_Conciliacion_Facturacion es una FOTO que gv_conciliacion_registrar saca de
-- Facturacion_NP al facturar (16/09 12:10); en ese momento la razón social estaba vacía y se
-- completó después, pero la foto quedó vacía. Medido: 2 de 220 filas, las dos de 4181.
-- Arreglo al LEER (no toca datos): si la foto no tiene nombre, se toma el de Facturacion_NP.
-- Se aplica sobre la definición viva, idempotente (marcador v22.30-rs).
do $$ declare d text; n text; begin
  d := pg_get_functiondef('public.gv_conciliacion_lista(integer,integer,text,text)'::regprocedure);
  if d ~ 'v22\.30-rs' then raise notice 'ya estaba'; return; end if;
  n := replace(d, 'select s.np, s.empresa, s.tanda, s.cod_cliente, s.razon_social,',
    'select s.np, s.empresa, s.tanda, s.cod_cliente,' || chr(10) ||
    '           -- v22.30-rs (Luis 24/09): la foto se sacó con la razón social vacía (LK 0034/35); se completa al leer.' || chr(10) ||
    '           coalesce(nullif(btrim(s.razon_social), ''''), (select f.razon_social from public."Facturacion_NP" f' || chr(10) ||
    '             where f.np = s.np and nullif(btrim(f.razon_social), '''') is not null' || chr(10) ||
    '             order by f.facturado_at desc nulls last limit 1)) as razon_social,');
  if n = d then raise exception 'no matcheó el texto'; end if;
  execute n;
end $$;
-- Chequeo: select np, razon_social from public.gv_conciliacion_lista(300,0,null,null) where coalesce(razon_social,'')='';  -- vacía
