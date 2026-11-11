-- Pruebas de la migración 14 (portero por módulo). Todo corre en UNA transacción que se deshace al final:
-- el resultado sale como mensaje de error a propósito ("RESULTADO ...") y no queda nada en la base.
begin;
create function pg_temp.probar(p_uid uuid, p_path text) returns text language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.path', p_path, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.verificar_acceso();
    perform set_config('role', 'none', true);
    return 'PASA';
  exception when others then
    perform set_config('role', 'none', true);
    return 'NO: ' || sqlerrm;
  end;
end $f$;
create function pg_temp.como(p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  execute p_sql into r;
  perform set_config('role', 'none', true);
  return r;
exception when others then
  perform set_config('role', 'none', true);
  return 'ERROR: ' || sqlerrm;
end $f$;

do $$
declare
  sup uuid := (select id from public.perfiles where rol = 'super' and activo order by creado limit 1);
  u_usr uuid := gen_random_uuid(); u_adm uuid := gen_random_uuid(); u_ven uuid := gen_random_uuid();
  u_baja uuid := gen_random_uuid(); u_tmp uuid := gen_random_uuid();
  res text[] := '{}'; n int := 0; fallas int := 0; v text;
begin
  -- usuarios de PRUEBA (se deshacen con la transacción)
  insert into auth.users (id, email, encrypted_password, aud, role) values
    (u_usr, 'prueba.usuario@prueba.local', 'h1', 'authenticated', 'authenticated'),
    (u_adm, 'prueba.admin@prueba.local', 'h2', 'authenticated', 'authenticated'),
    (u_ven, 'prueba.vendedor@prueba.local', 'h3', 'authenticated', 'authenticated'),
    (u_baja, 'prueba.baja@prueba.local', 'h4', 'authenticated', 'authenticated'),
    (u_tmp, 'prueba.temporal@prueba.local', 'h5', 'authenticated', 'authenticated');
  insert into public.seg_roles (codigo, nombre) values ('prueba_vendedor', 'PRUEBA Vendedor');
  insert into public.seg_permisos (rol, modulo, nivel, carga) select 'prueba_vendedor', codigo, 'no', false from public.seg_modulos;
  update public.seg_permisos set nivel = 've' where rol = 'prueba_vendedor' and modulo in ('ventas', 'cobranzas');
  update public.perfiles set activo = true, rol = 'usuario' where id = u_usr;
  update public.perfiles set activo = true, rol = 'admin' where id = u_adm;
  update public.perfiles set activo = true, rol = 'prueba_vendedor' where id = u_ven;
  update public.perfiles set activo = false, rol = 'usuario' where id = u_baja;
  update public.perfiles set activo = true, rol = 'usuario', debe_cambiar_clave = true, clave_temporal_hash = 'h5' where id = u_tmp;

  -- [quien, ruta, esperado (PASA o un pedazo del mensaje)]
  for v in select x from unnest(array[
    'S|/rpc/api_compras_comprobantes_v2|PASA', 'S|/rpc/api_legajos_v2|PASA', 'S|/rpc/api_seg_listar|PASA',
    'S|/rpc/api_seg_permiso_guardar|PASA', 'S|/rpc/api_fecha_corte_v2|PASA', 'S|/rpc/api_seg_listar_v2|PASA',
    'S|/perfiles|solo lee por sus funciones', 'S|/rpc/api_ventas_resumen_v2|no está habilitada',
    'U|/rpc/api_compras_comprobantes_v2|PASA', 'U|/rpc/api_radar_hoy_v2|PASA', 'U|/rpc/api_cobranzas_seguimiento_agregar_v2|PASA',
    'U|/rpc/api_legajos_v2|no tiene acceso a Legajos', 'U|/rpc/api_legajos_recibo_v2|no tiene acceso a Legajos',
    'U|/rpc/api_seg_listar|solo para el rol super', 'U|/rpc/api_seg_editar|solo para el rol super', 'U|/rpc/api_seg_yo_v2|PASA',
    'A|/rpc/api_legajos_v2|PASA', 'A|/rpc/api_iva_ventas_v2|PASA', 'A|/rpc/api_seg_bitacora|solo para el rol super',
    'V|/rpc/api_ventas_lineas_v2|PASA', 'V|/rpc/api_cobranzas_v2|PASA', 'V|/rpc/api_compras_comprobantes_v2|no tiene acceso a Compras',
    'V|/rpc/api_radar_hoy_v2|no tiene acceso a Radar', 'V|/rpc/api_cobranzas_seguimiento_agregar_v2|puede ver Cobranzas pero no cargar',
    'V|/rpc/api_seg_mis_permisos|PASA',
    'B|/rpc/api_seg_yo_v2|sin perfil activo', 'B|/rpc/api_compras_comprobantes_v2|sin perfil activo',
    'T|/rpc/api_compras_comprobantes_v2|cambiar tu contraseña', 'T|/rpc/api_seg_yo_v2|PASA', 'T|/rpc/api_seg_mis_permisos|PASA'
  ]) x loop
    declare q text := split_part(v, '|', 1); ruta text := split_part(v, '|', 2); esp text := split_part(v, '|', 3); r text; uid uuid;
    begin
      uid := case q when 'S' then sup when 'U' then u_usr when 'A' then u_adm when 'V' then u_ven when 'B' then u_baja else u_tmp end;
      r := pg_temp.probar(uid, ruta);
      n := n + 1;
      if (esp = 'PASA' and r = 'PASA') or (esp <> 'PASA' and r like 'NO:%' and position(esp in r) > 0) then
        res := res || ('OK ' || q || ' ' || ruta);
      else
        fallas := fallas + 1; res := res || ('FALLA ' || q || ' ' || ruta || ' esperaba [' || esp || '] dio [' || r || ']');
      end if;
    end;
  end loop;

  -- después de cambiar la contraseña temporal, pasa (sin que nadie apague la marca)
  update auth.users set encrypted_password = 'otra' where id = u_tmp;
  n := n + 1;
  if pg_temp.probar(u_tmp, '/rpc/api_compras_comprobantes_v2') = 'PASA' then res := res || 'OK T cambió la contraseña y ya pasa'::text;
  else fallas := fallas + 1; res := res || 'FALLA T cambió la contraseña y sigue bloqueado'::text; end if;

  -- rol desactivado: queda afuera al instante
  update public.seg_roles set activo = false where codigo = 'prueba_vendedor';
  n := n + 1;
  if pg_temp.probar(u_ven, '/rpc/api_ventas_lineas_v2') like '%rol está desactivado%' then res := res || 'OK V rol desactivado: afuera'::text;
  else fallas := fallas + 1; res := res || 'FALLA V rol desactivado sigue entrando'::text; end if;
  update public.seg_roles set activo = true where codigo = 'prueba_vendedor';

  -- menú y sueldos según rol
  n := n + 1; v := pg_temp.como(u_usr, 'select string_agg(pantalla, '','' order by orden) from public.api_seg_mis_permisos()');
  if v = 'Inicio,Ventas,Cobranzas,Compras,Stock,Tesoreria,ActivoFijo,IVA' then res := res || ('OK menú usuario: ' || v);
  else fallas := fallas + 1; res := res || ('FALLA menú usuario: ' || coalesce(v, 'null')); end if;
  n := n + 1; v := pg_temp.como(sup, 'select count(*)::text from public.api_seg_mis_permisos()');
  if v = '10' then res := res || 'OK menú super: 10'::text; else fallas := fallas + 1; res := res || ('FALLA menú super: ' || v); end if;
  n := n + 1; v := pg_temp.como(u_ven, 'select string_agg(pantalla || '':'' || nivel, '','' order by orden) from public.api_seg_mis_permisos()');
  if v = 'Ventas:ve,Cobranzas:ve' then res := res || ('OK menú vendedor: ' || v); else fallas := fallas + 1; res := res || ('FALLA menú vendedor: ' || coalesce(v, 'null')); end if;
  n := n + 1; v := pg_temp.como(u_usr, 'select public.seg_puede_ver_sueldos()::text') || '/' || pg_temp.como(u_adm, 'select public.seg_puede_ver_sueldos()::text') || '/' || pg_temp.como(sup, 'select public.seg_puede_ver_sueldos()::text');
  if v = 'false/true/true' then res := res || 'OK sueldos usuario/admin/super = no/sí/sí'::text; else fallas := fallas + 1; res := res || ('FALLA sueldos: ' || v); end if;
  -- mismo resultado que la función vieja para los tres roles de hoy
  n := n + 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u_usr, 'role', 'authenticated')::text, true);
  v := (public.seg_puede_ver_sueldos() = public.seg_puede_ver_sueldos_antes_20261111())::text;
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  v := v || '/' || (public.seg_puede_ver_sueldos() = public.seg_puede_ver_sueldos_antes_20261111())::text;
  if v = 'true/true' then res := res || 'OK sueldos igual que antes (usuario, admin)'::text; else fallas := fallas + 1; res := res || ('FALLA sueldos distinto de antes: ' || v); end if;
  n := n + 1; v := pg_temp.como(u_tmp, 'select debe_cambiar_clave::text from public.api_seg_yo_v2()');
  if v = 'false' then res := res || 'OK temporal ya cambiada: api_seg_yo_v2 dice false'::text; else fallas := fallas + 1; res := res || ('FALLA temporal: ' || v); end if;
  -- un no-super no puede cambiar permisos ni aunque llame la función directo
  n := n + 1; v := pg_temp.como(u_adm, 'select public.api_seg_permiso_guardar(''usuario'', ''legajos'', ''exporta'', false)::text');
  if v like 'ERROR: No autorizado%' then res := res || 'OK admin no puede cambiar permisos'::text; else fallas := fallas + 1; res := res || ('FALLA admin cambió permisos: ' || v); end if;
  -- el super no se edita
  n := n + 1; v := pg_temp.como(sup, 'select public.api_seg_permiso_guardar(''super'', ''ventas'', ''no'', false)::text');
  if v like '%siempre tiene todo%' then res := res || 'OK permisos del super no se tocan'::text; else fallas := fallas + 1; res := res || ('FALLA super editable: ' || v); end if;
  -- crear rol y permiso por la función, con bitácora
  n := n + 1; v := pg_temp.como(sup, 'select public.api_seg_rol_guardar(''prueba_rol2'', ''PRUEBA Rol 2'', null, true)::text');
  if v like '%"ok": true%' and (select count(*) from public.seg_permisos where rol = 'prueba_rol2' and nivel = 'no') = 9
     and exists (select 1 from public.seguridad_bitacora where accion = 'crear rol' and detalle->>'rol' = 'prueba_rol2')
  then res := res || 'OK crear rol: 9 módulos en "no" y queda en bitácora'::text; else fallas := fallas + 1; res := res || ('FALLA crear rol: ' || v); end if;
  n := n + 1; v := pg_temp.como(sup, 'select public.api_seg_permiso_guardar(''prueba_rol2'', ''ventas'', ''ve'', true)::text');
  if (select nivel || '/' || carga from public.seg_permisos where rol = 'prueba_rol2' and modulo = 'ventas') = 've/false'
  then res := res || 'OK permiso: Ventas "ve" y la carga se ignora (Ventas no tiene carga)'::text; else fallas := fallas + 1; res := res || ('FALLA permiso: ' || v); end if;
  -- desactivar un rol con usuarios activos no se puede
  n := n + 1; v := pg_temp.como(sup, 'select public.api_seg_rol_guardar(''usuario'', ''Usuario'', null, false)::text');
  if v like '%hay usuarios activos%' then res := res || 'OK no deja desactivar un rol con usuarios activos'::text; else fallas := fallas + 1; res := res || ('FALLA desactivar rol: ' || v); end if;
  -- anónimo: el portero no le cambia nada (y no tiene permiso sobre las funciones)
  n := n + 1;
  if not has_function_privilege('anon', 'public.api_compras_comprobantes_v2(date,date)', 'execute')
     and not has_function_privilege('anon', 'public.api_seg_listar_v2()', 'execute')
     and not has_function_privilege('authenticated', 'public.seg_marcar_clave_temporal(uuid,uuid,text,text,text)', 'execute')
  then res := res || 'OK anónimo sin funciones; seg_marcar_clave_temporal solo para el servicio'::text;
  else fallas := fallas + 1; res := res || 'FALLA permisos de ejecución'::text; end if;

  raise exception 'RESULTADO % de % OK || %', n - fallas, n, array_to_string(res, ' || ');
end $$;
rollback;
