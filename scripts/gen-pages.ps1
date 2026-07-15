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

Write-Log "gen-pages: イベント $($events.Count) 件 / 記事 $($posts.Count) 本のページを生成"

# 出力ディレクトリ（毎回作り直して古いページを掃除）
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
  <a href="../index.html">CARJAM — 日本全国のカーイベント情報</a>　|　<a href="../blog.html">ブログ</a>　|　<a href="../privacy.html">プライバシーポリシー</a>
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
        "<a class=""btn ghost"" href=""../index.html"">CARJAMで他のイベントを探す</a>"

    New-Page $title $descText $canonical $jsonLd $body "$PROJECT_ROOT\events\$($e.id).html"
    $eventUrls += $canonical
}

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
foreach ($u in $staticUrls) {
    [void]$sb.AppendLine("  <url><loc>$u</loc><lastmod>$today</lastmod></url>")
}
foreach ($u in ($eventUrls + $articleUrls)) {
    [void]$sb.AppendLine("  <url><loc>$u</loc></url>")
}
[void]$sb.AppendLine('</urlset>')
[IO.File]::WriteAllText("$PROJECT_ROOT\sitemap.xml", $sb.ToString(), $utf8NoBom)

Write-Log "gen-pages: 完了（イベント $($eventUrls.Count) / 記事 $($articleUrls.Count) / sitemap $($staticUrls.Count + $eventUrls.Count + $articleUrls.Count) URL）"
