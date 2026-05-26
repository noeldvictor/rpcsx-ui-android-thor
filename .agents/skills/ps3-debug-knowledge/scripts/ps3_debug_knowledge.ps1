[CmdletBinding()]
param(
  [ValidateSet('Search', 'Status', 'Append')]
  [string]$Action = 'Search',

  [string]$Query = '',

  [string]$Text = '',

  [int]$Context = 2,

  [int]$MaxMatches = 80
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')
  return $root.Path
}

function Get-KnowledgeFiles {
  param([string]$Root)

  $files = @()
  $agents = Join-Path $Root 'AGENTS.md'
  if (Test-Path -LiteralPath $agents) {
    $files += Get-Item -LiteralPath $agents
  }

  $experiments = Join-Path $Root 'debug-experiments'
  if (Test-Path -LiteralPath $experiments) {
    $files += Get-ChildItem -LiteralPath $experiments -Filter '*.md' -File
  }

  $skills = Join-Path $Root '.agents\skills'
  if (Test-Path -LiteralPath $skills) {
    $files += Get-ChildItem -LiteralPath $skills -Recurse -Filter 'SKILL.md' -File
    $files += Get-ChildItem -Path (Join-Path $skills '*\references\*.md') -File -ErrorAction SilentlyContinue
  }

  return $files | Sort-Object FullName -Unique
}

function Write-RelativeMatch {
  param(
    [string]$Root,
    [Microsoft.PowerShell.Commands.MatchInfo]$Match
  )

  $relative = Resolve-Path -LiteralPath $Match.Path -Relative
  if ($relative.StartsWith('.\')) {
    $relative = $relative.Substring(2)
  }
  Write-Output ("{0}:{1}: {2}" -f $relative, $Match.LineNumber, $Match.Line.Trim())
}

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot

if ($Action -eq 'Status') {
  $queries = @(
    'User gate as of',
    'GPU migration credit as of',
    'Current Windows RSX-local GPU-residency stack',
    'GPU-port accounting as of',
    'Windows PUTLLC16 relaxed-reservation',
    'Windows dynamic MFC fallback',
    'Windows depth-feedback RSX slice'
  )

  $files = Get-KnowledgeFiles -Root $repoRoot
  foreach ($item in $queries) {
    Write-Output ""
    Write-Output ("# {0}" -f $item)
    $matches = Select-String -LiteralPath $files.FullName -Pattern $item -SimpleMatch -Context 0,1 | Select-Object -First 8
    foreach ($match in $matches) {
      Write-RelativeMatch -Root $repoRoot -Match $match
      foreach ($ctx in $match.Context.PostContext) {
        if ($ctx.Trim().Length -gt 0) {
          Write-Output ("  {0}" -f $ctx.Trim())
        }
      }
    }
  }
  exit 0
}

if ($Action -eq 'Append') {
  if ([string]::IsNullOrWhiteSpace($Text)) {
    throw 'Append requires -Text.'
  }

  $path = Join-Path $repoRoot 'debug-experiments\ps3-debug-knowledge.md'
  if (-not (Test-Path -LiteralPath $path)) {
    "# PS3 Debug Knowledge`r`n" | Set-Content -LiteralPath $path -Encoding UTF8
  }

  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
  Add-Content -LiteralPath $path -Encoding UTF8 -Value ""
  Add-Content -LiteralPath $path -Encoding UTF8 -Value ("## {0}" -f $stamp)
  Add-Content -LiteralPath $path -Encoding UTF8 -Value $Text
  Write-Output ("Appended durable note to {0}" -f $path)
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Query)) {
  throw 'Search requires -Query, or use -Action Status.'
}

$knowledgeFiles = Get-KnowledgeFiles -Root $repoRoot
$matches = Select-String -LiteralPath $knowledgeFiles.FullName -Pattern $Query -SimpleMatch -Context $Context,$Context |
  Select-Object -First $MaxMatches

foreach ($match in $matches) {
  Write-RelativeMatch -Root $repoRoot -Match $match
  foreach ($pre in $match.Context.PreContext) {
    if ($pre.Trim().Length -gt 0) {
      Write-Output ("  < {0}" -f $pre.Trim())
    }
  }
  foreach ($post in $match.Context.PostContext) {
    if ($post.Trim().Length -gt 0) {
      Write-Output ("  > {0}" -f $post.Trim())
    }
  }
}

if (-not $matches) {
  Write-Output ("No matches for '{0}'." -f $Query)
}
