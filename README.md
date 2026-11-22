# By the People

Civic accountability app: report local issues, rally neighbours, and see which leaders deliver.
Runs fully on localhost (no cloud services).

## Run

```bash
# 1. Backend (Node 22.5+; uses built-in node:sqlite)
cd backend && npm install && npm run seed && npm start      # http://localhost:3000

# 2. App (Flutter 3.44+, iOS simulator)
xcrun simctl location booted set 21.2514,81.6296              # demo area
cd app && flutter run
```

Demo login: `demo@bythepeople.app` / `demo1234` (or tap "Try the demo account").
Android emulator reaches the backend at `10.0.2.2:3000` automatically; override with `--dart-define=API_URL=...`.

## Test

```bash
cd backend && npm test        # 17 end-to-end API tests on a throwaway DB
cd app && flutter test && flutter analyze
```

Rules (radius, 5-supporter threshold, severity, verification) live in `backend/src/config.js`.
