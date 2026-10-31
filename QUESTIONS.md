# QUESTIONS.md — Decisions Deferred or Clarifications Needed

*Items here are things that came up during implementation but are NOT listed in the spec. Implementer must not act on these; only log and move on.*

## Q1 — Existing appointments with wrong chamberId
Existing Firestore documents have `chamberId = "Bup"` / `"BSL"` (chamber display names) instead of the real IDs (`chamber-1793458283033`). The fix for new bookings is in Step 1, but existing records cannot be retroactively migrated by app code.

**Question:** Should a one-time Firestore migration script be added to `scripts/` to back-fill `chamberId` on existing appointments? Or should the query layer just accept both chamber name and chamber ID (soft match)?

---

## Q2 — `android/app/google-services.json` is tracked in git
This file contains Firebase client-side config (API key, project_id, etc.). It is currently tracked. In the Final Gate we remove scripts, but google-services.json is required for the Android build. Should it stay tracked, or be replaced with environment injection in CI?

---

## Q3 — Operator chamber card in Profile vs. Step 5
Step 5 says "Remove the chamber cards from Profile (keep one summary line)." The current profile shows cards with waiting count stream. Confirm: should the stream still run but collapsed into one line, or should the waiting count be dropped from Profile entirely?

---

## Q4 — `scripts/` directory
The spec (Final Gate) says to delete scratch/patch scripts from the repo. Scripts include legitimate maintenance tools: `migrate_to_firestore.js`, `bootstrap_owner_admin.js`. Should these be deleted from git history (git filter-repo) or just removed from the working tree and gitignored?
