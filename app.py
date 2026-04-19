#!/usr/bin/env python3
"""
IngestionStatusCheck Web UI - Flask Backend

Reads local Excel files (IngestedURLs.xlsx, BlockedURLs.xlsx)
and provides a REST API for URL auditing.
"""

from flask import Flask, render_template, request, jsonify
from pathlib import Path
import pandas as pd
import re
from urllib.parse import urlparse
import io
import csv
from zipfile import BadZipFile

app = Flask(__name__)

# Configuration
BASE_DIR = Path(__file__).parent
INGEST_FILE = BASE_DIR / "IngestedURLs.xlsx"
BLOCKED_FILE = BASE_DIR / "BlockedURLs.xlsx"
INGEST_CSV_FILE = BASE_DIR / "IngestedURLs.csv"
BLOCKED_CSV_FILE = BASE_DIR / "BlockedURLs.csv"

# URL normalization settings
GUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)

# Azure DevOps wiki URL: extract (org, page_id) key for cross-format matching
# Matches both GUID and human-readable project/wiki slugs
ADO_WIKI_RE = re.compile(
    r"https?://dev\.azure\.com/([^/]+)/[^/]+/_wiki/wikis/[^/]+/([0-9]+)",
    re.IGNORECASE,
)

# Tracking parameters to strip
TRACKING_PREFIXES = ("utm_", "mc_")
TRACKING_KEYS = {"gclid", "fbclid", "msclkid", "igshid", "yclid", "_hsenc", "_hsmi"}


def normalize_url(raw_url: str) -> str:
    """Normalize URL for comparison."""
    value = (raw_url or "").strip()
    if not value:
        return ""
    
    if not value.lower().startswith(("http://", "https://")):
        value = "https://" + value
    
    parsed = urlparse(value)
    
    # Remove tracking query params
    params = dict(p.split("=", 1) if "=" in p else (p, "") 
                  for p in (parsed.query.split("&") if parsed.query else []))
    
    params = {
        k: v for k, v in params.items()
        if not any(k.startswith(p) for p in TRACKING_PREFIXES)
        and k not in TRACKING_KEYS
    }
    
    new_query = "&".join(f"{k}={v}" if v else k for k, v in sorted(params.items()))
    normalized = f"{parsed.scheme}://{parsed.netloc.lower()}{parsed.path}"
    
    if new_query:
        normalized += f"?{new_query}"
    if parsed.fragment:
        normalized += f"#{parsed.fragment}"
    
    # Remove trailing slash from path
    if normalized.endswith("/") and parsed.path == "/":
        normalized = normalized[:-1]
    
    return normalized.lower()


def extract_guids(url: str) -> set[str]:
    """Extract GUIDs from URL."""
    return set(GUID_RE.findall(url))


def _looks_encrypted_office_file(path: Path) -> bool:
    """Detect Office encrypted container signature in file bytes."""
    try:
        with path.open("rb") as f:
            head = f.read(65536)
        return b"EncryptedPackage" in head
    except Exception:
        return False


def _read_excel_with_errors(path: Path) -> pd.DataFrame:
    """Read Excel with clear, actionable errors."""
    try:
        return pd.read_excel(path, sheet_name=0)
    except ImportError as e:
        raise RuntimeError(
            f"Cannot read {path.name}: missing Excel engine dependency ({e})."
        ) from e
    except BadZipFile as e:
        if _looks_encrypted_office_file(path):
            raise RuntimeError(
                f"Cannot read {path.name}: file appears encrypted/protected. "
                "Please save an unprotected copy as .xlsx or .csv."
            ) from e
        raise RuntimeError(
            f"Cannot read {path.name}: invalid or corrupted .xlsx file format."
        ) from e
    except Exception as e:
        if _looks_encrypted_office_file(path):
            raise RuntimeError(
                f"Cannot read {path.name}: file appears encrypted/protected. "
                "Please save an unprotected copy as .xlsx or .csv."
            ) from e
        raise RuntimeError(f"Cannot read {path.name}: {e}") from e


def _read_csv_with_errors(path: Path) -> pd.DataFrame:
    """Read CSV with clear, actionable errors."""
    try:
        return pd.read_csv(path, encoding="utf-8-sig")
    except UnicodeDecodeError:
        try:
            return pd.read_csv(path, encoding="latin-1")
        except Exception as e:
            raise RuntimeError(f"Cannot read {path.name}: {e}") from e
    except Exception as e:
        raise RuntimeError(f"Cannot read {path.name}: {e}") from e


