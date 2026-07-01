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

# イベント名・会場名のキーワードから都道府県を推定
function Get-PrefectureFromName($name) {
    $map = [ordered]@{
        "北海道|ふらの|富良野|EZO|蝦夷|札幌|函館|旭川" = "北海道"
        "青森|弘前|八戸" = "青森県"
        "岩手|盛岡" = "岩手県"
        "宮城|仙台" = "宮城県"
        "秋田" = "秋田県"
        "山形|やまがた" = "山形県"
        "福島" = "福島県"
        "茨城|水戸|つくば" = "茨城県"
        "栃木|宇都宮|日光" = "栃木県"
        "群馬|前橋|高崎|伊勢崎" = "群馬県"
        "埼玉|さいたま|浦和|大宮" = "埼玉県"
        "千葉|幕張|柏" = "千葉県"
        "東京|品川|渋谷|新宿|秋葉原|羽田" = "東京都"
        "横浜|神奈川|川崎|湘南" = "神奈川県"
        "新潟|国上|長岡|SORAIRO" = "新潟県"
        "富山" = "富山県"
        "金沢|石川|能登|北陸" = "石川県"
        "福井" = "福井県"
        "山梨|甲府|富士吉田" = "山梨県"
        "長野|信州|北信越|松本|諏訪" = "長野県"
        "岐阜|可児" = "岐阜県"
        "静岡|浜松|富士" = "静岡県"
        "名古屋|愛知|豊田|岡崎" = "愛知県"
        "三重|鈴鹿|伊勢" = "三重県"
        "滋賀|琵琶湖|大津" = "滋賀県"
        "京都|きょうと" = "京都府"
        "OSAKA|大阪|なにわ|難波|梅田" = "大阪府"
        "神戸|兵庫|姫路|尼崎" = "兵庫県"
        "奈良" = "奈良県"
        "和歌山" = "和歌山県"
        "鳥取" = "鳥取県"
        "島根|山陰" = "島根県"
        "岡山" = "岡山県"
        "広島|HIROSHIMA" = "広島県"
        "山口" = "山口県"
        "徳島" = "徳島県"
        "香川|高松" = "香川県"
        "愛媛|松山" = "愛媛県"
        "高知" = "高知県"
        "福岡|博多|北九州" = "福岡県"
        "佐賀" = "佐賀県"
        "長崎" = "長崎県"
        "熊本|肥後" = "熊本県"
        "大分" = "大分県"
        "宮崎" = "宮崎県"
        "鹿児島|KAGOSHIMA" = "鹿児島県"
        "沖縄|OKINAWA|那覇" = "沖縄県"
    }
    foreach ($pattern in $map.Keys) {
        if ($name -match $pattern) { return $map[$pattern] }
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
            $pref = Get-PrefectureFromName $name
            if (-not $pref) { $pref = Get-Prefecture $row }
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

# ===== RACRY (racry.jp) =====
Write-Log "racry.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://racry.jp/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    # 各イベントリンクを取得して詳細ページを解析
    $links = [regex]::Matches($html, 'href="(https://racry\.jp/event/[^"]+)"') |
             ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $before = $discoveredEvents.Count
    foreach ($link in $links) {
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
            $epref = Get-PrefectureFromName $ename
            if (-not $epref) { $epref = Get-Prefecture $dhtml }
            if ($ename -and $edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$link; source="racry" }
                $newUrls += $link
            }
            Start-Sleep -Milliseconds 200
        } catch {}
    }
    Write-Log "racry.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "racry.jp エラー: $_"
}

