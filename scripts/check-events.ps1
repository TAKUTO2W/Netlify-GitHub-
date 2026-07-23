# ===================================================
# CARJAM イベント自動収集スクリプト
# 対象: mach5.jp / dupcar-event.com
# ===================================================

. "$PSScriptRoot\config.ps1"
# 詳細ページから会場・住所・主催などを抽出する共通処理（enrich-event-details.ps1 と共用）
. "$PSScriptRoot\lib-event-detail.ps1"

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
    # 16進数参照 &#x27; など（これが漏れていて、イベント名に &#x27; が残っていた）
    $str = [regex]::Replace($str, '&#[xX]([0-9a-fA-F]+);', { [char][Convert]::ToInt32($args[0].Groups[1].Value, 16) })
    # &amp;#x27; のように二重エスケープされている場合にも対応
    $str = [regex]::Replace($str, '&#[xX]([0-9a-fA-F]+);', { [char][Convert]::ToInt32($args[0].Groups[1].Value, 16) })
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
# ② イベント名・ソースからカテゴリを自動判定
function Get-CategoryFromName($name, $source) {
    if ($name -match 'サーキット|ジムカーナ|タイムアタック|レース|RACE|耐久|Rally|ラリー|GP|Formula|フォーミュラ|Sprint|SuperGT|SUPER GT|GTi') { return 'レース' }
    if ($name -match 'ショー|SHOW|モーターショー|オートモーティブ|カーショー|CarShow|展示会|Car Show|AutoShow') { return 'モーターショー' }
    if ($name -match 'クラシック|旧車|ヴィンテージ|CLASSIC|VINTAGE|昭和|旧車會|バイク|族車') { return 'クラシックカー' }
    if ($name -match 'カスタム|チューニング|Custom|Tuning|痛車|コスプレ|ITASHA|ドレスアップ|Dress') { return 'カスタム・チューニング' }
    if ($name -match 'オフロード|SUV|4WD|四駆|ジムニー|ランクル|ランドクルーザー|ジープ|オフ会') { return 'オフロード・SUV' }
    if ($source -eq 'tensapo') { return 'モーターショー' }
    if ($source -eq 'coscam' -or $source -eq 'itasha') { return 'カスタム・チューニング' }
    if ($source -eq 'racry') { return 'カスタム・チューニング' }
    return 'カーミーティング'
}

function Get-PrefectureFromName($name) {
    $map = [ordered]@{
        "北海道|ふらの|富良野|EZO|蝦夷|札幌|函館|旭川" = "北海道"
        "青森|弘前|八戸" = "青森県"
        "岩手|盛岡" = "岩手県"
        "宮城|仙台|SUGO|スポーツランドSUGO|スポーツランド菅生" = "宮城県"
        "秋田" = "秋田県"
        "山形|やまがた" = "山形県"
        "福島" = "福島県"
        "茨城|水戸|つくば|筑波サーキット|筑波" = "茨城県"
        "栃木|宇都宮|日光|もてぎ|ツインリンク|Twin Ring|ツインリンクもてぎ" = "栃木県"
        "群馬|前橋|高崎|伊勢崎" = "群馬県"
        "埼玉|さいたま|浦和|大宮" = "埼玉県"
        "千葉|幕張|柏|袖ヶ浦|茂原|袖ケ浦|SODEGAURA|幕張メッセ" = "千葉県"
        "東京|品川|渋谷|新宿|秋葉原|羽田|お台場|豊洲|有明|青海|東京ビッグサイト|東京国際展示場" = "東京都"
        "横浜|神奈川|川崎|湘南|箱根|大観山|厚木|相模|大黒PA|大黒ふ頭|みなとみらい|海老名" = "神奈川県"
        "新潟|国上|長岡|SORAIRO" = "新潟県"
        "富山" = "富山県"
        "金沢|石川|能登|北陸" = "石川県"
        "福井" = "福井県"
        "山梨|甲府|富士吉田" = "山梨県"
        "長野|信州|北信越|松本|諏訪" = "長野県"
        "岐阜|可児" = "岐阜県"
        "静岡|浜松|富士|富士スピードウェイ|FISCO|富士スピ|FSW" = "静岡県"
        "名古屋|愛知|豊田|岡崎" = "愛知県"
        "三重|鈴鹿|伊勢|鈴鹿サーキット" = "三重県"
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
        "福岡|博多|北九州|門司|小倉" = "福岡県"
        "佐賀" = "佐賀県"
        "長崎" = "長崎県"
        "熊本|肥後" = "熊本県"
        "大分|オートポリス" = "大分県"
        "宮崎" = "宮崎県"
        "鹿児島|KAGOSHIMA" = "鹿児島県"
        "沖縄|OKINAWA|那覇" = "沖縄県"
    }
    foreach ($pattern in $map.Keys) {
        if ($name -match $pattern) { return $map[$pattern] }
    }
    return ""
}

