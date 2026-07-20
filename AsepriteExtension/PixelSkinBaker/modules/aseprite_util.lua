--- aseprite_util.lua
-- Aseprite Image <-> 純Luaグリッド の橋渡しと、レイヤー合成の共通ヘルパー。
-- Aseprite 固有API（app / Image）に依存する。複数コマンドから共有する。

local aseprite_util = {}

--- RGB画像の1ピクセルを {r,g,b,a} で返すグリッド（純Luaコアが受け取る形式）を作る。
function aseprite_util.image_to_grid(image)
  local pc = app.pixelColor
  return {
    width = image.width,
    height = image.height,
    at = function(x, y)
      local px = image:getPixel(x, y)
      return { r = pc.rgbaR(px), g = pc.rgbaG(px), b = pc.rgbaB(px), a = pc.rgbaA(px) }
    end,
  }
end

--- スプライトのレイヤー木を（グループ再帰しつつ）名前で探す。
-- 深さ優先で最初に名前が一致したレイヤー／グループを返す。無ければ nil。
local function find_layer_by_name(layers, name)
  for _, ly in ipairs(layers) do
    if ly.name == name then return ly end
    if ly.isGroup and ly.layers then
      local found = find_layer_by_name(ly.layers, name)
      if found ~= nil then return found end
    end
  end
  return nil
end

local function frame_no(frame)
  return (type(frame) == "table" and frame.frameNumber) or frame
end

-- レイヤー（またはグループ）を out へ下から順に合成する共通ルーチン。
-- check_vis=true のとき、そのレイヤー自身の可視性を尊重する。
-- exclude_name が一致するレイヤー／グループはスキップ。
local function composite_layer(out, layer, frame_number, check_vis, exclude_name)
  if check_vis and not layer.isVisible then return end
  if exclude_name and layer.name == exclude_name then return end
  if layer.isGroup then
    if layer.layers then
      for _, child in ipairs(layer.layers) do
        composite_layer(out, child, frame_number, true, exclude_name)  -- 配下の可視性は常に尊重
      end
    end
  elseif layer.isImage then
    local cel = layer:cel(frame_number)
    if cel ~= nil then
      out:drawImage(cel.image, cel.position)
    end
  end
end

--- スプライト木から名前でレイヤー／グループを探す（深さ優先）。無ければ nil。
function aseprite_util.find_layer(sprite, name)
  if name == nil or name == "" then return nil end
  return find_layer_by_name(sprite.layers, name)
end

--- 対象がレイヤーグループなら true。
function aseprite_util.is_group(layer)
  return layer ~= nil and layer.isGroup == true
end

--- グループ配下の全イメージレイヤーを下→上の順で返す（サブグループは再帰展開）。
-- 各要素は Aseprite の Layer オブジェクト（.name でパーツ名を参照できる）。
function aseprite_util.child_image_layers(group)
  local out = {}
  local function walk(g)
    if not g.layers then return end
    for _, ly in ipairs(g.layers) do
      if ly.isGroup then
        walk(ly)
      elseif ly.isImage then
        out[#out + 1] = ly
      end
    end
  end
  walk(group)
  return out
end

--- 単一レイヤー（またはグループ）オブジェクトを全キャンバスRGB画像へラスタライズする。
-- 対象自身の可視性は無視し、グループ配下の可視性は尊重する（flatten_frame の only_layer と同じ規約）。
function aseprite_util.rasterize_layer(sprite, layer, frame)
  local out = Image(sprite.width, sprite.height, ColorMode.RGB)
  out:clear()
  composite_layer(out, layer, frame_no(frame), false, nil)
  return out
end

--- 指定スプライトの、指定フレームの対象レイヤー群を全キャンバスRGB画像へ合成する。
-- opts:
--   only_layer    = <name>  該当レイヤー／グループが存在すればそれのみ使用。
--                           グループの場合は配下の全イメージレイヤーを合成する
--                           （＝BaseAnimation をパーツ別レイヤーのグループにできる）。
--                           ターゲット自身の可視性は無視するが、グループ配下の
--                           個々のレイヤーの可視性は尊重する（非表示パーツ＝そのフレームで不使用）。
--   exclude_layer = <name>  合成から除外するレイヤー／グループ名（only_layer 未指定時に有効）。
-- only_layer が無い場合は可視イメージレイヤーを（グループ再帰しつつ）下から順に合成。
-- ブレンドモード・不透明度は考慮しない（フラットなピクセルアート前提）。
function aseprite_util.flatten_frame(sprite, frame, opts)
  opts = opts or {}
  local out = Image(sprite.width, sprite.height, ColorMode.RGB)
  out:clear()

  local target = nil
  if opts.only_layer and opts.only_layer ~= "" then
    target = find_layer_by_name(sprite.layers, opts.only_layer)
  end

  local frame_number = frame_no(frame)

  if target ~= nil then
    composite_layer(out, target, frame_number, false, nil)  -- 自身の可視性は無視（配下は尊重）
  else
    for _, ly in ipairs(sprite.layers) do
      composite_layer(out, ly, frame_number, true, opts.exclude_layer)
    end
  end

  return out
end

--- {width,height,data(行優先 {r,g,b,a})} を Aseprite Image へ書き込む。
-- offset_x/offset_y だけずらして配置する（スプライトシート合成にも使う）。
function aseprite_util.write_pixels_to_image(out_image, frame, offset_x, offset_y)
  offset_x = offset_x or 0
  offset_y = offset_y or 0
  local pc = app.pixelColor
  local W = frame.width
  for y = 0, frame.height - 1 do
    for x = 0, W - 1 do
      local c = frame.data[y * W + x + 1]
      out_image:drawPixel(offset_x + x, offset_y + y, pc.rgba(c.r, c.g, c.b, c.a))
    end
  end
end

return aseprite_util
