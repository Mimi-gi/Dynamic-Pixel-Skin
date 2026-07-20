using UnityEngine;

namespace PixelSkin
{
    /// <summary>
    /// 1キャラクターの LUT スキン制御（spec §4、決定7/22/26/27）。
    /// Renderer.material の自動複製でキャラ専用マテリアルインスタンスを持ち、
    /// SetSkin / Set*Intensity で LUT・パラメータを差し替える。
    /// MaterialPropertyBlock は使わない（SRP Batcher維持、決定・§5.1）。
    /// </summary>
    [RequireComponent(typeof(SpriteRenderer))]
    public class CharacterSkinController : MonoBehaviour
    {
        [SerializeField] private CharacterSkinLibrary library;
        [SerializeField] private SpriteRenderer spriteRenderer;
        [SerializeField] private Animator animator;
        [SerializeField] private int initialSkinIndex = 0;

        private Material mat; // spriteRenderer.material（初回アクセスで複製される）

        public int CurrentSkinIndex { get; private set; } = -1;
        public CharacterSkinLibrary Library => library;

        private void Reset()
        {
            spriteRenderer = GetComponent<SpriteRenderer>();
            animator = GetComponent<Animator>();
        }

        private void Awake()
        {
            if (spriteRenderer == null) spriteRenderer = GetComponent<SpriteRenderer>();
            EnsureMaterial();
            if (library != null && library.skins != null && library.skins.Count > 0)
            {
                SetSkin(Mathf.Clamp(initialSkinIndex, 0, library.skins.Count - 1));
            }
        }

        private void OnDestroy()
        {
            // 自動複製されたマテリアルインスタンスをリークさせない（決定26）
            if (mat != null)
            {
                if (Application.isPlaying) Destroy(mat);
                else DestroyImmediate(mat);
                mat = null;
            }
        }

        // ---- 公開API（決定22。命名は全キャラ共通=決定27）----

        /// <summary>library.skins[index] を現在のマテリアルへ適用する。</summary>
        public void SetSkin(int index)
        {
            if (library == null || library.skins == null ||
                index < 0 || index >= library.skins.Count)
            {
                Debug.LogWarning($"[PixelSkin] SetSkin: 無効なインデックス {index}", this);
                return;
            }

            var s = library.skins[index];
            if (s == null || s.baseSkinLUT == null)
            {
                Debug.LogWarning("[PixelSkin] SetSkin: SkinSet または baseSkinLUT が未設定です。", this);
                return;
            }

            EnsureMaterial();
            if (mat == null) return;

            mat.SetTexture(PixelSkinShaderProperties.BaseSkinLUT, s.baseSkinLUT);

            // 任意LUT: 未設定なら Intensity=0 で寄与を消す（未バインドの既定テクスチャでも安全）
            mat.SetTexture(PixelSkinShaderProperties.ShadowLUT, s.shadowLUT);
            mat.SetFloat(PixelSkinShaderProperties.ShadowIntensity,
                s.HasShadow ? s.defaultShadowIntensity : 0f);

            mat.SetTexture(PixelSkinShaderProperties.OptionalLUT, s.optionalLUT);
            mat.SetFloat(PixelSkinShaderProperties.OptionalIntensity,
                s.HasOptional ? s.defaultOptionalIntensity : 0f);
            mat.SetFloat(PixelSkinShaderProperties.OptionalBlendMode,
                (float)(int)s.defaultOptionalBlendMode);

            CurrentSkinIndex = index;
        }

        public void SetShadowIntensity(float value)
        {
            EnsureMaterial();
            if (mat != null) mat.SetFloat(PixelSkinShaderProperties.ShadowIntensity, value);
        }

        public void SetOptionalIntensity(float value)
        {
            EnsureMaterial();
            if (mat != null) mat.SetFloat(PixelSkinShaderProperties.OptionalIntensity, value);
        }

        public void SetOptionalBlendMode(OptionalBlendMode mode)
        {
            EnsureMaterial();
            if (mat != null) mat.SetFloat(PixelSkinShaderProperties.OptionalBlendMode, (float)(int)mode);
        }

        private void EnsureMaterial()
        {
            if (mat == null && spriteRenderer != null)
            {
                mat = spriteRenderer.material; // Unity が複製
            }
        }
    }
}
