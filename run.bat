@echo off
REM URL Checker Web UI Setup & Run Script

echo.
echo ========================================
echo URL Checker - Web UI Setup
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Python is not installed or not in PATH
    echo Please install Python 3.8+ from python.org
    pause
    exit /b 1
)

echo ✓ Python found
python --version

REM Check if venv exists, if not create it
if not exist "venv" (
    echo.
    echo Creating virtual environment...
    python -m venv venv
)

REM Activate venv
echo Activating virtual environment...
call venv\Scripts\activate.bat

REM Install/update requirements
echo.
echo Installing dependencies (flask, pandas, openpyxl)...
pip install -q -r requirements.txt

REM Check for Excel files
echo.
echo Checking for database files...
if not exist "IngestedURLs.xlsx" (
    echo ⚠️  Warning: IngestedURLs.xlsx not found
    echo    Make sure this file is in the same folder
    echo.
)

if not exist "BlockedURLs.xlsx" (
    echo ⚠️  Warning: BlockedURLs.xlsx not found
    echo    Make sure this file is in the same folder
    echo.
)

REM Run the app
echo.
echo ========================================
echo Starting URL Checker Web UI...
echo ========================================
echo.
echo 🌐 Open your browser to: http://localhost:5000
echo.
echo (Press Ctrl+C to stop the server)
echo.

python app.py

pause
