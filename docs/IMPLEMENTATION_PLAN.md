# OpenClaw Enterprise - 实施计划

## 项目概述

本文档详述了 OpenClaw Enterprise 在 AWS Bedrock 上的完整实施计划，采用 Let's Encrypt 证书实现基于 IP 地址的 HTTPS 访问。

## 项目时间线：3-4 周（26 天）

---

## Phase 1: 项目结构搭建 (第 1-2 天) ✅

**状态**: 已完成

### 交付物
- [x] 项目目录结构创建
- [x] 英文 README.md 完成
- [x] 中文 README_zh.md 完成
- [ ] 实施计划文档（中英文）

### 已创建文件
```
/workspace/
├── README.md              # 英文文档
├── README_zh.md           # 中文文档
├── docs/                  # 文档文件夹
├── packer/                # AMI 构建配置
├── cloudformation/        # 部署模板
├── skills/                # 预审计 Skills
├── scenarios/             # 场景预设
├── compliance/            # 合规文档
└── scripts/               # 构建/部署脚本
```

---

## Phase 2: Packer AMI 构建 (第 3-6 天)

**状态**: 进行中

### 交付物
- [ ] Packer HCL 配置文件
- [ ] UserData 引导脚本
- [ ] Nginx SSL 配置模板
- [ ] Certbot 自动化脚本
- [ ] OpenClaw 安装脚本
- [ ] Docker 沙箱配置

### 核心组件

#### 2.1 Packer 配置 (`packer/openclaw-bedrock.pkr.hcl`)
- Ubuntu 22.04 LTS 基础镜像
- ARM64 (Graviton) 支持
- 预装 Docker、Nginx、Certbot、Node.js
- 配置安全加固

#### 2.2 UserData 引导脚本 (`packer/files/userdata/bootstrap.sh`)
```bash
#!/bin/bash
# 步骤：
# 1. 从元数据获取 Elastic IP
# 2. 安装依赖（nginx、certbot、docker）
# 3. 为 IP 申请 Let's Encrypt 证书
# 4. 配置 Nginx 反向代理
# 5. 安装并配置 OpenClaw
# 6. 设置 systemd 服务
# 7. 配置证书自动续期
```

#### 2.3 Nginx SSL 配置 (`packer/files/nginx/openclaw.conf`)
- TLS 1.2/1.3 强制
- HSTS 头部
- 反向代理到 localhost:18789
- 速率限制
- 安全头部

#### 2.4 Certbot 自动化 (`packer/files/certbot/renew-cert.sh`)
- 自动证书续期（60 天触发）
- 成功后重载 Nginx
- 日志记录和告警

---

## Phase 3: CloudFormation 模板 (第 7-11 天)

**状态**: 待处理

### 交付物
- [ ] 主 CloudFormation 模板 (`cloudformation/main.yaml`)
- [ ] VPC 嵌套模板
- [ ] IAM 嵌套模板
- [ ] EC2 嵌套模板
- [ ] 安全组嵌套模板
- [ ] S3 备份桶模板

### 核心资源
- 带公共子网的 VPC
- 互联网网关
- EC2 实例 (c7g.large)
- Elastic IP
- 最小权限 IAM Role
- S3 备份桶
- CloudWatch 告警

### 参数
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| OpenClawModel | String | global.amazon.nova-2-lite-v1:0 | Bedrock 模型 ID |
| InstanceType | String | c7g.large | EC2 实例类型 |
| ScenarioPreset | String | general | 场景预设 |
| EnableLiteLLM | Boolean | true | 启用智能路由 |
| MonthlyTokenBudget | Number | 50 | 预算告警阈值 |
| EnableGuardrails | Boolean | false | 启用内容过滤 |
| EnableSandbox | Boolean | true | Docker 沙箱隔离 |
| EnableBackup | Boolean | true | S3 自动备份 |
| EnableMonitoring | Boolean | true | CloudWatch 监控 |

---

## Phase 4: LiteLLM 集成 (第 12-14 天)

**状态**: 待处理

### 交付物
- [ ] LiteLLM Docker 配置
- [ ] 智能路由规则
- [ ] 语义缓存设置
- [ ] 成本跟踪集成

