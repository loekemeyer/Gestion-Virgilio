-- gv_ppp_web_base_sin_l_chef  (2026-09-16)
-- Guard: un artículo EXCLUSIVAMENTE de Chef nunca lleva sufijo "L" en un pedido web de Chef.
--
-- Contexto: la página de Chef (paginach, admin-supercot.js: isChefSuper / addLSuffix) tenía a
-- Dorinka (WMart Chef / Chango Más, cod 2686) en el grupo de "supers de Chef con L-suffix" junto
-- a Cencosud. Toma el código Chef (ej. 769 "Bombilla Autolimpiante Inox") y le pega la L → 769L.
-- El front de Gestión (pppGuardarWeb → REST a PPP_Web_Base) reescribe esa foto en cada guardado,
-- así que la L reentra y hasta DUPLICA líneas (769 + 769L conviven, clave distinta). Con la L el
-- pipeline trata el artículo como de LK (pkEmpresaArt fuerza LK) → góndola/precio/ISIS equivocados.
--
-- Regla del dueño (Tomás González, 2026-09-16): sólo TdF y Cencosud (Jumbo) de Chef llevan L; los
-- artículos de Chef comunes (como los de Dorinka) NO. Este trigger lo garantiza en el backend:
-- pela la L SÓLO cuando el código base está en la lista de Chef y NO en la de LK (exclusivo de
-- Chef). Los 3 duales (437E, 438E, 809E) y los artículos de Loeke de TdF (500…) quedan intactos.
--
-- PPP_Web_Base es tabla del pipeline web de Gestión; Producción no la referencia (grep 0). Reversible:
--   drop trigger trg_gv_ppp_web_base_sin_l_chef on public."PPP_Web_Base";
--   drop function public.gv_ppp_web_base_sin_l_chef();

create or replace function public.gv_ppp_web_base_sin_l_chef() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if lower(coalesce(new.empresa,'')) = 'chef' and new.articulo ~ 'L$'
     and exists (select 1 from public.precios_venta_chef c
                  where regexp_replace(c.cod,'\s','','g') = regexp_replace(new.articulo,'L$',''))
     and not exists (select 1 from public.precios_venta l
                  where regexp_replace(l.cod,'\s','','g') = regexp_replace(new.articulo,'L$',''))
  then
    new.articulo := regexp_replace(new.articulo,'L$','');
  end if;
  return new;
end $$;

drop trigger if exists trg_gv_ppp_web_base_sin_l_chef on public."PPP_Web_Base";
create trigger trg_gv_ppp_web_base_sin_l_chef
  before insert or update on public."PPP_Web_Base"
  for each row execute function public.gv_ppp_web_base_sin_l_chef();

-- Prueba (transacción revertida): 769L colapsa a 769; 505L (TdF) y 438EL (dual) quedan.
-- begin;
--   insert into public."PPP_Web_Base"(empresa,order_id,np_idx,np_label,articulo,cajas) values
--     ('chef',229,1,'CH 0025','769L',8),('chef',229,1,'CH 0025','505L',1),('chef',229,1,'CH 0025','438EL',1)
--   on conflict (empresa,order_id,np_idx,articulo) do update set cajas=excluded.cajas;
--   select articulo from public."PPP_Web_Base" where order_id=229 order by articulo;  -- 438EL,505L,769,798E,838,840,865E
-- rollback;
