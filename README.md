# dev-secops

A small NestJS notes API used to practice DevSecOps step by step.
Every stage follows the same loop: **break → detect → fix → block it in the pipeline**.

## Getting started

```bash
cp .env.example .env          # then change DB_PASSWORD and JWT_SECRET
docker compose up -d          # starts PostgreSQL
npm install
npm run start:dev             # API at http://localhost:3000/api
```

Other commands: `npm test`, `npm run lint`, `npm run build`.

Run the whole stack in containers, with the production image:

```bash
docker compose --profile app up -d --build
```

## Architecture

The code is organized **by module** (each feature lives together) and,
inside each module, **by layer**:

```
src/
├── main.ts                   Bootstrap: /api prefix and global validation
├── app.module.ts             Root module: wires config, database and modules
├── config/                   Environment variables and database connection
├── migrations/               Versioned database schema (used in production)
└── modules/
    ├── auth/                 Register, login and JWT protection
    │   ├── controllers/      HTTP → service
    │   ├── services/         Logic (password hashing, issuing tokens)
    │   ├── dto/              Input/output data shapes
    │   ├── guards/           JwtAuthGuard: requires a valid token
    │   └── decorators/       @CurrentUser()
    ├── users/                User model (no endpoints of its own)
    │   ├── entities/
    │   └── services/
    ├── notes/                CRUD for the user's notes
    │   ├── controllers/
    │   ├── services/
    │   ├── entities/
    │   └── dto/
    └── health/               GET /api/health
```

How it maps to MVC:

| MVC         | Here                         | Responsibility                                  |
|-------------|------------------------------|-------------------------------------------------|
| Model       | `entities/`                  | How data is stored (tables)                     |
| View        | `dto/*-response.dto.ts`      | What the client sees (response JSON)            |
| Controller  | `controllers/`               | Receives HTTP, validates, delegates, returns the view |
| (Service)   | `services/`                  | Business logic; knows nothing about HTTP        |

Path of a `POST /api/notes` request:

```
JwtAuthGuard → ValidationPipe(CreateNoteDto) → NotesController.create
            → NotesService.create → Repository<Note> → PostgreSQL
            ← NoteResponseDto.fromEntity ←
```

## Endpoints

| Method | Route                 | Auth | Description                     |
|--------|-----------------------|------|---------------------------------|
| GET    | /api/health           | No   | API status                      |
| POST   | /api/auth/register    | No   | `{ email, password }` → token   |
| POST   | /api/auth/login       | No   | `{ email, password }` → token   |
| GET    | /api/notes?search=    | Yes  | List (and search) my notes      |
| GET    | /api/notes/:id        | Yes  | One note                        |
| POST   | /api/notes            | Yes  | `{ title, content? }`           |
| PATCH  | /api/notes/:id        | Yes  | Update the fields sent          |
| DELETE | /api/notes/:id        | Yes  | Delete                          |

Authenticated routes need the header `Authorization: Bearer <accessToken>`.

## Security built into the base code

- Passwords hashed with bcrypt (never stored in plain text); `passwordHash` has `select: false`.
- Same error for "unknown email" and "wrong password" (no user enumeration).
- `whitelist` + `forbidNonWhitelisted`: fields like `ownerId` cannot be smuggled in.
- Every query filters by `ownerId` → a user cannot read other users' notes (IDOR).
- The app refuses to start if variables are missing or `JWT_SECRET` is too short.
- Postgres is published on `127.0.0.1` only.
- `.env` is in `.gitignore`.

## Roadmap

- [x] 0. Base app
- [x] 1. Pipeline in GitHub Actions (lint, test, build)
- [x] 2. Secrets in code — gitleaks, pre-commit ([guide](docs/02-secrets.md))
- [x] 3. Dependencies and SCA — Trivy, Dependabot ([guide](docs/03-dependencies-sca.md))
- [x] 4. SAST — Semgrep ([guide](docs/04-sast.md))
- [x] 5. Container image — Dockerfile + Trivy ([guide](docs/05-container-image.md))
- [ ] 6. SBOM and signing — Syft, Cosign
- [ ] 7. IaC — Terraform + Checkov
- [ ] 8. Secrets in production — Vault
- [ ] 9. DAST — OWASP ZAP
- [ ] 10. Full pipeline
