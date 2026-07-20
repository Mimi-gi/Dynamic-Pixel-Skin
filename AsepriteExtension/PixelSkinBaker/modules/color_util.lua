--- color_util.lua
-- 色の正規化・キー化・比較・色空間変換ヘルパー。
-- 純粋なLua。Aseprite固有API（app / Image / Color 等）には一切依存しない。
-- 色は「0..255 の整数 4 要素 {r, g, b, a}」を基本表現とする。

local color_util = {}

--- 値を [lo, hi] にクランプする。
-- @param v number
-- @param lo number
-- @param hi number
-- @return number
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
color_util.clamp = clamp

--- 実数を 0..255 の整数へ丸めてクランプする。
-- @param v number
-- @return integer
function color_util.to_byte(v)
  local n = math.floor(v + 0.5)
  return clamp(n, 0, 255)
end

--- {r,g,b,a} を正規化（各成分を 0..255 の整数へ）。
-- 入力に a が無い場合は不透明(255)とみなす。
-- @param c table {r,g,b[,a]}
-- @return table {r,g,b,a}
function color_util.normalize(c)
  return {
    r = color_util.to_byte(c.r or 0),
    g = color_util.to_byte(c.g or 0),
    b = color_util.to_byte(c.b or 0),
    a = color_util.to_byte(c.a == nil and 255 or c.a),
  }
end

--- 色を辞書キー用の文字列に変換する（RGBのみ。アルファは含めない）。
-- 完全一致辞書のキーとして使う。アルファはベイク側で別途透過判定するため、
-- ここではRGBが同じ色は同一キーに集約する。
-- @param c table 正規化済み {r,g,b,a}
-- @return string 例 "255,128,0"
function color_util.rgb_key(c)
  return string.format("%d,%d,%d", c.r, c.g, c.b)
end

--- 2色のRGBユークリッド距離の二乗を返す（平方根は取らない＝比較用途に十分）。
-- アルファは距離に含めない。
-- @param a table 正規化済み {r,g,b,a}
-- @param b table 正規化済み {r,g,b,a}
-- @return number
function color_util.dist2(a, b)
  local dr = a.r - b.r
  local dg = a.g - b.g
  local db = a.b - b.b
  return dr * dr + dg * dg + db * db
end

--- HSV → RGB 変換。
-- @param h number 色相 0..1（1で一周）
-- @param s number 彩度 0..1
-- @param v number 明度 0..1
-- @return table {r,g,b,a}（a=255固定、r/g/b は 0..255 整数）
function color_util.hsv_to_rgb(h, s, v)
  h = (h - math.floor(h)) * 6.0        -- 0..6
  local i = math.floor(h)
  local f = h - i
  local p = v * (1.0 - s)
  local q = v * (1.0 - s * f)
  local t = v * (1.0 - s * (1.0 - f))
  local r, g, b
  local sector = i % 6
  if sector == 0 then r, g, b = v, t, p
  elseif sector == 1 then r, g, b = q, v, p
  elseif sector == 2 then r, g, b = p, v, t
  elseif sector == 3 then r, g, b = p, q, v
  elseif sector == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return {
    r = color_util.to_byte(r * 255.0),
    g = color_util.to_byte(g * 255.0),
    b = color_util.to_byte(b * 255.0),
    a = 255,
  }
end

--- アルファがしきい値以下なら透明とみなす。
-- @param c table 正規化済み {r,g,b,a}
-- @param alpha_threshold integer|nil 既定 0（0のみ透明）。境界の半透明を弾きたい場合に上げる。
-- @return boolean
function color_util.is_transparent(c, alpha_threshold)
  local t = alpha_threshold or 0
  return c.a <= t
end

return color_util
