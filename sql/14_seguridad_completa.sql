-- 14 · Seguridad completa (11/11/2026). Empresa Ejemplo · base de prueba ushvdubzbpctctodujen.
-- Agrega roles editables, permisos por módulo (no ve / ve / ve y exporta, + carga en Cobranzas),
-- contraseña temporal con cambio obligatorio y bitácora de ingresos.
-- El control queda EN LA BASE: el portero (verificar_acceso, que PostgREST corre antes de cada pedido)
-- mira qué función se pide, a qué módulo pertenece y qué nivel tiene el rol del usuario.
-- Falla CERRADO: una función que no está en seg_funciones no la puede llamar ningún usuario logueado.
-- Los roles de hoy (super, admin, usuario) quedan con los MISMOS accesos que tienen hoy:
--   super todo; admin todo menos Seguridad; usuario todo menos Legajos y Seguridad. Todos exportan y cargan seguimiento.
-- No se borra nada. Las dos funciones que cambian de cuerpo quedan copiadas al lado con sufijo _antes_20261111.

begin;

-- 0. Respaldo de las dos funciones que cambian (mismo cuerpo, otro nombre)
do $$
declare d text;
begin
  if to_regproc('public.verificar_acceso_antes_20261111') is null then
    d := pg_get_functiondef('public.verificar_acceso()'::regprocedure);
    d := replace(d, 'FUNCTION public.verificar_acceso()', 'FUNCTION public.verificar_acceso_antes_20261111()');
    execute d;
    execute 'revoke all on function public.verificar_acceso_antes_20261111() from public, anon, authenticated';
  end if;
  if to_regproc('public.seg_puede_ver_sueldos_antes_20261111') is null then
    d := pg_get_functiondef('public.seg_puede_ver_sueldos()'::regprocedure);
    d := replace(d, 'FUNCTION public.seg_puede_ver_sueldos()', 'FUNCTION public.seg_puede_ver_sueldos_antes_20261111()');
    execute d;
    execute 'revoke all on function public.seg_puede_ver_sueldos_antes_20261111() from public, anon, authenticated';
  end if;
end $$;

-- 1. Roles
create table if not exists public.seg_roles (
  codigo      text primary key check (codigo ~ '^[a-z][a-z0-9_]{1,29}$'),
  nombre      text not null check (length(trim(nombre)) between 1 and 60),
  descripcion text check (descripcion is null or length(descripcion) <= 300),
  es_sistema  boolean not null default false,
  activo      boolean not null default true,
  creado      timestamptz not null default now(),
  creado_por  uuid);
alter table public.seg_roles enable row level security;
revoke all on public.seg_roles from public, anon, authenticated;
insert into public.seg_roles (codigo, nombre, descripcion, es_sistema) values
  ('super',   'Super',          'Todos los módulos y la administración de usuarios, roles y permisos', true),
  ('admin',   'Administrador',  'Todos los módulos, incluido Legajos y sueldos', true),
  ('usuario', 'Usuario',        'Todos los módulos menos Legajos y sueldos', true)
on conflict (codigo) do nothing;

-- 2. Módulos (pantalla = id de la pantalla en el panel)
create table if not exists public.seg_modulos (
  codigo      text primary key,
  nombre      text not null,
  pantalla    text not null unique,
  orden       int  not null,
  tiene_carga boolean not null default false,
  activo      boolean not null default true);
alter table public.seg_modulos enable row level security;
revoke all on public.seg_modulos from public, anon, authenticated;
insert into public.seg_modulos (codigo, nombre, pantalla, orden, tiene_carga) values
  ('radar',       'Radar · Tablero central', 'Inicio',     1, false),
  ('ventas',      'Ventas',                  'Ventas',     2, false),
  ('cobranzas',   'Cobranzas',               'Cobranzas',  3, true),
  ('compras',     'Compras',                 'Compras',    4, false),
  ('stock',       'Stock',                   'Stock',      5, false),
  ('tesoreria',   'Tesorería',               'Tesoreria',  6, false),
  ('legajos',     'Legajos y sueldos',       'Legajos',    7, false),
  ('activo_fijo', 'Activo Fijo',             'ActivoFijo', 8, false),
  ('iva',         'IVA',                     'IVA',        9, false)
on conflict (codigo) do nothing;

