# Code Review & Security Audit Report

**Branch:** fix/safety  
**Target:** Flutter + Firestore (`docdesk-1e4cc`)  
**Scope:** Booking flow, notifications, UI/UX audit, rules vs code, release hygiene, BMDC verification.

---

## 1. Top 10 Fixes (Ordered by Priority)

1. **[P0] `lib/screens/doctor_detail_screen.dart:327-335, 466`**  
   *Root Cause:* Booking dialog populates `selectedChamber` with `hospitalName` (e.g. `"Bup"`) instead of `c.id` (`"chamber-1793458283033"`), saving hospital name into `appointments.chamberId`.  
   *Fix:* Map dropdown items to chamber IDs (`c.id`), display `c.hospitalName`, and pass `c.id` to `FirestoreService.createAppointment(chamberId: c.id)`.

2. **[P0] `lib/services/firestore_service.dart:2164-2173`**  
   *Root Cause:* `createAppointment` creates notification with title `"Appointment Confirmed"` directly to `userId` (the patient) when status is only `'requested'`. Doctor and operator receive 0 notifications.  
   *Fix:* Change patient notification title to `"Appointment Requested"`. Query doctor's `claimedByUid` and chamber's `operatorUid` and notify both of new pending booking.

3. **[P0] `firestore.rules:43`**  
   *Root Cause:* `isDoctorManagingOperator()` allows `affectedKeys().hasOnly(['roles', 'operatorAssignments', 'updatedAt'])`. But `FirestoreService.assignChamberOperator` (line 1136) writes `assignedChambers`, triggering rule rejection (`PERMISSION_DENIED`).  
   *Fix:* Add `'assignedChambers'` to `hasOnly(['roles', 'operatorAssignments', 'assignedChambers', 'updatedAt'])` in `firestore.rules`.

4. **[P0] `firestore.rules:334-336` & `firestore-debug.log:548`**  
   *Root Cause:* Message creation rule evaluates `request.time < chat.expiresAt` and `chat.messageCount < chat.messageLimit` without existence checks, causing fatal rule evaluation error when fields are absent.  
   *Fix:* Guard fields: `(!('expiresAt' in chat) || request.time < chat.expiresAt) && (!('messageLimit' in chat) || chat.messageCount < chat.messageLimit)`.

5. **[P0] `lib/screens/bmdc_verification_screen.dart:73-79`**  
   *Root Cause:* WebView injected JS checks `!hasCaptcha` and auto-clicks search button (`btn.click()`), violating BMDC manual-lookup requirement.  
   *Fix:* Delete lines 72-79 so the script only populates `target.value = val;` and dispatches input/change events without auto-clicking search or checking CAPTCHA.

6. **[P1] `lib/screens/home_screen.dart:182-206` vs `lib/screens/operator_desk_screen.dart:168`**  
   *Root Cause:* Home screen requests counter queries global `appointments` collection without `doctorId` or date filter; Queue Desk calls `fetchTodayQueue` which restricts to today's `scheduledTime`.  
   *Fix:* Scope home stream to doctor's `doctorId` / operator's `chamberId`, and add a dedicated "Requested" appointments section to `OperatorDeskScreen`.

7. **[P1] `lib/screens/home_screen.dart:197, 203`**  
   *Root Cause:* Home computes `todayCount` using `scheduledTime.toString().startsWith(todayStr)`. Because `scheduledTime` is a Firestore `Timestamp`, `toString()` yields `"Timestamp(seconds=..."`, making `todayCount` always 0.  
   *Fix:* Cast `d['scheduledTime']` to `Timestamp`, convert via `.toDate().toIso8601String()`, and then compare date prefix.

8. **[P1] `lib/screens/admin_console_screen.dart:1899-1988`**  
   *Root Cause:* "Clear All Appointments" (collection purge), role switchers, and local storage reset are exposed without checking `kDebugMode`.  
   *Fix:* Wrap debug cards in `if (kDebugMode)` so destructive actions and role impersonation cannot be accessed in release builds.

9. **[P1] `firestore.indexes.json:102-114`**  
   *Root Cause:* Composite index indexes `notifications` on `(userId ASC, createdAt DESC)`, but code (`notification_service.dart:96`) stores and sorts by `timestamp`.  
   *Fix:* Change `createdAt` to `timestamp` in `firestore.indexes.json` for collection `notifications`.

