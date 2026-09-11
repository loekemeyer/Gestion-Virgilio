-- ══════════════════════════════════════════════════════════════════════════
-- CUARENTENA — fuente de datos para retener pedidos (idea usuario 8877)
-- ══════════════════════════════════════════════════════════════════════════
-- v14.82 (2026-09-10). Submódulo Cuarentena en "A Programar" (PPP).
--
-- MOTIVO: un pedido no debe salir a Programación si el cliente tiene DEUDA,
-- está SUSPENDIDO o el pedido SUPERA su límite de crédito. Esos datos NO viven
-- en Gestión: se cargan a mano subiendo planillas (.xls) del ERP, desde 4
-- botones del sector Cuarentena:
--   · Importar Búsqueda CL LK  → tipo 'busqueda', empresa 'lk'   (límite + estado/suspendido)
--   · Importar Búsqueda CL CH  → tipo 'busqueda', empresa 'chef'
--   · Importar Deuda LK        → tipo 'deuda',    empresa 'lk'   (saldo adeudado)
--   · Importar Deuda CH        → tipo 'deuda',    empresa 'chef'
--
-- TABLA NUEVA Y DEDICADA (pedido del dueño 2026-09-10: "creá una tabla nueva
-- para esto, nada de usar algo preexistente"). NO se cuelga de `deudores` ni de
-- las tablas de ISIS: se alimenta SOLO con lo que se sube por estos botones.
--
-- Objetos (todos nuevos, prefijo GV_/gv_, RLS on, sin acceso anon):
--   GV_Cuarentena_Fuente          — una fila por cliente por (empresa, tipo).
--   gv_cuarentena_cargar(...)      — REEMPLAZO TOTAL de (empresa, tipo) con lo subido.
--   gv_cuarentena_fuente_resumen() — conteos por (empresa, tipo) para la pantalla.
--
-- Gate de seguridad: es_supervisor_virgilio() (definido en sql/deudores.sql;
-- se REUSA la función de permiso, no datos). Sin sesión de supervisor: rechazo.
--
-- LAYOUT REAL de "Búsqueda CL" (verificado 2026-09-10, LK y CH idénticos, 86 cols):
--   A(0)  Código                    → cod (clave, por empresa)
--   C(2)  Razón Social              → razon_social
--   D(3)  Estado                    → estado (Activo / Suspendido / Sin Cta.Cte.)
--   H(7)  CUIT                      → cuit
--   AV(47) Límite de Crédito        → limite_credito (0 = infinito)
-- suspendido = (Estado ∈ {Suspendido, Sin Cta.Cte.}). El front auto-detecta por
-- encabezado y deja re-mapear. REGLA DE LÍMITE (marcado, fase próxima): un pedido
-- va a cuarentena si al sumarlo al acumulado NO facturado y NO en cuarentena del
-- cliente (con descuentos, sin IVA) se SUPERA su límite; límite 0 = sin tope. Un
-- pedido en cuarentena NO consume crédito hasta que se libere.
--
-- LAYOUT REAL de "Deuda" (verificado 2026-09-10, LK y CH, export Crystal "Ficha
-- Vto.", AGRUPADO — NO es tabla plana): fila 1 encabezados (L = "Pendiente"); por
-- cliente: una CABECERA (A = código texto, B = razón social, sin comprobante) +
-- filas de DETALLE (E = comprobante FCA…, L = pendiente) + una fila SUBTOTAL (sólo
-- L). El total del cliente = SUMA de "Pendiente" (col L) de sus comprobantes; puede
-- ser negativo (saldo a favor). El front lo parsea con `cuarParseDeudaCrystal`.
-- REGLA DE DEUDA (marcado): total > $1.000 → todos los pedidos del cliente a
-- cuarentena. Se guardan todos los clientes; el umbral se aplica al marcar.
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. Tabla fuente ─────────────────────────────────────────────────────────
create table if not exists public."GV_Cuarentena_Fuente" (
  id             bigint generated always as identity primary key,
  empresa        text not null check (empresa in ('lk','chef')),
  tipo           text not null check (tipo in ('busqueda','deuda')),
  cod            text,                 -- código de cliente tal como viene (trim)
  cuit           text,                 -- normalizado a dígitos (11), nullable
  razon_social   text,
  estado         text,                -- de 'busqueda': texto crudo (Activo / Suspendido / Sin Cta.Cte.)
  limite_credito numeric,             -- de 'busqueda' (0 = infinito)
  suspendido     boolean,             -- de 'busqueda': true si estado ∈ {Suspendido, Sin Cta.Cte.}
  deuda          numeric,             -- de 'deuda' (saldo adeudado)
  raw            jsonb,               -- fila original mapeada por encabezado, para re-derivar
  lote           text not null,       -- id de la corrida de importación
  cargado_por    text,
  cargado_at     timestamptz not null default now()
);

create index if not exists gv_cuarentena_fuente_emp_tipo_idx
  on public."GV_Cuarentena_Fuente" (empresa, tipo);
create index if not exists gv_cuarentena_fuente_cod_idx
  on public."GV_Cuarentena_Fuente" (empresa, cod);
create index if not exists gv_cuarentena_fuente_cuit_idx
  on public."GV_Cuarentena_Fuente" (cuit);

comment on table public."GV_Cuarentena_Fuente" is
  'Cuarentena (idea 8877): datos crudos subidos por .xls desde el sector Cuarentena '
  'de A Programar. Una fila por cliente por (empresa, tipo). tipo=busqueda trae '
  'limite_credito + suspendido; tipo=deuda trae deuda. Cada importación reemplaza '
  'TOTAL su (empresa, tipo). Tabla nueva y dedicada, NO cuelga de deudores/ISIS.';

-- RLS: prendida y SIN policies → sólo las funciones SECURITY DEFINER (owner
-- postgres) la tocan. Además revocamos los privilegios directos que toda tabla
-- nueva hereda de los default privileges del schema public (anon/authenticated
-- nacen con INSERT/UPDATE/DELETE abiertos — ver nota en sql/deudores.sql).
alter table public."GV_Cuarentena_Fuente" enable row level security;
revoke all on table public."GV_Cuarentena_Fuente" from anon, authenticated, public;

-- ── 2. Carga (reemplazo total por empresa+tipo) ─────────────────────────────
create or replace function public.gv_cuarentena_cargar(
  p_empresa text,
  p_tipo    text,
  p_rows    jsonb,
  p_lote    text default null
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_n    integer;
  v_lote text := coalesce(nullif(trim(p_lote), ''),
                          to_char(now() at time zone 'America/Argentina/Buenos_Aires',
                                  'YYYYMMDD"T"HH24MISS'));
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not es_supervisor_virgilio() then
    raise exception 'Sólo un supervisor puede importar reportes de cuarentena.'
      using errcode = '42501';
  end if;
  if p_empresa not in ('lk','chef') then raise exception 'empresa inválida: %', p_empresa; end if;
  if p_tipo   not in ('busqueda','deuda') then raise exception 'tipo inválido: %', p_tipo; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows debe ser un array jsonb';
  end if;

  -- reemplazo total de esa fuente
  delete from public."GV_Cuarentena_Fuente" where empresa = p_empresa and tipo = p_tipo;

  insert into public."GV_Cuarentena_Fuente"
    (empresa, tipo, cod, cuit, razon_social, estado, limite_credito, suspendido, deuda, raw, lote, cargado_por)
  select
    p_empresa, p_tipo,
    nullif(trim(r->>'cod'), ''),
    nullif(regexp_replace(coalesce(r->>'cuit',''), '\D', '', 'g'), ''),
    nullif(trim(r->>'razon_social'), ''),
    nullif(trim(r->>'estado'), ''),
    case when nullif(r->>'limite_credito','') is not null then (r->>'limite_credito')::numeric end,
    case when r ? 'suspendido' and jsonb_typeof(r->'suspendido') = 'boolean'
         then (r->>'suspendido')::boolean end,
    case when nullif(r->>'deuda','') is not null then (r->>'deuda')::numeric end,
    coalesce(r->'raw', r),
    v_lote, v_email
  from jsonb_array_elements(p_rows) as r
  where coalesce(nullif(trim(r->>'cod'), ''),
                 nullif(regexp_replace(coalesce(r->>'cuit',''), '\D', '', 'g'), '')) is not null;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.gv_cuarentena_cargar(text,text,jsonb,text) from public, anon;
grant execute on function public.gv_cuarentena_cargar(text,text,jsonb,text) to authenticated, service_role;

comment on function public.gv_cuarentena_cargar(text,text,jsonb,text) is
  'Cuarentena: reemplaza TOTAL las filas de (empresa, tipo) con lo subido por '
  '.xls. Gate es_supervisor_virgilio(). Devuelve cuántas filas quedaron.';

-- ── 3. Resumen por fuente (para la pantalla) ────────────────────────────────
create or replace function public.gv_cuarentena_fuente_resumen()
returns table (
  empresa text, tipo text, filas bigint, con_cuit bigint,
  suspendidos bigint, con_deuda bigint, con_limite bigint,
  lote text, cargado_por text, cargado_at timestamptz
)
language sql security definer set search_path = public as $$
  select f.empresa, f.tipo,
         count(*)                                              as filas,
         count(*) filter (where f.cuit is not null)            as con_cuit,
         count(*) filter (where f.suspendido is true)          as suspendidos,
         count(*) filter (where coalesce(f.deuda,0) > 0)       as con_deuda,
         count(*) filter (where coalesce(f.limite_credito,0)>0) as con_limite,
         max(f.lote)        as lote,
         max(f.cargado_por) as cargado_por,
         max(f.cargado_at)  as cargado_at
  from public."GV_Cuarentena_Fuente" f
  where es_supervisor_virgilio()
  group by f.empresa, f.tipo;
$$;

revoke all on function public.gv_cuarentena_fuente_resumen() from public, anon;
grant execute on function public.gv_cuarentena_fuente_resumen() to authenticated, service_role;

comment on function public.gv_cuarentena_fuente_resumen() is
  'Cuarentena: conteos por (empresa, tipo) de GV_Cuarentena_Fuente para mostrar '
  'debajo de cada botón de importación. Sólo supervisor (si no, 0 filas).';

-- ── v14.86/87: valorización + límite (aplicado por migraciones, la base manda) ──
-- gv_ppp_web_valor_items(empresa,cod,items,cond) — neto sin IVA (criterio Facturación,
--   2% web condicional por condición de pago 8,9,10,11,12,13,18; súper=lista especial).
-- gv_cuarentena_limite(p_pendientes jsonb) — greedy con BASE (armados no facturados) por cliente.
-- gv_cuarentena_marcar / _limite: gate es_supervisor_virgilio() OR gv_es_supervisor_o_servicio()
--   (para que el cron service_role pueda evaluarlos). Volcar con pg_get_functiondef si se recrea.
--
-- ── v14.88: liberar de cuarentena + carga inicial ──
-- GV_Cuarentena_Liberados (tabla) + gv_cuarentena_liberar(empresa,order_id,motivos) +
--   gv_cuarentena_liberados(): un pedido "liberado" sale del sector y va a Pedidos a programar
--   MANTENIENDO el badge; gv_cuarentena_marcar/_limite lo excluyen del sector. Gate supervisor.
-- CARGA INICIAL (2026-09-10, lote 'inicial_20260910') hecha con gv_cuarentena_cargar:
--   lk/busqueda 1283 (202 susp · 817 c/límite), chef/busqueda 763 (211 · 216),
--   lk/deuda 183 (138 >0), chef/deuda 40 (27 >0). Verificado con gv_cuarentena_fuente_resumen().
-- FRONT v14.88: los 4 botones de importación viven en la pestaña "Config. Cuarentena" (PPP,
--   a la derecha de Ocupación); el sector Cuarentena muestra la ficha rediseñada (NP grande,
--   zona, m³, razón social, 3 badges y botón "Enviar a Pedidos a programar") + timer de carga.

-- ============================================================================
-- v14.94 (2026-09-11) — gv_cuarentena_marcar: los SÚPER quedan EXENTOS de la regla de deuda
-- Dueño: "Coto es súper. Los súper no se analiza si tiene o no tiene deuda."
-- Fuente de "es súper": cobranzas_cliente_cadena (empresa, cod_cliente, super_key).
-- OJO: ahí Chef figura como 'ch'; en GV_Cuarentena_Fuente como 'chef' → se normaliza.
-- Estado (suspendido / sin cta. cte.) y límite de crédito NO cambian.
-- Verificado: Coto (lk 801, $132k) y Cencosud (chef 2444, $17,8M) no caen; Villar (4103) sí.
-- Backup de la definición previa: sql/backups/cuarentena_20260911_np56_perez_zarate_y_marcar_pre_super.sql
-- ============================================================================
create or replace function public.gv_cuarentena_marcar(p_pedidos jsonb)
returns table(order_id text, empresa text, motivos text[])
language sql
security definer
set search_path to 'public'
as $function$
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  marca as (
    select p.order_id, p.empresa,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'busqueda'
            and f.cod = p.cod and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'deuda'
            and f.cod = p.cod and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod
                 and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          limit 1)
      ], null) as motivos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.motivos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = m.order_id);
