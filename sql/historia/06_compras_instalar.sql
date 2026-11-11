-- Paso 5a: Compras para la pantalla interactiva. Dos funciones nuevas; no se toca nada existente.
-- 1) Una fila por comprobante de compra (FAC, N/C, N/D; sin anulados). N/C resta. 1800-01-01 = sin fecha.
create or replace function public.api_compras_comprobantes_v2(p_desde date default null, p_hasta date default null)
returns table (id_cpa04 bigint, fecha date, vencimiento date, t_comp text, n_comp text, signo int, estado text,
  cod_provee text, proveedor text, provincia text, neto numeric, exento numeric, iva numeric, total numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id_cpa04::bigint, c.fecha_emis::date,
         nullif(c.fecha_vto::date, date '1800-01-01'),
         c.t_comp::text, c.n_comp::text,
         case when c.t_comp ~ 'N/C' then -1 else 1 end,
         coalesce(nullif(trim(c.estado), ''), 'sin estado')::text,
         c.cod_provee::text, coalesce(p.nom_provee, 'Proveedor ' || c.cod_provee)::text,
         coalesce(g.nombre_pro, case when nullif(trim(p.provincia::text), '') is null then 'Sin provincia' else 'Sin provincia (codigo ' || trim(p.provincia::text) || ')' end)::text,
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * coalesce(c.importe_ne, 0),
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * coalesce(c.importe_ex, 0),
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * (coalesce(c.imp_iva1,0)+coalesce(c.imp_iva2,0)+coalesce(c.imp_iva3,0)+coalesce(c.imp_iva4,0)+coalesce(c.imp_iva5,0)),
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * coalesce(c.importe_to, 0)
  from public.cpa04 c
  left join lateral (select x.nom_provee, x.provincia from public.cpa01 x where x.cod_provee = c.cod_provee limit 1) p on true
  left join lateral (select y.nombre_pro from public.gva18 y where y.cod_provin = trim(p.provincia::text) limit 1) g on true
  where c.t_comp in ('FAC', 'N/C', 'N/D') and coalesce(c.estado, '') <> 'ANU'
    and (p_desde is null or c.fecha_emis::date >= p_desde)
    and (p_hasta is null or c.fecha_emis::date <= p_hasta)
  order by c.fecha_emis, c.n_comp;
$$;
-- 2) Una fila por renglon de articulo comprado (cpa46), con los datos de su comprobante.
create or replace function public.api_compras_articulos_v2(p_desde date default null, p_hasta date default null)
returns table (id_cpa04 bigint, fecha date, t_comp text, n_comp text, cod_provee text, proveedor text,
  cod_articu text, articulo text, cantidad numeric, precio_unitario numeric, importe numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select l.id_cpa04::bigint, coalesce(nullif(l.fecha_mov::date, date '1800-01-01'), c.fecha_emis::date),
         coalesce(c.t_comp::text, l.tcomp_in_c::text), coalesce(c.n_comp::text, l.ncomp_in_c::text),
         c.cod_provee::text, coalesce(p.nom_provee, 'Proveedor ' || coalesce(c.cod_provee, '?'))::text,
         l.cod_articu::text, coalesce(a.descripcio, 'Articulo ' || l.cod_articu)::text,
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * coalesce(l.cantidad, 0),
         l.precio_net,
         (case when c.t_comp ~ 'N/C' then -1 else 1 end) * coalesce(l.imp_neto_p, coalesce(l.precio_net, 0) * coalesce(l.cantidad, 0))
  from public.cpa46 l
  left join public.cpa04 c on c.id_cpa04 = l.id_cpa04
  left join lateral (select x.nom_provee from public.cpa01 x where x.cod_provee = c.cod_provee limit 1) p on true
  left join lateral (select s.descripcio from public.sta11 s where s.cod_articu = l.cod_articu limit 1) a on true
  where coalesce(c.estado, '') <> 'ANU'
    and (p_desde is null or coalesce(nullif(l.fecha_mov::date, date '1800-01-01'), c.fecha_emis::date) >= p_desde)
    and (p_hasta is null or coalesce(nullif(l.fecha_mov::date, date '1800-01-01'), c.fecha_emis::date) <= p_hasta)
  order by 2, 4;
$$;
revoke all on function public.api_compras_comprobantes_v2(date, date), public.api_compras_articulos_v2(date, date) from public, anon;
grant execute on function public.api_compras_comprobantes_v2(date, date), public.api_compras_articulos_v2(date, date) to authenticated;
comment on function public.api_compras_comprobantes_v2(date, date) is 'Comprobantes de compra para la pantalla interactiva. 26/09/2026.';
comment on function public.api_compras_articulos_v2(date, date) is 'Renglones de articulos comprados para la pantalla interactiva. 26/09/2026.';
notify pgrst, 'reload schema';
select 'instalado' as estado;
