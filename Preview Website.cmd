@echo off
cd /d "%~dp0"
echo Four.Meme local website
echo After startup, open http://127.0.0.1:8814 in your browser.
echo Close this window or press Ctrl+C to stop.
node scripts\preview-site.mjs
pause
