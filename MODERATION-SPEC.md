# Stitch Social — Minimal Moderation & Reporting Spec

**Status:** Spec (not yet implemented). Drafted 2026-05-16.
**Goal:** Ship the smallest viable set of moderation features that lets us truthfully answer **"Yes"** to Stripe Connect due-diligence questions about user reporting, content takedown, and repeat-violator handling.

This spec is intentionally minimal. Anything beyond it (AI moderation, hash-matching, automated NSFW screening) is *out of scope* for v1 and explicitly described as "rolling out" in our public-facing docs until those features ship.

---

## Stripe alignment

After v1 of this spec is implemented, the truthful answers to Stripe's questionnaire become:

| Stripe question | Post-v1 answer |
|-----------------|----------------|
| User reporting functionality? | **Yes** — in-app Report button on videos/profiles/comments, routes to a reviewable queue. |
| Repeat-violator policy? | **Yes** — strikes tracked per user; thresholds trigger suspension and termination per ToS. |
| Programmatic detection/demonetize/remove? | Still **No** for v1 (content scanning is roadmap). Answer accurately. |

The first two go from "No" to "Yes." The third stays "No" — do not claim otherwise.

---

## 1. UI: where the Report button goes (iOS)

Add a "Report" action to the existing `ContextualOverlayAction` enum (currently has profile/thread/engagement/follow/share/reply/stitch/more).

### Placements
1. **Video overlay menu** — the "more" (…) menu on any video card or full-screen video. Add `case report` alongside the existing cases.
2. **Profile menu** — the "more" (…) menu on a profile that's not your own. Add a "Report user" entry.
3. **Comment / thread reply menu** — long-press or "more" on individual replies. Add a "Report" entry.
4. **Message thread menu** — for DMs. Add "Report conversation" on the recipient header.

### Visual treatment
- Use SF Symbol `flag` or `exclamationmark.bubble`.
- Group at the bottom of the action sheet with a divider, label color: secondary red.
- Don't hide it behind multiple taps — single-tap on (…) → "Report" is the target.

### Tap behavior
Tapping "Report" presents `ReportSheetView` (modal). User picks a category and (optionally) types a note. On submit, write to Firestore (see schema below) and show a confirmation toast: "Report received. Our team will review within 48 hours."

---

## 2. Report categories

Map to the AUP. Display in this exact order so the most-common categories are easiest to pick:

| Category key | Display label |
|--------------|---------------|
| `nudity_sexual` | Nudity or sexual content |
| `harassment_bullying` | Harassment, bullying, or threats |
| `hate_speech` | Hate speech or violent extremism |
| `violence_graphic` | Graphic violence |
| `child_safety` | Child safety violation |
| `copyright_ip` | Copyright or trademark infringement |
| `impersonation` | Impersonation |
| `spam_scam` | Spam, scam, or fraud |
| `self_harm` | Self-harm or suicide |
| `illegal` | Illegal activity |
| `other` | Something else |

For `child_safety`, route to a separate priority queue and trigger an admin email immediately (see §5).

For `copyright_ip`, surface a note that formal DMCA takedowns must be sent to dmca@stitchsocial.me — but accept the in-app report as a first signal.

---

## 3. Firestore schema

### Collection: `reports`

```
reports/{reportId}
  reporterUid: string          // who filed the report
  reporterIp: string?          // captured server-side via Cloud Function, optional
  targetType: "video" | "user" | "comment" | "thread" | "message"
  targetId: string             // the documentId of the target
  targetOwnerUid: string       // denormalized: uid of the content's author
  category: string             // one of the category keys above
  note: string?                // user-provided context, max 1000 chars
  createdAt: timestamp
  status: "new" | "in_review" | "resolved_actioned" | "resolved_no_action" | "duplicate"
  reviewedByUid: string?       // admin who closed it
  reviewedAt: timestamp?
  resolution: string?          // free text from admin
  priority: "normal" | "high"  // "high" for child_safety + repeated reports
```

### Indexes
- `(targetOwnerUid, status, createdAt desc)` — for "how many open reports against this user"
- `(status, priority, createdAt desc)` — for the admin queue
- `(reporterUid, targetType, targetId)` — to detect duplicate reports

### Security rules
- Authenticated users can `create` reports where `reporterUid == request.auth.uid` and where they cannot read other users' reports.
- Only users with `admin_access` claim (currently `developers@stitchsocial.me` and `james@stitchsocial.me`) can `read`, `update`, `list`.

---

## 4. Strikes & enforcement

### Collection: `userModeration/{uid}`

```
userModeration/{uid}
  strikes: number              // running count of substantiated violations
  totalReports: number         // includes unsubstantiated, for context
  lastStrikeAt: timestamp?
  lastStrikeCategory: string?
  suspensionEndsAt: timestamp? // null if not suspended
  isBannedPermanently: boolean // already exists on user doc as isBanned; mirror here
  notes: string?               // admin-only freeform
```

