# ===================================================
# CARJAM イベント自動収集スクリプト
# 対象: mach5.jp / dupcar-event.com
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

# System.Web なしで使えるHTML実体参照デコード
function Decode-Html($str) {
    $str = $str -replace '&amp;',  '&'
    $str = $str -replace '&lt;',   '<'
    $str = $str -replace '&gt;',   '>'
    $str = $str -replace '&quot;', '"'
    $str = $str -replace '&#39;',  "'"
    $str = $str -replace '&nbsp;', ' '
    # 数値参照 &#nnn;
    $str = [regex]::Replace($str, '&#(\d+);', { [char][int]$args[0].Groups[1].Value })
    return $str.Trim()
}

# 都道府県リスト
$PREFS = @("北海道","青森県","岩手県","宮城県","秋田県","山形県","福島県",
           "茨城県","栃木県","群馬県","埼玉県","千葉県","東京都","神奈川県",
           "新潟県","富山県","石川県","福井県","山梨県","長野県","岐阜県","静岡県","愛知県",
           "三重県","滋賀県","京都府","大阪府","兵庫県","奈良県","和歌山県",
           "鳥取県","島根県","岡山県","広島県","山口県",
           "徳島県","香川県","愛媛県","高知県",
           "福岡県","佐賀県","長崎県","熊本県","大分県","宮崎県","鹿児島県","沖縄県")

$REGION_MAP = @{
    "北海道"="北海道"
    "青森県"="東北";"岩手県"="東北";"宮城県"="東北";"秋田県"="東北";"山形県"="東北";"福島県"="東北"
    "茨城県"="関東";"栃木県"="関東";"群馬県"="関東";"埼玉県"="関東";"千葉県"="関東";"東京都"="関東";"神奈川県"="関東"
    "新潟県"="中部";"富山県"="中部";"石川県"="中部";"福井県"="中部";"山梨県"="中部";"長野県"="中部";"岐阜県"="中部";"静岡県"="中部";"愛知県"="中部"
    "三重県"="近畿";"滋賀県"="近畿";"京都府"="近畿";"大阪府"="近畿";"兵庫県"="近畿";"奈良県"="近畿";"和歌山県"="近畿"
    "鳥取県"="中国";"島根県"="中国";"岡山県"="中国";"広島県"="中国";"山口県"="中国"
    "徳島県"="四国";"香川県"="四国";"愛媛県"="四国";"高知県"="四国"
    "福岡県"="九州";"佐賀県"="九州";"長崎県"="九州";"熊本県"="九州";"大分県"="九州";"宮崎県"="九州";"鹿児島県"="九州";"沖縄県"="九州"
}

function Get-Prefecture($text) {
    foreach ($p in $PREFS) {
        if ($text -match [regex]::Escape($p)) { return $p }
    }
    return ""
}

Write-Log "=== check-events.ps1 開始 ==="

# 既知URLリストを読み込む
$knownUrlsFile = "$PROJECT_ROOT\data\known-event-urls.json"
$knownUrls = @()
if (Test-Path $knownUrlsFile) {
    $raw = Get-Content $knownUrlsFile -Raw -Encoding UTF8
    if ($raw.Trim() -ne "" -and $raw.Trim() -ne "null") {
        try { $knownUrls = $raw | ConvertFrom-Json } catch {}
    }
}
if (-not $knownUrls) { $knownUrls = @() }

# 既存の new-events.js から現在のリストを読み込む
$newEventsFile = "$PROJECT_ROOT\data\new-events.js"
$existingNewEvents = @()
if (Test-Path $newEventsFile) {
    $raw = Get-Content $newEventsFile -Raw -Encoding UTF8
    if ($raw -match 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') {
        try { $existingNewEvents = $Matches[1] | ConvertFrom-Json } catch {}
    }
}
if (-not $existingNewEvents) { $existingNewEvents = @() }

$discoveredEvents = @()
$newUrls = @()

# ===== mach5.jp =====
Write-Log "mach5.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://www.mach5.jp/eventmania/allevent.php" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content

    $trMatches = [regex]::Matches($html, '<tr[^>]*>([\s\S]*?)</tr>', 'IgnoreCase')
    foreach ($tr in $trMatches) {
        $row = $tr.Groups[1].Value
        if ($row -match '<a\s+href="([^"]+)"[^>]*>([^<]+)</a>') {
            $href = $Matches[1].Trim()
            $name = Decode-Html $Matches[2]
            $date = ""
            if ($row -match '(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})') {
                $date = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }
            $pref = Get-Prefecture $row
            if ($href -notmatch '^https?://') {
                $href = "https://www.mach5.jp/eventmania/" + $href.TrimStart('/')
            }
            if ($name -and $date -and ($href -notin $knownUrls)) {
                $discoveredEvents += [PSCustomObject]@{ name=$name; date=$date; prefecture=$pref; venue=""; url=$href; source="mach5" }
                $newUrls += $href
            }
        }
    }
    Write-Log "mach5.jp: $($discoveredEvents.Count) 件の新規候補"
} catch {
    Write-Log "mach5.jp エラー: $_"
}

