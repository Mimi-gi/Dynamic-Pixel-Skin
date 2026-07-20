--- dir_anim_gen.lua
-- BaseAnimation（シルエット）＋ KeyPointAnimation（DirectionalSkin色の既知対応）＋
-- DirectionalSkin から、1フレーム分の DirectionalAnimation（DirectionalSkin色）を
-- 調和補間で生成する純Luaコア。Aseprite 非依存。

local color_util = require("modules.color_util")
local lookup = require("modules.lookup")
local harmonic = require("modules.harmonic")

local dir_anim_gen = {}

local TRANSPARENT = { r = 0, g = 0, b = 0, a = 0 }

local function clampi(v, lo, hi)
  v = math.floor(v + 0.5)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- 1フレーム生成。
-- @param base_grid table BaseAnimation グリッド（非透明＝シルエット）
-- @param keypoint_grid table KeyPointAnimation グリッド（非透明＝固定拘束、DirectionalSkin色）
-- @param dirskin_grid table DirectionalSkin グリッド（座標→色サンプリング元）
-- @param dict table dictionary.build(dirskin_grid) の戻り値（KeyPoint色のデコード用）
-- @param opts table|nil {
--   alpha_threshold = integer(既定0),
--   mode            = lookup.MODE_*（既定 nearest）,
--   max_dist2       = number|nil（nearest時の許容距離二乗）,
--   harmonic        = table（harmonic.solve の opts）,
-- }
-- @return table { width, height, data, stats }
function dir_anim_gen.generate(base_grid, keypoint_grid, dirskin_grid, dict, opts)
  opts = opts or {}
  local at = opts.alpha_threshold or 0
  local resolve_opts = {
    mode = opts.mode or lookup.MODE_NEAREST,
    max_dist2 = opts.max_dist2,
  }

  local W, H = base_grid.width, base_grid.height
  local skinW, skinH = dirskin_grid.width, dirskin_grid.height
  local N = W * H

  -- ドメイン = BaseAnimation 非透明 ∪ KeyPointAnimation 非透明
  local in_domain = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local idx = y * W + x + 1
      local bc = color_util.normalize(base_grid.at(x, y))
      local kc = color_util.normalize(keypoint_grid.at(x, y))
      in_domain[idx] = (not color_util.is_transparent(bc, at))
        or (not color_util.is_transparent(kc, at))
    end
  end

  -- 固定拘束 = KeyPoint 非透明ピクセルの色をスキン座標へデコード
  local fixed = {}
  local constraints, failed = 0, 0
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local idx = y * W + x + 1
      local kc = color_util.normalize(keypoint_grid.at(x, y))
      if not color_util.is_transparent(kc, at) then
        local coord = lookup.resolve(dict, kc, resolve_opts)
        if coord ~= nil then
          fixed[idx] = { coord.x, coord.y }
          constraints = constraints + 1
        else
          failed = failed + 1
        end
      end
    end
  end

  -- 調和補間でスキン座標場(fx,fy)を解く
  local field = harmonic.solve(W, H, in_domain, fixed, 2, opts.harmonic)

  -- 座標場 → DirectionalSkin 色サンプリング → 出力
  local data = {}
  local resolved_pixels = 0
  for idx = 1, N do
    local out = TRANSPARENT
    if field.solved[idx] then
      local v = field.value[idx]
      local sx = clampi(v[1], 0, skinW - 1)
      local sy = clampi(v[2], 0, skinH - 1)
      local c = color_util.normalize(dirskin_grid.at(sx, sy))
      if not color_util.is_transparent(c, at) then
        out = { r = c.r, g = c.g, b = c.b, a = 255 }
        resolved_pixels = resolved_pixels + 1
      end
    end
    data[idx] = out
  end

  return {
    width = W,
    height = H,
    data = data,
    stats = {
      constraints = constraints,
      failed_decodes = failed,
      resolved_pixels = resolved_pixels,
      reached_all = field.reached_all,
      iterations = field.iterations,
    },
  }
end

return dir_anim_gen
