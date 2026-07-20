# Unity側 実装仕様書（UV写像 LUT アニメーション ランタイム）

本書は `docs/architecture.md` §4–5 と確定済み設計判断（memory: project-pixel-skin-arch-decisions、決定1–11 / 20–27）を、Unity側の**実装可能な仕様**へ落とし込んだもの。Aseprite側（`UV Sprite` 生成まで）は完了しており、本書はその出力を受け取る**ランタイム＋Editorツール**の設計を対象とする。

> 実装前の必読: 本書と `docs/architecture.md`。矛盾する場合は memory の確定判断＞本書＞architecture.md の順で優先（architecture.md §4.2 のアトラス/`_UVRemap` は死んだ節。実装しない＝決定3）。

---

## 0. スコープ

- 対象: Unity `6000.5.4f1`（Unity 6）／URP `17.6.0`／PC専用／同時描画 5–6体（決定20, 24）。
- Unityの責務は**ランタイムの動的カラー割り当てと合成のみ**。ベイク・画像生成はしない（architecture.md §3.2）。
- **スコープ外**（実装しない）: Sprite Atlas と `_UVRemap`（決定3）、URP Light2D 統合（決定21）、キャラ全体のフェード/半透明（決定25）、オブジェクトプーリング（決定26）。
- Unityプロジェクトルート: `Dynammic-Pixel-Skin/`。本仕様の成果物は原則 `Assets/PixelSkin/` 配下に置く。

---

## 1. 入力アセットとインポート設定

### 1.1 UV Sprite（座標エンコード・アニメ本体）
- 中身: R=元スキンX / G=(スキン高-1)-元スキンY（Yフリップ済み）/ B=0 / A=有効フラグ（architecture.md §2.6、決定6）。**色ではなく座標**。
- インポート要件（決定2、専用インポートパイプラインで自動適用。手動設定に委ねない）:
  - **sRGB: 無効（Linear）** ← 座標値を正確に読むため必須。sRGBだと 8bit 値がガンマ変換され破綻する。
  - Filter: **Point**／Compression: **None**／Mipmap: **無効**／Wrap: **Clamp**。
  - Sprite Mode: **Multiple**（横ストリップのシートをフレーム分割）。Pixels Per Unit はスキン解像度に合わせる（別途統一）。
- 解像度上限 256×256（決定1、8bit座標エンコードに整合）。

### 1.2 LUT（BaseSkin / ShadowMap / OptionalMap）
- 実カラーテクスチャ（決定4のとおり固定3枚1組。OptionalMap=旧OptionalState、決定19）。
- インポート要件（決定8、UV Spriteとは**sRGBが逆**なので同一プリセット流用禁止）:
  - **sRGB: 有効**（通常のカラーテクスチャ）。
  - Filter: **Point**／Compression: **None**／Mipmap: **無効**／Wrap: **Clamp**（テクセル境界の色漏れ回避）。
  - Texture Type: **Default**（Spriteにしない。シェーダーのテクスチャプロパティに直接割り当てるため）。
- 全LUTは対応する BaseSkin と**同一解像度**であること（決定11でインポート時自動検証、§5）。

---

## 2. データモデル（ScriptableObject）

LUTとキャラ/スロットの紐付けは命名規則でなく**手作業のScriptableObject**（決定10）。スキンバリエーションは**リスト**で持つ（決定9）。

### 2.1 `SkinSet`（LUT・1バリエーション）
```
[CreateAssetMenu] class SkinSet : ScriptableObject
  string   displayName        // 表示用（"default","red"等）
  Texture2D baseSkinLUT        // 必須
  Texture2D shadowLUT          // 任意（未設定=影レイヤー無し）
  Texture2D optionalLUT        // 任意（未設定=Optionalレイヤー無し）
  // 対応パラメータも任意。該当LUTが未設定なら参照されない
  float    defaultShadowIntensity   = 1
  float    defaultOptionalIntensity = 1
  OptionalBlendMode defaultOptionalBlendMode  // Multiply / Additive
```
- **BaseSkin のみ必須**。ShadowLUT / OptionalLUT は任意で、未設定のスロットは描画に一切寄与しない
  （Controller が該当 Intensity を 0 にし、シェーダー側は乗算=×1・加算=+0 の恒等になる。§3.3/§4）。
