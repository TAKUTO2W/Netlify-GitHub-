# ===================================================
# CARJAM X(Twitter) イベント告知投稿
# 2日に1回（偶数日）、直近のイベントまとめを@carjam_usdmに投稿する。
# daily-run.ps1 から毎朝呼ばれる。テストは -Force で日付ゲートを無視。
# ===================================================
param([switch]$Force)

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

# ---- 隔日ゲート（偶数日のみ投稿）----
if (-not $Force -and ((Get-Date).DayOfYear % 2 -ne 0)) {
    Write-Log "Xイベント告知: 本日は投稿日ではない（隔日運用）"
    exit 0
}

if ($X_API_KEY -like "ここに*" -or -not $X_API_KEY) {
    Write-Log "Xイベント告知スキップ: X_API_KEY 未設定"
    exit 0
}

# ---- 直近イベントの選定 ----
$events = @()
$raw = Get-Content "$PROJECT_ROOT\data\new-events.js" -Raw -Encoding UTF8
if ($raw -match 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') {
    $events += @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })
}
$events += @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })

$today = (Get-Date).Date
$upcoming = @($events | Where-Object {
    if (-not ($_.date -and $_.name)) { return $false }
    $d = [datetime]::MinValue
    # 日付形式が不正なイベントは無視（yyyy-MM-dd のみ受け付け）
    if (-not [datetime]::TryParseExact($_.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $false }
    return ($d -ge $today)
} | Sort-Object date | Select-Object -First 6)

# 同名イベントを除去して3件に絞る
$seen = @{}
$picked = @()
foreach ($e in $upcoming) {
    if (-not $seen.ContainsKey($e.name)) { $seen[$e.name] = $true; $picked += ,$e }
    if ($picked.Count -ge 3) { break }
}

if ($picked.Count -eq 0) {
    Write-Log "Xイベント告知スキップ: 直近イベントなし"
    exit 0
}

# ---- 投稿文の組み立て（X基準: 全角=2, 半角=1, URL=23 で280以内）----
function Get-XWeight($s) {
    $w = 0
    foreach ($c in $s.ToCharArray()) { if ([int]$c -le 0x7F) { $w += 1 } else { $w += 2 } }
    return $w
}
function Trunc($s, $max) {
    if ($s.Length -le $max) { return $s }
    return $s.Substring(0, $max).TrimEnd() + "…"
}

$url = $CARJAM_URL
$hashtags = "#カーイベント #車好きと繋がりたい"

do {
    $lines = @("🚗 直近のカーイベント")
    foreach ($e in $picked) {
        $d = [datetime]::ParseExact($e.date, "yyyy-MM-dd", $null)
        $lines += "・$($d.Month)/$($d.Day) $(Trunc $e.name 14)（$($e.prefecture)）"
    }
    $lines += "全国のイベント情報はこちら👇"
    $lines += $url
    $lines += $hashtags
    $text = $lines -join "`n"

    # URL部分は実長でなく23としてカウント
    $weight = (Get-XWeight ($text.Replace($url, ""))) + 23 + 1
    if ($weight -gt 275 -and $picked.Count -gt 1) {
        $picked = @($picked | Select-Object -First ($picked.Count - 1))
    } else { break }
} while ($true)

Write-Log "Xイベント告知: $($picked.Count)件で投稿（weight=$weight）"

# ---- OAuth 1.0a で POST /2/tweets ----
function Encode-Uri($s) { return [Uri]::EscapeDataString($s) }

$method = "POST"
$apiUrl = "https://api.twitter.com/2/tweets"
$nonce  = [System.Guid]::NewGuid().ToString("N")
$ts     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()

$oauthParams = [ordered]@{
    "oauth_consumer_key"     = $X_API_KEY
    "oauth_nonce"            = $nonce
    "oauth_signature_method" = "HMAC-SHA1"
    "oauth_timestamp"        = $ts
    "oauth_token"            = $X_ACCESS_TOKEN
    "oauth_version"          = "1.0"
}
$paramStr = ($oauthParams.GetEnumerator() | Sort-Object Key | ForEach-Object {
    "$(Encode-Uri $_.Key)=$(Encode-Uri $_.Value)"
}) -join "&"
$baseString = "$method&$(Encode-Uri $apiUrl)&$(Encode-Uri $paramStr)"
$signingKey = "$(Encode-Uri $X_API_KEY_SECRET)&$(Encode-Uri $X_ACCESS_TOKEN_SECRET)"
$hmac = New-Object System.Security.Cryptography.HMACSHA1
$hmac.Key = [System.Text.Encoding]::ASCII.GetBytes($signingKey)
$sig = [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($baseString)))
$oauthParams["oauth_signature"] = $sig
$authHeader = "OAuth " + (($oauthParams.GetEnumerator() | Sort-Object Key | ForEach-Object {
    "$(Encode-Uri $_.Key)=`"$(Encode-Uri $_.Value)`""
}) -join ", ")

$bodyObj = @{ text = $text } | ConvertTo-Json -Compress
$headers = @{ "Authorization" = $authHeader; "Content-Type" = "application/json" }

try {
    $res = Invoke-WebRequest -Uri $apiUrl -Method POST -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyObj)) -TimeoutSec 30 -UseBasicParsing
    $resJson = [System.Text.Encoding]::UTF8.GetString($res.RawContentStream.ToArray()) | ConvertFrom-Json
    Write-Log "Xイベント告知: 投稿成功 [Status: $($res.StatusCode)] tweet_id=$($resJson.data.id)"
} catch {
    Write-Log "Xイベント告知: 投稿失敗 - $_"
    exit 1
}
