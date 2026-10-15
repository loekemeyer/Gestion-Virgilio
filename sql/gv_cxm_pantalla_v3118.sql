-- v31.18 (Luis, 15/10/2026): EMPAQUE pendiente de definir — se carga desde Stock → «📦 Empaque».
-- «Con 2 de los datos siempre podés sacar el tercero. Ponelo como pendiente de definir en algún lado de GV (creale algo
--  en el front para que se pueda poner el dato y que impacte la tabla correspondiente). A lo mejor también se podría
--  marcar algo como "Esto no tiene Inner".»
--
-- 1) trg_gv_rack_cxm_coherente DERIVA el tercer dato cuando hay dos (si da entero).
-- 2) gv_cxm_estado: por código con stock en racks / a guardar / excedente, o importado activo → qué tiene y qué falta.
-- 3) gv_cxm_guardar: la RPC de la pantalla (sólo supervisor, gv_rpc_guard). Escribe la canónica (todas las filas del
--    código) y, si el código está en Importados_Volumen, le deja las mismas unidades (uni_master / uni_inner; sin inner
--    = uni_inner 0, como ya lo usa importación): así el conflicto se resuelve en los dos lados de una vez.

create or replace function public.gv_rack_cxm_coherente()
 returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if new.cxm is not null and new.sin_inner then new.sin_inner := false; end if;
  if new.sin_master then new.uni_x_master := null; end if;
  -- un ingreso a racks que cambia cxm: si las unidades dejan de cerrar, se limpian (manda el conteo físico)
  if new.cxm is not null and new.uni_x_inner is not null and new.uni_x_master is not null
     and new.uni_x_master <> new.cxm * new.uni_x_inner then
    new.uni_x_inner := null; new.uni_x_master := null;
  end if;
  -- v31.18: con dos datos sale el tercero (sólo si da entero)
  if not new.sin_master and not new.sin_inner then
    if new.cxm is not null and new.uni_x_inner is not null and new.uni_x_master is null then
      new.uni_x_master := new.cxm * new.uni_x_inner;
    elsif new.cxm is null and new.uni_x_inner > 0 and new.uni_x_master > 0 and new.uni_x_master % new.uni_x_inner = 0 then
      new.cxm := new.uni_x_master / new.uni_x_inner;
    elsif new.cxm > 0 and new.uni_x_master > 0 and new.uni_x_inner is null and new.uni_x_master % new.cxm = 0 then
      new.uni_x_inner := new.uni_x_master / new.cxm;
    end if;
  end if;
  return new;
end $function$;

create or replace view public.gv_cxm_estado with (security_invoker = true) as
with st as (
  select upper(regexp_replace(btrim(cod_art), '\s+(LK|CH)$', '')) cod, min(descripcion) descripcion, min(empresa) empresa,
         sum(coalesce(racks,0) + coalesce(racks_ch,0)) racks, sum(coalesce(a_guardar,0) + coalesce(excedente,0)) a_guardar,
         sum(coalesce(terminado,0)) gondola
    from public.vista_saldos_stock group by 1),
imp as (select distinct upper(btrim(cod_art)) cod from public."Importados" where coalesce(activo, true)),
can as (select cod, min(cxm) cxm, min(uni_x_inner) uni_x_inner, min(uni_x_master) uni_x_master,
               bool_or(sin_inner) sin_inner, bool_or(sin_master) sin_master, min(fuente) fuente, min(nota) nota, max(actualizado_en) actualizado_en
          from public."GV_Rack_CxM" group by cod),
iv as (select upper(btrim(cod)) cod, min(uni_master) uni_master, min(uni_inner) uni_inner from public."Importados_Volumen" group by 1),
art as (select upper(btrim("Cod_Art")) cod, max(nullif("Uni_x_Caja",0)) uxc from public."Articulos Virgilio X Tallerista" group by 1),
u as (select cod from st where racks > 0 or a_guardar > 0 union select cod from imp)
select u.cod, st.descripcion, st.empresa, round(coalesce(st.racks,0)) racks, round(coalesce(st.a_guardar,0)) a_guardar,
       round(coalesce(st.gondola,0)) gondola, (imp.cod is not null) importado,
       can.cxm, can.uni_x_inner, can.uni_x_master, coalesce(can.sin_inner,false) sin_inner, coalesce(can.sin_master,false) sin_master,
       can.fuente, can.nota, can.actualizado_en,
       iv.uni_master iv_uni_master, iv.uni_inner iv_uni_inner, art.uxc sugerido_uni_x_inner,
       case
         when can.cod is null then 'sin dato'
         when iv.uni_inner = 0 and not coalesce(can.sin_inner,false) then 'importación dice sin inner'
         when iv.uni_inner > 0 and iv.uni_master > 0 and (can.cxm is null or iv.uni_master <> can.cxm * iv.uni_inner) then 'no coincide con importación'
         when can.sin_master then null
         when can.sin_inner and can.uni_x_master > 0 then null
         when can.cxm is not null and can.uni_x_inner is not null and can.uni_x_master is not null then null
         else 'incompleto'
       end as pendiente
  from u left join st on st.cod = u.cod left join imp on imp.cod = u.cod left join can on can.cod = u.cod
  left join iv on iv.cod = u.cod left join art on art.cod = u.cod;
