# ===================================================
# CARJAM 毎日の自動実行まとめスクリプト
# タスクスケジューラからこれを呼ぶ
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# イベント収集
& "$scriptDir\check-events.ps1"

# 同じイベントが複数の収集元から入って重複するのを除去する。
# 収集の直後・ページ生成の前に行う。gitが履歴を持つので日次では .bak を作らない。
& "$scriptDir\dedup-events.ps1" -Apply -NoBackup

# ブログ自動生成 + はてなブログ投稿
& "$scriptDir\gen-blog.ps1"

# イベント・記事の個別ページと sitemap.xml を生成（SEO用）
& "$scriptDir\gen-pages.ps1"

# Xへの投稿は 2026-07-21 に停止した（別の仕組み＝Codex 側で担当するため）。
# スクリプトは残してあるので、戻すなら次の行のコメントを外すだけでよい。
# ※ X APIキーは config.ps1 にそのまま残す。scan-x-events.ps1（水曜の収集）が
#   同じキーから Bearer Token を作って使っているため、消すとそちらが動かなくなる。
# & "$scriptDir\gen-x-events.ps1"

# note下書きの自動生成は 2026-07-21 に停止した（不要と判断）。
# スクリプト自体（gen-note-draft.ps1 / gen-note-article.ps1 / post-to-note.ps1）は
# 残してあるので、再開したくなったら次の行を戻すだけでよい。
# & "$scriptDir\gen-note-draft.ps1"

# Xでカーイベントの告知を探す（毎週水曜のみ・サイトには自動掲載せずレポートを出すだけ）
# 出力: note-drafts\x-scan-YYYY-MM-DD.txt → 中身を見て submit.html から登録する
& "$scriptDir\scan-x-events.ps1"

# GitHub に push して Netlify を自動更新
Write-Log "GitHub へ push 中..."
try {
    Set-Location $PROJECT_ROOT
    $git = "C:\Program Files\Git\cmd\git.exe"
    & $git add -A data/new-events.js data/new-blog-posts.js data/updates.js data/known-event-urls.json events articles sitemap.xml
    $today = Get-Date -Format "yyyy-MM-dd"
    & $git commit -m "auto update: $today"
    & $git push
    Write-Log "GitHub push 完了 → Netlify 自動デプロイ開始"
} catch {
    Write-Log "GitHub push エラー: $_"
}
