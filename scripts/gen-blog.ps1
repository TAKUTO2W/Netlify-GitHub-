# ===================================================
# CARJAM ブログ記事 自動生成・はてなブログ投稿スクリプト
# Claude API不要・HTML記事テンプレートを使用
# はてなブログ: WSSE認証（rakumaru方式）
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

# ===================================================
# WSSE認証ヘッダー生成
# ===================================================
function Make-WsseHeader($username, $apiKey) {
    $nonce = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($nonce)
    $created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $combined = $nonce + [System.Text.Encoding]::UTF8.GetBytes($created) + [System.Text.Encoding]::UTF8.GetBytes($apiKey)
    $digest = $sha1.ComputeHash($combined)

    $digestB64 = [Convert]::ToBase64String($digest)
    $nonceB64  = [Convert]::ToBase64String($nonce)

    return "UsernameToken Username=`"$username`", PasswordDigest=`"$digestB64`", Nonce=`"$nonceB64`", Created=`"$created`""
}

# ===================================================
# はてなブログ投稿（HTML形式・WSSE認証）
# ===================================================
function Post-ToHatena($title, $bodyHtml, $category) {
    $carjamPromo = @"
<hr style="margin:2rem 0;border-color:#e0e0e0;">
<div style="background:#fff8f0;border:2px solid #e8001d;border-radius:12px;padding:1.2rem 1.4rem;text-align:center;">
  <p style="font-size:1rem;font-weight:bold;color:#e8001d;margin:0 0 0.5rem;">🚗 全国の車イベント情報はCARJAMで！</p>
  <p style="margin:0 0 0.8rem;font-size:0.95rem;">レース・カスタムショー・クラシックカー・ミーティングなど、日本全国の車イベントを一括検索</p>
  <a href="$CARJAM_URL" style="display:inline-block;background:#e8001d;color:#fff;padding:0.6rem 1.8rem;border-radius:8px;text-decoration:none;font-weight:bold;">CARJAM をみる →</a>
</div>
"@

    $fullBody = $bodyHtml + $carjamPromo
    $escapedBody = $fullBody -replace ']]>', ']]&gt;'
    $escapedTitle = $title -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:app="http://www.w3.org/2007/app">
  <title>$escapedTitle</title>
  <author><name>$HATENA_ID</name></author>
  <content type="text/html"><![CDATA[$escapedBody]]></content>
  <updated>$now</updated>
  <app:control><app:draft>no</app:draft></app:control>
</entry>
"@

    $wsse = Make-WsseHeader $HATENA_ID $HATENA_API_KEY
    $postUrl = "https://blog.hatena.ne.jp/$HATENA_ID/$HATENA_BLOG_ID/atom/entry"

    $headers = @{
        "Content-Type" = "application/atom+xml;type=entry"
        "X-WSSE"       = $wsse
    }

    $response = Invoke-WebRequest -Uri $postUrl -Method POST -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($xml)) -TimeoutSec 30 -UseBasicParsing
    # 記事URLを返す（X投稿で使用）
    $location = $response.Headers["Location"]
    if (-not $location) {
        # AtomPub response の <link rel="alternate"> から抽出
        if ($response.Content -match '<link[^>]+rel="alternate"[^>]+href="([^"]+)"') {
            $location = $Matches[1]
        }
    }
    return @{ StatusCode = $response.StatusCode; ArticleUrl = $location }
}

# ===================================================
# カスタム情報 記事テンプレート（15本）
# ===================================================
$customArticles = @(
    @{
        title   = "車高調整（ローダウンサス・エアサス）の選び方と注意点"
        excerpt = "車高を下げてスタイルをカッコよくしたい！でも選び方を間違えると乗り心地が最悪になることも。"
        content = @"
<h2>車高調整の種類</h2>
<p>車高を下げる方法には主に<strong>ダウンサスペンション</strong>・<strong>車高調（フルタップ式）</strong>・<strong>エアサスペンション</strong>の3種類があります。ダウンサスはコストが安く手軽ですが調整幅がなく、車高調は細かく高さを設定できる反面、セッティングに知識が必要です。エアサスはスイッチ一つで車高が変わる最上位の選択肢ですが価格は高め。</p>
<h2>選び方のポイント</h2>
<ul>
  <li><strong>街乗りメイン</strong>なら全長調整式車高調（乗り心地とのバランスが取りやすい）</li>
  <li><strong>見た目重視</strong>ならエアサス（駐車場やイベント時に低く、走行時は上げられる）</li>
  <li><strong>コスパ重視</strong>ならダウンサス＋純正ショック交換</li>
</ul>
<h2>注意点</h2>
<p>車高を下げすぎると車検に通らなくなる場合があります。地上最低高9cm以上が保安基準。また、タイヤとフェンダーの干渉も要チェックです。ローダウン後は必ずアライメントを調整しましょう。</p>
"@
        tags    = @("車高調","ローダウン","エアサス","カスタム","サスペンション")
    },
    @{
        title   = "ホイール交換の基礎知識：PCD・オフセット・インセットの計算方法"
        excerpt = "ホイール交換はドレスアップの王道。でも数値の意味を知らないと最悪ハミタイに…"
        content = @"
<h2>ホイール選びで必須の3つの数値</h2>
<p>ホイール交換時に必ず確認する数値がPCD・オフセット（インセット）・ハブ径の3つです。</p>
<h2>PCDとは？</h2>
<p><strong>PCD（ピッチ・サークル・ダイアメーター）</strong>はボルト穴の中心を結んだ円の直径。日本車の多くは<strong>PCD114.3</strong>（5穴）か<strong>PCD100</strong>（4穴・5穴）です。車に合わないPCDのホイールは装着不可。</p>
<h2>オフセットとは？</h2>
<p>ホイールの中心面からハブ取り付け面までの距離。<strong>数値が小さい（ローオフセット）</strong>ほどホイールが外側に出ます。純正より低い数値にするとツライチ・ハミタイになるので注意。</p>
<h2>ハブ径</h2>
<p>ハブセンターの穴径。ほとんどの社外ホイールはハブリングで対応できます。ぴったり合うものを選ぶとセンター出しがしやすくなります。</p>
"@
        tags    = @("ホイール交換","PCD","オフセット","ドレスアップ","インチアップ")
    },
    @{
        title   = "マフラー交換で変わる排気音と馬力アップの仕組み"
        excerpt = "マフラー交換は音・見た目・パワーすべてを変える定番チューン。選び方を解説します。"
        content = @"
<h2>マフラーの種類</h2>
<p>交換マフラーには<strong>砲弾型</strong>・<strong>デュアル出し</strong>・<strong>センター出し</strong>などがあります。さらに交換部位によって<strong>リアピース（テール部のみ）</strong>・<strong>中間パイプ＋リア</strong>・<strong>フロントパイプから全交換</strong>と分かれます。</p>
<h2>音量と車検</h2>
<p>保安基準では近接排気音量の上限が定められています（2016年以降の車は<strong>96dB以下</strong>）。JASMAマーク付きマフラーは基準内なので車検対応の目安になります。爆音系は車検時に純正に戻す手間が発生します。</p>
<h2>馬力アップの仕組み</h2>
<p>純正マフラーは消音・耐久性重視で排気抵抗が高め。抵抗を減らすと排気効率が上がり<strong>数馬力〜10馬力程度</strong>のアップが見込めます。ただしNA車はほぼ体感できない場合も。ターボ車の方が効果が出やすいです。</p>
"@
        tags    = @("マフラー交換","排気音","馬力アップ","チューニング","車検対応")
    },
    @{
        title   = "エアロパーツ（フロントリップ・リアディフューザー）の選び方"
        excerpt = "エアロパーツでドレスアップ＆ダウンフォース向上。素材・形状の違いを理解して選ぼう。"
        content = @"
<h2>主なエアロパーツの種類</h2>
<ul>
  <li><strong>フロントリップスポイラー</strong>：バンパー下部に取り付け、フロントのダウンフォースを増加</li>
  <li><strong>サイドスカート</strong>：車体側面の空気の流れを整えてリフトを低減</li>
  <li><strong>リアディフューザー</strong>：リア下部の乱流を整え、リアの安定性を向上</li>
  <li><strong>リアウイング・スポイラー</strong>：リアダウンフォースを直接発生させる</li>
</ul>
<h2>素材の違い</h2>
<p><strong>FRP（繊維強化プラスチック）</strong>は安価で加工しやすいが割れやすい。<strong>CFRP（カーボン）</strong>は軽量で高剛性だが高価。<strong>ウレタン</strong>は柔軟で接触時に割れにくく街乗り向き。</p>
<h2>注意点</h2>
<p>車検では最低地上高9cm以上が必要。フロントリップはバンパーの一部とみなされるため、地上高に注意。車種専用品を選ぶと取り付けが楽です。</p>
"@
        tags    = @("エアロパーツ","フロントリップ","リアディフューザー","ドレスアップ","FRP")
    },
    @{
        title   = "ウィンドウフィルムとラッピングの違い・それぞれの選び方"
        excerpt = "フィルムチューンは手軽なカスタムの代表格。ウィンドウフィルムとラッピングの違いをおさえよう。"
        content = @"
<h2>ウィンドウフィルム</h2>
<p>窓ガラスに貼る透明〜スモーク系のフィルム。主な目的は<strong>遮熱・UVカット・プライバシー保護</strong>。フロントガラスと運転席・助手席のサイドガラスは可視光線透過率<strong>70%以上</strong>が保安基準。スモークが濃すぎると車検に通りません。</p>
<h2>ラッピングフィルム</h2>
<p>ボディ全体や一部をフィルムで覆うカスタム。再塗装と違い<strong>剥がせばノーマルに戻せる</strong>のが最大の利点。マット・カーボン・ミラー・サテンなど豊富な仕上げが選べます。施工費用は全体で<strong>15〜50万円</strong>程度。</p>
<h2>DIYか業者か</h2>
<p>ウィンドウフィルムは小窓なら自分でも貼れますが、気泡が入りやすく技術が必要。ラッピングは業者施工を強くおすすめします。特に大面積は専門の技術が仕上がりに大きく影響します。</p>
"@
        tags    = @("ウィンドウフィルム","カーラッピング","スモーク","カスタム","フィルムチューン")
    },
    @{
        title   = "ブレーキキャリパー塗装・交換でブレーキ性能を向上させる方法"
        excerpt = "ホイールの隙間から見えるキャリパーを赤や金に塗装するだけでスポーティさが大幅アップ！"
        content = @"
<h2>キャリパー塗装の基本</h2>
<p>純正キャリパーを耐熱スプレーで塗装するだけで見た目が激変します。<strong>耐熱温度300℃以上</strong>の専用塗料を使いましょう。スプレー缶タイプは2,000〜3,000円程度から入手可能。</p>
<h2>DIY塗装の手順</h2>
<ol>
  <li>ホイールを外してキャリパーを脱脂・マスキング</li>
  <li>足付け（ペーパーで軽く研磨）</li>
  <li>プライマー → 本塗装（2〜3回重ね塗り）→ クリア</li>
  <li>十分に乾燥させてから装着</li>
</ol>
<h2>社外キャリパーへの交換</h2>
<p>brembo・Alcon・Endlessなどの社外大径キャリパーへの交換はブレーキ性能を大幅アップできますが、<strong>ホイールとの干渉チェックが必須</strong>。キャリパーだけでなくローターサイズも変わるため、ホイールは19インチ以上が一般的です。</p>
"@
        tags    = @("キャリパー塗装","ブレーキ強化","ドレスアップ","brembo","カスタム")
    },
    @{
        title   = "ドライブレコーダー最新機種の選び方と取り付けポイント"
        excerpt = "煽り運転・もらい事故対策の必需品ドラレコ。前後2カメラ・駐車監視の選び方を解説。"
        content = @"
<h2>ドラレコ選びの4つのポイント</h2>
<ol>
  <li><strong>前後カメラ</strong>：後方からの追突・煽り対策に必須。リアカメラ付きを選ぼう</li>
  <li><strong>解像度</strong>：ナンバープレートを鮮明に記録するには<strong>Full HD（1080p）以上</strong>が目安。最近は4Kモデルも</li>
  <li><strong>駐車監視</strong>：駐車中の当て逃げを記録。常時録画・動体検知・衝撃検知の3モードがあると安心</li>
  <li><strong>GPS内蔵</strong>：走行速度・位置情報を記録でき、事故時の証拠能力が上がる</li>
</ol>
<h2>取り付けポイント</h2>
<p>フロントカメラはルームミラー裏に設置すると視野を妨げず法令上も問題なし。配線はAピラー内部に隠すと見た目がすっきりします。電源はシガーソケットか<strong>常時電源（ACCから）</strong>に接続。駐車監視には専用の低電圧カットオフユニットが必要です。</p>
"@
        tags    = @("ドライブレコーダー","前後カメラ","駐車監視","煽り運転対策","カーグッズ")
    },
    @{
        title   = "LED化でヘッドライト・テールランプをカスタムする方法"
        excerpt = "暗い純正ハロゲンをLEDに換えるだけで見た目も視認性も劇的に変わる！選び方と注意点。"
        content = @"
<h2>LEDバルブ交換のメリット</h2>
<p>ハロゲン球からLEDに交換すると<strong>明るさが約2〜3倍</strong>になり、消費電力は約1/3に低減。白く明るい光で夜間視認性が大幅アップします。バルブ寿命もハロゲンの約6,000時間に対し<strong>30,000時間以上</strong>と大幅に長持ち。</p>
<h2>選び方のチェックポイント</h2>
<ul>
  <li><strong>バルブ規格を確認</strong>：H4・H7・H11など車種ごとに異なる。整備書かオートバックスのサイトで確認</li>
  <li><strong>車検対応マーク</strong>：「車検対応品」の表記があるものを選ぶ（光軸・光量・色温度が基準内）</li>
  <li><strong>放熱設計</strong>：LEDはヒートシンクやファンで放熱が必要。安物は熱で早期劣化する</li>
</ul>
<h2>HID・レーザーとの違い</h2>
<p>HIDは明るいが立ち上がりが遅い。最新のマトリクスLEDやレーザーヘッドライトは対向車を眩惑しないよう制御できますが価格は高め。バルブ交換で手軽に始めるならLEDが最適解です。</p>
"@
        tags    = @("LEDバルブ","ヘッドライト","テールランプ","カスタム","車検対応")
    },
    @{
        title   = "バケットシート交換：純正シートとスポーツシートの違い"
        excerpt = "ドライビングポジションを決めるシート選び。ホールド感と日常快適性のバランスが鍵。"
        content = @"
<h2>バケットシートの特徴</h2>
<p>スポーツ走行でのドライバーの横Gをしっかり支えるために設計されたシート。左右のサイドサポートが高く、<strong>ホールド性が格段に上がる</strong>のがメリット。サーキット走行・峠攻めには欠かせません。</p>
<h2>フルバケ vs セミバケ</h2>
<ul>
  <li><strong>フルバケット</strong>：背もたれが固定で調整不可。リクライニングなし。4点・6点ハーネス対応。ガチのサーキット向き</li>
  <li><strong>セミバケット</strong>：リクライニング機能あり。純正シートより格段にホールドが高く日常使いにも対応</li>
</ul>
<h2>交換時の注意</h2>
<p>車種専用シートレールが必要。シートベルト警告灯・エアバッグ関係の配線を純正同様に接続すること（SRSエアバッグのコネクタを外すと警告灯が点灯）。公道走行ならシートベルトも認証品を使用すること。</p>
"@
        tags    = @("バケットシート","シート交換","フルバケ","セミバケ","ドレスアップ")
    },
    @{
        title   = "ステアリング交換の選び方とエアバッグキャンセラーの注意事項"
        excerpt = "細径ステアリングへの交換でドライビングが変わる。でもエアバッグ問題は絶対押さえておこう。"
        content = @"
<h2>ステアリング交換のメリット</h2>
<p>純正より<strong>細径（Φ330〜350mm）</strong>のスポーツステアリングに交換すると、操舵感がシャープになりドライビングポジションも改善できます。グリップ素材（本革・スウェード・ウッド）でドライバーの好みに合わせてカスタマイズ可能。</p>
<h2>エアバッグ問題</h2>
<p>社外ステアリングに交換するとエアバッグが廃止されます。SRS警告灯を消すために<strong>エアバッグキャンセラー（抵抗器）</strong>を取り付けますが、万が一の事故時にエアバッグは展開しません。公道での安全性が低下する点を理解した上で判断してください。</p>
<h2>ボス（ハブ）の選び方</h2>
<p>ステアリングと車体を繋ぐボスは<strong>車種専用品</strong>を必ず使用。ホーンボタンを別途用意するか、ボスにホーン配線端子があるものを選びましょう。</p>
"@
        tags    = @("ステアリング交換","細径ハンドル","エアバッグ","スポーツ","カスタム")
    },
    @{
        title   = "サスペンション交換前後の違いと走行フィーリング改善方法"
        excerpt = "ふわふわした乗り味を引き締めたい・峠でもロールを抑えたい方向けサスペンション選びガイド。"
        content = @"
<h2>純正サスペンションの特性</h2>
<p>純正サスは快適性・耐久性・コスト最優先で設計されています。スポーツ走行では<strong>ロール量が大きく</strong>、コーナリング時の安定感が不足しがち。</p>
<h2>アップグレードの選択肢</h2>
<ul>
  <li><strong>スポーツバネ＋純正ショック</strong>：安価だがショックが早期劣化しやすい</li>
  <li><strong>車高調（フルタップ式）</strong>：車高・減衰力を個別調整可能。最もバランスが良い</li>
  <li><strong>スタビライザー交換・追加</strong>：ロール量を抑えつつ乗り心地への影響が少ない</li>
  <li><strong>ピロボール化</strong>：サーキット専用。乗り心地は悪化するが応答性が最大に</li>
</ul>
<h2>交換後のセッティング</h2>
<p>サスペンション交換後は必ず<strong>4輪アライメント調整</strong>を行いましょう。キャンバー・トー・キャスターが狂うとタイヤの偏摩耗や直進安定性の低下につながります。工賃は1〜2万円程度。</p>
"@
        tags    = @("サスペンション","車高調","スタビライザー","アライメント","チューニング")
    },
    @{
        title   = "ターボチューン・タービン交換で出力を大幅アップする方法"
        excerpt = "ターボ車のポテンシャルを引き出す方法。タービン交換から始めるチューニングを解説。"
        content = @"
<h2>ターボチューンの基本</h2>
<p>ターボ車のチューニングは段階的に行うのが鉄則。最初はECUリマップ（ブースト圧アップ）→インタークーラー強化→タービン交換という順番が一般的です。</p>
<h2>タービン交換の種類</h2>
<ul>
  <li><strong>純正形状タービン</strong>：純正と同サイズだが耐久性・効率を高めた品。低速レスポンスを保ちつつ最高出力アップ</li>
  <li><strong>ハイフロータービン</strong>：純正より大径化。高回転での最高出力が大幅アップ。ただしターボラグが増加</li>
  <li><strong>ビッグタービン</strong>：大排気量レースエンジン向け。一般公道でのセッティングには高度な知識が必要</li>
</ul>
<h2>補機類のセット交換</h2>
<p>タービンを交換する場合、<strong>インジェクター・燃料ポンプ・ECUセッティング</strong>も必ずセットで対応が必要。燃調が合わないとエンジンが壊れます。信頼できるチューニングショップへの依頼を強くおすすめします。</p>
"@
        tags    = @("ターボチューン","タービン交換","馬力アップ","ECUセッティング","チューニング")
    },
    @{
        title   = "オイルクーラー取り付けでエンジンを守る方法"
        excerpt = "サーキット走行やスポーツ走行でエンジンオイルが高温になりすぎる問題をオイルクーラーで解決。"
        content = @"
<h2>オイルクーラーが必要な場面</h2>
<p>通常の街乗りでは純正の油温管理で十分ですが、<strong>サーキット走行・山岳路の連続走行・チューニングエンジン</strong>ではオイル温度が130℃を超えることがあります。高温はオイルの劣化を加速させエンジン寿命を縮めます。</p>
<h2>オイルクーラーの種類と取り付け位置</h2>
<ul>
  <li><strong>プレート＆フィン型</strong>：コンパクトで冷却効率が高い。バンパー開口部前に設置</li>
  <li><strong>チューブ＆フィン型</strong>：安価で広く流通。冷却効率はやや低め</li>
</ul>
<h2>取り付け時の注意</h2>
<p>サンドイッチブロック（オイルフィルター座面に割り込ませる）方式が一般的。取り付け後は<strong>オイル漏れがないか数日間チェック</strong>が必須です。冬季に油温が上がりにくくなるため、<strong>サーモスタット付き</strong>を選ぶと季節を選ばず使えます。</p>
"@
        tags    = @("オイルクーラー","サーキット","チューニング","エンジンオイル","冷却")
    },
    @{
        title   = "ロールケージ取り付けの基礎とメリット・デメリット"
        excerpt = "安全性とボディ剛性を同時に高めるロールケージ。車内レイアウトへの影響も含めて解説。"
        content = @"
<h2>ロールケージの目的</h2>
<p>ロールケージの主目的は<strong>横転時のキャビン保護</strong>。モータースポーツの安全規定で義務化されており、公式戦に出場するなら取り付け必須です。また副次的にボディ剛性が大幅にアップし、コーナリング時のレスポンスが向上します。</p>
<h2>公道仕様 vs サーキット専用</h2>
<ul>
  <li><strong>6点式（公道可）</strong>：Aピラー〜ルーフをパイプで結ぶ。車検対応品を選べば公道走行OK</li>
  <li><strong>フルロールケージ（サーキット専用）</strong>：ドア部分まで張り巡らせる本格仕様。後部座席廃止が一般的</li>
</ul>
<h2>デメリット</h2>
<p>室内空間が大幅に狭くなる。乗り降りが不便になる。パイプが頭部に近いため<strong>ヘルメットの着用が推奨</strong>（ないとパイプに頭をぶつける危険）。普段使いの車への取り付けは利便性と安全性のトレードオフをよく考えましょう。</p>
"@
        tags    = @("ロールケージ","ボディ剛性","サーキット","安全装備","モータースポーツ")
    },
    @{
        title   = "フルコン・サブコン：ECUチューニングの基礎知識"
        excerpt = "エンジン制御を最適化してパワーアップ。サブコンとフルコンの違いを分かりやすく解説。"
        content = @"
<h2>ECUチューニングとは</h2>
<p>ECU（エンジンコントロールユニット）の燃料噴射量・点火時期・ブースト圧などのマップを書き換えることで、<strong>エンジンの出力特性を最適化</strong>します。純正ECUは環境・耐久性・コストのバランスを重視した保守的な設定のため、チューニングパーツに合わせた最適化で出力が向上します。</p>
<h2>サブコン（サブコントロールユニット）</h2>
<p>純正ECUの信号に割り込んで補正するデバイス。取り付けが比較的簡単で、<strong>純正ECUに戻すことも容易</strong>。ただし制御できる範囲が限られるため、大幅なチューンには対応しにくい。</p>
<h2>フルコン（フルコントロールユニット）</h2>
<p>純正ECUを取り外し、汎用ECUで完全に置き換えます。<strong>あらゆるパラメータを自由に設定</strong>できるため大規模チューンに対応。セッティングには専門のダイノ（シャーシダイナモ）設備と技術が必要。費用は工賃含め<strong>30〜100万円以上</strong>が一般的です。</p>
"@
        tags    = @("ECUチューニング","フルコン","サブコン","エンジン制御","チューニング")
    }
)

# ===================================================
# 車のトラブル解消 記事テンプレート（15本）
# ===================================================
$troubleArticles = @(
    @{
        title   = "エンジンがかからない原因TOP5と対処法"
        excerpt = "朝、車のエンジンがかからない…焦らず原因を確認。よくある原因と対処法を解説します。"
        content = @"
<h2>原因1：バッテリー上がり</h2>
<p>最も多い原因がバッテリー上がり。セルモーターの音が弱い・またはまったく音がしない場合はバッテリーを疑いましょう。ブースターケーブルやジャンプスターターで対応できます。</p>
<h2>原因2：燃料切れ</h2>
<p>燃料計の針が「E」付近なら燃料切れの可能性。携行缶で給油するか、ロードサービスに連絡を。</p>
<h2>原因3：スターターモーターの故障</h2>
<p>「カチカチ」という音だけしてエンジンがかからない場合はスターター故障の可能性。バッテリーを充電しても改善しなければ修理が必要。</p>
<h2>原因4：燃料ポンプの故障</h2>
<p>IGNオンで「ウィーン」というポンプ音が聞こえなければ燃料ポンプ故障を疑う。エンジンが全くかかる気配がない場合に多い。</p>
<h2>原因5：イモビライザーのエラー</h2>
<p>スマートキーの電池切れや電波干渉でイモビが誤作動することも。スペアキーで試してみましょう。どれも解決しなければJAFか保険ロードサービスに連絡を。</p>
"@
        tags    = @("エンジンかからない","バッテリー上がり","トラブル","故障","応急処置")
    },
    @{
        title   = "タイヤのパンク応急処置と交換のタイミング"
        excerpt = "走行中にパンク！焦らず安全に対処するための手順と、スペアタイヤ交換の基本を解説。"
        content = @"
<h2>パンクに気づいたら</h2>
<p>走行中にハンドルが取られる・振動が増した場合はパンクの可能性があります。急ブレーキ・急ハンドルは禁物。<strong>ゆっくり速度を落として安全な場所に停車</strong>しましょう。</p>
<h2>スペアタイヤへの交換手順</h2>
<ol>
  <li>ハザードランプ点灯・発煙筒設置（後続車への警告）</li>
  <li>ジャッキポイントを確認してジャッキアップ</li>
  <li>ホイールナットを外してタイヤ交換</li>
  <li>ナットは対角線順に仮締め → 接地後に本締め</li>
</ol>
<h2>テンパータイヤ（スペアタイヤ）の注意</h2>
<p>テンパータイヤは<strong>最高速度80km/h以下・走行距離100km以内</strong>が目安。あくまで応急用です。パンク修理後すぐに通常タイヤに戻しましょう。</p>
<h2>パンク修理キットの場合</h2>
<p>最近の車はスペアタイヤの代わりにパンク修理キット（コンプレッサー＋シーリング剤）が積まれているケースも。釘刺さりなど小さな穴なら応急処置できますが、大きなカットは対応不可。</p>
"@
        tags    = @("パンク","タイヤ交換","応急処置","スペアタイヤ","ロードサービス")
    },
    @{
        title   = "エアコンが効かない原因と冷媒（ガス）補充方法"
        excerpt = "夏に限って車のエアコンが壊れる…。冷媒ガス不足から圧縮機故障まで原因別に解説。"
        content = @"
<h2>まず確認すること</h2>
<p>エアコンスイッチを入れてコンプレッサーが動作しているか確認（ブーン音・エンジン回転数の変動）。動いていない場合はコンプレッサーか電気系の問題。</p>
<h2>原因1：冷媒（ガス）不足</h2>
<p>エアコンガス（R-134a）が漏れて不足すると冷えが弱くなります。<strong>補充費用は5,000〜15,000円</strong>程度。カーディーラーやカー用品店で対応可能。ただし漏れている場合は修理が先。</p>
<h2>原因2：コンプレッサー故障</h2>
<p>異音（ガリガリ・キーキー）がする場合はコンプレッサーのベアリングやクラッチ故障の可能性。交換費用は<strong>5〜15万円</strong>と高額。</p>
<h2>原因3：エバポレーターの詰まり</h2>
<p>風は出るが冷えない場合はエバポレーターの汚れ・詰まりも原因に。エアコンフィルターを定期交換し、エバポレーター洗浄スプレーで予防できます。</p>
"@
        tags    = @("エアコン","冷媒補充","コンプレッサー","カーエアコン","夏対策")
    },
    @{
        title   = "ブレーキの異音・振動の原因と対処法"
        excerpt = "ブレーキを踏むたびにキーキー・ゴーゴーと音が…。そのまま乗り続けると危険です。"
        content = @"
<h2>キーキー音（高音）</h2>
<p>ブレーキパッドの摩耗センサーが鳴らす警告音の可能性が高いです。パッドの厚さが残り数mmになると金属がローターに接触して音が出ます。<strong>早急にパッド交換</strong>が必要。放置するとローターも傷みます。</p>
<h2>ゴーゴー・ガリガリ音（低音・金属音）</h2>
<p>パッドが完全に摩耗してバックプレートがローターに接触している状態。<strong>危険な状態</strong>なので即修理が必要。ローターごと交換になることが多く費用が増大します。</p>
<h2>ブレーキング時の振動（ステアリングが震える）</h2>
<p>ブレーキローターの歪みが原因のことが多い。熱による変形や長期間の固定（タイヤが動かない状態での放置）で発生します。<strong>ローターの研磨か交換</strong>で解消できます。</p>
<h2>対処法</h2>
<p>ブレーキの異常は命に直結する問題です。音や振動が続く場合は自分で判断せず、すぐに整備工場へ持ち込みましょう。</p>
"@
        tags    = @("ブレーキ異音","ブレーキパッド","ローター","振動","車検")
    },
    @{
        title   = "警告灯が点灯したときの対応ガイド【色別・種類別】"
        excerpt = "ダッシュボードに見慣れない警告灯が点いた！色と種類で緊急度を判断して正しく対処しよう。"
        content = @"
<h2>警告灯の色の意味</h2>
<ul>
  <li><strong>赤色</strong>：緊急・危険。すぐに安全な場所に停車して確認が必要</li>
  <li><strong>オレンジ/黄色</strong>：注意。近日中に点検・修理が必要</li>
  <li><strong>緑/青色</strong>：正常作動中の表示（ウィンカー・ハイビームなど）</li>
</ul>
<h2>主な赤色警告灯と対処</h2>
<ul>
  <li><strong>エンジンオイル圧力</strong>：すぐに停車・エンジン停止。オイル漏れの可能性</li>
  <li><strong>水温（H）</strong>：オーバーヒート。すぐに停車してエンジンを冷ます</li>
  <li><strong>充電（バッテリー）</strong>：オルタネーター故障の可能性。バッテリーが切れる前に整備工場へ</li>
</ul>
<h2>エンジン警告灯（オレンジ）</h2>
<p>エンジン制御システムの異常を示します。すぐに止まるわけではないが放置厳禁。診断機でエラーコードを読み取り原因を特定しましょう。</p>
"@
        tags    = @("警告灯","エンジン警告灯","オーバーヒート","トラブル","車のトラブル")
    },
    @{
        title   = "バッテリー上がりのジャンプスタート方法と予防法"
        excerpt = "バッテリー上がりは突然やってくる。ジャンプスタートの正しい手順と予防法を覚えておこう。"
        content = @"
<h2>ジャンプスタートの手順</h2>
<ol>
  <li>救援車をバッテリー上がり車のそばに並べる（エンジンはかけたまま）</li>
  <li><strong>赤いケーブル</strong>を上がり車の＋端子 → 救援車の＋端子につなぐ</li>
  <li><strong>黒いケーブル</strong>を救援車の－端子 → 上がり車のエンジンブロック（アース）につなぐ（－端子でも可だがスパーク防止のためアースが安全）</li>
  <li>救援車のエンジン回転を少し上げて3〜5分待つ</li>
  <li>上がり車のエンジンをかける</li>
  <li>ケーブルを逆の順番（黒→赤）で外す</li>
</ol>
<h2>ジャンプスターター（モバイルタイプ）</h2>
<p>救援車不要の携帯型ジャンプスターターが便利。<strong>1〜2万円</strong>で購入でき、緊急時に非常に役立ちます。スマートフォンの充電やLEDライトとしても使えるものが多い。</p>
<h2>予防法</h2>
<p>バッテリーは3〜5年が交換目安。アイドリングストップ車はより短寿命の傾向があります。カー用品店で無料テストしてもらえるので、定期的にチェックを。</p>
"@
        tags    = @("バッテリー上がり","ジャンプスタート","ブースターケーブル","緊急対応","予防法")
    },
    @{
        title   = "オーバーヒートの原因と冷却水（クーラント）管理方法"
        excerpt = "水温計が上昇中！オーバーヒートは重大なエンジンダメージにつながる。正しい対処法を解説。"
        content = @"
<h2>オーバーヒートのサイン</h2>
<p>水温計の針が「H」側に傾いている・ダッシュボードの水温警告灯が点灯・ボンネットから白煙が出るといった症状が現れます。この状態で走り続けるとエンジンが焼き付き、<strong>数十万円の修理費</strong>になることも。</p>
<h2>緊急対処法</h2>
<ol>
  <li>エアコンをオフにして暖房を最大にする（エンジン熱を逃がす）</li>
  <li>安全な場所に停車</li>
  <li>エンジンをすぐに止めずアイドリングで冷却（急停止はNG）</li>
  <li>十分冷えてからラジエターキャップを開ける（熱いうちに開けると噴出・危険）</li>
</ol>
<h2>冷却水の管理</h2>
<p>冷却水（LLC/クーラント）は<strong>2年または4万km</strong>を目安に交換。リザーバータンクの水位をMAX〜MINの間に保ちましょう。水道水の補充は緊急時のみ。成分が薄まるので早めに正規のクーラントで補充・交換を。</p>
"@
        tags    = @("オーバーヒート","冷却水","クーラント","水温","エンジントラブル")
    },
    @{
        title   = "フロントガラスの油膜・くもりを解消してクリアな視界を保つ方法"
        excerpt = "雨の日にワイパーを動かすと視界がぼやける…それは油膜が原因。解消方法を徹底解説。"
        content = @"
<h2>油膜の原因</h2>
<p>排気ガス・撥水コーティング剤の残留・ワイパーゴムの劣化などで油膜が形成されます。雨天時に視界がにじんで見えるのはこれが原因。夜間の対向車ライトの滲みも油膜によるものです。</p>
<h2>油膜取りの手順</h2>
<ol>
  <li>ガラスを水で洗い流す</li>
  <li>油膜取り専用クリーナー（キイロビン等）をスポンジに取り円を描くように磨く</li>
  <li>水で洗い流して乾燥させる</li>
  <li>撥水コーティング剤（ガラコ等）を施工</li>
</ol>
<h2>車内のくもり対策</h2>
<p>内窓のくもりはタバコのヤニや皮脂が原因のことも。<strong>内窓専用クリーナー</strong>で拭き取るとすっきりします。エアコンのA/Cボタンを使えばくもり除去が早くなります。</p>
<h2>撥水コーティングの持続</h2>
<p>施工したコーティングは<strong>1〜3ヶ月</strong>で効果が低下します。定期的に再施工しましょう。</p>
"@
        tags    = @("油膜取り","フロントガラス","撥水コーティング","視界","ワイパー")
    },
    @{
        title   = "異音（ゴトゴト・キーキー・カラカラ）別の原因と診断方法"
        excerpt = "走行中に変な音がする…。音の種類から原因を推測して早めに対処しましょう。"
        content = @"
<h2>ゴトゴト音（低速時・段差通過後）</h2>
<p>足回りからのゴトゴト音は<strong>スタビライザーリンク・ブッシュ類の摩耗</strong>が原因のことが多い。放置するとステアリングの安定性が低下します。1〜3万円程度で修理可能。</p>
<h2>キーキー音（走行時・ブレーキ時）</h2>
<p>走行時のキーキー音はブレーキパッドの摩耗センサーかドライブシャフトの異常。ブレーキ時のみなら<strong>パッド交換</strong>、常時鳴る場合はベアリング系を疑う。</p>
<h2>カラカラ音（エンジン回転に連動）</h2>
<p>エンジン回転に合わせてカラカラ音がする場合はオイル不足・タイミングチェーンの伸び・エンジンマウントの劣化などが考えられます。<strong>エンジンオイルの量を確認</strong>してから整備工場へ。</p>
<h2>シャリシャリ音（走行中）</h2>
<p>ブレーキローターに砂や小石が挟まっていることが多い。自然に取れる場合もありますが、数日続くなら確認を。</p>
"@
        tags    = @("異音","ゴトゴト","キーキー","カラカラ","足回り")
    },
    @{
        title   = "ドアが開かない・閉まらないときの応急対処法"
        excerpt = "ドアのトラブルは朝一番に起こりがち。原因と応急処置、修理が必要なケースを解説。"
        content = @"
<h2>ドアが外から開かない</h2>
<p><strong>アウタードアハンドルの故障</strong>またはロッド・ケーブルの外れが原因。内側からは開く場合はハンドルかそのリンク部分の問題。内側からも開かない場合はラッチ（錠前）の故障。</p>
<h2>ドアが閉まらない・半ドアになる</h2>
<p>ストライカー（ドア枠側の金具）とラッチの噛み合わせが悪いことが原因。<strong>ヒンジの緩み・経年変化によるドアの下がり</strong>が多い。応急処置としてストライカーの位置を調整することで改善できる場合があります。</p>
<h2>凍結でドアが開かない（冬季）</h2>
<p>ドアのゴムパッキンが凍り付いた状態。<strong>解凍スプレー（デアイサー）</strong>をゴム部分に吹き付けて溶かします。お湯は熱膨張でパッキンを傷めるのでNG。予防にはパッキンへのシリコンスプレーが効果的。</p>
<h2>電動ドア（スライドドア）が動かない</h2>
<p>ヒューズ切れ・センサーの誤作動・モーター故障が考えられます。手動で開閉できる場合はそのまま使いながら早めに診断を。</p>
"@
        tags    = @("ドアトラブル","ドア開かない","凍結","スライドドア","応急処置")
    },
    @{
        title   = "車検に通らない主な理由と事前チェックポイント"
        excerpt = "車検は突然落ちると大変。事前に自分でチェックできるポイントをまとめました。"
        content = @"
<h2>車検で落ちやすいポイント10選</h2>
<ol>
  <li><strong>タイヤのはみ出し（ハミタイ）</strong>：フェンダーからタイヤが出ていると不合格</li>
  <li><strong>光軸のずれ</strong>：ヘッドライトの向きが基準外。事前に光軸調整を</li>
  <li><strong>スモークフィルムが濃い</strong>：可視光線透過率70%未満は不合格</li>
  <li><strong>マフラーの音量超過</strong>：近接排気音量が基準を超えると不合格</li>
  <li><strong>警告灯の点灯</strong>：エンジン・ABS警告灯などが点灯したまま</li>
  <li><strong>ブレーキパッドの残量不足</strong>：目視で確認できる場合がある</li>
  <li><strong>ワイパーゴムの劣化</strong>：拭き取りが不均一だと不合格になることも</li>
  <li><strong>ウィンカー・ライト類の球切れ</strong>：全灯の点灯確認を事前に</li>
  <li><strong>ホーン（クラクション）が鳴らない</strong>：接続不良・故障</li>
  <li><strong>車高が低すぎる</strong>：地上最低高9cm未満</li>
</ol>
<h2>事前に自分でできる対策</h2>
<p>上記10項目を車検の1ヶ月前に自分でチェックするだけで、再検査のリスクと余計な費用を大幅に減らせます。</p>
"@
        tags    = @("車検","車検対応","整備","タイヤ","光軸")
    },
    @{
        title   = "オイル漏れを発見したときの緊急対応と修理方法"
        excerpt = "駐車場に黒いシミ…エンジンオイル漏れは放置厳禁。発見したらすぐに対処しましょう。"
        content = @"
<h2>オイル漏れの確認方法</h2>
<p>駐車後に地面に黒〜茶色のシミがある・エンジンオイルゲージを確認して残量が減っている・走行後にエンジンルームから焦げ臭いにおいがするといった症状が出たらオイル漏れを疑いましょう。</p>
<h2>漏れ箇所の特定</h2>
<p>主な漏れ箇所は<strong>オイルパン・ヘッドカバーガスケット・フロントクランクシール・ドレンボルト周辺</strong>です。ウエスで漏れ箇所を拭いてエンジンをかけると漏れが分かりやすくなります。</p>
<h2>応急処置</h2>
<p>少量の漏れなら<strong>オイル添加剤（液体ガスケット系）</strong>で一時的に止められることがありますが、あくまで応急処置。根本修理が必要です。大量漏れの場合は走行不能になるため、<strong>すぐに整備工場かロードサービス</strong>に連絡を。</p>
<h2>修理費用の目安</h2>
<p>ドレンボルトのパッキン交換は数百円。ガスケット交換は工賃含め<strong>1〜5万円</strong>程度。クランクシール交換は位置によっては高額になる場合があります。</p>
"@
        tags    = @("オイル漏れ","エンジンオイル","ガスケット","修理","応急処置")
    },
    @{
        title   = "ガス欠直前の対処法と燃費を改善するドライビングテクニック"
        excerpt = "燃料警告灯が点いた！あとどのくらい走れる？ガス欠寸前の対処法と燃費向上テクニックを解説。"
        content = @"
<h2>燃料警告灯が点いたら</h2>
<p>多くの車は警告灯点灯時に残量<strong>約7〜10L</strong>。走れる距離は車種によりますが概ね<strong>60〜100km</strong>程度。ナビで最寄りのガソリンスタンドを即座に検索し、高速走行を控えてエコ運転で向かいましょう。</p>
<h2>万が一ガス欠になったら</h2>
<p>エンジンが止まる前にハザードランプを点灯して安全な場所に寄せましょう。高速道路ではSA・PAに向かうか、路肩に停車して<strong>JAFや保険ロードサービス</strong>に連絡を。携行缶での給油サービスがあります。</p>
<h2>燃費を改善するドライビングテクニック</h2>
<ul>
  <li><strong>急発進・急加速をやめる</strong>：燃費に最も直結する習慣</li>
  <li><strong>エンジンブレーキを活用</strong>：アクセルを離すだけで燃料噴射がカット</li>
  <li><strong>タイヤ空気圧を適正に保つ</strong>：低いと転がり抵抗が増し燃費悪化</li>
  <li><strong>エアコンをうまく使う</strong>：外気温に合わせてON/OFFを切り替える</li>
  <li><strong>不要な荷物を降ろす</strong>：100kgで燃費約1〜2%悪化</li>
</ul>
"@
        tags    = @("ガス欠","燃費改善","燃料警告灯","エコドライブ","ロードサービス")
    },
    @{
        title   = "雨天時のワイパーびびり・筋が残る原因と解消方法"
        excerpt = "雨の日にワイパーが効かない！ビビり音や拭き残しの原因とすぐできる対処法を解説。"
        content = @"
<h2>ワイパーびびりの原因</h2>
<p>ワイパーゴムの硬化・変形、ワイパーブレードの角度ずれ、撥水コーティング剤とゴムの相性などが主な原因です。気温が低い冬は特にゴムが硬くなりびびりが発生しやすくなります。</p>
<h2>すぐできる対処法</h2>
<ol>
  <li>ワイパーゴムの表面を濡らした布で拭く（汚れ・油膜を除去）</li>
  <li>アームの角度を確認・調整（ブレードがガラス面に均一に当たっているか）</li>
  <li>ワイパーゴム専用のコート剤を塗布（シリコン系が効果的）</li>
</ol>
<h2>ゴムの交換時期</h2>
<p>ワイパーゴムの交換目安は<strong>1年に1回（または5,000km）</strong>。ゴム部分だけ交換するタイプとブレード全体を交換するタイプがあります。カー用品店なら<strong>数百〜2,000円</strong>程度で購入でき、取り付けも簡単です。</p>
<h2>冬季の対策</h2>
<p>積雪地域では<strong>冬用ワイパー（スノーブレード）</strong>への交換が有効。通常のワイパーは雪が詰まって動かなくなることがあります。</p>
"@
        tags    = @("ワイパー","びびり音","雨天対策","ゴム交換","視界確保")
    },
    @{
        title   = "スリップ・横滑りを防ぐ冬道・雨道の安全運転テクニック"
        excerpt = "雨や雪道でのスリップ事故は一瞬で起きる。横滑り防止装置の仕組みと安全運転の要点を解説。"
        content = @"
<h2>スリップが起きる原因</h2>
<p>タイヤと路面の摩擦力を超えた制動・加速・コーナリングを行うとスリップが発生します。特に<strong>急ブレーキ・急ハンドル・急加速</strong>の「急」がつく操作が危険。</p>
<h2>VSC・ESC（横滑り防止装置）の活用</h2>
<p>現在の多くの車に搭載されている横滑り防止装置は、コーナリング中のスリップを感知して自動的にブレーキをかけ姿勢を安定させます。<strong>スポーツ走行時以外はOFFにしない</strong>ことが基本。</p>
<h2>雨道の安全運転</h2>
<ul>
  <li><strong>速度を10〜15km/h落とす</strong>：制動距離が大幅に伸びる</li>
  <li><strong>車間距離を2倍以上とる</strong>：濡れた路面は乾燥時より止まりにくい</li>
  <li><strong>ハイドロプレーニング注意</strong>：高速×浅いタイヤ溝で水の上を滑る現象。速度を落とし溝の残量を管理</li>
</ul>
<h2>冬道（雪・凍結）の注意</h2>
<p>スタッドレスタイヤへの早めの交換と、停止・発進時に<strong>ポンピングブレーキ</strong>（ABSなし車）またはブレーキを強く踏み続ける（ABS車）が有効です。</p>
"@
        tags    = @("スリップ防止","横滑り防止","雪道","安全運転","スタッドレス")
    }
)

# ===================================================
# HTMLテンプレートでラップ
# ===================================================
function Build-ArticleHtml($article, $category) {
    $date = Get-Date -Format "yyyy年M月d日"
    $catColor = if ($category -eq "カスタム情報") { "#e8001d" } else { "#0066cc" }
    $catIcon  = if ($category -eq "カスタム情報") { "🔧" } else { "🚨" }

    return @"
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$($article.title)</title>
</head>
<body>
<div style="max-width:720px;margin:0 auto;padding:1.5rem 1rem 3rem;font-family:'Hiragino Sans','Yu Gothic','Meiryo',sans-serif;color:#333;line-height:1.9;">

  <div style="background:linear-gradient(135deg,$catColor,#333);color:#fff;border-radius:12px;padding:2rem 1.5rem;margin-bottom:2rem;">
    <div style="display:inline-block;background:rgba(255,255,255,0.2);border-radius:20px;padding:0.2rem 1rem;font-size:0.85rem;margin-bottom:0.8rem;">$catIcon $category</div>
    <h1 style="margin:0 0 0.5rem;font-size:1.4rem;line-height:1.5;">$($article.title)</h1>
    <p style="margin:0;font-size:0.9rem;opacity:0.85;">$date 更新｜CARJAM自動車情報ブログ</p>
  </div>

  <div style="background:#f8f8f8;border-left:4px solid $catColor;border-radius:0 8px 8px 0;padding:1rem 1.2rem;margin-bottom:2rem;font-size:0.95rem;">
    $($article.excerpt)
  </div>

  $($article.content)

  <div style="margin-top:2rem;padding-top:1rem;border-top:1px solid #eee;font-size:0.85rem;color:#888;">
    <strong>タグ：</strong>$(($article.tags | ForEach-Object { "#$_" }) -join " ")
  </div>

</div>
</body>
</html>
"@
}

# ===================================================
# Claude APIで新規記事を生成（テンプレート枯渇後の恒久生成手段）
# 戻り値はテンプレートと同形式: @{title; excerpt; content(HTML); tags}
# ===================================================
function Invoke-ClaudeArticle($category, $existingTitles) {
    if (-not $CLAUDE_API_KEY -or $CLAUDE_API_KEY -match "ここに") {
        Write-Log "Claude記事生成スキップ: config.ps1 の CLAUDE_API_KEY が未設定"
        return $null
    }

    $titleList = ($existingTitles | ForEach-Object { "- $_" }) -join "`n"
    $prompt = @"
あなたは日本のカーイベント情報サイト「CARJAM」のブログライターです。カテゴリ「$category」の記事を1本書いてください。

条件:
- 読者は日本の車好き（初心者〜中級者）
- 文体は「です・ます」調で、親しみやすく実用的に
- content はHTML形式の本文。<h2>見出しを3〜5個使い、<p>段落、必要に応じて<ul><li>や<strong>を使う。800〜1200文字程度
- excerpt は記事カード用の紹介文（40〜60文字。「〜しよう」等の軽い呼びかけ可）
- title は30文字前後
- tags は日本語キーワードを4〜5個
- 以下の既存記事とテーマが重複しない、新しいテーマを選ぶこと:
$titleList
"@

    $schema = @{
        type = "object"
        properties = @{
            title   = @{ type = "string" }
            excerpt = @{ type = "string" }
            content = @{ type = "string" }
            tags    = @{ type = "array"; items = @{ type = "string" } }
        }
        required = @("title", "excerpt", "content", "tags")
        additionalProperties = $false
    }

    $body = @{
        model      = "claude-opus-4-8"
        max_tokens = 8000
        messages   = @(@{ role = "user"; content = $prompt })
        output_config = @{ format = @{ type = "json_schema"; schema = $schema } }
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "x-api-key"         = $CLAUDE_API_KEY
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }

    $res = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method POST -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300 -UseBasicParsing
    $json = [System.Text.Encoding]::UTF8.GetString($res.RawContentStream.ToArray()) | ConvertFrom-Json

    if ($json.stop_reason -ne "end_turn") {
        Write-Log "Claude記事生成中断: stop_reason=$($json.stop_reason)（$category）"
        return $null
    }
    $textBlock = $json.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1
    $article = $textBlock.text | ConvertFrom-Json

    Write-Log "Claude記事生成OK（$category）: $($article.title) [tokens in=$($json.usage.input_tokens) out=$($json.usage.output_tokens)]"
    return @{
        title   = $article.title
        excerpt = $article.excerpt
        content = $article.content
        tags    = @($article.tags)
    }
}

