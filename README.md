# 🪪 PAN Number Validation — SQL Project

> **Data Cleaning & Validation using PostgreSQL | PL/pgSQL**  
> Author: **Tushar Maurya**

---

## 📌 Project Overview

This project cleans and validates a dataset of Indian **Permanent Account Numbers (PAN)** stored in a PostgreSQL database.  
Each PAN is categorised as **Valid** or **Invalid** based on the official Indian Income Tax Department format, with a final **summary report** for audit purposes.

---

## 🗂 Project Structure

```
pan-validation/
│
├── pan_validation.sql       ← Main SQL script (all 4 sections)
└── README.md                ← Project documentation
```

---

## 🔍 PAN Format Rules

A valid Indian PAN follows the format: **`AAAAA1234A`** (exactly 10 characters)

| Position | Type       | Rule                                                  | Valid Example | Invalid Example |
|----------|------------|-------------------------------------------------------|---------------|-----------------|
| 1–5      | Alphabetic | Uppercase only, no adjacent duplicates, not a full A–Z sequence | `AHGVE` | `AABCD`, `ABCDE` |
| 6–9      | Numeric    | Digits 1–9 only, no adjacent duplicates, not a full sequence   | `1276`  | `1123`, `1234`   |
| 10       | Alphabetic | Single uppercase letter                               | `F`           | `1`, `f`        |

✅ **Valid PAN Example:** `AHGVE1276F`

---

## ⚙️ Script Breakdown

### Section 1 — `fn_check_adjacent_character(p_str TEXT)`

**Purpose:** Detects whether any two consecutive characters in the string are identical.

**How it works:**
- Loops from position `1` to `length - 1`
- Compares each character with the next using `substring()`
- Returns `TRUE` (invalid) as soon as a duplicate adjacent pair is found
- Returns `FALSE` (safe) if no adjacent duplicates exist

**Why needed?**  
PANs like `AABCD1276F` or `1123` would pass the regex check — this function catches repeated characters that regex alone cannot block.

```sql
-- Loops through each character pair and flags duplicates
FOR i IN 1 .. length(p_str) - 1   -- stop at second-to-last character
LOOP
  IF substring(p_str, i, 1) = substring(p_str, i + 1, 1) THEN
    RETURN TRUE;   -- adjacent duplicate found → invalid PAN
  END IF;
END LOOP;
RETURN FALSE;      -- no duplicates found → safe to proceed
```

---

### Section 2 — `fn_check_sequential_character(p_str TEXT)`

**Purpose:** Detects whether all characters form a continuous ascending sequence like `ABCDE` or `1234`.

**How it works:**
- Uses `ascii()` to get the numeric code of each character
- Checks if the next character's ASCII code is exactly `current + 1`
- Returns `FALSE` (safe) as soon as any pair breaks the sequence
- Returns `TRUE` (invalid) only when ALL pairs differ by exactly 1

**Why `ascii()`?**  
Comparing characters directly won't give the numeric difference. `ascii('B') - ascii('A') = 1` lets us mathematically verify if characters are consecutive.

```sql
-- Checks if each character's ASCII value is exactly 1 more than the previous
IF ascii(substring(p_str, i + 1, 1))
 - ascii(substring(p_str, i,     1)) <> 1 THEN
  RETURN FALSE;  -- sequence broken → string is NOT fully sequential → safe
END IF;
-- If loop completes without a break → all chars sequential → invalid
RETURN TRUE;
```

---

### Section 3 — `vw_valid_invalid_pan` (View)

**Purpose:** Cleans the raw data and categorises every PAN as `Valid PAN` or `Invalid PAN`.

---

#### CTE 1 — `cte_cleaned_pan` (Data Cleaning)

| Step | Function Used | Why |
|---|---|---|
| Remove NULLs & blanks | `WHERE pan_number IS NOT NULL AND trim(...) <> ''` | Prevent errors in downstream processing |
| Strip spaces | `TRIM(pan_number)` | PAN may have accidental leading/trailing spaces |
| Uppercase | `UPPER(...)` | Standardise format regardless of input case |
| Deduplicate | `DISTINCT` | Each PAN should be validated only once |

```sql
SELECT DISTINCT
  upper(trim(pan_number)) AS pan_number   -- clean + standardise + deduplicate
FROM pan_numbers_dataset
WHERE pan_number IS NOT NULL
  AND trim(pan_number) <> ''              -- remove blank and null rows
```

---

#### CTE 2 — `cte_valid_pan` (Three Validation Gates)

All three gates must pass — failure in any one marks the PAN as invalid.

| Gate | Check | Rejects If |
|---|---|---|
| A | Regex `^[A-Z]{5}[1-9]{4}[A-Z]$` | Does not match official 10-char format |
| B | `fn_check_adjacent_character()` | Any two consecutive characters are the same |
| C | `fn_check_sequential_character()` on first 5 chars | All 5 alphabetic chars form a continuous sequence |

