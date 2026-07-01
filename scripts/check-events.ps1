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
        "横浜|神奈川|川崎|湘南|箱根|大観山|厚木|相模" = "神奈川県"
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

# ===== mach5.jp (areaevent - 全都道府県・今日以降) =====
Write-Log "mach5.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://www.mach5.jp/eventmania/areaevent.php?afterToday&pref=null" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # 各イベントは id="title_date" ブロック内: <a href="URL">タイトル</a> + YYYY/M/D
    $evBlocks = [regex]::Matches($html, '(?s)id="title_date">(.*?)(?=id="title_date"|</table|$)', 'IgnoreCase')
    foreach ($ev in $evBlocks) {
        $b = $ev.Groups[1].Value
        $ename = ""; $eurl = ""
        if ($b -match '<a[^>]+href="(https?://[^"]+)"[^>]*>([^<]{3,80})</a>') {
            $eurl = $Matches[1]; $ename = Decode-Html $Matches[2]
        }
        $edate = ""
        if ($b -match '(\d{4})/(\d{1,2})/(\d{1,2})') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        }
        $plain = ($b -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $epref = Get-PrefectureFromName $plain
        if (-not $epref) { $epref = Get-Prefecture $plain }
        if ($ename -and $edate -and $eurl -and ($eurl -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="mach5" }
            $newUrls += $eurl
        }
    }
    Write-Log "mach5.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "mach5.jp エラー: $_"
}

