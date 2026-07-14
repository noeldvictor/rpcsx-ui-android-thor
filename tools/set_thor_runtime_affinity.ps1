param(
    [ValidateSet("Status", "DefaultF8", "AllThreadsFF", "RsxPrimeSpuNonPrimePpuA715")]
    [string] $Mode = "Status",
    [string] $Package = "net.rpcsx.easy"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$adb = if ($env:ANDROID_HOME -and (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"))) {
    Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
} else {
    "adb"
}

$remote = @'
PACKAGE="__PACKAGE__"
MODE="__MODE__"
pid=$(pidof "$PACKAGE")
echo "package=$PACKAGE"
echo "mode=$MODE"
echo "pid=$pid"

if [ -z "$pid" ]; then
  echo "No running process."
  exit 0
fi

apply_mask() {
  mask="$1"
  tid="$2"
  run-as "$PACKAGE" taskset -p "$mask" "$tid" >/dev/null 2>&1 || echo "failed mask=$mask tid=$tid"
}

case "$MODE" in
  DefaultF8)
    for t in /proc/$pid/task/*; do
      apply_mask f8 "${t##*/}"
    done
    apply_mask f8 "$pid"
    ;;
  AllThreadsFF)
    for t in /proc/$pid/task/*; do
      apply_mask ff "${t##*/}"
    done
    apply_mask ff "$pid"
    ;;
  RsxPrimeSpuNonPrimePpuA715)
    for t in /proc/$pid/task/*; do
      tid="${t##*/}"
      name=$(cat "$t/comm" 2>/dev/null)
      case "$name" in
        rsx::thread|RSX*)
          apply_mask 80 "$tid"
          ;;
        SPU*|spu*)
          apply_mask 7f "$tid"
          ;;
        PPU*|ppu*)
          apply_mask 18 "$tid"
          ;;
      esac
    done
    ;;
esac

echo "process:"
grep Cpus_allowed /proc/$pid/status
echo "threads:"
for t in /proc/$pid/task/*; do
  name=$(cat "$t/comm" 2>/dev/null)
  case "$name" in
    rsx*|RSX*|SPU*|spu*|PPU*|ppu*)
      echo "--- $name ${t##*/}"
      grep "Cpus_allowed_list" "$t/status"
      ;;
  esac
done
'@

$remote = $remote.Replace("__PACKAGE__", $Package).Replace("__MODE__", $Mode)
# PowerShell here-strings use CRLF on Windows. Android's /system/bin/sh treats
# the trailing carriage returns as part of tokens (for example "in\r"), which
# breaks the case statement and can leave an A/B affinity run half-applied.
$remote = $remote.Replace("`r`n", "`n")
& $adb shell $remote
