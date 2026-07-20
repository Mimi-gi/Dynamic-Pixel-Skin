--- generate_command.lua
-- Aseprite API 層。アクティブスプライト（BaseSkin を含む）から DirectionalSkin を
-- 自動生成し、"DirectionalSkin" レイヤーへ書き込む。
--
-- 純Luaコア gradient_gen を呼び出す薄いラッパー。

local gradient_gen = require("modules.gradient_gen")
local aseprite_util = require("modules.aseprite_util")

local generate_command = {}

local DIR_SKIN_LAYER = "DirectionalSkin"
local BASE_SKIN_LAYER = "BaseSkin"

-- data(行優先{r,g,b,a}) から新しい RGB Image を作る。
local function pixels_to_image(gen)
  local img = Image(gen.width, gen.height, ColorMode.RGB)
  img:clear()
  aseprite_util.write_pixels_to_image(img, gen, 0, 0)
  return img
end

-- "DirectionalSkin" レイヤーを取得（無ければ作成）し、frame1 のセル画像を差し替える。
local function put_directional_layer(sprite, img)
  local layer = nil
  for _, ly in ipairs(sprite.layers) do
    if ly.name == DIR_SKIN_LAYER then layer = ly break end
  end
  if layer == nil then
    layer = sprite:newLayer()
    layer.name = DIR_SKIN_LAYER
  end
  local frame1 = sprite.frames[1]
  local cel = layer:cel(frame1.frameNumber)
  if cel ~= nil then
    cel.image = img
    cel.position = Point(0, 0)
  else
    sprite:newCel(layer, frame1, img, Point(0, 0))
  end
  return layer
end

function generate_command.show_dialog()
  local sprite = app.activeSprite
  if sprite == nil then
    app.alert("BaseSkin を含むスプライトを開いてから実行してください。")
    return
  end
  if sprite.colorMode ~= ColorMode.RGB then
    app.alert("スプライトを RGB カラーモードにしてください（Sprite > Color Mode > RGB）。")
    return
  end

  local dlg = Dialog("PixelSkin: Generate DirectionalSkin")
  dlg:entry{ id = "base_layer", label = "BaseSkin レイヤー名(任意)", text = BASE_SKIN_LAYER }
  dlg:combobox{ id = "connectivity", label = "パーツ連結", option = "4", options = { "4", "8" } }
  dlg:label{ label = "", text = "既存の DirectionalSkin レイヤーは上書きされます" }
  dlg:button{ id = "ok", text = "Generate" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  local d = dlg.data
  if not d.ok then return end

  local ok, result = pcall(function()
    -- BaseSkin マスクを合成（DirectionalSkin レイヤー自身は入力から除外）
    local base_image = aseprite_util.flatten_frame(sprite, sprite.frames[1], {
      only_layer = d.base_layer,
      exclude_layer = DIR_SKIN_LAYER,
    })
    local gen = gradient_gen.generate(aseprite_util.image_to_grid(base_image), {
      connectivity = tonumber(d.connectivity) or 4,
    })
    if gen.part_count == 0 then
      error("不透明ピクセルが見つかりませんでした（BaseSkin レイヤー名は正しい？）")
    end
    local img = pixels_to_image(gen)
    app.transaction("Generate DirectionalSkin", function()
      put_directional_layer(sprite, img)
    end)
    app.refresh()
    return gen.part_count
  end)

  if ok then
    app.alert(string.format(
      "DirectionalSkin を生成しました（パーツ数: %d）。\nこのレイヤーの色をスポイトで拾ってアニメを描いてください。",
      result))
  else
    app.alert("生成失敗:\n" .. tostring(result))
  end
end

return generate_command
