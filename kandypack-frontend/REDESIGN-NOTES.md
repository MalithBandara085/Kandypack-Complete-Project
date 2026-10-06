# Kandypack frontend update

This is the uploaded frontend with a refreshed storefront, product search and Add buttons, checkout styling, navigation, login/signup styling, order history and staff dashboard styling. Dashboard adds search, status filtering, live record counts, stable ordering and pending-update protection. Cross-tab account changes reload the page to prevent a stale role display. Backend permissions remain authoritative.

No backend or database files are included. No database migration is needed for this frontend update. Product artwork is decorative, not product photography. System fonts remove the build-time Google Fonts dependency. Existing dependency versions are unchanged.

## Install on your PC in CMD

Extract this ZIP to a NEW folder named frontend-refresh under C:\Users\HP\Desktop\Kandypack-project. It should contain kandypack-frontend\app.

From C:\Users\HP\Desktop\Kandypack-project:

```cmd
robocopy "phase1-test\kandypack-frontend\app" "backup-before-update\frontend-before-redesign\app" /E
robocopy "frontend-refresh\kandypack-frontend\app" "phase1-test\kandypack-frontend\app" /E
docker build -t kandypack-frontend-redesign .\phase1-test\kandypack-frontend
```

Only continue if the build succeeds:

```cmd
docker stop kandypack_frontend_phase1_test
docker run -d --name kandypack_frontend_redesign -p 127.0.0.1:3000:3000 kandypack-frontend-redesign
```

Open http://localhost:3000 and hard-refresh with Ctrl+F5. Keep the existing test backend running. Do not run docker compose down -v or restore a database.

If needed, return to the old frontend:

```cmd
docker stop kandypack_frontend_redesign
docker start kandypack_frontend_phase1_test
```

## Live checks before promotion

Customer: sign in; search a product; Add it; verify selection, quantity and total; place an order with a suitable future date/route; open My orders and its allocations.
Staff: sign in; find that order; filter by status; update a valid status; confirm row stays in place unless filtered out; download CSV. Test cancellation on a fresh scheduled order.
Both: log out/in, narrow the window, check all controls and messages. Changing accounts in another tab should reload existing pages.

After these checks, promote verified frontend/backend and the separately reviewed database migration to the original project. This ZIP alone does not promote backend/database changes or update Drive/GitHub.
