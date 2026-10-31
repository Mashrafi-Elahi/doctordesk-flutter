# Implementation Progress — fix/safety

**Branch:** fix/safety  
**Last commit:** `3ffc573` step 1: booking flow  
**Last updated:** 2026-11-01

---

## Checklist

| Step | Name | Status |
|------|------|--------|
| 1 | Booking Flow (Query builders, chamberId fix, notifications) | ✅ Done |
| 2 | Roles & Active Portal | 🔄 In Progress |
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

### Step 1: Booking Flow ✅
**Commit:** `3ffc573`
**Changes:**
- Created `lib/services/appointment_queries.dart` — single source of truth for all appointment queries (operator requests, doctor requests, today queue, patient appointments, badge counts).
- Fixed `doctor_detail_screen.dart:327-335` — `chamberId` now uses `c.id` (Firestore doc ID) not `c.hospitalName`.
- Fixed `firestore_service.dart:2164-2173` — patient gets "Appointment Requested" (not "Confirmed"); doctor (via `claimedByUid`) and chamber operator (via `operatorUid`) now also get notified.
- Fixed `firestore.rules:43` — added `assignedChambers` to `isDoctorManagingOperator` allowed keys.
- Fixed `firestore.rules:334-336` — guarded `expiresAt` and `messageLimit` null fields in chat message create rule.
- Fixed `firestore.indexes.json` — replaced wrong `(notifications, userId, createdAt)` index with `(userId, timestamp)`. Added 4 composite indexes for `appointments` (chamberId+status+createdAt, doctorId+status+createdAt, chamberId+status+scheduledTime, doctorId+status+scheduledTime).
- Fixed `home_screen.dart:182-212` — scoped appointment stream by role (doctor/operator) using `AppointmentQueries`; fixed `todayCount` Timestamp comparison (was using `toString().startsWith()` which never matched).
- Added `_doctorProfileId` and `_operatorAssignments` state fields to home screen, loaded from user profile in `_loadData()`.

**Known issues:**
- Existing appointments in Firestore have `chamberId = "Bup"` or `"BSL"` (chamber names, not IDs). These cannot be back-filled by the app; they need a one-time migration script or manual correction (logged in QUESTIONS.md Q1).

### Step 2: Roles & Active Portal
**What is next:**
1. Remove "Rate as Chamber Operator" prompt from patient-facing doctor profiles unless viewer is a doctor.
2. Add rule: patient cannot book with their own `doctorProfileId`.
3. Add rule: operator cannot create `status == 'requested'` for a chamber they operate.
4. Show rules diff for any changes.

---

## Handoff Notes for Codex

**Current branch:** fix/safety  
**What was done:** Step 1 complete — booking flow fixes (chamberId, notifications, query builders, indexes, rules).  
**Important constraints:**
- `tools/serviceAccount.json` and `.env` are gitignored; do not commit them.
- `lib/services/chat_service.dart` — do NOT touch (works correctly).
- `lib/services/firestore_service.dart:2740-2785` (`confirmAppointment` transaction) — do NOT change the transaction logic, only fix callers.
- `lib/widgets/app_role_and_nav.dart` — do NOT touch.
- `lib/services/auth_service.dart` — do NOT touch.
- `flutter analyze` must pass after each step before committing.
