param(
  [Parameter(Mandatory=$true)] [string] $OsBaseUrl,   # e.g. http://localhost:19220
  [Parameter(Mandatory=$true)] [string] $IndexName,   # e.g. kwve-transcripts
  [Parameter(Mandatory=$false)] [string] $TemplatePath,
  [Parameter(Mandatory=$false)] [string] $SamplePath
)

$ProgressPreference = 'SilentlyContinue'

function Invoke-Code($Script) {
  try {
    (Invoke-WebRequest -UseBasicParsing @Script).StatusCode
  } catch {
    if ($_.Exception.Response) { $_.Exception.Response.StatusCode.Value__ } else { 0 }
  }
}

# 1) Apply template (optional)
if ($TemplatePath -and (Test-Path -LiteralPath $TemplatePath)) {
  Write-Host "[INFO] Template path: $TemplatePath"
  $body = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
  $code = Invoke-Code @{
    Uri = "$OsBaseUrl/_index_template/kwve-transcripts-template"
    Method = 'PUT'
    ContentType = 'application/json'
    Body = $body
  }
  if ($code -eq 200)      { Write-Host "[PASS] Template applied (200)" }
  elseif ($code -eq 201)  { Write-Host "[PASS] Template created (201)" }
  else                    { Write-Host "[WARN] Template HTTP $code" }
} else {
  Write-Host "[WARN] Template not provided or not found. Continuing without it."
}

# 2) Create index (idempotent)
$code = Invoke-Code @{
  Uri = "$OsBaseUrl/$IndexName"
  Method = 'PUT'
}
if ($code -eq 200)        { Write-Host "[PASS] Index ok (200)" }
elseif ($code -eq 201)    { Write-Host "[PASS] Index created (201)" }
elseif ($code -in 400,409){ Write-Host "[PASS] Index exists ($code)" }
else                      { Write-Host "[WARN] Index HTTP $code" }

# 3) Insert sample doc (optional)
if ($SamplePath -and (Test-Path -LiteralPath $SamplePath)) {
  Write-Host "[INFO] Sample path: $SamplePath"
  $body = Get-Content -LiteralPath $SamplePath -Raw -Encoding UTF8
  $docId = 'radio:KWVE:2025-09-04T09:00:00Z' # matches your sample
  $uri = "$OsBaseUrl/$IndexName/_doc/$([uri]::EscapeDataString($docId))"

  $code = Invoke-Code @{
    Uri = $uri
    Method = 'POST'
    ContentType = 'application/json'
    Body = $body
  }
  if ($code -in 200,201) {
    Write-Host "[PASS] Sample doc indexed ($code)"
  } else {
    Write-Host "[INFO] Doc insert HTTP $code - retrying once..."
    Start-Sleep -Seconds 2
    $code = Invoke-Code @{
      Uri = $uri
      Method = 'POST'
      ContentType = 'application/json'
      Body = $body
    }
    if ($code -in 200,201) { Write-Host "[PASS] Sample doc indexed ($code)" }
    else                   { Write-Host "[WARN] Doc insert still HTTP $code" }
  }
} else {
  Write-Host "[WARN] Sample not provided or not found. Skipping sample doc."
}
