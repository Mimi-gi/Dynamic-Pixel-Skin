# Pixel Skin Baker (Aseprite 拡張)

`DirectionalSkin`（指向性グラデーションで塗った展開図）と `DirectionalAnimation`
（それを同じ色規約で動かしたアニメーション）を色で照合し、各ピクセルに元スキン座標を
R/G チャンネルへエンコードした **UV Sprite** スプライトシート（PNG）を生成する。

## パイプライン上の位置づけ
- **BaseSkin**: スキンの展開図（ただの絵）。座標空間 (x,y) の定義元。ランタイムでは実カラー LUT。
- **DirectionalSkin**: BaseSkin の真上に、各パーツを白→黒グラデーション＋パーツ別の色相で塗ったもの。
  「指向性色 → BaseSkin座標(x,y)」の対応辞書の生成元。ベイク専用（ランタイム不使用）。
- **DirectionalAnimation**: DirectionalSkin と同じ色規約でキャラが動く姿を描いたアニメーション。ベイク入力。
- **UV Sprite（本ツールの出力）**: R = 元X座標, G = (skin高さ-1)-元Y座標（Unity 左下原点へのYフリップ）, B = 0,
  A = 255（有効）/ 0（透明＝未描画 or 照合失敗）。

詳細は `docs/architecture.md` を参照。

## インストール
`PixelSkinBaker` フォルダごと Aseprite の拡張として読み込む:
- Aseprite: Edit > Preferences > Extensions > Add Extension で本フォルダを圧縮した `.aseprite-extension`
  （= zip）を指定するか、開発中は
  `%APPDATA%/Aseprite/extensions/pixel-skin-baker/` にフォルダを配置して再起動する。

## 使い方

### コマンド1: Generate DirectionalSkin（DirectionalSkinの自動生成）
DirectionalSkin は手描きせず、BaseSkin から自動生成できます。
1. `BaseSkin`（展開図・ただの絵）を含むスプライト（RGBモード）を開いてアクティブにする。
2. File メニュー > **Generate DirectionalSkin (PixelSkin)** を実行。
3. `BaseSkin レイヤー名`（該当レイヤーがあればそれのみを対象、無ければ可視レイヤー全体）と
   `パーツ連結`（4=辺で接触を同一パーツ / 8=斜め接触も同一）を指定して Generate。
4. 同じスプライトに `DirectionalSkin` レイヤーが生成される（BaseSkinの不透明領域を連結成分で
   パーツ分割し、各パーツを色相帯＋2軸グラデーションで塗ったもの）。既存の同名レイヤーは上書き。

このレイヤーは「アニメを描くときにスポイトで色を拾う参照パレット」になります。

このレイヤーは「アニメを描くときにスポイトで色を拾う参照パレット」になり、次のコマンド2の
KeyPoint を描く色の元にもなります。

### コマンド2: Generate DirectionalAnimation（調和補間による半自動生成）
フレームごとに指向性の色を全面塗りする代わりに、**境界に少数のキーポイントを描くだけ**で
内部を調和補間（なめらか埋め）して DirectionalAnimation を半自動生成します。

各フレームに2つのレイヤー（または同名のレイヤーグループ）を用意します（アニメスプライト内、RGBモード）:
- **BaseAnimation**: 通常の手描きアニメ（実際の見た目）。非透明領域が「解消対象のシルエット」になる。
- **KeyPointAnimation**: DirectionalSkin の色（コマンド1の生成物からスポイト）で既知対応を描く。
  領域が**シルエットの外縁（＝ドメイン境界）またはキーポイントの閉曲線でとじていれば**よい。
  つまり外縁が壁になる部分はキーポイントで囲む必要はなく、外縁だけでは値が決まらない部分に
  キーポイント（線でも点でもよい）を置く。この alpha>0 のピクセルが「既知の対応（固定拘束）」になる。

**2つの運用モード（BaseAnimation が単一レイヤーかグループかで自動切替）:**
- **単一レイヤーモード**: `BaseAnimation` レイヤー1枚 ＋ `KeyPointAnimation` レイヤー1枚。
  シルエット全体を1つのドメインとして一括で調和補間する。単純な形に向く。
- **パーツ別モード（カットアウト向け・推奨）**: `BaseAnimation` を**レイヤーグループ**にし、配下に
  パーツ別レイヤー（例 `arm_L`, `body`, `leg_R`）を置く。各パーツに対応するキーポイントは
  **`<パーツ名>_key`**（例 `arm_L_key`）という名前のレイヤーで用意する（`KeyPointAnimation`
  グループ内でも、どこに置いてもよい。名前で対応付ける）。
  各パーツを**独立に**調和補間して個別の DirectionalMap を作り、レイヤー順（下→上）に合成する。
  → 隣接パーツ間で座標がにじまない。非表示パーツはそのフレームで無視。対応する `_key` が無い
  パーツは透明のまま残り、実行後に警告が出る。接尾辞 `_key` はダイアログで変更可。

