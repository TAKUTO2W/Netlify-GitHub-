# ===================================================
# X（旧Twitter）でカーイベントの告知を探し、CARJAM未掲載のものを報告する
#
# 【この仕組みの位置づけ】
# サイトに自動掲載はしない。**発見のためのレーダー**として使う。
#
# 理由（2026-07-21 に実測）:
#   告知系キーワードで62件取得 → 日付と都道府県の両方が本文にあるのは3件（5%）だけ。
#   しかもその3件は「鉄道おもちゃ展」（車と無関係）と、既に掲載済みイベントの重複投稿。
#   **新規で使えるものはゼロだった。**
#   Xの投稿はイベント告知の形式が決まっておらず、日時・会場が画像のフライヤーにしか
#   書かれていないことが非常に多い。画像内の文字はAPIでは取れない。
#   そのまま取り込むと日付も会場も無いレコードがサイトに流入する。
#
# そこで「候補をレポートに出す→人が見て判断する」形にしている。
# 公式サイトを持たずSNSでしか告知しない小規模イベントを見つけるのが狙い。
#
#   .\scan-x-events.ps1              … 水曜だけ実行される（daily-run から毎日呼ばれる前提）
#   .\scan-x-events.ps1 -Force       … 曜日に関係なく今すぐ実行する
#   .\scan-x-events.ps1 -MaxQueries 3 … 検索するキーワード数を絞る（費用調整）
#
# 【費用】読み取り $0.005/件。既存の従量課金クレジットから引かれる。
#   実測で1回あたり約65円（87件）。**毎日動かすと月2,000円規模**になるので週1回にしている。
#   水曜にしたのは、週末イベントの告知が出そろい、かつ金曜のnote下書き生成より前だから。
# ===================================================
param(
    [int]$MaxQueries = 5,
    [int]$MaxResults = 50,
    [switch]$Force
)

. "$PSScriptRoot\config.ps1"

# ---- 水曜ゲート ----
# 費用がかかるので毎日は動かさない。gen-note-draft.ps1 の金曜ゲートと同じ作法。
if (-not $Force -and (Get-Date).DayOfWeek -ne 'Wednesday') {
    exit 0
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

if (-not $X_API_KEY -or -not $X_API_KEY_SECRET) {
    Write-Log "X検索: 中止 — config.ps1 に X_API_KEY / X_API_KEY_SECRET がありません"
    exit 1
}

# ---- Bearer Token を取得 ----
# 投稿用のキーから App-only トークンを作れるので、config.ps1 への追加設定は不要。
try {
    $pair = "$([uri]::EscapeDataString($X_API_KEY)):$([uri]::EscapeDataString($X_API_KEY_SECRET))"
    $b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $bt = (Invoke-RestMethod -Uri "https://api.twitter.com/oauth2/token" -Method POST `
            -Headers @{ Authorization = "Basic $b64"; "Content-Type" = "application/x-www-form-urlencoded;charset=UTF-8" } `
            -Body "grant_type=client_credentials" -TimeoutSec 30).access_token
} catch {
    Write-Log "X検索: Bearer Token の取得に失敗 — $($_.Exception.Message)"
    exit 1
}

# ---- 検索クエリ ----
# 「参加してきた」等の事後報告を除外し、告知だけを狙う。
# CARJAM自身の投稿も除外（@carjam_usdm）。
$QUERIES = @(
    '(旧車 OR ネオクラシック) (ミーティング OR イベント OR フェス) (開催 OR 開催決定) -is:retweet lang:ja',
    '(痛車 OR コスプレ痛車) (イベント OR 展示 OR フェス) (開催 OR エントリー受付) -is:retweet lang:ja',
    '(カーミーティング OR カーフェス OR カーイベント) (開催 OR 開催決定 OR 参加募集) -is:retweet lang:ja',
    '(走行会 OR ドリフト OR ジムカーナ) (開催 OR エントリー受付中) -is:retweet lang:ja',
    '(オフ会 OR ミーティング) (旧車 OR 愛車 OR クルマ好き) 開催 -is:retweet lang:ja'
)
$QUERIES = @($QUERIES | Select-Object -First $MaxQueries)

$EXCLUDE = '-from:carjam_usdm -参加してきた -行ってきた -参加しました -お疲れ様でした'

$PREF_SHORT = @("北海道","青森","岩手","宮城","秋田","山形","福島","茨城","栃木","群馬","埼玉","千葉","東京","神奈川",
    "新潟","富山","石川","福井","山梨","長野","岐阜","静岡","愛知","三重","滋賀","京都","大阪","兵庫","奈良","和歌山",
    "鳥取","島根","岡山","広島","山口","徳島","香川","愛媛","高知","福岡","佐賀","長崎","熊本","大分","宮崎","鹿児島","沖縄")

# ---- 既存イベント名を読み込む（既知のものを候補から外すため） ----
$known = @()
$raw = Get-Content "$PROJECT_ROOT\data\new-events.js" -Raw -Encoding UTF8
if ($raw -match 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') {
    $known += @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_.name })
}
$known += @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_.name })
# 比較用に記号・空白を落として正規化
function Norm($s) { if (-not $s) { return "" } ($s -replace '[\s　★☆【】\[\]（）()！!？?・、。〜~ー-]', '').ToLower() }
$knownNorm = @($known | ForEach-Object { Norm $_ } | Where-Object { $_ })

# ---- 検索 ----
$seen = @{}
$hits = @()
$fetched = 0

