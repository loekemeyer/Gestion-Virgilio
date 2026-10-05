-- v26.73 · PASO 2 de 3 · CORRER EN EL PROYECTO DE CHEF (nkhzocgdpwtgrmwleihr), SQL Editor.
-- Copiar TODO este archivo (termina en «FIN PASO 2») y apretar Run. Tiene que decir «Success».
-- La puerta: sólo entra quien tiene el token. El token vive en el Vault de LK
-- (KRIKOS_CHEF_TOKEN); acá queda sólo su sha256, así que este archivo no tiene nada secreto.
-- Rollback: drop function public.krikos_crear_pedido_super(text, jsonb);

create or replace function public.krikos_crear_pedido_super(p_token text, p_order jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if p_token is null
     or encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
        <> '7e2fb177e09403b13cbc42cd7abcf09ab912868b9d6f6937e5ddb1d7c625f155' then
    raise exception 'krikos_crear_pedido_super: token inválido' using errcode = '28000';
  end if;
  return public._krikos_insert_pedido(p_order, false);
end
$fn$;

revoke all on function public.krikos_crear_pedido_super(text, jsonb) from public;
grant execute on function public.krikos_crear_pedido_super(text, jsonb) to anon, authenticated, service_role;
-- FIN PASO 2
