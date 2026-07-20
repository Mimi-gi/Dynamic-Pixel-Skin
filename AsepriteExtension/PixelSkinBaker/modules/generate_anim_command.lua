--- generate_anim_command.lua
-- Aseprite API 層。アクティブなアニメスプライトの BaseAnimation / KeyPointAnimation
-- レイヤーと、外部 DirectionalSkin ファイルから、DirectionalAnimation レイヤーを
-- 調和補間で半自動生成する。純Luaコア dir_anim_gen を呼ぶ薄いラッパー。

local dictionary = require("modules.dictionary")
local lookup = require("modules.lookup")
local dir_anim_gen = require("modules.dir_anim_gen")
local aseprite_util = require("modules.aseprite_util")

local generate_anim_command = {}

local BASE_LAYER = "BaseAnimation"
local KEY_LAYER = "KeyPointAnimation"
local OUT_LAYER = "DirectionalAnimation"
local KEY_SUFFIX = "_key"

-- 出力レイヤーを取得（無ければ作成）し、指定フレームのセル画像を差し替える。
local function put_cel(sprite, layer, frame, img)
  local cel = layer:cel(frame.frameNumber)
  if cel ~= nil then
    cel.image = img
    cel.position = Point(0, 0)
  else
    sprite:newCel(layer, frame, img, Point(0, 0))
  end
end

local function ensure_layer(sprite, name)
  for _, ly in ipairs(sprite.layers) do
    if ly.name == name then return ly end
  end
  local ly = sprite:newLayer()
  ly.name = name
  return ly
end

