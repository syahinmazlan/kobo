# reading goal plugin for koreader

a lightweight goal plugin focused on three flows:
- set an absolute goal (percentage or page)
- set a **book completion goal** as **"read in x days"**
- show progress in status bars with compact/non-compact display styles

## current menu structure

from **tools → reading goal**:

- **set percentage goal**
- **set page goal**
- **book goal**
  - **read in x days**
  - **stop book goal**
- **settings**
- **stop goal** (stops absolute percentage/page goal)

## current menu structure

from **tools → reading goal**:

- **set percentage goal**
- **set page goal**
- **book goal**
  - **read in x days**
  - **stop book goal**
- **settings**
- **stop goal** (stops absolute percentage/page goal)

## feature logic

### 1) absolute goals (percentage/page)

- **set percentage goal**: target a specific book percentage (example: 75%).
- **set page goal**: target a specific page number.

### 2) book goal: "read in x days"

this is the main workflow for completion planning.

when you set **read in x days**, the plugin:
1. reads your current page (`curr`)
2. resolves effective total pages (`total`) (flow-aware for books with hidden flows)
3. computes remaining pages: `remaining = max(0, total - curr)`
4. sets initial daily target: `target_pages = ceil(remaining / days)`
5. stores goal metadata (`start_date`, `completion_days`, `total_effective_pages`) for dynamic recalculation

as you keep reading across days, the plugin recalculates once per day:
- `elapsed_days = days since start_date`
- `days_left = max(1, completion_days - elapsed_days)`
- `remaining_pages = max(0, total_effective_pages - curr)`
- `new_target_pages = ceil(remaining_pages / days_left)`

this means if you over-read or under-read on one day, the next day's target adjusts automatically.

to stop only this completion-timeframe goal:
- **tools → reading goal → book goal → stop book goal**

### 3) status bar display

you can toggle progress reminders from:
- tools → reading goal → settings → **show progress reminder: on/off**

the plugin can show your progress in the status bar and/or the alt status bar. toggle these from:
- tools → reading goal → settings → **display goal in status bar: on/off**
- tools → reading goal → settings → **display goal in alt status bar: on/off**

- absolute goal labels:
  - in-progress (non-compact): `▸ 14.3%`, `▸ 42pg`
  - in-progress (compact): `-14.3%`, `-42 pg`
  - exact completion: `★★★`

- book-goal daily target labels (compact toggle):
  - **compact off:** verbose page/percent format  
    - under target: `▸ 25pg|5.0%`
    - exact target: `★★★`
    - over target: `19pg|3.8%`
  - **compact on:** signed-page format  
    - under target: `-25pg`
    - exact target: `★★★`
    - over target: `+19pg`

- over-goal prefix indicator:
  - header/footer uses `★` as the goal symbol only when a daily target is exceeded.
  - when not over target, the star prefix is not shown.

toggle compact style from:
- tools → reading goal → settings → **compact status display: on/off**

