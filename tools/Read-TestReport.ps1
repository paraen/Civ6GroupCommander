param(
  [string]$LogPath = "C:\Users\31767\AppData\Local\Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log",
  [ValidateRange(10,200)][int]$Limit = 60
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LogPath)) { throw "Game Lua.log not found: $LogPath" }
$gcInfo = Get-Item -LiteralPath $LogPath
Write-Output ("Log updated: {0:yyyy-MM-dd HH:mm:ss}" -f $gcInfo.LastWriteTime)
$gcLines = @(Get-Content -LiteralPath $LogPath -Tail 8000 | Where-Object {
  $_ -match '\[GC\]|Runtime Error|stack traceback|Error loading'
})
$gcBoot = -1
for ($gcIndex=0; $gcIndex -lt $gcLines.Count; $gcIndex++) {
  if ($gcLines[$gcIndex] -match '\[GC\]\[BOOT\]') { $gcBoot=$gcIndex }
}
if ($gcBoot -ge 0) { $gcLines = @($gcLines | Select-Object -Skip $gcBoot) }
# Keep handshake/error/command evidence; omit repetitive selection refresh spam.
$gcLines | Where-Object { $_ -notmatch '\[GC\]\[SELECTION\]' } | Select-Object -Last $Limit