10. **[P2] `lib/screens/home_screen.dart:681-705` & `lib/screens/home_screen.dart:112, 824`**  
    *Root Cause:* Header stacks redundant `_getRoleGreeting()` ("Hello, Patient"), `_buildRoleBadge()` ("[Patient]"), and `_greetingName`. Doctor home also mounts deprecated `_buildDoctorDashboardCard()`.  
    *Fix:* Simplify header to `"Hello, $_greetingName"`, remove role chip if redundant, and delete `_buildDoctorDashboardCard()` (lines 112-250, 824).

---

## Section A: Booking Flow Audit (P0)

### 1. Newest 5 Appointments in Firestore (`docdesk-1e4cc`)
Fetched via service account (`tools/serviceAccount.json`):
1. **`KyPVf2sNf8iT4kDjGCWz`**: `patientName: "Rehnuma"`, `doctorName: "Dr. Nuzhat Saima"`, `scheduledTime: 2026-11-02T04:00:00Z`, `doctorId: "doctor_uHlqUgF07vZ8Ie4z54KinN9i0Li1"`, `chamberId: "Bup Medical"`, `userId: "b1hA1IJVoTZRK71wnMD4cOustFn1"`, `status: "requested"`, `createdAt: 2026-10-31T20:35:24.545Z`.
2. **`KgQQ9fJBcjofliWXmc4v`**: `patientName: "Mashrafi Elahi"`, `doctorName: "Dr. Mashrafi Elahi"`, `scheduledTime: 2026-11-02T04:00:00Z`, `queuePosition: 1`, `doctorId: "doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83"`, `chamberId: "Bup"`, `userId: "LEPN8RB9Oeg5vXKX76plaXD57Zz2"`, `status: "requested"`, `createdAt: 2026-10-31T20:14:53.990Z`.
3. **`LSDVNOAp5izqIDqdowzx`**: `patientName: "Mashrafi Elahi"`, `doctorName: "Dr. Mashrafi Elahi"`, `scheduledTime: 2026-11-02T04:00:00Z`, `queuePosition: 1`, `doctorId: "doctor_LEPN8RB9Oeg5vXKX76plaXD57Zz2"`, `chamberId: "BSL"`, `userId: "LEPN8RB9Oeg5vXKX76plaXD57Zz2"`, `status: "requested"`, `createdAt: 2026-10-31T20:14:43.393Z`.
4. **`92fInhxMgdCmHfj7JNIE`**: `patientName: "Mashrafi Elahi"`, `doctorName: "Akhtarun Nahar Alo"`, `scheduledTime: 2026-11-02T04:00:00Z`, `doctorId: "doctor_2356"`, `chamberId: "Popular Diagnostic Centre Ltd."`, `userId: "mMOqrPAdtIRH5a76t7Fx1ky8Bp83"`, `status: "requested"`, `createdAt: 2026-10-31T18:33:30.129Z`.
5. **`iOXOHseqqbbX9wdvaw4y`**: `patientName: "Mashrafi Elahi"`, `doctorName: "Dr. Nuzhat Saima"`, `scheduledTime: 2026-11-01T04:00:00Z`, `queuePosition: 1`, `doctorId: "doctor_nuzhat_saima"`, `chamberId: "Bup Medical"`, `userId: "mMOqrPAdtIRH5a76t7Fx1ky8Bp83"`, `status: "waiting"`, `createdAt: 2026-10-31T14:44:55.349Z`.

**Comparison with Doctor Chambers & Operator Assignments:**
- Doc 2 has `chamberId: "Bup"`. Doctor `doctor_mMOqrPAdtIRH5a76t7Fx1ky8Bp83` has chamber `id: "chamber-1793458283033"`, `name: "Bup"`. Operator `5rNRlLLaczZ65NuqsTSPE0kf2Pr1` has `operatorAssignments: ["chamber-1793458283033"]`. Mismatch: code saved the chamber title `"Bup"` instead of `"chamber-1793458283033"`.
- Doc 3 has `chamberId: "BSL"`. Doctor `doctor_LEPN8RB9Oeg5vXKX76plaXD57Zz2` has chamber `id: "chamber-1793457537320"`, `name: "BSL"`. Operator `b1hA1IJVoTZRK71wnMD4cOustFn1` has `operatorAssignments: ["chamber-1793457537320"]`. Mismatch: code saved `"BSL"` instead of chamber ID.
- Doc 1 has `chamberId: "Bup Medical"`. Doctor `doctor_uHlqUgF07vZ8Ie4z54KinN9i0Li1`'s chamber has no `id` property, and operator assignments for `uHlqUgF07vZ8Ie4z54KinN9i0Li1` contain `["chamber-bup-1", "demo-chamber"]`.

