@echo off
rem Start the eDIL site at http://localhost:4567 on Windows (set PORT to change).
rem Double-click this file, or run bin\server from a Command Prompt.
cd /d "%~dp0.."
call bundle check >nul 2>&1 || call bundle install || goto :failed
ruby bin\fetch-data || goto :failed
bundle exec ruby app.rb
goto :eof

:failed
echo.
echo Could not start the site; see the messages above.
pause
exit /b 1
