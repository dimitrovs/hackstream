# HackStream Architecture and Iterative Delivery Plan

Inspired by SlipStream, HackStream enables ultra-low-RAM devices (e.g., Raspberry Pi Zero) to run heavyweight desktop applications remotely. The first use case is a remote browser session (Firefox browser) streamed over a low-latency protocol to the client.

## Goals

- Let low-spec devices launch and use heavy GUI apps remotely with acceptable latency and bandwidth.
- Provide secure multi-user isolation with authentication and role-based authorization.
- Start with a single-node MVP and evolve to multi-node scheduling.
- Optimize for low bandwidth and quick cold-starts.

## High-level Architecture

- Control Plane (API + Auth): User auth, session lifecycle, quotas, orchestration.
- Stream Workers: Per-session Docker containers running xpra server + browser.
- Client: Lightweight Linux CLI (wrapper around xpra) performing auth and connect.
- Data Plane: xpra over TLS (or SSH) from client to the session container via ingress.
- Persistence: Postgres (users/sessions), Redis (ephemeral tokens/queues), optional storage for profiles.
- Ingress/Proxy: Traefik/Nginx (TLS, TCP/WebSocket passthrough, SNI routing).

## Components

### 1) Control Plane

- API Gateway: REST/JSON; optional WebSocket/SSE for session events.
  - Endpoints: `/login`, `/sessions` (create/list/stop), `/tokens`, `/profiles`, `/health`.
- AuthN/AuthZ:
  - Initial (MVP): Local accounts (username/password, Argon2id hashing). Client prompts and stores a session token locally.
  - Post-MVP: OIDC (Google/GitHub/Azure AD) with PKCE; optional TOTP 2FA for local accounts.
  - Control plane uses JWT or session cookies; data plane uses one-time xpra session tokens (15–60s TTL).
- User Management:
  - Roles: admin, user; account lifecycle (invite/disable);
  - Quotas: concurrency, CPU/RAM caps, idle timeout, storage quota.
- Scheduler & Session Manager:
  - Creates per-session containers with cgroup limits, user namespace, network namespace.
  - Generates ephemeral DISPLAY, xpra config, one-time TLS cert/key and session token.
  - Health checks, idle detection, auto-shutdown.
- Observability:
  - Logs: structured JSON; Audit trail of actions.
  - Metrics: Prometheus (sessions, start latency, bitrate, RTT).
  - Tracing: OpenTelemetry across API → scheduler → container lifecycle.
- Storage:
  - Postgres: users/sessions/tokens/quotas/audit.
  - Redis: tokens, locks, pre-warmed pool state.
  - Optional per-user profile volume for persistent browser data.

### 2) Stream Workers (Dockerized session)

- Base image: Linux (e.g., Ubuntu), xpra, Xorg/Xvfb or Wayland, PulseAudio/PipeWire, Firefox browser, fonts/codecs.
- xpra configuration:
  - TLS enabled; h264 (nvenc/vaapi if available), fallback to vp9/vpx; webp for stills.
  - Adaptive bitrate/quality; zstd/lz4 for pixels/control streams.
  - Keyboard, clipboard, audio; file-transfer disabled by default (policy-controlled).
- Browser run modes:
  - Default: ephemeral incognito.
  - Optional: persistent per-user profile volume.
  - Flags tuned for environment (GPU enabled/disabled, VAAPI features where available).
- Hardening:
  - Rootless containers; read-only root FS; seccomp/apparmor; minimal capabilities; tmpfs /tmp; egress policy.
- Networking:
  - xpra TCP port with TLS; routed via ingress (TCP passthrough) using SNI or per-session mapping.

### 3) Client (Linux app & CLI)