### 配置示例
```yaml
# LiteLLM 配置
model_list:
  - model_name: "smart-router"
    litellm_params:
      model: "bedrock/global.amazon.nova-2-lite-v1:0"
  - model_name: "complex-tasks"
    litellm_params:
      model: "bedrock/anthropic.claude-sonnet-4-20250514-v1:0"

router_settings:
  routing_strategy: simple_shuffle
  fallbacks: [...]
  
general_settings:
  master_key: "sk-..."
  database_url: "postgresql://..."
```

---

## Phase 5: 监控与告警 (第 15-17 天)

**状态**: 待处理

### 交付物
- [ ] CloudWatch 仪表板
- [ ] 告警配置
- [ ] Log Insights 查询
- [ ] SNS 通知设置

### 监控指标
- EC2 CPU 使用率 (>80% 告警)
- 内存使用率 (>80% 重启触发)
- OpenClaw 端口健康检查
- HTTP 端点可用性
- Bedrock API 调用次数
- Token 用量 vs 预算

### 告警配置
| 指标 | 阈值 | 动作 |
|------|------|------|
| CPU 使用率 | >80% 持续 5 分钟 | SNS 通知 |
| 内存使用率 | >80% | Systemd 重启 |
| 端口 18789 | 不可达 | 自动恢复 |
| Token 预算 | >月度 80% | SNS 通知 |
| 健康检查 | 失败 3 次 | EC2 重启 |

---

## Phase 6: 场景预设 (第 18-20 天)

**状态**: 待处理

### 交付物
- [ ] 通用助手场景
- [ ] 跨境电商场景
- [ ] DevOps 场景
- [ ] 知识管理场景
- [ ] 客服机器人场景

### 每个场景包含
- SOUL.md 配置
- 预选 Skills
- 默认模型分配
- 自定义指令

---

## Phase 7: 安全与合规 (第 21-23 天)

**状态**: 待处理

### 交付物
- [ ] SOC2 控制点映射文档
- [ ] 安全自查清单
- [ ] 数据流向图
- [ ] IAM 策略文档
- [ ] 安全加固指南

### 安全措施
- IMDSv2 强制
- IAM 最小权限策略
- Docker 沙箱隔离
- 仅 SSM Session Manager（无 SSH）
- KMS 加密密钥
- CloudTrail 审计日志
- Bedrock Guardrails 集成

---

## Phase 8: 测试与验证 (第 24-26 天)

**状态**: 待处理

### 测试类别
- [ ] 脚本单元测试
- [ ] CloudFormation 集成测试
- [ ] 端到端部署测试
- [ ] 安全渗透测试
- [ ] 负载测试
- [ ] 成本验证测试

### 验证清单
- [ ] AMI 构建成功
- [ ] CloudFormation 堆栈无错误创建
- [ ] HTTPS 证书正确配置
- [ ] OpenClaw Web UI 可通过 HTTPS 访问
- [ ] Bedrock 模型调用正常工作
- [ ] 监控告警正确触发
- [ ] 备份/恢复流程验证
- [ ] 证书自动续期工作正常

---

## 下一步行动

### 本周重点
1. 创建 Packer 配置文件
2. 编写 UserData 引导脚本
3. 创建 Nginx SSL 配置
4. 开发 Certbot 自动化脚本
5. 本地测试 AMI 构建

### 关键路径
- Packer AMI 构建 → CloudFormation 模板 → 端到端测试

### 依赖项
- 已启用 Bedrock 访问的 AWS 账户
- 本地安装 Packer 用于测试
- 已配置的 AWS CLI

---

## 风险缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Let's Encrypt 速率限制 | 高 | 使用 Elastic IP；缓存证书 |
| Bedrock 模型可用性 | 中 | 实现备用模型 |
| EC2 实例故障 | 中 | 自动恢复 + 健康检查 |
| 成本超支 | 高 | 预算告警 + 智能路由 |
| 安全漏洞 | 高 | 定期补丁 + 沙箱隔离 |

---

## 成功标准

1. **一键部署**: CloudFormation 堆栈在 <10 分钟内完成
2. **HTTPS 工作**: IP 地址上有效的 SSL 证书
3. **成本控制**: 相比纯 Claude 部署节省 60-80%
4. **安全性**: 零 SSH 访问；全部通过 SSM
5. **可靠性**: 自动愈合，恢复时间 <5 分钟
6. **可用性**: 部署后 Web UI 可访问且功能正常
