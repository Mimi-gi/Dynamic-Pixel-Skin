--- dictionary.lua
-- DirectionalSkin のピクセルグリッドから「指向性色 → BaseSkin座標(x,y)」の対応辞書を構築する。
-- 純粋なLua。Aseprite固有APIには依存しない。
--
-- グリッド表現（全モジュール共通）:
--   grid = {
--     width  = <integer>,
--     height = <integer>,
--     at = function(x, y) -> {r,g,b,a}   -- x:[0,width-1], y:[0,height-1], 左上原点(Aseprite native)
--   }
--
-- 座標はこの段階では Aseprite native（左上原点・top-down）のまま保持する。
-- Unity左下原点へのYフリップはベイク段階(baker.lua)で行う。

local color_util = require("modules.color_util")

local dictionary = {}

--- DirectionalSkin グリッドから辞書を構築する。
-- @param grid table 上記グリッド表現
-- @param alpha_threshold integer|nil 透明とみなすアルファ上限（既定 0）
-- @return table {
--   exact   = { [rgb_key] = {x=, y=} },        -- 完全一致用（代表座標＝重心）
--   entries = { {color={r,g,b,a}, x=, y=}, ... } -- 近傍一致用（代表色と代表座標の一覧）
-- }
function dictionary.build(grid, alpha_threshold)
  local buckets = {}       -- rgb_key -> {sumX, sumY, count, color}
  local order = {}         -- rgb_key の出現順（決定論的な entries 生成のため）

  for y = 0, grid.height - 1 do
    for x = 0, grid.width - 1 do
      local c = color_util.normalize(grid.at(x, y))
      if not color_util.is_transparent(c, alpha_threshold) then
        local key = color_util.rgb_key(c)
        local b = buckets[key]
        if b == nil then
          b = { sumX = 0, sumY = 0, count = 0, color = c }
          buckets[key] = b
          order[#order + 1] = key
        end
        b.sumX = b.sumX + x
        b.sumY = b.sumY + y
        b.count = b.count + 1
      end
    end
  end

  local exact = {}
  local entries = {}
  for _, key in ipairs(order) do
    local b = buckets[key]
    -- 重心（同色が複数座標にまたがる衝突を1点へ集約）
    local cx = math.floor(b.sumX / b.count + 0.5)
    local cy = math.floor(b.sumY / b.count + 0.5)
    exact[key] = { x = cx, y = cy }
    entries[#entries + 1] = { color = b.color, x = cx, y = cy }
  end

  return { exact = exact, entries = entries }
end

return dictionary
