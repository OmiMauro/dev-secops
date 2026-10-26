# dev-secops

API de notas en NestJS para practicar DevSecOps paso a paso.
Cada etapa sigue el ciclo: **romper → detectar → arreglar → bloquear en el pipeline**.

## Arrancar

```bash
cp .env.example .env          # y cambia DB_PASSWORD y JWT_SECRET
docker compose up -d          # levanta PostgreSQL
npm install
npm run start:dev             # API en http://localhost:3000/api
```

Otros comandos: `npm test`, `npm run lint`, `npm run build`.

## Arquitectura

Se organiza **por módulo** (cada funcionalidad junta) y, dentro de cada
módulo, **por capa**:

```
src/
├── main.ts                   Arranque: prefijo /api y validación global
├── app.module.ts             Módulo raíz: une config, BD y módulos
├── config/                   Variables de entorno y conexión a la BD
└── modules/
    ├── auth/                 Registro, login y protección con JWT
    │   ├── controllers/      HTTP → servicio
    │   ├── services/         Lógica (hash de contraseñas, emitir tokens)
    │   ├── dto/              Datos de entrada/salida
    │   ├── guards/           JwtAuthGuard: exige token válido
    │   └── decorators/       @CurrentUser()
    ├── users/                Modelo de usuario (sin endpoints propios)
    │   ├── entities/
    │   └── services/
    ├── notes/                CRUD de notas del usuario
    │   ├── controllers/
    │   ├── services/
    │   ├── entities/
    │   └── dto/
    └── health/               GET /api/health
```

Cómo encaja con MVC:

| MVC         | Aquí                         | Responsabilidad                                  |
|-------------|------------------------------|--------------------------------------------------|
| Modelo      | `entities/`                  | Cómo se guardan los datos (tablas)               |
| Vista       | `dto/*-response.dto.ts`      | Qué ve el cliente (JSON de respuesta)            |
| Controlador | `controllers/`               | Recibe HTTP, valida, delega, devuelve la vista   |
| (Servicio)  | `services/`                  | Lógica de negocio; no sabe nada de HTTP          |

Recorrido de una petición `POST /api/notes`:

```
JwtAuthGuard → ValidationPipe(CreateNoteDto) → NotesController.create
            → NotesService.create → Repository<Note> → PostgreSQL
            ← NoteResponseDto.fromEntity ←
```

## Endpoints

| Método | Ruta                  | Auth | Descripción                     |
|--------|-----------------------|------|---------------------------------|
| GET    | /api/health           | No   | Estado de la API                |
| POST   | /api/auth/register    | No   | `{ email, password }` → token   |
| POST   | /api/auth/login       | No   | `{ email, password }` → token   |
| GET    | /api/notes?search=    | Sí   | Lista (y busca) mis notas       |
| GET    | /api/notes/:id        | Sí   | Una nota                        |
| POST   | /api/notes            | Sí   | `{ title, content? }`           |
| PATCH  | /api/notes/:id        | Sí   | Actualiza campos enviados       |
| DELETE | /api/notes/:id        | Sí   | Borra                           |

Rutas con auth: header `Authorization: Bearer <accessToken>`.

## Seguridad que ya trae el código base

- Contraseñas con bcrypt (nunca en claro) y `passwordHash` con `select: false`.
- Mismo error para "email no existe" y "contraseña mala" (no enumera usuarios).
- `whitelist` + `forbidNonWhitelisted`: no se pueden colar campos como `ownerId`.
- Cada consulta filtra por `ownerId` → un usuario no ve notas ajenas (IDOR).
- La app no arranca si faltan variables o `JWT_SECRET` es corto.
- Postgres publicado solo en `127.0.0.1`.
- `.env` en `.gitignore`.

## Hoja de ruta

- [x] 0. App base
- [ ] 1. Pipeline en GitHub Actions (lint, test, build)
- [ ] 2. Secretos en el código — gitleaks, pre-commit
- [ ] 3. Dependencias y SCA — Trivy, Dependabot
- [ ] 4. SAST — Semgrep
- [ ] 5. Imagen de contenedor — Dockerfile + Trivy
- [ ] 6. SBOM y firma — Syft, Cosign
- [ ] 7. IaC — Terraform + Checkov
- [ ] 8. Secretos en producción — Vault
- [ ] 9. DAST — OWASP ZAP
- [ ] 10. Pipeline completo
