## ReadingStats+ for KOReader

**ReadingStats+** is a customized plugin for KOReader designed to provide deeper insights into your reading habits. It features expanded session analytics, smarter progress tracking for complex ebook layouts, and a more information-dense interface.

---

## Key Enhancements

### Advanced Analytics
* **Daily Averages:** See your average reading time per day.
* **Session Metrics:** Tracks average and median session lengths, plus pages per session.
* **Efficiency Tracking:** View your reading speed in **pages per hour (pg/hr)** and progress gain in **percentage per hour (%/hr)**.
* **Smart Totals:** Includes an "Actual Reading" metric that caps per-page time to prevent idle periods from inflating your total stats.

### Improved Interface
* **Two-Column Layout:** A redesigned stats block under the title for faster scanning.
* **High-Density Table:** Shows **7 rows per page**
* **Visual Cues:** If you've read today, the latest entry is automatically **bolded** for easy identification.

### Smarter Progress Handling
* **Flow-Aware:** Correctly calculates progress for books with "hidden flows" by deriving effective total pages.
* **Data Validation:** Filters out "junk" data—sessions are only counted if you read more than one page and spent at least 60 seconds reading.

---

## Data Reference Guide

### The Stats Header
| Category | Metric | Description |
| :--- | :--- | :--- |
| **Header** | `X days` | Number of unique days you’ve read. |
| | `Book total` | Raw sum of all recorded reading time. |
| | `Actual reading` | The "true" time spent (excluding long idle gaps). |
| **Left Col** | `Daily avg` | Average time spent reading per day. |
| | `Avg/Med session` | The average and middle-ground (median) length of your sessions. |
| **Right Col** | `pg/hr` | Your current reading speed. |
| | `pg/session` | How many pages you typically clear in one sitting. |
| | `%/hr` | How quickly you are moving through the book total. |

### The Daily Table
* **DATE:** Local calendar date.
* **TIME:** Total duration spent reading that day.
* **PAGES:** Unique pages turned.
* **SPEED:** Reading speed for that specific day.
* **ΔPROG:** How much total progress (%) you gained compared to yesterday.
* **TOTAL:** Your total completion percentage at the end of that day.
* **RANGE:** The specific page numbers covered (e.g., 10–45).

---

## 📂 Installation
.adds/koreader/patches/`2-Reading-Stats+.lua`
