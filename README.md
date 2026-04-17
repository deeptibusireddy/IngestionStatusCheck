# IngestionStatusCheck

IngestionStatusCheck provides a simple way to validate URLs against your latest ingested and blocked URL lists.

Primary experience:
- Web UI for single URL checks and CSV uploads

Secondary experience:
- Legacy PowerShell script (archived)

## What You Need

1. Python 3.8+ installed.
2. These files in the project root:
   - `IngestedURLs.xlsx` or `IngestedURLs.csv`
   - `BlockedURLs.xlsx` or `BlockedURLs.csv`

Notes:
- The app tries `.xlsx` first and automatically falls back to `.csv`.
- CSV fallback is useful when Excel files are encrypted/protected.

## Quick Start (Web UI - Recommended)

1. Start the app:
   - Double-click `run.bat`
   - Or run PowerShell: `powershell -ExecutionPolicy Bypass -File .\run.ps1`
2. Open `http://localhost:5000` in your browser.
3. Choose one input mode:
   - Paste one URL per line (single URL works too)
   - Upload `.csv` or `.txt` with one URL per line
4. Click **Run Audit**.
5. Review results directly in the UI.

## Status Meanings

- `found`: URL exists in ingested content.
- `blocked`: URL is in the blocked list.
- `missing`: URL was not found.

## Legacy CLI (Archived)

If needed, the original script is at:
- `Archive\Legacy\IngestionStatusCheck.ps1`

Run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\Archive\Legacy\IngestionStatusCheck.ps1
```

Optional examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\Archive\Legacy\IngestionStatusCheck.ps1 -InputFile .\YourInputFile.xlsx -OutputTag teamA
```

```powershell
powershell -ExecutionPolicy Bypass -File .\Archive\Legacy\IngestionStatusCheck.ps1 -InputFile .\YourInputFile.xlsx -InputNoHeader
```

## Project Layout

- `app.py`: Flask backend API.
- `templates/index.html`: Web UI.
- `run.bat` and `run.ps1`: local launch scripts.
- `Archive\`: legacy scripts, sample data, and old temp outputs.

## Troubleshooting

- Python not found:
  Install Python and ensure it is in PATH.
- Web app does not start:
  Check if port 5000 is in use: `netstat -ano | findstr :5000`
- Data files missing in UI:
  Confirm `IngestedURLs.xlsx` and `BlockedURLs.xlsx` are in the project root.