# 都道府県を「イベント名を最優先・文脈は最小限だけ」で推定する。
#
# 【2026-07-20の事故】ページ全体のテキストを Get-PrefectureFromName に渡していたため、
# サイトのナビメニューに含まれる「北海道」を拾って無関係なイベントが北海道になっていた。
# 上の $map は [ordered]（順番固定）で北海道が先頭なので、最初にヒットして即returnしてしまう。
# careventnavi は 32件中19件（59%）が誤って北海道になっていた。
#
# 対策: ①名前だけで判定 → ②開催地ラベルの直後40文字だけ見る → ③分からなければ空。
# 誤った都道府県より「未定」の方がマシ、という方針。
function Get-PrefectureScoped($name, $context) {
    # ① イベント名だけで判定できるならそれが最も確実
    $p = Get-PrefectureFromName $name
    if ($p) { return $p }

    # ② 開催地・会場ラベルの直後だけを見る（ナビメニューを拾わないため）
    if ($context) {
        $labels = '開催場所|開催地|開催県|会場|場所|住所|所在地|アクセス'
        foreach ($m in [regex]::Matches($context, "($labels)[^\p{L}\p{N}]{0,6}(.{0,40})")) {
            $p = Get-PrefectureFromName $m.Groups[2].Value
            if ($p) { return $p }
        }
    }

    # ③ 分からないものは空（呼び出し元で「未定」になる）
    return ""
}

