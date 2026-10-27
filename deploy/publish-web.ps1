# Rebuilds the Flutter app + landing page and publishes them. No server restart needed.
#   usage:  .\deploy\publish-web.ps1
$root = Split-Path -Parent $PSScriptRoot
$site = Join-Path $root "deploy\site"

Push-Location (Join-Path $root "app")
flutter build web --release --dart-define=API_URL=same --base-href /app/
$ok = $LASTEXITCODE
Pop-Location
if ($ok -ne 0) { throw "Flutter build failed - nothing was published." }

New-Item -ItemType Directory -Force $site | Out-Null
Remove-Item "$site\*" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$site\app" | Out-Null
Copy-Item "$root\app\build\web\*" "$site\app\" -Recurse      # the game  -> /app/
Copy-Item "$root\landing\*" $site -Recurse                    # landing   -> /
Copy-Item "$root\app\web\favicon.svg" "$site\favicon.svg"
Write-Host "Published. Hard-refresh the browser (Ctrl+Shift+R) to see changes."
