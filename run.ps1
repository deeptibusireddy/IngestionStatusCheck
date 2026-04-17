# URL Checker Web UI - PowerShell Setup & Run Script

Write-Host ""
Write-Host "========================================"
Write-Host "URL Checker - Web UI Setup" -ForegroundColor Cyan
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

# Check for Excel files
Write-Host ""
Write-Host "Checking for database files..."

if (-not (Test-Path "IngestedURLs.xlsx")) {
    Write-Host "⚠️  Warning: IngestedURLs.xlsx not found" -ForegroundColor Yellow
    Write-Host "   Make sure this file is in the same folder"
    Write-Host ""
}

if (-not (Test-Path "BlockedURLs.xlsx")) {
    Write-Host "⚠️  Warning: BlockedURLs.xlsx not found" -ForegroundColor Yellow
    Write-Host "   Make sure this file is in the same folder"
    Write-Host ""
}

# Run the app
Write-Host ""
Write-Host "========================================"
Write-Host "Starting URL Checker Web UI..." -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""
Write-Host "🌐 Open your browser to: http://localhost:5000" -ForegroundColor Green
Write-Host ""
Write-Host "(Press Ctrl+C to stop the server)"
Write-Host ""

python app.py

Read-Host "Press Enter to exit"