### 2. Firestore Queries & Screen Disagreement Root Cause
- **Doctor Home Counter (`home_screen.dart:182`):** `_db.collection('appointments').snapshots()`. No filters. Loops over all database records; if `status == 'requested'`, increments `pendingRequests`.
- **Doctor Queue Desk (`operator_desk_screen.dart:168` -> `firestore_service.dart:2005`):** `_db.collection('appointments').where('doctorId'|'chamberId').where('scheduledTime', >= startOfDay).where('scheduledTime', <= endOfDay)`.
- **Why screens disagree:** Patient bookings default to tomorrow (`DateTime.now().add(Duration(days: 1))`), or have null time. Home counts any requested doc in the entire database, showing `"1 Requests"`, while Queue Desk strictly filters for today's timestamps, showing `"No patients in queue today"`.

### 3. "Book Appointment" Code Trace
- **Trigger:** `doctor_detail_screen.dart:460` -> `FirestoreService.createAppointment()`.
- **Writes:** Inserts doc into `appointments` with `status: 'requested'`, `scheduledTime: Timestamp`, `chamberId: selectedChamber` (human name), `userId: uid`.
- **Notifications Created (`firestore_service.dart:2166-2172`):** Calls `NotificationService.createNotification()` with `userId: uid` (the booking patient), `title: 'Appointment Confirmed'` [BUG], and `relatedId: docRef.id`. Doctor and operator are never queried or notified.

### 4. Hardcoded, Seeded, or Drifting Numbers
- `home_screen.dart:197, 203`: `todayCount` parsed with `scheduledTime.startsWith(todayStr)` on `Timestamp.toString()`, always yields 0.
- `home_screen.dart:1001-1003`: `'6,000+ listed doctors'` hardcoded in both true/false branches of ternary.
- `profile_screen.dart:1106`: `streamTodayWaitingCount` queries `chamberId == chamberId`, returns 0 if chamber name was stored instead of ID.
- `operator_desk_screen.dart:213`: Queue numbers recomputed from list index (`e.key + 1`), drifting from counter doc `queues/{chamberId}_{dateKey}`.

---

## Section B: Notifications Audit

- **Creation:** `NotificationService.createNotification()` (`notification_service.dart:79`). Writes to Firestore `notifications` (`userId`, `recipientId`, `title`, `body`, `type`, `isRead: false`, `relatedId`, `timestamp: FieldValue.serverTimestamp()`) and appends to local `SharedPreferences` (`local_notifications_${userId}`).
- **Reading:** `notificationsStream()` (`notification_service.dart:128`) listens to `notifications.where('userId', isEqualTo: userId).limit(50)`.
- **Clearing:** AppBar "Clear all" button calls `NotificationService.clearAll(userId)` (`notifications_screen.dart:58`), batch-deleting all user docs in Firestore and clearing `SharedPreferences`.
- **Tap Handler & Routing:** `notifications_screen.dart:189` `onTap` only executes `NotificationService.markAsRead(n.id, _userId)`. **No routing exists:** tapping does not open appointment, chat session, or post.
- **Swipe-to-Dismiss:** None (no `Dismissible` widget in list).
- **Expiry / TTL:** None in Firestore or code (local cache caps at 50).
- **Unread State:** Tracked by `isRead` boolean; unread shows 8px primary dot, bold title, and tinted background.
- **Bell Badge Source:** `home_screen.dart:708` streams `NotificationService.notificationsStream()` and counts `!n.isRead`.

---

## Section C: UI / UX Audit

- **Redundant Home Header:** `lib/screens/home_screen.dart:681-705` displays `_getRoleGreeting()` ("Hello, Patient") + `_buildRoleBadge()` ("Patient" chip) + `_greetingName`. Defined in lines 70-109.
- **My Practice Dashboard Card:** `lib/screens/home_screen.dart:112-250` (`_buildDoctorDashboardCard()`), rendered on doctor role at line 824. Must be deleted.
- **Feed Own Posts:** `_PostCard` in `lib/screens/feed_screen.dart:452`. Own posts display identical tags ("Patient Member" / "Doctor Specialist") with no "You" indicator or visual differentiator.
- **Raw IDs & Placeholders in UI:**
  - `lib/screens/operator_desk_screen.dart:144`: `'Chamber Desk (${cId.substring(8, 12)})'`.
  - `lib/screens/profile_screen.dart:961`: `'Chamber Desk (${chamberId.substring(8, 12)})'`.
  - `lib/screens/profile_screen.dart:1032`: Hardcoded `'Specialist Doctor'`.
  - `lib/screens/appointment_screen.dart:124-128`: Fallback `'Specialist Doctor'` and raw `chamberId`.
  - `lib/services/firestore_service.dart:2150, 2753`: Fallback `'Specialist Doctor'` and `'demo-chamber'`.