- Packaging: Debian/Ubuntu .deb distributed via apt repository; installs both a CLI and a lightweight GUI wrapper.
- Desktop integration: Installs a `.desktop` entry and icon so HackStream appears in the launcher.
- First-run GUI login: On initial launch, a small window prompts for server URL and username/password; credentials exchanged for a session token and saved under `~/.config/hackstream/config`.
- Launch flow: After login, the GUI shows a "Launch Browser" action (and optional URL field). Clicking it requests a session and spawns the xpra client to attach, presenting the remote Firefox window on the user’s desktop.
- Subsequent launches: If already configured/logged-in, opening the launcher can connect directly or show the simple launcher UI with recent URLs.
- CLI remains available for headless usage:
  - `hackstream launch browser --url <url> --profile ephemeral|persist --quality auto|low|high`
  - `hackstream list` / `hackstream stop <sessionId>`
  - `hackstream configure` or `hackstream config set api_url <url>`
- Transport: xpra over TLS (preferred) or xpra over SSH.
- Defaults: Low-quality preset optimized for low-power clients; auto-reconnect enabled.

## Session Lifecycle

1. Login: Client authenticates with username/password via `/v1/login` (GUI prompts on first run or if expired); receives a control-plane token stored locally.
2. Launch: Client calls `/sessions` with app=Firefox, profile, URL, and quality settings.
3. Provision: Scheduler starts container; xpra server boots; one-time TLS cert/key and session token created.
4. Connect: API returns `host`, `port`, `SNI`, `token`; client attaches via xpra.
5. Stream: Adaptive codec/bitrate; stats surfaced to metrics.
6. Idle/Stop: Idle timeout or explicit stop; container cleaned; audit recorded.

## Security Model

- Isolation: One user per container; no shared X server; user namespaces; per-session network namespace.
- Secrets: One-time session tokens; short-lived certs; server secrets in KMS/Vault.
- RBAC & Policy: App allowlists, GPU usage, max duration, file-transfer policy.
- Compliance: Audit logs; minimal telemetry (no keystroke/screen capture by default).

## Networking and Ingress

- TLS everywhere; Let’s Encrypt on ingress; xpra upstream TLS or SSH tunnel.
- Traefik (or Nginx stream) for TCP passthrough with SNI-based routing to per-session service.
- API on 443; xpra sessions on dynamic ports hidden behind ingress/proxy.

## Scaling Strategy

- MVP: Single server (Docker), simple queue/scheduler, pre-warmed container pool.
- Scale-up: Multiple nodes with a simple node registry, labels for gpu/non-gpu, binpack by free RAM/CPU.
- Scale-out: Kubernetes (Deployments, StatefulSets, HPA), PVs for profiles, node labels/affinity.

## Performance and SlipStream Influence

- Bandwidth optimization: h264/vaapi/nvenc, constrained bitrate, ROI updates, server-side scaling to client display.
- Control stream compression and clipboard diffing; zstd tuned to CPU budget.
- Optional HTTP Accelerator sidecar: per-domain image re-encoding (webp/avif), script stripping/minify, tracker removal (user opt-in).

## Data Model (minimal)

- `users(id, email, name, auth_provider, roles, created_at, disabled)`
- `sessions(id, user_id, app, state, started_at, ended_at, node_id, resources, profile_mode)`
- `tokens(id, user_id, type, expires_at, session_id?)`
- `quotas(subject, max_sessions, cpu_limit, mem_limit, idle_timeout)`
- `audit(id, user_id, action, target_id, timestamp, meta)`

## API Sketch

- `POST /v1/login { username, password }` → `{ access_token }` (or session cookie)
- `POST /v1/sessions { app, url?, profile, quality? }` → `{ session_id, connect: { host, sni, port, token } }`
- `GET /v1/sessions` → `[ ... ]`
- `POST /v1/sessions/{id}/stop`
- `GET /v1/me`, `GET /v1/quotas`
- Admin: `POST /v1/users`, `PATCH /v1/users/{id}`, `GET /v1/metrics`

## Container Image Outline (Firefox + xpra)

