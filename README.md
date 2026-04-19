# IngestionStatusCheck

IngestionStatusCheck provides a simple way to validate URLs against your latest ingested and blocked URL lists.

Primary experience:
- Web UI for single URL checks and CSV uploads

Secondary experience:
- Legacy PowerShell script (archived)

## What You Need

1. **Python 3.8+** — download from [python.org](https://www.python.org/downloads/). During installation, check **"Add Python to PATH"**.
2. These files in the project root (at least one format each):
   - `IngestedURLs.xlsx` **or** `IngestedURLs.csv`
   - `BlockedURLs.xlsx` **or** `BlockedURLs.csv`

> The app tries `.xlsx` first and automatically falls back to `.csv`. Encrypted/password-protected Excel files are not supported — use CSV instead.

## Quick Start (Web UI)

1. Open PowerShell in the project folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\run.ps1
   ```

   `run.ps1` will automatically create a virtual environment and install all Python dependencies on first run. Subsequent runs skip the install if nothing changed.

2. Open `http://localhost:5000` in your browser.
3. Choose one input mode:
   - Paste one URL per line
   - Upload a `.csv` or `.txt` with one URL per line
4. Click **Run Audit**.
5. Review results directly in the UI.

## Status Meanings

| Status | Meaning |
|--------|---------|
| `found` | URL matched in ingested content |
| `blocked` | URL matched in the blocked list |
| `missing` | URL was not found in either list |

> Azure DevOps wiki URLs are matched by page ID, so human-readable URLs (e.g. `/Infrastructure%20Solutions/_wiki/…/7975`) will match stored GUID-based equivalents automatically.

## Troubleshooting

- **Python not found**: Install from python.org and ensure "Add Python to PATH" was checked. Re-open PowerShell after installing.
- **Script blocked by execution policy**: Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, then retry.
- **Port 5000 in use**: Run `netstat -ano | findstr :5000` to find the blocking process.
- **Data files missing in UI**: Confirm `IngestedURLs.csv` (or `.xlsx`) and `BlockedURLs.csv` (or `.xlsx`) are in the project root.

## Project Layout

- `app.py`: Flask backend API.
- `templates/index.html`: Web UI.
- `run.ps1`: Setup and launch script (creates venv, installs dependencies, starts server).
- `requirements.txt`: Python dependencies.
- `Archive\`: Legacy scripts, sample data, and old temp outputs.

## Legacy CLI (Archived)

The original PowerShell script is at `Archive\Legacy\IngestionStatusCheck.ps1`.

```powershell
powershell -ExecutionPolicy Bypass -File .\Archive\Legacy\IngestionStatusCheck.ps1
```
