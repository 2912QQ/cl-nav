# 导航站（Cloudflare Workers 版）

基于 [eooce/nav-item](https://github.com/eooce/nav-item) 的 Cloudflare Workers 移植版。原项目是 Node.js + Express + SQLite，本项目把后端重写成 Worker，数据存放在 D1，上传的图片存放在 KV，**不需要自己的服务器**，连接 GitHub 即可自动部署。

## 功能

- 分类 / 子分类 / 卡片管理，支持分类加密（访问密码）
- 广告位、友情链接
- 书签导入导出（JSON，以及浏览器导出的 HTML 书签）
- 后台更换壁纸：上传图片，或填写图片 URL，支持恢复默认
- 管理员登录、修改密码、显示上次登录时间和 IP

## 工作方式

| 部分 | 实现 |
|---|---|
| 前端 | `public/` 里编译好的静态文件，由 Workers Static Assets 托管 |
| 后端 API | `src/index.js`（Hono），接口与原项目保持一致 |
| 数据库 | Cloudflare D1，首次访问时自动建表 |
| 图片存储 | Cloudflare KV（单张最大 10MB） |
| 登录 | JWT，有效期 2 小时；密码使用 PBKDF2 哈希 |

## 部署

### 1. 准备仓库

Fork 本仓库，或把代码推送到你自己的 GitHub 仓库。`public/` 目录必须包含前端编译文件（`index.html`、`assets/` 等）。

### 2. 在 Cloudflare 连接仓库

1. 打开 Cloudflare 后台，进入 **Workers & Pages → Create → Import a repository**。
2. 授权 GitHub，选择该仓库，分支选 `main`。
3. 项目名称填 `cl-nav`，**必须和 `wrangler.toml` 里的 `name` 一致**，想用别的名字就同时修改两处。
4. 构建命令留空，部署命令填 `npx wrangler deploy`，保存并部署。

D1 数据库和 KV 命名空间**不需要手动创建**。`wrangler.toml` 里只声明了绑定、没有写 ID，首次部署时 Cloudflare 会自动创建并绑定。

### 3. 设置环境变量

Worker 页面 → **Settings → Variables and Secrets**，添加：

| 名称 | 类型 | 说明 |
|---|---|---|
| `ADMIN_USERNAME` | 文本 | 管理员用户名，不填默认 `admin` |
| `ADMIN_PASSWORD` | Secret | 管理员密码，**必填** |
| `JWT_SECRET` | Secret | 登录令牌密钥，建议填一串随机字符；不填会自动生成并保存在数据库里 |

生成随机密钥：

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

`wrangler.toml` 中设置了 `keep_vars = true`，在后台填写的变量不会被后续的 Git 部署覆盖。

### 4. 检查并登录

部署完成后访问 `https://<你的Worker>.workers.dev/api/health`：

```json
{"ok":true,"kvBound":true,"adminPasswordSet":true,"jwtSecretSet":true,"users":0}
```

确认 `kvBound` 和 `adminPasswordSet` 为 `true`，然后打开 `/admin`，用上面设置的账号密码登录。第一次登录时会用环境变量自动创建管理员。

## 迁移原数据

在原站后台导出书签（JSON 或 HTML），再到新站后台导入。导入采用合并方式：同名分类会合并，同一分类下相同网址会跳过。

## 本地开发

```bash
npm install
echo 'ADMIN_PASSWORD=你的密码' > .dev.vars
npx wrangler dev
```

本地开发使用本地模拟的 D1 和 KV，数据保存在 `.wrangler/` 目录里，已被 `.gitignore` 排除。

## 常见问题

**忘记管理员密码**
在 D1 控制台执行 `DELETE FROM users;`，然后用环境变量里的账号密码重新登录，管理员会被重新创建。

**登录时报 1102 或 Exceeded CPU**
Workers 免费版每次请求的 CPU 时间很短，密码哈希可能超时。可以升级到 Workers 付费版，或降低 `src/index.js` 里 PBKDF2 的迭代次数（默认 100000）。

**构建时报权限错误，无法创建 D1 或 KV**
说明自动创建资源失败。可以在后台手动创建 D1 和 KV，再把它们的 ID 填进 `wrangler.toml`：

```toml
[[d1_databases]]
binding = "DB"
database_name = "你的库名"
database_id = "你的 D1 ID"

[[kv_namespaces]]
binding = "KV"
id = "你的 KV ID"
```

**上传图片失败**
单张图片限 10MB，只支持 jpg / png / webp / gif / avif / ico。大图可以改用图片 URL。

**workers.dev 域名访问不稳定**
在 Worker 的 **Settings → Domains & Routes** 里绑定自己的域名。

## 目录结构

```
.
├── public/          前端编译文件（含 wallpaper.js，用于壁纸功能）
├── src/index.js     Worker 后端
├── wrangler.toml    Cloudflare 配置
└── package.json
```

## 安全说明

- 仓库里不包含任何密钥，管理员密码和 JWT 密钥只存在于 Cloudflare 的环境变量里。
- 上传接口和壁纸设置接口都需要登录。
- 登录接口目前没有限流，建议在 Cloudflare 里为 `/api/login` 配置速率限制规则，或开启 Turnstile 等防护。

## 许可

前端和接口设计来自 [eooce/nav-item](https://github.com/eooce/nav-item)（MIT License），请同时遵守原项目的许可条款。
