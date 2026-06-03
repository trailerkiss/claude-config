---
name: python-coding-standards
description: >
  Mandatory standards for writing ANY Python code. Triggers whenever Claude is about to
  write, generate, scaffold, or modify Python code of any kind — scripts, modules, data
  processing, automation, tooling, or one-off utilities. This skill must fire before the
  first line of Python is written. Use this skill any time you see: a .py file being
  created, a request to "write a Python script", "add a Python function", "parse this with
  Python", "build a tool in Python", or any Python-adjacent task. Also fires for
  requirements.txt, setup.py, pyproject.toml, or any Python environment configuration.
  Never skip this skill for Python work, even for "quick" or "small" scripts.
---

# Python Coding Standards

> Read this before writing a single line of Python. Every Python task — no matter how
> small — follows these standards. This is not optional.
Rule 0 — Always Start with a Virtual Environment
Every Python project lives in its own virtual environment. No exceptions.
```bash
# Create the venv inside the project directory
cd ~/projects/my-project
python3 -m venv venv

# Activate it (Linux/WSL2)
source venv/bin/activate

# Verify you are inside the venv before installing anything
which python   # should show .../venv/bin/python
which pip      # should show .../venv/bin/pip
```
Never install packages globally with `pip install --break-system-packages` for project
code. That flag is only acceptable for one-off system tools. All project dependencies
go into a venv.
Never use `sudo pip install`. If you feel the urge, stop and create a venv instead.
---
Rule 1 — Project Structure
Every Python project uses this layout:
```
my-project/
├── venv/                  # virtual environment — never committed to git
├── .gitignore             # must include venv/, __pycache__/, *.pyc, .env
├── requirements.txt       # pinned dependencies (pip freeze > requirements.txt)
├── README.md              # what it does, how to set it up, how to run it
├── .env.example           # example env vars — never .env itself
├── src/                   # or flat layout for simple scripts
│   └── main.py
└── tests/
    └── test_main.py
```
For simple single-file scripts, flat layout is fine:
```
my-project/
├── venv/
├── .gitignore
├── requirements.txt
└── script.py
```
---
Rule 2 — Dependency Management
Always pin versions in `requirements.txt`:
```
# requirements.txt — pinned
pdfplumber==0.11.4
pandas==2.2.2
python-dotenv==1.0.1
requests==2.32.3
```
Generate it after installing:
```bash
pip freeze > requirements.txt
```
To set up a project from scratch on a new machine:
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```
---
Rule 3 — Environment Variables, Never Hardcoded Secrets
API keys, tokens, passwords, file paths, and anything environment-specific go in `.env`.
Never in source code.
```python
# WRONG
api_key = "sk-ant-api03-abc123..."

# RIGHT
from dotenv import load_dotenv
import os

load_dotenv()
api_key = os.environ["ANTHROPIC_API_KEY"]  # raises KeyError if missing — intentional
```
`.env` file (never commit this):
```
ANTHROPIC_API_KEY=sk-ant-api03-abc123...
N8N_API_KEY=eyJhbGci...
STOREDGE_URL=https://...
```
`.env.example` (commit this — it documents what's needed):
```
ANTHROPIC_API_KEY=your-key-here
N8N_API_KEY=your-key-here
STOREDGE_URL=https://...
```
---
Rule 4 — Defensive Code Patterns
Always validate inputs early
```python
def process_store_data(store_name: str, occ_sqft: float, total_sqft: float) -> dict:
    """Process occupancy metrics for a single store."""
    if not store_name or not store_name.strip():
        raise ValueError(f"store_name cannot be empty")
    if total_sqft <= 0:
        raise ValueError(f"total_sqft must be positive, got {total_sqft!r}")
    if occ_sqft < 0:
        raise ValueError(f"occ_sqft cannot be negative, got {occ_sqft!r}")
    if occ_sqft > total_sqft:
        raise ValueError(f"occ_sqft ({occ_sqft}) exceeds total_sqft ({total_sqft})")
    ...
```
Use type hints on all function signatures
```python
from typing import Optional
import logging

def extract_pdf_table(
    pdf_path: str,
    page_number: int,
    table_name: str
) -> list[dict]:
    ...