grant select on public.gv_cxm_estado to anon, authenticated;

create or replace function public.gv_cxm_guardar(p_cod text, p_cxm numeric, p_uni_x_inner numeric, p_uni_x_master numeric,
                                                 p_sin_inner boolean default false, p_sin_master boolean default false, p_nota text default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_cod text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '\s+(LK|CH)$', ''));
  v_cxm numeric := nullif(p_cxm, 0); v_ui numeric := nullif(p_uni_x_inner, 0); v_um numeric := nullif(p_uni_x_master, 0);
  v_si boolean := coalesce(p_sin_inner, false); v_sm boolean := coalesce(p_sin_master, false);
  v_quien text := coalesce(nullif(auth.jwt() ->> 'email', ''), session_user::text);
  v_n int; r record;
begin
  perform public.gv_rpc_guard('gv_cxm_guardar');
  if v_cod = '' then raise exception 'Falta el código'; end if;
  if v_si and v_sm then raise exception 'No puede ser «sin inner» y «sin master» a la vez'; end if;
  if v_sm then v_cxm := null; v_um := null; end if;
  if v_si then
    v_cxm := null; v_ui := null;
    if v_um is null then raise exception 'Sin inner: falta cuántas unidades trae la master'; end if;
  end if;
  if not v_si and not v_sm then
    if v_cxm is null and v_ui > 0 and v_um > 0 then
      if v_um % v_ui <> 0 then raise exception 'Unidades × master (%) no se divide en unidades × inner (%)', v_um, v_ui; end if;
      v_cxm := v_um / v_ui;
    end if;
    if v_cxm is null then raise exception 'Faltan datos: con dos de los tres sale el tercero'; end if;
    if v_cxm <> trunc(v_cxm) or v_cxm <= 0 then raise exception 'Inner × master tiene que ser un entero positivo'; end if;
    if v_ui is not null and v_um is not null and v_um <> v_cxm * v_ui then
      raise exception 'No cierra: % × % = %, no %', v_cxm, v_ui, v_cxm * v_ui, v_um;
    end if;
    if v_ui is null and v_um is not null then
      if v_um % v_cxm <> 0 then raise exception 'Unidades × master (%) no se divide en % inner', v_um, v_cxm; end if;
      v_ui := v_um / v_cxm;
    end if;
    if v_um is null and v_ui is not null then v_um := v_cxm * v_ui; end if;
  end if;

  update public."GV_Rack_CxM"
     set cxm = v_cxm, uni_x_inner = v_ui, uni_x_master = v_um, sin_inner = v_si, sin_master = v_sm,
         fuente = 'a mano (' || v_quien || ')', nota = coalesce(nullif(btrim(p_nota), ''), nota), actualizado_en = now()
   where cod = v_cod;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public."GV_Rack_CxM"(cod, emp, cxm, uni_x_inner, uni_x_master, sin_inner, sin_master, fuente, nota)
    values (v_cod, coalesce(public.gv_empresa_de_articulo(v_cod), 'LK'), v_cxm, v_ui, v_um, v_si, v_sm,
            'a mano (' || v_quien || ')', nullif(btrim(p_nota), ''));
  end if;

  -- importación: mismas unidades (sin inner = uni_inner 0). Sin master no se toca (es de nacionales).
  if not v_sm and v_um is not null then
    update public."Importados_Volumen"
       set uni_master = v_um, uni_inner = case when v_si then 0 else v_ui end, actualizado = now()
     where upper(btrim(cod)) = v_cod
       and (uni_master is distinct from v_um or uni_inner is distinct from (case when v_si then 0 else v_ui end));
  end if;

  select * into r from public.gv_cxm_estado where cod = v_cod;
  return jsonb_build_object('ok', true, 'cod', v_cod, 'cxm', v_cxm, 'uni_x_inner', v_ui, 'uni_x_master', v_um,
                            'sin_inner', v_si, 'sin_master', v_sm, 'pendiente', r.pendiente);
end $function$;
revoke all on function public.gv_cxm_guardar(text, numeric, numeric, numeric, boolean, boolean, text) from public;
grant execute on function public.gv_cxm_guardar(text, numeric, numeric, numeric, boolean, boolean, text) to anon, authenticated;
insert into public."GV_RPC_Guard"(fn, activo, desde, version) values ('gv_cxm_guardar', true, now(), 'v31.18')
on conflict (fn) do update set activo = true, version = excluded.version;
