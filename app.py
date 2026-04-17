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

app = Flask(__name__)

# Configuration
BASE_DIR = Path(__file__).parent
INGEST_FILE = BASE_DIR / "IngestedURLs.xlsx"
BLOCKED_FILE = BASE_DIR / "BlockedURLs.xlsx"

# URL normalization settings
GUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
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


def load_database():
    """Load ingested and blocked URLs from Excel files."""
    ingested = set()
    blocked = set()
    
    try:
        if INGEST_FILE.exists():
            df = pd.read_excel(INGEST_FILE, sheet_name=0)
            # Try to find URL column
            url_col = None
            for col in ["DocumentLink", "URL", "Link", "url"]:
                if col in df.columns:
                    url_col = col
                    break
            if url_col is None:
                url_col = df.columns[0]  # Use first column
            
            for url in df[url_col].dropna():
                normalized = normalize_url(str(url))
                if normalized:
                    ingested.add(normalized)
    except Exception as e:
        print(f"Error loading ingested URLs: {e}")
    
    try:
        if BLOCKED_FILE.exists():
            df = pd.read_excel(BLOCKED_FILE, sheet_name=0)
            # Try to find URL column
            url_col = None
            for col in ["ArticlePublicLink", "URL", "Link", "url"]:
                if col in df.columns:
                    url_col = col
                    break
            if url_col is None:
                url_col = df.columns[0]  # Use first column
            
            for url in df[url_col].dropna():
                normalized = normalize_url(str(url))
                if normalized:
                    blocked.add(normalized)
    except Exception as e:
        print(f"Error loading blocked URLs: {e}")
    
    return ingested, blocked


def audit_urls(urls: list[str], ingested: set[str], blocked: set[str]) -> list[dict]:
    """
    Audit URLs against ingested and blocked databases.
    Returns list of results with status and reason.
    """
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
        # Check if GUID match
        elif guids:
            guid_match = None
            for guid in guids:
                # Check if ANY URL in ingested contains this GUID
                for ing_url in ingested:
                    if guid in ing_url:
                        guid_match = guid
                        break
                if guid_match:
                    break
            
            if guid_match:
                results.append({
                    "input": input_url,
                    "normalized": normalized,
                    "status": "found",
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
    ingested, blocked = load_database()
    
    # Run audit
    results = audit_urls(urls, ingested, blocked)
    
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
    ingested_exists = INGEST_FILE.exists()
    blocked_exists = BLOCKED_FILE.exists()
    
    ingested_count = 0
    blocked_count = 0
    
    if ingested_exists:
        try:
            df = pd.read_excel(INGEST_FILE, sheet_name=0)
            ingested_count = len(df)
        except:
            pass
    
    if blocked_exists:
        try:
            df = pd.read_excel(BLOCKED_FILE, sheet_name=0)
            blocked_count = len(df)
        except:
            pass
    
    return jsonify({
        "ingested_file": ingested_exists,
        "blocked_file": blocked_exists,
        "ingested_count": ingested_count,
        "blocked_count": blocked_count
    })


if __name__ == "__main__":
    print("Starting IngestionStatusCheck Web UI...")
    print(f"Database files location: {BASE_DIR}")
    print(f"  - IngestedURLs.xlsx: {INGEST_FILE.exists()}")
    print(f"  - BlockedURLs.xlsx: {BLOCKED_FILE.exists()}")
    print("\nOpen browser to http://localhost:5000")
    app.run(debug=True, host="localhost", port=5000)
