-- v29.28 (Thomas, 09/10, D13): cada bolsa plástica que el operario manda a un inyector SUMA el stock
-- de ese inyector en GP2. Antes no llegaba ninguna (0 movimientos envio_inyector en toda la historia):
--   1) el celular llamaba GP2.enviar_material_virgilio con la clave pública y GP2 contesta
--      «No autorizado» desde el 28/09 (_exigir_autorizado);
--   2) GP2 conoce las bolsas por otro código (PP, PS, PE, NV, N25, NR): sólo ABS y AI coincidían.
-- Lo resuelve una función de Gestión (SECURITY DEFINER) que traduce el código de Virgilio al
-- componente de GP2 por GV_Bolsa_GP2 y llama al MISMO GP2.enviar_material_inyector (kg del sector
-- 14 «materia prima en Virgilio» → ubicación del inyector), sin tocar ningún objeto de GP2.
-- Rollback: revoke execute on function public.gv_insumo_envio_inyector(text,numeric,text,text) from anon, authenticated;

create table if not exists public."GV_Bolsa_GP2" (
  cod_virgilio text primary key,
  comp_id bigint not null,
  nota text,
  creado timestamptz not null default now()
);
alter table public."GV_Bolsa_GP2" enable row level security;
revoke insert, update, truncate on public."GV_Bolsa_GP2" from anon, authenticated;

insert into public."GV_Bolsa_GP2" (cod_virgilio, comp_id, nota) values
  ('PP 2630',        742, 'GP2 2405 PP 2630 (Polipropileno)'),
  ('PS PE',          749, 'GP2 2425 PS Poliestireno HF 555'),
  ('PE Polie',       748, 'GP2 2435 PE Polietileno Baja 7147'),
  ('ABS',            743, 'GP2 2455 ABS GP 22 Natural'),
  ('AI',             744, 'GP2 2465 Alto Impacto AI 4600'),
  ('NY Virgen',      745, 'GP2 2475 Nylon Virgen'),
  ('NY c/Carga 25%', 747, 'GP2 2485 Nylon c/Carga 25%'),
  ('NY Recup',       746, 'GP2 2505 Nylon Recuperado')
on conflict (cod_virgilio) do nothing;
-- EBA no existe en GP2: sin fila, la función contesta en_gp2 = false y la salida queda sólo en Virgilio.

create or replace function public.gv_insumo_envio_inyector(
  p_cod_virgilio text, p_bolsas numeric, p_inyector text, p_legajo text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $fn$
declare v_comp bigint; v_kg numeric; v_claims text; v_res jsonb;
begin
  -- v29.28-envio-iny (marcador: no cambiar)
  if p_bolsas is null or p_bolsas <= 0 or p_bolsas > 500 then
    raise exception 'Bolsas fuera de rango: %', p_bolsas;
  end if;
  select comp_id into v_comp from public."GV_Bolsa_GP2"
   where upper(btrim(cod_virgilio)) = upper(btrim(coalesce(p_cod_virgilio, '')));
  if v_comp is null then
    return jsonb_build_object('ok', true, 'en_gp2', false, 'cod', p_cod_virgilio);
  end if;
  v_kg := coalesce((select valor from "GP2".parametro where clave = 'material_plastico_kg_x_bolsa'), 25);
  -- GP2._autorizado() deja pasar sin claims (backend): se vacían SÓLO durante esta llamada.
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '', true);
  begin
    v_res := "GP2".enviar_material_inyector(p_inyector, v_comp, p_bolsas * v_kg, now(),
      concat_ws(' · ', 'Virgilio: ' || p_bolsas || ' bolsas ' || p_cod_virgilio,
                nullif('legajo ' || coalesce(p_legajo, ''), 'legajo ')));
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v_res || jsonb_build_object('en_gp2', true, 'bolsas', p_bolsas, 'kg_x_bolsa', v_kg, 'cod', p_cod_virgilio);
end $fn$;
revoke all on function public.gv_insumo_envio_inyector(text, numeric, text, text) from public;
-- SIN grant: la función saltea el control de acceso de GP2 (28/09). Queda sin uso hasta que Thomas
-- elija quién la puede llamar (D16). Hoy nadie la llama y el front no la usa.