- 対応パラメータ（`defaultShadowIntensity` 等）も、該当 LUT が未設定なら無視される。

### 2.2 `CharacterSkinLibrary`（1キャラの全バリエーション）
```
[CreateAssetMenu] class CharacterSkinLibrary : ScriptableObject
  string        characterId
  List<SkinSet> skins          // index が SetSkin(index) の引数（決定22）
```
- `SetSkin(index)` は `skins[index]` を解決してマテリアルへ適用（§4）。
- 3枚組の解像度整合は §5 のバリデータが SkinSet 単位で検査。

---

## 3. シェーダー仕様（URP 2D / 手書きHLSL・Unlit）

`Light2D` 非対応（決定21）なので **Sprite-Unlit 系のカスタムシェーダー**を手書きする（Shader Graph不使用: CBUFFER厳密制御とSRP Batcher整合のため）。

### 3.1 プロパティとCBUFFER（SRP Batcher厳守／決定・§5.2）
- **テクスチャはCBUFFER外**で宣言:
  - `_MainTex`（= UV Sprite。SpriteRendererが供給するスプライト本体）＋ `sampler_MainTex`
  - `_BaseSkinLUT` / `_ShadowLUT` / `_OptionalLUT` ＋ 各サンプラー
- **`CBUFFER_START(UnityPerMaterial)` 内**に全スカラー＋TexelSize:
  - `float4 _MainTex_ST`（Sprite描画の標準）
  - `float4 _BaseSkinLUT_TexelSize`（.z=幅px, .w=高さpx をデコードに使用。**SRP Batcher整合のためCBUFFER内に明示宣言**）
  - `half  _ShadowIntensity`
  - `half  _OptionalIntensity`
  - `int   _OptionalBlendMode`（0=乗算 / 1=加算。決定5・19。これ以上のブレンド汎用化はしない）
- **`MaterialPropertyBlock` は全面禁止**（決定・§5.1）。パラメータ差分は**キャラごとのマテリアルインスタンス**で持つ（§4）。

### 3.2 座標デコード（ハーフテクセル補正必須／architecture.md §4.1）
```hlsl
half4 src = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv); // UV Sprite
float w = _BaseSkinLUT_TexelSize.z;
float h = _BaseSkinLUT_TexelSize.w;
// 8bit値→整数インデックス復元。FP誤差で1つ下の座標に落ちないよう +0.5 して round 相当に。
float xi = floor(src.r * 255.0 + 0.5);
float yi = floor(src.g * 255.0 + 0.5);
// さらに +0.5 でテクセル中央を狙う（色漏れ対策）。分母は実LUTサイズ（256固定ではない）。
float2 lutUV = float2((xi + 0.5) / w, (yi + 0.5) / h);
```
- 原点はUnity基準（左下）で統一済み（決定6）。**シェーダー側でのV反転は不要**。
- 分母 `w/h` は `_BaseSkinLUT_TexelSize` の実ピクセルサイズ。256 は解像度上限であってUV分母ではない。
- 全LUTは同解像度なので TexelSize は BaseSkin のもの1つで足りる（決定11の整合保証が前提）。

