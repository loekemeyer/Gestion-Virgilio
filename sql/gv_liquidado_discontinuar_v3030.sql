-- v30.30 (Luis, 14/10/2026): el 574 queda DISCONTINUADO cuando sus últimas cajas se pickearon
-- (v30.29, dentro de un pedido de 574E), se armaron, se facturaron y se entregaron.
-- Condición, medida, no supuesta:
--   1) hay un PKC del código con real > 0 desde p_desde (se pickeó),
--   2) esa tanda tiene remito recibido (CRN texto = 'NP|TANDA'): se fue,
--   3) el código tiene saldo 0 en TODOS los depósitos de vista_saldos_stock (nada en
--      góndola, separar, a facturar…): se armó y se facturó.
-- Si se cumple, alta en Articulos_Discontinuados → su trigger libera la góndola (F50).
-- Idempotente (on conflict do nothing). Lo corre el cron gv-liquidado-discontinuar.
create or replace function public.gv_liquidado_discontinuar(p_simular boolean default false)
returns table(cod text, tanda text, discontinuado boolean)
language plpgsql security definer set search_path = public as $f$
-- v30.30-liquidado-disc
declare r record; v_tanda text; v_saldo numeric;
begin
  for r in select * from (values ('574'::text, timestamptz '2026-10-14 00:00-03', 'Luis 14/10: se liquidaron las 2 cajas en un pedido de 574E')) x(cod, desde, nota)
  loop
    v_tanda := null;
    if exists (select 1 from "Articulos_Discontinuados" a where a.cod = r.cod) then continue; end if;
    select upper(btrim(split_part(k.texto,'|',1))) into v_tanda
      from "Registros_Produccion_Virgilio" k
     where k.opcion = 'PKC' and k.ts_cliente >= r.desde
       and upper(regexp_replace(btrim(split_part(k.texto,'|',2)),' +(LK|CH)$','')) = r.cod
       and split_part(k.texto,'|',4) ~ '^\d+(\.\d+)?$' and split_part(k.texto,'|',4)::numeric > 0
       and exists (select 1 from "Registros_Produccion_Virgilio" c
                    where c.opcion = 'CRN' and c.ts_cliente >= r.desde
                      and upper(btrim(split_part(c.texto,'|',2))) = upper(btrim(split_part(k.texto,'|',1))))
     order by k.ts_cliente desc limit 1;
    if v_tanda is null then continue; end if;
    select coalesce(sum(coalesce(v.terminado,0) + coalesce(v.separar_pedidos,0) + coalesce(v.a_facturar,0)
                        + coalesce(v.excedente,0) + coalesce(v.racks,0) + coalesce(v.racks_ch,0)
                        + coalesce(v.a_guardar,0) + coalesce(v.para_envasar,0)), 0)
      into v_saldo from vista_saldos_stock v where upper(v.cod_art) = r.cod;
    if v_saldo <> 0 then continue; end if;
    if not p_simular then
      insert into "Articulos_Discontinuados"(cod, motivo) values (r.cod, 'liquidado (v30.30) — ' || r.nota || ' · tanda ' || v_tanda)
      on conflict do nothing;
    end if;
    cod := r.cod; tanda := v_tanda; discontinuado := not p_simular; return next;
  end loop;
end $f$;
revoke all on function public.gv_liquidado_discontinuar(boolean) from public, anon, authenticated;

select cron.schedule('gv-liquidado-discontinuar', '13 8 * * *', $c$select * from public.gv_liquidado_discontinuar(false)$c$);

insert into "GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
values ('gv_liquidado_discontinuar', 'funcion', 'Articulos_Discontinuados',
        'v30.30-liquidado-disc: el 574 se discontinúa solo cuando su PKC (real>0) tiene remito CRN y su saldo total es 0. Si se pierde el insert, el 574 queda vivo con la góndola F50 ocupada.',
        'Luis', 'v30.30', true);
-- rollback: select cron.unschedule('gv-liquidado-discontinuar'); drop function public.gv_liquidado_discontinuar(boolean);
--           update "GV_Reglas_Centinela" set activo=false where version='v30.30';