- Packages: xpra, Xorg/Xvfb or Wayland compositor, PulseAudio/PipeWire, Firefox browser, fonts, codecs.
- Runtime user: non-root with dedicated home directory.
- Entry point:
  - Start xpra server with TLS and desired encoders.
  - Launch Firefox on attach or eager start with remote control script.
  - Health/readiness endpoint exposing xpra status.

### Example runtime flags

- xpra: `start :100 --bind-tcp=0.0.0.0:PORT --tcp-encryption=tls --ssl-cert=/run/certs/cert.pem --ssl-key=/run/certs/key.pem --video-encoders=h264,vaapi,vpx --compress=zstd --clipboard=yes`
- Firefox: `Firefox` (minimal configuration needed for containerized environment)
- GPU nodes: enable VAAPI/NVENC and pass-through `/dev/dri`.

## Non-functional Requirements

- Latency: <80 ms interactive RTT on LAN; <150–200 ms WAN target.
- Cold-start: <8 s for first session on cold host; <3 s from pre-warmed pool.
- Security: TLS 1.2+; short-lived tokens; containers rootless and restricted.
- Availability: Single-node MVP; aim for >99% in future multi-node.

## MVP Scope

- Single-node server using Docker.
- Basic API with OIDC device flow and local accounts (username/password).
- Per-session container running xpra + Firefox (browser optimized for containerized environments).
- TLS via Traefik; one-time session tokens; idle timeout; simple quotas; audit logs.
- Go CLI wrapper to login, launch, attach, list, and stop sessions.
- Desktop GUI wrapper for simplified login and session launching.

## Risks & Mitigations

- Cold start latency → pre-warmed pool, layered images, lazy browser init.
- Bandwidth variability → adaptive bitrate, quick reconfigure, network smoothing.
- Security of remote desktop → one-time tokens, TLS, RBAC, disable file-transfer by default.
- Low-power clients → prefer h264 decode, low-quality presets.

---

# Iterative Delivery Plan (Epics, User Stories, Milestones)

## Tech Stack (proposed)

- Control Plane: Go (Gin/Fiber/Echo) or Python (FastAPI). Pick Go for single-binary deployment.
- Persistence: Postgres, Redis.
- Orchestration: Docker Engine (MVP), Traefik ingress.
- Streaming: xpra server/client.
- Telemetry: Prometheus, Grafana, OpenTelemetry.
- CLI: Go static binary.

## Epics

1. Authentication & User Management
2. Session Orchestration & Containers
3. Streaming & Connectivity
4. Client App & CLI
5. Observability & Admin
6. Security & Hardening
7. Persistent Profiles (Post-MVP)
8. Multi-node Scheduling & GPU (Post-MVP)
9. Optional HTTP Accelerator (Post-MVP)

## Milestones

- P0: Feasibility Prototype (Unauthenticated single-session streaming; xpra+Firefox container; Raspberry Pi client proves decode/interaction on low memory.)
- M0: Project scaffolding, CI, base image build.
- M1 (MVP Core): Local username/password auth, session creation, single-node scheduler, xpra+Firefox container, CLI launch/connect, TLS ingress, quotas, idle timeout, audit.
- M2: Observability, admin ops, robustness (retries, autoreconnect), packaging.
- M3+: Persistent profiles, GPU, multi-node, optional OIDC and 2FA, accelerator, UI dashboard.

## User Stories (with acceptance criteria)

### Prototype P0: Feasibility (Unauthenticated, single-user path)

- Story P0-1: As an engineer, I can build a Docker image that starts xpra and launches Firefox reliably.
  - AC: Image builds on the target host; entrypoint starts xpra server and Firefox; readiness observable.
    - **Current State**: A `Dockerfile` and `entrypoint.sh` script have been implemented to achieve this. The Dockerfile installs necessary dependencies (e.g., xpra, Firefox, Xvfb) and sets up a non-root user. The entrypoint script starts Xvfb, launches xpra, and runs the specified application (e.g., Firefox).
- Story P0-2: As an operator, I can run one container and expose a connection endpoint on the LAN.
  - AC: Container starts on a single server; xpra is reachable within the local network.