### 3.3 マルチレイヤー合成（レイヤー種別ごとに決め打ち／architecture.md §4.2・決定5）
```hlsl
half4 baseCol = SAMPLE_TEXTURE2D(_BaseSkinLUT, sampler_BaseSkinLUT, lutUV);
half4 shadow  = SAMPLE_TEXTURE2D(_ShadowLUT,   sampler_ShadowLUT,   lutUV);
half4 opt     = SAMPLE_TEXTURE2D(_OptionalLUT, sampler_OptionalLUT, lutUV);

half3 col = baseCol.rgb;
col *= lerp(1.0.xxx, shadow.rgb, _ShadowIntensity);           // Shadow=乗算固定

half3 mul = lerp(1.0.xxx, opt.rgb, _OptionalIntensity);        // 経路0: 乗算
half3 add = opt.rgb * opt.a * _OptionalIntensity;              // 経路1: 加算
col = lerp(col * mul, col + add, (half)_OptionalBlendMode);    // 2経路のみ

return half4(col, 1.0) * src.a;                                // UV SpriteのAで有効画素をゲート
```
- 出力アルファは `src.a`（UV Sprite の有効フラグ）。照合失敗/未描画画素は透明（決定17整合）。
- ブレンドは Unlit・アルファブレンド想定。データ駆動ブレンドモード系は導入しない（決定5）。
- **任意LUT未設定の扱い**（§2.1）: シェーダーはキーワード分岐しない。`_ShadowIntensity` / `_OptionalIntensity`
  が 0 のとき各項は恒等（乗算×1・加算+0）になるため、Controller が未設定スロットの Intensity を 0 に
  すれば、そのLUTが未バインド（Unityの既定テクスチャ）でも結果に影響しない。SRP Batcher維持のため
  `multi_compile` キーワードは使わない。

---

## 4. ランタイムC#（`CharacterSkinController`）

1キャラ1コンポーネント。`Renderer.material` の自動複製で**キャラ専用マテリアルインスタンス**を持ち、`SetFloat/SetInt/SetTexture` で制御（決定7・22・26・27）。

```
class CharacterSkinController : MonoBehaviour
  [SerializeField] CharacterSkinLibrary library;
  [SerializeField] SpriteRenderer renderer;   // UV Sprite を再生
  [SerializeField] Animator animator;         // クリップ再生（命名規約§6）
  int currentSkinIndex;
  Material mat;   // renderer.material（初回アクセスで複製される）

  Awake():  mat = renderer.material; SetSkin(0);
  OnDestroy(): if (mat) Destroy(mat);         // 複製インスタンスのリーク防止（決定26）

  // --- 公開API（決定22。総称 SetSkin/SetParameter 形。命名は全キャラ共通=決定27）---
  void SetSkin(int index):
     var s = library.skins[index];
     mat.SetTexture(_BaseSkinLUT, s.baseSkinLUT);   // 必須
     // 任意LUT: 未設定なら Intensity=0 にして寄与を消す（§3.3）
     mat.SetTexture(_ShadowLUT,   s.shadowLUT);      // null可（既定テクスチャにバインド）
     mat.SetFloat(_ShadowIntensity, s.shadowLUT ? s.defaultShadowIntensity : 0f);
     mat.SetTexture(_OptionalLUT, s.optionalLUT);    // null可
     mat.SetFloat(_OptionalIntensity, s.optionalLUT ? s.defaultOptionalIntensity : 0f);
     mat.SetInt(_OptionalBlendMode, (int)s.defaultOptionalBlendMode);
     currentSkinIndex = index;

  // パラメータ操作（signatureはTBD=決定22。当面は明示メソッドで用意）
  void SetShadowIntensity(float v):   mat.SetFloat(_ShadowIntensity, v);
  void SetOptionalIntensity(float v): mat.SetFloat(_OptionalIntensity, v);
  void SetOptionalBlendMode(OptionalBlendMode m): mat.SetInt(_OptionalBlendMode,(int)m);
```
- Shaderプロパティ名は `static readonly int` の `Shader.PropertyToID` でキャッシュ。
- `MaterialPropertyBlock` は使わない（決定・§5.1）。SetSkin はテクスチャ差し替え＝マテリアルインスタンス自体を書き換える運用（architecture.md §5.2）。

---

## 5. カスタムインポータ / バリデーション（Editor）

- **UV Sprite 自動インポート**（決定2）: `AssetPostprocessor.OnPreprocessTexture` で、対象（フォルダ規約 例 `Assets/PixelSkin/UVSprites/` またはラベル）を判定し `sRGBTexture=false / filterMode=Point / textureCompression=None / mipmapEnabled=false / wrapMode=Clamp / spriteImportMode=Multiple` を強制。
- **LUT 自動インポート**（決定8）: 別フォルダ規約 例 `Assets/PixelSkin/LUTs/` で `sRGBTexture=true`（他はPoint/None/mipoff/Clamp、Type=Default）。UV Sprite と**分岐**する。
- **解像度整合バリデータ**（決定11）: SkinSet のインスペクタ拡張で、baseSkin と **設定済みの** shadow/optional が
  同一サイズかつ ≤256² かを検査し、不一致は HelpBox 警告。**未設定（任意）スロットは検査対象外**。人手のQAに委ねない。

