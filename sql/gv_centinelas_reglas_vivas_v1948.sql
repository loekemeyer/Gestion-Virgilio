-- ════════════════════════════════════════════════════════════════════════════════════
-- v19.48 (2026-09-17) — CENTINELAS: "que siempre traigan definiciones vivas y usen las
--                        tablas vigentes" (pedido de Luis, en mayusculas, y con razon)
-- ════════════════════════════════════════════════════════════════════════════════════
-- Viene del problema 390: dos sesiones editaron `trg_normalizar_empresa_stock()` el mismo
-- dia, la segunda partio de una copia vieja y borro una regla de la primera. Nada aviso.
-- Costo 4 tandas con el picking duplicado.
--
-- La prosa en el CLAUDE.md sola no alcanza — ya estaba escrito "no usar la tabla vieja" y
-- se uso igual. Asi que esto es lo que **falla solo**.
--
-- ── 1. GV_Reglas_Centinela + gv_reglas_perdidas ─────────────────────────────────────
-- Una tabla EDITABLE donde cada fila dice: "en tal objeto tiene que seguir apareciendo tal
-- patron, porque tal regla". La vista lista lo que falta. **Vacia = todo bien.**
-- Agregar una regla nueva es un INSERT, no tocar codigo.
--
--   select * from public.gv_reglas_perdidas;
--
-- Las 7 cargadas al 17/09:
--   trg_normalizar_empresa_stock  · gv_empresa_de_articulo   · el articulo manda (v19.26)
--   trg_normalizar_empresa_stock  · npd_                     · NPD sin picking (v19.42)
--   trg_normalizar_empresa_stock  · NOT BETWEEN 4 AND 6      · NP de los dos lados (v18.99)
--   gv_empresa_de_articulo_vivo   · codigos_duales           · un dual contesta NULL (v19.30)
--   gv_empresa_de_articulo_vivo   · Racks_Planimetria        · racks de la tabla viva (v19.27)
--   gv_refrescar_articulo_empresa · Racks_Planimetria        · idem
--   gv_mov_empresa_resuelta       · Racks_Planimetria        · idem
--
-- ── 2. gv_tablas_viejas_en_uso ──────────────────────────────────────────────────────
-- Que objeto sigue leyendo una tabla CONGELADA (`Ubicaciones_Articulos`, ultima escritura
-- 10/08; `PPP_Entregados_Meta`, congelada el 02/09).
--
-- ⚠ **Saca los COMENTARIOS antes de buscar.** La primera version daba 5 y 4 eran falsos
-- positivos: un `-- NO usar Ubicaciones_Articulos` contaba como uso, y los dos centinelas
-- (`gv_fuentes_lugares` y esta misma) nombran esas tablas a proposito. Con los comentarios
-- afuera y esos dos excluidos queda **1 objeto real**:
--
--   `gv_codigos_multigrafia` lee `Ubicaciones_Articulos`.
--
-- No se toco: esa vista busca codigos escritos con varias grafias, y la tabla congelada le
-- sirve de historico. Queda a la vista para decidirlo.
--
-- ── Estado al aplicar ───────────────────────────────────────────────────────────────
--   gv_reglas_perdidas       0
--   gv_tablas_viejas_en_uso  1  (gv_codigos_multigrafia)
--
-- ── El bloque de la regla quedo en los TRES repos ───────────────────────────────────
-- `Gestion-Virgilio` (con los centinelas), `paginach` y `pagina-LK-copia` (version
-- generica, con el md5 del cuerpo normalizado para comparar un .sql del repo contra lo que
-- corre de verdad). Arriba de todo, no al final.
-- ════════════════════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Reglas_Centinela" (
  id bigserial primary key,
  objeto text not null, clase text not null default 'funcion',
  patron text not null, regla text not null,
  quien_pidio text, version text,
  activo boolean not null default true, creado_en timestamptz not null default now());
alter table public."GV_Reglas_Centinela" enable row level security;
revoke insert, update, delete, truncate on public."GV_Reglas_Centinela" from anon, authenticated;
grant select on public."GV_Reglas_Centinela" to anon, authenticated;
create policy "lectura" on public."GV_Reglas_Centinela" for select using (true);

create or replace view public.gv_reglas_perdidas
with (security_invoker = true) as
select r.objeto, r.regla, r.quien_pidio, r.version,
       case when cuerpo is null then 'EL OBJETO NO EXISTE'
            else 'LA REGLA SE PERDIO (alguien reemplazo el objeto con una copia vieja)' end que_paso,
       r.patron
  from public."GV_Reglas_Centinela" r
  left join lateral (
    select case when r.clase = 'vista'
                then (select pg_get_viewdef(c.oid, true) from pg_class c
                       join pg_namespace n on n.oid=c.relnamespace
                      where n.nspname='public' and c.relname=r.objeto and c.relkind in ('v','m'))
                else (select p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                       where n.nspname='public' and p.proname=r.objeto limit 1) end cuerpo
  ) x on true
 where r.activo and (x.cuerpo is null or x.cuerpo !~ r.patron);

create or replace view public.gv_tablas_viejas_en_uso
with (security_invoker = true) as
with viejas(tabla, reemplazo) as (values
  ('Ubicaciones_Articulos','Racks_Planimetria (la de racks viva)'),
  ('PPP_Entregados_Meta','Recepcion Remitos, opcion CRN')),
codigo as (
  select 'funcion' clase, p.oid::regprocedure::text objeto,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','gs'),'--[^\n]*','','g') src
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  union all
  select 'vista', c.relname,
         regexp_replace(regexp_replace(pg_get_viewdef(c.oid,true),'/\*.*?\*/','','gs'),'--[^\n]*','','g')
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind in ('v','m'))
select v.tabla, v.reemplazo, k.clase, k.objeto
  from viejas v join codigo k on k.src like '%'||v.tabla||'%'
 where k.objeto not in ('gv_tablas_viejas_en_uso','gv_fuentes_lugares');
