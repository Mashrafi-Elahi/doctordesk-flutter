# Session log

## 2026-10-12

- Refreshed the Firestore doctor-name search index for the full directory, so names are searchable after prefixes like `Dr.`; also compacted the Home mood card header so the Calendar action no longer clips on narrow screens.

- Consolidated Home search and AI guidance: removed the duplicate on-page symptom suggestion panel and folded the Health Assistant action into the search field.

- Fixed post-auth role/nav refresh in `lib/screens/main_shell.dart` by listening to Firebase auth state and deriving the active portal role after role sync.
- Fixed the guest Settings `Sign In` action so it opens the shared auth modal and refreshes the page after authentication.
- Improved Firebase auth error messages in `lib/widgets/auth_modal.dart`, including Google certificate and app-configuration failures.
- `flutter analyze` passes with no issues.
- Live Feed permission denial remains a Firebase deployment/config issue: checked-in `firestore.rules` already permits public reads for `posts`; deploy these rules to project `docdesk-1e4cc` before submission.
- Android Google Sign-In still requires the local debug SHA-1 `A1:0F:C4:1C:03:52:15:F8:7D:C5:40:B1:84:CC:1D:63:2B:2F:A6:EE` (and SHA-256 from the keystore) to be registered on the Firebase Android app.

## Follow-up: reviews and Dhaka location coverage

- Review updates now pass owner-only update validation in `firestore.rules`.
- Review aggregate writes now use `ratingAverage` and `ratingCount`, matching the Doctor model and Firestore rules.
- Added reusable offline Dhaka area shortcuts and geocoder fallback in `lib/services/dhaka_locations.dart`, the check-in dialog, and nearby search.
- Review UI now gives a clear message when the live Firestore rules have not been deployed.
- `flutter analyze` and `flutter test` pass after these changes.

## Follow-up: identity, appointment ownership, and language

- Removed hard-coded admin/doctor grants for email addresses and the old owner UID. Admin access now requires `/admins/{uid}`; doctor access requires a claimed doctor profile whose `claimedByUid` matches the user; operator access requires assigned chambers.
- Fixed profile display fallback so signed-in users no longer appear as fake names such as Karim Rahman or Dr. Rafiqul Islam.
- Queue loading now scopes to the logged-in doctor's `doctorProfileId` or assigned operator chambers. Booking is blocked for unclaimed doctor profiles, and Firestore appointment rules are owner/doctor/operator scoped.
- Added app-wide language state in `lib/services/app_language.dart`; changing English/Bengali now persists and rebuilds the shell, with shared navigation and core screens translated.
- Validation: `flutter analyze`, `flutter test` (26 passed), `git diff --check`, and `flutter build apk --debug` passed. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- The new `firestore.rules` still needs an authorized deployment to project `docdesk-1e4cc`; owner/admin records and doctor claims must exist in Firestore for the new relation checks to grant access.
- Fixed the Flutter `RenderFlex overflowed by ... pixels` warning in the operator/doctor queue row by compacting action controls and ellipsizing long patient names.

## Follow-up: reliable location discovery and functional profile actions

- Nearby Doctors now uses the area saved during first-time check-in before attempting device GPS, provides instant Dhaka-area suggestions while typing, persists later area choices, and includes a directory fallback when the Firestore import has no mapped chamber metadata.
- Symptom recommendations from both the home screen and Health Assistant now open the nearby, specialty-filtered doctor flow instead of a name-search result that can be empty.
- Removed the non-functional Saved Doctors/My Reviews placeholder actions; Edit Profile now opens its actual profile editor and Settings continues to open the settings screen.
- Added the missing Firestore `posts(type, timestamp desc)` composite index definition required by the filtered Feed tabs.

## Firebase deployment status

- Deployed `firestore.indexes.json` to Firebase project `docdesk-1e4cc` on 2026-10-12. The Feed composite index deployed successfully.
- Deployed the revised `firestore.rules` to `docdesk-1e4cc` on 2026-10-12 after explicit approval. Firebase accepted and released the rules successfully.

## Location reliability follow-up

- Nearby Doctors now falls back to Android's last known position if a new GPS fix times out; an approved permission with no emulator/device coordinate now leads to the saved-area/manual path instead of a blank result.
- Added a `backfill:chambers` migration mode that writes only chamber `lat`, `lng`, and `geohash` records, leaving doctor profiles, user accounts, roles, and claims untouched.
- Ran the chamber-only backfill against `docdesk-1e4cc`: 301 geocoded chamber records were created/updated for 301 doctor profiles. This enables live distance-sorted nearby results around the mapped Dhaka hospitals.

## Authentication and app administration follow-up

- Email/password sign-up now sends Firebase verification emails and provides resend/recheck actions; signed-in unverified users also receive an in-app verification notice.
- Replaced the Android Google generic provider path with native `google_sign_in` credential exchange. The current Firebase Android config still lacks an OAuth certificate entry, so the local SHA-1/SHA-256 must be registered in Firebase before Google sign-in can complete.
- Promoted `mashrafeelahi8@gmail.com` (UID `LEPN8RB9Oeg5vXKX76plaXD57Zz2`) to the DoctorDesk in-app admin record and created/updated the first video post `doctordesk-welcome-video` with `https://youtu.be/uFzgEeNLjYY`.
- Registered the app's Android debug SHA-1 and SHA-256 certificates with Firebase Management for `com.doctordesk.doctordesk`; native Google Sign-In can now recognize locally built debug APKs.

## Location autocomplete follow-up

- Added `assets/dhaka_places.json` with 51 approximate Dhaka-area centers, Bengali labels, and Banglish aliases. Nearby Doctors now returns local area/chamber matches immediately (2+ characters), calls Photon in parallel after a 300 ms debounce, and uses Nominatim only for exact-address-shaped input with a one-request-per-second guard.
- Network failures now log their HTTP/status details and show a visible suggestion error. This work is committed on branch `firebase-only` as `368b282` (`feat(location): add reliable Dhaka place suggestions`); no Firestore writes or migrations ran.
