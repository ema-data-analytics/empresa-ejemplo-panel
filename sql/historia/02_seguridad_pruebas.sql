-- Pruebas de Seguridad. Crea 3 usuarios de prueba SIN contrasena, prueba todo y DESHACE todo al final
-- (la ultima linea tira un error a proposito para que nada quede guardado).
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  res text := ''; n int; m text; t text;
begin
  insert into auth.users (id, email, aud, role, raw_user_meta_data) values
    (a, 'prueba_a@prueba.local', 'authenticated', 'authenticated', '{"nombre":"Prueba A","rol":"super"}'),
    (b, 'prueba_b@prueba.local', 'authenticated', 'authenticated', '{}'),
    (c, 'prueba_c@prueba.local', 'authenticated', 'authenticated', '{}');

  select count(*) into n from public.perfiles where id in (a,b,c) and rol = 'usuario' and not activo;
  res := res || 'P01 alta crea perfil usuario INACTIVO (ignora rol super del registro): ' || case when n = 3 then 'PASA' else 'FALLA ' || n end || chr(10);
  select nombre into t from public.perfiles where id = a;
  res := res || 'P02 nombre tomado del registro: ' || case when t = 'Prueba A' then 'PASA' else 'FALLA ' || coalesce(t,'-') end || chr(10);

  -- preparacion: a = super activo, b = usuario activo, c queda inactivo
  update public.perfiles set rol = 'super', activo = true where id = a;
  update public.perfiles set activo = true where id = b;

  -- portero
  begin perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.verificar_acceso(); reset role;
    res := res || 'P03 portero deja pasar usuario activo: PASA' || chr(10);
  exception when others then res := res || 'P03 portero deja pasar usuario activo: FALLA ' || sqlerrm || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.verificar_acceso(); reset role;
    res := res || 'P04 portero frena usuario INACTIVO: FALLA (paso)' || chr(10);
  exception when others then res := res || 'P04 portero frena usuario INACTIVO: PASA (' || sqlerrm || ')' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.verificar_acceso(); reset role;
    res := res || 'P05 portero frena usuario sin perfil (registro por su cuenta): FALLA (paso)' || chr(10);
  exception when others then res := res || 'P05 portero frena usuario sin perfil: PASA' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    set local role anon; perform public.verificar_acceso(); reset role;
    res := res || 'P06 portero deja pasar anonimo (carga del servidor sigue andando): PASA' || chr(10);
  exception when others then res := res || 'P06 portero deja pasar anonimo: FALLA ' || sqlerrm || chr(10); end;

  -- lo que ve cada uno
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated; select count(*) into n from public.perfiles; reset role;
  res := res || 'P07 usuario comun ve solo su perfil (1): ' || case when n = 1 then 'PASA' else 'FALLA ' || n end || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; select count(*) into n from public.perfiles; reset role;
  res := res || 'P08 super ve todos (3): ' || case when n = 3 then 'PASA' else 'FALLA ' || n end || chr(10);

  begin perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
    set local role authenticated; perform * from public.api_seg_listar(); reset role;
    res := res || 'P09 usuario comun NO puede listar usuarios: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P09 usuario comun NO puede listar usuarios: PASA' || chr(10); end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; select count(*) into n from public.api_seg_listar(); reset role;
  res := res || 'P10 super lista usuarios (3): ' || case when n = 3 then 'PASA' else 'FALLA ' || n end || chr(10);

  begin perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
    set local role authenticated; update public.perfiles set rol = 'super' where id = b; reset role;
    res := res || 'P11 usuario NO puede darse rol super por su cuenta: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P11 usuario NO puede darse rol super por su cuenta: PASA' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.api_seg_editar(b, 'B', 'super', true); reset role;
    res := res || 'P12 usuario NO puede usar editar: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P12 usuario NO puede usar editar: PASA' || chr(10); end;

  begin perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.api_seg_editar(a, 'A', 'admin', true); reset role;
    res := res || 'P13 super NO puede quitarse el rol: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P13 super NO puede quitarse el rol: PASA' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.api_seg_editar(a, 'A', 'super', false); reset role;
    res := res || 'P14 super NO puede anularse: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P14 super NO puede anularse: PASA' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.api_seg_editar(b, 'B', 'jefe', true); reset role;
    res := res || 'P15 rol inexistente rechazado: FALLA (acepto)' || chr(10);
  exception when others then res := res || 'P15 rol inexistente rechazado: PASA' || chr(10); end;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.api_seg_editar(b, 'Usuario B', 'admin', true);
  perform public.api_seg_editar(c, 'Usuario C', 'usuario', true);
  reset role;
  select string_agg(rol || '/' || activo, ',' order by email) into t from public.perfiles where id in (b, c);
  res := res || 'P16 super cambia rol y activa a otros: ' || case when t = 'admin/true,usuario/true' then 'PASA' else 'FALLA ' || coalesce(t,'-') end || chr(10);

  begin perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.verificar_acceso(); reset role;
    res := res || 'P17 usuario activado entra al instante: PASA' || chr(10);
  exception when others then res := res || 'P17 usuario activado entra al instante: FALLA ' || sqlerrm || chr(10); end;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; perform public.api_seg_editar(c, 'Usuario C', 'usuario', false); reset role;
  begin perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    set local role authenticated; perform public.verificar_acceso(); reset role;
    res := res || 'P18 usuario anulado queda afuera al instante: FALLA (paso)' || chr(10);
  exception when others then res := res || 'P18 usuario anulado queda afuera al instante: PASA' || chr(10); end;

  -- dos supers: el otro si puede bajarlo; y nunca queda 0 super
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; perform public.api_seg_editar(b, 'Usuario B', 'super', true); reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated; perform public.api_seg_editar(a, 'Prueba A', 'usuario', true); reset role;
  select count(*) into n from public.perfiles where rol = 'super' and activo and id in (a, b, c);
  res := res || 'P19 un super baja a otro super y queda al menos uno (1): ' || case when n = 1 then 'PASA' else 'FALLA ' || n end || chr(10);

  select count(*) into n from public.seguridad_bitacora where sobre in (a, b, c);
  res := res || 'P20 todo quedo en la bitacora (3 altas + 5 cambios = 8): ' || case when n = 8 then 'PASA' else 'FALLA ' || n end || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated; select count(*) into n from public.api_seg_bitacora(50); reset role;
  res := res || 'P21 super lee la bitacora: ' || case when n >= 8 then 'PASA' else 'FALLA ' || n end || chr(10);
  begin perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    set local role authenticated; perform * from public.api_seg_bitacora(50); reset role;
    res := res || 'P22 no super NO lee la bitacora: FALLA (pudo)' || chr(10);
  exception when others then res := res || 'P22 no super NO lee la bitacora: PASA' || chr(10); end;
  begin perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
    set local role authenticated; select count(*) into n from public.seguridad_bitacora; reset role;
    res := res || 'P23 nadie lee la bitacora directo: FALLA (pudo, ' || n || ')' || chr(10);
  exception when others then res := res || 'P23 nadie lee la bitacora directo: PASA' || chr(10); end;

  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated; select string_agg(nombre || '/' || rol || '/' || activo, ',') into t from public.api_seg_yo(); reset role;
  res := res || 'P24 cada uno ve su propio perfil (api_seg_yo): ' || case when t = 'Usuario C/usuario/false' then 'PASA' else 'FALLA ' || coalesce(t,'-') end || chr(10);

  update auth.users set email = 'prueba_c_nuevo@prueba.local' where id = c;
  select email into t from public.perfiles where id = c;
  res := res || 'P25 cambio de email se copia al perfil: ' || case when t = 'prueba_c_nuevo@prueba.local' then 'PASA' else 'FALLA ' || coalesce(t,'-') end || chr(10);

  select string_agg(p || '=' || has_function_privilege('anon', p, 'execute')::text, ',') into t
    from unnest(array['public.es_super()','public.api_seg_yo()','public.api_seg_listar()','public.api_seg_editar(uuid,text,text,boolean)','public.api_seg_bitacora(integer)']) p;
  res := res || 'P26 anonimo no puede ejecutar ninguna funcion de seguridad: ' || case when t !~ 'true' then 'PASA' else 'FALLA ' || t end || chr(10);
  select count(*) into n from information_schema.role_table_grants where table_schema = 'public' and table_name in ('perfiles','seguridad_bitacora') and grantee = 'anon';
  res := res || 'P27 anonimo sin permisos sobre perfiles y bitacora: ' || case when n = 0 then 'PASA' else 'FALLA ' || n end || chr(10);

  delete from auth.users where id = c;
  select count(*) into n from public.perfiles where id = c;
  res := res || 'P28 borrar usuario en Supabase borra su perfil: ' || case when n = 0 then 'PASA' else 'FALLA' end || chr(10);

  raise exception 'RESULTADOS (todo deshecho)%', chr(10) || res;
end $$;