### Strike thresholds (matches ToS §enforcement)

When an admin resolves a report as `resolved_actioned`, increment `strikes` on the offender's doc. Cloud Function trigger:

- **Strike 1:** Status note set; content removed; in-app notification sent ("Warning: your content violated our [AUP](/terms#aup) for [category]").
- **Strike 2:** Set `suspensionEndsAt = now + 7 days`. Block sign-in or limit access via auth claim. In-app notification.
- **Strike 3:** Set `isBannedPermanently = true`. Sign out, disable account, freeze any pending payouts.

### Immediate-ban categories
For these categories, skip the strike ladder and ban immediately on first substantiated report:
- `child_safety`
- `violence_graphic` *if specifically credible threats*
- Discovered evasion of a prior permanent ban

### Forfeiture of earnings
On permanent ban, set a flag on the user's `coin_balances` doc that prevents withdrawal. Existing Hype Coin balance is forfeit. Outgoing tips already credited to other creators remain.

---

## 5. Admin queue

### Phase 1 (this spec) — minimum

Add an admin page at `/Users/jamesgarmon/stitch-landing/app/admin/reports/page.js` modeled on `app/admin/users/page.js`:

- List of `reports` with `status == "new"` or `"in_review"`, sorted by `priority desc, createdAt asc`.
- Each row shows: reporter username, target type+link, category, note, age.
- "View target" opens the target content/profile in a new tab.
- Buttons per row:
  - **Action** — opens a dialog: choose remediation (warn / remove content / strike / suspend / ban). Submitting writes to `userModeration` and updates `reports.status = "resolved_actioned"`.
  - **Dismiss** — sets `reports.status = "resolved_no_action"`.
  - **Mark Duplicate** — sets `reports.status = "duplicate"` linked to another report.

### Phase 1.1 — automated escalation
A scheduled Cloud Function runs every 15 min:
- For any `target` with `>= 3 new reports` in the last 24h, auto-hide content (set `hidden=true` on the target doc) pending review, and bump `priority = "high"`.
- For `child_safety` reports, send an email to abuse@stitchsocial.me immediately on create.

### Phase 2 (later, not v1)
- Search and filter by category, reporter, target user
- Bulk actions
- Audit trail of every admin action
- Public transparency report

---

## 6. Cloud Functions to add

In `~/Developer/StitchSocial-Functions/index.js`:

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onReportCreated` | Firestore: `reports/{id}` onCreate | Capture reporter IP, send admin email for `child_safety`, check duplicate-vote logic. |
| `onReportResolved` | Firestore: `reports/{id}` onUpdate (status change to `resolved_actioned`) | Increment `userModeration.strikes`, apply suspension/ban per thresholds, send in-app notification to offender. |
| `dailyReportEscalation` | Pub/Sub schedule, every 15 min | Auto-hide content with ≥3 reports in 24h; bump priority. |
| `applyContentRemoval` | Callable from admin UI | Soft-delete a target (video/comment): set `removed=true`, `removedReason`, `removedAt`. Existing feed queries must filter on `removed != true`. |

---

## 7. ToS / Privacy alignment (already shipped)

- The Terms of Service at `/terms` already describes the reporting process, the strikes ladder, immediate-ban categories, and abuse@stitchsocial.me as the email channel — implementation must match.
- Privacy policy at `/privacy` already describes the `reports` data we collect and retain (up to 2 years post-termination).

If implementation diverges from the ToS, **update the ToS to match the truth, not the other way around.**

---

## 8. Implementation order (suggested)

1. **iOS (½ day):** Add `report` to `ContextualOverlayAction`. Build `ReportSheetView`. Wire to Firestore `reports.create`.
2. **Firestore (1 hr):** Schema + indexes + security rules.
3. **Cloud Functions (½ day):** `onReportCreated` + `onReportResolved` + `applyContentRemoval`.
4. **Admin UI (½ day):** `/admin/reports` page.
5. **Cloud Function (1 hr):** scheduled escalation.
6. **iOS notifications (1 hr):** display warnings and suspension messages to offenders.
7. **Test:** seed a few fake reports, walk through warn → strike → suspend → ban.

Total: ~2 days of focused work for one engineer.

---

## 9. What this spec deliberately does NOT include

- Automated NSFW image/video scanning (would require OpenAI Moderation API, Hive, Sightengine, or Rekognition).
- CSAM hash matching (PhotoDNA / Apple's NeuralHash).
- Audio transcription for hate-speech detection.
- IP/copyright fingerprinting.
- ML-based account-takeover detection.

These are roadmap items. Until they ship, we answer Stripe **"No"** to the "programmatic detection" question and accurately describe our position in public-facing docs.
