-- =====================================================================
-- Portal Vannucci: esquema para Supabase
-- Aplicado el 21-10-2026 en el proyecto qrjeknshzeqrodrnnfhv como migración
-- "esquema_inicial_portal_vannucci".
-- Reemplaza la base de datos del artifact (envios, aprobadas, maestro, config).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Esquema privado para funciones auxiliares (no expuesto por la API)
-- ---------------------------------------------------------------------
create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- 1. Orfebres y perfiles (roles)
-- ---------------------------------------------------------------------
create table public.orfebres (
  id         bigint generated always as identity primary key,
  nombre     text not null unique,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Un perfil por usuario de Supabase Auth. El rol NO va en user_metadata
-- (lo puede editar el propio usuario); vive aquí y solo el supervisor lo cambia.
create table public.perfiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  nombre     text,
  rol        text not null default 'lector' check (rol in ('supervisor', 'orfebre', 'lector')),
  orfebre_id bigint references public.orfebres (id),
  creado_en  timestamptz not null default now(),
  constraint orfebre_requiere_vinculo check (rol <> 'orfebre' or orfebre_id is not null)
);
create index perfiles_orfebre_id_idx on public.perfiles (orfebre_id);

-- Rol del usuario actual. SECURITY DEFINER para poder leer perfiles sin
-- recursión de RLS; vive en el esquema privado y solo mira auth.uid().
create or replace function private.rol_actual()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select rol from public.perfiles where user_id = (select auth.uid());
$$;

create or replace function private.orfebre_actual()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select orfebre_id from public.perfiles where user_id = (select auth.uid());
$$;

revoke execute on function private.rol_actual(), private.orfebre_actual() from public, anon;
grant execute on function private.rol_actual(), private.orfebre_actual() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Maestros: parámetros, modelos y productos
-- ---------------------------------------------------------------------
-- Grupos: tonos, piedras, tipos, categorias (base) y los que cree el supervisor.
create table public.grupos_parametro (
  id         text primary key check (id ~ '^[a-z0-9_]+$'),
  nombre     text not null,
  usa_sigla  boolean not null default false,
  es_base    boolean not null default false,
  orden      integer not null default 0
);

create table public.parametros (
  id         bigint generated always as identity primary key,
  grupo_id   text not null references public.grupos_parametro (id) on delete cascade,
  nombre     text not null,
  sigla      text,
  activo     boolean not null default true,
  orden      integer not null default 0,
  unique (grupo_id, nombre)
);

create table public.modelos (
  id             bigint generated always as identity primary key,
  nombre         text not null unique,
  categoria      text,
  codigo_base    text,
  peso_objetivo  numeric(8,2) check (peso_objetivo >= 0),
  alias          text[] not null default '{}',
  notas          text,
  activo         boolean not null default true,
  actualizado_por uuid references auth.users (id),
  actualizado_en  timestamptz not null default now()
);

-- Catálogo: copia inicial desde Bsale (origen = 'bsale') más productos creados
-- en el portal. bsale_original guarda la fila importada para "Volver a los valores de Bsale".
create table public.productos (
  codigo         text primary key check (codigo ~ '^[A-Za-z0-9_\-.~:@+]{1,80}$'),
  nombre         text not null,
  modelo_id      bigint references public.modelos (id),
  categoria      text,
  tono           text,
  piedra         text,
  central_ct     numeric(6,2) check (central_ct >= 0),
  variante       text,
  precio         integer not null default 0 check (precio >= 0),          -- CLP con IVA
  precio_neto    integer generated always as (round(precio / 1.19)::integer) stored,
  atributos      jsonb not null default '{}',                            -- grupos extra: {"tallas": "7"}
  activo         boolean not null default true,
  origen         text not null default 'portal' check (origen in ('bsale', 'portal')),
  bsale_original jsonb,
  editado_por    uuid references auth.users (id),
  editado_en     timestamptz not null default now()
);
create index productos_modelo_id_idx on public.productos (modelo_id);

