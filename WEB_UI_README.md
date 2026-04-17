# URL Checker Web UI

A modern, browser-based interface for auditing URLs against your ingested and blocked URL databases.

## Quick Start

### 1. Prerequisites
- **Python 3.8+** installed (download from [python.org](https://python.org))
- **IngestedURLs.xlsx** - Your ingested URLs database
- **BlockedURLs.xlsx** - Your blocked URLs database

### 2. Run the App

**Option A: Batch File (Windows)**
```
Double-click run.bat
```

**Option B: PowerShell**
```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

**Option C: Manual**
```powershell
# Create virtual environment (first time only)
python -m venv venv

# Activate virtual environment
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the app
python app.py
```

### 3. Open in Browser

Once running, open your browser to:
```
http://localhost:5000
```

## How It Works

### Input
- Paste one URL per line in the text area
- URLs can be in any format (http/https/no scheme)

### Processing
The tool analyzes each URL:
1. Normalizes it (removes tracking params, handles redirects, etc.)
2. Extracts any GUIDs found in the URL
3. Matches against your databases

### Output Status
- **found** - URL exists in ingested content
- **blocked** - URL is in the blocked list
- **missing** - URL not found in database
- **not-testable** - URL requires sign-in (cannot validate)

### Export
- Click "Download CSV" to get results as a CSV file
- File includes original URL, status, reason, and any GUIDs found

## File Structure

```
URL.Checker/
├── app.py                    # Flask web server
├── requirements.txt          # Python dependencies
├── run.bat                   # Windows batch launcher
├── run.ps1                   # PowerShell launcher
├── templates/
│   └── index.html           # Web UI frontend
├── IngestedURLs.xlsx        # Your ingested URLs (required)
├── BlockedURLs.xlsx         # Your blocked URLs (required)
└── audit_results/           # Output folder (auto-created)
```

## Configuration

### Database Files
The app looks for:
- `IngestedURLs.xlsx` with a column named: `DocumentLink`, `URL`, or first column
- `BlockedURLs.xlsx` with a column named: `ArticlePublicLink`, `URL`, or first column

If your Excel columns are named differently, update `app.py` lines ~100-105:
```python
for col in ["YOUR_COLUMN", "DocumentLink", "URL", "Link", "url"]:
```

### Port
Default port is 5000. To change, modify `app.py` line 175:
```python
app.run(debug=True, host="localhost", port=YOUR_PORT)
```

## Troubleshooting

### Error: "Python is not installed"
- Install Python 3.8+ from [python.org](https://python.org)
- During installation, check "Add Python to PATH"
- Restart terminal/PowerShell after installing

### Error: "Database files not found"
- Make sure `IngestedURLs.xlsx` and `BlockedURLs.xlsx` are in the same folder as `app.py`
- Check that the status bar shows correct row counts

### Error: "Port 5000 already in use"
- Another application is using port 5000
- Find the process: `netstat -ano | findstr :5000`
- Edit port in `app.py` line 175: `port=5001`

### Slow performance
- Large database files (100k+ URLs) may take time to load
- Use filtered subsets of data for testing

### URLs not matching
- Check that URLs are valid and complete
- The tool normalizes URLs but may not handle all edge cases
- Ensure your Excel files are in the correct format

## API Reference

### POST /api/audit
Audit a list of URLs.

**Request:**
```json
{
  "urls": "https://example.com\nhttps://another.com"
}
```

**Response:**
```json
{
  "results": [
    {
      "input": "https://example.com",
      "normalized": "https://example.com",
      "status": "found",
      "reason": "Full URL match",
      "guids": []
    }
  ],
  "counts": {
    "found": 1,
    "blocked": 0,
    "missing": 0,
    "total": 1
  }
}
```

### GET /api/status
Check database status.

**Response:**
```json
{
  "ingested_file": true,
  "blocked_file": true,
  "ingested_count": 12345,
  "blocked_count": 456
}
```

### POST /api/download
Download results as CSV.

## Browser Compatibility

- Chrome/Edge: ✓ Full support
- Firefox: ✓ Full support
- Safari: ✓ Full support
- IE11: ⚠️ Not supported

## Privacy

All processing happens locally on your machine:
- Excel files are read from your local folder
- URLs never leave your machine
- No data is sent to external services

## Performance Tips

1. **Separate databases for testing**
   - Use smaller Excel files for initial testing
   - Avoid 100k+ row files for interactive use

2. **Batch processing**
   - For large batches, consider using the Classic PowerShell method
   - Web UI is optimized for 100-1000 URLs per batch

3. **Memory**
   - Each database is loaded into memory
   - Large files may require more RAM
   - 100k URLs ≈ 100MB memory

## Need Help?

- Check the URL formatting (should start with `http://` or `https://`)
- Verify Excel column names match the expected names
- Look in `audit_results/` folder for previous runs (if using PowerShell)

## License & Credits

Built to simplify URL audits for content ingestion workflows.