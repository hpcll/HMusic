# HMusic 音频代理部署指南

## ⚠️ 免责声明

**本代理仅供技术学习和研究使用！**

- 本工具通过代理转发音频请求，可能涉及规避技术保护措施
- 使用者需自行承担法律风险，开发者不对任何侵权行为负责
- 请遵守当地法律法规及各音乐平台的服务条款
- 禁止将本工具用于商业用途或大规模分发

**如果您不同意以上条款，请勿使用本功能。**

---

## 为什么需要音频代理？

小爱音箱在播放第三方音乐时，需要直接访问音频 CDN。但很多 CDN（如 QQ音乐、网易云）会检查：

- **User-Agent**：必须是浏览器或官方 App
- **Referer**：必须来自官方网站
- **IP 限制**：某些 CDN 对特定 IP 段有限制

如果不使用代理，音箱可能会出现"有反应但不响"的情况。

通过 Cloudflare Workers 代理，可以：
1. 设置合法的 User-Agent 和 Referer
2. 利用 Cloudflare 的全球 CDN 网络
3. 让音箱能够顺利播放音乐

---

## 自行部署步骤

### 1. 注册 Cloudflare 账号

访问 https://dash.cloudflare.com/sign-up 注册（免费）。

### 2. 创建 Worker

1. 登录 Cloudflare Dashboard
2. 点击左侧菜单 **Workers & Pages**
3. 点击 **Create** → **Create Worker**
4. 给 Worker 起个名字，如 `hmusic-proxy`
5. 点击 **Deploy**

### 3. 编辑 Worker 代码

1. 部署后，点击 **Edit code**
2. 删除默认代码
3. 将本目录下 `worker.js` 文件的内容粘贴进去
4. 点击右上角 **Save and deploy**

### 4. 获取 Worker URL

部署成功后，你会看到一个 URL：
```
https://hmusic-proxy.your-subdomain.workers.dev
```

### 5. 验证部署

访问健康检查端点：
```
https://your-worker.workers.dev/health
```

应该返回：
```json
{
  "status": "ok",
  "service": "HMusic Audio Proxy",
  "version": "1.0.0"
}
```

---

## 重要：绑定自定义域名

### 为什么需要自定义域名？

`workers.dev` 域名在国内**可能被墙**，无法直接访问。

解决方案：绑定一个自己的域名（需要域名托管在 Cloudflare）。

### 绑定步骤

1. 确保你的域名 DNS 已托管在 Cloudflare
2. 进入 Cloudflare Dashboard → **Workers & Pages**
3. 点击你的 Worker 名称
4. 点击 **Settings** 标签
5. 找到 **域和路由** 区域，点击 **+ 添加**
6. 选择 **自定义域**
7. 输入子域名，如 `proxy.yourdomain.com`
8. 点击 **添加域**

Cloudflare 会自动配置 DNS 和 SSL 证书，几分钟后即可使用。

### 验证自定义域名

```
https://proxy.yourdomain.com/health
```

---

## 在 HMusic App 中配置

1. 打开 HMusic App
2. 进入 **设置** → **音源设置**
3. 找到 **音频代理服务器**
4. 填入你的代理 URL（不要带末尾斜杠）
5. 开启 **启用音频代理** 开关
6. 保存设置

---

## 免费额度

Cloudflare Workers 免费套餐：
- **每天 100,000 次请求**
- 每次请求最大执行时间 10ms（CPU 时间）

### 用量估算

| 用户数 | 每人每天播放 | 总请求数 | 免费额度占比 |
|--------|-------------|----------|-------------|
| 1人    | 50首        | 50       | 0.05%       |
| 5人    | 50首        | 250      | 0.25%       |
| 10人   | 50首        | 500      | 0.5%        |

个人使用完全足够！

---

## 安全说明

Worker 代码包含安全措施：

1. **域名白名单**：只允许代理音乐 CDN 的 URL
2. **协议限制**：只允许 HTTP/HTTPS
3. **超时保护**：30秒超时，防止资源占用

### 支持的音乐源

- QQ音乐 (`qq.com`, `qqmusic.qq.com`)
- 网易云音乐 (`music.126.net`, `163.com`)
- 酷狗音乐 (`kugou.com`)
- 酷我音乐 (`kuwo.cn`)
- 咪咕音乐 (`migu.cn`)

如需添加新的音乐源，修改 `worker.js` 中的 `ALLOWED_DOMAINS` 数组。

---

## 故障排查

### 问题：音箱无法播放

1. 检查代理 URL 是否正确
2. 访问 `/health` 端点检查服务状态
3. 查看 Cloudflare Dashboard 的 Worker 日志

### 问题：返回 403 错误

域名不在白名单中，需要添加到 `ALLOWED_DOMAINS`。

### 问题：国内无法访问

`workers.dev` 域名被墙，请绑定自定义域名。

### 问题：返回 504 超时

CDN 响应太慢，可能是源站问题。

---

## 访问统计

在 Cloudflare Dashboard → Workers 页面可以查看：
- 请求总数
- 成功/失败率
- 响应时间分布
