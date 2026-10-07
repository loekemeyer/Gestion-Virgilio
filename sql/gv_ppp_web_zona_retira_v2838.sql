-- v28.38 (Luis, 07/10/2026, D9): LA ZONA DE UN RETIRA ES SIEMPRE «Retira».
-- Luis, textual: "LA ZONA DE UN RETIRA ES SIEMPRE RETIRA PORQUE NO LE MANDAMOS UN RETIRA A UNA
-- DIRECCION A UN CLIENTE SINO QUE LO VIENEN A BUSCAR".
--
-- Caso: pedido 1448 (Silvano, LK 4282) eligió la sucursal «Retira» (Virgilio 2788), pero esa fila de
-- la ficha no tiene zona y el feed le dejó la de su otra dirección (San Miguel → Zona 6). La tanda E92A
-- quedó como Zona 6 aunque salió el 25/09 como «Retira cliente».
--
-- Arreglo: trigger BEFORE INSERT/UPDATE en PPP_Web_Programacion: si el pedido dice Retira
-- (gv_es_retira_fila: dirección/barrio exacto «Retira», Virgilio 2788, «Exp. Retira»), zona := 'Retira'.
-- Lo cubre aunque la Edge Function reescriba la fila cada 5 min con la zona del feed.
--
-- Datos (D8, Luis: "PONELE A E92A QUE ES UNA TANDA DE RETIRA"): las 4 filas del pedido 1448 pasan a
-- zona Retira; LK 0252 queda en E92A. Backup: zz_backups."GV_Backup_PPPWebProg_1448_20261007".
--
-- Rollback:
--   alter table public."PPP_Web_Programacion" disable trigger gv_ppp_web_zona_retira;
--   update public."PPP_Web_Programacion" w set zona = b.zona
--     from zz_backups."GV_Backup_PPPWebProg_1448_20261007" b
--    where w.empresa = b.empresa and w.order_id = b.order_id and w.np = b.np;

create table if not exists zz_backups."GV_Backup_PPPWebProg_1448_20261007" as
  select * from public."PPP_Web_Programacion" where lower(empresa) = 'lk' and order_id = 1448;
alter table zz_backups."GV_Backup_PPPWebProg_1448_20261007" enable row level security;

create or replace function public.gv_ppp_web_zona_retira()
returns trigger language plpgsql as $$
begin
  -- v28.38-zona-retira: un Retira no va a una dirección; lo vienen a buscar.
  if public.gv_es_retira_fila(new.barrio, null, new.direccion)
     and coalesce(btrim(new.zona), '') !~* '^retira$' then
    new.zona := 'Retira';
  end if;
  return new;
end $$;

create or replace trigger gv_ppp_web_zona_retira
  before insert or update on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_zona_retira();

update public."PPP_Web_Programacion"
   set zona = 'Retira'
 where lower(empresa) = 'lk' and order_id = 1448 and coalesce(zona, '') <> 'Retira';

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_ppp_web_zona_retira', 'funcion', 'gv_es_retira_fila',
       'La zona de un Retira es siempre Retira (no se manda a una dirección, lo vienen a buscar)',
       'Luis', 'v28.38'
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_ppp_web_zona_retira');
