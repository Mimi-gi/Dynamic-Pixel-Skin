using UnityEditor;
using UnityEngine;

namespace PixelSkin.EditorTools
{
    /// <summary>
    /// UV Sprite / LUT のインポート設定を自動適用（決定2/8、spec §5）。
    /// フォルダ規約で判定し、UV Sprite=Linear・LUT=sRGB と正反対の色空間を強制する。
    /// 対象フォルダ:
    ///   Assets/PixelSkin/UVSprites/  → UV Sprite（座標エンコード, Linear, Sprite/Multiple）
    ///   Assets/PixelSkin/LUTs/       → LUT（実カラー, sRGB, Default）
    /// </summary>
    public class PixelSkinImportPostprocessor : AssetPostprocessor
    {
        private const string UVSpriteDir = "/PixelSkin/UVSprites/";
        private const string LutDir = "/PixelSkin/LUTs/";

        private void OnPreprocessTexture()
        {
            var importer = assetImporter as TextureImporter;
            if (importer == null) return;

            string p = assetPath.Replace('\\', '/');
            if (p.Contains(UVSpriteDir)) ConfigureUVSprite(importer);
            else if (p.Contains(LutDir)) ConfigureLut(importer);
        }

        private static void ConfigureUVSprite(TextureImporter t)
        {
            t.textureType = TextureImporterType.Sprite;
            t.spriteImportMode = SpriteImportMode.Multiple; // 横ストリップをフレーム分割
            t.sRGBTexture = false;                          // Linear: 座標値をそのまま読む（必須）
            t.filterMode = FilterMode.Point;
            t.mipmapEnabled = false;
            t.wrapMode = TextureWrapMode.Clamp;
            t.alphaIsTransparency = false;                  // Aは有効フラグ。ブリード補正しない
            t.isReadable = true;                            // Editorプレビュー/検証で CPU 読み取り
            t.textureCompression = TextureImporterCompression.Uncompressed;

            var ps = t.GetDefaultPlatformTextureSettings();
            ps.format = TextureImporterFormat.RGBA32;       // 8bit値を無損失で保持
            ps.textureCompression = TextureImporterCompression.Uncompressed;
            t.SetPlatformTextureSettings(ps);
        }

        private static void ConfigureLut(TextureImporter t)
        {
            t.textureType = TextureImporterType.Default;    // Spriteにしない（シェーダーへ直接割当）
            t.sRGBTexture = true;                           // 通常のカラーテクスチャ
            t.filterMode = FilterMode.Point;
            t.mipmapEnabled = false;
            t.wrapMode = TextureWrapMode.Clamp;             // テクセル境界の色漏れ回避
            t.isReadable = true;
            t.textureCompression = TextureImporterCompression.Uncompressed;
        }
    }
}
