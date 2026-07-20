--- main.lua
-- PixelSkinBaker Aseprite 拡張のエントリポイント。
-- init/exit ライフサイクルと、メニューコマンドの登録を担う。

-- この拡張フォルダを package.path へ追加し、./modules/*.lua を require できるようにする。
-- （debug.getinfo で main.lua 自身の場所を求める。区切りは "/" 統一で Windows でも動作する）
local function setup_paths()
  local src = debug.getinfo(1, "S").source:sub(2) -- 先頭の '@' を除去
  local dir = src:match("^(.*[/\\])") or ("." .. "/")
  dir = dir:gsub("\\", "/")
  package.path = dir .. "?.lua;" .. dir .. "modules/?.lua;" .. package.path
end

function init(plugin)
  setup_paths()
  local bake_command = require("modules.bake_command")
  local generate_command = require("modules.generate_command")
  local generate_anim_command = require("modules.generate_anim_command")

  plugin:newCommand{
    id = "PixelSkinGenerateDirectionalSkin",
    title = "Generate DirectionalSkin (PixelSkin)",
    group = "file_export",
    onclick = function()
      generate_command.show_dialog()
    end,
  }

  plugin:newCommand{
    id = "PixelSkinGenerateDirectionalAnimation",
    title = "Generate DirectionalAnimation (PixelSkin)",
    group = "file_export",
    onclick = function()
      generate_anim_command.show_dialog()
    end,
  }

  plugin:newCommand{
    id = "PixelSkinBakeUVSprite",
    title = "Bake UV Sprite (PixelSkin)",
    group = "file_export",
    onclick = function()
      bake_command.show_dialog()
    end,
  }
end

function exit(plugin)
  -- 現状クリーンアップ対象なし
end
