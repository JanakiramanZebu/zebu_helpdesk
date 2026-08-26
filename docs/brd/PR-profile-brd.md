# Business Requirements Document — Profile

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Profile **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Profile — Business Requirements Document |
| Module Scope | The signed-in agent's own profile screen: the profile header, the availability toggle, and the edit-profile, change-password, and regenerate-avatar actions. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/profile/profile_screen.dart`, `lib/models/me.dart` |

---

## 6. Functional Requirements

### 6.1 PR-001 — Profile screen and header

| Field | Value |
|-------|-------|
| Description | The Profile screen loads the signed-in agent's profile and shows their identity plus the available actions. |
| Acceptance Criteria | - The app bar title reads **Profile**<br>- On open the agent's profile is loaded; while loading a loading view is shown, and on failure an error view with **retry**<br>- The header shows the agent's avatar, **name**, **@username**, **email**, and (when present) their **department** — shown as "{department} · {role}" when a role exists<br>- A progress indicator is shown at the top while a profile action is in flight |
| Priority | High |

### 6.2 PR-002 — Availability toggle

| Field | Value |
|-------|-------|
| Description | A toggle sets whether the agent is available to accept new ticket assignments. |
| Acceptance Criteria | - An **Available** switch is shown with the subtitle **Accept new ticket assignments**, reflecting the agent's current availability<br>- Toggling it updates availability on the server and refreshes the profile<br>- The toggle is disabled while another profile action is in flight; on failure an error toast is shown |
| Priority | Medium |

### 6.3 PR-003 — Edit profile

| Field | Value |
|-------|-------|
| Description | An edit sheet updates the agent's contact details and signature. |
| Acceptance Criteria | - **Edit profile** opens a sheet titled **Edit profile** pre-filled with the current values<br>- The sheet shows fields for **First name**, **Last name**, **Email**, **Phone**, **Mobile**, **Timezone** (hint **e.g. Asia/Kolkata**), and a multi-line **Signature**<br>- **Save** submits (busy indicator while saving); on success the sheet closes, the profile refreshes, and a toast reads **Profile updated**<br>- On an API error with field errors, each is shown inline under its field; a general error is shown at the top of the sheet |
| Priority | Medium |

### 6.4 PR-004 — Change password

| Field | Value |
|-------|-------|
| Description | A sheet changes the agent's password. |
| Acceptance Criteria | - **Change password** opens a sheet titled **Change password** with obscured **Current password** and **New password** fields<br>- If either field is empty, an inline error **Both fields are required** is shown and no request is made<br>- **Update password** submits (busy indicator while saving); on success the sheet closes and a toast reads **Password changed**<br>- On an API error with field errors, they are shown inline (current/new password); a general error is shown at the top of the sheet |
| Priority | Medium |

### 6.5 PR-005 — Regenerate avatar

| Field | Value |
|-------|-------|
| Description | An action regenerates the agent's generated avatar. |
| Acceptance Criteria | - **Regenerate avatar** requests a new avatar and, on success, refreshes the profile and shows a toast **Avatar regenerated**<br>- The action is disabled while another profile action is in flight; on failure an error toast is shown |
| Priority | Low |

---

*Document in progress — additional cases added after individual approval.*
