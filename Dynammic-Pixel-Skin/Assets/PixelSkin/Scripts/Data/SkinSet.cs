using UnityEngine;

namespace PixelSkin
{
    /// <summary>
    /// 1スキンバリエーション分の LUT セット（決定4/9/10）。
    /// BaseSkin のみ必須。Shadow / Optional は任意で、未設定スロットは描画に寄与しない
    /// （Controller が該当 Intensity を 0 にし、シェーダーで恒等化。spec §3.3/§4）。
    /// </summary>
    [CreateAssetMenu(menuName = "PixelSkin/Skin Set", fileName = "SkinSet")]
    public class SkinSet : ScriptableObject
    {
        [Tooltip("表示名（default / red など）")]
        public string displayName = "default";

        [Header("LUT (BaseSkin は必須)")]
        public Texture2D baseSkinLUT;
        [Tooltip("任意。未設定なら影レイヤー無し")]
        public Texture2D shadowLUT;
        [Tooltip("任意。未設定なら Optional レイヤー無し")]
        public Texture2D optionalLUT;

        [Header("既定パラメータ (対応LUT未設定時は無視)")]
        [Range(0f, 1f)] public float defaultShadowIntensity = 1f;
        [Range(0f, 1f)] public float defaultOptionalIntensity = 1f;
        public OptionalBlendMode defaultOptionalBlendMode = OptionalBlendMode.Multiply;

        public bool HasShadow => shadowLUT != null;
        public bool HasOptional => optionalLUT != null;
    }
}
