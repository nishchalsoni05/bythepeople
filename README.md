# By the People

Civic accountability app: report local issues, rally neighbours, and see which leaders deliver.
Runs fully on localhost (no cloud services).

## Run

```bash
# 1. Backend (Node 22.5+; uses built-in node:sqlite)
cd backend && npm install && npm run seed && npm start      # http://localhost:3000

# 2. App (Flutter 3.44+, iOS simulator)
cd app && cp -n .env.example .env                             # first time only
xcrun simctl location booted set 21.2514,81.6296              # demo area
flutter run
```

Configuration lives in `app/.env` (see `app/.env.example`):

- `API_URL`: backend base URL. Use `http://localhost:3000` for the iOS simulator and for a phone over USB (run `adb reverse tcp:3000 tcp:3000` first). Use `http://10.0.2.2:3000` for the Android emulator.
- `HTTP_LOG`: `true` to log request paths and status codes in debug builds.

`--dart-define=API_URL=...` overrides the file. `.env` is bundled into the app, so never put secrets in it.

Demo login: `demo@bythepeople.app` / `demo1234` (or tap "Try the demo account").

## Test

```bash
cd backend && npm test        # 17 end-to-end API tests on a throwaway DB
cd app && flutter test && flutter analyze
```

Rules (radius, 5-supporter threshold, severity, verification) live in `backend/src/config.js`.
