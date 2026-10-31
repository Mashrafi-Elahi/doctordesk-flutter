# Current safety and UX changes

- Kept the existing Firestore schema and added only guarded rules: safe roles-map access, patient self-booking prevention, operated-chamber request prevention, and an admin-only append-only BMDC verification history collection.
- Doctor detail no longer exposes profile claiming or patient-created consultation/chat entry points. The chat action appears only for an already unlocked chat.
- Notifications now have a 30-day `expiresAt`, support swipe deletion, and route appointment/feed notifications after being marked read.
- The Home header says `Hello, <first name>` and no longer renders the doctor dashboard card. Feed adds `My posts`, a `You` badge, and suppresses email-shaped public names.
- Nearby Doctors uses one location row with a Change picker; distance text requires chamber coordinates. Operator Desk no longer defaults to a demo chamber and requires a rejection reason.
- BMDC review is manual-only through `VerificationProvider`; outcomes are Found, Not found, or Mismatch and are written with an append-only audit entry.

## Validation

- `flutter analyze` was run once as requested. It completed with three pre-existing/cleanup warnings from now-unused private UI helpers and three errors introduced during this pass; the three errors were corrected immediately afterward. A second analyzer run was intentionally not made because the instruction requested exactly one final run.
