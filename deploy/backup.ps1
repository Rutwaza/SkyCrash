# Daily database backup. Run by Windows Task Scheduler (see the guide).
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "backups"
New-Item -ItemType Directory -Force $dest | Out-Null
$file = "skycrash-$(Get-Date -Format 'yyyyMMdd-HHmm').sql.gz"

Push-Location $root
docker compose exec -T db sh -c "pg_dump -U postgres --clean --if-exists skycrash | gzip > /tmp/backup.sql.gz"
docker compose cp db:/tmp/backup.sql.gz (Join-Path $dest $file)
Pop-Location

# keep 30 days of backups locally
Get-ChildItem $dest -Filter "skycrash-*.sql.gz" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
Write-Host "Backup saved: $dest\$file"
# TIP: also copy the backups folder to another disk / cloud drive. One PC is a single point of failure.
