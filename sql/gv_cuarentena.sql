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
