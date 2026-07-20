--- lookup.lua
-- 指向性色から代表座標(x,y)を引く照合ロジック。
-- 完全一致モードと近傍一致モードの2種を提供する。純粋なLua、Aseprite非依存。

local color_util = require("modules.color_util")

local lookup = {}

lookup.MODE_EXACT = "exact"
lookup.MODE_NEAREST = "nearest"

--- 完全一致で座標を引く。
-- @param dict table dictionary.build の戻り値
-- @param c table 正規化済み色 {r,g,b,a}
-- @return table|nil {x=, y=}
function lookup.exact(dict, c)
  return dict.exact[color_util.rgb_key(c)]
end

--- 近傍一致（RGBユークリッド最近傍）で座標を引く。
-- しきい値を超える（似た色が無い）場合は nil を返す。
-- @param dict table dictionary.build の戻り値
-- @param c table 正規化済み色 {r,g,b,a}
-- @param max_dist2 number|nil 許容する距離の二乗。nil なら無制限（必ず最近傍を返す）
-- @return table|nil {x=, y=}
function lookup.nearest(dict, c, max_dist2)
  local best, best_d2 = nil, nil
  for _, e in ipairs(dict.entries) do
    local d2 = color_util.dist2(c, e.color)
    if best_d2 == nil or d2 < best_d2 then
      best_d2 = d2
      best = e
    end
  end
  if best == nil then return nil end
  if max_dist2 ~= nil and best_d2 > max_dist2 then return nil end
  return { x = best.x, y = best.y }
end

--- モード指定で座標を引く共通入口。
-- @param dict table dictionary.build の戻り値
-- @param c table 正規化済み色 {r,g,b,a}
-- @param opts table|nil { mode = MODE_EXACT|MODE_NEAREST, max_dist2 = number }
-- @return table|nil {x=, y=}
function lookup.resolve(dict, c, opts)
  opts = opts or {}
  local mode = opts.mode or lookup.MODE_EXACT
  if mode == lookup.MODE_NEAREST then
    return lookup.nearest(dict, c, opts.max_dist2)
  end
  return lookup.exact(dict, c)
end

return lookup