-- 3. Permisos por rol y módulo. El rol super no usa esta tabla: siempre tiene todo.
create table if not exists public.seg_permisos (
  rol             text not null references public.seg_roles(codigo) on update cascade,
  modulo          text not null references public.seg_modulos(codigo),
  nivel           text not null default 'no' check (nivel in ('no', 've', 'exporta')),
  carga           boolean not null default false,
  actualizado     timestamptz not null default now(),
  actualizado_por uuid,
  primary key (rol, modulo),
  check (not carga or nivel <> 'no'));
alter table public.seg_permisos enable row level security;
revoke all on public.seg_permisos from public, anon, authenticated;
insert into public.seg_permisos (rol, modulo, nivel, carga)
select r.codigo, m.codigo,
       case when r.codigo = 'usuario' and m.codigo = 'legajos' then 'no' else 'exporta' end,
       m.tiene_carga
from public.seg_roles r cross join public.seg_modulos m
where r.codigo in ('admin', 'usuario')
on conflict (rol, modulo) do nothing;

-- 4. Qué función pertenece a qué módulo. accion: ve | carga | libre (cualquier usuario activo) | super
create table if not exists public.seg_funciones (
  funcion text primary key,
  modulo  text references public.seg_modulos(codigo),
  accion  text not null check (accion in ('ve', 'carga', 'libre', 'super')),
  check ((accion in ('ve', 'carga')) = (modulo is not null)));
alter table public.seg_funciones enable row level security;
revoke all on public.seg_funciones from public, anon, authenticated;
insert into public.seg_funciones (funcion, modulo, accion) values
  ('api_radar_hoy_v2', 'radar', 've'), ('api_radar_mensual_v2', 'radar', 've'),
  ('api_ventas_lineas_v2', 'ventas', 've'),
  ('api_cobranzas_v2', 'cobranzas', 've'), ('api_cobranzas_seguimiento_v2', 'cobranzas', 've'),
  ('api_cobranzas_seguimiento_agregar_v2', 'cobranzas', 'carga'),
  ('api_compras_comprobantes_v2', 'compras', 've'), ('api_compras_articulos_v2', 'compras', 've'),
  ('api_stock_saldos_v2', 'stock', 've'), ('api_stock_movimientos_v2', 'stock', 've'),
  ('api_tesoreria_cuentas_v2', 'tesoreria', 've'), ('api_tesoreria_movimientos_v2', 'tesoreria', 've'),
  ('api_tesoreria_cheques_v2', 'tesoreria', 've'),
  ('api_legajos_v2', 'legajos', 've'), ('api_legajos_liquidaciones_v2', 'legajos', 've'),
  ('api_legajos_conceptos_v2', 'legajos', 've'), ('api_legajos_recibo_v2', 'legajos', 've'),
  ('api_activo_bienes_v2', 'activo_fijo', 've'), ('api_activo_movimientos_v2', 'activo_fijo', 've'),
  ('api_iva_ventas_v2', 'iva', 've'), ('api_iva_compras_v2', 'iva', 've'),
  ('api_fecha_corte_v2', null, 'libre'), ('seg_puede_ver_sueldos', null, 'libre'),
  ('api_seg_yo', null, 'libre'), ('api_seg_yo_v2', null, 'libre'), ('api_seg_mis_permisos', null, 'libre'),
  ('api_seg_registrar_ingreso', null, 'libre'),
  ('api_seg_listar', null, 'super'), ('api_seg_listar_v2', null, 'super'), ('api_seg_editar', null, 'super'),
  ('api_seg_editar_v2', null, 'super'), ('api_seg_bitacora', null, 'super'),
  ('api_seg_roles', null, 'super'), ('api_seg_rol_guardar', null, 'super'),
  ('api_seg_permisos', null, 'super'), ('api_seg_permiso_guardar', null, 'super'),
  ('es_super', null, 'libre')
on conflict (funcion) do nothing;

-- 5. Perfiles: el rol pasa a ser cualquiera de seg_roles; contraseña temporal
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.perfiles'::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ 'rol'
  loop
    execute format('alter table public.perfiles drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'perfiles_rol_fk') then
    alter table public.perfiles add constraint perfiles_rol_fk foreign key (rol) references public.seg_roles(codigo) on update cascade;
  end if;
end $$;
alter table public.perfiles add column if not exists debe_cambiar_clave boolean not null default false;
alter table public.perfiles add column if not exists clave_temporal_hash text;

-- "Tiene que cambiar la contraseña": se marcó temporal Y la contraseña sigue siendo la temporal.
-- Apenas el usuario la cambia (Supabase guarda otro hash), deja de valer solo, sin que nadie lo apague.
create or replace function public.seg_debe_cambiar_clave(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.debe_cambiar_clave and p.clave_temporal_hash is not distinct from u.encrypted_password
                   from public.perfiles p join auth.users u on u.id = p.id where p.id = p_id), false);
