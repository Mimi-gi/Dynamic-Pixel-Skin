--- bake_command.lua
-- Aseprite API 層。純Luaコア（dictionary / lookup / baker）を Aseprite の
-- Sprite / Image / Dialog と橋渡しする。ここだけが Aseprite 固有APIに依存する。
--
-- 処理の流れ:
--   1. ダイアログで DirectionalSkin ファイル・出力先・照合モード等を選択
--   2. DirectionalSkin を全キャンバス画像へ合成 → グリッド化 → 辞書構築
--   3. 現在のスプライトの各フレームの DirectionalAnimation を全キャンバス画像へ合成 → ベイク
--   4. 出力を横並びスプライトシートに合成し PNG エクスポート

local dictionary = require("modules.dictionary")
local lookup = require("modules.lookup")
local baker = require("modules.baker")
local aseprite_util = require("modules.aseprite_util")

local bake_command = {}

-- 既定のレイヤー名。該当レイヤーがあればそれのみを、無ければ可視レイヤー全てを使う。
local DEFAULT_SKIN_LAYER = "DirectionalSkin"
local DEFAULT_ANIM_LAYER = "DirectionalAnimation"

local image_to_grid = aseprite_util.image_to_grid

--------------------------------------------------------------------------------
-- ベイク実行
--------------------------------------------------------------------------------

-- @param params table {
--   skin_path, anim_sprite, skin_layer, anim_layer, output_path,
--   mode, max_dist2, alpha_threshold
-- }
local function run_bake(params)
  -- 1. DirectionalSkin を読み込み辞書化
  local skin_sprite = Sprite{ fromFile = params.skin_path }
  if skin_sprite == nil then
    error("DirectionalSkin ファイルを開けませんでした: " .. tostring(params.skin_path))
  end

  local skin_image = aseprite_util.flatten_frame(
    skin_sprite, skin_sprite.frames[1], { only_layer = params.skin_layer })
  local skin_height = skin_image.height
  local dict = dictionary.build(image_to_grid(skin_image), params.alpha_threshold)
  skin_sprite:close()

  if #dict.entries == 0 then
    error("DirectionalSkin から有効な色が見つかりませんでした（全て透明？レイヤー名は正しい？）")
  end

  -- 2. アニメーション各フレームをベイク
  local anim = params.anim_sprite
  local bake_opts = {
    skin_height = skin_height,
    mode = params.mode,
    max_dist2 = params.max_dist2,
    alpha_threshold = params.alpha_threshold,
  }

  local baked = {}
  for i, frame in ipairs(anim.frames) do
    local frame_image = aseprite_util.flatten_frame(anim, frame, { only_layer = params.anim_layer })
    baked[i] = baker.bake_frame(image_to_grid(frame_image), dict, bake_opts)
  end

  -- 3. 横並びスプライトシートへ合成し PNG エクスポート
  local n = #baked
  local frame_w, frame_h = anim.width, anim.height
  local sheet = Sprite(frame_w * n, frame_h, ColorMode.RGB)
  local sheet_image = Image(sheet.width, sheet.height, ColorMode.RGB)
  sheet_image:clear()
  for i = 1, n do
    aseprite_util.write_pixels_to_image(sheet_image, baked[i], (i - 1) * frame_w, 0)
  end
  sheet.cels[1].image = sheet_image
  sheet:saveCopyAs(params.output_path)
  sheet:close()

  return n
end

--------------------------------------------------------------------------------
-- ダイアログ
--------------------------------------------------------------------------------

function bake_command.show_dialog()
  local anim = app.activeSprite
  if anim == nil then
    app.alert("ベイク対象の DirectionalAnimation スプライトを開いてから実行してください。")
    return
  end
  if anim.colorMode ~= ColorMode.RGB then
    app.alert("スプライトを RGB カラーモードにしてから実行してください（Sprite > Color Mode > RGB）。")
    return
  end

  local dlg = Dialog("PixelSkin: Bake UV Sprite")
  dlg:file{
    id = "skin_path",
    label = "DirectionalSkin ファイル",
    open = true,
    filetypes = { "aseprite", "ase", "png" },
  }
  dlg:entry{ id = "skin_layer", label = "Skin レイヤー名(任意)", text = DEFAULT_SKIN_LAYER }
  dlg:entry{ id = "anim_layer", label = "Anim レイヤー名(任意)", text = DEFAULT_ANIM_LAYER }
  dlg:combobox{
    id = "mode",
    label = "照合モード",
    option = "exact",
    options = { "exact", "nearest" },
  }
  dlg:number{ id = "threshold", label = "近傍しきい値(距離)", text = "32", decimals = 0 }
  dlg:file{
    id = "output_path",
    label = "出力 PNG",
    save = true,
    filetypes = { "png" },
  }
  dlg:button{ id = "ok", text = "Bake" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  local d = dlg.data
  if not d.ok then return end
  if d.skin_path == nil or d.skin_path == "" then
    app.alert("DirectionalSkin ファイルを指定してください。")
    return
  end
  if d.output_path == nil or d.output_path == "" then
    app.alert("出力 PNG のパスを指定してください。")
    return
  end

  -- 近傍しきい値はユーザー入力が「色距離」なので二乗して渡す
  local threshold = tonumber(d.threshold) or 0
  local params = {
    skin_path = d.skin_path,
    anim_sprite = anim,
    skin_layer = d.skin_layer,
    anim_layer = d.anim_layer,
    output_path = d.output_path,
    mode = (d.mode == "nearest") and lookup.MODE_NEAREST or lookup.MODE_EXACT,
    max_dist2 = (d.mode == "nearest") and (threshold * threshold) or nil,
    alpha_threshold = 0,
  }

  local ok, result = pcall(run_bake, params)
  if ok then
    app.alert(string.format("ベイク完了: %d フレームを書き出しました。\n%s", result, params.output_path))
  else
    app.alert("ベイク失敗:\n" .. tostring(result))
  end
end

return bake_command
