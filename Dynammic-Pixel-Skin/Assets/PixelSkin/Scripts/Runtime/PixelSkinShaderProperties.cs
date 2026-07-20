using UnityEngine;

namespace PixelSkin
{
    /// <summary>
    /// PixelSkin/LUT シェーダーのプロパティ ID キャッシュ。
    /// 文字列名は PixelSkinLUT.shader と一致させること。
    /// </summary>
    public static class PixelSkinShaderProperties
    {
        public static readonly int BaseSkinLUT      = Shader.PropertyToID("_BaseSkinLUT");
        public static readonly int ShadowLUT        = Shader.PropertyToID("_ShadowLUT");
        public static readonly int OptionalLUT      = Shader.PropertyToID("_OptionalLUT");
        public static readonly int ShadowIntensity  = Shader.PropertyToID("_ShadowIntensity");
        public static readonly int OptionalIntensity= Shader.PropertyToID("_OptionalIntensity");
        public static readonly int OptionalBlendMode= Shader.PropertyToID("_OptionalBlendMode");
    }
}
