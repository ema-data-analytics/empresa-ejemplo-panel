-- Paso 2 del sistema Empresa Ejemplo: Seguridad. Solo agrega objetos nuevos; no toca nada existente.
-- Roles: super (todo + usuarios), admin, usuario. Un usuario nuevo nace INACTIVO y como 'usuario'.
-- El rol nunca se toma de los datos que manda el usuario al registrarse.

-- 1. Perfiles
create table if not exists public.perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nombre      text not null check (length(trim(nombre)) > 0),
  email       text unique,
  rol         text not null default 'usuario' check (rol in ('super','admin','usuario')),
  activo      boolean not null default false,
  creado      timestamptz not null default now(),
  actualizado timestamptz not null default now());
alter table public.perfiles enable row level security;
revoke all on public.perfiles from public, anon, authenticated;
grant select on public.perfiles to authenticated;

-- 2. Bitacora de seguridad (quien cambio que)
create table if not exists public.seguridad_bitacora (
  id bigserial primary key, cuando timestamptz not null default now(),
  quien uuid, accion text not null, sobre uuid, detalle jsonb);
alter table public.seguridad_bitacora enable row level security;
revoke all on public.seguridad_bitacora from public, anon, authenticated;
revoke all on sequence public.seguridad_bitacora_id_seq from public, anon, authenticated;

-- 3. Es super activo (se usa en politicas y funciones)
create or replace function public.es_super() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfiles p where p.id = auth.uid() and p.rol = 'super' and p.activo);
$$;
revoke all on function public.es_super() from public, anon;
grant execute on function public.es_super() to authenticated;

drop policy if exists perfiles_propio on public.perfiles;
create policy perfiles_propio on public.perfiles for select to authenticated using (id = auth.uid());
drop policy if exists perfiles_super on public.perfiles;
create policy perfiles_super on public.perfiles for select to authenticated using (public.es_super());

-- 4. Alta automatica del perfil cuando se crea un usuario (desde Supabase o desde la pantalla Seguridad)
create or replace function public.seg_nuevo_usuario() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, nombre, email)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'nombre'), ''), split_part(coalesce(new.email, 'sin email'), '@', 1)), new.email)
  on conflict (id) do nothing;
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle) values (null, 'alta de usuario (perfil inactivo)', new.id, jsonb_build_object('email', new.email));
  return new;
end $$;
revoke all on function public.seg_nuevo_usuario() from public, anon, authenticated;
drop trigger if exists seg_nuevo_usuario on auth.users;
create trigger seg_nuevo_usuario after insert on auth.users for each row execute function public.seg_nuevo_usuario();

create or replace function public.seg_cambio_email() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    update public.perfiles set email = new.email, actualizado = now() where id = new.id;
  end if;
  return new;
end $$;
revoke all on function public.seg_cambio_email() from public, anon, authenticated;
drop trigger if exists seg_cambio_email on auth.users;
create trigger seg_cambio_email after update of email on auth.users for each row execute function public.seg_cambio_email();

-- 5. Portero: antes de CADA pedido a la API, un usuario logueado tiene que tener perfil ACTIVO.
--    Anonimo y servicio pasan (no tienen acceso a los datos por otro lado). Un usuario anulado queda afuera al instante.
create or replace function public.verificar_acceso() returns void
language plpgsql stable set search_path = '' as $$
begin
  if current_user::text <> 'authenticated' then return; end if;
  if not exists (select 1 from public.perfiles p where p.id = auth.uid() and p.activo) then
    raise exception 'Acceso denegado: usuario sin perfil activo' using errcode = '42501';
  end if;
end $$;
revoke all on function public.verificar_acceso() from public;
grant execute on function public.verificar_acceso() to anon, authenticated, service_role;

-- 6. Funciones de la pantalla Seguridad
create or replace function public.api_seg_yo()
returns table (id uuid, nombre text, email text, rol text, activo boolean)
language sql stable set search_path = '' as $$
  select p.id, p.nombre, p.email, p.rol, p.activo from public.perfiles p where p.id = auth.uid();
$$;

create or replace function public.api_seg_listar()
returns table (id uuid, nombre text, email text, rol text, activo boolean, creado timestamptz, ultimo_ingreso timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query select p.id, p.nombre, p.email, p.rol, p.activo, p.creado, u.last_sign_in_at
    from public.perfiles p left join auth.users u on u.id = p.id order by p.nombre;
end $$;

create or replace function public.api_seg_editar(p_id uuid, p_nombre text, p_rol text, p_activo boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare antes public.perfiles; supers int;
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  select * into antes from public.perfiles where id = p_id for update;
  if not found then raise exception 'No existe el usuario'; end if;
  if p_id = auth.uid() and (p_rol <> 'super' or not p_activo) then
    raise exception 'No podes quitarte el rol super ni anularte a vos mismo';
  end if;
  if antes.rol = 'super' and antes.activo and (p_rol <> 'super' or not p_activo) then
    select count(*) into supers from public.perfiles where rol = 'super' and activo;
    if supers <= 1 then raise exception 'Tiene que quedar al menos un super activo'; end if;
  end if;
  update public.perfiles set nombre = trim(p_nombre), rol = p_rol, activo = p_activo, actualizado = now() where id = p_id;
  insert into public.seguridad_bitacora (quien, accion, sobre, detalle) values (auth.uid(), 'editar perfil', p_id,
    jsonb_build_object('antes', jsonb_build_object('nombre', antes.nombre, 'rol', antes.rol, 'activo', antes.activo),
                       'despues', jsonb_build_object('nombre', trim(p_nombre), 'rol', p_rol, 'activo', p_activo)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_seg_bitacora(p_limite int default 200)
returns table (cuando timestamptz, quien text, accion text, sobre text, detalle jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_super() then raise exception 'No autorizado' using errcode = '42501'; end if;
  return query select b.cuando, coalesce(q.nombre, 'sistema'), b.accion, coalesce(s.nombre, s.email, b.sobre::text), b.detalle
    from public.seguridad_bitacora b left join public.perfiles q on q.id = b.quien left join public.perfiles s on s.id = b.sobre
    order by b.id desc limit greatest(1, least(coalesce(p_limite, 200), 1000));
end $$;

revoke all on function public.api_seg_yo(), public.api_seg_listar(), public.api_seg_editar(uuid,text,text,boolean), public.api_seg_bitacora(int) from public, anon;
grant execute on function public.api_seg_yo(), public.api_seg_listar(), public.api_seg_editar(uuid,text,text,boolean), public.api_seg_bitacora(int) to authenticated;

-- 7. Activar el portero en la API
alter role authenticator set pgrst.db_pre_request to 'public.verificar_acceso';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

select json_build_object('perfiles', to_regclass('public.perfiles')::text, 'bitacora', to_regclass('public.seguridad_bitacora')::text,
  'portero', (select setconfig from pg_db_role_setting s join pg_roles r on r.oid = s.setrole where r.rolname = 'authenticator'),
  'triggers', (select json_agg(tgname) from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal))::text;
