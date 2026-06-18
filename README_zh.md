# OpenClaw Enterprise — 基于 AWS Bedrock 的 AI 智能体平台

> 成本可控、安全合规、开箱即用的企业级 AI 助手平台。一键部署到 AWS，通过 Amazon Bedrock 获得 10+ 顶级模型能力，无需管理 API Key。

---

## 为什么选择这个方案

[OpenClaw](https://github.com/openclaw/openclaw) 是全球增长最快的开源 AI 助手——它运行在你自己的设备上，连接 WhatsApp、Telegram、Discord、Slack、飞书等 20+ 消息平台，能够真正执行操作：管理邮件、浏览网页、运行命令、调度任务。

**痛点**：自行部署意味着管理多个 AI 提供商的 API Key、配置网络、处理安全加固、应对不可控的 Token 费用。

**我们的方案**：一个 CloudFormation 模板，给你一套完整的企业级基础设施——不只是"能跑"，而是"敢用、用得起、好维护"。

---

## 核心亮点

### 智能成本控制（节省 60-80% Token 费用）

| 能力 | 说明 |
|------|------|
| LiteLLM 智能路由 | 简单问题自动走 Nova 2 Lite（$0.30/1M tokens），复杂任务升级 Claude Sonnet，按需分配算力 |
| Semantic Caching | 对重复/相似查询返回缓存结果，避免重复调用 LLM |
| Token 预算告警 | 设置月度预算阈值，用量达 80% 时 CloudWatch 自动告警，防止账单失控 |
| 成本 Dashboard | 实时展示 Token 用量、费用趋势、模型调用分布，运营情况一目了然 |

> 社区反馈：有用户反映未经优化的 OpenClaw + Bedrock 部署一周花费 $100。本方案通过智能路由 + 缓存 + 预算控制，将同等场景成本压缩至 $20-40/周。

### 企业级安全合规

| 能力 | 说明 |
|------|------|
| Bedrock Guardrails | 预配置内容过滤、主题拒绝、PII 脱敏、上下文基础检查，减少幻觉与风险输出 |
| IAM 最小权限 | 不使用 `AmazonBedrockFullAccess` 宽泛策略，仅授予必要的 `InvokeModel` + `ApplyGuardrail` 权限 |
| Docker 沙箱隔离 | 默认启用 `sandbox.mode: "non-main"`，所有非主会话在 Docker 容器中执行，防止恶意 Skills 危害主机 |
| Skills 安全白名单 | 仅预装经过审计的安全 Skills，杜绝 900+ 已报告的恶意 Skills 风险 |
| 零 SSH 攻击面 | 无 SSH 密钥、无 SSH 端口，全部通过 SSM Session Manager 加密隧道访问 |
| IMDSv2 强制 | 实例元数据服务强制使用安全令牌，无 v1 回退 |
| 合规文档包 | 附带 SOC2 控制点映射、安全自查清单、数据流向图 |

### 运维自动化

| 能力 | 说明 |
|------|------|
| 健康自愈 | 每 5 分钟检查端口 + HTTP + 通道连通性，异常自动重启；systemd 在内存达 80% 时优雅重启 |
| S3 自动备份 | EventBridge + Lambda 每日备份 workspace（SOUL.md、Skills、会话历史），一键恢复 |
| 自动更新管道 | SSM Automation 蓝绿部署，低峰期自动拉取 OpenClaw 新版本（可选开启） |
| CloudWatch Insights | 预配置日志查询模板：错误率、响应延迟、模型调用分布，无需手写查询 |
| OS 安全补丁 | unattended-upgrades 自动安装安全更新 |

### 垂直场景预配置

不只是给你一个空壳助手。根据业务场景一键加载预设的 AI 人格、技能包和工作流：

| 场景 | AI 人格 | 预装 Skills | 默认模型 |
|------|---------|-------------|----------|
| **通用助手** | 全能个人助理 | 邮件、日历、天气、文件管理 | Nova 2 Lite |
| **跨境电商** | 多语言运营专家 | 多语言翻译、订单查询、库存管理 | Claude Sonnet |
| **DevOps** | 运维自动化专家 | GitHub、Jira、监控告警、日志分析 | Claude Sonnet |
| **知识管理** | 企业知识库管家 | 文档索引、Memory Search、FAQ 问答 | Nova Pro |
| **客服机器人** | 智能客服代理 | 多渠道接入、FAQ 知识库、工单系统、Guardrails 过滤 | Nova 2 Lite |

---

## 架构

```
用户 (WhatsApp / Telegram / Discord / Slack / 飞书 / Web)
│
▼
┌──────────────────────────────────────────────────────────────┐
│  AWS Cloud                                                    │
│                                                               │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐    │
│  │ EC2 Instance│───▶│ Nginx (HTTPS)│───▶│  OpenClaw     │    │
│  │ (OpenClaw)  │    │ (IP SSL 证书) │    │  localhost:   │    │
│  │  Graviton   │    │  :443         │    │  18789        │    │
│  │  ARM c7g    │    └──────────────┘    └───────────────┘    │
│  │             │          │                    │              │
│  │  Docker     │    ┌─────┴──────┐       ┌────┴─────┐       │
│  │  Sandbox    │    │ CloudWatch │       │ CloudTrail│       │
│  └─────────────┘    │ (告警 +    │       │ (审计日志) │       │
│       │             │  日志)     │       │           │       │
│  SSM Session Manager        S3 (备份)                        │
│  (安全访问，无 SSH)                                          │
└──────────────────────────────────────────────────────────────┘
│
▼
用户 (收到 AI 回复)
```

### 基础设施组件

| 组件 | 说明 |
|------|------|
| **EC2 (Graviton ARM)** | c7g.large (2 vCPU, 4GB RAM)，ARM 架构比 x86 便宜 20-40% |
| **Nginx 反向代理** | Let's Encrypt IP 证书 SSL 终止，转发至 localhost:18789 |
| **Let's Encrypt SSL** | 免费 90 天 IP 地址证书，Certbot 自动续期 |
| **Elastic IP** | 静态公网 IP，确保 HTTPS 访问稳定性和证书有效性 |
| **OpenClaw** | 核心 AI 智能体，本地运行，Docker 沙箱隔离 |
| **Amazon Bedrock** | 模型推理，IAM 认证（无需 API Key），Global CRIS 自动路由 |
| **SSM Session Manager** | 加密隧道访问，无开放端口，会话自动记录到 CloudTrail |
| **S3** | Workspace 备份 + 文件存储 |
| **CloudWatch** | 监控告警 + Logs Insights 预配置查询 |
| **CloudTrail** | 所有 Bedrock API 调用审计（who, when, what model, what input） |

---

## 支持模型

通过 CloudFormation 参数一键切换，无需改代码：

| 模型 | 输入/输出 每百万 Tokens | 适用场景 |
|------|------------------------|----------|
| **Nova 2 Lite**（默认） | $0.30 / $2.50 | 日常任务，比 Claude 便宜 90% |
| Nova Pro | $0.80 / $3.20 | 平衡性能，多模态 |
| Claude Opus 4.6 | $15.00 / $75.00 | 最强能力，复杂 Agentic 任务 |
| Claude Opus 4.5 | $15.00 / $75.00 | 深度分析，扩展思考 |
| Claude Sonnet 4.5 | $3.00 / $15.00 | 复杂推理，编码 |
| Claude Sonnet 4 | $3.00 / $15.00 | 可靠编码与分析 |
| Claude Haiku 4.5 | $1.00 / $5.00 | 快速高效 |
| DeepSeek R1 | $0.55 / $2.19 | 开源推理模型 |
| Llama 3.3 70B | — | 开源替代方案 |
| Kimi K2.5 | $0.60 / $3.00 | 多模态 Agentic，262K 上下文 |

> 使用 Global CRIS inference profiles，部署在任意 Region，请求自动路由到最优位置。

---

## 成本预估

### 典型月度成本（轻度使用）

| 组件 | 费用 (us-west-2) | 说明 |
|------|-------------------|------|
| EC2 (c7g.large, Graviton) | ~$53 | 2 vCPU, 4GB RAM |
| EBS (30GB gp3 x2) | $4.80 | 系统盘 + 数据盘 |
| Elastic IP | $0.00 | 绑定运行中的实例免费 |
| CloudWatch 监控 | ~$4 | 自动恢复 + 告警 + 日志 |
| Bedrock (Nova 2 Lite) | $5.55 | 约 100 次对话/天 |
| **月度总计** | **~$67** | |

### 智能路由节省对比

| 场景 | 无路由（纯 Claude） | 智能路由（本方案） | 节省 |
|------|---------------------|---------------------|------|
| 轻度使用 (100 对话/天) | ~$45/月 | ~$5.55/月 | **87%** |
| 中度使用 (300 对话/天) | ~$135/月 | ~$16.65/月 | **87%** |
| 重度使用 (1000 对话/天) | ~$450/月 | ~$55.50/月 | **87%** |

> 以上对比基于 80% 简单任务走 Nova 2 Lite + 20% 复杂任务走 Claude Sonnet 的路由策略。

### vs 竞品

| 方案 | 月费 | 差异 |
|------|------|------|
| ChatGPT Plus (1 人) | $20/人/月 | 单用户，无消息平台集成 |
| 本方案 (1 人) | $67/月 | 全控制 + 20+ 消息平台 + 成本可控 |
| 本方案 (5 人) | $13.40/人/月 | 比 ChatGPT 便宜 33% |
| 本方案 (20 人) | $3.35/人/月 | 比 ChatGPT 便宜 83% |

---

## 快速开始

### 一键部署

1. 点击 CloudFormation Launch Stack 按钮（按 Region）
2. 选择模型、实例类型、场景预设等参数
3. 等待约 8 分钟
4. 查看 Outputs 标签页获取访问信息

| Region | 启动 |
|--------|------|
| US West (Oregon) | `Launch Stack` |
| US East (Virginia) | `Launch Stack` |
| EU (Ireland) | `Launch Stack` |
| Asia Pacific (Tokyo) | `Launch Stack` |

### 部署后连接

```bash
# 1. 安装 SSM Session Manager 插件（一次性）
#    https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# 2. 从 CloudFormation Outputs 获取 Elastic IP
ELASTIC_IP=$(aws cloudformation describe-stacks \
  --stack-name openclaw-enterprise \
  --query 'Stacks[0].Outputs[?OutputKey==`ElasticIP`].OutputValue' \
  --output text --region us-west-2)

# 3. 在浏览器中通过 HTTPS 访问
echo "https://$ELASTIC_IP"
```

### CLI 部署

```bash
aws cloudformation create-stack \
  --stack-name openclaw-enterprise \
  --template-body file://cloudformation/main.yaml \
  --capabilities CAPABILITY_IAM \
  --region us-west-2

aws cloudformation wait stack-create-complete \
  --stack-name openclaw-enterprise --region us-west-2
```

---

## CloudFormation 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `OpenClawModel` | `global.amazon.nova-2-lite-v1:0` | Bedrock 模型 ID |
| `InstanceType` | `c7g.large` | EC2 实例类型（Graviton ARM） |
| `ScenarioPreset` | `general` | 场景预设：`general` / `ecommerce` / `devops` / `knowledge` / `support` |
| `OpenClawVersion` | `2026.4.27` | OpenClaw 版本（锁定版本避免兼容性问题） |
| `EnableLiteLLM` | `true` | 启用 LiteLLM 智能路由 + 缓存 |
| `MonthlyTokenBudget` | `50` | 月度 Token 预算（美元），超限告警 |
| `EnableGuardrails` | `false` | 启用 Bedrock Guardrails 内容过滤 |
| `GuardrailId` | `""` | Bedrock Guardrail ID（需预创建或由模板自动创建） |
| `EnableSandbox` | `true` | Docker 沙箱隔离（推荐开启） |
| `EnableAutoUpdate` | `false` | 自动更新 OpenClaw 版本 |
| `EnableBackup` | `true` | S3 每日自动备份 workspace |
| `EnableMonitoring` | `true` | CloudWatch 监控 + 告警 + 日志 (~$4/月) |
| `CreateVPCEndpoints` | `false` | VPC 私有网络端点 (~$88/月) |

---

## 连接消息平台

部署完成后，在 Web UI 的 "Channels" 中连接你需要的平台：

| 平台 | 配置方式 |
|------|----------|
| WhatsApp | 扫描 QR 码 |
| Telegram | 通过 @BotFather 创建 Bot，粘贴 Token |
| Discord | Developer Portal 创建 App，粘贴 Bot Token |
| Slack | api.slack.com 创建 App，安装到 Workspace |
| 飞书 / Lark | 社区插件 openclaw-feishu |
| Microsoft Teams | Azure Bot 注册 |
| WebChat | 内置，无需额外配置 |

---

## 项目结构

```
OpenClawBedrock/
├── packer/                           # AMI 构建
│   ├── openclaw-bedrock.pkr.hcl     # Packer 配置
│   └── files/                       # 预装文件与服务配置
│       ├── nginx/                   # Nginx SSL 配置模板
│       ├── certbot/                 # Let's Encrypt 证书自动化脚本
│       └── userdata/                # UserData 初始化脚本
├── cloudformation/                   # 部署模板
│   ├── main.yaml                    # 主模板
│   └── nested/                      # 嵌套模板 (VPC/IAM/LiteLLM/Monitoring)
├── dashboard/                        # 管理控制台 (静态 Web)
├── skills/                           # 预装审计 Skills
├── scenarios/                        # 场景预配置 (SOUL.md + Skills)
│   ├── general/                     # 通用助手
│   ├── ecommerce/                   # 跨境电商
│   ├── devops/                      # DevOps
│   ├── knowledge/                   # 知识管理
│   └── support/                     # 客服机器人
├── compliance/                       # 合规文档包
├── scripts/                          # 构建/部署/测试脚本
└── docs/                             # 用户文档
```

---

## 安全架构

| 层级 | 措施 |
|------|------|
| **网络** | SSM Session Manager 加密隧道，无开放端口，安全组最小化入站 |
| **身份** | IAM Role（EC2 Instance Profile），自动凭证轮换，无长期密钥 |
| **实例** | IMDSv2 强制（HttpTokens: required），Docker 沙箱隔离 |
| **数据** | SSM Parameter Store (KMS 加密) 存储 Gateway Token，S3 服务端加密 |
| **供应链** | Docker GPG 签名仓库，NVM 下载后执行（非 curl \| sh），npm 固定 registry |
| **审计** | CloudTrail 记录所有 Bedrock API 调用，CloudWatch Logs 保留运行日志 |
| **内容** | Bedrock Guardrails 过滤违规内容、PII 脱敏、主题限制 |
| **传输** | Let's Encrypt IP SSL 证书，强制 TLS 1.2/1.3，启用 HSTS |

---

## 许可证与合规

- **OpenClaw**：[MIT License](https://github.com/openclaw/openclaw/blob/main/LICENSE)
- **本产品**：基于 OpenClaw 构建，包含额外的安全加固、成本控制、运维自动化和场景预配置
- **第三方许可证**：详见 [THIRD-PARTY-LICENSES.txt](./THIRD-PARTY-LICENSES.txt)
- **AWS 服务**：使用 Amazon Bedrock、EC2、S3、CloudWatch、SSM、CloudTrail 等，费用按 AWS 官方定价

---

## 支持

- **问题反馈**：GitHub Issues
- **OpenClaw 社区**：[Discord](https://discord.gg/openclaw) / [GitHub Issues](https://github.com/openclaw/openclaw/issues)
- **AWS Bedrock**：[AWS re:Post](https://repost.aws/)