foreach ($qBase in $QUERIES) {
    $q = [uri]::EscapeDataString("$qBase $EXCLUDE")
    $url = "https://api.twitter.com/2/tweets/search/recent?query=$q&max_results=$MaxResults&tweet.fields=created_at,author_id&expansions=author_id&user.fields=username,name"
    try {
        $res = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $bt" } -UseBasicParsing -TimeoutSec 30
        $j = [Text.Encoding]::UTF8.GetString($res.RawContentStream.ToArray()) | ConvertFrom-Json
    } catch {
        Write-Log "X検索: クエリ失敗（HTTP $([int]$_.Exception.Response.StatusCode)）"
        continue
    }

    $users = @{}
    if ($j.includes -and $j.includes.users) { foreach ($u in $j.includes.users) { $users[$u.id] = $u.username } }

    foreach ($t in @($j.data)) {
        $fetched++
        if ($seen.ContainsKey($t.id)) { continue }
        $seen[$t.id] = $true
        $txt = ($t.text -replace '\s+', ' ').Trim()

        # 日付が書かれていないものは候補にしない（画像のフライヤーだけの投稿が非常に多い）
        if ($txt -notmatch '(\d{1,2})\s*[月/]\s*(\d{1,2})\s*日?') { continue }
        $mo = [int]$Matches[1]; $dy = [int]$Matches[2]
        if ($mo -lt 1 -or $mo -gt 12 -or $dy -lt 1 -or $dy -gt 31) { continue }

        # 都道府県が書かれていないものも外す
        $pref = ""
        foreach ($p in $PREF_SHORT) { if ($txt -match $p) { $pref = $p; break } }
        if (-not $pref) { continue }

        # 車と無関係なもの（「電車好き集まれ！鉄道おもちゃ展」が実際に混ざった）
        # ラジコンは「MRD走行会」のように名前からは分からず、ハッシュタグでしか
        # 判別できないことがある（#ラジドリ #RCドリフト #ミニッツ）。
        if ($txt -match '鉄道|電車|プラレール|模型|ミニ四駆|ラジコン|ラジドリ|RCドリフト|RCカー|ミニッツ|MiniZ|Mini-Z|1/10|1/24|ドローン') { continue }

        # 二輪を除外する。CARJAMは四輪のサイト。
        # 初回実行で候補7件中4件がバイクだった（PMCイベント、ハードエンデューロ走行会、
        # カワサキプラザ、トライアンフ）。「走行会」はバイクでも使う語なので必須の処理。
        if ($txt -match 'バイク|ライダー|ライディング|二輪|モーターサイクル|エンデューロ|モトクロス|トライアル|オートバイ|ツーリング|カワサキ|ヤマハ|ハーレー|ドゥカティ|トライアンフ|KTM|BMW Motorrad|🏍') { continue }

        # 既にCARJAMにあるイベントの投稿は除く
        $n = Norm $txt
        $isKnown = $false
        foreach ($kn in $knownNorm) {
            if ($kn.Length -ge 6 -and $n.Contains($kn)) { $isKnown = $true; break }
        }
        if ($isKnown) { continue }

        $uname = if ($users.ContainsKey($t.author_id)) { $users[$t.author_id] } else { "" }
        $hits += [PSCustomObject]@{
            pref = $pref
            date = "{0}/{1}" -f $mo, $dy
            text = $txt
            url  = if ($uname) { "https://x.com/$uname/status/$($t.id)" } else { "https://x.com/i/status/$($t.id)" }
        }
    }
    Start-Sleep -Milliseconds 900
}

# ---- レポート出力 ----
$outDir = "$PROJECT_ROOT\note-drafts"   # .gitignore 済みのフォルダを使う
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = "$outDir\x-scan-$((Get-Date).ToString('yyyy-MM-dd')).txt"

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("X（旧Twitter）から見つけたカーイベント候補")
[void]$sb.AppendLine((Get-Date -Format "yyyy-MM-dd HH:mm"))
[void]$sb.AppendLine("")
[void]$sb.AppendLine("検索した投稿 $fetched 件 → 候補 $(@($hits).Count) 件")
[void]$sb.AppendLine("（日付と都道府県が本文に書かれていて、CARJAMにまだ無いものだけ）")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("※ これは自動掲載していません。中身を見て、載せる価値があれば")
[void]$sb.AppendLine("   submit.html から登録するか、主催者に連絡してください。")
[void]$sb.AppendLine("=" * 60)
[void]$sb.AppendLine("")

foreach ($h in ($hits | Sort-Object pref)) {
    [void]$sb.AppendLine("[$($h.pref)] $($h.date)")
    [void]$sb.AppendLine("  $($h.text)")
    [void]$sb.AppendLine("  → $($h.url)")
    [void]$sb.AppendLine("")
}

if (@($hits).Count -eq 0) {
    [void]$sb.AppendLine("今回は候補が見つかりませんでした。")
}

[IO.File]::WriteAllText($outPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

$cost = [math]::Round($fetched * 0.005 * 150)
Write-Log "X検索: $fetched 件を検索し候補 $(@($hits).Count) 件（約${cost}円）→ $outPath"

Write-Host ""
Write-Host "検索した投稿: $fetched 件 / 候補: $(@($hits).Count) 件（約${cost}円）"
Write-Host "レポート: $outPath"
if (@($hits).Count -gt 0) {
    Write-Host ""
    $hits | Sort-Object pref | Select-Object -First 10 | ForEach-Object {
        "  [{0}] {1}  {2}" -f $_.pref, $_.date, $_.text.Substring(0, [Math]::Min(60, $_.text.Length))
    }
}
