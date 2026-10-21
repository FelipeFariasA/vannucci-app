# Portal Vannucci — Sistema Joyería

Portal del taller de joyería Vannucci: registro de piezas por orfebre, aprobación del Supervisor de Taller, indicadores de productividad y ventas, y maestros (parámetros, modelos, productos y precios).

## Origen

La app vive como artifact de Claude: <https://claude.ai/artifact/K8xYdkGQwozkqGZ5aRQtoL>

`index.html` es una copia del artifact publicado (versión `1792374181-d30d`, 21-10-2026).

## Dependencias del entorno

La página usa el runtime de artifacts de claude.ai y **no funciona abierta sola en un navegador ni en otro hosting** sin adaptarla:

| Capacidad | Uso |
|---|---|
| `claude.use('user')` | Identifica al usuario y su rol (Editor = Supervisor, Colaborador = Orfebre, Lector) |
| `claude.use('db')` | Base de datos compartida: `envios`, `aprobadas`, `config`, `maestro` |
| `claude.use('downloads')` | Descarga del CSV de productos |
| `assets` | Logo (`/_blob/...`) y archivos de datos (histórico de la planilla, ventas, catálogo Bsale) |

Los datos de negocio (histórico, ventas, catálogo, piezas registradas) **no están en este repositorio**: se cargan en tiempo de ejecución desde la base de datos y los assets del artifact.

## Archivos

- `index.html` — la app completa (HTML, CSS y JS en un solo archivo; usa d3 7.9.0 desde cdnjs).
- `assets/logo-vannucci.png` — logo usado en el encabezado (en el artifact se sirve como `/_blob/9f6e015d297b39a793b64492134420c1`).

## Actualizar

Cuando cambie el artifact, vuelve a copiar su HTML a `index.html` y haz commit.
