FROM node:22-alpine AS build

WORKDIR /app

# Pinned to the version that produced pnpm-lock.yaml.
RUN npm install -g pnpm@11.21.0

# The build does not render PDFs, so skip puppeteer's Chromium download.
ENV PUPPETEER_SKIP_DOWNLOAD=true

# `--frozen-lockfile` installs exactly what pnpm-lock.yaml pins and fails if it
# is out of date with package.json, so image builds are reproducible.
# pnpm-workspace.yaml holds the allowBuilds list for dependency install scripts.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm run build

# Drop dev-only packages before they are copied into the runtime image. The
# `puppeteer` devDependency bundles its own Chromium (hundreds of MB) that
# production never uses — production runs puppeteer-core with
# @sparticuz/chromium.
RUN pnpm prune --prod


FROM node:22-alpine AS production

WORKDIR /app

ENV NODE_ENV=production

# Chromium needs these at runtime; the Alpine base does not ship them.
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=build --chown=nextjs:nodejs /app/.next ./.next
COPY --from=build --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=build --chown=nextjs:nodejs /app/public ./public

USER nextjs

EXPOSE 3000
CMD ["npm", "start"]
