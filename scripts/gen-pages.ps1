# ===================================================
# CARJAM 個別ページ生成（SEO用）
# イベント・ブログ記事の静的HTMLと sitemap.xml を生成する。
# daily-run.ps1 から毎朝呼ばれる（単体実行も可）。
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

$SITE_URL = "https://carjam-usdm.netlify.app"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Esc-Html($s) {
    if ($null -eq $s) { return "" }
    return $s.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

function Format-DateJp($iso) {
    try {
        $d = [datetime]::ParseExact($iso, "yyyy-MM-dd", $null)
        return "{0}年{1}月{2}日" -f $d.Year, $d.Month, $d.Day
    } catch { return $iso }
}

# ---------------------------------------------------
# データ読み込み（JSON化されたソースのみを読む）
# ---------------------------------------------------
function Read-JsonArrayFromJs($path, $pattern) {
    $raw = Get-Content $path -Raw -Encoding UTF8
    if ($raw -match $pattern) { return @($Matches[1] | ConvertFrom-Json) }
    return @()
}

# PS5.1注意: パイプ経由のConvertFrom-Jsonは配列を1オブジェクトで返すため ForEach-Object で展開する
$events = @()
$events += @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
$events += Read-JsonArrayFromJs "$PROJECT_ROOT\data\new-events.js" 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);'