def _load_source_with_fallback(
    xlsx_path: Path,
    csv_path: Path,
    label: str,
) -> tuple[pd.DataFrame | None, str | None, list[str]]:
    """Load from xlsx first; if that fails, try csv fallback."""
    non_fatal = []

    if xlsx_path.exists():
        try:
            return _read_excel_with_errors(xlsx_path), xlsx_path.name, []
        except Exception as e:
            non_fatal.append(str(e))

    if csv_path.exists():
        try:
            # CSV fallback succeeded; xlsx parse issues are non-fatal here.
            return _read_csv_with_errors(csv_path), csv_path.name, []
        except Exception as e:
            non_fatal.append(str(e))

    if not xlsx_path.exists() and not csv_path.exists():
        return None, None, [
            f"No {label} source found. Expected {xlsx_path.name} or {csv_path.name}."
        ]

    return None, None, non_fatal


def _ado_wiki_key(url: str) -> tuple[str, str] | None:
    """Return (org_lower, page_id) for Azure DevOps wiki URLs, else None."""
    m = ADO_WIKI_RE.search(url)
    if m:
        return (m.group(1).lower(), m.group(2))
    return None


def load_database():
    """Load ingested and blocked URLs from Excel files."""
    ingested = set()
    blocked = set()
    # Maps (org, page_id) -> status ("ingested" or "blocked") for ADO wiki cross-format matching
    ado_wiki_index: dict[tuple[str, str], str] = {}
    errors = []
    
    ing_df, _, ing_errors = _load_source_with_fallback(
        INGEST_FILE,
        INGEST_CSV_FILE,
        "ingested",
    )
    errors.extend(ing_errors)
    if ing_df is not None and len(ing_df.columns) > 0:
        # Try to find URL column
        url_col = None
        for col in ["DocumentLink", "URL", "Link", "url"]:
            if col in ing_df.columns:
                url_col = col
                break
        if url_col is None:
            url_col = ing_df.columns[0]  # Use first column

        for url in ing_df[url_col].dropna():
            normalized = normalize_url(str(url))
            if normalized:
                ingested.add(normalized)
                key = _ado_wiki_key(normalized)
                if key:
                    ado_wiki_index[key] = "ingested"

    blk_df, _, blk_errors = _load_source_with_fallback(
        BLOCKED_FILE,
        BLOCKED_CSV_FILE,
        "blocked",
    )
    errors.extend(blk_errors)
    if blk_df is not None and len(blk_df.columns) > 0:
        # Try to find URL column
        url_col = None
        for col in ["ArticlePublicLink", "URL", "Link", "url"]:
            if col in blk_df.columns:
                url_col = col
                break
        if url_col is None:
            url_col = blk_df.columns[0]  # Use first column

        for url in blk_df[url_col].dropna():
            normalized = normalize_url(str(url))
            if normalized:
                blocked.add(normalized)
                key = _ado_wiki_key(normalized)
                if key:
                    ado_wiki_index[key] = "blocked"

    return ingested, blocked, ado_wiki_index, errors


def audit_urls(
    urls: list[str],
    ingested: set[str],
    blocked: set[str],
    ado_wiki_index: dict[tuple[str, str], str] | None = None,
) -> list[dict]:
    """
    Audit URLs against ingested and blocked databases.
    Returns list of results with status and reason.
    """
    if ado_wiki_index is None:
        ado_wiki_index = {}
    results = []
    
    for input_url in urls:
        if not input_url.strip():
            continue
        
        normalized = normalize_url(input_url)
        guids = extract_guids(normalized)
        
        # Check if blocked
        if normalized in blocked:
            results.append({
                "input": input_url,
                "normalized": normalized,
                "status": "blocked",
                "reason": "URL is in blocked list",
                "guids": list(guids)
            })
        # Check if found in ingested
        elif normalized in ingested:
            results.append({
                "input": input_url,
                "normalized": normalized,
                "status": "found",
                "reason": "URL exists in ingested content",
                "guids": list(guids)
            })
        # Azure DevOps wiki page-ID cross-format match
        elif (ado_key := _ado_wiki_key(normalized)) and ado_key in ado_wiki_index:
            db_status = ado_wiki_index[ado_key]
            results.append({
                "input": input_url,
                "normalized": normalized,
                "status": "blocked" if db_status == "blocked" else "found",
                "reason": f"ADO wiki page ID match (page {ado_key[1]})",
                "guids": list(guids)
            })
        # Check if GUID match (GUIDs in input URL found in stored URLs)
        elif guids:
            guid_match = None
            match_status = "found"
            for guid in guids:
                for blk_url in blocked:
                    if guid in blk_url:
                        guid_match = guid
                        match_status = "blocked"
                        break
                if guid_match:
                    break
                for ing_url in ingested:
                    if guid in ing_url:
                        guid_match = guid
                        match_status = "found"
                        break
                if guid_match:
                    break
            
            if guid_match:
                results.append({
                    "input": input_url,
                    "normalized": normalized,
                    "status": match_status,
                    "reason": f"GUID match: {guid_match}",
                    "guids": list(guids)
                })
            else:
                results.append({
                    "input": input_url,
                    "normalized": normalized,
                    "status": "missing",
                    "reason": "URL not found in database",
                    "guids": list(guids)
                })
        else:
            results.append({
                "input": input_url,
                "normalized": normalized,
                "status": "missing",
                "reason": "URL not found in database",
                "guids": []
            })
    
    return results