# ===== Americars & Trucks (americarsandtrucks.com) =====
Write-Log "americarsandtrucks.com を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://americarsandtrucks.com/jp/events/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # <article> or event block with h3 title + date + location
    $blocks = [regex]::Matches($html, '(?s)<(?:article|div)[^>]*class="[^"]*event[^"]*"[^>]*>(.*?)</(?:article|div)>', 'IgnoreCase')
    if ($blocks.Count -eq 0) {
        # fallback: find h3 blocks
        $blocks = [regex]::Matches($html, '(?s)<h3[^>]*>(.*?)</h3>', 'IgnoreCase')
    }
    foreach ($block in $blocks) {
        $btext = $block.Groups[1].Value
        $ename = ""
        if ($btext -match '<[^>]+>([^<]{5,80})<') { $ename = Decode-Html $Matches[1] }
        elseif ($btext -match '([^<]{5,80})') { $ename = Decode-Html $Matches[1].Trim() }
        if (-not $ename) { continue }
        # date in surrounding context
        $ctx = $html.Substring([Math]::Max(0, $block.Index - 500), [Math]::Min(1000, $html.Length - $block.Index))
        $edate = ""
        if ($ctx -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($ctx -match '(\d{1,2})月\s*[·・]\s*(\d{1,2})') {
            $yr = (Get-Date).Year
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        $eurl = ""
        if ($ctx -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
        $epref = Get-PrefectureFromName "$ename $ctx"
        if (-not $epref) { $epref = Get-Prefecture $ctx }
        if ($ename -and $edate -and $eurl -and ($eurl -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="americars" }
            $newUrls += $eurl
        }
    }
    Write-Log "americarsandtrucks.com: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "americarsandtrucks.com エラー: $_"
}

# ===== 24OFFMAP (24offmap.jp) =====
Write-Log "24offmap.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://www.24offmap.jp/events/vehicle/classic" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    $yr = (Get-Date).Year
    # Next.js SSR: <span class="text-[var(--accent)]...">日付</span> → <p class="...font-bold...">タイトル</p> → 📍 都道府県
    $evBlocks = [regex]::Matches($html, '(?s)<span class="text-\[var\(--accent\)\][^"]*">(\d+/\d+[^<]*)</span>.*?<p class="text-white[^"]*font-bold[^"]*">([^<]+)</p>.*?📍\s*(?:<!--[^-]*-->)?\s*([^<\n,·]+)(?:.*?href="(https?://[^"]+)")?', 'IgnoreCase')
    foreach ($ev in $evBlocks) {
        $dateRaw = $ev.Groups[1].Value.Trim() -replace '（[^）]*）',''
        $ename   = Decode-Html $ev.Groups[2].Value.Trim()
        $prefRaw = $ev.Groups[3].Value.Trim() -replace '\s*·.*$',''
        $eurl    = $ev.Groups[4].Value
        if (-not $eurl) { $eurl = "https://www.24offmap.jp/events/vehicle/classic" }
        $epref = Get-PrefectureFromName "$ename $prefRaw"
        if (-not $epref) { $epref = Get-Prefecture $prefRaw }
        $edate = ""
        if ($dateRaw -match '(\d{1,2})/(\d{1,2})') {
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        if ($ename -and $edate -and ($eurl -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="24offmap" }
            $newUrls += $eurl
        }
    }
    Write-Log "24offmap.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "24offmap.jp エラー: $_"
}

# ===== cos-cam (cos-cam.work) =====
Write-Log "cos-cam.work を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://cos-cam.work/?page_id=969" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # h3 に月/日, テキストに都道府県, a タグにタイトルとリンク
    $blocks = [regex]::Matches($html, '(?s)<h3[^>]*>(.*?)</h3>\s*(.*?)(?=<h3|</section|$)', 'IgnoreCase')
    foreach ($block in $blocks) {
        $dateStr = $block.Groups[1].Value -replace '<[^>]+>',''
        $rest = $block.Groups[2].Value
        $edate = ""
        $yr = (Get-Date).Year
        if ($dateStr -match '(\d{1,2})[^\d]+(\d{1,2})') {
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        $ename = ""
        if ($rest -match '<a[^>]+>([^<]{5,80})</a>') { $ename = Decode-Html $Matches[1] }
        $eurl = ""
        if ($rest -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
        elseif ($rest -match "href='(https?://[^']+)'") { $eurl = $Matches[1] }
        $epref = Get-PrefectureFromName $rest
        if (-not $epref) { $epref = Get-Prefecture $rest }
        if ($ename -and $edate -and $eurl -and ($eurl -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="coscam" }
            $newUrls += $eurl
        }
    }
    Write-Log "cos-cam.work: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "cos-cam.work エラー: $_"
}

# ===== F-DESIGN EVENT (f-designpro.com) =====
Write-Log "f-designpro.com を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://f-designpro.com/event/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # [開催日] ラベルと [会場] ラベルで区切られたブロックを解析
    $blocks = [regex]::Matches($html, '(?s)(?:\[開催日\]|【開催日】)(.*?)(?=\[開催日\]|【開催日】|$)', 'IgnoreCase')
    foreach ($block in $blocks) {
        $btext = $block.Groups[1].Value
        $edate = ""
        if ($btext -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($btext -match '(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        }
        $ename = ""
        if ($btext -match '<(?:h\d|strong|b)[^>]*>([^<]{5,80})</(?:h\d|strong|b)>') { $ename = Decode-Html $Matches[1] }
        elseif ($btext -match '<a[^>]+>([^<]{5,80})</a>') { $ename = Decode-Html $Matches[1] }
        $eurl = ""
        if ($btext -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
        $evenue = ""
        if ($btext -match '(?:\[会場\]|【会場】)\s*([^\[【\r\n]{3,50})') { $evenue = Decode-Html $Matches[1].Trim() }
        $epref = Get-PrefectureFromName "$ename $evenue"
        if (-not $epref) { $epref = Get-Prefecture $btext }
        if ($ename -and $edate -and ($eurl -notin $knownUrls -or -not $eurl)) {
            $linkKey = if ($eurl) { $eurl } else { "fdesign_$ename" }
            if ($linkKey -notin $knownUrls) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url=$(if ($eurl) { $eurl } else { "https://f-designpro.com/event/" }); source="fdesign" }
                if ($eurl) { $newUrls += $eurl }
            }
        }
    }
    Write-Log "f-designpro.com: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "f-designpro.com エラー: $_"
}

# ===== 痛車天国 (itasha-tengoku.yaesu-net.co.jp) =====
Write-Log "itasha-tengoku.yaesu-net.co.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://itasha-tengoku.yaesu-net.co.jp/event-calendar/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # 各イベントブロック: 日付・都道府県・タイトル・リンクが div/li 内に並ぶ
    # パターン: 年月日テキスト → 都道府県テキスト → イベント名 → a href
    $evBlocks = [regex]::Matches($html, '(?s)(\d{4})年(\d{1,2})月(\d{1,2})日[^<]*(?:<[^>]+>[^<]*)*?([都道府県]{2,3})[^\r\n<]*(?:<[^>]+>[^<]*)*?href="(https?://[^"]+)"[^>]*>([^<]{4,80})</a>', 'IgnoreCase')
    foreach ($ev in $evBlocks) {
        $yr = $ev.Groups[1].Value; $mo = $ev.Groups[2].Value; $dy = $ev.Groups[3].Value
        $edate = "$yr-$($mo.PadLeft(2,'0'))-$($dy.PadLeft(2,'0'))"
        $eurl = $ev.Groups[5].Value
        $ename = Decode-Html $ev.Groups[6].Value.Trim()
        if ($eurl -in $knownUrls) { continue }
        $epref = Get-PrefectureFromName "$ename $($ev.Groups[4].Value)"
        if (-not $epref) { $epref = Get-Prefecture $ev.Groups[4].Value }
        if ($ename.Length -ge 4) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="itasha" }
            $newUrls += $eurl
        }
    }
    # フォールバック: シンプルリンク抽出
    if (($discoveredEvents.Count - $before) -eq 0) {
        $links = [regex]::Matches($html, 'href="(https://itasha-tengoku[^"]+)"[^>]*>([^<]{5,80})</a>')
        foreach ($lm in $links) {
            $eurl = $lm.Groups[1].Value
            $ename = Decode-Html $lm.Groups[2].Value.Trim()
            if ($eurl -in $knownUrls -or $ename.Length -lt 5) { continue }
            # URLの周辺から日付を探す
            $pos = $lm.Index
            $ctx = $html.Substring([Math]::Max(0,$pos-300), [Math]::Min(400,$html.Length-$pos))
            $edate = ""
            if ($ctx -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }
            $epref = Get-PrefectureFromName $ctx
            if (-not $epref) { $epref = Get-Prefecture $ctx }
            if ($edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="itasha" }
                $newUrls += $eurl
            }
        }
    }
    Write-Log "itasha-tengoku.yaesu-net.co.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "itasha-tengoku.yaesu-net.co.jp エラー: $_"
}