- **Text Contrast Violations:**
  - `lib/screens/admin_console_screen.dart:1520, 1561`: `badgeColor = Colors.orange` text on `Colors.orange.withValues(alpha: 0.15)` chip (contrast ~2.1:1, fails WCAG AA).
  - `lib/screens/admin_console_screen.dart:1771, 1800`: `stColor = Colors.orange` text on `Colors.deepPurple.shade50`.
- **Admin Console Tiles & Debug Status:**
  1. *L850:* Firebase Backend Status Card (Online/Latency/Counts) — **ACTIVE**
  2. *L966:* Doctor Role Allocation & Approvals (`fetchDoctorApplications`) — **ACTIVE**
  3. *L1190:* Add Doctor to Directory Dialog — **ACTIVE**
  4. *L1221:* Directory Management List & Delete Doctor — **ACTIVE**
  5. *L1294:* Moderator Appointments & Permissions — **ACTIVE**
  6. *L1435:* Doctor Verification Tabs (Pending/Verified/Rejected) — **ACTIVE**
  7. *L1690:* Assign Doctor Profile to Registered Email — **ACTIVE**
  8. *L1702:* Doctor Profile Claim Requests Stream — **ACTIVE**
  9. *L1879:* Telehealth & Paid Consultation Approvals — **ACTIVE**
  10. *L1903:* "Clear All Appointments" (Purge) — **DEBUG / DANGEROUS**
  11. *L1923:* "Switch to Doctor Portal" — **DEBUG / TEST**
  12. *L1935:* "Switch to Operator Desk" — **DEBUG / TEST**
  13. *L1947:* "Switch to Guest Patient Mode" — **DEBUG / TEST**
  14. *L1971:* "Reset All Local App Storage" — **DEBUG / TEST**

---

## Section D: Rules vs Code Audit

- **`users` Collection:**
  - Code (`firestore_service.dart:1136`) writes `assignedChambers`.
  - Rule (`firestore.rules:43`) allows only `['roles', 'operatorAssignments', 'updatedAt']`. **Mismatch:** Doctor operator assignment fails.
  - Rule helper `getUserData().roles.isDoctor` (line 34): if a user doc lacks a `roles` map, rules engine crashes with evaluation error, blocking authentication access.
- **`appointments` Collection:**
  - Patient can set `scheduledTime` at booking (rule line 105 does not validate `scheduledTime`).
  - Patient cannot set `queuePosition` on create (`line 107`).
  - Patient cannot alter status on update except to `'cancelled'` (`line 138`).
  - Operator update/delete checks `resource.data.chamberId in getUserData().operatorAssignments` (`lines 135, 150`). Because code stored chamber name (`"Bup"`), rule rejects operator attempts to confirm/reschedule/reject.
- **`queues` Collection:**
  - Rule line 161 requires `chamberId in getUserData().operatorAssignments`. Transaction in `confirmAppointment` fails when appointment has chamber name.
- **`chats` & `messages` Collection:**
  - Rule line 334 checks `request.time < chat.expiresAt` and `messageCount < messageLimit`. In `firestore-debug.log:548`, this threw `evaluation error at L330:26` because existing chat docs lacked those fields.
- **`consultations` Collection:**
  - Patient cannot set payment status to completed; only allowed `pending_payment` or `paid_unconfirmed` (`line 361, 370`). Doctor/admin updates completion.

---

## Section E: Release Hygiene (P0)

- **Secrets & Service Account:**
  - `tools/serviceAccount.json`: Ignored in `.gitignore:58`. Untracked in git. Verified absent from git history.
  - `.env`: Ignored in `.gitignore:57`. Untracked in git. Verified absent from git history.
  - `android/app/google-services.json`: Tracked in git repository (commit `9f5cedb`). Contains Firebase client config/API key.
- **Tracked Maintenance / Scratch Scripts to Move Out:**
  - `scripts/backfill_search_index.js`
  - `scripts/bootstrap_owner_admin.js`
  - `scripts/build_bundled_doctors.js`
  - `scripts/configure_android_google_signin.js`
  - `scripts/migrate_to_firestore.js`
  - `scripts/seed_demo_accounts_and_reviews.js`
