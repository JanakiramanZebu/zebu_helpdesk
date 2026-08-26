# Business Requirements Document — Reports

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Reports **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Reports — Business Requirements Document |
| Module Scope | The Reports screen — a single scrollable surface where the agent reviews ticket **volume** over a chosen recent window (7 / 30 / 90 days). It covers the day-range selector, the volume summary card (Opened / Closed / Net totals and per-day averages), and the "Ticket activity" line chart of opened-vs-closed per day, plus the screen's loading / error / empty / refresh behaviour. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/reports/reports_screen.dart`, `lib/features/reports/widgets/{report_range_selector,report_summary_card,activity_chart_card,activity_line_chart}.dart`, `lib/models/reports.dart` |

---

## 6. Functional Requirements

### 6.1 RP-001 — Reports screen: structure, data load, and states

| Field | Value |
|-------|-------|
| Description | The Reports screen fetches a volume report for the selected day-range and shows it as a range selector followed by a summary card and an activity chart. It handles loading, error (with retry), and empty states, and supports pull-to-refresh. |
| Acceptance Criteria | - The screen is titled **Reports**<br>- On open it fetches the volume report for the default range (30 days) and shows a centred loading indicator while the fetch is in flight<br>- On success the body shows, top to bottom: the **day-range selector** (RP-002), the **volume summary card** (RP-003 / RP-004), and the **Ticket activity chart card** (RP-005)<br>- On a fetch error, an error view with a **retry** action is shown (the range selector stays visible above it); retry re-attempts the fetch<br>- When the fetch returns no report at all, an error view reading **No data** with retry is shown<br>- The whole screen is vertically scrollable and supports **pull-to-refresh**, which re-fetches the current range<br>- Changing the range (RP-002) triggers a fresh fetch for the new range |
| Priority | High |

### 6.2 RP-002 — Day-range selector

| Field | Value |
|-------|-------|
| Description | A dropdown at the top of the screen selects the reporting window. Changing it re-fetches the report for the new window. |
| Acceptance Criteria | - The selector is a dropdown offering exactly three options: **Last 7 days**, **Last 30 days**, **Last 90 days**<br>- The default selection when the screen first opens is **Last 30 days**<br>- Selecting a different option updates the range and immediately re-fetches the report; selecting the already-selected option does nothing<br>- The selector stays visible in the loading, populated, and error states |
| Priority | High |

### 6.3 RP-003 — Volume summary card: Opened / Closed / Net

| Field | Value |
|-------|-------|
| Description | A summary card shows the headline volume totals for the selected window: tickets opened, tickets closed, and the net change. |
| Acceptance Criteria | - The card shows a title reading **Last N days**, where N is the window returned by the server<br>- Three metrics are shown side by side in this order: **Opened**, **Closed**, **Net**<br>- **Opened** shows the total opened count for the window; **Closed** shows the total closed count<br>- **Net** shows the net value for the window; when the net is positive it is shown with a leading **+** (e.g. "+12"); zero or negative values are shown as-is<br>- Counts are formatted with the app's count formatting<br>- The three metrics are populated from the volume report's totals (opened / closed / net) |
| Priority | High |

### 6.4 RP-004 — Volume summary card: per-day averages

| Field | Value |
|-------|-------|
| Description | Below the totals, the card shows the average opened and closed per day over the window. |
| Acceptance Criteria | - A line reads **Avg X opened · Y closed per day**, where X and Y are each shown to one decimal place<br>- X is the opened total divided by the number of days in the window; Y is the closed total divided by the number of days<br>- The day count used as the divisor is the report's window (treated as 1 if the server reports 0 days, to avoid a divide-by-zero) |
| Priority | Medium |

### 6.5 RP-005 — Ticket activity chart card

| Field | Value |
|-------|-------|
| Description | A card shows the "Ticket activity" chart — opened vs closed per day across the window — with a title, a legend, and an empty state when there is no activity. |
| Acceptance Criteria | - The card shows the title **Ticket activity**<br>- A legend is shown with two entries: **Opened** and **Closed**<br>- When the report has one or more daily data points, the line chart (RP-006) is rendered plotting an **Opened** series and a **Closed** series over the window's dates<br>- When the report's series is empty, the chart area shows the message **No activity in this range** instead of a chart |
| Priority | High |

### 6.6 RP-006 — Activity line chart rendering

| Field | Value |
|-------|-------|
| Description | The activity chart plots the opened and closed daily series as two lines with area fills, a labelled Y scale, gridlines, and a few X date labels. |
| Acceptance Criteria | - Two series are plotted — **Opened** and **Closed** — each as a line with a faint area fill beneath it, over the window's daily values<br>- The Y axis is divided into 4 gridlines; the scale's top is rounded up to a "nice" step so the axis labels read as round numbers, and each gridline is labelled with its value<br>- Up to four X-axis date labels are shown along the range, formatted as day + short month (e.g. "6 Jun"); the first is left-aligned, the last right-aligned, and any in between centred<br>- For short ranges (up to 31 data points) a point dot is drawn at each day's value on each series<br>- The chart scales to the available width and the configured height |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
