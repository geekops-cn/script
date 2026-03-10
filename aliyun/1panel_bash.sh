#!/bin/bash

# 导出阿里云访问密钥（必须 export）
export ALIBABA_CLOUD_ACCESS_KEY_ID="ACCESS_KEY_ID"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="ACCESS_KEY_SECRET"

# 进入脚本目录
cd /root/aliyun_cdn_cert || exit 1

# 使用虚拟环境执行脚本
/root/cdn_env/bin/python update_cdn_cert.py