```
パーツ別モードのレイヤー構成例:
  BaseAnimation        (グループ)      KeyPointAnimation   (グループ・任意)
   ├ arm_L                              ├ arm_L_key
   ├ body                               ├ body_key
   └ leg_R                              └ leg_R_key
```

手順:
1. アニメスプライトを開き、上記いずれかの構成でレイヤーを用意する。
2. File メニュー > **Generate DirectionalAnimation (PixelSkin)** を実行。
3. `DirectionalSkin ファイル`・各レイヤー/グループ名・`KeyPoint接尾辞`（グループ時、既定 `_key`）・
   `KeyPoint照合`（既定 nearest）・`近傍しきい値`・`最大反復数` を指定して Generate。
4. `DirectionalAnimation` レイヤーが全フレームに生成される。目視確認後、コマンド3（Bake）で rg 化する。

> **仕組み**: シルエットの外縁とキーポイントで塞がれた領域の内部を、既知対応から Laplace 方程式で
> なめらかに内挿します（前提: 領域は平面的でねじれ・折り曲げが無いこと）。外縁は自然境界（自由端）
> として扱われるため、領域を全周キーポイントで囲む必要はありません。ただし**その領域にキーポイントが
> 1つも掛かっていない**と値が決まらず透明のまま残ります（実行後に警告が出ます）。

> **注意（ワークフロー適合）**: この技術は本来、色付きパーツを動かすカットアウト方式と相性が
> 良いです。フレームバイフレーム手描きでも、上記コマンド2で「境界キーポイントだけ描く」ことで
> 全面塗りの手間を大きく減らせます。`nearest` 照合（色ブレ吸収）の併用を推奨します。

### コマンド3: Bake UV Sprite（UV Spriteの生成）
1. `DirectionalAnimation` のスプライト（RGBカラーモード）を Aseprite で開いてアクティブにする。
2. File メニュー > **Bake UV Sprite (PixelSkin)** を実行。
3. ダイアログで指定:
   - **DirectionalSkin ファイル**: 展開図の指向性レイヤーを含む `.aseprite`/`.png`。
   - **Skin レイヤー名 / Anim レイヤー名**: 該当名のレイヤーがあればそれのみを使用（BaseSkin の実カラーを
     混ぜないため）。無ければ可視レイヤー全てを合成。既定は `DirectionalSkin` / `DirectionalAnimation`。
   - **照合モード**: `exact`（完全一致、既定）/ `nearest`（近傍一致）。
   - **近傍しきい値**: `nearest` 時のみ有効な色距離（RGBユークリッド）。超過したピクセルは透明化。
   - **出力 PNG**: 生成する UV Sprite スプライトシート（横並び）。

## 実装構成
- `main.lua` — 拡張エントリ（init/exit・3コマンド登録）。
- **Aseprite 非依存の純Luaコア**:
  - `modules/color_util.lua` — 色の正規化・比較・HSV変換。
  - `modules/dictionary.lua` — 色→座標辞書の構築（重心集約）。
  - `modules/lookup.lua` — 完全一致／近傍一致。
  - `modules/baker.lua` — ベイク中核（rgエンコード＋Yフリップ）。
  - `modules/gradient_gen.lua` — DirectionalSkin自動生成（連結成分＋グラデーション）。
  - `modules/harmonic.lua` — 調和補間ソルバ（Laplaceなめらか埋め、到達不能領域検出）。
  - `modules/dir_anim_gen.lua` — DirectionalAnimation生成（KeyPoint拘束＋調和補間）。
- **Aseprite API 層**:
  - `modules/aseprite_util.lua` — Image⇔グリッド変換・レイヤー合成の共通ヘルパー。
  - `modules/bake_command.lua` — Bake UV Sprite コマンド。
  - `modules/generate_command.lua` — Generate DirectionalSkin コマンド。
  - `modules/generate_anim_command.lua` — Generate DirectionalAnimation コマンド。

純Luaコアのアルゴリズムは Python 移植による合成テストで検証済み（ベイク: Yフリップ・重心集約・
完全/近傍一致・透明処理／DirectionalSkin生成: 連結成分・パーツ別色相・パーツ内一意性／
調和補間: 線形拘束の内挿・4隅対称場・孤立領域検出／DirectionalAnimation生成: 全境界拘束での恒等再構成）。
ただし Aseprite API 層と実際の座標系整合（特にYフリップの向き）は、実機での目視確認が必要。
