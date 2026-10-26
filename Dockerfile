# syntax=docker/dockerfile:1

# Multi-stage build: tools needed to BUILD the app (TypeScript compiler,
# dev dependencies, npm itself) never reach the final image.
#
# Base images are pinned by digest. Dependabot (docker ecosystem) opens
# a PR when a newer digest is published, e.g. after a security patch.

# ---------- 1. build: compile TypeScript ----------
# Same Debian release (trixie) as the runtime image, so any native module
# built here links against the same glibc.
FROM node:26.11.1-trixie-slim@sha256:193fe51b64e77981119c98c2002c9e32a70e2f006fb4d25068ce0558998917f0 AS build
WORKDIR /app

# Copy only the manifests first: this layer (and npm ci) is cached until
# a dependency changes, instead of on every source change.
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npm run build

# ---------- 2. prod-deps: runtime dependencies only ----------
FROM node:26.11.1-trixie-slim@sha256:193fe51b64e77981119c98c2002c9e32a70e2f006fb4d25068ce0558998917f0 AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---------- 3. runtime: what actually ships ----------
# Distroless: no shell, no package manager, no curl. An attacker who gets
# code execution has almost nothing to work with, and there are far fewer
# packages that can carry CVEs.
# The ":nonroot" variant runs as UID 65532, never as root.
FROM gcr.io/distroless/nodejs24-debian13:nonroot@sha256:cb606325b7ec4af55462cb0b424a53b452a5b4a894ffe841fcf1048d216fb9f8
WORKDIR /app

ENV NODE_ENV=production

# --chown is not needed: files stay owned by root and are only readable
# by the nonroot user, so the app cannot modify its own code.
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./

USER nonroot
EXPOSE 3000

# No curl in distroless, so the health check uses Node's built-in fetch.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", "fetch('http://localhost:3000/api/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

# The distroless entrypoint is already "node".
CMD ["dist/main.js"]
