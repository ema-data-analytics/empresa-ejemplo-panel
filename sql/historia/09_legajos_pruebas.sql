-- PRUEBAS Legajos (solo lectura: todo se deshace al final). Se simula el usuario super (Anibal) y un usuario sin perfil.
do $$
declare res text := ''; n numeric; m numeric; k numeric; t text; u uuid := 'a7581332-ef44-4d49-af7a-ffc85b943ce2';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  select count(*) into k from public.api_legajos_v2();
  res := res || 'L01 legajos = filas de legajo_cloud (' || (select count(*) from public.legajo_cloud) || '): ' || k || case when k = (select count(*) from public.legajo_cloud) then ' PASA' else ' FALLA' end || chr(10);
  select count(*), sum(neto), sum(haberes) into k, m, n from public.api_legajos_liquidaciones_v2();
  res := res || 'L02 recibos = filas de tot_liquidacion (' || (select count(*) from public.tot_liquidacion) || '): ' || k || case when k = (select count(*) from public.tot_liquidacion) then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'L03 neto y haberes = tot_liquidacion (' || (select round(sum(tot_neto), 2) || ' / ' || round(sum(tot_haberes), 2) from public.tot_liquidacion) || '): ' || m || ' / ' || n
    || case when m = (select round(sum(tot_neto), 2) from public.tot_liquidacion) and n = (select round(sum(tot_haberes), 2) from public.tot_liquidacion) then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_legajos_liquidaciones_v2() where abs(neto - (haberes + asignaciones + no_remunerativo - retenciones)) >= 0.01;
  res := res || 'L04 en cada recibo neto = haberes + asignaciones + no remunerativo - retenciones (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_legajos_liquidaciones_v2() r
    join (select l.id_tot_liquidacion, sum(l.imp_liquidado) filter (where c.tipo_concepto = 1) h, sum(l.imp_liquidado) filter (where c.tipo_concepto in (2, 5)) re,
                 sum(l.imp_liquidado) filter (where c.tipo_concepto in (4, 6, 7)) nr, sum(l.imp_liquidado) filter (where c.tipo_concepto = 8) co
          from public.liquidacion l join public.concepto c using (id_concepto) group by 1) x on x.id_tot_liquidacion = r.id_tot_liquidacion
    where abs(r.haberes - coalesce(x.h, 0)) >= 0.01 or abs(r.retenciones - coalesce(x.re, 0)) >= 0.01 or abs(r.no_remunerativo - coalesce(x.nr, 0)) >= 0.01 or abs(r.contribuciones - coalesce(x.co, 0)) >= 0.01;
  res := res || 'L05 totales de cada recibo = suma de sus renglones por tipo de concepto (0 diferencias): ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select round(sum(importe), 2) into m from public.api_legajos_conceptos_v2();
  select round(sum(imp_liquidado), 2) into n from public.liquidacion;
  res := res || 'L06 conceptos agrupados = suma de liquidacion (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select id_tot_liquidacion into k from public.api_legajos_liquidaciones_v2() where haberes > 0 limit 1;
  select round(sum(importe) filter (where tipo_concepto = 1), 2) into m from public.api_legajos_recibo_v2(k::bigint);
  select haberes into n from public.api_legajos_liquidaciones_v2() where id_tot_liquidacion = k;
  res := res || 'L07 un recibo: sus haberes = total del recibo (' || n || '): ' || m || case when m = n then ' PASA' else ' FALLA' end || chr(10);
  select count(*) into n from public.api_legajos_liquidaciones_v2() r where not exists (select 1 from public.api_legajos_v2() l where l.id_legajo = r.id_legajo);
  res := res || 'L08 recibos de legajos que no estan en el maestro: ' || n || case when n = 0 then ' PASA' else ' FALLA' end || chr(10);
  select count(*) filter (where activo), count(*) filter (where not activo) into k, n from public.api_legajos_v2();
  res := res || 'L09 legajos activos / egresados: ' || k || ' / ' || n || chr(10);
  select string_agg(tipo || ':' || c, ', ') into t from (select tipo, count(*) c from public.api_legajos_liquidaciones_v2() group by 1 order by 2 desc) x;
  res := res || 'L10 recibos por tipo de liquidacion: ' || t || chr(10);
  select min(periodo) || ' a ' || max(periodo) into t from public.api_legajos_liquidaciones_v2();
  res := res || 'L11 periodos: ' || t || chr(10);
  select count(*) into k from public.api_legajos_liquidaciones_v2('2023-01-01', '2023-12-31');
  select count(*) into n from public.tot_liquidacion t join public.dato_fijo d using (id_dato_fijo) where d.per_liquidacion::date between '2023-01-01' and '2023-12-31';
  res := res || 'L12 filtro 2023 = recibos 2023 (' || n || '): ' || k || case when k = n then ' PASA' else ' FALLA' end || chr(10);
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  select count(*) into k from public.api_legajos_v2();
  select count(*) into m from public.api_legajos_liquidaciones_v2();
  select count(*) into n from public.api_legajos_recibo_v2(1);
  res := res || 'L13 un usuario sin rol super/admin no ve nada (legajos, recibos, renglones): ' || k || ', ' || m || ', ' || n || case when k + m + n = 0 then ' PASA' else ' FALLA' end || chr(10);
  res := res || 'L14 anonimo no puede ejecutar: ' || case when not has_function_privilege('anon', 'public.api_legajos_v2()', 'execute') and not has_function_privilege('anon', 'public.api_legajos_liquidaciones_v2(date,date)', 'execute') and not has_function_privilege('anon', 'public.api_legajos_recibo_v2(bigint)', 'execute') then 'PASA' else 'FALLA' end || chr(10);
  raise exception 'RESULTADOS (solo lectura)%', chr(10) || res;
end $$;
