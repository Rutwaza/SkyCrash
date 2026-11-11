# SkyCrash

SkyCrash is a browser-based, real-time crash game with a Flutter client, a
TypeScript/Node.js server, and a PostgreSQL database. The game is themed around
a plane: a multiplier rises during each round, and a player tries to cash out
before the plane crashes.

This guide describes the code as it exists in this repository. It covers the
parts of the application, how those parts communicate, how to run and rebuild
it, and what is needed to deploy a similar application.

> **Important:** This project handles bets, balances, deposits, and withdrawals.
> It is a software example, not legal, financial, or security advice. Gambling
> and payment services are regulated differently in different places. Before
> making a real-money service public, get qualified legal and security reviews,
> confirm that the service and its payment methods are allowed where it will be
> used, and add the protections and operating procedures required there. Do
> not use real funds while experimenting.

## Contents

- [How the application fits together](#how-the-application-fits-together)
- [Repository map](#repository-map)
- [How a round works](#how-a-round-works)
- [Accounts, wallets, and payments](#accounts-wallets-and-payments)
- [Predictor (Peek) feature](#predictor-peek-feature)
- [Database](#database)
- [Requirements](#requirements)
- [Run the web application locally with Docker](#run-the-web-application-locally-with-docker)
- [Change and rebuild the application](#change-and-rebuild-the-application)
- [Run a Flutter client during development](#run-a-flutter-client-during-development)
- [Deploy it](#deploy-it)
- [Back up and restore the database](#back-up-and-restore-the-database)
- [Configuration reference](#configuration-reference)
- [HTTP API and real-time events](#http-api-and-real-time-events)
- [Checks and known limitations](#checks-and-known-limitations)
- [A practical path for building a similar application](#a-practical-path-for-building-a-similar-application)

## How the application fits together

The application has four main runtime parts:

1. **Flutter web client** (`app/`): draws the game, accepts player actions,
   displays balances and game history, and communicates with the server.
2. **Node.js API and game server** (`backend/`): authenticates players,
   executes game rounds, validates bets and cash-outs, updates balances, and
   handles administrative and payment requests.
3. **PostgreSQL database**: stores accounts, balances, transaction ledger
   entries, game rounds, bets, payments, and Predictor packs.
4. **Caddy web server** (`deploy/Caddyfile`): serves the landing page and
   Flutter web build, and forwards API, admin, and Socket.IO traffic to the
   backend.

Docker Compose connects these services on a private Docker network. In the
default configuration, only Caddy's web ports are published on the computer,
bound to `127.0.0.1`. The database and backend ports are not published directly.

```text
Browser
  |
  | http://localhost:8080
  v
Caddy (web)
  |-- /, /app/*       -> static files in deploy/site
  |-- /api/*          -> backend:4000
  |-- /socket.io/*    -> backend:4000 (WebSocket/realtime)
  `-- /admin*         -> backend:4000
                               |
                               v
                         PostgreSQL (db)
```

The optional `tunnel` Compose service runs `cloudflared`. A tunnel can provide
an internet route to Caddy without opening a router port. A named tunnel uses a
Cloudflare account and a hostname configured for a domain. A temporary
Cloudflare Quick Tunnel instead creates a random `trycloudflare.com` address;
that address is temporary and should not be treated as a production service.

## Repository map

### Top level

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Defines PostgreSQL, the backend, Caddy, and the optional Cloudflare connector. |
| `.env.example` | Names the environment variables and gives local-network defaults. Copy it to `.env` and set private values there. |
| `.gitignore` | Excludes `.env`, dependency folders, generated build output, backups, and generated `deploy/site` files from Git. |
| `README.md` | This project and operations guide. |

### `app/` — Flutter client

| Path | Purpose |
|---|---|
| `app/pubspec.yaml` | Flutter/Dart version requirements and package dependencies. |
| `app/lib/main.dart` | Loads the saved login token, creates the shared game state, and starts the app. |
| `app/lib/services/api.dart` | HTTP API calls, authentication token storage, and the client API base URL. |
| `app/lib/services/game_service.dart` | Socket.IO connection, round state, displayed balance, bets, sounds, and game events. |
| `app/lib/services/format.dart` | Client display constants and RWF number formatting. |
| `app/lib/services/sounds.dart` | Generates small sound effects and plays them. |
| `app/lib/screens/` | Login/registration, game, deposit, and withdrawal screens. |
| `app/lib/widgets/` | Reusable game, bet, and top-wins interface components. |
| `app/assets/` | SVG logos included in the Flutter app. |
| `app/web/` | Flutter web entry point, manifest, and icons. |
| `app/android/` | Android wrapper and Android-specific project files. |

The client uses Provider to expose `GameService` state to widgets and
`socket_io_client` for real-time updates. Its locally calculated multiplier is
for smooth animation only. The server decides the crash point and accepts or
rejects every bet and cash-out.

### `backend/` — API and game server

| Path | Purpose |
|---|---|
| `backend/package.json` and `package-lock.json` | Node dependencies and scripts. |
| `backend/tsconfig.json` | TypeScript compiler configuration. |
| `backend/Dockerfile` | Multi-stage Docker build: compile TypeScript, then run the production server as the unprivileged `node` user. |
| `backend/src/server.ts` | Creates Express and Socket.IO servers, mounts routes, serves admin pages, and starts the game engine. |
| `backend/src/config.ts` | Reads environment variables and defines game and payment limits. |
| `backend/src/db/pool.ts` | Creates the PostgreSQL connection pool. |
| `backend/src/routes/` | HTTP routes for login, player history, payments, and admin actions. |
| `backend/src/services/engine.ts` | Round loop, bet validation, cash-out, real-time events, and Predictor pack handling. |
| `backend/src/services/fair.ts` | Seed hashing, crash-point calculation, and multiplier/time conversion. |
| `backend/src/services/wallet.ts` | Transactional wallet balance changes and idempotent ledger entries. |
| `backend/src/services/realtime.ts` | Shared Socket.IO and game-engine references, plus balance notifications. |
| `backend/src/services/telegram.ts` | Optional fire-and-forget Telegram notifications. |
| `backend/src/services/util.ts` | Small shared helpers, including the public user-ID mask. |
| `backend/src/services/peek.ts` | Activates Predictor purchase orders. |
| `backend/src/services/peekPricing.ts` | Estimates suggested Predictor prices using sampled game outcomes. |
| `backend/admin/index.html` | Admin login and deposit, withdrawal, and user interface. |
| `backend/admin/peek.html` | Directly accessible Predictor administration page. |
| `backend/scripts/genChain.ts` | Generates a precomputed one-million-seed hash chain for the game. |

### `deploy/` — web and operations

| Path | Purpose |
|---|---|
| `deploy/Caddyfile` | Routes static pages and backend paths. |
| `deploy/db-init/01-schema.sql` | The schema and starter Predictor classes initialized by Compose for a new database volume. |
| `deploy/publish-web.ps1` | Builds the Flutter web application and copies it and the landing page into `deploy/site/`. |
| `deploy/backup.ps1` | Creates a compressed PostgreSQL dump and removes local backups older than 30 days. |
| `deploy/site/` | Generated static site files. This is intentionally ignored by Git and is populated by the publish script. |

### `landing/` — public landing page

`landing/index.html` is a static marketing/information page. Caddy serves it
from `/`. Its links send visitors to the game under `/app/`.

## How a round works

1. The engine selects the next unused seed in `seed_chain`, starting from the
   highest index and moving down.
2. It computes a SHA-256 hash of that seed and publishes the hash in the
   database and in the `BETTING` event. The seed itself is not sent to players
   until the round crashes.
3. It computes a crash multiplier from an HMAC-SHA-256 of the seed and the
   public salt `skycrash-v1`. The first 52 bits of the HMAC are used. The
   current rules make one out of every 33 results crash at `1.00x`; other
   results follow the formula in `backend/src/services/fair.ts`.
4. The engine opens a short betting window (currently six seconds by default).
   It debits each accepted stake and records the bet before the round starts.
5. During the running phase, the multiplier follows an exponential curve. The
   server periodically sends ticks; the Flutter client animates between them.
6. A player can request a cash-out while the round is running and before the
   crash point. An automatic cash-out can also be requested when the bet is
   placed.
7. When the crash point is reached, the engine stores the revealed seed and
   crash point, emits the `CRASHED` event, and waits before starting another
   round.

The code includes a seed-chain generator: `backend/scripts/genChain.ts`
generates a million seeds where each new seed is the SHA-256 hash of the prior
one, then inserts them into `seed_chain`. The terminal hash can be published
before play begins. A production fairness system should also publish a clear,
independently reviewed verification procedure and make sure seed-chain
generation and publication cannot be manipulated by the operator. This
repository does not provide a separate public verifier.

The current engine keeps active round state and live bets in memory. It refunds
unsettled bets from rounds it detects as aborted when the server restarts, using
ledger idempotency keys. A production system needs careful review of restart,
concurrency, multi-instance, and settlement behavior; adding more server
instances without redesigning this in-memory state would not be safe.

## Accounts, wallets, and payments

### Player accounts

- Players register or log in with a Rwandan phone number in `+250` format and
  a password.
- Passwords are stored as bcrypt hashes.
- Successful login returns a signed JSON Web Token (JWT), stored by the client
  in secure storage.
- The JWT is sent with protected HTTP calls and in the Socket.IO handshake.
- Tokens expire after seven days.

### Wallet and ledger

The wallet balance is denominated in whole RWF units. A balance change is
performed inside a PostgreSQL transaction alongside a `ledger_entries` row.
The `applyDelta` helper refuses to let a wallet become negative and supports a
unique idempotency key so repeated webhook processing cannot credit the same
payment twice.

Examples of ledger changes are deposits, bet stakes, winnings, withdrawals,
and refunds. The ledger should be treated as the audit trail; never manually
change wallet balances in the database without a corresponding, reviewed
ledger operation.

### Deposits

- The app supports Mobile Money (manual review) and USDT on TRC20 (through
  NOWPayments).
- A Mobile Money deposit creates a pending record and sends a Telegram notice
  if Telegram is configured. An administrator confirms the amount actually
  received before crediting the wallet.
- A crypto deposit creates a payment with NOWPayments. The provider sends a
  signed callback to `/api/pay/webhook/nowpayments`; only a valid callback with
  a `finished` status is credited.
- `PUBLIC_URL` must be a public base URL for the provider callback to reach the
  server. A local-only address such as `http://localhost:8080` cannot receive a
  callback from the payment provider.

### Withdrawals

A withdrawal request immediately reserves the requested funds by debiting the
player wallet. An administrator pays the request manually and marks it paid.
If the request is rejected, the amount is returned as a refund. This code does
not send money to a Mobile Money provider or crypto address automatically.

### Telegram notifications

If both Telegram environment variables are set, the backend sends notifications
for payment activity, Predictor orders, and admin logins. Telegram is optional;
notification failures are logged and do not intentionally block payment actions.

## Predictor (Peek) feature

The Predictor feature sells packs that can reveal the upcoming crash point to
eligible players. The client shows a pack banner and can show the revealed
round value during the betting phase. The server associates eligible bets with
the pack and applies its configured multiplier cap. The engine also tracks
daily Predictor-related winnings against `PEEK_DAILY_BUDGET`.

Packs may be purchased with wallet funds or ordered through Mobile Money or
crypto. An administrator can create classes, assign a class to a user, review
orders, and close active packs. Pack state is held in the database and loaded
by the game engine.

This feature materially changes the fairness and risk of the game. Review its
business, legal, user-disclosure, and security implications before enabling it
for real users. The separate admin page is served at `/admin/peek`; its link in
the main admin header is currently commented out, but hiding that link is not
access control. Keep the route protected by strong credentials and suitable
access controls.

## Database

The primary tables created by `deploy/db-init/01-schema.sql` are:

| Table | What it stores |
|---|---|
| `users` | Phone number, password hash, account status, and creation time. |
| `wallets` | The current balance for each user. |
| `ledger_entries` | Signed balance changes and optional unique idempotency keys. |
| `seed_chain` | Precomputed game seeds indexed in play order. |
| `rounds` | Seed commitment, revealed seed, crash point, and round timing. |
| `bets` | Stake, optional automatic cash-out, cash-out multiplier, payout, and optional Predictor reference. |
| `deposits` | Deposit method, provider reference, amount, status, and review information. |
| `withdrawals` | Requested destination and amount, status, and review information. |
| `peek_classes` | Available Predictor pack definitions and prices. |
| `user_peeks` | Active and historical packs assigned to users. |
| `peek_orders` | Wallet, Mobile Money, and crypto pack purchase orders. |

### Schema file warning

For Docker's first database initialization, **`deploy/db-init/01-schema.sql` is
the authoritative schema**. The file `backend/src/db/schema.sql` is an older,
incomplete schema and does not include all fields required by the current
backend. `backend/src/db/peek.sql` is also an older Predictor schema. Do not
apply those older files to a current database.

The initialization SQL runs only when PostgreSQL creates a new, empty `pgdata`
volume. Editing that SQL does not migrate a database that already exists.
Changes to a database that contains data require an explicit, reviewed
migration. Do not delete the volume to force initialization again unless you
intend to permanently erase that database.

## Requirements

For the recommended Docker workflow:

- Windows with PowerShell, macOS, or Linux.
- Docker Desktop on Windows/macOS, or Docker Engine with the Compose plugin
  on Linux.
- Git to clone the repository.

To rebuild the Flutter web client, also install Flutter/Dart. For direct backend
development, install Node.js 22 or newer and npm. Android builds additionally
need the Android SDK and a suitable Java runtime through the Flutter Android
toolchain.

## Run the web application locally with Docker

The following instructions use PowerShell syntax. Run commands from the
repository's top-level folder.

### 1. Get the code and check Docker

```powershell
git clone https://github.com/Rutwaza/SkyCrash.git
Set-Location .\SkyCrash
docker --version
docker compose version
```

If the repository was downloaded as a ZIP instead, extract it and open
PowerShell in the extracted project folder.

### 2. Create and configure `.env`

```powershell
Copy-Item .env.example .env
notepad .env
```

At minimum, set a PostgreSQL password, a JWT signing secret, and an admin
password. For example, generate a random secret in PowerShell with:

```powershell
[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
```

Run this separately for `POSTGRES_PASSWORD` and `JWT_SECRET`. Choose a strong,
unique `ADMIN_PASSWORD`; the admin login requires at least eight characters.
Do not use the example values in a public deployment, paste secrets into chat,
or commit `.env`. Git ignores this file.

The optional NOWPayments and Telegram variables can remain blank while
experimenting. Mobile Money deposits and withdrawals are manually reviewed by
an administrator. Do not enter an untrusted payment provider's credentials.

### 3. Build the landing page and Flutter web app

The web container serves files from `deploy/site/`, which is generated and
ignored by Git. Build it before starting the stack:

```powershell
.\deploy\publish-web.ps1
```

The script runs a Flutter release web build with `API_URL=same` and base path
`/app/`, then copies the game into `deploy/site/app/` and the landing page into
`deploy/site/`. It replaces the existing generated contents of `deploy/site/`;
do not place manually maintained files there.

### 4. Start the stack

The database schema does not automatically create game seeds. A fresh database
needs a seed chain before the backend can run rounds. Start only PostgreSQL,
build the backend image, and generate the chain once:

```powershell
docker compose up -d db
docker compose build backend
docker compose run --rm --no-deps backend node dist/scripts/genChain.js
```

The generator prints a terminal hash. Record it and, if running a public game,
publish it before the first round so players have a commitment to compare with
later revealed seeds. **Do not run the generator again on a database that
already has played rounds:** it truncates and replaces the existing chain.

If this database has already been initialized, check whether a chain exists
before deciding whether to generate one:

```powershell
docker compose exec db psql -U postgres -d skycrash -c "SELECT COUNT(*) FROM seed_chain;"
```

Only generate a chain if the database is new and the result is zero. Keep any
existing chain for databases that have game history.

Now start the full stack:

```powershell
docker compose up -d --build
docker compose ps
```

Compose waits for PostgreSQL's health check, then starts the backend and Caddy.
Open:

- Landing page: `http://localhost:8080/`
- Game: `http://localhost:8080/app/`
- Admin page: `http://localhost:8080/admin`
- Predictor admin page (direct route): `http://localhost:8080/admin/peek`

The browser and server are on the same origin, so the production Flutter build
uses the current site origin for API and Socket.IO requests. The local Compose
defaults bind to loopback, so other computers cannot reach the site through
your computer's LAN address by default.

### 5. Check logs and stop

```powershell
docker compose logs --tail 100
docker compose logs --tail 100 backend
docker compose logs --tail 100 db
```

Stop containers without deleting the database:

```powershell
docker compose down
```

Start them again with `docker compose up -d`. The named volumes retain database
and Caddy state when containers are stopped or recreated. Avoid
`docker compose down -v`: the `-v` flag deletes the database volume and its
contents.

## Change and rebuild the application

### Backend changes

The backend Dockerfile compiles TypeScript and creates a production image.
Rebuild and replace just that service after backend changes:

```powershell
docker compose up -d --build backend
docker compose logs --tail 100 backend
```

### Web client or landing-page changes

After changing Flutter client code, rebuild and publish the static files:

```powershell
.\deploy\publish-web.ps1
```

For landing-page-only changes, the same script republishes the page and the
current Flutter build. Caddy serves these files from disk, so a server restart
is normally unnecessary. Hard-refresh the browser with `Ctrl+Shift+R`.

### Database changes

Create a migration for any change to an existing database. The initial SQL
under `deploy/db-init/` is not a migration runner and executes only for a new
volume. Back up the database before applying schema changes.

## Run a Flutter client during development

The default Flutter API URL depends on where the client runs:

- Flutter web defaults to `http://localhost:4000`.
- An Android emulator defaults to `http://10.0.2.2:4000`, which points from the
  emulator to the development computer.
- For a physical phone, the source comment gives the computer's LAN address as
  an example, such as `http://192.168.1.50:4000`.
- The published web build sets `API_URL=same`, so it uses the host serving the
  page.

The supplied Compose file intentionally does not publish the backend's port
4000 or PostgreSQL's port 5432 to the host. Therefore, a Flutter hot-reload
session pointed at the default localhost URL cannot reach the Compose backend
without additional local development networking configuration. The simplest
supported end-to-end workflow in this repository is to build the release web
client with `.\deploy\publish-web.ps1` and use it through Caddy at
`http://localhost:8080/app/`.

For Flutter dependency setup or analysis:

```powershell
Set-Location .\app
flutter pub get
flutter analyze
```

Return to the project root with `Set-Location ..`. If setting up a hot-reload
workflow, expose backend and database ports only on loopback in a local
development override, configure `DATABASE_URL` for the host-run backend, and
pass the correct `API_URL` to Flutter. Do not expose those development ports
publicly.

## Deploy it

### Private testing with a Cloudflare Quick Tunnel

First build the static site and start the regular stack:

```powershell
.\deploy\publish-web.ps1
docker compose up -d --build
```

In another PowerShell window, run a temporary Cloudflare Quick Tunnel through
the existing `cloudflared` image:

```powershell
docker compose --profile tunnel run --rm --no-deps -e TUNNEL_TOKEN= tunnel tunnel --no-autoupdate --url http://web:80
```

The command prints a random `https://....trycloudflare.com` URL. Open the game
by appending `/app/`, or open the admin page by appending `/admin`. Keep the
command running; pressing `Ctrl+C` stops the temporary tunnel. The link can
change on the next run and is not an uptime-guaranteed or production hostname.

Anyone who has the link can reach the public-facing application. Before sharing
it, set a strong admin password and understand that hiding an admin link does
not protect the route. Do not run a real-money service through a temporary
tunnel.

### Named Cloudflare Tunnel

A remotely managed Cloudflare Tunnel needs a Cloudflare account and, to publish
a named public hostname, a domain configured in Cloudflare. Configure its
published application route to send traffic to `http://web:80`. Store the
connector token privately in the root `.env` as `TUNNEL_TOKEN`, then run:

```powershell
docker compose --profile tunnel up -d
docker compose logs --tail 100 tunnel
```

The Docker Compose service runs `cloudflared tunnel run` using the token. Never
put a tunnel token in this README, source code, screenshots, logs you share, or
Git. If a token is exposed, rotate it in Cloudflare.

### A server with a domain

For a server deployment, use a domain and configure DNS and HTTPS deliberately.
The supplied `.env.example` includes an alternative VPS settings block for
`SITE_ADDRESS`, `WEB_BIND`, and web ports. Understand those settings before
enabling them: binding the web ports to `0.0.0.0` makes them reachable on
network interfaces, and the Caddy configuration's TLS behavior depends on the
site address. Add a firewall, HTTPS, monitoring, managed secrets, restricted
admin access, a database backup/restore procedure, and a secure update process.
Do not expose PostgreSQL or the backend directly to the public internet.

This repository does not include production orchestration, automated database
migrations, CI/CD, monitoring, or a full disaster-recovery setup.

## Back up and restore the database

`deploy/backup.ps1` makes a compressed SQL dump using `pg_dump` inside the
database container and retains local backups for 30 days. Run it from the
project root:

```powershell
.\deploy\backup.ps1
```

The script creates `backups/`, which is ignored by Git. Copy backups to a
separate, protected location; a backup only on the same computer is not a
disaster-recovery plan.

To restore a dump into a running database, first make a separate backup of the
current data. Then, from the project root, substitute the desired backup file:

```powershell
gzip -dc .\backups\skycrash-YYYYMMDD-HHMM.sql.gz | docker compose exec -T db psql -U postgres -d skycrash
```

PowerShell does not include `gzip` on every Windows installation. If that
command is unavailable, install/use a gzip-capable tool or copy the archive
from the container and decompress it before piping the SQL to `psql`. Test
restores on a separate database before relying on them.

## Configuration reference

Set values in the root `.env` file. The file is deliberately ignored by Git.

| Variable | Required? | Purpose |
|---|---|---|
| `POSTGRES_PASSWORD` | Yes for Compose | Password for the PostgreSQL `postgres` user. Compose refuses to start the database if this is empty. |
| `JWT_SECRET` | Yes for secure authentication | Secret used to sign player and admin JWTs. Generate a long random value. |
| `ADMIN_PASSWORD` | Strongly recommended | Password for the separate admin login. Admin login is disabled unless it is at least eight characters. |
| `PUBLIC_URL` | Needed for automatic crypto callbacks | Public base URL used when constructing the NOWPayments callback URL. |
| `USD_RWF` | Optional | Exchange conversion used to create crypto payment requests; defaults to `1450`. Set and review it for your context. |
| `NOWPAYMENTS_API_KEY` | Optional | NOWPayments API key for crypto payments. |
| `NOWPAYMENTS_IPN_SECRET` | Optional | Secret used to verify NOWPayments callback signatures. |
| `TELEGRAM_BOT_TOKEN` | Optional | Telegram bot token for operator notifications. |
| `TELEGRAM_CHAT_ID` | Optional | Telegram destination for those notifications. |
| `MOMO_PAY_NUMBER` | Optional | Number shown for manual Mobile Money payments. |
| `PEEK_DAILY_BUDGET` | Optional | Daily Predictor winnings budget; defaults to `5000000` RWF. |
| `SITE_ADDRESS` | Optional | Caddy's site address; defaults to `:80`. |
| `WEB_BIND` | Optional | Host interface to bind; defaults to `127.0.0.1` for local-only access. |
| `WEB_PORT` | Optional | Host HTTP port; defaults to `8080`. |
| `WEB_TLS_PORT` | Optional | Host HTTPS port mapping; defaults to `8443`. |
| `TUNNEL_TOKEN` | Only for a named Cloudflare tunnel | Cloudflare connector token. Leave empty for a Quick Tunnel. Treat it as a password. |

Game settings such as the six-second betting period, 3% instant-bust
probability, bet limits, payout limits, multiplier growth, and Predictor
expiration are currently constants in `backend/src/config.ts`, not environment
variables.

## HTTP API and real-time events

All HTTP routes are mounted under the following prefixes by `server.ts`.
Protected player routes require `Authorization: Bearer <player-jwt>`.
Administrative API routes require an admin JWT returned by the admin login
route.

### Player HTTP routes

| Method and path | Authentication | Purpose |
|---|---|---|
| `POST /api/auth/register` | Public | Create a phone-number account and wallet; returns a player JWT. |
| `POST /api/auth/login` | Public | Verify credentials and return a player JWT. |
| `GET /api/me/balance` | Player | Read the wallet balance. |
| `GET /api/me/bets` | Player | Read the latest 50 bets and their round results. |
| `GET /api/me/transactions` | Player | Read the latest 100 ledger entries. |
| `POST /api/pay/deposit` | Player | Create a manual Mobile Money or NOWPayments crypto deposit request. |
| `POST /api/pay/withdraw` | Player | Reserve funds for a manual withdrawal request. |
| `POST /api/pay/webhook/nowpayments` | Provider signature | Process a signed NOWPayments completion callback. |
| `GET /api/pay/peek/classes` | Player | List active Predictor classes. |
| `POST /api/pay/peek/buy` | Player | Buy a Predictor pack with wallet funds, MoMo, or crypto. |
| `GET /api/top-wins` | Public | Return recent high payouts with masked user identifiers. |
| `GET /api/recent-rounds` | Public | Return recent crash multipliers. |

### Admin HTTP routes

Open `/admin` for the admin interface. The direct Predictor administration page
is `/admin/peek`. Admin API calls use the JWT returned from
`POST /api/admin/login`.

| Method and path | Purpose |
|---|---|
| `POST /api/admin/login` | Exchange the admin password for an eight-hour admin JWT. |
| `GET /api/admin/summary` | Today's deposits, withdrawals, bets, payouts, and wallet totals. |
| `GET /api/admin/deposits` | List deposits; accepts `status=pending`, a status, or `status=all`. |
| `POST /api/admin/deposits/:id/approve` | Confirm a pending deposit and credit the wallet. |
| `POST /api/admin/deposits/:id/reject` | Reject a pending deposit. |
| `GET /api/admin/withdrawals` | List withdrawals; accepts a status filter. |
| `POST /api/admin/withdrawals/:id/paid` | Mark a manually paid withdrawal as paid. |
| `POST /api/admin/withdrawals/:id/reject` | Reject a withdrawal and return its reserved amount. |
| `GET /api/admin/users?q=...` | Search users by phone number. |
| `/api/admin/peek/*` | Manage Predictor classes, quotes, assignments, active packs, stats, and orders. |

### Socket.IO events

The Flutter client connects to Socket.IO using its player JWT in the handshake.
The backend emits:

| Event | Meaning |
|---|---|
| `snapshot` | Current phase, round state, and recent history sent on connection. |
| `phase` | `BETTING`, `RUNNING`, or `CRASHED` state transition. The final crash event reveals the seed. |
| `tick` | A multiplier update during a running round. |
| `stats` | Current number of bettors and total stake. |
| `win` | Public, masked recent win information. |
| `cashed` | A player's accepted cash-out and updated balance. |
| `balance` | Player balance or account notification. |
| `peek_state` | Predictor pack status, countdown, and remaining predictions. |
| `peek` | Predictor information for an eligible connection during the betting phase. |

The client emits `bet` with an amount and optional automatic cash-out multiplier,
and `cashout` with its bet ID. Both use Socket.IO acknowledgements so the server
can return success or a game-rule error.

## Checks and known limitations

- TypeScript compilation:
  ```powershell
  Set-Location .\backend
  npm ci
  npx tsc --noEmit
  Set-Location ..
  ```
- Flutter static analysis:
  ```powershell
  Set-Location .\app
  flutter pub get
  flutter analyze
  Set-Location ..
  ```
- `npm test` is currently a placeholder that exits with “Error: no test
  specified”; there is no automated backend test suite in this repository.
- The client uses optimistic, locally animated multiplier display, but
  authoritative game actions are processed by the backend.
- The round engine keeps live state in one process. It is not designed for
  multiple backend replicas.
- Withdrawals are paid manually; Mobile Money deposits are manually confirmed.
- Crypto payment callbacks require a publicly reachable `PUBLIC_URL` and
  correctly configured provider credentials.
- There is no automated migration framework, CI workflow, production monitoring,
  or complete access-control policy included.
- A public URL, tunnel, or hidden admin link is not a substitute for
  authentication, authorization, rate limiting, secure deployment, and
  operational controls.

## A practical path for building a similar application

For a new real-time game or another application with accounts and balances, a
safer development sequence is:

1. **Write down the rules and threat model.** Define the phases, timing,
   stake/payout limits, account states, and what happens on disconnects,
   process restarts, retries, or payment callbacks.
2. **Choose the components.** Keep the client responsible for presentation,
   the server responsible for decisions, and the database responsible for
   durable records. Decide whether HTTP, WebSockets, or both are appropriate.
3. **Design the database before the UI.** Define users, wallets, an append-only
   transaction ledger, rounds, bets, payment requests, indexes, constraints,
   and idempotency keys. Write migrations that can safely upgrade existing
   data.
4. **Implement and test the core server rules.** Validate every input on the
   server, use database transactions for related changes, and ensure retries
   cannot debit or credit twice. Write tests for boundary values and competing
   requests before connecting payments.
5. **Design the real-time protocol.** Specify the exact events, message
   payloads, authentication, reconnect behavior, ordering, and how the client
   recovers a snapshot after losing connection.
6. **Build the client from the protocol.** Keep network calls and state
   management separate from widgets. Treat values displayed by the client as
   untrusted until the server confirms the operation.
7. **Add payment providers last.** Use provider test environments, validate
   callback signatures, make callbacks idempotent, reconcile provider records,
   and document how humans handle manual payment reviews.
8. **Run it locally with realistic test data.** Use Docker for reproducible
   dependencies, keep secrets out of source control, and test backups and
   restores rather than assuming a dump will work.
9. **Deploy with the required protections.** Use HTTPS, least-privilege
   credentials, firewall rules, restricted admin access, logs and alerts,
   tested backups, an update plan, and a documented incident-response process.
10. **Obtain domain-specific reviews.** A wagering, wallet, or payment product
    needs qualified legal, compliance, financial, and security review before it
    handles real users or money.

Use the code and limits in this repository as examples of one implementation,
not as universal rules or proof that a similar system is secure, fair, or
compliant.
