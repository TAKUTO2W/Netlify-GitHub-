# ===================================================
# イベント詳細ページから「会場・住所・主催・時間・料金・公式URL」を取り出す共通ライブラリ
#
# check-events.ps1（今後の収集）と enrich-event-details.ps1（既存データの補完）の
# 両方から読み込む。ロジックを1か所にまとめて二重管理を防ぐ。
#
# 【背景】2026-07-20 時点で、自動収集206件のうち会場が入っているのは11%、
# 説明文は0%だった。収集元の詳細ページには情報が載っていたのに、
# スクレイパー側が venue="" と決め打ちしていて最初から取りに行っていなかった。
#
# 多くのイベントサイトは「ラベル行 → 値行」の構造になっている:
#     会場
#     石川県産業展示館 4号館
#     住所
#     〒920-0361 石川県金沢市袋畠町南193番地
# これを利用して汎用的に拾う。
# ===================================================

$PREF_NAMES = @("北海道","青森県","岩手県","宮城県","秋田県","山形県","福島県",
    "茨城県","栃木県","群馬県","埼玉県","千葉県","東京都","神奈川県",
    "新潟県","富山県","石川県","福井県","山梨県","長野県","岐阜県","静岡県","愛知県",
    "三重県","滋賀県","京都府","大阪府","兵庫県","奈良県","和歌山県",
    "鳥取県","島根県","岡山県","広島県","山口県",
    "徳島県","香川県","愛媛県","高知県",
    "福岡県","佐賀県","長崎県","熊本県","大分県","宮崎県","鹿児島県","沖縄県")

# HTMLを行の配列にする。ナビ・ヘッダー・フッターは先に落とす
# （落とさないと「都道府県から探す」メニュー等を拾って誤判定する。7/20の事故と同じ轍）
function ConvertTo-DetailLines($html) {
    $h = $html
    foreach ($t in @('script','style','nav','header','footer','aside','select','form')) {
        $h = [regex]::Replace($h, "(?is)<$t[^>]*>.*?</$t>", ' ')
    }
    $h = [regex]::Replace($h, '(?is)<!--.*?-->', ' ')
    $txt = ($h -replace '<[^>]+>', "`n")
    # HTML実体参照を戻す
    $txt = $txt -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#0?39;', "'"
    $txt = [regex]::Replace($txt, '&#(\d+);', { [char][int]$args[0].Groups[1].Value })
    return @($txt -split "`n" | ForEach-Object { ($_ -replace '[ \t ]+', ' ').Trim() } | Where-Object { $_ -ne '' })
}

# 収集元サイトのAI生成痕やナビ由来のゴミを落とす
function Test-JunkLine($s) {
    if ($s.Length -lt 2) { return $true }
    if ($s -match 'contentReference|oaicite|Googleマップ|コンテンツへスキップ|カートに追加|お買い物を続ける|カートへ進む') { return $true }
    if ($s -match '^(TOP|HOME|イベント一覧|周辺情報|アクセス|地図|シェア|ツイート)$') { return $true }
    if ($s -match '^[>＞»\|｜\-–—・\s]+$') { return $true }
    return $false
}

# ラベル行の直後の値を拾う。
# $labels は正規表現。ラベル行に「会場：〇〇」と値が同居している場合も拾う。
function Get-LabeledValue($lines, $labelPattern, [int]$maxLines = 1) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        # 「会場：石川県産業展示館」のように同じ行に値がある場合
        if ($l -match "^\s*$labelPattern\s*[:：]\s*(.+)$") {
            $v = $Matches[1].Trim()
            if ($v -and -not (Test-JunkLine $v)) { return $v }
        }
        # 「会場」だけの行 → 次の行が値
        if ($l -match "^\s*$labelPattern\s*[:：]?\s*$") {
            $collected = @()
            for ($j = $i + 1; $j -lt $lines.Count -and $collected.Count -lt $maxLines; $j++) {
                $v = $lines[$j]
                if (Test-JunkLine $v) { continue }
                # 次のラベルに到達したら打ち切り
                if ($v -match '^(会場|住所|所在地|開催日|日時|開催時間|時間|主催|主催者|入場料|料金|参加費|URL|公式サイト|概要|開催概要|イベント概要|イベント内容|参加・見学について|お問い合わせ)\s*[:：]?$') { break }
                $collected += $v
            }
            if ($collected.Count -gt 0) { return ($collected -join ' ') }
        }
    }
    return ""
}