```
Always use logging, never bare print() in production code
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

logger.info("Processing store: %s", store_name)
logger.warning("Missing field %s for store %s — using default", field, store_name)
logger.error("Failed to parse page %d: %s", page_num, exc)
```
Wrap I/O and external calls in try/except with specific exceptions
```python
# WRONG — catches everything silently
try:
    data = parse_pdf(path)
except:
    data = {}

# RIGHT — specific, logged, re-raised or handled intentionally
try:
    data = parse_pdf(path)
except FileNotFoundError:
    logger.error("PDF not found: %s", path)
    raise
except pdfplumber.PDFSyntaxError as exc:
    logger.error("Corrupt PDF %s: %s", path, exc)
    raise ValueError(f"Could not parse {path}") from exc
```
Fail loudly on missing data, not silently with defaults
```python
# WRONG — hides bugs
dpsf = row.get("rent", 0) / row.get("occ_sqft", 1)

# RIGHT — surface the problem
rent = row["rent"]           # KeyError if missing
occ_sqft = row["occ_sqft"]  # KeyError if missing
if occ_sqft == 0:
    raise ValueError(f"occ_sqft is zero for store {row['name']} — cannot compute dpsf")
dpsf = rent / occ_sqft
```
---
Rule 5 — PDF Parsing with pdfplumber
For PDF table extraction, use `pdfplumber`. It is the most reliable Python library for
bordered and borderless table extraction.
```bash
pip install pdfplumber
```
Basic pattern
```python
import pdfplumber
import logging

logger = logging.getLogger(__name__)

def extract_table_from_page(
    pdf_path: str,
    page_index: int,  # 0-based
    table_settings: dict | None = None
) -> list[list[str | None]]:
    """
    Extract first table from a given PDF page.
    
    Returns list of rows, each row is a list of cell values (strings or None).
    First row is typically the header.
    """
    with pdfplumber.open(pdf_path) as pdf:
        if page_index >= len(pdf.pages):
            raise ValueError(
                f"Page {page_index} does not exist in {pdf_path} "
                f"(PDF has {len(pdf.pages)} pages)"
            )
        page = pdf.pages[page_index]
        tables = page.extract_tables(table_settings or {})
        
        if not tables:
            logger.warning("No tables found on page %d of %s", page_index, pdf_path)
            return []
        
        if len(tables) > 1:
            logger.warning(
                "Found %d tables on page %d — using first one",
                len(tables), page_index
            )
        
        return tables[0]
```
Handling multi-level headers (like FacilityComparison)
```python
def parse_occupancy_table(pdf_path: str) -> list[dict]:
    """
    Parse Page 2 OCCUPANCY table from FacilityComparison PDF.
    Handles two-row header: FACILITY / UNITS / SQUARE FEET groups.
    """
    raw = extract_table_from_page(pdf_path, page_index=1)
    
    if len(raw) < 3:
        raise ValueError(f"Expected at least 3 rows in occupancy table, got {len(raw)}")
    
    # Skip header rows (rows 0 and 1), data starts at row 2
    records = []
    for row_idx, row in enumerate(raw[2:], start=2):
        if not row[0]:  # skip empty/total rows
            continue
        try:
            records.append({
                "name":         row[0].strip(),
                "unrent":       int(row[1] or 0),
                "occ_sqft":     float((row[8] or "0").replace(",", "")),
                "sqft_pct_occ": float((row[10] or "0").replace("%", "").strip()),
            })
        except (ValueError, IndexError) as exc:
            logger.warning("Skipping row %d — parse error: %s | row=%r", row_idx, exc, row)
            continue
    
    return records
```
Iterating over all pages for repeating sections (ManagementSummary pattern)
```python
def extract_all_store_leads(pdf_path: str) -> dict[str, int]:
    """
    Extract MTD lead totals from TOP LEAD SOURCES table in each store section.
    Returns dict of {store_name: mtd_leads_total}.
    """
    results = {}
    
    with pdfplumber.open(pdf_path) as pdf:
        logger.info("Processing %d pages in ManagementSummary", len(pdf.pages))
        
        current_store = None
        for page_idx, page in enumerate(pdf.pages):
            text = page.extract_text() or ""
            
            # Detect store name from page heading
            for line in text.split("\n"):
                if line.strip().startswith("Store:") or _looks_like_store_heading(line):
                    current_store = _clean_store_name(line)
                    break
            
            # Find TOP LEAD SOURCES table on this page
            tables = page.extract_tables()
            for table in tables:
                if _is_lead_sources_table(table):
                    mtd_total = _sum_mtd_column(table)
                    if current_store and mtd_total is not None:
                        results[current_store] = mtd_total
                        logger.debug("Store %s: %d MTD leads", current_store, mtd_total)
    
    logger.info("Extracted leads for %d stores", len(results))
    return results
```
---
Rule 6 — Script Entry Points
Every runnable script uses `if __name__ == "__main__":` and `argparse` for CLI arguments.
```python
import argparse
import logging
import sys

def main() -> int:
    """Entry point. Returns exit code."""
    parser = argparse.ArgumentParser(
        description="Extract metrics from storEDGE PDF reports"
    )
    parser.add_argument("facility_pdf", help="Path to FacilityComparison PDF")
    parser.add_argument("mgmt_pdf", help="Path to ManagementSummary PDF")
    parser.add_argument("--output", default="output.json", help="Output JSON path")
    parser.add_argument("--verbose", action="store_true", help="Debug logging")
    args = parser.parse_args()
    
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )
    
    try:
        result = process_reports(args.facility_pdf, args.mgmt_pdf)
        write_json(result, args.output)
        logger.info("Done — output written to %s", args.output)
        return 0
    except Exception as exc:
        logger.error("Fatal error: %s", exc, exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```
---
Rule 7 — Code Style
PEP 8 always — 4-space indentation, 88-char line limit (Black formatter default)
Docstrings on every function and class — one-line summary, then args/returns if complex
No magic numbers — name your constants
No commented-out code in commits — delete it or use git
Meaningful names — `store_occupancy_pct` not `s`, `occ` not `o`
```python
# Constants at module level
GOAL_AR_PCT = 3.0          # AR % goal per store
MIN_OCC_SQFT_WARN = 0.5    # warn if store below 50% sqft occupancy
PDF_ACTIVITY_PAGE = 0      # 0-based page index for ACTIVITY table
PDF_OCCUPANCY_PAGE = 1
PDF_ECONOMICS_PAGE = 2
```
---
Quick Setup Checklist
When starting any new Python task, run through this:
```bash
# 1. Go to or create the project directory
cd ~/projects/my-project    # or: mkdir ~/projects/my-project && cd $_

# 2. Create and activate venv
python3 -m venv venv
source venv/bin/activate

# 3. Verify activation
which python   # must show venv/bin/python

# 4. Install dependencies
pip install pdfplumber python-dotenv    # example

# 5. Pin them immediately
pip freeze > requirements.txt

# 6. Create .gitignore if it doesn't exist
printf "venv/\n__pycache__/\n*.pyc\n.env\n*.egg-info/\n" >> .gitignore

# 7. Now write code
```
