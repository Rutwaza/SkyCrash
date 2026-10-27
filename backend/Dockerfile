# ---- build stage: compile TypeScript ----
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
COPY scripts ./scripts
RUN npx tsc

# ---- runtime stage ----
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY admin ./dist/admin
USER node
EXPOSE 4000
CMD ["node", "dist/src/server.js"]
