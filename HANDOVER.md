# CARJAM 引き継ぎ書

最終更新: 2026-07-19 / 前セッションからの引き継ぎ用

---

## 1. このプロジェクトは何か

**CARJAM** — 日本全国のカーイベント情報を自動収集・集約する静的サイト。
運営: 株式会社USDM（takuto）／ 個人運営で**更新は全自動**。

| 項目 | 値 |
|---|---|
| 本番URL | https://carjam-usdm.netlify.app |
| ローカル | `C:\Users\user\claude-code\car-site` |
| リポジトリ | https://github.com/TAKUTO2W/Netlify-GitHub- |
| ホスティング | Netlify（GitHubにpushで自動デプロイ） |
| 技術 | 素のHTML/CSS/JS（フレームワークなし）＋ PowerShell 5.1 |
| 現在の規模 | イベント197件 / AI記事37本 / SEOページ309 |

---

## 2. 毎朝9時に全自動で動くもの

Windowsタスクスケジューラ **`CARJAM_DailyUpdate`** が `scripts\daily-run.ps1` を実行。
中身は以下を順番に呼ぶだけ：

| # | スクリプト | 内容 | 頻度 |
|---|---|---|---|
| 1 | `check-events.ps1` | 12サイトをスクレイピングしてイベント収集 | 毎日 |
| 2 | `gen-blog.ps1` | **Claude API**で記事2本生成 → はてなブログ投稿 | 毎日 |
| 3 | `gen-pages.ps1` | イベント/記事の個別HTML + sitemap.xml 生成 | 毎日 |
| 4 | `gen-x-events.ps1` | Xにイベントまとめを投稿 | **偶数日のみ** |
| 5 | `gen-note-draft.ps1` | note用下書きを生成しメモ帳で開く | **金曜のみ** |
| 6 | （daily-run内） | git add/commit/push → Netlifyデプロイ | 毎日 |

ログ: `scripts\run.log`（**UTF-16なので `Get-Content` で読む。bashのgrepは文字化けする**）

---

## 3. 発信チャネルと費用

| チャネル | 方式 | 頻度 | 費用 |
|---|---|---|---|
| サイト本体 | 完全自動 | 毎日 | 無料 |
| はてなブログ | 完全自動（API） | 毎日2本 | 無料 |
| X @carjam_usdm | 完全自動（API） | 2日に1回 | 月$3 |
| note @usdmstaff | **半自動**（下書き生成→手動コピペ） | 週1（金） | 無料 |

**noteの運用手順**（毎週金曜、ユーザーの作業は2〜3分）:
1. 朝9時に `note-drafts\note-draft-YYYY-MM-DD.txt` が生成されメモ帳が自動で開く
2. 下書き冒頭に書かれた **アイキャッチ画像 `images\note-eyecatch.jpg`** をnoteで選ぶ
3. タイトルと本文をコピペして公開
※ noteは投稿APIが無く、画像アップロードもOSのダイアログを使うため**自動化不可**（規約リスクもあり不採用）
| Claude API（記事生成） | — | — | 月$2程度 |

**残高に注意**: X APIはプリペイド制。現在$25チャージ済み（≒8ヶ月分）。切れると投稿が止まる。
確認先: https://console.x.com/accounts/2072807412650663936/billing/credits

---

## 4. 認証情報（すべて `scripts\config.ps1`）

**このファイルは `.gitignore` 済み・絶対にコミットしない。値をチャットに貼らせない。**

- `$CLAUDE_API_KEY` — 記事生成用（2026-07-15に再発行）
- `$HATENA_*` — はてなブログ投稿用
- `$X_API_KEY` / `$X_API_KEY_SECRET` / `$X_ACCESS_TOKEN` / `$X_ACCESS_TOKEN_SECRET` — X投稿用（2026-07-18に再発行）
- `$X_POST_BLOG` — **未設定＝ブログ告知のXポストは無効**（コスト抑制。有効化するなら `$true` を追加）

**編集時の注意**: ユーザーはメモ帳で編集する。cp932で保存されることがあるので、
編集後は UTF-8 BOM 付きに戻すこと（PowerShellが日本語を読めなくなる）。

