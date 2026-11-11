-- 14b · Arreglo del portero (11/11/2026). Error de la migración 14, encontrado por sus pruebas (38 de 44):
-- verificar_acceso pasó a SECURITY DEFINER y adentro current_user es el dueño, no 'authenticated':
-- el portero salía en la primera línea y dejaba pasar todo. Ahora el rol sale del token que PostgREST ya validó.
create or replace function public.verificar_acceso() returns void
language plpgsql stable security definer set search_path = '' as $$
declare
  v_path text; v_fn text; v_rol text; v_activo boolean; f record; v_nivel text; v_carga boolean; v_mod text;
  v_jwt_rol text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  if v_jwt_rol <> 'authenticated' then return; end if;
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
notify pgrst, 'reload config';
select 'portero arreglado' as resultado;
