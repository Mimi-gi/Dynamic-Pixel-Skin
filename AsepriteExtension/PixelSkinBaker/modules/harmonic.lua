--- harmonic.lua
-- ドメイン（解く領域）と固定拘束（Dirichlet境界）から、ベクトル場を
-- 調和緩和（Laplace方程式のGauss-Seidel反復）でなめらかに埋める純Luaソルバ。
-- Aseprite 非依存。DirectionalAnimation 生成の内部補間に使う。
--
-- 座標は 0..W-1 / 0..H-1、インデックスは idx = y*W + x + 1（1始まり）。

local harmonic = {}

-- 4近傍のうちドメイン内のものを返すヘルパー。
local function domain_neighbors(x, y, W, H, in_domain)
  local ns = {}
  if x > 0 then local i = y * W + (x - 1) + 1; if in_domain[i] then ns[#ns+1] = i end end
  if x < W - 1 then local i = y * W + (x + 1) + 1; if in_domain[i] then ns[#ns+1] = i end end
  if y > 0 then local i = (y - 1) * W + x + 1; if in_domain[i] then ns[#ns+1] = i end end
  if y < H - 1 then local i = (y + 1) * W + x + 1; if in_domain[i] then ns[#ns+1] = i end end
  return ns
end

--- ベクトル場を調和緩和で解く。
-- @param W integer 幅
-- @param H integer 高さ
-- @param in_domain table 長さ W*H の bool 配列（解く領域）
-- @param fixed table 長さ W*H。fixed[idx] = {v1,...,vK}（固定拘束）または nil
-- @param num_fields integer ベクトル次元 K
-- @param opts table|nil { max_iter=2000, eps=0.01, weight_fn=function(idxA,idxB)->number }
-- @return table {
--   value  = { [idx] = {v1,...,vK} },   -- solved==true のピクセルのみ有効
--   solved = { [idx] = bool },          -- ドメイン内かつ拘束に到達可能なピクセル
--   iterations = integer,
--   reached_all = bool,                 -- ドメイン全体が拘束に到達したか
-- }
function harmonic.solve(W, H, in_domain, fixed, num_fields, opts)
  opts = opts or {}
  local max_iter = opts.max_iter or 2000
  local eps = opts.eps or 0.01
  local weight_fn = opts.weight_fn

  local N = W * H
  local value = {}
  local is_fixed = {}
  local solved = {}

  -- 固定拘束の合計（初期値・到達不能時のフォールバック用）
  local sum = {}
  for k = 1, num_fields do sum[k] = 0 end
  local fixed_count = 0
  for idx = 1, N do
    if fixed[idx] ~= nil then
      is_fixed[idx] = true
      local v = {}
      for k = 1, num_fields do v[k] = fixed[idx][k]; sum[k] = sum[k] + fixed[idx][k] end
      value[idx] = v
      fixed_count = fixed_count + 1
    end
  end
  if fixed_count == 0 then
    return { value = value, solved = solved, iterations = 0, reached_all = false }
  end
  local avg = {}
  for k = 1, num_fields do avg[k] = sum[k] / fixed_count end

  -- 到達可能性: 固定拘束からドメインを4連結BFSで塗る（拘束を含まない孤立領域を除外）
  local reachable = {}
  do
    local queue = {}
    for idx = 1, N do
      if is_fixed[idx] then reachable[idx] = true; queue[#queue+1] = idx end
    end
    local head = 1
    while head <= #queue do
      local idx = queue[head]; head = head + 1
      local x = (idx - 1) % W
      local y = math.floor((idx - 1) / W)
      for _, ni in ipairs(domain_neighbors(x, y, W, H, in_domain)) do
        if not reachable[ni] then reachable[ni] = true; queue[#queue+1] = ni end
      end
    end
  end

  -- 自由ピクセル（ドメイン内・非固定・到達可能）を列挙し初期化＋近傍キャッシュ
  local free = {}
  local nbr_cache = {}
  local reached_all = true
  for idx = 1, N do
    if in_domain[idx] then
      if not reachable[idx] then
        reached_all = false
      elseif not is_fixed[idx] then
        local x = (idx - 1) % W
        local y = math.floor((idx - 1) / W)
        nbr_cache[idx] = domain_neighbors(x, y, W, H, in_domain)
        local v = {}
        for k = 1, num_fields do v[k] = avg[k] end
        value[idx] = v
        free[#free+1] = idx
      end
    end
  end

  -- Gauss-Seidel 反復
  local iterations = 0
  for iter = 1, max_iter do
    iterations = iter
    local max_delta = 0
    for _, idx in ipairs(free) do
      local ns = nbr_cache[idx]
      local acc = {}
      for k = 1, num_fields do acc[k] = 0 end
      local wsum = 0
      for _, ni in ipairs(ns) do
        local w = weight_fn and weight_fn(idx, ni) or 1.0
        wsum = wsum + w
        local nv = value[ni]
        for k = 1, num_fields do acc[k] = acc[k] + w * nv[k] end
      end
      if wsum > 0 then
        local cur = value[idx]
        for k = 1, num_fields do
          local nvk = acc[k] / wsum
          local d = nvk - cur[k]
          if d < 0 then d = -d end
          if d > max_delta then max_delta = d end
          cur[k] = nvk
        end
      end
    end
    if max_delta < eps then break end
  end

  for _, idx in ipairs(free) do solved[idx] = true end
  for idx = 1, N do if is_fixed[idx] then solved[idx] = true end end

  return { value = value, solved = solved, iterations = iterations, reached_all = reached_all }
end

return harmonic
