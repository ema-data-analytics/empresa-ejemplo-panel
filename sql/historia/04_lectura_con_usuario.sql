-- Paso 3b: arreglo encontrado en la prueba real con usuario.
-- Las tablas tienen RLS con politica solo para 'anon' (carga), asi que un usuario logueado NO ve filas:
-- las funciones api_* devolvian vacio (el tablero mostraba "—").
-- Arreglo: el sistema lee SOLO por sus funciones _v2, que corren con permiso del dueno (SECURITY DEFINER),
-- con search_path fijo, habilitadas solo a usuarios logueados; el portero exige perfil activo.
-- Las tablas siguen cerradas para lectura directa. Las funciones originales no se tocan.
do $$
declare d text;
begin
  if to_regproc('public.api_fecha_corte_v2') is null then
    d := pg_get_functiondef('public.api_fecha_corte'::regproc);
    d := regexp_replace(d, 'FUNCTION public\.api_fecha_corte\(', 'FUNCTION public.api_fecha_corte_v2(');
    execute d;
  end if;
end $$;
alter function public.api_fecha_corte_v2() security definer set search_path = public, pg_temp;
alter function public.api_ventas_resumen_v2(date, date, integer) security definer set search_path = public, pg_temp;
alter function public.api_ventas_por_mes_v2(date, date, integer) security definer set search_path = public, pg_temp;
alter function public.api_ventas_por_vendedor_v2(date, date, integer) security definer set search_path = public, pg_temp;
alter function public.api_ventas_por_cliente_v2(date, date, integer, integer) security definer set search_path = public, pg_temp;
alter function public.api_ventas_por_articulo_v2(date, date, integer, integer) security definer set search_path = public, pg_temp;
revoke all on function public.api_fecha_corte_v2() from public, anon;
grant execute on function public.api_fecha_corte_v2() to authenticated;
comment on function public.api_fecha_corte_v2() is 'Copia de api_fecha_corte con SECURITY DEFINER para que la lea el usuario logueado. 26/09/2026.';
notify pgrst, 'reload schema';
select 'ok';
