# Kandypack team handoff — 6 October 2026

## What this package contains
The frontend and backend copied from the working PC project, with sharing configuration corrected. The customer pages and separate admin/dispatcher dashboard behaviour are retained. This package does not include the database export, passwords, or the group's report/EER documents. Add your project documents separately.

## First setup on a teammate's computer (Windows CMD)
1. Install/start Docker Desktop with Linux containers.
2. Extract this package. Open CMD in the directory containing this START-HERE.md and docker-compose.yml.
3. Obtain kandypack_updated.sql privately from the project owner and place it beside docker-compose.yml. This must be the updated export, not the old seed SQL.
4. Run: copy .env.example .env
5. Run: notepad .env
6. Replace the placeholder with a local database password. If it contains dollar signs or #, enclose the entire value in single quotes. Example: POSTGRES_PASSWORD='your-local-password'
7. Run: docker compose config --quiet
8. Run: docker compose up -d --build
9. Run: docker compose ps
10. Open http://localhost:3000 after services finish starting.

The password above is PostgreSQL's connection password, not an admin/customer website password. Website accounts come from the private SQL export.

## Owner's currently working PC
Continue running from C:\Users\HP\Desktop\Kandypack-project.
Do not start this sharing copy alongside the existing stack: its container names and ports are the same.
Do not rename/move the working project or change its Compose project name during presentation preparation; the database volume is associated with that project.
This ZIP does not automatically update your PC, Drive, or GitHub.
If adopting this configuration in the original project later, keep the existing pgdata volume and use the existing database password in .env. Changing .env does not change a password already stored in PostgreSQL.

## Database preservation
Initialization SQL runs only when PostgreSQL starts with an empty data directory.
An existing database is not updated by replacing the SQL file.
The updated export already contains the train allocation migration. Do not run that migration again on a database restored from this export.
Never run docker compose down -v against the working project: it removes the database volume.
Keep kandypack_working_final.dump and the earlier backup outside the shared source package.
Do not import this full export over an existing populated database.

## Daily use and presentation
Start Docker Desktop, open CMD in the working project, then run:
docker compose up -d
Open http://localhost:3000.
To stop without removing data: docker compose stop
If backend restarts, log out and log in again: the current JWT signing key is regenerated on startup.
Train trips must still be in the future and arrive before the requested delivery date. Existing October demo trips do not automatically move forward for a later presentation date.

## Team sharing and GitHub
Share source and this guide together. Transfer the full SQL export privately to authorised teammates; it contains account hashes and customer records.
The root .gitignore excludes .env, database exports, backups and build outputs. It does not remove files already tracked in an existing Git repository.
Do not blindly replace/delete teammates' files. Review the repository diff before committing.
No Drive or GitHub upload has been performed by preparing this package.

## Checks already reported
The original PC built frontend/backend and ran against PostgreSQL 18.
The owner reported working customer/admin/dispatcher logins and new order placement after promotion.
Earlier test-database checks covered cancellation reservation release, capacity balance, forward status changes and CSV export.
The sharing ZIP configuration has been inspected, but a fresh Docker installation from this ZIP still needs a startup check on a teammate's machine.

## Changes made while packaging
- Removed two redundant frontend ZIP files and IDE workspace files.
- Removed the obsolete nested PostgreSQL 17 Compose configuration.
- Added one root PostgreSQL 18 Compose file with a database readiness check.
- Replaced the hardcoded backend database password with DB_PASSWORD.
- Added .env.example and exclusions for secrets/build outputs.
- Made Maven wrapper executable during Docker build for Windows ZIP portability.
- Left application controllers, services, entities, UI pages and database records unchanged.
