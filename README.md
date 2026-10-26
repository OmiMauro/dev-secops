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

Run the whole stack in containers (PostgreSQL + Vault + the production
image, secrets loaded from Vault):

```bash
scripts/stack.sh up
scripts/stack.sh down
```

## Repository layout

| Path | What |
|------|------|
| `src/` | The NestJS API |
| `scripts/security/` | One script per security tool; CI runs the same scripts |
| `docs/` | One guide per step, with exercises |
| `.semgrep/rules/` | Custom SAST rules |
| `policy/terraform/` | Policy as Code (Rego) |
| `terraform/` | AWS infrastructure (scanned, never applied) |

## Architecture

The code is organized **by module** (each feature lives together) and,
inside each module, **by layer**:

```
src/
├── main.ts                   Bootstrap: Vault secrets, helmet, validation, Swagger
├── app.module.ts             Root module: wires config, database and modules
├── config/                   Env validation, database, Vault loader, Swagger
├── common/validators/        Reusable validators (@NoNullBytes)
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
| GET    | /api/docs             | No   | Swagger UI (only with `SWAGGER_ENABLED=true`) |
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
- Security headers with `helmet`; NUL bytes rejected in note fields (both found by ZAP, step 9).

## DevSecOps steps

Each step has a guide with what was added, why, and a "break it" exercise.
Run every static check at once with `scripts/security/all.sh`.

| Step | Topic | Tools | Guide |
|------|-------|-------|-------|
| 0 | Base app | NestJS, TypeORM, PostgreSQL | this README |
| 1 | CI pipeline | GitHub Actions | `.github/workflows/ci.yml` |
| 2 | Secrets in code | gitleaks, pre-commit | [docs/02-secrets.md](docs/02-secrets.md) |
| 3 | Dependencies (SCA) | Trivy, Dependabot, dependency review | [docs/03-dependencies-sca.md](docs/03-dependencies-sca.md) |
| 4 | Static analysis (SAST) | Semgrep + custom rules | [docs/04-sast.md](docs/04-sast.md) |
| 5 | Container image | Distroless, Trivy | [docs/05-container-image.md](docs/05-container-image.md) |
| 6 | SBOM and signing | Syft, Cosign | [docs/06-sbom-signing.md](docs/06-sbom-signing.md) |
| 7 | Infrastructure as Code | Terraform, Checkov, Conftest/OPA | [docs/07-iac.md](docs/07-iac.md) |
| 8 | Secrets in production | Vault, External Secrets | [docs/08-vault.md](docs/08-vault.md) |
| 9 | Dynamic analysis (DAST) | OWASP ZAP | [docs/09-dast.md](docs/09-dast.md) |
| 10 | Full pipeline | GitHub Actions, actionlint, zizmor | [docs/10-pipeline.md](docs/10-pipeline.md) |

Every git commit in the history is one step, so `git show <commit>`
shows exactly what each step changed.

## Requirements

- Node.js 24 (`.nvmrc`)
- Docker: every security tool runs in a container, pinned by digest in
  `scripts/security/images.sh`. Nothing else to install.
- Optional: [pre-commit](https://pre-commit.com) for the git hooks (step 2).