# ===== RACRY (racry.jp) =====
Write-Log "racry.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://racry.jp/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # 商品詳細ページ URL: /products/detail/N — リストページから抽出
    $prodBlocks = [regex]::Matches($html, '(?s)product__items--pic">(.*?)(?=product__items--pic|</main|$)', 'IgnoreCase')
    foreach ($pb in $prodBlocks) {
        $b = $pb.Groups[1].Value
        $eurl = if ($b -match 'href="(https://racry\.jp/products/detail/\d+)"') { $Matches[1] } else { "" }
        if (-not $eurl -or $eurl -in $knownUrls) { continue }
        $plain = ($b -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $edate = ""
        if ($plain -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        }
        try {
            $detail = Invoke-WebRequest -Uri $eurl -UseBasicParsing -TimeoutSec 15
            $dhtml = $detail.Content
            $ename = ""
            if ($dhtml -match '<title>([^|｜<]{3,80})') { $ename = Decode-Html ($Matches[1].Trim() -replace '[|｜].*$','').Trim() }
            if (-not $ename -and $dhtml -match '<h1[^>]*>([^<]+)</h1>') { $ename = Decode-Html $Matches[1].Trim() }
            if (-not $edate -and $dhtml -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }
            $epref = Get-PrefectureFromName "$ename $plain"
            if (-not $epref) { $epref = Get-Prefecture "$plain $dhtml" }
            if ($ename.Length -ge 3 -and $edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="racry" }
                $newUrls += $eurl
            }
        } catch {}
        Start-Sleep -Milliseconds 300
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
    $yr = (Get-Date).Year
    # イベントカード: <article> または class="event-card" の div
    $cards = [regex]::Matches($html, '(?s)<article[^>]*>(.*?)</article>', 'IgnoreCase')
    if ($cards.Count -eq 0) {
        $cards = [regex]::Matches($html, '(?s)<div[^>]*class="[^"]*event[^"]*"[^>]*>(.*?)</div>', 'IgnoreCase')
    }
    foreach ($card in $cards) {
        $inner = $card.Groups[1].Value
        $ename = if ($inner -match '<h3[^>]*>([^<]+)</h3>') { Decode-Html $Matches[1].Trim() }
                 elseif ($inner -match '<h2[^>]*>([^<]+)</h2>') { Decode-Html $Matches[1].Trim() }
                 else { "" }
        if (-not $ename -or $ename.Length -lt 3) { continue }
        $plain = ($inner -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $edate = ""
        # "1月 · 9" or "1月 · 9-11" format
        if ($plain -match '(\d+)月\s*[·・·]\s*(\d+)') {
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        } elseif ($plain -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        }
        $eurl = if ($inner -match 'href="(https?://[^"]+)"') { $Matches[1] } else { "https://americarsandtrucks.com/jp/events/" }
        $epref = Get-PrefectureFromName "$ename $plain"
        if (-not $epref) { $epref = Get-Prefecture $plain }
        $key = "americars_$ename"
        if ($ename -and $edate -and ($key -notin $knownUrls)) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="americars" }
            $newUrls += $key
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
    $yr_now = (Get-Date).Year; $mo_now = (Get-Date).Month
    # 月ブロック: id="202607" など (年+月の6桁)
    $monthBlocks = [regex]::Matches($html, '(?s)id="(\d{4})(\d{2})"[^>]*>(.*?)(?=id="\d{6}"|</body|$)', 'IgnoreCase')
    foreach ($mb in $monthBlocks) {
        $yr = $mb.Groups[1].Value; $mo = $mb.Groups[2].Value
        if ([int]$yr -lt $yr_now -or ([int]$yr -eq $yr_now -and [int]$mo -lt $mo_now)) { continue }
        $mbContent = $mb.Groups[3].Value
        # eventid リンク: href="...eventid=NNN..."
        $evLinks = [regex]::Matches($mbContent, 'href="[^"]*eventid=(\d+)[^"]*"[^>]*>([^<]{3,60})</a>', 'IgnoreCase')
        foreach ($ev in $evLinks) {
            $evid = $ev.Groups[1].Value
            $ename = Decode-Html $ev.Groups[2].Value.Trim()
            $evurl = "https://cos-cam.work/?page_id=2&eventid=$evid"
            if ($evurl -in $knownUrls) { continue }
            # リンク手前のテキストから日付 (M / D) を取得
            $before_text = $mbContent.Substring(0, [Math]::Min($ev.Index + $ev.Length, $mbContent.Length))
            $plain_before = ($before_text -replace '<[^>]+>',' ' -replace '\s+',' ')
            $dy = "1"
            if ($plain_before -match '(\d{1,2})\s*/\s*(\d{1,2})\s*日') { $dy = $Matches[2] }
            elseif ($plain_before -match '(\d{1,2})\s*/\s*(\d{1,2})') { $dy = $Matches[2] }
            $edate = "$yr-$($mo.PadLeft(2,'0'))-$($dy.PadLeft(2,'0'))"
            $epref = Get-PrefectureFromName $ename
            if (-not $epref) { $epref = Get-Prefecture $plain_before }
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$evurl; source="coscam" }
            $newUrls += $evurl
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
    $yr = (Get-Date).Year; $today_date = (Get-Date).Date
    # スクリプト・スタイル除去後にプレーンテキスト化
    $stripped = $html -replace '(?s)<style[^>]*>.*?</style>','' -replace '(?s)<script[^>]*>.*?</script>',''
    $plain = ($stripped -replace '<[^>]+>',' ' -replace '[ \t]+',' ')
    # M/D[区切り]イベント名[スペース]会場名 の行形式を解析
    # 例: "7/5 第13回箱根REMT2026 大観山スカイラウンジ"
    $lines = $plain -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{1,2}/\d{1,2}' }
    foreach ($line in $lines) {
        if ($line -match '^(\d{1,2})/(\d{1,2})[-–\s]+(.+)$') {
            $mo = $Matches[1]; $dy = $Matches[2]; $rest = $Matches[3].Trim()
        } elseif ($line -match '^(\d{1,2})/(\d{1,2})\s+(.+)$') {
            $mo = $Matches[1]; $dy = $Matches[2]; $rest = $Matches[3].Trim()
        } else { continue }
        try {
            $edate_obj = [datetime]"$yr-$($mo.PadLeft(2,'0'))-$($dy.PadLeft(2,'0'))"
            if ($edate_obj -lt $today_date) { continue }
            $edate = $edate_obj.ToString("yyyy-MM-dd")
        } catch { continue }
        # F-DESIGN出展 などの注釈を除去
        $rest = ($rest -replace '\s*F-DESIGN.*$','').Trim()
        # イベント名と会場名を分割 (スペース2個以上 or 最後のスペース区切り)
        $ename = ""; $evenue = ""
        if ($rest -match '^(.{4,50})\s{2,}(.{3,40})$') {
            $ename = $Matches[1].Trim(); $evenue = $Matches[2].Trim()
        } elseif ($rest -match '^([^\s]{4,}(?:\s[^\s]{1,6}){0,3})\s+([^\s].{2,})$') {
            $ename = $Matches[1].Trim(); $evenue = $Matches[2].Trim()
        } else { $ename = $rest.Trim() }
        $key = "fdesign_${yr}_${mo}_${dy}_" + ($ename -replace '[^\w\p{L}]','')
        if ($ename.Length -ge 3 -and ($key -notin $knownUrls)) {
            $epref = Get-PrefectureFromName "$ename $evenue"
            if (-not $epref) { $epref = Get-Prefecture "$ename $evenue" }
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url="https://f-designpro.com/event/"; source="fdesign" }
            $newUrls += $key
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
    # <a href="URL">内テキスト</a> ブロック — 内テキストに年月日・都道府県・イベント名が含まれる
    # 例: "2026年 7月5日 （日） 埼玉県 車ぷれ 2026年7月5日（日） 久喜市役所鷲宮行政センター駐車場 ..."
    $aBlocks = [regex]::Matches($html, '(?s)<a\s+href="(https?://[^"]+)"[^>]*>(.*?)</a>', 'IgnoreCase')
    foreach ($ab in $aBlocks) {
        $inner = $ab.Groups[2].Value
        if ($inner -notmatch '\d{4}年') { continue }
        $eurl = $ab.Groups[1].Value
        if ($eurl -in $knownUrls) { continue }
        $plain = ($inner -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $edate = ""
        if ($plain -match '(\d{4})年\s*(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        }
        $ename = ""
        # パターン: ） [都道府県] [イベント名] YYYY年 または ） [イベント名] YYYY年
        if ($plain -match '[）)]\s+([^\s]{2,5}[県都道府])\s+(.{3,60}?)\s+\d{4}年') {
            $epref_text = $Matches[1]; $ename = $Matches[2].Trim()
            $epref = Get-PrefectureFromName "$ename $epref_text"
            if (-not $epref) { $epref = Get-Prefecture $epref_text }
        } elseif ($plain -match '[）)]\s+(.{4,60}?)\s+\d{4}年') {
            $ename = $Matches[1].Trim()
            $epref = Get-PrefectureFromName $plain
            if (-not $epref) { $epref = Get-Prefecture $plain }
        }
        if ($ename.Length -ge 3 -and $edate) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$eurl; source="itasha" }
            $newUrls += $eurl
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
    $today_mz = (Get-Date).Date
    # 見出し + [開催日] ブロックのペアを取得
    # 構造: <h2/h3/strong>イベント名</h2> ... [ 開催日 ] YYYY年M月D日 [ 会場 ] 会場名 [ WEBサイト ] URL
    $evBlocks = [regex]::Matches($html, '(?s)(<(?:h[2-4]|strong)[^>]*>([^<]{3,60})</(?:h[2-4]|strong)>)\s*(?:<[^>]*>)*\s*\[\s*開催日\s*\](.*?)(?=<(?:h[2-4]|strong)|\z)', 'IgnoreCase')
    foreach ($block in $evBlocks) {
        $ename = Decode-Html $block.Groups[2].Value.Trim()
        if ($ename -match 'テンプレート|イベント名' -or $ename.Length -lt 3) { continue }
        $afterText = $block.Groups[3].Value
        $plain = ($afterText -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $edate = ""
        if ($plain -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $yr=$Matches[1]; $mo=$Matches[2]; $dy=$Matches[3]
            $edate = "$yr-$($mo.PadLeft(2,'0'))-$($dy.PadLeft(2,'0'))"
            try { if ([datetime]$edate -lt $today_mz) { continue } } catch { continue }
        } else { continue }
        $evenue = ""
        if ($plain -match '\[\s*会場\s*\]\s*([^\[]{3,60}?)(?=\s*\[|\s*$)') { $evenue = $Matches[1].Trim() }
        $eurl = "https://motorzone.co.jp/event/eventinfo.html"
        if ($afterText -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
        $key = "motorzone_$ename"
        if ($key -notin $knownUrls) {
            $epref = Get-PrefectureFromName "$ename $evenue"
            if (-not $epref) { $epref = Get-Prefecture "$ename $evenue" }
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url=$eurl; source="motorzone" }
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
    $today_kb = (Get-Date).Date
    $rows = [regex]::Matches($html, '(?s)<tr[^>]*>(.*?)</tr>', 'IgnoreCase')
    foreach ($row in $rows) {
        $rowContent = $row.Groups[1].Value
        # 展示会名は <th> タグに格納されている
        $thCells = [regex]::Matches($rowContent, '(?s)<th[^>]*>(.*?)</th>', 'IgnoreCase')
        $tdCells = [regex]::Matches($rowContent, '(?s)<td[^>]*>(.*?)</td>', 'IgnoreCase')
        if ($tdCells.Count -lt 2) { continue }
        $ename = ""
        if ($thCells.Count -gt 0) {
            $ename = Decode-Html ($thCells[0].Groups[1].Value -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        }
        if ($ename.Length -lt 3) { continue }
        # td[0]=会場・都市, td[1]=日程
        $evenue = Decode-Html ($tdCells[0].Groups[1].Value -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $dateRaw = Decode-Html ($tdCells[1].Groups[1].Value -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        if ($dateRaw -notmatch '\d') { continue }
        $edate = ""
        if ($dateRaw -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($dateRaw -match '(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})') {
            $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        } elseif ($dateRaw -match '(\d{1,2})月(\d{1,2})日') {
            $yr = (Get-Date).Year
            $edate = "$yr-$($Matches[1].PadLeft(2,'0'))-$($Matches[2].PadLeft(2,'0'))"
        }
        if (-not $edate) { continue }
        try { if ([datetime]$edate -lt $today_kb) { continue } } catch { continue }
        $epref = Get-PrefectureFromName "$ename $evenue"
        if (-not $epref) { $epref = Get-Prefecture $evenue }
        $key = "tensapo_$ename"
        if ($key -notin $knownUrls) {
            $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$evenue; url="https://www.kbinfo.co.jp/tensapo/column/1350164_14101.html"; source="tensapo" }
            $newUrls += $key
        }
    }
    Write-Log "kbinfo.co.jp (展サポ): $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "kbinfo.co.jp エラー: $_"
}

# ===== jmty.jp カーイベント =====
Write-Log "jmty.jp を取得中..."
try {
    $searches = @("カーミーティング", "スーパーカー", "車イベント")
    $jmtyBefore = $discoveredEvents.Count
    $jmtySeen = @()
    foreach ($kw in $searches) {
        $kwenc = [uri]::EscapeUriString($kw)
        $res = Invoke-WebRequest -Uri "https://jmty.jp/all/eve-kw-$kwenc" -UseBasicParsing -TimeoutSec 30
        $html = $res.Content
        # 記事リンク: /all/sale/article-N
        $links = [regex]::Matches($html, 'href="(/all/[^"]+article-\d+[^"]*)"') |
                 ForEach-Object { "https://jmty.jp" + $_.Groups[1].Value -replace '\?.*$','' } |
                 Sort-Object -Unique | Where-Object { $_ -notin $knownUrls -and $_ -notin $jmtySeen }
        foreach ($link in ($links | Select-Object -First 10)) {
            $jmtySeen += $link
            try {
                $detail = Invoke-WebRequest -Uri $link -UseBasicParsing -TimeoutSec 15
                $dhtml = $detail.Content
                $ename = ""
                if ($dhtml -match '<title>([^|｜<]{4,80})') { $ename = Decode-Html ($Matches[1].Trim() -replace '[|｜].*$','').Trim() }
                $edate = ""
                if ($dhtml -match '開催日[^：:]*[：:]\s*(\d{4})年(\d{1,2})月(\d{1,2})日') {
                    $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
                } elseif ($dhtml -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                    $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
                }
                $epref = Get-PrefectureFromName $ename
                if (-not $epref) { $epref = Get-Prefecture $dhtml }
                if ($ename.Length -ge 4 -and $edate) {
                    $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=""; url=$link; source="jmty" }
                    $newUrls += $link
                }
                Start-Sleep -Milliseconds 300
            } catch {}
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Log "jmty.jp: $($discoveredEvents.Count - $jmtyBefore) 件の新規候補"
} catch {
    Write-Log "jmty.jp エラー: $_"
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
