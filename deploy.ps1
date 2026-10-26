# 用法（在 nav-worker 目录里，PowerShell）：
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1
# 需要先把 data.sql、dist.tar.gz、uploads.tar.gz 放在本目录。可重复运行。
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "失败：${what}（退出码 $LASTEXITCODE）" } }
function JsonFrom($text) { $i = $text.IndexOf('['); if ($i -lt 0) { return $null }; return ($text.Substring($i) | ConvertFrom-Json) }

Step '0. 检查环境'
node -v; Check 'Node.js 未安装，请先安装 Node.js LTS'
foreach ($f in 'data.sql', 'dist.tar.gz') {
  if (-not (Test-Path $f)) { throw "缺少文件 ${f}，请先从旧设备拷贝到当前目录" }
}

Step '1. 安装依赖'
if (-not (Test-Path node_modules)) { npm install; Check 'npm install' } else { Write-Host 'node_modules 已存在，跳过安装' }

Step '2. 准备前端文件和旧上传文件'
New-Item -ItemType Directory -Force public | Out-Null
tar xzf dist.tar.gz -C public --strip-components=1; Check '解压 dist.tar.gz'
if (-not (Test-Path 'public/index.html')) { throw 'public/index.html 不存在，dist.tar.gz 内容不对' }

Step '3. 登录 Cloudflare'
$who = (npx wrangler whoami 2>&1 | Out-String)
if ($who -match 'fetch request failed|connectivity') { throw '无法连接 Cloudflare API，请检查网络；如需代理，先执行：$env:HTTPS_PROXY="http://127.0.0.1:你的代理端口"' }
if ($who -notmatch 'You are logged in') { npx wrangler login; Check 'wrangler login' }
else { Write-Host '已登录 Cloudflare' }

Step '4. 创建 D1 数据库（已存在会自动跳过）'
npx wrangler d1 create nav-db 2>&1 | Out-Host
$list = JsonFrom ((npx wrangler d1 list --json 2>&1 | Out-String))
$db = $list | Where-Object { $_.name -eq 'nav-db' } | Select-Object -First 1
if (-not $db) { throw '没有找到名为 nav-db 的 D1 数据库' }
$toml = Get-Content wrangler.toml -Raw -Encoding UTF8
$toml = [regex]::Replace($toml, 'database_id\s*=\s*".*?"', "database_id = `"$($db.uuid)`"")
[IO.File]::WriteAllText("$PWD\wrangler.toml", $toml, (New-Object Text.UTF8Encoding $false))
Write-Host "database_id 已写入 wrangler.toml：$($db.uuid)"

Step '5. 建表'
npx wrangler d1 execute nav-db --remote --file=schema.sql; Check '执行 schema.sql'

Step '6. 导入数据（库里已有数据则跳过）'
$cnt = JsonFrom ((npx wrangler d1 execute nav-db --remote --json --command "SELECT COUNT(*) AS c FROM menus" 2>&1 | Out-String))
$existing = 0
if ($cnt) { $existing = [int]$cnt[0].results[0].c }
if ($existing -gt 0) { Write-Host "远端已有 $existing 个菜单，跳过 data.sql 导入" -ForegroundColor Yellow }
else { npx wrangler d1 execute nav-db --remote --file=data.sql; Check '导入 data.sql' }

Step '7. （已无需 R2，跳过）'

Step '8. 重设管理员密码（直接回车跳过）'
$sec = Read-Host '请输入新的管理员密码（至少6位，回车跳过）' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
if ($pw.Length -ge 6) {
  $env:ADMIN_PW = $pw
  node tools/hash.mjs; Check '生成密码哈希'
  npx wrangler d1 execute nav-db --remote --file=admin.sql; Check '写入管理员密码'
  Remove-Item admin.sql; Remove-Item Env:ADMIN_PW
  Write-Host '管理员密码已更新'
} else { Write-Host '已跳过（保留旧 bcrypt 密码，免费版可能因 CPU 限制登录失败）' -ForegroundColor Yellow }

Step '9. 部署 Worker'
npx wrangler deploy; Check 'wrangler deploy'

Step '10. 设置 JWT 密钥（已设置过则不动）'
$secrets = (npx wrangler secret list 2>&1 | Out-String)
if ($secrets -match 'JWT_SECRET') { Write-Host 'JWT_SECRET 已存在，保持不变' }
else {
  $secret = (node -e "console.log(require('crypto').randomBytes(32).toString('hex'))").Trim()
  $secret | npx wrangler secret put JWT_SECRET; Check '设置 JWT_SECRET'
}

Write-Host "`n完成。打开上面输出的 workers.dev 地址，登录后台验证。" -ForegroundColor Green
