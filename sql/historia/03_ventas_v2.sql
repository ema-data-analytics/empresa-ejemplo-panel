-- Paso 4a (Ventas): copias _v2 de las funciones de ventas que leen la vista de costo corregida (vista_venta_linea_v2).
-- Las originales NO se tocan. Solo cambia la vista que leen.
do $$
declare f text; d text; n int;
begin
  foreach f in array array['api_ventas_resumen','api_ventas_por_mes','api_ventas_por_vendedor','api_ventas_por_cliente','api_ventas_por_articulo'] loop
    if exists (select 1 from pg_proc where proname = f || '_v2' and pronamespace = 'public'::regnamespace) then
      raise exception '% _v2 ya existe: no se pisa', f; end if;
    d := pg_get_functiondef(('public.' || f)::regproc);
    n := (select count(*) from regexp_matches(d, 'vista_venta_linea\M', 'g'));
    if n = 0 then raise exception '% no lee vista_venta_linea', f; end if;
    d := regexp_replace(d, 'vista_venta_linea\M', 'vista_venta_linea_v2', 'g');
    d := regexp_replace(d, 'FUNCTION public\.' || f || '\(', 'FUNCTION public.' || f || '_v2(');
    execute d;
    execute format('revoke all on function public.%I(%s) from public, anon', f || '_v2', pg_get_function_identity_arguments((f || '_v2')::regproc));
    execute format('grant execute on function public.%I(%s) to authenticated', f || '_v2', pg_get_function_identity_arguments((f || '_v2')::regproc));
    execute format('comment on function public.%I(%s) is %L', f || '_v2', pg_get_function_identity_arguments((f || '_v2')::regproc),
      'Copia de ' || f || ' que lee vista_venta_linea_v2 (costo con 1800-01-01 = sin fecha). 26/09/2026.');
  end loop;
end $$;
notify pgrst, 'reload schema';
-- PRUEBAS
with r1 as (select * from public.api_ventas_resumen(null, null, null)),
     r2 as (select * from public.api_ventas_resumen_v2(null, null, null)),
     vv as (select * from public.vista_venta_linea_v2 where estado_comprobante <> 'ANU')
select json_agg(json_build_array(p, esperado, obtenido, case when esperado = obtenido then 'PASA' else 'FALLA' end))::text from (values
 ('01 existen las 5 funciones _v2', '5', (select count(*)::text from pg_proc where pronamespace='public'::regnamespace and proname in ('api_ventas_resumen_v2','api_ventas_por_mes_v2','api_ventas_por_vendedor_v2','api_ventas_por_cliente_v2','api_ventas_por_articulo_v2'))),
 ('02 ninguna abierta al anonimo', '0', (select count(*)::text from pg_proc where pronamespace='public'::regnamespace and proname like 'api\_ventas\_%\_v2' and has_function_privilege('anon', oid, 'execute'))),
 ('03 las 5 habilitadas al usuario logueado', '5', (select count(*)::text from pg_proc where pronamespace='public'::regnamespace and proname like 'api\_ventas\_%\_v2' and has_function_privilege('authenticated', oid, 'execute'))),
 ('04 ninguna _v2 lee la vista vieja', '0', (select count(*)::text from pg_proc where pronamespace='public'::regnamespace and proname like 'api\_ventas\_%\_v2' and prosrc ~ 'vista_venta_linea([^_]|$)')),
 ('05 venta total igual a la vieja', (select venta_neta_total::text from r1), (select venta_neta_total::text from r2)),
 ('06 venta total = suma directa de la vista v2', (select round(sum(importe_con_signo),2)::text from vv), (select venta_neta_total::text from r2)),
 ('07 margen v2 = suma directa (sin filtro de dias)', (select round(sum(margen_con_signo),2)::text from vv where tiene_costo), (select margen_neto::text from r2)),
 ('08 ventas por mes suman la venta total', (select venta_neta_total::text from r2), (select round(sum(t.venta_total),2)::text from public.api_ventas_por_mes_v2(null,null,null) t)),
 ('09 margen por mes suma el margen total', (select margen_neto::text from r2), (select round(sum(t.margen_neto),2)::text from public.api_ventas_por_mes_v2(null,null,null) t)),
 ('10 ventas por vendedor suman la venta total', (select venta_neta_total::text from r2), (select round(sum(t.venta_total),2)::text from public.api_ventas_por_vendedor_v2(null,null,null) t)),
 ('11 ventas por cliente suman la venta total', (select venta_neta_total::text from r2), (select round(sum(t.venta_total),2)::text from public.api_ventas_por_cliente_v2(null,null,100000,null) t)),
 ('12 la funcion vieja no cambio (margen -2253544.08)', '-2253544.08', (select margen_neto::text from r1))
) t(p, esperado, obtenido);
