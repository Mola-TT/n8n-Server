@echo off
REM Windows batch script to start the n8n User Management Web Application

echo ================================================================================
echo n8n User Management Web Application
echo ================================================================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.7 or higher from https://www.python.org/
    echo.
    pause
    exit /b 1
)

REM Check if webapp.env exists
if not exist "webapp.env" (
    echo WARNING: webapp.env not found
    echo Copying env.template to webapp.env...
    copy env.template webapp.env >nul
    echo.
    echo Please edit webapp.env and set your N8N_API_BASE_URL and N8N_API_KEY
    echo Then run this script again.
    echo.
    pause
    exit /b 1
)

REM Start the server
echo Starting server...
echo.
python serve.py

pause