# ===== みんカラ カレンダー (minkara.carview.co.jp) =====
Write-Log "minkara.carview.co.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://minkara.carview.co.jp/calendar/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    $calIds = [regex]::Matches($html, '/calendar/(\d+)/') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($id in $calIds) {
        $eurl = "https://minkara.carview.co.jp/calendar/$id/"
        if ($eurl -in $knownUrls) { continue }
        try {
            $detail = Invoke-WebRequest -Uri $eurl -UseBasicParsing -TimeoutSec 20
            $dhtml = $detail.Content
            # タイトルは <title> タグから（"告知 - みんカラ | ..." を除去）
            $ename = ""
            if ($dhtml -match '<title>([^<]+)</title>') {
                $ename = Decode-Html ($Matches[1] -replace '\s*[-|].*$','').Trim()
                # "告知" "参加報告" などの接尾語を除去
                $ename = $ename -replace '\s*(告知|参加報告|開催情報)\s*$',''
            }
            $edate = ""
            if ($dhtml -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }
            $evenue = ""
            if ($dhtml -match '(?:会場|開催地)[^\n<]{0,10}[>:\s]+([^\n<]{3,50})') { $evenue = Decode-Html $Matches[1].Trim() }
            $epref = Get-PrefectureFromName "$ename $evenue"
            if (-not $epref -and $evenue) { $epref = Get-Prefecture $evenue }
            if ($ename.Length -ge 4 -and $edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url=$eurl; source="minkara" }
                $newUrls += $eurl
            }
            Start-Sleep -Milliseconds 300
        } catch {}
    }
    Write-Log "minkara.carview.co.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "minkara.carview.co.jp エラー: $_"
}

