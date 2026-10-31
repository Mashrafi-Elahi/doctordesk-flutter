# Implementation Progress — fix/safety

**Branch:** fix/safety  
**Last commit:** `fb80425` (pre-implementation baseline)  
**Last updated:** 2026-11-01

---

## Checklist

| Step | Name | Status |
|------|------|--------|
| 1 | Booking Flow (Query builders, chamberId fix, notifications) | 🔄 In Progress |
| 2 | Roles & Active Portal | ⬜ Not Started |
| 3 | Home, Header & Removals | ⬜ Not Started |
| 4 | Doctors Near Me | ⬜ Not Started |
| 5 | Operator Desk Redesign | ⬜ Not Started |
| 6 | Notifications | ⬜ Not Started |
| 7 | Feed | ⬜ Not Started |
| 8 | Messaging (only after care) | ⬜ Not Started |
| 9 | Admin Console | ⬜ Not Started |
| 10 | BMDC (manual check only) | ⬜ Not Started |
| 11 | Tests | ⬜ Not Started |
| Final Gate | Release cleanup & deploy | ⬜ Not Started |

---

## Step Details

### Step 1: Booking Flow
**What is next:** 
1. Create `lib/services/appointment_queries.dart` — single source of truth for all appointment queries.
2. Fix `chamberId` in `doctor_detail_screen.dart:327` — use `c.id` not `c.hospitalName`.
3. Fix notification in `firestore_service.dart:2164` — "Request sent" to patient; doctor and operator get "New request".
4. Add missing composite indexes to `firestore.indexes.json`.
5. Fix `isDoctorManagingOperator` in `firestore.rules:43` — add `assignedChambers`.
6. Fix chat message rule null-field guard in `firestore.rules:334`.

**Known issues:**
- Existing appointments in Firestore have `chamberId = "Bup"` or `"BSL"` (chamber names, not IDs). These cannot be back-filled by the app; they need a one-time migration script or manual correction.

---

## Handoff Notes for Codex

**Current branch:** fix/safety  
**What was done before this:** Full audit (REVIEW.md) identifying 10 P0/P1/P2 issues across booking, rules, BMDC, UI.  
**Important constraints:**
- `tools/serviceAccount.json` and `.env` are gitignored; do not commit them.
- `lib/services/chat_service.dart` — do NOT touch (works correctly).
- `lib/services/firestore_service.dart:2740-2785` (`confirmAppointment` transaction) — do NOT change the transaction logic, only fix callers.
- `lib/widgets/app_role_and_nav.dart` — do NOT touch.
- `lib/services/auth_service.dart` — do NOT touch.
- `flutter analyze` must pass after each step before committing.
