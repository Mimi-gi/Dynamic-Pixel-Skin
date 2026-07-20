--- baker.lua
-- ベイク中核。DirectionalAnimation の1フレーム（グリッド）と辞書から、
-- rgエンコードされた UV Sprite の1フレーム（ピクセル配列）を生成する。
-- 純粋なLua、Aseprite非依存。
--
-- 入力フレームは dictionary.lua と同じグリッド表現:
--   { width, height, at = function(x,y) -> {r,g,b,a} }   -- 左上原点(top-down)
--
-- 出力は行優先(top-down)のフラット配列:
--   { width, height, data = { [y*width + x + 1] = {r,g,b,a} } }
--
-- エンコード規約:
--   R = 元スキンのX座標 (0..255)
--   G = (skin_height - 1) - 元スキンのY座標   -- Unity左下原点へのYフリップ（決定6）
--   B = 0
--   A = 255（有効ピクセル） / 0（透明＝未描画 or ベイク失敗）

local color_util = require("modules.color_util")
local lookup = require("modules.lookup")

local baker = {}

local TRANSPARENT = { r = 0, g = 0, b = 0, a = 0 }

--- 1フレームをベイクする。
-- @param frame table グリッド表現（DirectionalAnimationの1フレーム）
-- @param dict table dictionary.build の戻り値
-- @param opts table {
--   skin_height     = <integer>,           -- 必須。Yフリップの基準（DirectionalSkinの高さ）
--   mode            = MODE_EXACT|MODE_NEAREST, -- 既定 MODE_EXACT
--   max_dist2       = number|nil,           -- 近傍一致モード時のしきい値（距離の二乗）
--   alpha_threshold = integer|nil,          -- 透明とみなすアルファ上限（既定 0）
-- }
-- @return table { width, height, data }
function baker.bake_frame(frame, dict, opts)
  assert(opts and opts.skin_height, "baker.bake_frame: opts.skin_height is required")
  local skin_height = opts.skin_height
  local alpha_threshold = opts.alpha_threshold or 0
  local resolve_opts = { mode = opts.mode or lookup.MODE_EXACT, max_dist2 = opts.max_dist2 }

  local W, H = frame.width, frame.height
  local data = {}

  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local idx = y * W + x + 1
      local c = color_util.normalize(frame.at(x, y))
      if color_util.is_transparent(c, alpha_threshold) then
        data[idx] = TRANSPARENT
      else
        local coord = lookup.resolve(dict, c, resolve_opts)
        if coord == nil then
          data[idx] = TRANSPARENT          -- ベイク失敗＝透明
        else
          local r = color_util.to_byte(coord.x)
          local g = color_util.to_byte((skin_height - 1) - coord.y)
          data[idx] = { r = r, g = g, b = 0, a = 255 }
        end
      end
    end
  end

  return { width = W, height = H, data = data }
end

--- 複数フレームを一括ベイクする薄いヘルパー。
-- @param frames table グリッドの配列
-- @param dict table
-- @param opts table baker.bake_frame と同じ
-- @return table 出力フレーム（{width,height,data}）の配列
function baker.bake_frames(frames, dict, opts)
  local out = {}
  for i, f in ipairs(frames) do
    out[i] = baker.bake_frame(f, dict, opts)
  end
  return out
end

return baker