# ===== モーターゾーン (motorzone.co.jp) =====
Write-Log "motorzone.co.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://motorzone.co.jp/event/eventinfo.html" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    $rows = [regex]::Matches($html, '(?s)<tr[^>]*>(.*?)</tr>', 'IgnoreCase')
    foreach ($row in $rows) {
        $cells = [regex]::Matches($row.Groups[1].Value, '(?s)<td[^>]*>(.*?)</td>', 'IgnoreCase')
        if ($cells.Count -lt 3) { continue }
        $ename = Decode-Html ($cells[0].Groups[1].Value -replace '<[^>]+>','').Trim()
        $evenue = Decode-Html ($cells[1].Groups[1].Value -replace '<[^>]+>','').Trim()
        $dateRaw = Decode-Html ($cells[2].Groups[1].Value -replace '<[^>]+>','').Trim()
        if ($ename.Length -lt 3 -or $dateRaw -notmatch '\d') { continue }
        $edate = ""
        if ($dateRaw -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($dateRaw -match '(\d{1,2})月(\d{1,2})日') {
            $yr = (Get-Date).Year
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        $eurl = ""
        if ($row.Groups[1].Value -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
        $epref = Get-PrefectureFromName "$ename $evenue"
        if (-not $epref) { $epref = Get-Prefecture $evenue }
        $key = "motorzone_$ename"
        if ($ename -and $edate -and ($key -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url=$(if($eurl){$eurl}else{"https://motorzone.co.jp/event/eventinfo.html"}); source="motorzone" }
            $newUrls += $key
        }
    }
    Write-Log "motorzone.co.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "motorzone.co.jp エラー: $_"
}

# ===== 展サポ 自動車展示会 (kbinfo.co.jp) =====
Write-Log "kbinfo.co.jp (展サポ) を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://www.kbinfo.co.jp/tensapo/column/1350164_14101.html" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    $rows = [regex]::Matches($html, '(?s)<tr[^>]*>(.*?)</tr>', 'IgnoreCase')
    foreach ($row in $rows) {
        $cells = [regex]::Matches($row.Groups[1].Value, '(?s)<td[^>]*>(.*?)</td>', 'IgnoreCase')
        if ($cells.Count -lt 3) { continue }
        $ename = Decode-Html ($cells[0].Groups[1].Value -replace '<[^>]+>','').Trim()
        $evenue = Decode-Html ($cells[1].Groups[1].Value -replace '<[^>]+>','').Trim()
        $dateRaw = Decode-Html ($cells[2].Groups[1].Value -replace '<[^>]+>','').Trim()
        if ($ename.Length -lt 3 -or $dateRaw -notmatch '\d') { continue }
        $edate = ""
        if ($dateRaw -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($dateRaw -match '(\d{1,2})月(\d{1,2})日') {
            $yr = (Get-Date).Year
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        $epref = Get-PrefectureFromName "$ename $evenue"
        if (-not $epref) { $epref = Get-Prefecture $evenue }
        $key = "tensapo_$ename"
        if ($ename -and $edate -and ($key -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url="https://www.kbinfo.co.jp/tensapo/column/1350164_14101.html"; source="tensapo" }
            $newUrls += $key
        }
    }
    Write-Log "kbinfo.co.jp (展サポ): $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "kbinfo.co.jp エラー: $_"
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
