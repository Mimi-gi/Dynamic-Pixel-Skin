using UnityEditor;
using UnityEngine;

namespace PixelSkin.EditorTools
{
    /// <summary>
    /// SkinSet の解像度整合バリデータ（決定1/11、spec §5）。
    /// BaseSkin ≤256² を検査し、設定済みの Shadow/Optional が BaseSkin と同一サイズかを検査する。
    /// 未設定（任意）スロットは検査対象外。
    /// </summary>
    [CustomEditor(typeof(SkinSet))]
    public class SkinSetEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();

            var s = (SkinSet)target;
            if (s.baseSkinLUT == null)
            {
                EditorGUILayout.HelpBox("BaseSkin LUT は必須です。", MessageType.Error);
                return;
            }

            int w = s.baseSkinLUT.width;
            int h = s.baseSkinLUT.height;

            if (w > 256 || h > 256)
            {
                EditorGUILayout.HelpBox($"BaseSkin 解像度 {w}x{h} が上限 256 を超えています（決定1）。", MessageType.Error);
            }

            CheckMatch(s.shadowLUT, "Shadow", w, h);
            CheckMatch(s.optionalLUT, "Optional", w, h);

            if (s.baseSkinLUT != null && w <= 256 && h <= 256 &&
                MatchOrNull(s.shadowLUT, w, h) && MatchOrNull(s.optionalLUT, w, h))
            {
                EditorGUILayout.HelpBox($"OK: {w}x{h}（設定済みLUTは整合）", MessageType.Info);
            }
        }

        private static void CheckMatch(Texture2D t, string name, int w, int h)
        {
            if (t == null) return; // 任意スロットは検査しない
            if (t.width != w || t.height != h)
            {
                EditorGUILayout.HelpBox(
                    $"{name} LUT の解像度 {t.width}x{t.height} が BaseSkin {w}x{h} と不一致です（決定11）。",
                    MessageType.Error);
            }
        }

        private static bool MatchOrNull(Texture2D t, int w, int h)
        {
            return t == null || (t.width == w && t.height == h);
        }
    }
}