- **Static Analysis & Debug Guards:**
  - `flutter analyze` completed cleanly: `No issues found! (ran in 83.5s)`.
  - `kDebugMode` is **NOT** used for role switchers or appointment purge in `admin_console_screen.dart:1899-1988`.
- **Missing Firestore Indexes:**
  - `notifications`: index exists for `(userId, createdAt)`, but code requires `(userId, timestamp)`.
  - `appointments`: missing composite index for `(chamberId ASC, status ASC, createdAt DESC)` and `(doctorId ASC, status ASC, createdAt DESC)` needed to list requested appointments.

---

## Section F: BMDC Verification Audit

- **WebView Automation Check:**
  - `lib/screens/bmdc_verification_screen.dart:73-79` actively inspects `hasCaptcha` and auto-clicks the search button (`btn.click()`). **Policy Violation.** It must only populate the text input.
- **Badge Text:**
  - `"BMDC Verified Doctor"` (`feed_screen.dart:489`)
  - `"Verified BMDC Practitioner"` (`doctor_detail_screen.dart:550`)
  - `"BMDC Reg: ... • Verified Specialist"` (`settings_screen.dart:154`)
  - `"BMDC Verified Specialist"` (`tts_service.dart:90`)
- **Stored Fields (`firestore_service.dart:2340`):**
  - Stores `verificationStatus` (`'verified'` | `'unverified'` | `'rejected'`), `isBmdcVerified: bool`, and `updatedAt`.
  - **Verified Clean:** Does NOT store date of birth (DOB), blood group, parents' names, or NID.

---

## 3. Query Audit Table

| Screen | Collection | Where Clauses | Returns `status='requested'` & `scheduledTime=null`? |
| :--- | :--- | :--- | :--- |
| **Operator Desk** (`operator_desk_screen.dart:168`) | `appointments` | `chamberId == cid`, `scheduledTime >= startOfDay`, `scheduledTime <= endOfDay`, `orderBy scheduledTime ASC` | **No** (excludes null & future dates) |
| **Doctor Queue Desk** (`doctor_manager_screen.dart:198`) | `appointments` | `doctorId == did`, `scheduledTime >= startOfDay`, `scheduledTime <= endOfDay`, `orderBy scheduledTime ASC` | **No** (excludes null & future dates) |
| **Doctor Home Counters** (`home_screen.dart:182`) | `appointments` | *None* (Full collection snapshot) | **Yes** (in-memory `status == 'requested'`) |
| **Operator Profile** (`profile_screen.dart:1106`) | `appointments` | `chamberId == cid`, `scheduledTime >= startOfDay`, `scheduledTime <= endOfDay` | **No** (excludes null & future dates) |
| **Patient Appointments** (`appointment_screen.dart:91`) | `appointments` | `userId == currentUid` | **Yes** (in-memory `status != 'completed'`) |
| **Manage-Tab Badges** (`doctor_manager_screen.dart:1019`) | `operator_applications` | `doctorId == did`, `status == 'pending'` | **N/A** (queries `operator_applications`) |
| **Conflict Checker** (`firestore_service.dart:2711`) | `appointments` | `doctorId == did`, `scheduledTime >= startOfDay`, `scheduledTime <= endOfDay` | **No** (excludes null & non-today dates) |

---

## 4. Do Not Touch List

1. **`lib/services/chat_service.dart` (Token & Care Unlock Logic):** Chat unlocking correctly scopes participants, duration, and message limits.
2. **`lib/services/firestore_service.dart:2740-2785` (`confirmAppointment` Transaction):** Atomic queue counter increment on `queues/{chamberId}_{dateKey}` is robust once valid `chamberId` is supplied.
3. **`lib/widgets/app_role_and_nav.dart` (`AppBottomNavConfig`):** Single source of truth for dynamic navigation tabs across user roles.
4. **`lib/services/auth_service.dart` (Role Sync & Multi-role Model):** `UserRoles` model and claim state persistence function cleanly.
5. **`lib/screens/feed_screen.dart` Q&A & Doctor Answer System:** Verification badge display, markdown answers, and moderation permissions work as intended.
6. **`lib/services/firestore_service.dart:82` (`fetchDoctors` Geohash & Bundled Fallback):** Hybrid bundled assets fallback with Firestore search index is solid.