# ===================================================
# X(Twitter) OAuth 1.0a 投稿
# ===================================================
function Post-ToX($title, $hatenaUrl) {
    # キー未設定チェック
    if ($X_API_KEY -like "ここに*" -or $X_API_KEY -eq "") {
        Write-Log "X投稿スキップ: config.ps1 の X_API_KEY が未設定"
        return
    }

    # ツイート本文を組み立て（280文字制限）
    $hashtags = "#カーカスタム #車イベント #CARJAM"
    $base = "📝ブログ更新`n$title`n$hatenaUrl`n$hashtags"
    if ($base.Length -gt 280) {
        $overhead = "📝ブログ更新`n`n$hatenaUrl`n$hashtags".Length + 1
        $maxTitle = [Math]::Max(0, 280 - $overhead)
        $short = $title.Substring(0, [Math]::Min($title.Length, $maxTitle)).TrimEnd() + "…"
        $base = "📝ブログ更新`n$short`n$hatenaUrl`n$hashtags"
    }

    # OAuth 1.0a署名生成
    $method   = "POST"
    $url      = "https://api.twitter.com/2/tweets"
    $nonce    = [System.Guid]::NewGuid().ToString("N")
    $ts       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()

    # パーセントエンコード関数
    function Encode-Uri($s) {
        return [Uri]::EscapeDataString($s)
    }

    $oauthParams = [ordered]@{
        "oauth_consumer_key"     = $X_API_KEY
        "oauth_nonce"            = $nonce
        "oauth_signature_method" = "HMAC-SHA1"
        "oauth_timestamp"        = $ts
        "oauth_token"            = $X_ACCESS_TOKEN
        "oauth_version"          = "1.0"
    }

    # パラメータを辞書順でエンコード
    $paramStr = ($oauthParams.GetEnumerator() | Sort-Object Key | ForEach-Object {
        "$(Encode-Uri $_.Key)=$(Encode-Uri $_.Value)"
    }) -join "&"

    $baseString = "$method&$(Encode-Uri $url)&$(Encode-Uri $paramStr)"
    $signingKey  = "$(Encode-Uri $X_API_KEY_SECRET)&$(Encode-Uri $X_ACCESS_TOKEN_SECRET)"

    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = [System.Text.Encoding]::ASCII.GetBytes($signingKey)
    $sig = [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($baseString)))

    $oauthParams["oauth_signature"] = $sig
    $authHeader = "OAuth " + (($oauthParams.GetEnumerator() | Sort-Object Key | ForEach-Object {
        "$(Encode-Uri $_.Key)=`"$(Encode-Uri $_.Value)`""
    }) -join ", ")

    $body = '{"text":"' + ($base -replace '"','\"' -replace "`n",'\n') + '"}'

    $headers = @{
        "Authorization" = $authHeader
        "Content-Type"  = "application/json"
    }

    $res = Invoke-WebRequest -Uri $url -Method POST -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 -UseBasicParsing
    return $res
}

# ===================================================
# 記事生成メイン
# ===================================================
Write-Log "=== gen-blog.ps1 開始 ==="

# 既存の new-blog-posts.js を読み込む
$blogFile = "$PROJECT_ROOT\data\new-blog-posts.js"
$existingPosts = @()
if (Test-Path $blogFile) {
    $raw = Get-Content $blogFile -Raw -Encoding UTF8
    if ($raw -match 'window\.NEW_BLOG_POSTS\s*=\s*(\[[\s\S]*?\]);') {
        try { $existingPosts = $Matches[1] | ConvertFrom-Json } catch {}
    }
}

$nextId = $NEW_BLOG_START_ID
if ($existingPosts.Count -gt 0) {
    $maxId = ($existingPosts | Measure-Object -Property id -Maximum).Maximum
    if ($maxId -ge $nextId) { $nextId = $maxId + 1 }
}

$today = Get-Date -Format "yyyy-MM-dd"
$newPosts = @()

# 既に今日の記事が生成済みかチェック
$todayPosts = @($existingPosts | Where-Object { $_.date -eq $today })
# PS5.1では結果1件のとき .Count が $null になるため @() で配列化する
$hasCustom  = @($todayPosts | Where-Object { $_.category -eq "カスタム情報" }).Count -gt 0
$hasTrouble = @($todayPosts | Where-Object { $_.category -eq "車のトラブル解消" }).Count -gt 0

# 記事はClaude APIで新規生成する（テンプレート30本は全て掲載済みのため）
# 既存タイトル一覧を渡してテーマの重複を防ぐ
$existingTitles = @($existingPosts | ForEach-Object { $_.title })
$customArt  = $null
$troubleArt = $null
if (-not $hasCustom) {
    try { $customArt = Invoke-ClaudeArticle "カスタム情報" $existingTitles } catch { Write-Log "Claude記事生成エラー（カスタム情報）: $_" }
    if ($customArt) { $existingTitles += $customArt.title }
}
if (-not $hasTrouble) {
    try { $troubleArt = Invoke-ClaudeArticle "車のトラブル解消" $existingTitles } catch { Write-Log "Claude記事生成エラー（車のトラブル解消）: $_" }
}

# カスタム情報 記事を生成
if (-not $hasCustom -and $customArt) {
    Write-Log "カスタム情報 記事生成中: $($customArt.title)"
    try {
        $html = Build-ArticleHtml $customArt "カスタム情報"

        $post = [PSCustomObject]@{
            id       = $nextId
            category = "カスタム情報"
            date     = $today
            title    = $customArt.title
            excerpt  = $customArt.excerpt
            content  = $customArt.content
            tags     = $customArt.tags
        }
        $newPosts += $post
        $nextId++

        # はてなブログに投稿
        try {
            $res = Post-ToHatena $customArt.title $html "カスタム情報"
            Write-Log "はてなブログ投稿完了（カスタム情報）: $($customArt.title) [Status: $($res.StatusCode)]"
            # X(Twitter)に投稿
            try {
                $xUrl = if ($res.ArticleUrl) { $res.ArticleUrl } else { "https://$HATENA_BLOG_ID" }
                $xRes = Post-ToX $customArt.title $xUrl
                if ($xRes) { Write-Log "X投稿完了（カスタム情報）: [Status: $($xRes.StatusCode)]" }
            } catch {
                Write-Log "X投稿エラー（カスタム情報）: $_"
            }
        } catch {
            Write-Log "はてなブログ投稿エラー（カスタム情報）: $_"
        }

        Write-Log "カスタム情報 記事完了: $($customArt.title)"
    } catch {
        Write-Log "カスタム情報 生成エラー: $_"
    }
} else {
    if ($hasCustom) { Write-Log "カスタム情報 は今日生成済みのためスキップ" } else { Write-Log "カスタム情報 は記事生成できなかったためスキップ" }
}

# 車のトラブル解消 記事を生成
if (-not $hasTrouble -and $troubleArt) {
    Write-Log "車のトラブル解消 記事生成中: $($troubleArt.title)"
    try {
        $html = Build-ArticleHtml $troubleArt "車のトラブル解消"

        $post = [PSCustomObject]@{
            id       = $nextId
            category = "車のトラブル解消"
            date     = $today
            title    = $troubleArt.title
            excerpt  = $troubleArt.excerpt
            content  = $troubleArt.content
            tags     = $troubleArt.tags
        }
        $newPosts += $post
        $nextId++

        # はてなブログに投稿
        try {
            $res = Post-ToHatena $troubleArt.title $html "車のトラブル解消"
            Write-Log "はてなブログ投稿完了（車のトラブル解消）: $($troubleArt.title) [Status: $($res.StatusCode)]"
            # X(Twitter)に投稿
            try {
                $xUrl = if ($res.ArticleUrl) { $res.ArticleUrl } else { "https://$HATENA_BLOG_ID" }
                $xRes = Post-ToX $troubleArt.title $xUrl
                if ($xRes) { Write-Log "X投稿完了（車のトラブル解消）: [Status: $($xRes.StatusCode)]" }
            } catch {
                Write-Log "X投稿エラー（車のトラブル解消）: $_"
            }
        } catch {
            Write-Log "はてなブログ投稿エラー（車のトラブル解消）: $_"
        }

        Write-Log "車のトラブル解消 記事完了: $($troubleArt.title)"
    } catch {
        Write-Log "車のトラブル解消 生成エラー: $_"
    }
} else {
    if ($hasTrouble) { Write-Log "車のトラブル解消 は今日生成済みのためスキップ" } else { Write-Log "車のトラブル解消 は記事生成できなかったためスキップ" }
}

# new-blog-posts.js に追記
if ($newPosts.Count -gt 0) {
    $merged = @($existingPosts) + @($newPosts)
    $jsonPosts = $merged | ConvertTo-Json -Depth 5 -Compress
    if ($merged.Count -eq 1) { $jsonPosts = "[$jsonPosts]" }
    $jsContent = "// 自動更新される。scripts/gen-blog.ps1 が書き換える`nwindow.NEW_BLOG_POSTS = $jsonPosts;`n"
    [System.IO.File]::WriteAllText($blogFile, $jsContent, [System.Text.Encoding]::UTF8)
    Write-Log "new-blog-posts.js 更新: 合計 $($merged.Count) 件"

    # updates.js を更新
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

    $ann = [PSCustomObject]@{
        type    = "blog"
        count   = $newPosts.Count
        date    = $today
        message = "ブログ記事 $($newPosts.Count) 件を更新しました"
        names   = ($newPosts | ForEach-Object { $_.title }) -join "、"
    }
    $anns = @($currentUpdates.announcements) + @($ann)
    if ($anns.Count -gt 10) { $anns = $anns | Select-Object -Last 10 }
    $currentUpdates.announcements = $anns

    $updJson = $currentUpdates | ConvertTo-Json -Depth 5 -Compress
    $updJs = "// 自動更新される。scripts/check-events.ps1 / gen-blog.ps1 が書き換える`nwindow.SITE_UPDATES = $updJson;`n"
    [System.IO.File]::WriteAllText($updatesFile, $updJs, [System.Text.Encoding]::UTF8)
}

Write-Log "=== gen-blog.ps1 完了 (新規: $($newPosts.Count) 件) ==="
