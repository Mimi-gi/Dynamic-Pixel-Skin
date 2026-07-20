using UnityEditor;
using UnityEngine;

namespace PixelSkin.EditorTools
{
    /// <summary>
    /// UV Sprite → LUT デコード結果を Play mode に入らず確認する Editor Window（決定23、spec §7）。
    /// CPU 側でシェーダー(§3.2/§3.3)と同じ座標デコード・合成を再現する。
    /// 主目的は Yフリップ方向・座標整合の早期検証。
    /// 注: LUT は sRGB テクスチャのため厳密なリニア演算とは差があるが、座標検証には十分。
    /// 入力テクスチャは Read/Write 有効が必要（PixelSkin フォルダのインポータが自動で有効化）。
    /// </summary>
    public class LutDecodePreviewWindow : EditorWindow
    {
        private Texture2D uvSprite;
        private SkinSet skin;
        private Texture2D preview;
        private Vector2 scroll;
        private int zoom = 4;

        [MenuItem("Window/PixelSkin/LUT Decode Preview")]
        private static void Open()
        {
            GetWindow<LutDecodePreviewWindow>("PixelSkin Preview");
        }

        private void OnGUI()
        {
            EditorGUILayout.HelpBox(
                "UV Sprite（座標エンコード）と SkinSet を指定して Decode すると、シェーダーと同じ手順で" +
                "色を復元してプレビューします。Yフリップ・座標整合の確認用。", MessageType.None);

            uvSprite = (Texture2D)EditorGUILayout.ObjectField("UV Sprite", uvSprite, typeof(Texture2D), false);
            skin = (SkinSet)EditorGUILayout.ObjectField("Skin Set", skin, typeof(SkinSet), false);
            zoom = Mathf.Clamp(EditorGUILayout.IntSlider("Zoom", zoom, 1, 16), 1, 16);

            bool ready = uvSprite != null && skin != null && skin.baseSkinLUT != null;
            using (new EditorGUI.DisabledScope(!ready))
            {
                if (GUILayout.Button("Decode")) Decode();
            }

            if (preview != null)
            {
                EditorGUILayout.LabelField($"Result: {preview.width} x {preview.height}");
                scroll = EditorGUILayout.BeginScrollView(scroll);
                Rect r = GUILayoutUtility.GetRect(preview.width * zoom, preview.height * zoom,
                    GUILayout.ExpandWidth(false), GUILayout.ExpandHeight(false));
                EditorGUI.DrawPreviewTexture(r, preview);
                EditorGUILayout.EndScrollView();
            }
        }

        private void Decode()
        {
            if (!uvSprite.isReadable)
            {
                Debug.LogError("[PixelSkin] UV Sprite の Read/Write を有効にしてください。");
                return;
            }
            var baseLut = skin.baseSkinLUT;
            if (!baseLut.isReadable)
            {
                Debug.LogError("[PixelSkin] BaseSkin LUT の Read/Write を有効にしてください。");
                return;
            }

            int W = uvSprite.width, H = uvSprite.height;
            Color32[] uv = uvSprite.GetPixels32();

            int lw = baseLut.width, lh = baseLut.height;
            Color32[] basePx = baseLut.GetPixels32();

            Color32[] shadowPx = (skin.HasShadow && skin.shadowLUT.isReadable) ? skin.shadowLUT.GetPixels32() : null;
            Color32[] optPx = (skin.HasOptional && skin.optionalLUT.isReadable) ? skin.optionalLUT.GetPixels32() : null;
            if (skin.HasShadow && shadowPx == null)
                Debug.LogWarning("[PixelSkin] Shadow LUT が Read/Write 無効のためプレビューでは無視します。");
            if (skin.HasOptional && optPx == null)
                Debug.LogWarning("[PixelSkin] Optional LUT が Read/Write 無効のためプレビューでは無視します。");

            float shI = skin.HasShadow ? skin.defaultShadowIntensity : 0f;
            float opI = skin.HasOptional ? skin.defaultOptionalIntensity : 0f;
            bool additive = skin.defaultOptionalBlendMode == OptionalBlendMode.Additive;

            var outPx = new Color32[W * H];
            for (int idx = 0; idx < W * H; idx++)
            {
                Color32 s = uv[idx];
                if (s.a == 0) { outPx[idx] = new Color32(0, 0, 0, 0); continue; }

                // Color32 は raw バイト = 8bit座標そのもの（Yフリップ済み）
                int x = Mathf.Clamp(s.r, 0, lw - 1);
                int y = Mathf.Clamp(s.g, 0, lh - 1);
                int li = y * lw + x; // GetPixels32 は左下原点・行優先 → v が上方向に増えるのと一致

                Color b = basePx[li];
                Color col = b;

                if (shadowPx != null)
                {
                    Color sh = shadowPx[li];
                    col.r *= Mathf.Lerp(1f, sh.r, shI);
                    col.g *= Mathf.Lerp(1f, sh.g, shI);
                    col.b *= Mathf.Lerp(1f, sh.b, shI);
                }

                if (optPx != null)
                {
                    Color op = optPx[li];
                    if (additive)
                    {
                        col.r += op.r * op.a * opI;
                        col.g += op.g * op.a * opI;
                        col.b += op.b * op.a * opI;
                    }
                    else
                    {
                        col.r *= Mathf.Lerp(1f, op.r, opI);
                        col.g *= Mathf.Lerp(1f, op.g, opI);
                        col.b *= Mathf.Lerp(1f, op.b, opI);
                    }
                }

                col.a = 1f;
                outPx[idx] = col;
            }

            if (preview == null || preview.width != W || preview.height != H)
            {
                preview = new Texture2D(W, H, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point };
            }
            preview.SetPixels32(outPx);
            preview.Apply();
            Repaint();
        }
    }
}
