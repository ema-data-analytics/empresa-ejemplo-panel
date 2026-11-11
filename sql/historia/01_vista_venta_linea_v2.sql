-- Paso 1 del sistema Empresa Ejemplo (aprobado 26/09): vista de ventas con costo corregido, AL LADO de la actual.
-- Cambio unico: en sta_auditoria_costo_compra, fecha_comprobante 1800-01-01 = "sin fecha" -> se usa fecha_ingreso.
-- No se toca public.vista_venta_linea.
do $$
declare d text; d2 text; n1 int; n2 int; r record;
begin
  if to_regclass('public.vista_venta_linea_v2') is not null then raise exception 'vista_venta_linea_v2 ya existe: no se pisa'; end if;
  d := pg_get_viewdef('public.vista_venta_linea'::regclass, true);
  n1 := (length(d) - length(replace(d, 'h.fecha_comprobante <= c.fecha_emis', ''))) / length('h.fecha_comprobante <= c.fecha_emis');
  n2 := (length(d) - length(replace(d, 'ORDER BY h.fecha_comprobante DESC', ''))) / length('ORDER BY h.fecha_comprobante DESC');
  if n1 <> 1 or n2 <> 1 then raise exception 'La definicion no tiene los textos esperados (% / %)', n1, n2; end if;
  d2 := replace(d,  'h.fecha_comprobante <= c.fecha_emis',
                    'COALESCE(NULLIF(h.fecha_comprobante::date, ''1800-01-01''::date), h.fecha_ingreso::date) <= c.fecha_emis::date');
  d2 := replace(d2, 'ORDER BY h.fecha_comprobante DESC',
                    'ORDER BY COALESCE(NULLIF(h.fecha_comprobante::date, ''1800-01-01''::date), h.fecha_ingreso::date) DESC, h.fecha_ingreso DESC, h.id_sta_auditoria_costo_compra DESC');
  execute 'create view public.vista_venta_linea_v2 as ' || d2;
  -- mismos permisos que la vista original
  execute 'revoke all on public.vista_venta_linea_v2 from public, anon, authenticated';
  for r in select grantee, privilege_type from information_schema.role_table_grants
           where table_schema='public' and table_name='vista_venta_linea' and grantee in ('anon','authenticated','service_role') loop
    execute format('grant %s on public.vista_venta_linea_v2 to %I', r.privilege_type, r.grantee);
  end loop;
  execute 'comment on view public.vista_venta_linea_v2 is ''Igual a vista_venta_linea pero 1800-01-01 = sin fecha (usa fecha_ingreso). Creada 26/09/2026.''';
end $$;
-- PRUEBAS
with v1 as (select * from public.vista_venta_linea), v2 as (select * from public.vista_venta_linea_v2),
ind as (  -- calculo independiente, sin la vista
  select g.t_comp, g.n_comp, g.n_rengl_v,
    (select h.precio_u_l_actual from public.sta_auditoria_costo_compra h
      where h.cod_articu=g.cod_articu and coalesce(h.precio_u_l_actual,0)>0
        and (case when h.fecha_comprobante::date = date '1800-01-01' then h.fecha_ingreso::date else h.fecha_comprobante::date end) <= c.fecha_emis::date
      order by (case when h.fecha_comprobante::date = date '1800-01-01' then h.fecha_ingreso::date else h.fecha_comprobante::date end) desc, h.fecha_ingreso desc, h.id_sta_auditoria_costo_compra desc limit 1) k2
  from public.gva53 g join public.gva12 c on c.n_comp=g.n_comp and c.t_comp=g.t_comp)
select json_agg(json_build_array(p, esperado, obtenido, case when esperado=obtenido then 'PASA' else 'FALLA' end))::text from (values
 ('1 Filas v2 = filas v1', (select count(*) from v1)::text, (select count(*) from v2)::text),
 ('2 Venta total igual', (select sum(importe_con_signo) from v1)::text, (select sum(importe_con_signo) from v2)::text),
 ('3 Renglones con costo de compra real: identicos', '0', (select count(*) from v1 join v2 using (t_comp,n_comp,n_rengl_v) where v1.origen_costo='compra real' and (v2.costo_renglon is distinct from v1.costo_renglon or v2.origen_costo<>'compra real'))::text),
 ('4 Ningun renglon usa costo 1800 como fecha anterior', '0', (select count(*) from v2 x where x.origen_costo='historia de costo' and not exists (select 1 from public.sta_auditoria_costo_compra h where h.cod_articu=x.cod_articu and coalesce(h.precio_u_l_actual,0)>0 and (case when h.fecha_comprobante::date=date '1800-01-01' then h.fecha_ingreso::date else h.fecha_comprobante::date end) <= x.fecha::date))::text),
 ('5 Costo historia = calculo independiente renglon por renglon', '0', (select count(*) from v2 x join ind i using (t_comp,n_comp,n_rengl_v) where x.origen_costo='historia de costo' and x.costo_renglon is distinct from i.k2*coalesce(x.cantidad,0))::text),
 ('6 Renglones historia en v2 = renglones con costo independiente sin compra real', (select count(*) from ind i join v2 x using (t_comp,n_comp,n_rengl_v) where i.k2 is not null and x.fecha_compra_usada is null and x.tiene_articulo)::text, (select count(*) from v2 where origen_costo='historia de costo')::text),
 ('7 Margen v2 (calculo independiente previo: 299885)', '299885', (select round(sum(margen_con_signo))::text from v2 where tiene_costo and estado_comprobante<>'ANU')),
 ('8 La vista original no cambio (margen -2253544)', '-2253544', (select round(sum(margen_con_signo))::text from v1 where tiene_costo and estado_comprobante<>'ANU')),
 ('9 Permisos iguales a la original', (select coalesce(string_agg(grantee||':'||privilege_type, ',' order by grantee, privilege_type),'') from information_schema.role_table_grants where table_schema='public' and table_name='vista_venta_linea' and grantee in ('anon','authenticated','service_role')),
                                       (select coalesce(string_agg(grantee||':'||privilege_type, ',' order by grantee, privilege_type),'') from information_schema.role_table_grants where table_schema='public' and table_name='vista_venta_linea_v2' and grantee in ('anon','authenticated','service_role')))
) t(p, esperado, obtenido);