-- ---------------------------------------------------------------------
-- 3. Piezas (reemplaza envios + aprobadas + histórico de la planilla)
-- ---------------------------------------------------------------------
-- Una sola tabla con estado. Aprobar = cambiar estado; anular = volver a 'pendiente'.
-- Tono, tipo y modelo se guardan como texto, igual que hoy: renombrar un
-- parámetro no reescribe el historial.
create table public.piezas (
  id              bigint generated always as identity primary key,
  orfebre_id      bigint not null references public.orfebres (id),
  autor           uuid references auth.users (id),          -- null en el histórico de la planilla
  fecha           date not null check (fecha <= current_date),
  modelo          text not null,
  modelo_id       bigint references public.modelos (id),
  codigo_producto text,                                     -- texto libre: el formulario admite códigos fuera del catálogo
  tono            text,
  tipo            text,
  cotizacion      text,
  peso_obj        numeric(8,2) check (peso_obj >= 0),
  oro_trabajo     numeric(8,2) not null check (oro_trabajo > 0),
  peso_final      numeric(8,2) check (peso_final >= 0),
  oro_devuelto    numeric(8,2) not null default 0 check (oro_devuelto >= 0),
  merma_g         numeric(9,3) generated always as (oro_trabajo - peso_final - oro_devuelto) stored,
  merma_pct       numeric(7,2) generated always as (round((oro_trabajo - peso_final - oro_devuelto) / oro_trabajo * 100, 2)) stored,
  garantia        boolean not null default false,
  observaciones   text,
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  comentario      text,
  corregida       boolean not null default false,
  revisado_por    uuid references auth.users (id),
  revisado_en     timestamptz,
  origen          text not null default 'portal' check (origen in ('portal', 'planilla')),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  constraint portal_requiere_peso_final check (origen = 'planilla' or peso_final is not null)
);
create index piezas_orfebre_fecha_idx on public.piezas (orfebre_id, fecha);
create index piezas_autor_idx on public.piezas (autor);
create index piezas_modelo_id_idx on public.piezas (modelo_id);
create index piezas_pendientes_idx on public.piezas (creado_en) where estado = 'pendiente';

-- Lo que el orfebre no puede tocar lo fija la base de datos, no la página.
create or replace function private.piezas_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado_en := now();
  if coalesce(private.rol_actual(), '') = 'supervisor' then
    if tg_op = 'UPDATE' and new.estado is distinct from old.estado then
      new.revisado_por := (select auth.uid());
      new.revisado_en := now();
    end if;
    return new;
  end if;
  -- Orfebre: siempre a su nombre, siempre pendiente, sin datos de revisión.
  new.autor := (select auth.uid());
  new.orfebre_id := private.orfebre_actual();
  new.estado := 'pendiente';
  new.origen := 'portal';
  new.comentario := null;
  new.corregida := false;
  new.revisado_por := null;
  new.revisado_en := null;
  if tg_op = 'UPDATE' then
    new.creado_en := old.creado_en;
  end if;
  return new;
end;
$$;

create trigger piezas_proteger
  before insert or update on public.piezas
  for each row execute function private.piezas_proteger();

-- Vista para los indicadores: solo definitivas, con calidad calculada.
create view public.piezas_definitivas
with (security_invoker = true) as
select
  p.*,
  o.nombre as orfebre,
  to_char(p.fecha, 'YYYY-MM') as mes,
  case
    when p.merma_pct is null then 'incompleta'
    when p.merma_pct between -5 and 25 then 'válida'
    else 'atípica'
  end as calidad
from public.piezas p
join public.orfebres o on o.id = p.orfebre_id
where p.estado = 'aprobada';

-- ---------------------------------------------------------------------
-- 4. Ventas (copia de Bsale, solo supervisor)
-- ---------------------------------------------------------------------
create table public.ventas (
  id        bigint generated always as identity primary key,
  doc_id    text not null,
  fecha     date not null,
  sucursal  text not null,
  clase     text not null check (clase in ('Venta', 'Nota de crédito')),
  codigo    text,
  grupo     text,
  modelo    text,
  tono      text,
  piedra    text,
  cantidad  numeric(10,2) not null default 0,
  neto      numeric(14,2) not null          -- sin IVA; negativo en notas de crédito
);
create index ventas_fecha_sucursal_idx on public.ventas (fecha, sucursal);