# 詳細ページから拾える項目をまとめて返す
function Get-EventDetailFields($html) {
    $lines = ConvertTo-DetailLines $html
    $f = @{}
    $f.venue     = Get-LabeledValue $lines '(会場|開催場所|開催地|場所)'        1
    $f.address   = Get-LabeledValue $lines '(住所|所在地)'                      1
    $f.time      = Get-LabeledValue $lines '(開催時間|時間|開催時刻)'           2
    $f.organizer = Get-LabeledValue $lines '(主催者|主催|オーガナイザー)'       1
    $f.fee       = Get-LabeledValue $lines '(入場料|料金|参加費|エントリー費)'  1
    $f.officialUrl = ""
    $u = Get-LabeledValue $lines '(URL|公式サイト|公式HP|ホームページ)' 1
    if ($u -match '(https?://[^\s"<>]+)') { $f.officialUrl = $Matches[1] }

    # 会場が空でも住所があれば、住所から会場らしき部分を作らない。
    # 住所は住所として別に持つ（推測で会場名をでっち上げない）
    if ($f.venue) {
        # 「宮崎県 生駒高原 駐車場」のように県名が頭に付くことがある。会場名としてはそのまま残す
        $f.venue = ($f.venue -replace '^\s*〒?\d{3}-?\d{4}\s*', '').Trim()
        if ($f.venue.Length -gt 60) { $f.venue = "" }   # 明らかに拾いすぎたものは捨てる
    }
    return $f
}

# 住所や会場名から都道府県を取り出す（会場が分かれば都道府県も確定できる）
function Get-PrefectureFromPlace($text, $prefList) {
    if (-not $text) { return "" }
    foreach ($p in $prefList) {
        if ($text -match [regex]::Escape($p)) { return $p }
    }
    return ""
}

# 説明文を「自分の言葉で」組み立てる。
#
# 【方針】収集元サイトの説明文は**そのままコピーしない**。理由は2つ:
#   1) 他サイトの文章をそのまま転載するのは著作権上の問題がある
#   2) 同じ文章が複数サイトにあると重複コンテンツとしてSEO評価が下がる
# 抽出した「事実（会場・日時・主催・料金）」だけを使って組み立てる。
# 事実には著作権が無く、文章はこちらのオリジナルになる。
# **データに無いことは絶対に書かない**（推測で「入場無料」等と書かない）。
function New-EventDescription($ev, $fields, $jpDow) {
    $parts = @()

    $d = [datetime]::MinValue
    $dateStr = ""
    if ([datetime]::TryParseExact($ev.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
        $dateStr = "{0}年{1}月{2}日（{3}）" -f $d.Year, $d.Month, $d.Day, $jpDow[[int]$d.DayOfWeek]
        if ($ev.endDate -and $ev.endDate -ne $ev.date) {
            $d2 = [datetime]::MinValue
            if ([datetime]::TryParseExact($ev.endDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d2)) {
                $dateStr += "〜{0}月{1}日（{2}）" -f $d2.Month, $d2.Day, $jpDow[[int]$d2.DayOfWeek]
            }
        }
    }

    # 1文目: いつ・どこで・何が
    # 会場名にすでに都道府県が入っている場合は前置しない
    # （「福岡県の宮崎県 生駒高原」のような二重表記を防ぐ）
    $venueHasPref = $false
    if ($fields.venue) {
        foreach ($p in $script:PREF_NAMES) { if ($fields.venue -match [regex]::Escape($p)) { $venueHasPref = $true; break } }
    }
    $place = ""
    if ($fields.venue) {
        $place = $fields.venue
        if (-not $venueHasPref -and $ev.prefecture -and $ev.prefecture -ne '未定') {
            $place = "$($ev.prefecture)の$($fields.venue)"
        }
    } elseif ($ev.prefecture -and $ev.prefecture -ne '未定') {
        $place = $ev.prefecture
    }

    # ※ "$kindです" と書くと「kindです」という変数名として解釈される（PSは日本語も変数名に使える）。
    #    必ず $() で囲うこと。2026-07-20 に実際に踏んだ。
    # カテゴリ名をそのまま繋ぐと「カスタム・チューニングです」と不自然になるので言い換える
    $kindMap = @{
        'カーミーティング'     = 'カーミーティング'
        'レース'               = 'モータースポーツイベント'
        'モーターショー'       = 'モーターショー'
        'クラシックカー'       = 'クラシックカーイベント'
        'カスタム・チューニング' = 'カスタムカーイベント'
        'オフロード・SUV'      = 'オフロード・SUV系のイベント'
    }
    $kind = if ($ev.category -and $kindMap.ContainsKey($ev.category)) { $kindMap[$ev.category] }
            elseif ($ev.category) { "$($ev.category)のイベント" }
            else { "カーイベント" }
    if ($dateStr -and $place) { $parts += "$dateStr、$($place)で開催される$($kind)です。" }
    elseif ($dateStr)         { $parts += "$($dateStr)に開催される$($kind)です。" }
    elseif ($place)           { $parts += "$($place)で開催される$($kind)です。" }

    # 2文目以降: 分かっている事実だけを足す
    if ($fields.time)      { $parts += "開催時間は$($fields.time)。" }
    if ($fields.organizer) { $parts += "主催は$($fields.organizer)。" }
    if ($fields.fee)       { $parts += "入場・参加費は「$($fields.fee)」。" }
    if ($fields.address)   { $parts += "所在地は$($fields.address)。" }

    if ($parts.Count -eq 0) { return "" }
    return ($parts -join '')
}
