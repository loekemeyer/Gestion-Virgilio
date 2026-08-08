-- =====================================================================
-- equivalencias_familia_secundarios.sql  (v7.90 / v7.91)
--
-- Familias de EQUIVALENTES: mismo producto funcional, MISMA empresa, distinto SKU
-- (principal + secundario/s). Intercambiables para PLANIFICAR/FACTURAR (cambiando la
-- NP en el ERP) pero DISTINTOS para el picking. ⚠ NO incluye pares Loeke↔Chef (se
-- facturan por empresas distintas). Lista curada a mano con el dueño (= EQUIV_FAMILIAS
-- en index.html).
--
-- (A) Alerta Telegram cuando entra un pedido a un código SECUNDARIO (trigger sobre
--     PPP_Base_Pedidos, dedup, mecanismo tg_enqueue → telegram_outbox → tg_outbox_flush).
-- (B) Corrección por NP confirmada por la operadora (Correcciones_Pedido): el picking
--     la levanta para usar el PRINCIPAL sin esperar el resync del ERP.
--
-- Seguridad: anon/authenticated con lo JUSTO — Equivalencias_Familia SELECT;
-- Correcciones_Pedido SELECT+INSERT; vista SELECT. La función de trigger NO es
-- ejecutable por anon (revoke execute). RLS activada en las dos tablas.
-- =====================================================================

-- ── (A) Tabla de familias (secundario → principal) ───────────────────
create table if not exists public."Equivalencias_Familia" (
  cod_secundario text primary key,
  cod_principal  text not null,
  empresa        text,
  descripcion    text,
  actualizado_en timestamptz default now()
);
alter table public."Equivalencias_Familia" enable row level security;
drop policy if exists "equivfam_select" on public."Equivalencias_Familia";
create policy "equivfam_select" on public."Equivalencias_Familia" for select using (true);
revoke insert, update, delete, truncate, references, trigger on public."Equivalencias_Familia" from anon, authenticated;

insert into public."Equivalencias_Familia" (cod_secundario, cod_principal, empresa, descripcion) values
 -- Grupo A (con/sin E, sueltos)
 ('574','574E','LK','Corta Queso De Alambre'),
 ('525','525E','LK','Sacacorcho Cabo Madera'),
 ('580E','580','LK','Batidor Mini'),
 ('702EN','702E','CH','Abrelata Mariposa'),
 ('725','725E','CH','Sacacorcho Cabo Madera'),
 ('323','323E','LK','Rallador'),
 ('565','607E','LK','Pinza De Hielo'),
 -- Grupo B (33x nacional discontinuo ↔ 94xE importada, LK)
 ('338','941E','LK','Espatula Lisa'),
 ('334','942E','LK','Cuchara Ac Inox'),
 ('336','943E','LK','Cucharon Ac Inox'),
 ('332','945E','LK','Espatula/Calada Ac Inox'),
 ('335','946E','LK','Cuchara Calada/Mango'),
 ('333','948E','LK','Espumadera Ac Inox')
on conflict (cod_secundario) do update
  set cod_principal = excluded.cod_principal, empresa = excluded.empresa,
      descripcion = excluded.descripcion, actualizado_en = now();

