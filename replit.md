# Remote Control Android App

Flutter Android app for peer-to-peer screen sharing and remote touch input.

## Run & Operate

- `cd remote-control && flutter pub get` — install Flutter dependencies
- `cd remote-control && flutter analyze` — run the verified static check
- `cd remote-control && flutter test` — run the widget smoke test
- `cd remote-control && flutter build apk --debug` — build an Android debug APK when an Android SDK is configured
- `pnpm --filter @workspace/api-server run dev` — run the API server (port 5000)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `remote-control/lib/main.dart` — Flutter UI, PeerDart signaling, WebRTC media, and touch transport
- `remote-control/android/app/src/main/AndroidManifest.xml` — Android permissions and Accessibility Service registration
- `remote-control/android/app/src/main/res/xml/accessibility_service_config.xml` — gesture-capable Accessibility Service configuration
- `remote-control/README.md` — Android setup and device-to-device usage

## Architecture decisions

- PeerDart replaces the unavailable `flutter_peerjs` package while preserving the PeerJS-style signaling model.
- WebRTC's native `Helper.requestCapturePermission` and `getDisplayMedia` APIs handle Android MediaProjection.
- Viewer touch positions are normalized before transport so different device resolutions can be mapped safely.
- Android Accessibility Service gestures are opt-in and require explicit system settings approval.

## Product

The host shares its Android screen and receives remote touch gestures. A viewer connects
with the host's PeerJS ID and interacts with the shared screen.

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Gotchas

- The project requires Flutter and an Android SDK; this workspace has Flutter and Java but no Android SDK.
- The public PeerJS signaling server is suitable for a prototype only; production use should add authenticated pairing and an owned PeerServer.

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
