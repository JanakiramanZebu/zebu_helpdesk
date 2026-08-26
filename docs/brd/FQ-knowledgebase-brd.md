# Business Requirements Document — Knowledgebase (FAQ)

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Knowledgebase / FAQ **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Knowledgebase — Business Requirements Document |
| Module Scope | The Knowledgebase (FAQ) surfaces: the Knowledgebase screen that either browses categories or searches articles, and the article detail screen. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/faq/faq_screen.dart`, `lib/features/faq/faq_detail_screen.dart`, `lib/models/faq.dart` |

---

## 6. Functional Requirements

### 6.1 FQ-001 — Knowledgebase screen: browse vs search

| Field | Value |
|-------|-------|
| Description | The Knowledgebase screen browses categories when no search is entered and shows article search results when a query is entered. |
| Acceptance Criteria | - The app bar title reads **Knowledgebase**<br>- A search box with the placeholder **Search articles** applies on **submit** (not on every keystroke); clearing it returns to the category browse view<br>- When the search is empty, the category browse view (FQ-002) is shown; when a query is present, the search-results view (FQ-003) is shown |
| Priority | High |

### 6.2 FQ-002 — Category browse

| Field | Value |
|-------|-------|
| Description | The browse view lists knowledgebase categories as expandable tiles that lazily load their articles. |
| Acceptance Criteria | - Categories are loaded on open; while loading a loading view is shown, on error an error view with **retry**, and when there are none an empty state reading **No categories**<br>- Each category is an expandable tile showing its **name** and its article **count**<br>- Expanding a category loads its articles on first open (showing a spinner while loading, an error view with retry on failure, or **No articles in this category.** when empty)<br>- Each article row shows the article **question**, a **Public**/**Internal** chip, and (when present) its category chip; tapping it opens the article detail (FQ-004)<br>- The browse view supports pull-to-refresh |
| Priority | Medium |

### 6.3 FQ-003 — Article search results

| Field | Value |
|-------|-------|
| Description | When a query is entered, the screen shows a paginated list of matching articles. |
| Acceptance Criteria | - Matching articles are shown as a paginated list<br>- Each row shows the article **question**, a **Public**/**Internal** chip, and (when present) its category chip; tapping it opens the article detail (FQ-004)<br>- When no articles match, an empty state reading **No articles found** with the hint **Try a different search term.** is shown |
| Priority | Medium |

### 6.4 FQ-004 — Article detail

| Field | Value |
|-------|-------|
| Description | The article detail shows the full question, answer, attachments, notes, and timestamps. |
| Acceptance Criteria | - The app bar title reads **Article**; while loading a loading view is shown and on failure an error view with **retry**<br>- The body shows the article **question**, a visibility/type chip (the article's type, or **Public**/**Internal**), and (when present) its category chip<br>- The article **answer** is shown as plain text (its HTML is stripped for display)<br>- When the article has attachments, an **Attachments** section lists them (they open in the shared attachment viewer — see Global BRD, GL-001)<br>- When the article has notes, a **Notes** section shows them<br>- A footer line shows **"Created {date} · Updated {date}"** |
| Priority | High |

---

*Document in progress — additional cases added after individual approval.*