@app.route("/")
def index():
    """Serve the web UI."""
    return render_template("index.html")


@app.route("/api/audit", methods=["POST"])
def api_audit():
    """API endpoint to audit URLs from text input or file upload."""
    urls = []
    
    # Check if file was uploaded
    if 'file' in request.files:
        file = request.files['file']
        if file and file.filename:
            try:
                # Read file content
                stream = io.StringIO(file.stream.read().decode("UTF8"), newline=None)
                
                # Try to read as CSV first
                try:
                    reader = csv.reader(stream)
                    # Try to detect if it has a header
                    first_row = next(reader, None)
                    if first_row and len(first_row) > 0:
                        # Check if first row looks like a URL
                        first_cell = first_row[0].strip()
                        is_url = first_cell.lower().startswith(('http://', 'https://', 'www.'))
                        
                        if is_url:
                            # First row is data, not a header
                            urls.append(first_cell)
                        
                        # Read remaining rows
                        for row in reader:
                            if row and len(row) > 0 and row[0].strip():
                                urls.append(row[0].strip())
                except:
                    # If CSV parsing fails, treat as plain text
                    stream.seek(0)
                    urls = [line.strip() for line in stream if line.strip()]
            except Exception as e:
                return jsonify({"error": f"Error reading file: {e}"}), 400
    
    # Also check for text input (supports both form-data and JSON payloads)
    if not urls:
        url_text = (request.form.get("urls") or "").strip()
        if not url_text:
            data = request.get_json(silent=True) or {}
            url_text = (data.get("urls") or "").strip()

        if url_text:
            urls = [u.strip() for u in url_text.splitlines() if u.strip()]
    
    if not urls:
        return jsonify({"error": "No URLs provided"}), 400
    
    # Load databases
    ingested, blocked, ado_wiki_index, load_errors = load_database()
    if load_errors:
        return jsonify(
            {
                "error": "Database files could not be loaded.",
                "details": load_errors,
            }
        ), 400
    
    # Run audit
    results = audit_urls(urls, ingested, blocked, ado_wiki_index)
    
    # Count results
    counts = {
        "found": sum(1 for r in results if r["status"] == "found"),
        "blocked": sum(1 for r in results if r["status"] == "blocked"),
        "missing": sum(1 for r in results if r["status"] == "missing"),
        "total": len(results)
    }
    
    return jsonify({
        "results": results,
        "counts": counts
    })


@app.route("/api/status", methods=["GET"])
def api_status():
    """Check if database files exist and are loaded."""
    ingested_exists = INGEST_FILE.exists() or INGEST_CSV_FILE.exists()
    blocked_exists = BLOCKED_FILE.exists() or BLOCKED_CSV_FILE.exists()

    ingested_count = 0
    blocked_count = 0
    errors = []

    if ingested_exists:
        df, _, load_errors = _load_source_with_fallback(
            INGEST_FILE,
            INGEST_CSV_FILE,
            "ingested",
        )
        errors.extend(load_errors)
        if df is not None:
            ingested_count = len(df)

    if blocked_exists:
        df, _, load_errors = _load_source_with_fallback(
            BLOCKED_FILE,
            BLOCKED_CSV_FILE,
            "blocked",
        )
        errors.extend(load_errors)
        if df is not None:
            blocked_count = len(df)
    
    return jsonify({
        "ingested_file": ingested_exists,
        "blocked_file": blocked_exists,
        "ingested_count": ingested_count,
        "blocked_count": blocked_count,
        "errors": errors,
    })


if __name__ == "__main__":
    print("Starting IngestionStatusCheck Web UI...")
    print(f"Database files location: {BASE_DIR}")
    print(f"  - IngestedURLs.xlsx: {INGEST_FILE.exists()}")
    print(f"  - IngestedURLs.csv: {INGEST_CSV_FILE.exists()}")
    print(f"  - BlockedURLs.xlsx: {BLOCKED_FILE.exists()}")
    print(f"  - BlockedURLs.csv: {BLOCKED_CSV_FILE.exists()}")
    print("\nOpen browser to http://localhost:5000")
    app.run(debug=True, host="localhost", port=5000)