- Story P0-3: As a Raspberry Pi user, I can attach with xpra and load a test URL in Firefox.
  - AC: Pi Zero attaches, renders a test page, and basic interactions (type, scroll, click) are responsive.
- Story P0-4: As a team, we have a short runbook describing server bring-up and Pi client attachment.
  - AC: Steps documented; no authentication required; warning that it’s for trusted LAN testing only.

### Epic 1: Authentication & User Management

- Story A1 (MVP): As a user, I can authenticate via username/password from the CLI prompts.
  - AC: On first run or when expired, CLI prompts for server URL and username/password; obtains/stores a token or cookie for subsequent commands.
- Story A2 (MVP): As an admin, I can create and disable local users.
  - AC: API endpoints to create/disable; disabled users cannot obtain tokens.
- Story A3 (MVP): As an admin, I can assign roles and quotas.
  - AC: Role=admin/user enforced by middleware; quotas persisted and enforced on session create.
- Story A4 (Post-MVP): As a user, I can enable TOTP 2FA.
  - AC: TOTP enrollment QR; verification on login for local accounts.
- Story A5 (Post-MVP): As an org admin, I can integrate an external OIDC provider.
  - AC: Configure provider; users sign in with OIDC; claims map to roles.

### Epic 2: Session Orchestration & Containers

- Story S1 (MVP): As a user, I can request a browser session.
  - AC: `POST /sessions` returns session_id and connect descriptor (host, port, SNI, token).
- Story S2 (MVP): As a user, my session is isolated and limited in CPU/RAM.
  - AC: Container started rootless with cgroup limits; no shared X server; seccomp/apparmor profile applied.
- Story S3 (MVP): As a user, idle sessions auto-stop after configured timeout.
  - AC: Idle detector stops container; status changes to `stopped`; audit entry created.
- Story S4 (MVP): As a user, my session starts quickly due to pre-warmed pool.
  - AC: Configurable pool size; p50 start <3s from pool; fallback cold-start <8s.
- Story S5 (Post-MVP): As a user, I can choose GPU-accelerated nodes.
  - AC: Session scheduled to gpu-labeled node; hardware decode/encode verified in metrics.

### Epic 3: Streaming & Connectivity

- Story C1 (MVP): As a user, I connect via xpra over TLS with a one-time token.
  - AC: Client connects successfully; token expires after first use or TTL; TLS cert validated.
- Story C2 (MVP): As a user, I can choose quality presets.
  - AC: `--quality` maps to xpra encoders/bitrate; presets: low/auto/high.
- Story C3 (MVP): As a user, clipboard works; file transfer is disabled by default.
  - AC: Copy/paste text between client and session; file transfer blocked unless admin enables.
- Story C4 (Post-MVP): As a user, audio streaming works.
  - AC: PulseAudio/PipeWire integrated; audio enabled/disabled by policy.

### Epic 4: Client App & CLI

- Story L0 (MVP): As a desktop user, I install via apt and see a HackStream icon; launching it shows a login if needed and a button to start a browser session.
  - AC: Package installs a `.desktop` entry and icon; first-run GUI prompts for server URL and username/password; after login, "Launch Browser" opens a remote Firefox window.
- Story L1 (MVP): As a user, I can launch Firefox to a specific URL.
  - AC: `hackstream launch browser --url https://example.com` opens in remote session; prompts for config if missing.
- Story L2 (MVP): As a user, I can list and stop my sessions.
  - AC: `hackstream list` shows active sessions; `hackstream stop <id>` terminates the session.
- Story L3 (MVP): As a user, the client remembers my server URL and token securely and reconnects automatically.
  - AC: Config stored under `~/.config/hackstream`; reconnect on transient loss without re-prompting.
- Story L4 (Post-MVP): As a user, I can configure SSH tunneling instead of TLS.
  - AC: Client detects/uses SSH if configured; policy-controlled.

### Epic 5: Observability & Admin

