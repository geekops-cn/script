> 简单描述：使用1panel自动续签证书的功能，将证书同步到阿里云CDN域名中，替换证书。
> 1panel中将证书续订后保存到指定路径中`/root/aliyun_cdn_cert` 并且勾选申请证书之后执行脚本

# 📌 阿里云 CDN 证书自动替换脚本

本项目提供了一个 **Python 脚本**，用于自动将你本地的 SSL/TLS 证书上传并替换到阿里云 CDN 的加速域名中。适合结合 Let’s Encrypt/1Panel 自动续签后自动同步证书到阿里云 CDN 的场景。

---

## 🚀 功能简介

- 从本地读取证书文件（PEM 格式）
- 通过阿里云 OpenAPI 调用 `SetCdnDomainSSLCertificate` 接口替换 CDN HTTPS 证书
- 使用阿里云 Python SDK 核心库实现通用 API 调用
- 支持结合 Bash/计划任务（，比如 1Panel cron jobs）自动执行

---

## 📁 项目结构

```
aliyun_cdn_cert/
├── fullchain.pem              # 公钥证书（PEM 格式）
├── privkey.pem                # 私钥
├── update_cdn_cert.py         # Python 脚本（主逻辑）
├── run_update.sh              # 可选：Bash 启动脚本
└── README.md                 # 当前说明文档
```

---

## 📥 环境要求

- Python 3.7+
- 已安装虚拟环境（推荐 venv）
- 依赖库：  
  ```bash
  pip install aliyun-python-sdk-core
  ```
  这是阿里云 Python 核心 SDK，用于通用 API 调用。  

`aliyun-python-sdk-core` 是阿里云 SDK 的通用基础库，用于发送 RPC/OpenAPI 请求。 [oai_citation:0‡pydigger-has-moved](https://pydigger.com/pypi/alibabacloud-cdn20180510?utm_source=chatgpt.com)

---

## 🔐 阿里云认证凭据

脚本使用 RAM 用户的 AccessKey 进行 API 请求，必须设置如下环境变量：

```bash
export ALIBABA_CLOUD_ACCESS_KEY_ID="你的AccessKeyID"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="你的AccessKeySecret"
```

> 如果在脚本/计划任务中执行，建议在脚本内部也显式 `export`，以确保在非交互式环境下可读。  

---

## 🛠 使用步骤

---

### 1️⃣ 准备证书文件

确保证书是 **PEM 格式**，并包含完整证书链：

```
fullchain.pem   # 包含证书 + 中间证书
privkey.pem     # 私钥（未加密）
```

---

### 2️⃣ 修改 Python 脚本

编辑 `update_cdn_cert.py`，将以下变量修改为你的加速域名：

```python
CDN_DOMAIN = "your.cdn.domain.com"
```

确保域名和证书匹配。

---

### 3️⃣ 激活 Python 虚拟环境

假设你在 `/root` 目录创建了虚拟环境 `cdn_env`：

```bash
cd /root
source cdn_env/bin/activate
```

确认当前 Python 是虚拟环境：

```bash
which python
```

输出应类似：

```
/root/cdn_env/bin/python
```

---

### 4️⃣ 运行脚本测试

```bash
python update_cdn_cert.py
```

成功后输出示例：

```
响应 JSON: {
  "RequestId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
[成功] CDN 证书替换请求已发送。
```

表示证书更新请求已成功提交并被 CDN 接收。

---

## 🧑‍💻 Bash 启动脚本示例（可选）

当你结合 1Panel 计划任务执行时，可使用如下 Bash 脚本：

```bash
#!/bin/bash

# 设置阿里云凭据
export ALIBABA_CLOUD_ACCESS_KEY_ID="你的AccessKeyID"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="你的AccessKeySecret"

# 切换到项目目录
cd /root/aliyun_cdn_cert || exit 1

# 直接使用虚拟环境的 python 启动脚本
/root/cdn_env/bin/python update_cdn_cert.py
```

将此脚本保存为 `run_update.sh` 并设置可执行权限：

```bash
chmod +x run_update.sh
```

---

## 📆 与计划任务结合（比如 1Panel Cron）

在 1Panel 控制台的 “计划任务” 功能中，新建一个任务：

- **解释器**：bash  
- **脚本内容**：
  ```bash
  /root/aliyun_cdn_cert/run_update.sh
  ```

设置适当的 cron 表达式，例如：

```
0 2 * * *     # 每天凌晨 2 点
```

此计划任务将在指定时间自动执行证书更新。

---

## 🛡 权限要求

确保你的 RAM 用户拥有以下权限：

```json
{
  "Statement": [
    {
      "Action": "cdn:SetCdnDomainSSLCertificate",
      "Resource": "*",
      "Effect": "Allow"
    }
  ],
  "Version": "1"
}
```

否则会出现权限拒绝错误。

---

## 📌 注意事项

- 公钥证书必须包含中间链证书，否则证书可能无法正常部署。 [oai_citation:1‡阿里云](https://www.alibabacloud.com/help/en/cdn/user-guide/configure-an-ssl-certificate?utm_source=chatgpt.com)  
- 私钥不能设置密码，否则脚本无法正确读取。  
- 若证书续签频繁，建议与自动续签流程（比如 1Panel + Certbot / acme.sh）结合，自动触发上传。 [oai_citation:2‡WordPress智库](https://www.wpzhiku.com/acme-sh-aliyun-cdn/?utm_source=chatgpt.com)

---

## 🛠 参考文档

阿里云 CDN 官方说明：

- **配置 HTTPS 证书（控制台教程）** — HTTPS 配置步骤说明和证书要求。 [oai_citation:3‡阿里云](https://www.alibabacloud.com/help/en/cdn/user-guide/configure-an-ssl-certificate?utm_source=chatgpt.com)