-- Metadatos de cargas (rango de fechas y fuente de la última copia de Bsale, etc.)
create table public.config (
  clave          text primary key,
  valor          jsonb not null,
  actualizado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 5. Permisos de la API y RLS
-- ---------------------------------------------------------------------
-- Nada para anon: todo el portal requiere sesión.
revoke all on all tables in schema public from anon;

grant select on public.orfebres, public.perfiles, public.grupos_parametro, public.parametros,
                public.modelos, public.productos, public.piezas, public.piezas_definitivas,
                public.ventas, public.config to authenticated;
grant insert, update, delete on public.orfebres, public.perfiles, public.grupos_parametro,
                public.parametros, public.modelos, public.productos, public.piezas,
                public.ventas, public.config to authenticated;

alter table public.orfebres         enable row level security;
alter table public.perfiles         enable row level security;
alter table public.grupos_parametro enable row level security;
alter table public.parametros       enable row level security;
alter table public.modelos          enable row level security;
alter table public.productos        enable row level security;
alter table public.piezas           enable row level security;
alter table public.ventas           enable row level security;
alter table public.config           enable row level security;

-- Perfiles: cada uno ve el suyo; el supervisor ve y administra todos.
create policy perfiles_ver on public.perfiles for select to authenticated
  using (user_id = (select auth.uid()) or (select private.rol_actual()) = 'supervisor');
create policy perfiles_admin on public.perfiles for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

-- Maestros: los lee cualquiera con perfil; solo el supervisor los cambia.
create policy orfebres_ver on public.orfebres for select to authenticated
  using ((select private.rol_actual()) is not null);
create policy orfebres_admin on public.orfebres for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

create policy grupos_ver on public.grupos_parametro for select to authenticated
  using ((select private.rol_actual()) is not null);
create policy grupos_admin on public.grupos_parametro for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

create policy parametros_ver on public.parametros for select to authenticated
  using ((select private.rol_actual()) is not null);
create policy parametros_admin on public.parametros for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

create policy modelos_ver on public.modelos for select to authenticated
  using ((select private.rol_actual()) is not null);
create policy modelos_admin on public.modelos for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

create policy productos_ver on public.productos for select to authenticated
  using ((select private.rol_actual()) is not null);
create policy productos_admin on public.productos for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

-- Piezas:
--   todos con perfil ven las aprobadas (indicadores);
--   el orfebre ve, crea, edita y borra las suyas mientras no estén aprobadas;
--   el supervisor ve y cambia todo.
create policy piezas_ver on public.piezas for select to authenticated
  using (
    (estado = 'aprobada' and (select private.rol_actual()) is not null)
    or autor = (select auth.uid())
    or (select private.rol_actual()) = 'supervisor'
  );
create policy piezas_crear on public.piezas for insert to authenticated
  with check ((select private.rol_actual()) in ('orfebre', 'supervisor'));
create policy piezas_editar_propias on public.piezas for update to authenticated
  using (autor = (select auth.uid()) and estado in ('pendiente', 'rechazada'))
  with check (autor = (select auth.uid()) and estado = 'pendiente');
create policy piezas_borrar_propias on public.piezas for delete to authenticated
  using (autor = (select auth.uid()) and estado in ('pendiente', 'rechazada'));
create policy piezas_supervisor on public.piezas for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

-- Ventas y config: solo el supervisor.
create policy ventas_supervisor on public.ventas for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');
create policy config_supervisor on public.config for all to authenticated
  using ((select private.rol_actual()) = 'supervisor')
  with check ((select private.rol_actual()) = 'supervisor');

-- ---------------------------------------------------------------------
-- 5b. Perfil automático para cada usuario nuevo (entra como lector;
--     el supervisor le asigna el rol después)
-- ---------------------------------------------------------------------
create or replace function private.crear_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfiles (user_id, nombre, rol)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nombre', split_part(new.email, '@', 1)), 'lector')
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke execute on function private.crear_perfil() from public, anon, authenticated;

create trigger crear_perfil_al_registrarse
  after insert on auth.users
  for each row execute function private.crear_perfil();

-- ---------------------------------------------------------------------
-- 6. Datos iniciales (mismos valores por defecto que usa hoy la app)
-- ---------------------------------------------------------------------
insert into public.grupos_parametro (id, nombre, usa_sigla, es_base, orden) values
  ('tonos', 'Tonos de oro', true, true, 1),
  ('piedras', 'Piedras', true, true, 2),
  ('tipos', 'Tipos de trabajo', false, true, 3),
  ('categorias', 'Categorías de producto', false, true, 4);

insert into public.parametros (grupo_id, nombre, sigla, orden) values
  ('tonos', 'Blanco', 'BL', 1), ('tonos', 'Miel', 'MI', 2), ('tonos', 'Amarillo', 'AM', 3), ('tonos', 'Rosado', 'RO', 4),
  ('tonos', 'Rojo', null, 5), ('tonos', 'Platino', null, 6), ('tonos', 'Bicolor', null, 7), ('tonos', 'Plata', null, 8),
  ('piedras', 'Diamante de laboratorio', 'DL', 1), ('piedras', 'Diamante natural', 'DN', 2), ('piedras', 'Moissanita', 'MO', 3),
  ('tipos', 'Fabricación', null, 1), ('tipos', 'Engaste', null, 2), ('tipos', 'Fabricación y engaste', null, 3),
  ('tipos', 'Ajuste', null, 4), ('tipos', 'Terminación', null, 5), ('tipos', 'Reparación', null, 6),
  ('categorias', 'Anillo', null, 1), ('categorias', 'Aros', null, 2), ('categorias', 'Cadena', null, 3),
  ('categorias', 'Colgante', null, 4), ('categorias', 'Pulsera', null, 5), ('categorias', 'Collar', null, 6),
  ('categorias', 'Piercing', null, 7), ('categorias', 'Especial', null, 8), ('categorias', 'Otro', null, 9);

insert into public.orfebres (nombre) values ('José Luis'), ('Antony'), ('Milena'), ('Rubén');
