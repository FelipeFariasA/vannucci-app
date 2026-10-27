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

  let body: { accion?: string; email?: string; nombre?: string; rol?: string; orfebre_id?: number | null };
  try { body = await req.json(); } catch { return responder(400, { error: 'Datos inválidos.' }); }
  const email = String(body.email ?? '').trim().toLowerCase();

  // Enlace de acceso para un usuario que ya existe: le permite crear o restablecer su contraseña.
  // No envía correo; el administrador lo comparte por otro medio.
  if (body.accion === 'enlace') {
    const { data: perfil } = await admin.from('perfiles').select('user_id').eq('email', email).maybeSingle();
    if (!perfil) return responder(404, { error: 'Ese correo no tiene usuario en el portal.' });
    const gen = await admin.auth.admin.generateLink({ type: 'recovery', email, options: { redirectTo: PORTAL } });
    if (gen.error) return responder(400, { error: 'No se pudo generar el enlace: ' + gen.error.message });
    return responder(200, { ok: true, enlace: gen.data.properties.action_link });
  }

  const nombre = String(body.nombre ?? '').trim() || email.split('@')[0];
  const rol = String(body.rol ?? 'lector');
  const orfebreId = body.orfebre_id ? Number(body.orfebre_id) : null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return responder(400, { error: 'Correo inválido.' });
  if (!ROLES.includes(rol)) return responder(400, { error: 'Rol inválido.' });
  if (rol === 'orfebre' && !orfebreId) return responder(400, { error: 'Un orfebre debe quedar vinculado a su nombre del taller.' });

  const yaExiste = (m: string) => /already been registered|already exists/i.test(m);
  let userId: string;
  let enlace: string | null = null;
  const inv = await admin.auth.admin.inviteUserByEmail(email, { data: { nombre }, redirectTo: PORTAL });
  if (!inv.error) userId = inv.data.user.id;
  else if (yaExiste(inv.error.message)) return responder(409, { error: 'Ese correo ya tiene usuario en el portal; cambia su rol en la tabla.' });
  else {
    // El correo no salió (por ejemplo, el límite de envíos del correo de Supabase): se crea el usuario
    // igual y se devuelve el enlace de invitación para que el administrador lo comparta por otro medio.
    const gen = await admin.auth.admin.generateLink({ type: 'invite', email, options: { data: { nombre }, redirectTo: PORTAL } });
    if (gen.error) {
      if (yaExiste(gen.error.message)) return responder(409, { error: 'Ese correo ya tiene usuario en el portal; cambia su rol en la tabla.' });
      return responder(400, { error: 'No se pudo invitar: ' + gen.error.message });
    }
    userId = gen.data.user.id;
    enlace = gen.data.properties.action_link;
  }

  // El trigger crear_perfil ya creó el perfil como lector: se le asigna el rol pedido.
  const { error: e2 } = await admin.from('perfiles')
    .upsert({ user_id: userId, email, nombre, rol, orfebre_id: rol === 'orfebre' ? orfebreId : null }, { onConflict: 'user_id' });
  if (e2) return responder(500, { error: 'Usuario invitado, pero no se pudo asignar el rol: ' + e2.message });

  return responder(200, { ok: true, user_id: userId, correo_enviado: !enlace, enlace, motivo: enlace ? inv.error!.message : null });
});
