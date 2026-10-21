# Portal Vannucci — Sistema Joyería

Portal del taller de joyería Vannucci: registro de piezas por orfebre, aprobación del Supervisor de Taller, indicadores de productividad y ventas, y maestros (parámetros, modelos, productos y precios, usuarios).

## Arquitectura

- **`index.html`**: la app completa (HTML, CSS y JS en un solo archivo). Usa d3 7.9.0 y supabase-js 2.45.4 desde CDN.
- **Supabase** (proyecto `qrjeknshzeqrodrnnfhv`): base de datos Postgres, inicio de sesión por enlace al correo y permisos con RLS.
- La clave que aparece en `index.html` es la **clave publicable** de Supabase: es pública por diseño. Los permisos los aplica la base de datos, no la página.

Nació como artifact de Claude (<https://claude.ai/artifact/K8xYdkGQwozkqGZ5aRQtoL>), que usaba la base de datos de claude.ai. Esta versión usa Supabase y puede publicarse en cualquier hosting estático (por ejemplo GitHub Pages).

## Base de datos

El esquema está en [`supabase/esquema-propuesto.sql`](supabase/esquema-propuesto.sql) y se aplicó como migraciones en Supabase.

| Tabla / vista | Contenido |
|---|---|
| `piezas` | Todas las piezas (histórico de la planilla y registros del portal) con estado `pendiente`, `aprobada` o `rechazada`. La merma se calcula en la base de datos. |
| `piezas_definitivas` (vista) | Piezas aprobadas con orfebre, mes y calidad (válida, atípica, incompleta). Alimenta los indicadores. |
| `orfebres`, `perfiles` | Orfebres del taller y usuarios con su rol (`supervisor`, `orfebre`, `lector`). |
| `grupos_parametro`, `parametros` | Tonos, piedras, tipos de trabajo, categorías y grupos propios. |
| `modelos`, `productos` | Modelos del taller y catálogo (copia de Bsale del 18-10-2026 más productos del portal). |
| `ventas`, `config` | Ventas y notas de crédito de Bsale (solo supervisor) y metadatos de las cargas. |

### Roles

- **Supervisor de Taller**: ve y aprueba todo; administra maestros, usuarios y ventas.
- **Orfebre**: vinculado a un orfebre del taller; registra piezas a su nombre y ve las suyas y la productividad.
- **Lector**: solo ve la productividad.

Un trigger impide que un orfebre apruebe sus piezas o registre a nombre de otro.

## Puesta en marcha

1. En Supabase → **Authentication → Sign In / Providers**: dejar activo *Email* y desactivar *Allow new users to sign up*.
2. En **Authentication → URL Configuration**: poner como *Site URL* la dirección donde se publique `index.html` (por ejemplo la de GitHub Pages) y agregarla en *Redirect URLs*.
3. Invitar usuarios en **Authentication → Users → Invite user**. Cada uno entra como Lector; el supervisor le asigna su rol en *Maestros → Usuarios*.
4. El primer supervisor se asigna con SQL en el editor de Supabase:
   ```sql
   update public.perfiles set rol = 'supervisor' where email = 'correo@ejemplo.cl';
   ```

## Datos

Los datos de negocio no están en este repositorio. La carga inicial (histórico, catálogo, ventas) se hizo con archivos SQL generados localmente en `datos-importacion/`, carpeta excluida por `.gitignore`.
