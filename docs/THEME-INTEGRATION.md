# Theme Integration Notes

The visual prototype is in the separate rap-theme repository. It is a static UI demonstration, not an installable Pterodactyl theme package.

## Integration plan

1. Obtain and pin the exact Pterodactyl Panel 1.15.1 source tree used by the deployment.
2. Create a staging copy and verify its dependency lockfiles and build instructions.
3. Identify the actual admin navigation, React entry points, Laravel route conventions, authorization middleware, and asset build process in that exact source version.
4. Implement the Backup Manager UI as a separate feature area and use a typed API contract. Do not replace the whole frontend or patch compiled assets as the long-term source of truth.
5. Keep native Pterodactyl backup functionality and existing routes intact.
6. Add admin-only authorization, CSRF protection, audit logging, pagination, and server-side filters.
7. Build assets from source, run lint/type/build checks, then test all existing Panel pages in staging.
8. Deploy through a versioned patch/release with rollback instructions. Re-test after every Panel update.

## UI behavior requirements

- Dark navy background, blue primary action, compact cards and tables matching the approved mockup.
- Backup list filters by Panel, individual Node, server UUID, type, date, status, and search term.
- Server-side pagination; filtering Node 1 must not show other Nodes' backups.
- No destructive action from a row menu without a detail/confirmation flow.
- Empty, loading, error, stale-data, and permission-denied states.
- Never hardcode sample IPs, counts, or statuses in production; the current static prototype uses demo values only.

## Compatibility warning

Do not use APIs documented for a different major Panel version unless they are verified in 1.15.1. This repository does not yet contain a compiled or production-installed Panel patch.