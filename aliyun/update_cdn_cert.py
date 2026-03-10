#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
完整脚本：使用 aliyun-python-sdk-core
调用阿里云 CDN SetCdnDomainSSLCertificate API
https://help.aliyun.com/zh/cdn/developer-reference/api-cdn-2018-05-10-setcdndomainsslcertificate
"""

import os
import json
from aliyunsdkcore.client import AcsClient
from aliyunsdkcore.request import CommonRequest

# --------------- 参数区 -----------------

# CDN 域名（需替换为你自己的）
CDN_DOMAIN = "填写CDN域名"

# 本地证书文件
CERT_FILE = "fullchain.pem"
KEY_FILE = "privkey.pem"

# 区域
REGION = "cn-hangzhou"

# --------------- 读取证书 ---------------
def read_certificates():
    try:
        with open(CERT_FILE, "r", encoding="utf-8") as f:
            cert_pem = f.read().strip()
        with open(KEY_FILE, "r", encoding="utf-8") as f:
            key_pem = f.read().strip()
        return cert_pem, key_pem
    except Exception as e:
        print(f"[错误] 无法读取证书文件: {e}")
        exit(1)

# --------------- 更新 CDN 证书 ---------------
def update_cdn_certificate():
    ak = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_ID")
    sk = os.getenv("ALIBABA_CLOUD_ACCESS_KEY_SECRET")

    if not ak or not sk:
        print("[错误] 请先设置环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID 和 ALIBABA_CLOUD_ACCESS_KEY_SECRET")
        exit(1)

    # 读取 PEM 文件
    cert_pem, key_pem = read_certificates()

    # 初始化客户端
    client = AcsClient(ak, sk, REGION)

    # 构造通用请求
    request = CommonRequest()
    request.set_method("POST")
    request.set_domain("cdn.aliyuncs.com")
    request.set_version("2018-05-10")
    request.set_action_name("SetCdnDomainSSLCertificate")

    # 必须设置 AcceptFormat，否则返回非 JSON
    request.set_accept_format('json')

    # 设置参数
    request.add_query_param("DomainName", CDN_DOMAIN)
    request.add_query_param("SSLProtocol", "on")
    request.add_query_param("CertType", "upload")
    request.add_query_param("SSLPub", cert_pem)
    request.add_query_param("SSLPri", key_pem)

    try:
        # 调用 API
        response_bytes = client.do_action_with_exception(request)
        # 解析响应
        response_str = response_bytes.decode('utf-8')
        response_json = json.loads(response_str)
        print("响应 JSON:", json.dumps(response_json, indent=2, ensure_ascii=False))
        if "RequestId" in response_json:
            print("[成功] CDN 证书替换请求已发送。")
        else:
            print("[提示] 未返回 RequestId，请检查参数和权限。")
    except Exception as e:
        print(f"[错误] API 调用失败: {e}")

# --------------- 主执行 ---------------
if __name__ == "__main__":
    update_cdn_certificate()
