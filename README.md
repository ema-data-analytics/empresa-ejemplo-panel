# Empresa Ejemplo · Sistema de Gestión (EMA Data Analytics)

Panel de gestión sobre la base de **prueba** de Tango de Empresa Ejemplo (Supabase `ushvdubzbpctctodujen`).
Empresa Ejemplo es una base de prueba, no una empresa real.

- **Panel:** página estática (`index.html`) publicada con GitHub Pages. El navegador de cada usuario habla directo con Supabase, con SU sesión.
- **Base:** Supabase. Toda la lógica y TODO el control de acceso están en la base (funciones `api_*_v2` y el portero `verificar_acceso`).
- **Versión anterior:** sigue publicada en Google Apps Script (carpeta `apps-script/`, versión 10). No se borró.

## Seguridad

| Qué | Dónde se controla |
|---|---|
| Ingreso | Supabase Auth (usuario y contraseña). |
| Usuario activo, rol activo, permiso por módulo | **En la base**: `verificar_acceso()` corre antes de CADA pedido. Falla cerrado: una función que no está en `seg_funciones` no la puede llamar nadie logueado. |
| Niveles por módulo | `no` (no ve, ni en el menú ni en la base) · `ve` (pantallas, sin CSV ni Imprimir/PDF) · `exporta` (además CSV e Imprimir/PDF). Cobranzas tiene además **carga** (agregar seguimiento), controlada en la base. |
| Ocultar CSV / Imprimir | En la pantalla (los datos que ya ve se podrían copiar igual). |
| Alta de usuarios y blanqueo | Función de Supabase `usuarios` (la única con la clave de servicio, que pone Supabase; no está en este repositorio). Contraseña temporal al azar, se muestra una vez; el cambio en el primer ingreso lo exige la base. |
| Roles | Tabla `seg_roles`. `super` siempre tiene todo y administra Seguridad; no se edita. Un rol nuevo nace sin acceso. |
| Bitácora | `seguridad_bitacora`: ingresos, altas, blanqueos, cambios de usuario, rol y permiso. |

En este repositorio **solo** está la clave publicable (hecha para el navegador). La de servicio nunca va acá.

## Carpetas

| Carpeta | Qué tiene |
|---|---|
| `index.html` | El panel que publica GitHub Pages. **No se edita a mano**: se arma con `herramientas/armar_panel.py`. |
| `fuente/` | Los archivos de la aplicación (los mismos de Apps Script): Index y un archivo por módulo. |
| `herramientas/` | `armar_panel.py` (arma `index.html` y corta si algo no cuadra: anclas, ids o funciones repetidas, claves) y `partes/` con lo nuevo (Seguridad, permisos, contraseña). |
| `supabase/functions/usuarios/` | La función de alta y blanqueo. |
| `sql/` | Migraciones: `14_seguridad_completa.sql`, `14b_portero_rol.sql` y sus pruebas. En `historia/` las anteriores (pasos 1 a 13). |
| `pruebas/` | Prueba de pantalla con base simulada (`node pruebas/prueba_pantalla_seguridad.js`). La prueba en vivo se hace en el sistema real. |
| `apps-script/` | La versión de Apps Script (Codigo.gs y el Index publicado v10). |

## Cómo se publica un cambio

1. Cambiar `fuente/` o `herramientas/partes/`.
2. `python3 herramientas/armar_panel.py` (si corta, no se sube).
3. `node pruebas/prueba_pantalla_seguridad.js` (tiene que dar todo OK).
4. Subir a `main`, esperar a Pages y comparar el SHA-256 de lo publicado con el archivo.
5. Probar en vivo.
