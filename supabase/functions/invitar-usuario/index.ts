// Invita a un usuario al Portal Vannucci y le asigna rol.
// Solo la puede usar un administrador: se verifica la sesión de quien llama y su rol en public.perfiles.
// La clave de servicio (SUPABASE_SERVICE_ROLE_KEY) solo existe en el servidor de Supabase, nunca en la página.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const PORTAL = 'https://vannucci-app.vercel.app';
const ROLES = ['administrador', 'supervisor', 'orfebre', 'lector'];
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const responder = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder(405, { error: 'Método no permitido' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const auth = req.headers.get('Authorization') ?? '';
  const comoUsuario = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await comoUsuario.auth.getUser();
  if (!user) return responder(401, { error: 'Necesitas iniciar sesión.' });

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const { data: yo } = await admin.from('perfiles').select('rol').eq('user_id', user.id).maybeSingle();
  if (yo?.rol !== 'administrador') return responder(403, { error: 'Solo un administrador puede invitar usuarios.' });

  let body: { email?: string; nombre?: string; rol?: string; orfebre_id?: number | null };
  try { body = await req.json(); } catch { return responder(400, { error: 'Datos inválidos.' }); }
  const email = String(body.email ?? '').trim().toLowerCase();
  const nombre = String(body.nombre ?? '').trim() || email.split('@')[0];
  const rol = String(body.rol ?? 'lector');
  const orfebreId = body.orfebre_id ? Number(body.orfebre_id) : null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return responder(400, { error: 'Correo inválido.' });
  if (!ROLES.includes(rol)) return responder(400, { error: 'Rol inválido.' });
  if (rol === 'orfebre' && !orfebreId) return responder(400, { error: 'Un orfebre debe quedar vinculado a su nombre del taller.' });

  const { data: invitado, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { nombre }, redirectTo: PORTAL });
  if (error) {
    const yaExiste = /already been registered|already exists/i.test(error.message);
    return responder(yaExiste ? 409 : 400, { error: yaExiste ? 'Ese correo ya tiene usuario en el portal; cambia su rol en la tabla.' : 'No se pudo invitar: ' + error.message });
  }

  // El trigger crear_perfil ya creó el perfil como lector: se le asigna el rol pedido.
  const { error: e2 } = await admin.from('perfiles')
    .upsert({ user_id: invitado.user.id, email, nombre, rol, orfebre_id: rol === 'orfebre' ? orfebreId : null }, { onConflict: 'user_id' });
  if (e2) return responder(500, { error: 'Usuario invitado, pero no se pudo asignar el rol: ' + e2.message });

  return responder(200, { ok: true, user_id: invitado.user.id });
});
