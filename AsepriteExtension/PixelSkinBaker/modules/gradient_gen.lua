--- gradient_gen.lua
-- BaseSkin（不透明マスク）から DirectionalSkin を自動生成する純Luaコア。
-- Aseprite 非依存（グリッド入力・ピクセル配列出力）。
--
-- 手順:
--   1. 不透明ピクセルを連結成分でラベリングし「パーツ」に分割する
--      （接触＝同一パーツ。既定は4連結。8連結も選択可）。
--   2. 各パーツに色相を均等割り当てし、パーツ内はバウンディングボックス基準の
--      2軸グラデーション（X→彩度、Y→明度）で塗る。
--   → 各ピクセルが「視認しやすく」「パーツごとに色相帯で分離し」「パーツ内で
--      なるべく一意」な色を持つ。これがベイクの色→座標辞書の元になる。

local color_util = require("modules.color_util")

local gradient_gen = {}

local function is_opaque(grid, x, y, alpha_threshold)
  local c = grid.at(x, y)
  local a = c.a == nil and 255 or c.a
  return a > alpha_threshold
end

-- 連結成分ラベリング。labels[y*W+x+1] = 成分index(1..) または 0(背景)。
-- 成分は出現走査順（決定論的）に並ぶ。各成分の bbox も返す。
local function label_components(grid, alpha_threshold, connectivity)
  local W, H = grid.width, grid.height
  local labels = {}
  for i = 1, W * H do labels[i] = 0 end

  local neighbors
  if connectivity == 8 then
    neighbors = { {1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1} }
  else
    neighbors = { {1,0},{-1,0},{0,1},{0,-1} }
  end

  local components = {}  -- { {minx,miny,maxx,maxy, pixels={idx,...}}, ... }

  for sy = 0, H - 1 do
    for sx = 0, W - 1 do
      local sidx = sy * W + sx + 1
      if labels[sidx] == 0 and is_opaque(grid, sx, sy, alpha_threshold) then
        local label = #components + 1
        local comp = { minx = sx, miny = sy, maxx = sx, maxy = sy, pixels = {} }
        -- BFS/DFS
        local stack = { { sx, sy } }
        labels[sidx] = label
        while #stack > 0 do
          local node = stack[#stack]
          stack[#stack] = nil
          local x, y = node[1], node[2]
          local idx = y * W + x + 1
          comp.pixels[#comp.pixels + 1] = idx
          if x < comp.minx then comp.minx = x end
          if x > comp.maxx then comp.maxx = x end
          if y < comp.miny then comp.miny = y end
          if y > comp.maxy then comp.maxy = y end
          for _, d in ipairs(neighbors) do
            local nx, ny = x + d[1], y + d[2]
            if nx >= 0 and nx < W and ny >= 0 and ny < H then
              local nidx = ny * W + nx + 1
              if labels[nidx] == 0 and is_opaque(grid, nx, ny, alpha_threshold) then
                labels[nidx] = label
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
        components[label] = comp
      end
    end
  end

  return labels, components
end

--- DirectionalSkin を生成する。
-- @param grid table グリッド（BaseSkin）。at(x,y)->{r,g,b,a}
-- @param opts table|nil {
--   alpha_threshold = integer(既定0),
--   connectivity    = 4|8(既定4),
--   s_min,s_max     = number(彩度範囲, 既定 0.45..1.0),
--   v_min,v_max     = number(明度範囲, 既定 0.50..1.0),
--   hue_offset      = number(全体の色相オフセット, 既定0),
-- }
-- @return table { width, height, data={ [i]={r,g,b,a} }, part_count }
function gradient_gen.generate(grid, opts)
  opts = opts or {}
  local alpha_threshold = opts.alpha_threshold or 0
  local connectivity = opts.connectivity or 4
  local s_min = opts.s_min or 0.45
  local s_max = opts.s_max or 1.00
  local v_min = opts.v_min or 0.50
  local v_max = opts.v_max or 1.00
  local hue_offset = opts.hue_offset or 0.0

  local W, H = grid.width, grid.height
  local labels, components = label_components(grid, alpha_threshold, connectivity)
  local n = #components

  local data = {}
  for i = 1, W * H do data[i] = { r = 0, g = 0, b = 0, a = 0 } end

  for k = 1, n do
    local comp = components[k]
    -- 色相はパーツを均等に分割（1パーツなら赤=0）
    local hue = hue_offset + ((n > 1) and ((k - 1) / n) or 0.0)
    local den_x = math.max(1, comp.maxx - comp.minx)
    local den_y = math.max(1, comp.maxy - comp.miny)
    for _, idx in ipairs(comp.pixels) do
      local x = (idx - 1) % W
      local y = math.floor((idx - 1) / W)
      local lx = (x - comp.minx) / den_x   -- 0..1
      local ly = (y - comp.miny) / den_y   -- 0..1
      local s = s_min + (s_max - s_min) * lx
      local v = v_min + (v_max - v_min) * (1.0 - ly)
      data[idx] = color_util.hsv_to_rgb(hue, s, v)
    end
  end

  return { width = W, height = H, data = data, part_count = n }
end

return gradient_gen
