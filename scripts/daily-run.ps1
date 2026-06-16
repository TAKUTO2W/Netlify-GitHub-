# ===================================================
# CARJAM 毎日の自動実行まとめスクリプト
# タスクスケジューラからこれを呼ぶ
# ===================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# イベント収集
& "$scriptDir\check-events.ps1"

# ブログ自動生成
& "$scriptDir\gen-blog.ps1"
