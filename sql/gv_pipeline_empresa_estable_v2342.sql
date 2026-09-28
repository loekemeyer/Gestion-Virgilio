-- v23.42 (Luis 28/09): picking duplicado al cambiar la empresa de un articulo.
-- Causa: mov_stock_pipeline_dedup incluye la empresa; zz_normalizar_empresa la reescribe
-- desde gv_empresa_de_articulo. Si el articulo cambia de empresa (865ED -> CH el 25/09),
-- los reconciliadores (etapa1 / _rt) insertan OTRA fila con la empresa nueva en cada tanda
-- vieja: +cajas en Pickeados y -cajas en gondola, sin que el indice lo frene.
-- Arreglo: trigger BEFORE INSERT que, en codigo NO dual, hereda la empresa de la fila de
-- pipeline que esa tanda ya tiene para el articulo. Corre despues de zz_normalizar_empresa
-- (orden alfabetico) y antes de zzz_facturado_no_negativo (que maneja los duales).
-- Probado en transaccion abortada: F01F/321 LK, insert CH -> cae en la fila LK (3 -> 3 filas).
-- Rollback: drop trigger zz_pipeline_empresa_estable on public."Movimientos_Stock";

create or replace function public.trg_pipeline_empresa_estable()
returns trigger language plpgsql set search_path = public as $f$
declare v_emp text; v_ref text; v_ref0 text;
begin
  if new.tipo not in ('picking','separado','facturado') then return new; end if;
  if exists (select 1 from public.codigos_duales d
              where upper(btrim(d.cod)) = upper(btrim(new.cod_art))) then return new; end if;
  v_ref  := upper(btrim(coalesce(new.ref,'')));
  v_ref0 := upper(btrim(split_part(coalesce(new.ref,''),'|',1)));
  if v_ref = '' then return new; end if;
  select m.empresa into v_emp
    from public."Movimientos_Stock" m
   where upper(btrim(m.ref)) in (v_ref, v_ref0)
     and upper(btrim(m.cod_art)) = upper(btrim(new.cod_art))
     and m.tipo in ('picking','separado','facturado')
     and coalesce(m.empresa,'') not in ('','Mixto')
   order by (upper(btrim(m.ref)) = v_ref) desc, m.id asc
   limit 1;
  if v_emp is not null and v_emp is distinct from new.empresa then
    new.empresa := v_emp;
  end if;
  return new;
end $f$;

drop trigger if exists zz_pipeline_empresa_estable on public."Movimientos_Stock";
create trigger zz_pipeline_empresa_estable before insert on public."Movimientos_Stock"
  for each row execute function public.trg_pipeline_empresa_estable();

-- Centinela: vacia = ningun articulo no dual con su pipeline partido en dos empresas.
create or replace view public.gv_stock_pipeline_dos_empresas with (security_invoker = true) as
with p as (
  select upper(btrim(m.ref)) ref, upper(btrim(m.cod_art)) cod_art, m.deposito, m.tipo,
         coalesce(m.empresa,'') empresa, m.delta, m.id, m.creado
    from public."Movimientos_Stock" m
   where m.tipo in ('picking','separado','facturado')
     and upper(btrim(m.cod_art)) not in (select upper(btrim(cod)) from public.codigos_duales))
select ref, cod_art, deposito, tipo,
       string_agg(empresa||' '||delta::text, ' · ' order by id) filas,
       max(creado) ultima
  from p group by 1,2,3,4
having count(distinct empresa) > 1;
revoke all on public.gv_stock_pipeline_dos_empresas from anon;
-- Al 28/09: 865ED en D58A (fila CH extra +13/-13), E41A (fila LK extra +1/-1), E69A (todo 0).