$$;
revoke all on function public.seg_debe_cambiar_clave(uuid) from public, anon, authenticated;

-- 6. Portero nuevo: perfil activo + rol activo + permiso del módulo de la función pedida
create or replace function public.verificar_acceso() returns void
language plpgsql stable security definer set search_path = '' as $$
declare
  v_path text; v_fn text; v_rol text; v_activo boolean; f record; v_nivel text; v_carga boolean; v_mod text;
begin
  if current_user::text <> 'authenticated' then return; end if;
  select p.rol, p.activo into v_rol, v_activo from public.perfiles p where p.id = auth.uid();
  if v_rol is null or not v_activo then
    raise exception 'Acceso denegado: usuario sin perfil activo' using errcode = '42501';
  end if;
  if not exists (select 1 from public.seg_roles r where r.codigo = v_rol and r.activo) then
    raise exception 'Acceso denegado: tu rol está desactivado' using errcode = '42501';
  end if;
  v_path := coalesce(current_setting('request.path', true), '');
  v_fn := substring(v_path from '^/rpc/([A-Za-z0-9_]+)$');
  if v_fn is null then
    raise exception 'Acceso denegado: el sistema solo lee por sus funciones (%)', v_path using errcode = '42501';
  end if;
  select sf.modulo, sf.accion into f from public.seg_funciones sf where sf.funcion = v_fn;
  if not found then
    raise exception 'Acceso denegado: la función % no está habilitada en Seguridad', v_fn using errcode = '42501';
  end if;
  if f.accion = 'libre' then return; end if;
  if public.seg_debe_cambiar_clave(auth.uid()) then
    raise exception 'Tenés que cambiar tu contraseña antes de seguir' using errcode = '42501', hint = 'cambiar_clave';
  end if;
  if v_rol = 'super' then return; end if;
  if f.accion = 'super' then
    raise exception 'Acceso denegado: Seguridad es solo para el rol super' using errcode = '42501';
  end if;
  select sp.nivel, sp.carga into v_nivel, v_carga from public.seg_permisos sp where sp.rol = v_rol and sp.modulo = f.modulo;
  select m.nombre into v_mod from public.seg_modulos m where m.codigo = f.modulo;
  if coalesce(v_nivel, 'no') = 'no' then
    raise exception 'Acceso denegado: tu rol no tiene acceso a %', v_mod using errcode = '42501';
  end if;
  if f.accion = 'carga' and not coalesce(v_carga, false) then
    raise exception 'Acceso denegado: tu rol puede ver % pero no cargar', v_mod using errcode = '42501';
  end if;
end $$;
revoke all on function public.verificar_acceso() from public;
grant execute on function public.verificar_acceso() to anon, authenticated, service_role;

-- 7. Sueldos en el Radar: ahora sale del permiso del módulo Legajos (mismo resultado con los roles de hoy)
create or replace function public.seg_puede_ver_sueldos() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.perfiles p join public.seg_roles r on r.codigo = p.rol and r.activo
    left join public.seg_permisos s on s.rol = p.rol and s.modulo = 'legajos'
    where p.id = auth.uid() and p.activo and (p.rol = 'super' or coalesce(s.nivel, 'no') <> 'no'));
$$;

-- 8. Funciones para el panel
create or replace function public.api_seg_yo_v2()
returns table (id uuid, nombre text, email text, rol text, rol_nombre text, activo boolean, debe_cambiar_clave boolean)
language sql stable security definer set search_path = '' as $$
  select p.id, p.nombre, p.email, p.rol, r.nombre, p.activo, public.seg_debe_cambiar_clave(p.id)
  from public.perfiles p left join public.seg_roles r on r.codigo = p.rol where p.id = auth.uid();
$$;

-- Lo que el usuario puede ver: arma el menú. El super ve todo más Seguridad.
create or replace function public.api_seg_mis_permisos()
returns table (modulo text, nombre text, pantalla text, orden int, nivel text, carga boolean)
language sql stable security definer set search_path = '' as $$
  select m.codigo, m.nombre, m.pantalla, m.orden,
         case when p.rol = 'super' then 'exporta' else coalesce(s.nivel, 'no') end,
         case when p.rol = 'super' then m.tiene_carga else coalesce(s.carga, false) end
  from public.perfiles p join public.seg_roles r on r.codigo = p.rol and r.activo
  cross join public.seg_modulos m
  left join public.seg_permisos s on s.rol = p.rol and s.modulo = m.codigo
  where p.id = auth.uid() and p.activo and m.activo
    and (p.rol = 'super' or coalesce(s.nivel, 'no') <> 'no')
  union all
  select 'seguridad', 'Seguridad', 'Seguridad', 99, 'exporta', true
  from public.perfiles p where p.id = auth.uid() and p.activo and p.rol = 'super'
  order by 4;
