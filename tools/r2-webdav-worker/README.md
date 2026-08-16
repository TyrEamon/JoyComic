# JoyComic R2 WebDAV Worker

这是给 JoyComic 备份功能使用的轻量 WebDAV 到 Cloudflare R2 转换层。Worker 直接使用 R2 Binding，不需要在代码里填 R2 Access Key。

## 支持范围

- `PROPFIND`：JoyComic 连接测试和备份目录列表。
- `MKCOL`：创建虚拟目录。R2 是对象存储，因此不需要额外的目录对象。
- `PUT` / `GET` / `HEAD` / `DELETE`：备份文件上传、下载、查询和删除。
- HTTP Basic Auth：账号密码由 Worker Secret 提供，比较时使用定长哈希和 timing-safe comparison。

它不是通用网盘，没有实现 `LOCK`/`UNLOCK`/`MOVE`/`COPY`。这些方法不在 JoyComic 当前的备份流程中。

## 部署

1. 进入本目录并安装依赖：

   ```powershell
   npm install
   ```

2. 登录 Cloudflare：

   ```powershell
   npx wrangler login
   ```

3. 创建 R2 Bucket：

   ```powershell
   npx wrangler r2 bucket create joycomic-backups
   ```

   如果你要使用已有 Bucket，修改 `wrangler.jsonc` 中的 `bucket_name`。不要开启 R2 公开访问。

4. 用交互式命令设置 WebDAV 账号和强密码：

   ```powershell
   npx wrangler secret put DAV_USERNAME
   npx wrangler secret put DAV_PASSWORD
   ```

   线上密码不要写进 `wrangler.jsonc` 或 GitHub 仓库。本地调试可以使用已被 `.gitignore` 排除的 `.dev.vars`。

5. 检查后部署：

   ```powershell
   npm run check
   npm run deploy
   ```

6. 在 JoyComic 的 WebDAV 设置中填写：

   - URL：Wrangler 输出的 `https://...workers.dev/` 地址，保留根路径。
   - 用户名：`DAV_USERNAME` 的值。
   - 密码：`DAV_PASSWORD` 的值。

建议把 Worker 绑定在独立子域名的根路径，例如 `https://dav.example.com/`。JoyComic 会使用 WebDAV 响应中的绝对路径下载备份，因此不要只把 Worker 挂在 `/dav/*` 这类子路径。

## R2 中的存储路径

默认情况下，备份文件会保存为：

```text
joycomic-webdav/joycomic_backups/backup_YYYY-MM-DD.zip
```

`ROOT_PREFIX` 可以在 `wrangler.jsonc` 中修改，用来在同一个 Bucket 中隔离其他应用数据。

## 本地测试

测试使用 Workers 运行时和本地 R2 Binding，不会读写你线上的 Bucket：

```powershell
npm test
```

本地手工调试时，在本目录创建不提交的 `.dev.vars`：

```dotenv
DAV_USERNAME=local-user
DAV_PASSWORD=local-strong-password
```

然后运行 `npm run dev`。
