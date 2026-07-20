// PixelSkin/LUT — UV写像 LUT ランタイムシェーダー（URP 2D / Unlit）
// UV Sprite(_MainTex) の R/G を LUT 座標として使い、BaseSkin/Shadow/Optional の
// 3枚を合成する。設計: docs/unity_implementation_spec.md §3、docs/architecture.md §4-5。
// - SRP Batcher維持: 全スカラーを UnityPerMaterial CBUFFER に、テクスチャは外。MaterialPropertyBlock禁止。
// - +0.5 ハーフテクセル補正で色漏れ回避。座標のYフリップは Aseprite 側で済（V反転しない）。
// - Shadow/Optional は任意: Intensity=0 で恒等になるためキーワード分岐不要。
Shader "PixelSkin/LUT"
{
    Properties
    {
        [PerRendererData] _MainTex ("UV Sprite", 2D) = "white" {}
        _BaseSkinLUT ("Base Skin LUT", 2D) = "white" {}
        _ShadowLUT ("Shadow LUT", 2D) = "white" {}
        _OptionalLUT ("Optional LUT", 2D) = "black" {}
        [Range(0,1)] _ShadowIntensity ("Shadow Intensity", Float) = 1
        [Range(0,1)] _OptionalIntensity ("Optional Intensity", Float) = 1
        [Enum(Multiply,0,Additive,1)] _OptionalBlendMode ("Optional Blend Mode", Float) = 0
        _Color ("Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags
        {
            "Queue"="Transparent"
            "RenderType"="Transparent"
            "RenderPipeline"="UniversalPipeline"
            "IgnoreProjector"="True"
            "PreviewType"="Plane"
            "CanUseSpriteAtlas"="False"
        }

        Cull Off
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Tags { "LightMode"="Universal2D" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float3 positionOS : POSITION;
                float4 color      : COLOR;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 color      : COLOR;
                float2 uv         : TEXCOORD0;
            };

            // テクスチャは CBUFFER の外（SRP Batcher 要件）
            TEXTURE2D(_MainTex);      SAMPLER(sampler_MainTex);
            TEXTURE2D(_BaseSkinLUT);  SAMPLER(sampler_BaseSkinLUT);
            TEXTURE2D(_ShadowLUT);    SAMPLER(sampler_ShadowLUT);
            TEXTURE2D(_OptionalLUT);  SAMPLER(sampler_OptionalLUT);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _BaseSkinLUT_TexelSize;   // .z=幅px, .w=高さpx（デコード分母）
                half   _ShadowIntensity;
                half   _OptionalIntensity;
                float  _OptionalBlendMode;       // 0=乗算, 1=加算
                half4  _Color;
            CBUFFER_END

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color * _Color;
                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                half4 src = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv); // UV Sprite (R=X,G=flipY,A=有効)

                // --- 座標デコード（+0.5 round で整数復元 → +0.5 でテクセル中央）---
                float w = _BaseSkinLUT_TexelSize.z;
                float h = _BaseSkinLUT_TexelSize.w;
                float xi = floor(src.r * 255.0 + 0.5);
                float yi = floor(src.g * 255.0 + 0.5);
                float2 lutUV = float2((xi + 0.5) / w, (yi + 0.5) / h);

                // --- 3レイヤーサンプリング ---
                half3 baseCol = SAMPLE_TEXTURE2D(_BaseSkinLUT, sampler_BaseSkinLUT, lutUV).rgb;
                half4 shadow  = SAMPLE_TEXTURE2D(_ShadowLUT,   sampler_ShadowLUT,   lutUV);
                half4 opt     = SAMPLE_TEXTURE2D(_OptionalLUT, sampler_OptionalLUT, lutUV);

                // --- 合成（Shadow=乗算固定 / Optional=乗算 or 加算の2経路）---
                half3 col = baseCol;
                col *= lerp(half3(1.0, 1.0, 1.0), shadow.rgb, _ShadowIntensity);

                half3 optMul = lerp(half3(1.0, 1.0, 1.0), opt.rgb, _OptionalIntensity);
                half3 optAdd = opt.rgb * opt.a * _OptionalIntensity;
                col = lerp(col * optMul, col + optAdd, _OptionalBlendMode);

                half4 outCol = half4(col, 1.0) * src.a;  // UV Sprite の A で有効画素をゲート
                outCol *= i.color;                        // スプライトTint / 頂点カラー
                return outCol;
            }
            ENDHLSL
        }
    }

    Fallback Off
}
