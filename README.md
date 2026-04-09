diff --git a/README.md b/README.md
index a793aa6832e639353708b2f97f66dd89d9f5958b..696b5adfb2d20c2dd0ac3a32841361e669fc372f 100644
--- a/README.md
+++ b/README.md
@@ -1 +1,76 @@
-# kobo
\ No newline at end of file
+# ReadingStats+ for KOReader
+
+A customized Reading Stats popup for KOReader with expanded session analytics, flow-aware progress handling, and a denser table layout.
+
+## What this patch adds
+
+- **Expanded summary/header stats** with:
+  - Daily average reading time
+  - Average session length
+  - Median session length
+  - Pages per session
+  - Progress efficiency (`%/hr`)
+  - Reading speed (`pg/hr`)
+- **Actual reading total** that caps per-page duration contributions (to reduce inflated totals from long idle periods).
+- **Flow-aware progress denominator** support for books with hidden flows.
+- **7 rows per page** in the daily table (instead of 6).
+- **Top-row emphasis for today**: if the latest row is today, Time/Pages/Speed/ΔPROG are rendered in bold.
+- **Two-column stats block** under the title for quick scanning.
+
+## Stats and how they are calculated
+
+### Title row
+
+- `X days`: count of distinct days with recorded reading activity.
+- `Book total`: sum of daily reading durations.
+- `Actual reading`: capped per-page duration sum from `page_stat`.
+
+### Left stats column
+
+- `Daily avg`: average duration per day over the loaded stats window.
+- `Avg session`: average valid session duration.
+- `Med session`: median valid session duration.
+
+### Right stats column
+
+- `<value> pg/hr`: reading speed from valid rows.
+- `<value> pg/session`: average pages per valid session.
+- `<value> %/hr`: progress gain per hour.
+
+### Session row
+
+- `This session: <time>` where `<time>` is bold.
+
+### Table columns
+
+- `DATE`: local date
+- `TIME`: total reading time for that day
+- `PAGES`: distinct pages read that day
+- `SPEED`: per-row speed (with minimum thresholds)
+- `ΔPROG`: progress delta vs previous day
+- `TOTAL`: progress total for that day
+- `RANGE`: first-to-last page range for the day (capped to day total pages if needed)
+
+### Footer summary
+
+- `Summary: <total time> · <total%> total · <gain%> gain`
+
+## Valid-session rules
+
+A session is considered **valid** when:
+
+- `pages > 1`
+- `duration >= 60` seconds
+
+These rules are used by avg/median session and pages/session metrics.
+
+## Progress handling details
+
+- If hidden flows are active and supported, the patch attempts to derive effective total pages from the active flow.
+- Otherwise it falls back to document page count.
+- Daily progress is capped to avoid displaying over 100%.
+
+## File overview
+
+- `ReadingStats+.lua`: plugin implementation.
+- `README.md`: this documentation.