- Story O1 (MVP): As an admin, I can view metrics and logs.
  - AC: Prometheus exports metrics; Grafana dashboards; structured logs accessible; health endpoints.
- Story O2 (MVP): As an admin, I can see audit logs for user actions.
  - AC: Audit entries for login, session create/stop, admin actions.
- Story O3 (Post-MVP): As an admin, I have a simple web dashboard.
  - AC: UI with users, sessions, metrics summaries; behind admin auth.

### Epic 6: Security & Hardening

- Story H1 (MVP): As a security-conscious operator, I require TLS everywhere and short-lived tokens.
  - AC: API over HTTPS; xpra over TLS; session tokens TTL <= 60s; refresh tokens rotated.
- Story H2 (MVP): As an operator, I can configure RBAC and disable risky features.
  - AC: File-transfer off by default; features toggled per role; policies persisted.
- Story H3 (Post-MVP): As an operator, I can store secrets in an external KMS/Vault.
  - AC: Server loads secrets from KMS; rotation supported.

### Epic 7: Persistent Profiles (Post-MVP)

- Story P1: As a user, I can opt into a persistent browser profile.
  - AC: Per-user volume mounted; profile survives session restarts; storage quota enforced.

### Epic 8: Multi-node & GPU (Post-MVP)

- Story N1: As an operator, I can attach multiple nodes and schedule sessions by capacity/labels.
  - AC: Node registry; scheduler chooses node; workloads distributed.
- Story N2: As a user, I can select GPU acceleration when available.
  - AC: Session gets GPU device; encoder/decoder metrics confirm usage.

### Epic 9: Optional HTTP Accelerator (Post-MVP)

- Story A: As a user on very low bandwidth, I can enable server-side page optimization.
  - AC: Per-domain proxy re-encodes images/strips trackers; measurable bandwidth reduction.

## MVP Acceptance (Definition of Done)

- End-to-end: First-run prompt for server URL and credentials → launch via desktop icon or CLI → usable remote Firefox in <8s cold-start on a single server.
- Security: TLS-only, one-time session tokens, file-transfer disabled by default, RBAC enforced.
- Observability: Basic metrics, logs, and audit available.
- Docs: README with setup, ARCHITECTURE and API sketch, CLI and GUI usage examples.

## Prototype Acceptance (P0 Definition of Done)

- Pi Zero (or equivalent low-RAM device) can attach to a single containerized xpra+Firefox session over a trusted LAN.
- Test page loads and is interactable (scroll, type) with acceptable responsiveness.
- A low-quality preset enables smooth playback/scroll; CPU and RAM usage recorded for both server and client.
- A short outage test shows the client can resume without restarting the container.
- Security note: No authentication; for lab testing only.

## Operational Runbook (MVP)

- Provision single Linux host with Docker, Traefik, Postgres, Redis.
- Deploy Control Plane binary and systemd service; configure local accounts (username/password). OIDC can be added post-MVP.
- Build and push xpra+Firefox image; configure pre-warmed pool size and quotas.
- Package client: build a .deb that installs the CLI and GUI wrapper, places a `.desktop` file and icon, and registers an apt repository.
- Open 443; obtain TLS certs via Let’s Encrypt (Traefik); verify TCP passthrough to sessions.
- Validate end-to-end from a Raspberry Pi Zero using the desktop icon (GUI) and the CLI with low-quality preset.

## Operational Runbook (Prototype P0)

- Server: Install Docker on a lab host; build the xpra+Firefox image; run a single container that starts xpra and Firefox; expose a reachable port on the LAN; document the chosen low-quality configuration.
- Client (Raspberry Pi): Install the xpra client; attach to the server’s session endpoint; verify rendering and interaction on a test page; note CPU/RAM and perceived latency.
- Stability checks: Briefly disrupt the network and confirm the session resumes; ensure container continues running.
- Scope and safety: Keep testing on a trusted LAN; no authentication or multi-user isolation beyond the single container.