$posts = @()
$posts += @((Get-Content "$PROJECT_ROOT\data\legacy-posts.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
$posts += Read-JsonArrayFromJs "$PROJECT_ROOT\data\new-blog-posts.js" 'window\.NEW_BLOG_POSTS\s*=\s*(\[[\s\S]*?\]);'

# 車と関係のない行事は載せない。収集元（mach5 など）が花火大会・夏祭りを
# 「カーミーティング」として取り込んでいた（2026-09-14 に約80件見つかった）。
# サイトの質が低く見られ、Google の登録が進まない原因にもなる。
# ※「夏祭り」を名乗る痛車イベント（エンジョイ痛車フェスティバル 夏祭り 等）もあるので、
#   祭り系の語で弾くのは mach5 由来で、かつ車の語を含まないものだけにする。
$FESTIVAL_PATTERN = '花火|盆踊|納涼|夏まつり|夏祭|市民のまつり|市民祭|芸能まつり|鉄砲まつり|みなとまつり|サマーフェスティバル'
$CAR_WORD_PATTERN = '痛車|カー|車|サーキット|ミーティング|HKS|オフ会|ドリフト'
function Test-ListableEvent($e) {
    if (-not $e.name -or -not $e.date) { return $false }
    if ($e.source -eq 'mach5' -and $e.name -match $FESTIVAL_PATTERN -and $e.name -notmatch $CAR_WORD_PATTERN) { return $false }
    if ($e.name -match 'コスプレ') { return $false }
    if ($e.source -eq 'coscam' -and $e.name -notmatch '痛') { return $false }  # コスプレ撮影会の収集元。痛車・コス痛だけ残す
    return $true
}
# 日付に全角数字（"２０２６-１０-１１"）が入っているものがある（minkara・jmty 由来、2026-09-14 に6件）。
# 並べ替え・月の判定が壊れるので半角にそろえる。
function Convert-Digits($s) {
    if (-not $s) { return $s }
    return [regex]::Replace([string]$s, '[０-９]', { param($m) [string]([int][char]$m.Value - 0xFF10) })
}
foreach ($e in $events) {
    if ($e.date) { $e.date = Convert-Digits $e.date }
    if ($e.PSObject.Properties['endDate'] -and $e.endDate) { $e.endDate = Convert-Digits $e.endDate }
}

$before = $events.Count
$events = @($events | Where-Object { (Test-ListableEvent $_) -and ($_.date -match '^\d{4}-\d{2}-\d{2}$') })
Write-Log "gen-pages: 車以外の行事 $($before - $events.Count) 件を除外"

Write-Log "gen-pages: イベント $($events.Count) 件 / 記事 $($posts.Count) 本のページを生成"

# ---------------------------------------------------
# 都道府県・地方の対応表（一覧ページ /area/ 用）
# ---------------------------------------------------
$PREF_SLUG = [ordered]@{
    '北海道'='hokkaido'; '青森県'='aomori'; '岩手県'='iwate'; '宮城県'='miyagi'; '秋田県'='akita'; '山形県'='yamagata'; '福島県'='fukushima'
    '茨城県'='ibaraki'; '栃木県'='tochigi'; '群馬県'='gunma'; '埼玉県'='saitama'; '千葉県'='chiba'; '東京都'='tokyo'; '神奈川県'='kanagawa'
    '新潟県'='niigata'; '富山県'='toyama'; '石川県'='ishikawa'; '福井県'='fukui'; '山梨県'='yamanashi'; '長野県'='nagano'; '岐阜県'='gifu'; '静岡県'='shizuoka'; '愛知県'='aichi'
    '三重県'='mie'; '滋賀県'='shiga'; '京都府'='kyoto'; '大阪府'='osaka'; '兵庫県'='hyogo'; '奈良県'='nara'; '和歌山県'='wakayama'
    '鳥取県'='tottori'; '島根県'='shimane'; '岡山県'='okayama'; '広島県'='hiroshima'; '山口県'='yamaguchi'
    '徳島県'='tokushima'; '香川県'='kagawa'; '愛媛県'='ehime'; '高知県'='kochi'
    '福岡県'='fukuoka'; '佐賀県'='saga'; '長崎県'='nagasaki'; '熊本県'='kumamoto'; '大分県'='oita'; '宮崎県'='miyazaki'; '鹿児島県'='kagoshima'; '沖縄県'='okinawa'
}
$REGION_PREFS = [ordered]@{
    '北海道' = @('北海道')
    '東北'   = @('青森県','岩手県','宮城県','秋田県','山形県','福島県')
    '関東'   = @('茨城県','栃木県','群馬県','埼玉県','千葉県','東京都','神奈川県')
    '中部'   = @('新潟県','富山県','石川県','福井県','山梨県','長野県','岐阜県','静岡県','愛知県')
    '近畿'   = @('三重県','滋賀県','京都府','大阪府','兵庫県','奈良県','和歌山県')
    '中国'   = @('鳥取県','島根県','岡山県','広島県','山口県')
    '四国'   = @('徳島県','香川県','愛媛県','高知県')
    '九州・沖縄' = @('福岡県','佐賀県','長崎県','熊本県','大分県','宮崎県','鹿児島県','沖縄県')
}

# 今後開催（終了日が今日以降）のイベント。一覧ページはこれで作る
$todayStr = Get-Date -Format "yyyy-MM-dd"
$upcoming = @($events | Where-Object { $end = if ($_.endDate) { $_.endDate } else { $_.date }; $end -ge $todayStr } | Sort-Object date, id)
# 一覧ページを作る県（今後のイベントが1件以上）と月
$prefHasPage = @{}
foreach ($e in $upcoming) { if ($PREF_SLUG.Contains([string]$e.prefecture)) { $prefHasPage[[string]$e.prefecture] = $true } }
$monthHasPage = @{}
foreach ($e in $upcoming) { $monthHasPage[$e.date.Substring(0,7)] = $true }

# 出力ディレクトリ（毎回作り直して古いページを掃除）
foreach ($dir in @("$PROJECT_ROOT\area", "$PROJECT_ROOT\month")) {
    if (Test-Path $dir) { Remove-Item "$dir\*.html" -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $dir | Out-Null }
}
foreach ($dir in @("$PROJECT_ROOT\events", "$PROJECT_ROOT\articles")) {
    if (Test-Path $dir) { Remove-Item "$dir\*.html" -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $dir | Out-Null }
}

# ---------------------------------------------------
# 共通テンプレート（単一引用ヒアストリング＝変数展開なし）
# ---------------------------------------------------
$pageTemplate = @'
<!DOCTYPE html>
<html lang="ja">
<head>
  <!-- Google tag (gtag.js) -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-H1788PQ532"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-H1788PQ532');
  </script>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{TITLE}}</title>
  <meta name="description" content="{{DESC}}">
  <link rel="canonical" href="{{CANONICAL}}">
  <meta property="og:title" content="{{TITLE}}">
  <meta property="og:description" content="{{DESC}}">
  <meta property="og:type" content="article">
  <meta property="og:url" content="{{CANONICAL}}">
  <meta property="og:image" content="https://carjam-usdm.netlify.app/images/og-image.png">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/svg+xml" href="../images/favicon.svg">
  <script type="application/ld+json">{{JSONLD}}</script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0a0a0b; color: #c9c9cf; font-family: 'Hiragino Sans','Yu Gothic','Meiryo',sans-serif; line-height: 1.85; }
    a { color: inherit; }
    .nav { display: flex; align-items: center; gap: 10px; padding: 14px 20px; border-bottom: 1px solid #222; background: #111; }
    .nav-mark { width: 34px; height: 34px; background: #e8001d; color: #fff; font-weight: 900; display: flex; align-items: center; justify-content: center; border-radius: 8px; font-size: 14px; }
    .nav a { text-decoration: none; font-weight: 800; color: #fff; letter-spacing: 1px; }
    .nav-sub { font-size: 10px; color: #777; letter-spacing: 2px; }
    main { max-width: 760px; margin: 0 auto; padding: 32px 20px 60px; }
    .chip { display: inline-block; font-size: 11px; font-weight: 700; padding: 4px 12px; border-radius: 20px; background: rgba(232,0,29,.12); color: #ff5468; border: 1px solid rgba(232,0,29,.3); margin-bottom: 14px; }
    h1 { color: #fff; font-size: 24px; line-height: 1.45; margin-bottom: 18px; }
    .meta { background: #141416; border: 1px solid #222; border-radius: 12px; padding: 18px 20px; margin-bottom: 24px; font-size: 14px; }
    .meta div { display: flex; gap: 10px; padding: 4px 0; }
    .meta dt { color: #777; min-width: 5.5em; font-weight: 700; }
    .content { font-size: 15px; }
    .content h2 { font-size: 17px; color: #fff; margin: 1.6em 0 .6em; padding-left: 10px; border-left: 3px solid #e8001d; }
    .content p { margin: 0 0 1em; }
    .content ul, .content ol { margin: 0 0 1em; padding-left: 1.5em; }
    .content strong { color: #fff; }
    .btn { display: inline-block; background: #e8001d; color: #fff; font-weight: 700; text-decoration: none; padding: 12px 22px; border-radius: 8px; margin: 8px 8px 8px 0; font-size: 14px; }
    .btn.ghost { background: none; border: 1px solid #333; color: #c9c9cf; }
    .tags { margin-top: 20px; font-size: 12px; color: #777; }
    .lead { margin-bottom: 20px; }
    .evlist { list-style: none; margin: 0 0 24px; }
    .evlist li { padding: 12px 0; border-bottom: 1px solid #222; }
    .evlist a { color: #fff; font-weight: 700; text-decoration: none; }
    .evlist a:hover { text-decoration: underline; }
    .evlist .sub { display: block; font-size: 12px; color: #888; margin-top: 2px; }
    .content h2.sec { margin-top: 2em; }
    .links { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 20px; }
    .links a { font-size: 13px; text-decoration: none; padding: 6px 12px; border: 1px solid #333; border-radius: 16px; color: #c9c9cf; }
    .links a:hover { border-color: #e8001d; color: #fff; }
    .links .n { color: #777; margin-left: 4px; }
    .related { margin-top: 28px; padding-top: 18px; border-top: 1px solid #222; font-size: 14px; }
    footer { border-top: 1px solid #222; padding: 24px 20px; text-align: center; font-size: 12px; color: #666; }
    footer a { color: #999; }
  </style>
</head>
<body>
<nav class="nav">
  <div class="nav-mark">CJ</div>
  <div><a href="../index.html">CARJAM</a><div class="nav-sub">JAPAN CAR EVENTS</div></div>
</nav>
<main>
{{BODY}}
</main>
<footer>
  <a href="../index.html">CARJAM — 日本全国のカーイベント情報</a>　|　<a href="../area/index.html">都道府県から探す</a>　|　<a href="../blog.html">ブログ</a>　|　<a href="../privacy.html">プライバシーポリシー</a>
</footer>
</body>
</html>
'@

function New-Page($title, $desc, $canonical, $jsonLd, $body, $outPath) {
    $html = $pageTemplate.Replace("{{TITLE}}", (Esc-Html $title)).
        Replace("{{DESC}}", (Esc-Html $desc)).
        Replace("{{CANONICAL}}", $canonical).
        Replace("{{JSONLD}}", $jsonLd).
        Replace("{{BODY}}", $body)
    [IO.File]::WriteAllText($outPath, $html, $utf8NoBom)
}

# 一覧ページで使う部品
function Event-ListHtml($list) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<ul class="evlist">')
    foreach ($ev in @($list)) {
        $d = Format-DateJp $ev.date
        $v = if ($ev.venue -and $ev.venue -ne "未定") { "・" + (Esc-Html $ev.venue) } else { "" }
        [void]$sb.Append("<li><a href=""../events/$($ev.id).html"">$(Esc-Html $ev.name)</a><span class=""sub"">$($d)・$(Esc-Html $ev.prefecture)$($v)・$(Esc-Html $ev.category)</span></li>")
    }
    [void]$sb.Append('</ul>')
    return $sb.ToString()
}

function Month-Label($ym) {
    return "{0}年{1}月" -f [int]$ym.Substring(0,4), [int]$ym.Substring(5,2)
}

# 個別イベントページの下に付ける「同じ県・同じ月のイベント」へのリンク
function Related-LinksHtml($ev) {
    $parts = @()
    $pref = [string]$ev.prefecture
    if ($prefHasPage.ContainsKey($pref)) {
        $parts += "<a href=""../area/$($PREF_SLUG[$pref]).html"">$(Esc-Html $pref)のカーイベント一覧</a>"
    }
    $ym = $ev.date.Substring(0,7)
    if ($monthHasPage.ContainsKey($ym)) {
        $parts += "<a href=""../month/$($ym).html"">$(Month-Label $ym)の全国カーイベント</a>"
    }
    $parts += "<a href=""../area/index.html"">都道府県から探す</a>"
    return "<div class=""related""><div class=""links"">" + ($parts -join "") + "</div></div>"
}

function ItemList-JsonLd($name, $list) {
    $items = @()
    $pos = 1
    foreach ($ev in @($list | Select-Object -First 30)) {
        $items += [ordered]@{ "@type" = "ListItem"; position = $pos; url = "$SITE_URL/events/$($ev.id).html"; name = $ev.name }
        $pos++
    }
    $ld = [ordered]@{ "@context" = "https://schema.org"; "@type" = "ItemList"; name = $name; itemListElement = $items }
    return ($ld | ConvertTo-Json -Depth 6 -Compress)
}

# ---------------------------------------------------
# イベントページ
# ---------------------------------------------------
$eventUrls = @()
foreach ($e in $events) {
    if (-not $e.name -or -not $e.date) { continue }
    $canonical = "$SITE_URL/events/$($e.id).html"
    $dateJp = Format-DateJp $e.date
    $venue = if ($e.venue -and $e.venue -ne "未定") { $e.venue } else { "" }
    $placeName = if ($venue) { $venue } else { $e.prefecture }

    $title = "$($e.name)（$dateJp・$($e.prefecture)）| CARJAM"
    $descText = "「$($e.name)」の開催情報。開催日: $dateJp、開催地: $($e.prefecture)$(if ($venue) { "・$venue" })。日本全国のカーイベント情報はCARJAMでチェック。"

    $ld = [ordered]@{
        "@context" = "https://schema.org"
        "@type"    = "Event"
        name       = $e.name
        startDate  = $e.date
        endDate    = $(if ($e.endDate) { $e.endDate } else { $e.date })
        eventStatus = "https://schema.org/EventScheduled"
        eventAttendanceMode = "https://schema.org/OfflineEventAttendanceMode"
        location   = [ordered]@{
            "@type" = "Place"
            name    = $placeName
            address = [ordered]@{
                "@type" = "PostalAddress"
                addressRegion  = $e.prefecture
                addressCountry = "JP"
            }
        }
        organizer  = [ordered]@{ "@type" = "Organization"; name = "CARJAM（掲載）"; url = $SITE_URL }
        image      = @("$SITE_URL/images/og-image.png")
        description = $descText
    }
    $jsonLd = $ld | ConvertTo-Json -Depth 6 -Compress

    $body = "<div class=""chip"">$(Esc-Html $e.category)</div>`n" +
        "<h1>$(Esc-Html $e.name)</h1>`n" +
        "<div class=""meta"">" +
        "<div><dt>開催日</dt><dd>$dateJp$(if ($e.endDate -and $e.endDate -ne $e.date) { " 〜 " + (Format-DateJp $e.endDate) })</dd></div>" +
        "<div><dt>開催地</dt><dd>$(Esc-Html $e.prefecture)</dd></div>" +
        $(if ($venue) { "<div><dt>会場</dt><dd>$(Esc-Html $venue)</dd></div>" }) +
        "</div>`n" +
        $(if ($e.description) { "<div class=""content""><p>$(Esc-Html $e.description)</p></div>`n" }) +
        $(if ($e.url) { "<a class=""btn"" href=""$(Esc-Html $e.url)"" target=""_blank"" rel=""noopener"">イベント公式情報を見る</a>" }) +
        "<a class=""btn ghost"" href=""../index.html"">CARJAMで他のイベントを探す</a>" +
        (Related-LinksHtml $e)

    New-Page $title $descText $canonical $jsonLd $body "$PROJECT_ROOT\events\$($e.id).html"
    $eventUrls += $canonical
}

# ---------------------------------------------------
# 一覧ページ（都道府県別 /area/ ・ 月別 /month/ ・ 都道府県の索引 /area/index.html）
# 個別イベントページはどのページからもリンクされておらず Google に見つけてもらえなかった
# （2026-09-14 サーチコンソール「参照元ページ: 検出されませんでした」、1,014ページ中登録1）。
# トップはJSで描画しているため、静的なリンクの入った一覧ページで個別ページへつなぐ。
# 「東京都 カーイベント」「2026年10月 車イベント」のような検索の受け皿にもなる。
# ---------------------------------------------------
$hubUrls = @()
$yearNow = (Get-Date).Year

# 地方ごとの県リンク（件数つき）。一覧ページのある県だけ
function Region-LinksHtml($onlyRegion) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($region in $REGION_PREFS.Keys) {
        if ($onlyRegion -and $region -ne $onlyRegion) { continue }
        $links = @()
        foreach ($p in $REGION_PREFS[$region]) {
            if (-not $prefHasPage.ContainsKey($p)) { continue }
            $n = @($upcoming | Where-Object { $_.prefecture -eq $p }).Count
            $links += "<a href=""$($PREF_SLUG[$p]).html"">$(Esc-Html $p)<span class=""n"">$($n)</span></a>"
        }
        if ($links.Count -eq 0) { continue }
        if (-not $onlyRegion) { [void]$sb.Append("<h2 class=""sec"">$(Esc-Html $region)</h2>") }
        [void]$sb.Append("<div class=""links"">" + ($links -join "") + "</div>")
    }
    return $sb.ToString()
}

function Month-LinksHtml($prefix) {
    $links = @()
    foreach ($ym in @($monthHasPage.Keys | Sort-Object)) {
        $n = @($upcoming | Where-Object { $_.date.StartsWith($ym) }).Count
        $links += "<a href=""$($prefix)$($ym).html"">$(Month-Label $ym)<span class=""n"">$($n)</span></a>"
    }
    return "<div class=""links"">" + ($links -join "") + "</div>"
}

# 都道府県別
foreach ($pref in @($prefHasPage.Keys)) {
    $list = @($upcoming | Where-Object { $_.prefecture -eq $pref })
    $slug = $PREF_SLUG[$pref]
    $canonical = "$SITE_URL/area/$($slug).html"
    $region = @($REGION_PREFS.Keys | Where-Object { $REGION_PREFS[$_] -contains $pref })[0]
    $first = Format-DateJp $list[0].date
    $title = "$($pref)のカーイベント・車イベント一覧【$($yearNow)年】| CARJAM"
    $descText = "$($pref)で開催予定のカーイベント$($list.Count)件を日付順に掲載。カーミーティング・旧車・カスタムカーショー・サーキット走行会など、$($pref)の車イベント情報をCARJAMでまとめてチェック。"
    $body = "<div class=""chip"">都道府県別</div>`n" +
        "<h1>$(Esc-Html $pref)のカーイベント一覧</h1>`n" +
        "<p class=""lead"">$(Esc-Html $pref)で今後開催予定のカーイベントは <strong>$($list.Count)件</strong>（$($first)から）。イベント名を押すと、開催日・会場・公式情報をまとめたページが開きます。日程は変わることがあるので、お出かけ前に公式情報を確認してください。</p>`n" +
        (Event-ListHtml $list) +
        "<div class=""content""><h2 class=""sec"">$(Esc-Html $region)のほかの県</h2></div>" + (Region-LinksHtml $region) +
        "<div class=""content""><h2 class=""sec"">月別に探す</h2></div>" + (Month-LinksHtml "../month/") +
        "<a class=""btn ghost"" href=""index.html"">都道府県の一覧へ</a><a class=""btn ghost"" href=""../index.html"">CARJAMトップへ</a>"
    New-Page $title $descText $canonical (ItemList-JsonLd "$($pref)のカーイベント一覧" $list) $body "$PROJECT_ROOT\area\$($slug).html"
    $hubUrls += $canonical
}

# 月別（地方ごとに見出し）
foreach ($ym in @($monthHasPage.Keys | Sort-Object)) {
    $list = @($upcoming | Where-Object { $_.date.StartsWith($ym) })
    $label = Month-Label $ym
    $canonical = "$SITE_URL/month/$($ym).html"
    $title = "$($label)の全国カーイベント・車イベント一覧 | CARJAM"
    $descText = "$($label)に全国で開催予定のカーイベント$($list.Count)件を地方別に掲載。カーミーティング・旧車イベント・カスタムカーショー・モーターショーなど、$($label)の車イベントをCARJAMでチェック。"
    $sections = New-Object System.Text.StringBuilder
    foreach ($region in $REGION_PREFS.Keys) {
        $rl = @($list | Where-Object { $REGION_PREFS[$region] -contains $_.prefecture })
        if ($rl.Count -eq 0) { continue }
        [void]$sections.Append("<div class=""content""><h2 class=""sec"">$(Esc-Html $region)（$($rl.Count)件）</h2></div>" + (Event-ListHtml $rl))
    }
    $body = "<div class=""chip"">月別</div>`n" +
        "<h1>$($label)の全国カーイベント一覧</h1>`n" +
        "<p class=""lead"">$($label)に全国で開催予定のカーイベントは <strong>$($list.Count)件</strong>。地方ごとに日付順で並べています。</p>`n" +
        $sections.ToString() +
        "<div class=""content""><h2 class=""sec"">ほかの月</h2></div>" + (Month-LinksHtml "") +
        "<a class=""btn ghost"" href=""../area/index.html"">都道府県から探す</a><a class=""btn ghost"" href=""../index.html"">CARJAMトップへ</a>"
    New-Page $title $descText $canonical (ItemList-JsonLd "$($label)の全国カーイベント一覧" $list) $body "$PROJECT_ROOT\month\$($ym).html"
    $hubUrls += $canonical
}

# 都道府県の索引
$prefCount = $prefHasPage.Count
$body = "<div class=""chip"">都道府県から探す</div>`n" +
    "<h1>都道府県別 カーイベント一覧</h1>`n" +
    "<p class=""lead"">全国で今後開催予定のカーイベントは <strong>$($upcoming.Count)件</strong>（$($prefCount)都道府県）。県名を押すと、その県のイベントを日付順で見られます。数字は今後の開催件数です。</p>`n" +
    (Region-LinksHtml $null) +
    "<div class=""content""><h2 class=""sec"">月別に探す</h2></div>" + (Month-LinksHtml "../month/") +
    "<a class=""btn ghost"" href=""../index.html"">CARJAMトップへ</a>"
New-Page "都道府県別 カーイベント・車イベント一覧【$($yearNow)年】| CARJAM" "全国のカーイベント$($upcoming.Count)件を都道府県別・月別に探せます。カーミーティング・旧車・カスタムカーショー・サーキット走行会など、日本全国の車イベント情報はCARJAM。" "$SITE_URL/area/" '{"@context":"https://schema.org","@type":"CollectionPage","name":"都道府県別 カーイベント一覧"}' $body "$PROJECT_ROOT\area\index.html"
$hubUrls = @("$SITE_URL/area/") + $hubUrls
Write-Log "gen-pages: 一覧ページ $($hubUrls.Count) 枚（都道府県 $($prefHasPage.Count) / 月 $($monthHasPage.Count) / 索引 1）"

# ---------------------------------------------------
# 記事ページ
# ---------------------------------------------------
$articleUrls = @()
foreach ($p in $posts) {
    if (-not $p.title) { continue }
    $canonical = "$SITE_URL/articles/$($p.id).html"
    $dateJp = Format-DateJp $p.date
    $title = "$($p.title) | CARJAMブログ"
    $descText = $p.excerpt

    $ld = [ordered]@{
        "@context" = "https://schema.org"
        "@type"    = "BlogPosting"
        headline   = $p.title
        datePublished = $p.date
        articleSection = $p.category
        keywords   = ($p.tags -join ",")
        author     = [ordered]@{ "@type" = "Organization"; name = "CARJAM" }
        publisher  = [ordered]@{ "@type" = "Organization"; name = "CARJAM"; url = $SITE_URL }
        mainEntityOfPage = $canonical
        image      = @("$SITE_URL/images/og-image.png")
        description = $p.excerpt
    }
    $jsonLd = $ld | ConvertTo-Json -Depth 6 -Compress

    # 生成記事はHTML、ベース記事はプレーンテキスト（改行区切り）
    $contentHtml = if ($p.content -match '<h2|<p') { $p.content }
        else { "<p>" + ((Esc-Html $p.content) -replace "`n`n+", "</p><p>" -replace "`n", "<br>") + "</p>" }

    $body = "<div class=""chip"">$(Esc-Html $p.category)</div>`n" +
        "<h1>$(Esc-Html $p.title)</h1>`n" +
        "<div class=""meta""><div><dt>公開日</dt><dd>$dateJp</dd></div></div>`n" +
        "<div class=""content"">$contentHtml</div>`n" +
        "<div class=""tags"">$(($p.tags | ForEach-Object { "#" + (Esc-Html $_) }) -join " ")</div>`n" +
        "<a class=""btn ghost"" href=""../blog.html"">ブログ一覧へ戻る</a>"

    New-Page $title $descText $canonical $jsonLd $body "$PROJECT_ROOT\articles\$($p.id).html"
    $articleUrls += $canonical
}

# ---------------------------------------------------
# sitemap.xml
# ---------------------------------------------------
$today = Get-Date -Format "yyyy-MM-dd"
$staticUrls = @("$SITE_URL/", "$SITE_URL/blog.html", "$SITE_URL/submit.html", "$SITE_URL/sponsor.html", "$SITE_URL/contact.html", "$SITE_URL/privacy.html")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($u in ($staticUrls + $hubUrls)) {
    [void]$sb.AppendLine("  <url><loc>$u</loc><lastmod>$today</lastmod></url>")
}
foreach ($u in ($eventUrls + $articleUrls)) {
    [void]$sb.AppendLine("  <url><loc>$u</loc></url>")
}
[void]$sb.AppendLine('</urlset>')
[IO.File]::WriteAllText("$PROJECT_ROOT\sitemap.xml", $sb.ToString(), $utf8NoBom)

Write-Log "gen-pages: 完了（イベント $($eventUrls.Count) / 一覧 $($hubUrls.Count) / 記事 $($articleUrls.Count) / sitemap $($staticUrls.Count + $hubUrls.Count + $eventUrls.Count + $articleUrls.Count) URL）"