local function run(params)
  local anim = params.anim_sprite

  -- DirectionalSkin を読み込み、辞書＋座標→色サンプリング用グリッドを用意
  local skin_sprite = Sprite{ fromFile = params.skin_path }
  if skin_sprite == nil then
    error("DirectionalSkin ファイルを開けませんでした: " .. tostring(params.skin_path))
  end
  local skin_image = aseprite_util.flatten_frame(
    skin_sprite, skin_sprite.frames[1], { only_layer = params.skin_layer })
  local dirskin_grid = aseprite_util.image_to_grid(skin_image)
  local dict = dictionary.build(dirskin_grid, 0)
  if #dict.entries == 0 then
    skin_sprite:close()
    error("DirectionalSkin から有効な色が見つかりませんでした。")
  end

  local gen_opts = {
    mode = params.mode,
    max_dist2 = params.max_dist2,
    harmonic = { max_iter = params.max_iter, eps = params.eps },
  }

  local acc = { constraints = 0, failed = 0, warned_islands = false, missing_keys = {} }

  -- gen 結果を part_img へ書き、out_img へアルファ合成（透明部は下を残す）。統計も集計。
  local function accumulate(out_img, gen)
    local part_img = Image(anim.width, anim.height, ColorMode.RGB)
    part_img:clear()
    aseprite_util.write_pixels_to_image(part_img, gen, 0, 0)
    out_img:drawImage(part_img)  -- 透明ピクセルは下の合成結果を残す（＝上のパーツが勝つ）
    acc.constraints = acc.constraints + gen.stats.constraints
    acc.failed = acc.failed + gen.stats.failed_decodes
    if not gen.stats.reached_all then acc.warned_islands = true end
  end

  local base_layer = aseprite_util.find_layer(anim, params.base_layer)
  local base_is_group = aseprite_util.is_group(base_layer)
  -- グループ時に処理する子イメージレイヤー（下→上）。単一レイヤー時は使わない。
  local parts = base_is_group and aseprite_util.child_image_layers(base_layer) or nil

  app.transaction("Generate DirectionalAnimation", function()
    local out_layer = ensure_layer(anim, OUT_LAYER)
    for _, frame in ipairs(anim.frames) do
      local out_img = Image(anim.width, anim.height, ColorMode.RGB)
      out_img:clear()

      if base_is_group then
        -- パーツ別: 各ベース子レイヤー <name> を、対応する <name><suffix> の
        -- KeyPoint と組にして独立に調和補間 → 下→上の順に合成する。
        local suffix = params.key_suffix
        for _, part in ipairs(parts) do
          -- 自身が接尾辞で終わるレイヤー（＝同居した KeyPoint）はベースパーツ扱いしない
          local is_key_layer = (#suffix > 0 and part.name:sub(-#suffix) == suffix)
          if not is_key_layer then
            local base_img = aseprite_util.rasterize_layer(anim, part, frame)
            local key_layer = aseprite_util.find_layer(anim, part.name .. suffix)
            local key_img
            if key_layer ~= nil then
              key_img = aseprite_util.rasterize_layer(anim, key_layer, frame)
            else
              key_img = Image(anim.width, anim.height, ColorMode.RGB)
              key_img:clear()  -- 対応KeyPoint無し＝拘束ゼロ（このパーツは透明のまま残る）
              acc.missing_keys[part.name] = true
            end
            local gen = dir_anim_gen.generate(
              aseprite_util.image_to_grid(base_img),
              aseprite_util.image_to_grid(key_img),
              dirskin_grid, dict, gen_opts)
            accumulate(out_img, gen)
          end
        end
      else
        -- 単一レイヤー: 従来どおりシルエット全体を1ドメインとして解く。
        local base_img = aseprite_util.flatten_frame(anim, frame, { only_layer = params.base_layer })
        local key_img = aseprite_util.flatten_frame(anim, frame, { only_layer = params.key_layer })
        local gen = dir_anim_gen.generate(
          aseprite_util.image_to_grid(base_img),
          aseprite_util.image_to_grid(key_img),
          dirskin_grid, dict, gen_opts)
        accumulate(out_img, gen)
      end

      put_cel(anim, out_layer, frame, out_img)
    end
  end)

  -- DirectionalSkin スプライトは閉じる（辞書・グリッドは読み取り済みだが、
  -- grid.at はクロージャで skin_image を参照するため、ここより後で使わないこと）
  skin_sprite:close()

  -- missing_keys を配列化
  local missing_list = {}
  for name in pairs(acc.missing_keys) do missing_list[#missing_list + 1] = name end

  return {
    constraints = acc.constraints,
    failed = acc.failed,
    warned_islands = acc.warned_islands,
    per_part = base_is_group,
    missing_keys = missing_list,
  }
end

function generate_anim_command.show_dialog()
  local anim = app.activeSprite
  if anim == nil then
    app.alert("BaseAnimation / KeyPointAnimation を含むアニメスプライトを開いてから実行してください。")
    return
  end
  if anim.colorMode ~= ColorMode.RGB then
    app.alert("スプライトを RGB カラーモードにしてください（Sprite > Color Mode > RGB）。")
    return
  end

  local dlg = Dialog("PixelSkin: Generate DirectionalAnimation")
  dlg:file{ id = "skin_path", label = "DirectionalSkin ファイル", open = true,
            filetypes = { "aseprite", "ase", "png" } }
  dlg:entry{ id = "base_layer", label = "BaseAnimation レイヤー/グループ名", text = BASE_LAYER }
  dlg:entry{ id = "key_layer", label = "KeyPoint レイヤー/グループ名(単一時)", text = KEY_LAYER }
  dlg:entry{ id = "key_suffix", label = "KeyPoint接尾辞(グループ時)", text = KEY_SUFFIX }
  dlg:entry{ id = "skin_layer", label = "Skin レイヤー名(任意)", text = "DirectionalSkin" }
  dlg:combobox{ id = "mode", label = "KeyPoint照合", option = "nearest", options = { "nearest", "exact" } }
  dlg:number{ id = "threshold", label = "近傍しきい値(距離)", text = "32", decimals = 0 }
  dlg:number{ id = "max_iter", label = "最大反復数", text = "2000", decimals = 0 }
  dlg:button{ id = "ok", text = "Generate" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  local d = dlg.data
  if not d.ok then return end
  if d.skin_path == nil or d.skin_path == "" then
    app.alert("DirectionalSkin ファイルを指定してください。")
    return
  end

  local threshold = tonumber(d.threshold) or 0
  local params = {
    anim_sprite = anim,
    skin_path = d.skin_path,
    base_layer = d.base_layer,
    key_layer = d.key_layer,
    key_suffix = (d.key_suffix ~= nil and d.key_suffix ~= "") and d.key_suffix or KEY_SUFFIX,
    skin_layer = d.skin_layer,
    mode = (d.mode == "exact") and lookup.MODE_EXACT or lookup.MODE_NEAREST,
    max_dist2 = (d.mode == "exact") and nil or (threshold * threshold),
    max_iter = tonumber(d.max_iter) or 2000,
    eps = 0.01,
  }

  local ok, result = pcall(run, params)
  if ok then
    app.refresh()
    local mode_label = result.per_part and "パーツ別（グループ）" or "一括（単一レイヤー）"
    local msg = string.format(
      "DirectionalAnimation を生成しました。\nモード: %s\n拘束点: %d / デコード失敗: %d",
      mode_label, result.constraints, result.failed)
    if result.missing_keys and #result.missing_keys > 0 then
      msg = msg .. "\n\n注意: 対応する KeyPoint レイヤー（<パーツ名>" .. params.key_suffix
        .. "）が見つからないパーツがあり、透明のままです:\n  " .. table.concat(result.missing_keys, ", ")
    end
    if result.warned_islands then
      msg = msg .. "\n\n注意: キーポイントに到達しない領域があり、その部分は透明のままです。\nその領域にキーポイントが1つも掛かっていない可能性があります（外縁だけでは値が決まりません）。\n領域内にキーポイントを置くか、外縁とキーポイントで領域がとじているか確認してください。"
    end
    app.alert(msg)
  else
    app.alert("生成失敗:\n" .. tostring(result))
  end
end

return generate_anim_command