-- ── (A) Trigger: aviso Telegram por pedido en secundario ─────────────
-- PPP_Base_Pedidos se carga por REEMPLAZO TOTAL (DELETE all + INSERT). Trigger por
-- STATEMENT con transition table `newrows` → escanea lo insertado una vez. dedup_key
-- 'sec_<np>_<cod>' → cada pedido-secundario avisa UNA sola vez (outbox on conflict do
-- nothing). Nunca rompe el sync (exception → return null).
create or replace function public.notificar_pedido_secundario_telegram()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare r record; msg text; enviados int := 0;
begin
  for r in
    select nr.pedido as pedido,
           upper(btrim(nr.articulo)) as art_raw,
           regexp_replace(upper(btrim(nr.articulo)),'^0+(?=.)','') as art_norm,
           ef.cod_principal as ppal, ef.descripcion as desc_prod,
           sum(coalesce(nr.cajas,0)) as cajas
    from newrows nr
    join public."Equivalencias_Familia" ef
      on ef.cod_secundario = regexp_replace(upper(btrim(nr.articulo)),'^0+(?=.)','')
    where nr.pedido is not null and btrim(nr.pedido) <> ''
    group by nr.pedido, upper(btrim(nr.articulo)),
             regexp_replace(upper(btrim(nr.articulo)),'^0+(?=.)',''),
             ef.cod_principal, ef.descripcion
  loop
    msg := '⚠ Pedido en código SECUNDARIO — NP ' || r.pedido || ' pide ' || r.art_raw || '×' || r.cajas
         || E'\n👉 Cambiá la NP en el ERP a ' || r.ppal || coalesce(' (' || r.desc_prod || ')','')
         || E'. No deben entrar pedidos al secundario.';
    perform public.tg_enqueue(msg, 'sec_' || r.pedido || '_' || r.art_norm);
    enviados := enviados + 1;
  end loop;
  if enviados > 0 then perform public.tg_outbox_flush(); end if;
  return null;
exception when others then
  return null;
end $fn$;
revoke execute on function public.notificar_pedido_secundario_telegram() from anon, authenticated, public;

drop trigger if exists trg_pedido_secundario_telegram on public."PPP_Base_Pedidos";
create trigger trg_pedido_secundario_telegram
after insert on public."PPP_Base_Pedidos"
referencing new table as newrows
for each statement execute function public.notificar_pedido_secundario_telegram();

-- Sembrar el backlog inicial como "ya avisado" (para no spamear al prender el trigger):
--   insert cada combo actual con tg_enqueue(dedup 'sec_<np>_<cod>') y luego
--   update telegram_outbox set status='sent' where left(dedup_key,4)='sec_' and status='pending';

-- ── (B) Corrección por NP (operadora confirma → picking levanta el principal) ──
create table if not exists public."Correcciones_Pedido" (
  np             text not null,
  cod_secundario text not null,
  cod_principal  text not null,
  cajas          numeric,
  confirmado_por text,
  confirmado_en  timestamptz default now(),
  primary key (np, cod_secundario)
);
alter table public."Correcciones_Pedido" enable row level security;
drop policy if exists "correcc_select" on public."Correcciones_Pedido";
create policy "correcc_select" on public."Correcciones_Pedido" for select using (true);
drop policy if exists "correcc_insert" on public."Correcciones_Pedido";
create policy "correcc_insert" on public."Correcciones_Pedido" for insert with check (true);
revoke update, delete, truncate, references, trigger on public."Correcciones_Pedido" from anon, authenticated;
-- Confirmación idempotente desde el front: Prefer resolution=ignore-duplicates.

-- Vista para el panel de la operadora: pedidos cargados en secundario que TODAVÍA corren
-- (v7.97: excluye los ya ENTREGADOS — si la NP está en PPP_Entregados_Meta, ya salió).
create or replace view public.vista_pedidos_secundarios
with (security_invoker = true) as
select btrim(b.pedido)          as np,
       upper(btrim(b.articulo)) as cod_secundario,
       ef.cod_principal, ef.descripcion,
       sum(coalesce(b.cajas,0)) as cajas
from public."PPP_Base_Pedidos" b
join public."Equivalencias_Familia" ef
  on ef.cod_secundario = regexp_replace(upper(btrim(b.articulo)),'^0+(?=.)','')
where b.pedido is not null and btrim(b.pedido) <> ''
  and not exists (select 1 from public."PPP_Entregados_Meta" e where btrim(e.np) = btrim(b.pedido))
group by btrim(b.pedido), upper(btrim(b.articulo)), ef.cod_principal, ef.descripcion;
grant select on public.vista_pedidos_secundarios to anon, authenticated;
