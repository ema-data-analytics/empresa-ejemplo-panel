// Edge function "usuarios" · Empresa Ejemplo (11/11/2026)
// Alta de usuarios y blanqueo de contraseña desde la pantalla Seguridad.
// Solo la puede usar un usuario con rol super, activo y sin contraseña temporal pendiente.
// La clave de servicio NO está en este archivo: Supabase la pone sola en SUPABASE_SERVICE_ROLE_KEY.
// La contraseña temporal la genera esta función al azar, se muestra UNA vez al super y el usuario
// la tiene que cambiar en su primer ingreso (lo exige la base, no la pantalla).
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_BASE = Deno.env.get("SUPABASE_URL") ?? "";
const CLAVE_PUBLICA = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CLAVE_SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respuesta(cuerpo: unknown, estado = 200) {
  return new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...CORS, "Content-Type": "application/json" } });
}

// 14 caracteres sin los que se confunden (0 O o 1 l I), con mayúscula, minúscula y número.
function claveTemporal(): string {
  const may = "ABCDEFGHJKLMNPQRSTUVWXYZ", min = "abcdefghijkmnpqrstuvwxyz", num = "23456789";
  const todos = may + min + num;
  const r = new Uint32Array(14);
  crypto.getRandomValues(r);
  const c = Array.from(r, (x, i) => (i === 0 ? may : i === 1 ? min : i === 2 ? num : todos)[x % (i === 0 ? may.length : i === 1 ? min.length : i === 2 ? num.length : todos.length)]);
  for (let i = c.length - 1; i > 0; i--) { const j = r[i] % (i + 1); [c[i], c[j]] = [c[j], c[i]]; }
  return c.join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return respuesta({ error: "Método no permitido" }, 405);
  if (!URL_BASE || !CLAVE_PUBLICA || !CLAVE_SERVICIO) return respuesta({ error: "La función no está configurada" }, 500);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return respuesta({ error: "Falta iniciar sesión" }, 401);

  // 1. Quién llama: con SU sesión, la base dice si es super activo y si no tiene la contraseña temporal pendiente
  const comoUsuario = createClient(URL_BASE, CLAVE_PUBLICA, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: yo, error: eYo } = await comoUsuario.rpc("api_seg_yo_v2");
  if (eYo || !yo || !yo.length) return respuesta({ error: "No se pudo verificar tu usuario: " + (eYo?.message ?? "sin perfil") }, 403);
  const quien = yo[0];
  if (quien.rol !== "super" || !quien.activo) return respuesta({ error: "Solo un usuario super puede administrar usuarios" }, 403);
  if (quien.debe_cambiar_clave) return respuesta({ error: "Primero cambiá tu contraseña temporal" }, 403);

  let cuerpo: Record<string, unknown>;
  try { cuerpo = await req.json(); } catch { return respuesta({ error: "Pedido inválido" }, 400); }
  const accion = String(cuerpo.accion ?? "");
  const servicio = createClient(URL_BASE, CLAVE_SERVICIO, { auth: { persistSession: false, autoRefreshToken: false } });

  if (accion === "crear") {
    const email = String(cuerpo.email ?? "").trim().toLowerCase();
    const nombre = String(cuerpo.nombre ?? "").trim();
    const rol = String(cuerpo.rol ?? "").trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respuesta({ error: "El email no es válido" }, 400);
    if (nombre.length < 2 || nombre.length > 80) return respuesta({ error: "Falta el nombre (2 a 80 caracteres)" }, 400);
    if (!rol) return respuesta({ error: "Falta el rol" }, 400);
    const clave = claveTemporal();
    const { data: nuevo, error: eAlta } = await servicio.auth.admin.createUser({
      email, password: clave, email_confirm: true, user_metadata: { nombre },
    });
    if (eAlta || !nuevo?.user) {
      const m = eAlta?.message ?? "sin detalle";
      return respuesta({ error: /already|registered|exists/i.test(m) ? "Ya existe un usuario con ese email" : "No se pudo crear: " + m }, 400);
    }
    const { error: eMarca } = await servicio.rpc("seg_marcar_clave_temporal", {
      p_id: nuevo.user.id, p_quien: quien.id, p_accion: "crear usuario", p_nombre: nombre, p_rol: rol,
    });
    if (eMarca) {
      return respuesta({ error: "El usuario se creó pero quedó INACTIVO: " + eMarca.message + ". Editalo desde la lista." }, 500);
    }
    return respuesta({ ok: true, id: nuevo.user.id, email, clave_temporal: clave });
  }

  if (accion === "blanquear") {
    const id = String(cuerpo.id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return respuesta({ error: "Usuario inválido" }, 400);
    if (id === quien.id) return respuesta({ error: "Para tu propia contraseña usá Cambiar contraseña" }, 400);
    const clave = claveTemporal();
    const { data: act, error: eAct } = await servicio.auth.admin.updateUserById(id, { password: clave });
    if (eAct || !act?.user) return respuesta({ error: "No se pudo blanquear: " + (eAct?.message ?? "sin detalle") }, 400);
    const { error: eMarca } = await servicio.rpc("seg_marcar_clave_temporal", {
      p_id: id, p_quien: quien.id, p_accion: "blanquear contraseña",
    });
    if (eMarca) return respuesta({ error: "La contraseña se cambió pero no quedó marcada como temporal: " + eMarca.message }, 500);
    return respuesta({ ok: true, id, email: act.user.email, clave_temporal: clave });
  }

  return respuesta({ error: "Acción desconocida" }, 400);
});
