namespace PixelSkin
{
    /// <summary>
    /// OptionalMap レイヤーの合成モード（決定5・19）。乗算 / 加算の2経路のみ。
    /// 値はシェーダー _OptionalBlendMode に (float) で渡す（0=乗算, 1=加算）。
    /// </summary>
    public enum OptionalBlendMode
    {
        Multiply = 0,
        Additive = 1,
    }
}