---

## 5. 計測・SEO

- **GA4**: 測定ID `G-H1788PQ532`（全8ページの`<head>`にgtag設置済み）
  - アカウント「USDM」→ プロパティ「CARJAM」
  - ※同じGoogleアカウントに別サイトのGAプロパティもあるので選択時に注意
- **Search Console**: `https://carjam-usdm.netlify.app/` をURLプレフィックスで登録済み、sitemap送信済み（298 URL検出）
- 2026-07-15に導入したばかりなので、**検索流入が出るのはこれから**（1〜2ヶ月）

---

## 6. 前セッションでやったこと（2026-07-15〜19）

1. 旧PCからの移行検証（全項目OK）
2. ブログをテンプレ30本ローテ → **Claude API生成に切替**（テンプレ枯渇のため）
3. ブログ表示バグ2件修正（並び順が古い順／HTMLタグが生表示）
4. GA4導入
5. **SEO個別ページ化**（モーダルのみ→309ページ、schema.org構造化データ付き）＋sitemap＋GSC登録
6. X自動投稿の実装・運用開始
7. note半自動運用の実装＋1本目投稿（**投稿はユーザーが完了済み**）

---

## 7. 未完了・次にやること

### 🔴 すぐ着手できるもの

**A. はてなブログの「placeholder」記事削除（未処理）**
- 7/16のAI生成事故で中身空の記事がはてな側に残っている（サイト側は削除済み）
- 削除するかはユーザー判断待ち。APIで削除可能

### 🟡 提案済み・ユーザー未決定

- **独自ドメイン取得**（carjam.jp 等・年1,500円前後）— 早いほどSEO評価の積み上げが有利
- **主催者への「掲載しました」連絡** — 無料で最も効果的な認知拡大策。連絡先リストは私が生成可能
- **埋め込みウィジェット配布** — 他サイトに貼れるイベント一覧パーツ

### 🟢 却下済み（蒸し返さない）

- ❌ ブログを1日4本に増やす → GoogleのAI大量生成ペナルティのリスク。2本/日を維持
- ❌ noteへ毎日のAI記事を転記 → 重複コンテンツで共食い＋スパム見え。週1まとめのみ

---

## 8. 既知のハマりどころ

| 事象 | 対処 |
|---|---|
| PowerShell 5.1 で `.Count` が `$null` | `@()` で配列化してから `.Count`（1件ヒット時のバグ）。7/3の記事重複の原因 |
| `run.log` が文字化け | UTF-16。`Get-Content` で読む |
| `config.ps1` が cp932 になる | メモ帳保存が原因。UTF-8 BOMに戻す |
| `ConvertFrom-Json` が配列を1個に潰す | `| ForEach-Object { $_ }` で展開 |
| `-ExecutionPolicy Bypass` がauto modeで拒否される | ユーザーに承認してもらう。ポリシーは全スコープUndefined |
| ヒーローの「掲載イベント数」が実数と違う | **仕様**（DB全件＝過去含む）。直さない |

---

## 9. ユーザーについて

- Claude Code初心者。**専門用語には日本語の意味を添える**
- 手順は**1度に1つ**。長い手作業（コピペ等）は苦手なので、私が代行できる部分は代行する
- ブラウザ操作は Chrome拡張（claude-in-chrome）で代行してきた。Chromeが多数接続されているので
  毎回「確認画面を出して選ぶ」方式が確実
- **APIキー等の値は私が受け取らない/書き込まない**（ユーザーが直接ファイルに貼る運用で合意済み）
- 費用には敏感。施策を提案するときは必ず金額の目安を添える

---

## 10. 参考

- 元の引き継ぎ書（Notion): https://app.notion.com/p/3913bb91b90d81bc8a7cec021b7ec083
- Obsidian記録: `C:\AI関連一覧\obsidian\MyVault\MyVault\` の Decisions/ Knowledge/
- Claudeメモリ: `C:\Users\user\.claude\projects\C--Users-user-claude-code-car-site\memory\`