```sql
WHERE
  -- Gate A: must match official PAN format exactly
  pan_number ~ '^[A-Z]{5}[1-9]{4}[A-Z]$'

  -- Gate B: no adjacent duplicate characters anywhere in PAN
  AND fn_check_adjacent_character(pan_number) = FALSE

  -- Gate C: first 5 alphabetic characters must not form a full sequence
  AND fn_check_sequential_character(substring(pan_number, 1, 5)) = FALSE
```

---

#### Final SELECT — Labelling Valid / Invalid

- **LEFT JOIN** keeps all cleaned PANs and tries to match each with the valid set
- **CASE WHEN** assigns `'Valid PAN'` if matched, else `'Invalid PAN'`
- PANs that were NULL or blank never appear here — counted separately in summary

```sql
SELECT
  cld.pan_number,
  CASE
    WHEN vld.pan_number IS NOT NULL THEN 'Valid PAN'
    ELSE                                 'Invalid PAN'
  END AS pan_status
FROM cte_cleaned_pan cld
LEFT JOIN cte_valid_pan vld ON cld.pan_number = vld.pan_number
```

---

### Section 4 — Summary Report

**Purpose:** Produces a single-row audit report with 4 key metrics.

| Metric | How Calculated |
|---|---|
| Total Records Processed | Raw `COUNT(*)` from source table (includes NULLs) |
| Total Valid PANs | `COUNT(*) FILTER (WHERE pan_status = 'Valid PAN')` |
| Total Invalid PANs | `COUNT(*) FILTER (WHERE pan_status = 'Invalid PAN')` |
| Total Missing / Incomplete | `Raw Total − (Valid + Invalid)` — NULLs, blanks, duplicates |

**Cross-check formula:** `Valid + Invalid + Missing = Total Raw Records` ✅

```sql
WITH cte AS (
  SELECT
    (SELECT COUNT(*) FROM pan_numbers_dataset)           AS total_records_processed,
    COUNT(*) FILTER (WHERE pan_status = 'Valid PAN')     AS total_valid_pans,
    COUNT(*) FILTER (WHERE pan_status = 'Invalid PAN')   AS total_invalid_pans
  FROM vw_valid_invalid_pan
)
SELECT
  total_records_processed,
  total_valid_pans,
  total_invalid_pans,
  (total_records_processed - (total_valid_pans + total_invalid_pans))
    AS total_missing_pans     -- nulls + blanks + duplicates
FROM cte;
```

**Sample Output:**

| Total Records Processed | Total Valid PANs | Total Invalid PANs | Total Missing / Incomplete |
|---|---|---|---|
| 1000 | 742 | 198 | 60 |

---

## 🛠 Key PostgreSQL Concepts Used

| Concept | Where Used | Why |
|---|---|---|
| `CREATE OR REPLACE FUNCTION` | Sections 1 & 2 | Reusable validation logic — called in the view without rewriting |
| `PL/pgSQL FOR loop` | Both functions | Needed to iterate character-by-character — pure SQL can't do this |
| `ascii()` | Section 2 | Converts char to integer so we can check if it is `+1` from previous |
| `substring(str, start, len)` | Both functions | Extracts one character at a time for per-position comparison |
| Regex operator `~` | Section 3 Gate A | Fastest way to enforce a strict character pattern in PostgreSQL |
| `CTE (WITH clause)` | Sections 3 & 4 | Breaks the query into clean, readable, named steps |
| `LEFT JOIN` | Section 3 | Keeps all cleaned PANs and uses NULL from right side to flag invalids |
| `FILTER (WHERE ...)` | Section 4 | Conditional aggregation in one pass — avoids multiple subqueries |
| Scalar subquery in `SELECT` | Section 4 | Pulls raw total from source table without joining it to the view |

---

## ▶️ How to Run

**Prerequisites:** PostgreSQL 12 or above. Source table `pan_numbers_dataset` must exist with a `pan_number` column.

```bash
# Step 1: Run the full script
psql -U <username> -d <database> -f pan_validation.sql
```

```sql
-- Step 2: Query the view to see all PANs with their status
SELECT * FROM vw_valid_invalid_pan;

-- Step 3: Run the summary report (Section 4 of the script)
-- Execute the final WITH cte AS (...) query
```

---

## 📊 Sample View Output

| pan_number | pan_status |
|---|---|
| AHGVE1276F | Valid PAN |
| AABCD1234F | Invalid PAN |
| ABCDE5678Z | Invalid PAN |
| BXMPT9823K | Valid PAN |

---

## 🧠 What I Learned

- Writing reusable **PL/pgSQL functions** for character-level string validation
- Using **CTEs** to structure complex queries in a readable, step-by-step manner
- Applying **regex pattern matching** in PostgreSQL using the `~` operator
- Using **`ascii()`** and **`substring()`** for positional character analysis
- Performing **conditional aggregation** using `FILTER (WHERE ...)` in a single pass
- Deriving **missing/incomplete counts** without extra joins using arithmetic on aggregates

---

## 👤 Author

**Tushar Maurya**  
Data & SQL Enthusiast  
Project completed as part of a data cleaning and validation exercise using PostgreSQL.

---

*Feel free to fork this repo, raise issues, or connect if you have suggestions!* 🚀