$$;

create or replace function public.api_seg_registrar_ingreso()
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle)
  select auth.uid(), 'ingreso', auth.uid(), null where auth.uid() is not null;
$$;

create or replace function public.api_seg_listar_v2()
returns table (id uuid, nombre text, email text, rol text, rol_nombre text, activo boolean,
               debe_cambiar_clave boolean, creado timestamptz, ultimo_ingreso timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query select p.id, p.nombre, p.email, p.rol, r.nombre, p.activo, public.seg_debe_cambiar_clave(p.id),
                      p.creado, u.last_sign_in_at
    from public.perfiles p left join auth.users u on u.id = p.id left join public.seg_roles r on r.codigo = p.rol
    order by p.nombre;
end $$;

-- Editar usuario: como api_seg_editar, pero el rol tiene que existir y estar activo
create or replace function public.api_seg_editar_v2(p_id uuid, p_nombre text, p_rol text, p_activo boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  if not exists (select 1 from public.seg_roles where codigo = p_rol and activo) then
    raise exception 'El rol % no existe o está desactivado', p_rol;
  end if;
  return public.api_seg_editar(p_id, p_nombre, p_rol, p_activo);
end $$;

create or replace function public.api_seg_roles()
returns table (codigo text, nombre text, descripcion text, es_sistema boolean, activo boolean, usuarios bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query select r.codigo, r.nombre, r.descripcion, r.es_sistema, r.activo,
                      (select count(*) from public.perfiles p where p.rol = r.codigo)
    from public.seg_roles r order by r.es_sistema desc, r.nombre;
end $$;

-- Crear o editar un rol. Un rol nuevo nace sin acceso a ningún módulo. El rol super no se toca.
create or replace function public.api_seg_rol_guardar(p_codigo text, p_nombre text, p_descripcion text, p_activo boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare antes public.seg_roles; v_cod text := lower(trim(coalesce(p_codigo, '')));
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  if v_cod = 'super' then raise exception 'El rol super no se puede modificar'; end if;
  if v_cod !~ '^[a-z][a-z0-9_]{1,29}$' then
    raise exception 'Código de rol inválido: solo minúsculas, números y _, empezando con letra (2 a 30)';
  end if;
  if length(trim(coalesce(p_nombre, ''))) = 0 then raise exception 'Falta el nombre del rol'; end if;
  select * into antes from public.seg_roles where codigo = v_cod for update;
  if found then
    if not coalesce(p_activo, true) and exists (select 1 from public.perfiles where rol = v_cod and activo) then
      raise exception 'No se puede desactivar: hay usuarios activos con este rol';
    end if;
    update public.seg_roles set nombre = trim(p_nombre), descripcion = nullif(trim(coalesce(p_descripcion, '')), ''),
           activo = coalesce(p_activo, true) where codigo = v_cod;
  else
    insert into public.seg_roles (codigo, nombre, descripcion, activo, creado_por)
    values (v_cod, trim(p_nombre), nullif(trim(coalesce(p_descripcion, '')), ''), coalesce(p_activo, true), auth.uid());
    insert into public.seg_permisos (rol, modulo, nivel, carga, actualizado_por)
    select v_cod, m.codigo, 'no', false, auth.uid() from public.seg_modulos m;
  end if;
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle) values (auth.uid(),
    case when antes.codigo is null then 'crear rol' else 'editar rol' end, null,
    jsonb_build_object('rol', v_cod, 'antes', to_jsonb(antes) - 'creado' - 'creado_por',
                       'despues', jsonb_build_object('nombre', trim(p_nombre), 'activo', coalesce(p_activo, true))));
  return jsonb_build_object('ok', true, 'codigo', v_cod);
end $$;

create or replace function public.api_seg_permisos(p_rol text)
returns table (modulo text, nombre text, orden int, tiene_carga boolean, nivel text, carga boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query select m.codigo, m.nombre, m.orden, m.tiene_carga,
                      case when p_rol = 'super' then 'exporta' else coalesce(s.nivel, 'no') end,
                      case when p_rol = 'super' then m.tiene_carga else coalesce(s.carga, false) end
    from public.seg_modulos m left join public.seg_permisos s on s.modulo = m.codigo and s.rol = p_rol
    where m.activo order by m.orden;
end $$;

create or replace function public.api_seg_permiso_guardar(p_rol text, p_modulo text, p_nivel text, p_carga boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare antes record; v_carga boolean;
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  if p_rol = 'super' then raise exception 'El rol super siempre tiene todo: no se edita'; end if;
  if not exists (select 1 from public.seg_roles where codigo = p_rol) then raise exception 'No existe el rol %', p_rol; end if;
  if not exists (select 1 from public.seg_modulos where codigo = p_modulo) then raise exception 'No existe el módulo %', p_modulo; end if;
  if p_nivel not in ('no', 've', 'exporta') then raise exception 'Nivel inválido: %', p_nivel; end if;
  v_carga := coalesce(p_carga, false) and p_nivel <> 'no'
             and (select tiene_carga from public.seg_modulos where codigo = p_modulo);
  select nivel, carga into antes from public.seg_permisos where rol = p_rol and modulo = p_modulo;
  insert into public.seg_permisos (rol, modulo, nivel, carga, actualizado, actualizado_por)
  values (p_rol, p_modulo, p_nivel, v_carga, now(), auth.uid())
  on conflict (rol, modulo) do update set nivel = excluded.nivel, carga = excluded.carga,
     actualizado = now(), actualizado_por = auth.uid();
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle) values (auth.uid(), 'cambiar permiso', null,
    jsonb_build_object('rol', p_rol, 'modulo', p_modulo,
      'antes', jsonb_build_object('nivel', antes.nivel, 'carga', antes.carga),
      'despues', jsonb_build_object('nivel', p_nivel, 'carga', v_carga)));
  return jsonb_build_object('ok', true);
end $$;

-- 9. Para la función de usuarios (corre con la clave de servicio dentro de Supabase): marca la contraseña
--    como temporal, deja el perfil activo con su rol y anota en la bitácora quién lo hizo.
create or replace function public.seg_marcar_clave_temporal(p_id uuid, p_quien uuid, p_accion text,
                                                            p_nombre text default null, p_rol text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_rol is not null and not exists (select 1 from public.seg_roles where codigo = p_rol and activo) then
    raise exception 'El rol % no existe o está desactivado', p_rol;
  end if;
  update public.perfiles p set
    debe_cambiar_clave = true,
    clave_temporal_hash = (select u.encrypted_password from auth.users u where u.id = p_id),
    nombre = coalesce(nullif(trim(p_nombre), ''), p.nombre),
    rol = coalesce(p_rol, p.rol),
    activo = case when p_accion = 'crear usuario' then true else p.activo end,
    actualizado = now()
  where p.id = p_id;
  if not found then raise exception 'No existe el perfil del usuario'; end if;
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle)
  values (p_quien, p_accion, p_id, jsonb_build_object('rol', p_rol, 'clave', 'temporal, cambio obligatorio'));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.seg_marcar_clave_temporal(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.seg_marcar_clave_temporal(uuid, uuid, text, text, text) to service_role;

revoke all on function public.api_seg_yo_v2(), public.api_seg_mis_permisos(), public.api_seg_registrar_ingreso(),
  public.api_seg_listar_v2(), public.api_seg_editar_v2(uuid, text, text, boolean), public.api_seg_roles(),
  public.api_seg_rol_guardar(text, text, text, boolean), public.api_seg_permisos(text),
  public.api_seg_permiso_guardar(text, text, text, boolean) from public, anon;
grant execute on function public.api_seg_yo_v2(), public.api_seg_mis_permisos(), public.api_seg_registrar_ingreso(),
  public.api_seg_listar_v2(), public.api_seg_editar_v2(uuid, text, text, boolean), public.api_seg_roles(),
  public.api_seg_rol_guardar(text, text, text, boolean), public.api_seg_permisos(text),
  public.api_seg_permiso_guardar(text, text, text, boolean) to authenticated;

notify pgrst, 'reload schema';
commit;

select json_build_object(
  'roles', (select count(*) from public.seg_roles), 'modulos', (select count(*) from public.seg_modulos),
  'permisos', (select count(*) from public.seg_permisos), 'funciones', (select count(*) from public.seg_funciones),
  'respaldos', (select count(*) from pg_proc where proname like '%_antes_20261111'),
  'perfiles_sin_rol_valido', (select count(*) from public.perfiles p where not exists (select 1 from public.seg_roles r where r.codigo = p.rol))
)::text as resultado;