---

## 6. Animator / アニメーション取り込み

- UV Sprite（横ストリップPNG）を Multiple スライス→フレームSpriteを生成し、`AnimationClip` で `SpriteRenderer.sprite` を差し替える標準的な2Dスプライトアニメとして再生。
- Animatorの**state名・パラメータ名は全キャラ共通の命名規約**（決定27）。`SetSkin(index)`/`SetParameter(value)` の総称APIが特別扱いなしで動く前提。
- 尺・fpsはクリップごと自由（決定15/標準化しない）。

---

## 7. Editorプレビューツール（決定23）

- Play modeに入らず UV Sprite→LUT デコード結果を確認する Editor Window。
- 入力: UV Sprite 1枚（or フレーム）＋ SkinSet。CPU側で §3.2 と同じデコード（`floor(r*255)+0.5` 相当）を再現し、合成結果をプレビュー描画。
- 目的: Yフリップ方向・座標整合・色漏れの早期検知（実機シェーダーと突き合わせる基準）。

---

## 8. ディレクトリ構成（提案）
```
Dynammic-Pixel-Skin/Assets/PixelSkin/
  Shaders/    PixelSkinLUT.shader (+ .hlsl include)
  Scripts/
    Runtime/  CharacterSkinController.cs, OptionalBlendMode.cs
    Data/     SkinSet.cs, CharacterSkinLibrary.cs
    Editor/   PixelSkinImportPostprocessor.cs, SkinSetValidator.cs, LutDecodePreviewWindow.cs
  UVSprites/  (UV Sprite PNG。インポータ規約フォルダ)
  LUTs/       (LUT PNG。インポータ規約フォルダ)
  Skins/      (SkinSet / CharacterSkinLibrary の .asset)
  Materials/  PixelSkinLUT.mat（ベースマテリアル）
```

---

## 9. 実装順序（フェーズ）と検証観点

1. **シェーダー** `PixelSkinLUT.shader`（§3）＋ベースマテリアル。まず1枚のUV Sprite＋手動割当LUTで静止デコードを確認 → **Yフリップ方向の実機確認**（memory積み残し）。
2. **データモデル** SkinSet / CharacterSkinLibrary（§2）。
3. **ランタイム** CharacterSkinController（§4）。SetSkin切替・破棄時マテリアル破棄・SRP Batcher維持（Frame Debuggerで確認）。
4. **インポータ＋バリデータ**（§5）。sRGBの正誤（UV=Linear / LUT=sRGB）を実データで確認。
5. **Editorプレビュー**（§7）。
6. **Animator結線**（§6）＋総称API疎通。

各段の最重要チェック: **(a) SRP Batcher に乗り続けているか**（MaterialPropertyBlock混入や CBUFFER 外変数で外れやすい）、**(b) UV Sprite が Point/Linear で読めているか**、**(c) +0.5 補正で色漏れが無いか**。

---

## 10. 未確定事項（実装時に確定 / 要相談）
- **U1**: UV Sprite シート→フレームSprite→AnimationClip の生成を手動運用にするか、Editorで自動生成するか（現状は手動想定）。
- **U2**: `SetParameter(value)` の最終シグネチャ（決定22はTBD）。当面 §4 の明示メソッドで代替。
- **U3**: DirectionalAnimation/UV Sprite の Pixels Per Unit と描画スケールの統一値。
- **U4**: インポータ対象の判定方式（フォルダ規約 vs アセットラベル vs `.uvsprite` 拡張規約）。
- **U5**: ベースシェーダーの土台（URP 2D の Sprite-Unlit パスを直接書くか、`Sprite-Unlit-Default` を改造するか）。