$function$;

-- ════════════════════════════════════════════════════════════════════════════
-- v15.04 (2026-09-11) — EL MOTIVO CON EL MONTO
-- Dueño: *"Que diga ahí el motivo de la cuarentena: ej deuda $10000, límite de
-- crédito superado x $100000, suspendido x pago"*.
--
-- Las dos RPC de marcado pasan a devolver también los NÚMEROS. Cambia el tipo de
-- retorno, así que van con DROP + CREATE (no alcanza CREATE OR REPLACE).
--   · gv_cuarentena_marcar → + deuda numeric, + estado text
--   · gv_cuarentena_limite → + exceso numeric, + limite numeric
-- La lógica de QUIÉN cae en cuarentena NO cambió (misma exención de súper de la
-- v14.94, mismo greedy por límite): sólo se expone el detalle que ya se calculaba.
--
-- ⚠ OJO CON LOS PERMISOS: al dropear y recrear, Supabase le vuelve a dar EXECUTE a
-- `anon` (event trigger propio del proyecto). Las dos son SECURITY DEFINER, así que
-- hay que revocarlo a mano — si no, quedan ejecutables con la anon key pública.
-- Estado correcto (el de antes): postgres, authenticated, service_role.
--
-- ROLLBACK: las definiciones previas están en
-- sql/backups/cuarentena_20260911_marcar_limite_pre_v1504.sql
-- ════════════════════════════════════════════════════════════════════════════

-- ============================================================================
-- v15.58 (2026-09-11) — la cuarentena es de lo PENDIENTE (Edge Function v23)
-- Vivi: "tengo estos mensajes de cuarentena pero no los veo en A Programar". La Edge Function
-- gv-ppp-web-tandas-diarias evaluaba gv_cuarentena_marcar / gv_cuarentena_limite y sincronizaba
-- Planify sobre todo el feed menos gv_pedidos_web_excluidos, sin sacar lo que ya tiene tanda en
-- PPP_Web_Programacion ni lo que está en un borrador (PPP_Web_Tanda_Items). Abría tareas a Viviana
-- por NP ya programadas y contaba dos veces al programado en el greedy del límite (base + pendiente).
-- Ahora `pedidosYaTomados` los saca antes de evaluar, igual que hace A Programar. Las RPC de acá NO
-- cambiaron. §3.ch de docs/SUPABASE-GESTION-VIRGILIO.md.
-- ============================================================================