# ===== dupcar-event.com =====
Write-Log "dupcar-event.com を取得中..."
try {
    $res2 = Invoke-WebRequest -Uri "https://dupcar-event.com/" -UseBasicParsing -TimeoutSec 30
    $html2 = $res2.Content

    $eventLinks = [regex]::Matches($html2, 'href="(https://dupcar-event\.com/event/\d+/)"')
    $uniqueLinks = $eventLinks | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    foreach ($link in $uniqueLinks) {
        if ($link -in $knownUrls) { continue }
        try {
            $detail = Invoke-WebRequest -Uri $link -UseBasicParsing -TimeoutSec 20
            $dhtml = $detail.Content

            $ename = ""
            if ($dhtml -match '<h1[^>]*>\s*([^<]+)\s*</h1>') { $ename = Decode-Html $Matches[1] }

            $edate = ""
            if ($dhtml -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }

            $epref = Get-Prefecture $dhtml

            $evenue = ""
            if ($dhtml -match '会場[^\n<]{0,20}<[^>]+>\s*([^<]{2,40})') { $evenue = Decode-Html $Matches[1] }

            if ($ename -and $edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url=$link; source="dupcar" }
                $newUrls += $link
                Write-Log "  dupcar 新着: $ename ($edate)"
            }
            Start-Sleep -Milliseconds 300
        } catch {
            Write-Log "  dupcar 詳細取得エラー ($link): $_"
        }
    }
} catch {
    Write-Log "dupcar-event.com エラー: $_"
}

# ===== 新規イベントをIDを付けてマージ =====
$nextId = $NEW_EVENT_START_ID
if ($existingNewEvents.Count -gt 0) {
    $maxId = ($existingNewEvents | Measure-Object -Property id -Maximum).Maximum
    if ($maxId -ge $nextId) { $nextId = $maxId + 1 }
}

$newEventObjects = @()
foreach ($ev in $discoveredEvents) {
    $region = if ($REGION_MAP.ContainsKey($ev.prefecture)) { $REGION_MAP[$ev.prefecture] } else { "その他" }
    $newEventObjects += [PSCustomObject]@{
        id          = $nextId
        name        = $ev.name
        date        = $ev.date
        endDate     = $ev.date
        prefecture  = if ($ev.prefecture) { $ev.prefecture } else { "未定" }
        region      = $region
        venue       = if ($ev.venue) { $ev.venue } else { "未定" }
        category    = "カーミーティング"
        description = "$($ev.name) の開催情報です。"
        url         = $ev.url
        featured    = $false
        source      = $ev.source
    }
    $nextId++
}

$mergedEvents = @($existingNewEvents) + @($newEventObjects)

# new-events.js を書き出す（空配列を確実に [] にする）
if ($mergedEvents.Count -eq 0) {
    $jsonEvents = "[]"
} elseif ($mergedEvents.Count -eq 1) {
    $jsonEvents = "[" + ($mergedEvents[0] | ConvertTo-Json -Compress) + "]"
} else {
    $jsonEvents = $mergedEvents | ConvertTo-Json -Depth 5 -Compress
}
$jsContent = "// 自動更新される。scripts/check-events.ps1 が書き換える`r`nwindow.NEW_EVENTS = $jsonEvents;`r`n"
[System.IO.File]::WriteAllText($newEventsFile, $jsContent, [System.Text.Encoding]::UTF8)
Write-Log "new-events.js を更新: 合計 $($mergedEvents.Count) 件"

# known-event-urls.json を更新
$allKnown = (@($knownUrls) + @($newUrls)) | Where-Object { $_ } | Sort-Object -Unique
if ($allKnown.Count -eq 0) {
    "[]" | Set-Content -Path $knownUrlsFile -Encoding UTF8
} else {
    $allKnown | ConvertTo-Json | Set-Content -Path $knownUrlsFile -Encoding UTF8
}
Write-Log "known-event-urls.json 更新: $($allKnown.Count) 件"

# ===== updates.js を更新 =====
$updatesFile = "$PROJECT_ROOT\data\updates.js"
$currentUpdates = [PSCustomObject]@{ lastChecked = $null; announcements = @() }
if (Test-Path $updatesFile) {
    $raw = Get-Content $updatesFile -Raw -Encoding UTF8
    if ($raw -match 'window\.SITE_UPDATES\s*=\s*(\{[\s\S]*?\});') {
        try { $currentUpdates = $Matches[1] | ConvertFrom-Json } catch {}
    }
}

$now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$currentUpdates.lastChecked = $now

if ($newEventObjects.Count -gt 0) {
    $ann = [PSCustomObject]@{
        type    = "events"
        count   = $newEventObjects.Count
        date    = (Get-Date -Format "yyyy-MM-dd")
        message = "新着イベント $($newEventObjects.Count) 件を追加しました"
        names   = ($newEventObjects | Select-Object -First 3 | ForEach-Object { $_.name }) -join "、"
    }
    $anns = @($currentUpdates.announcements) + @($ann)
    if ($anns.Count -gt 10) { $anns = $anns | Select-Object -Last 10 }
    $currentUpdates.announcements = $anns
}

$updJson = $currentUpdates | ConvertTo-Json -Depth 5 -Compress
$updJs = "// 自動更新される。scripts/check-events.ps1 / gen-blog.ps1 が書き換える`r`nwindow.SITE_UPDATES = $updJson;`r`n"
[System.IO.File]::WriteAllText($updatesFile, $updJs, [System.Text.Encoding]::UTF8)

Write-Log "=== check-events.ps1 完了 (新規: $($newEventObjects.Count) 件) ==="
