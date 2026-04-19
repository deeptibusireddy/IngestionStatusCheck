# IngestionStatusCheck Web UI - PowerShell Setup & Run Script

Write-Host ""
Write-Host "========================================"
Write-Host "IngestionStatusCheck - Web UI Setup" -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    Write-Host "✓ Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Python is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python 3.8+ from python.org" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if venv exists, if not create it
if (-not (Test-Path "venv")) {
    Write-Host ""
    Write-Host "Creating virtual environment..."
    python -m venv venv
    Write-Host "✓ Virtual environment created" -ForegroundColor Green
}

# Activate venv
Write-Host "Activating virtual environment..."
& ".\venv\Scripts\Activate.ps1"

# Install/update requirements
Write-Host ""
Write-Host "Installing dependencies (flask, pandas, openpyxl)..."
pip install -q -r requirements.txt
Write-Host "✓ Dependencies installed" -ForegroundColor Green

# Check for database files (accept either .xlsx or .csv for each)
Write-Host ""
Write-Host "Checking for database files..."

if (-not (Test-Path "IngestedURLs.xlsx") -and -not (Test-Path "IngestedURLs.csv")) {
    Write-Host "⚠️  Warning: IngestedURLs.xlsx or IngestedURLs.csv not found" -ForegroundColor Yellow
    Write-Host "   Add one of these files to the project folder before running the audit."
    Write-Host ""
} else {
    $ingFile = if (Test-Path "IngestedURLs.csv") { "IngestedURLs.csv" } else { "IngestedURLs.xlsx" }
    Write-Host "✓ Ingested URLs: $ingFile" -ForegroundColor Green
}

if (-not (Test-Path "BlockedURLs.xlsx") -and -not (Test-Path "BlockedURLs.csv")) {
    Write-Host "⚠️  Warning: BlockedURLs.xlsx or BlockedURLs.csv not found" -ForegroundColor Yellow
    Write-Host "   Add one of these files to the project folder before running the audit."
    Write-Host ""
} else {
    $blkFile = if (Test-Path "BlockedURLs.csv") { "BlockedURLs.csv" } else { "BlockedURLs.xlsx" }
    Write-Host "✓ Blocked URLs:  $blkFile" -ForegroundColor Green
}

# Run the app
Write-Host ""
Write-Host "========================================"
Write-Host "Starting IngestionStatusCheck Web UI..." -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""
Write-Host "🌐 Open your browser to: http://localhost:5000" -ForegroundColor Green
Write-Host ""
Write-Host "(Press Ctrl+C to stop the server)"
Write-Host ""

python app.py

Read-Host "Press Enter to exit"