# jmty.jp は URL に都道府県がローマ字で入っている（https://jmty.jp/{pref}/eve-.../article-...）。
# 本文を読むより確実なので、URLから引く。
$JMTY_PREF = @{
    hokkaido="北海道"; aomori="青森県"; iwate="岩手県"; miyagi="宮城県"; akita="秋田県"
    yamagata="山形県"; fukushima="福島県"; ibaraki="茨城県"; tochigi="栃木県"; gunma="群馬県"
    saitama="埼玉県"; chiba="千葉県"; tokyo="東京都"; kanagawa="神奈川県"; niigata="新潟県"
    toyama="富山県"; ishikawa="石川県"; fukui="福井県"; yamanashi="山梨県"; nagano="長野県"
    gifu="岐阜県"; shizuoka="静岡県"; aichi="愛知県"; mie="三重県"; shiga="滋賀県"
    kyoto="京都府"; osaka="大阪府"; hyogo="兵庫県"; nara="奈良県"; wakayama="和歌山県"
    tottori="鳥取県"; shimane="島根県"; okayama="岡山県"; hiroshima="広島県"; yamaguchi="山口県"
    tokushima="徳島県"; kagawa="香川県"; ehime="愛媛県"; kochi="高知県"; fukuoka="福岡県"
    saga="佐賀県"; nagasaki="長崎県"; kumamoto="熊本県"; oita="大分県"; miyazaki="宮崎県"
    kagoshima="鹿児島県"; okinawa="沖縄県"
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
# racry は全件を一覧ページ（/products/list?pageno=N）から辿る。2026-07-21 に
# 「トップページ分だけ」→「今後開催分を漏れなく」に拡張した。
#
# 一覧ページには日付が無く、過去イベント（2024年など）も商品として残り続けるため、
# 詳細ページを開いて開催日を確認し、今日以降のものだけ採用する。
# 過去と判定したURLも $newUrls（既知リスト）に入れて、翌日から再取得しないようにする
# （過去は過去のまま変わらないので安全。これで2日目以降は新規商品だけ見に行く）。
#
# 利用規約（/help/agreement）は知的財産権の一般条項のみで、無断転載・複製の
# 明示的な禁止は無いことを確認済み（2026-07-21）。事実データの抽出＋出典リンクで運用。
Write-Log "racry.jp を取得中..."
try {
    $before = $discoveredEvents.Count
    $racryUrls = New-Object System.Collections.Generic.List[string]
    $seenRacry = @{}
    $prevSig = ""
    # 一覧を最大30ページ辿ってイベントURLを全部集める
    for ($pg = 1; $pg -le 30; $pg++) {
        try {
            $lst = Invoke-WebRequest -Uri "https://racry.jp/products/list?pageno=$pg" -UseBasicParsing -TimeoutSec 20
        } catch { break }
        $pageUrls = @([regex]::Matches($lst.Content, 'https://racry\.jp/products/detail/\d+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        $sig = ($pageUrls -join ',')
        # 空 or 前ページと同じ内容（＝ページ番号超過で先頭に戻った）＝終端
        if ($pageUrls.Count -eq 0 -or $sig -eq $prevSig) { break }
        foreach ($u in $pageUrls) { if (-not $seenRacry.ContainsKey($u)) { $seenRacry[$u] = $true; $racryUrls.Add($u) } }
        $prevSig = $sig
        Start-Sleep -Milliseconds 300
    }
    Write-Log "racry.jp: 一覧から $($racryUrls.Count) 件のイベントURLを収集"

    $today_racry = (Get-Date).Date
    foreach ($eurl in $racryUrls) {
        if ($eurl -in $knownUrls) { continue }
        try {
            $detail = Invoke-WebRequest -Uri $eurl -UseBasicParsing -TimeoutSec 15
            $dhtml = $detail.Content
            $ename = ""
            if ($dhtml -match '<title>([^|｜<]{3,80})') { $ename = Decode-Html ($Matches[1].Trim() -replace '[|｜].*$','').Trim() }
            if (-not $ename -and $dhtml -match '<h1[^>]*>([^<]+)</h1>') { $ename = Decode-Html $Matches[1].Trim() }
            $edate = ""
            if ($dhtml -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
                $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
            }

            # 過去イベント・日付不明はサイトに載せない。ただし既知URLに入れて翌日から再取得しない
            $isFuture = $false
            if ($edate) { try { $isFuture = ([datetime]$edate -ge $today_racry) } catch {} }
            if (-not $isFuture) { $newUrls += $eurl; Start-Sleep -Milliseconds 300; continue }

            $epref = Get-PrefectureScoped $ename ""
            # 詳細ページから会場等を拾う。会場に県名が入っていればそれを優先する
            $det = Get-EventDetailFields $dhtml
            $pFromPlace = Get-PrefectureFromPlace "$($det.venue) $($det.address)" $PREF_NAMES
            if ($pFromPlace) { $epref = $pFromPlace }
            if ($ename.Length -ge 3 -and $edate) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$det.venue; url=$eurl; source="racry"; detail=$det }
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
            # このカレンダーは「日付 / 曜日 / 都道府県 / イベント名」の順に並んでいるので、
            # リンクの直前に出てくる県が正しい。
            # ブロック全体を Get-Prefecture に渡すと、その月の別イベントの県を拾ってしまう
            # （2026-07-20 に17件中10件が誤っていた原因）。
            $epref = Get-PrefectureNearest $plain_before $PREFS 300
            if (-not $epref) { $epref = Get-PrefectureFromName $ename }
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
    # 構造: <h4>イベント名</h4><p class="c-body">[ 開催日 ] YYYY年M月D日...</p>
    $evBlocks = [regex]::Matches($html, '(?s)<h4[^>]*>(.*?)</h4>\s*<p[^>]*class="[^"]*c-body[^"]*"[^>]*>(.*?)</p>', 'IgnoreCase')
    foreach ($block in $evBlocks) {
        $ename = Decode-Html ($block.Groups[1].Value -replace '<[^>]+>','').Trim()
        if ($ename -match 'テンプレート|イベント名' -or $ename.Length -lt 3) { continue }
        $body = $block.Groups[2].Value -replace '<br\s*/?>', "`n"
        $plain = ($body -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()
        $edate = ""
        if ($plain -match '(\d{4})年(\d{1,2})月(\d{1,2})日') {
            $yr=$Matches[1]; $mo=$Matches[2]; $dy=$Matches[3]
            $edate = "$yr-$($mo.PadLeft(2,'0'))-$($dy.PadLeft(2,'0'))"
            try { if ([datetime]$edate -lt $today_mz) { continue } } catch { continue }
        } else { continue }
        # 会場: [ 会場 ] venue または日付の次の行
        $evenue = ""
        if ($plain -match '\[\s*会場\s*\]\s*([^\[]{3,60}?)(?=\s*\[|\s*$)') {
            $evenue = $Matches[1].Trim()
        } elseif ($plain -match '\d{4}年[^\n]+\n([^\n]{3,50})') {
            $evenue = $Matches[1].Trim()
        }
        $eurl = "https://motorzone.co.jp/event/eventinfo.html"
        if ($body -match 'href="(https?://[^"]+)"') { $eurl = $Matches[1] }
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

# ===== careventnavi.jp =====
Write-Log "careventnavi.jp を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://careventnavi.jp/event-list/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    # 記事リンクを収集
    $links = [regex]::Matches($html, 'href="(https://careventnavi\.jp/[a-z0-9][a-z0-9\-]{4,80}/)"') |
             ForEach-Object { $_.Groups[1].Value } |
             Where-Object { $_ -notmatch 'category|author|page|tag|feed|about|contact|calendar|privacy|event-submission|event-support|event-list|%e3' } |
             Sort-Object -Unique
    foreach ($link in $links) {
        if ($link -in $knownUrls) { continue }
        try {
            $detail = Invoke-WebRequest -Uri $link -UseBasicParsing -TimeoutSec 15
            $dhtml = $detail.Content
            # タイトル: <title>イベント名｜... | Car Event NAVI</title>
            $ename = ""
            if ($dhtml -match '<title>([^|｜<]+)') {
                $ename = Decode-Html ($Matches[1].Trim() -replace '[|｜].*$','').Trim()
            }
            $dplain = ($dhtml -replace '<[^>]+>',' ' -replace '\s+',' ')
            # 日付: 最初の YYYY年M月D日 (公開日を除く2件目を優先)
            $dateMatches = [regex]::Matches($dplain, '(\d{4})年(\d{1,2})月(\d{1,2})日')
            $edate = ""
            foreach ($dm in ($dateMatches | Select-Object -Skip 0)) {
                $dobj = "$($dm.Groups[1].Value)-$($dm.Groups[2].Value.PadLeft(2,'0'))-$($dm.Groups[3].Value.PadLeft(2,'0'))"
                try {
                    if ([datetime]$dobj -ge $today_mz) { $edate = $dobj; break }
                } catch {}
            }
            if (-not $edate) { continue }
            # ページ全体($dplain)を渡さない。2026-07-20にここが原因で32件中19件が誤って北海道になった
            $epref = Get-PrefectureScoped $ename $dplain
            # 詳細ページに会場・住所・主催・時間・料金が載っているので拾う
            $det = Get-EventDetailFields $dhtml
            $pFromPlace = Get-PrefectureFromPlace "$($det.venue) $($det.address)" $PREF_NAMES
            if ($pFromPlace) { $epref = $pFromPlace }
            if ($ename.Length -ge 4) {
                $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$det.venue; url=$link; source="careventnavi"; detail=$det }
                $newUrls += $link
            }
            Start-Sleep -Milliseconds 400
        } catch {}
    }
    Write-Log "careventnavi.jp: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "careventnavi.jp エラー: $_"
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
        $res = Invoke-WebRequest -Uri "https://jmty.jp/all/eve?keyword=$kwenc" -UseBasicParsing -TimeoutSec 30
        $html = $res.Content
        # 記事リンク（絶対URL・都道府県別パス・英数字ID）: https://jmty.jp/{pref}/eve-xxx/article-XXXX
        $links = [regex]::Matches($html, 'href="(https://jmty\.jp/[a-z0-9]+/eve[^"/]*/article-[0-9a-z]+)"') |
                 ForEach-Object { $_.Groups[1].Value -replace '\?.*$','' } |
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
                # URLのローマ字（https://jmty.jp/{pref}/...）が最も確実。次点で名前・開催地ラベル
                $epref = ""
                if ($link -match 'https://jmty\.jp/([a-z]+)/') { $epref = $JMTY_PREF[$Matches[1]] }
                if (-not $epref) { $epref = Get-PrefectureScoped $ename $dhtml }
                $det = Get-EventDetailFields $dhtml
                if ($ename.Length -ge 4 -and $edate) {
                    $discoveredEvents += [PSCustomObject]@{ name=$ename; date=$edate; prefecture=$epref; venue=$det.venue; url=$link; source="jmty"; detail=$det }
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

# ===== JMRC四国（Googleカレンダーの公開ICSフィード） =====
# 四国4県のモータースポーツ競技会。HTMLではなくICS（iCalendar）なので解析が確実。
# LOCATION に住所が入っているため、会場と都道府県が最初から正確に取れる。
# 2026-07-20 追加。徳島・高知・愛媛の空白を埋めるのが目的。
Write-Log "JMRC四国(ICS) を取得中..."
try {
    $icsUrl = "https://calendar.google.com/calendar/ical/g6nf29eiu125m7ormpiqedpbj8%40group.calendar.google.com/public/basic.ics"
    $res = Invoke-WebRequest -Uri $icsUrl -UseBasicParsing -TimeoutSec 30
    $ics = [Text.Encoding]::UTF8.GetString($res.RawContentStream.ToArray())
    $ics = $ics -replace "`r`n ", ""      # ICSの行折り返しを戻す
    $before = $discoveredEvents.Count
    $todayIcs = (Get-Date).ToString('yyyyMMdd')

    foreach ($m in [regex]::Matches($ics, '(?s)BEGIN:VEVENT(.*?)END:VEVENT')) {
        $b = $m.Groups[1].Value
        if ($b -notmatch 'DTSTART[^:]*:(\d{8})') { continue }
        $dt = $Matches[1]
        if ($dt -lt $todayIcs) { continue }

        $sum = if ($b -match 'SUMMARY:(.+)') { ($Matches[1] -replace '\\,', ',' -replace '\\;', ';').Trim() } else { "" }
        if (-not $sum) { continue }

        # 一般来場者向けでないものは除外する。
        # このカレンダーには主催者内部の会議や、参加資格を取るための講習会も入っている。
        # サイトに載せると「行けないイベント」が並ぶことになるので入れない。
        if ($sum -match '総会|運営委員会|理事会|会議|打合せ|打ち合わせ|講習会|説明会|表彰式|セミナー') { continue }

        $loc = if ($b -match 'LOCATION:(.+)') { ($Matches[1] -replace '\\,', ',' -replace '\\n', ' ').Trim() } else { "" }
        $epref = ""
        foreach ($p in $PREFS) { if ($loc -match [regex]::Escape($p)) { $epref = $p; break } }

        # 先方のカレンダーには会場の登録ミスがある。
        # 例: 「【全日本ラリー】福島伊達」の LOCATION が「愛知県」になっている。
        # イベント名から読める県と会場の県が食い違う場合は、どちらが正しいか判断できないので
        # 「未定」にする（誤った県を断言するより良い）。
        $prefFromName = Get-PrefectureFromName $sum
        if ($epref -and $prefFromName -and $prefFromName -ne $epref) {
            Write-Log "JMRC四国: 県が不一致のため未定にした「$sum」(名前=$prefFromName / 会場=$epref)"
            $epref = ""
        }

        # LOCATION の先頭が会場名。ただし「高知県」のように県名しか無い場合は会場として扱わない
        $evenue = ($loc -split ',')[0].Trim()
        $evenue = ($evenue -replace '〒\d{3}-?\d{4}', '').Trim()
        if ($PREFS -contains $evenue -or $evenue -eq '日本') { $evenue = "" }

        $edate = "$($dt.Substring(0,4))-$($dt.Substring(4,2))-$($dt.Substring(6,2))"

        # このカレンダーは1つのサイトを指すので、URLだけでは重複判定できない。
        # ICSのUIDを付けてイベントごとに一意なURLにする。
        $uid = if ($b -match 'UID:(.+)') { $Matches[1].Trim() } else { "$dt-$sum" }
        $eurl = "https://www.jmrc-shikoku.gr.jp/#$uid"
        if ($eurl -in $knownUrls) { continue }

        $discoveredEvents += [PSCustomObject]@{
            name = $sum; date = $edate; prefecture = $epref; venue = $evenue
            url = $eurl; source = "jmrcshikoku"
        }
        $newUrls += $eurl
    }
    Write-Log "JMRC四国(ICS): $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "JMRC四国(ICS) の取得に失敗: $($_.Exception.Message)"
}

# ===== 会場のイベントカレンダー（一般イベントに混ざったカーイベントを拾う） =====
#
# 展示場・タワー等のカレンダーは車以外のイベントが大半なので、名前で絞る必要がある。
# 2026-07-20 追加。福井・長崎の空白を埋めるのが目的。
#
# 【重要】ここに載せてよいのは、利用規約に無断転載・複製の禁止条項が無いことを
# 実際に本文を読んで確認した会場だけ。幕張メッセ・東京ビッグサイト・朱鷺メッセ・
# 石川県産業展示館・ポートメッセなごや・とりぎん文化会館・ビッグパレットふくしまは
# 明確な禁止条項があるため入れないこと（→ HANDOVER §7 の不採用リスト）。

# 車のイベントかどうかを名前で判定する。
#
# 【注意】「カー」「車」は部分一致の誤検出が非常に多い。
# 2026-07-20 に雑な判定で「キッチンカーの開業セミナー」「医療ソーシャルワーカー協会 研修会」
# 「長崎県サッカー協会 第2回理事会」を取り込んでしまった。
# 対策として、紛らわしい語を先に消してから判定する。
# 取りこぼすより誤って載せる方が害が大きいので、判定は厳しめにしてある。
function Test-CarEventName($name) {
    # ① 実車のイベントでないもの
    if ($name -match 'ラジコン|RCカー|R/Cカー|タミヤ|ミニ四駆|プラモデル|ミニカー|チョロQ') { return $false }

    # ② 「カー」「車」を含むが車と無関係な語を先に消す
    $n = $name
    $n = $n -replace 'サッカー|ワーカー|キッチンカー|フードカー|ベビーカー|スニーカー|メーカー|ロッカー|スピーカー|マーカー|ハッカー|ステッカー|チェッカー|トラッカー|ウォーカー|エスカレーター|ケアマネージャー', ''
    $n = $n -replace '駐車場|駐車|電車|列車|自転車|車椅子|車いす|乗車|下車|発車|停車|車内|歯車|風車|water|water車', ''

    # ③ 車のイベントを示す語
    # ※「ミーティング」単体は入れないこと。「69期社内キックオフミーティング」を
    #   取り込んでしまった（2026-07-20）。車のミーティングは カー/旧車/痛車 等で拾える。
    return ($n -match 'クルマ|くるま|自動車|旧車|痛車|輸入車|中古車|新車|名車|愛車|試乗|モーターショー|オートサロン|オートモービル|カーミーティング|カーフェス|カーショー|カーイベント|オフ会|ドリフト|ジムカーナ|サーキット|走行会|ラリー|ダートトライアル|MOTOR|Motor|AUTO SALON|トヨタ|日産|ニッサン|ホンダ|マツダ|スバル|ダイハツ|スズキ|レクサス|ベンツ|BMW|アウディ|ポルシェ|フェラーリ|MAZDA|TOYOTA|NISSAN|HONDA|SUBARU')
}

# --- 福井県産業会館 ---
Write-Log "福井県産業会館 を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://sankan.sankan.jp/eventinfo/" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    foreach ($m in [regex]::Matches($html, '(?s)<a href="(https://sankan\.sankan\.jp/eventinfo/[^"]+)"[^>]*>.*?<h2>([^<]{3,60})</h2>(.*?)(?=<div class="ei-main"|</section|$)')) {
        $eurl  = $m.Groups[1].Value
        $ename = Decode-Html $m.Groups[2].Value.Trim()
        $rest  = $m.Groups[3].Value
        if (-not (Test-CarEventName $ename)) { continue }
        if ($eurl -in $knownUrls) { continue }
        if ($rest -notmatch '(\d{4})\.(\d{1,2})\.(\d{1,2})') { continue }
        $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        $evenue = if ($rest -match '(\d号館展示場|多目的ホール|屋外展示場)') { "福井県産業会館 $($Matches[1])" } else { "福井県産業会館" }
        $discoveredEvents += [PSCustomObject]@{
            name = $ename; date = $edate; prefecture = "福井県"; venue = $evenue
            url = $eurl; source = "sankan-fukui"
        }
        $newUrls += $eurl
    }
    Write-Log "福井県産業会館: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "福井県産業会館 の取得に失敗: $($_.Exception.Message)"
}

# --- 出島メッセ長崎 ---
Write-Log "出島メッセ長崎 を取得中..."
try {
    $res = Invoke-WebRequest -Uri "https://dejima-messe.jp/event" -UseBasicParsing -TimeoutSec 30
    $html = $res.Content
    $before = $discoveredEvents.Count
    foreach ($m in [regex]::Matches($html, '(?s)<li class="fadeInUp[^"]*">\s*<a href="([^"]+)"(.*?)</li>')) {
        $eurl = $m.Groups[1].Value
        $blk  = $m.Groups[2].Value
        if ($blk -notmatch '<dt class="event_ttl">([^<]{3,80})</dt>') { continue }
        $ename = Decode-Html $Matches[1].Trim()
        if (-not (Test-CarEventName $ename)) { continue }
        if ($eurl -in $knownUrls) { continue }
        if ($blk -notmatch '開催日</th>\s*<td>(\d{4})年(\d{1,2})月(\d{1,2})日') { continue }
        $edate = "$($Matches[1])-$($Matches[2].PadLeft(2,'0'))-$($Matches[3].PadLeft(2,'0'))"
        $discoveredEvents += [PSCustomObject]@{
            name = $ename; date = $edate; prefecture = "長崎県"; venue = "出島メッセ長崎"
            url = $eurl; source = "dejima-messe"
        }
        $newUrls += $eurl
    }
    Write-Log "出島メッセ長崎: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "出島メッセ長崎 の取得に失敗: $($_.Exception.Message)"
}

# ===== 旧車催事暦（midoriga-oka.com） =====
# 全国の旧車イベントを月別に一覧化した個人サイト。
# 「日付 / 時間 / イベント名 / 都道府県+市郡 / 会場」の5列テーブルで、
# 4項目が最初から揃っている数少ないソース。会場データの底上げにも効く。
#
# 利用規約に相当する torisetu.htm に「リンクはフリーです。ご自由にお使い下さい。」とあり、
# 無断使用・転載・複製を禁じる条項は無い（2026-07-20 に本文を確認）。
#
# 注意: Shift_JIS。UTF-8として読むと文字化けする。日付も全角数字。
Write-Log "旧車催事暦 を取得中..."
try {
    $sjis = [Text.Encoding]::GetEncoding("Shift_JIS")
    $before = $discoveredEvents.Count
    $nowY = (Get-Date).Year; $nowM = (Get-Date).Month

    # 今月から12ヶ月先まで見る（年をまたぐ）
    for ($i = 0; $i -lt 12; $i++) {
        $ym = (Get-Date).AddMonths($i)
        $pageUrl = "https://www.midoriga-oka.com/yog/ivc{0}{1}.htm" -f ($ym.Year % 100), $ym.Month.ToString('00')
        try {
            $res = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 15
        } catch { continue }
        $page = $sjis.GetString($res.RawContentStream.ToArray())

        foreach ($tr in [regex]::Matches($page, '(?s)<TR>(.*?)</TR>', 'IgnoreCase')) {
            $tds = @([regex]::Matches($tr.Groups[1].Value, '(?s)<TD[^>]*>(.*?)</TD>', 'IgnoreCase') |
                     ForEach-Object { (($_.Groups[1].Value -replace '<[^>]+>','') -replace '[\s　]+',' ').Trim() })
            if ($tds.Count -lt 5) { continue }

            # 全角数字を半角に直してから日付を読む（「１０月　４日」形式）
            $dcell = $tds[0]
            foreach ($pair in @(@('０','0'),@('１','1'),@('２','2'),@('３','3'),@('４','4'),@('５','5'),@('６','6'),@('７','7'),@('８','8'),@('９','9'))) {
                $dcell = $dcell.Replace($pair[0], $pair[1])
            }
            if ($dcell -notmatch '(\d{1,2})\s*月\s*(\d{1,2})\s*日') { continue }
            $mo = [int]$Matches[1]; $dy = [int]$Matches[2]

            # ページの年月とセルの月がずれる場合があるので、ページ側の年を基準にする
            $yr = $ym.Year
            if ($mo -lt $ym.Month -and $ym.Month -ge 11) { $yr = $ym.Year + 1 }
            $edate = "{0}-{1:00}-{2:00}" -f $yr, $mo, $dy
            try { if ([datetime]$edate -lt (Get-Date).Date) { continue } } catch { continue }

            $ename = $tds[2]
            if (-not $ename -or $ename.Length -lt 3 -or $ename -match '^(イベント名|催事名)$') { continue }

            $epref = ""
            foreach ($p in $PREFS) { if ($tds[3] -match [regex]::Escape($p)) { $epref = $p; break } }
            $evenue = $tds[4]
            if ($evenue -match '^(会場|開催地)$') { $evenue = "" }

            # このサイトは1ページに複数イベントが並ぶだけでイベント個別URLが無い。
            # 名前と日付で一意なURLを作って重複判定に使う。
            $eurl = "https://www.midoriga-oka.com/yog/infome.htm#$edate-$($ename -replace '\s','')"
            if ($eurl -in $knownUrls) { continue }

            $discoveredEvents += [PSCustomObject]@{
                name = $ename; date = $edate; prefecture = $epref; venue = $evenue
                url = $eurl; source = "yogcal"
            }
            $newUrls += $eurl
        }
        Start-Sleep -Milliseconds 400
    }
    Write-Log "旧車催事暦: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "旧車催事暦 の取得に失敗: $($_.Exception.Message)"
}

# ===== 名阪スポーツランド（奈良） =====
# 奈良県内のカーイベントの大半がここで開催されている。月別の走行会予定表が静的HTMLの表。
#
# 【実装上の注意】
#  - **HTTPS非対応**（443を開けていない）。平文HTTPで取得すること
#  - Shift_JIS
#  - 表の構造: 1列目=「4日 （火）」、4列目=「COZY練 ジ」のように主催者名＋種別記号が入る
#    種別記号: ド=ドリフト ジ=ジムカーナ カ=カート ミ=ミニバイク モ=モトクロス モタ=モタード ソ=その他
#  - 四輪だけを採る。ミニバイク・モトクロス・モタード・カートは二輪/カートなので除外
#
# robots.txt は msnbot への Crawl-delay のみで、一般クローラへの制限は無い（2026-07-20 確認）。
Write-Log "名阪スポーツランド を取得中..."
try {
    $sjis = [Text.Encoding]::GetEncoding("Shift_JIS")
    $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    $before = $discoveredEvents.Count

    for ($i = 0; $i -lt 6; $i++) {
        $ym = (Get-Date).AddMonths($i)
        # ページ名は 08.htm / 09.htm …、10月以降は 010.htm 形式（先頭に0が付く）
        $pageName = if ($ym.Month -lt 10) { "{0:00}.htm" -f $ym.Month } else { "0{0}.htm" -f $ym.Month }
        try {
            $res = Invoke-WebRequest -Uri "http://web1.kcn.jp/meihansl/$pageName" -UseBasicParsing -TimeoutSec 20 -Headers @{ "User-Agent" = $ua }
        } catch { continue }
        $page = $sjis.GetString($res.RawContentStream.ToArray())

        foreach ($tr in [regex]::Matches($page, '(?s)<TR[^>]*>(.*?)</TR>', 'IgnoreCase')) {
            # Decode-Html を通して実体参照を戻す（「T&amp;M」→「T&M」）
            $tds = @([regex]::Matches($tr.Groups[1].Value, '(?s)<TD[^>]*>(.*?)</TD>', 'IgnoreCase') |
                     ForEach-Object { Decode-Html ((($_.Groups[1].Value -replace '<[^>]+>','') -replace '&nbsp;',' ' -replace '[\s　]+',' ').Trim()) })
            if ($tds.Count -lt 4) { continue }
            if ($tds[0] -notmatch '(\d{1,2})\s*日') { continue }
            $dy = [int]$Matches[1]

            # 4列目（Cコース＝四輪のドリフト/ジムカーナ枠）を見る
            $cell = $tds[3]
            if (-not $cell -or $cell -match '定休日|貸切|練習走行|コース') { continue }

            # 末尾の種別記号を取り出す。四輪（ド/ジ）以外は載せない
            if ($cell -notmatch '^(.+?)\s*(ドリフト|ジムカーナ|ド|ジ|カ|ミ|モタ|モ|ソ)$') { continue }
            $organizer = $Matches[1].Trim()
            $kind = $Matches[2]
            if ($kind -notin @('ド','ジ','ドリフト','ジムカーナ')) { continue }
            if (-not $organizer -or $organizer.Length -lt 2) { continue }

            $kindName = if ($kind -in @('ド','ドリフト')) { 'ドリフト走行会' } else { 'ジムカーナ' }
            $ename = "$organizer $kindName"
            $edate = "{0}-{1:00}-{2:00}" -f $ym.Year, $ym.Month, $dy
            try { if ([datetime]$edate -lt (Get-Date).Date) { continue } } catch { continue }

            # このサイトはイベント個別URLを持たないので、日付＋名前で一意なURLを作る
            $eurl = "http://web1.kcn.jp/meihansl/$pageName#$edate-$($organizer -replace '\s','')"
            if ($eurl -in $knownUrls) { continue }

            $discoveredEvents += [PSCustomObject]@{
                name = $ename; date = $edate; prefecture = "奈良県"; venue = "名阪スポーツランド"
                url = $eurl; source = "meihan"
            }
            $newUrls += $eurl
        }
        Start-Sleep -Milliseconds 400
    }
    Write-Log "名阪スポーツランド: $($discoveredEvents.Count - $before) 件の新規候補"
} catch {
    Write-Log "名阪スポーツランド の取得に失敗: $($_.Exception.Message)"
}

# ===== 新規イベントをIDを付けてマージ =====
$nextId = $NEW_EVENT_START_ID
if ($existingNewEvents.Count -gt 0) {
    $maxId = ($existingNewEvents | Measure-Object -Property id -Maximum).Maximum
    if ($maxId -ge $nextId) { $nextId = $maxId + 1 }
}

$today = (Get-Date).Date
$jpDowNames = @("日","月","火","水","木","金","土")
$newEventObjects = @()
foreach ($ev in $discoveredEvents) {
    # ④ 過去イベントを除外（今日より前の日付はスキップ）
    try { if ([datetime]$ev.date -lt $today) { continue } } catch {}
    $region = if ($REGION_MAP.ContainsKey($ev.prefecture)) { $REGION_MAP[$ev.prefecture] } else { "その他" }
    # ② カテゴリを自動分類
    $cat = Get-CategoryFromName $ev.name $ev.source
    $obj = [PSCustomObject]@{
        id          = $nextId
        name        = $ev.name
        date        = $ev.date
        endDate     = $ev.date
        prefecture  = if ($ev.prefecture) { $ev.prefecture } else { "未定" }
        region      = $region
        venue       = if ($ev.venue) { $ev.venue } else { "未定" }
        category    = $cat
        description = ""
        url         = $ev.url
        featured    = $false
        source      = $ev.source
    }
    # 詳細ページから拾えた事実があれば、それだけを使って説明文を組み立てる。
    # 収集元の文章はコピーしない（著作権＋重複コンテンツ）。データに無いことは書かない。
    if ($ev.PSObject.Properties.Name -contains 'detail' -and $ev.detail) {
        $obj.description = New-EventDescription $obj $ev.detail $jpDowNames
    }
    $newEventObjects += $obj
    $nextId++
}

# 既存イベントのカテゴリ・説明文も再分類
$updatedExisting = @()
foreach ($ev in $existingNewEvents) {
    $src = if ($ev.PSObject.Properties['source']) { $ev.source } else { "" }
    $ev.category = Get-CategoryFromName $ev.name $src
    $ev.description = ""
    # 都道府県が "未定" の場合、名前から再推定
    if ($ev.prefecture -eq "未定" -or -not $ev.prefecture) {
        $guess = Get-PrefectureFromName "$($ev.name) $($ev.venue)"
        if ($guess) { $ev.prefecture = $guess }
    }
    $updatedExisting += $ev
}
$mergedEvents = @($updatedExisting) + @($newEventObjects)

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
