# OpenClaw Enterprise — AI Agent Platform on AWS Bedrock

> Cost-controlled, secure, compliant, and ready-to-use enterprise AI assistant platform. One-click deployment to AWS with access to 10+ top-tier models via Amazon Bedrock, no API Key management required.

---

## Why Choose This Solution

[OpenClaw](https://github.com/openclaw/openclaw) is the fastest-growing open-source AI assistant globally—it runs on your own infrastructure, connects to 20+ messaging platforms including WhatsApp, Telegram, Discord, Slack, and Feishu, and can truly execute actions: manage emails, browse the web, run commands, and schedule tasks.

**Pain Point**: Self-deployment means managing multiple AI provider API Keys, configuring networks, handling security hardening, and dealing with uncontrollable token costs.

**Our Solution**: A CloudFormation template providing complete enterprise-grade infrastructure—not just "runs," but "safe to use, affordable, and easy to maintain."

---

## Core Highlights

### Intelligent Cost Control (Save 60-80% on Token Costs)

| Capability | Description |
|------------|-------------|
| LiteLLM Smart Routing | Simple queries automatically route to Nova 2 Lite ($0.30/1M tokens), complex tasks upgrade to Claude Sonnet, allocating compute on demand |
| Semantic Caching | Returns cached results for repeated/similar queries, avoiding redundant LLM calls |
| Token Budget Alerts | Set monthly budget thresholds; CloudWatch alerts at 80% usage to prevent bill shocks |
| Cost Dashboard | Real-time display of token usage, cost trends, and model call distribution for clear operational visibility |

> Community Feedback: Users report unoptimized OpenClaw + Bedrock deployments costing $100/week. This solution compresses equivalent scenarios to $20-40/week through smart routing + caching + budget controls.

### Enterprise-Grade Security & Compliance

| Capability | Description |
|------------|-------------|
| Bedrock Guardrails | Pre-configured content filtering, topic rejection, PII redaction, and context-based checks to reduce hallucinations and risky outputs |
| IAM Least Privilege | No broad `AmazonBedrockFullAccess` policies; only grants necessary `InvokeModel` + `ApplyGuardrail` permissions |
| Docker Sandbox Isolation | Default `sandbox.mode: "non-main"` executes all non-main sessions in Docker containers, preventing malicious Skills from harming the host |
| Skills Security Whitelist | Only pre-installs audited safe Skills, eliminating risks from 900+ reported malicious Skills |
| Zero SSH Attack Surface | No SSH keys, no SSH ports; all access via encrypted SSM Session Manager tunnels |
| IMDSv2 Enforcement | Instance metadata service requires security tokens; no v1 fallback |
| Compliance Documentation Pack | Includes SOC2 control mapping, security self-check checklist, and data flow diagrams |

### Operational Automation

| Capability | Description |
|------------|-------------|
| Health Self-Healing | Checks port + HTTP + channel connectivity every 5 minutes; auto-restarts on failure; systemd gracefully restarts at 80% memory usage |
| S3 Auto Backup | EventBridge + Lambda daily backups of workspace (SOUL.md, Skills, session history) with one-click recovery |
| Auto-Update Pipeline | SSM Automation blue-green deployment; automatically pulls new OpenClaw versions during off-peak hours (optional) |
| CloudWatch Insights | Pre-configured log query templates: error rates, response latency, model call distribution—no manual query writing needed |
| OS Security Patches | unattended-upgrades automatically installs security updates |

### Vertical Scenario Pre-configuration

Not just an empty shell assistant. One-click loading of preset AI personas, skill packs, and workflows based on business scenarios:

| Scenario | AI Persona | Pre-installed Skills | Default Model |
|----------|------------|---------------------|---------------|
| **General Assistant** | All-around Personal Assistant | Email, Calendar, Weather, File Management | Nova 2 Lite |
| **Cross-Border E-commerce** | Multilingual Operations Expert | Multi-language Translation, Order Lookup, Inventory Management | Claude Sonnet |
| **DevOps** | Operations Automation Expert | GitHub, Jira, Monitoring Alerts, Log Analysis | Claude Sonnet |
| **Knowledge Management** | Enterprise Knowledge Steward | Document Indexing, Memory Search, FAQ Q&A | Nova Pro |
| **Customer Service Bot** | Intelligent Service Agent | Multi-channel Access, FAQ Knowledge Base, Ticket System, Guardrails Filtering | Nova 2 Lite |

---

## Architecture

```
User (WhatsApp / Telegram / Discord / Slack / Feishu / Web)
│
▼
┌──────────────────────────────────────────────────────────────┐
│  AWS Cloud                                                    │
│                                                               │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐    │
│  │ EC2 Instance│───▶│ Nginx (HTTPS)│───▶│  OpenClaw     │    │
│  │ (OpenClaw)  │    │ (IP SSL Cert)│    │  localhost:   │    │
│  │  Graviton   │    │  :443         │    │  18789        │    │
│  │  ARM c7g    │    └──────────────┘    └───────────────┘    │
│  │             │          │                    │              │
│  │  Docker     │    ┌─────┴──────┐       ┌────┴─────┐       │
│  │  Sandbox    │    │ CloudWatch │       │ CloudTrail│       │
│  └─────────────┘    │ (Alerts+   │       │ (Audit    │       │
│       │             │  Logs)     │       │  Logs)    │       │
│  SSM Session Manager        S3 (Backup)                    │
│  (Secure Access, No SSH)                                   │
└──────────────────────────────────────────────────────────────┘
│
▼
User (receives AI response)
```

### Infrastructure Components

| Component | Description |
|-----------|-------------|
| **EC2 (Graviton ARM)** | c7g.large (2 vCPU, 4GB RAM); ARM architecture 20-40% cheaper than x86 |
| **Nginx Reverse Proxy** | SSL termination with Let's Encrypt IP certificate; forwards to localhost:18789 |
| **Let's Encrypt SSL** | Free 90-day certificate for IP addresses; auto-renewal via Certbot |
| **Elastic IP** | Static public IP for stable HTTPS access and certificate validity |
| **OpenClaw** | Core AI agent running locally with Docker sandbox isolation |
| **Amazon Bedrock** | Model inference via IAM authentication (no API Keys); Global CRIS auto-routing |
| **SSM Session Manager** | Encrypted tunnel access; no open ports; sessions logged to CloudTrail |
| **S3** | Workspace backup + file storage |
| **CloudWatch** | Monitoring alerts + pre-configured Logs Insights queries |
| **CloudTrail** | Audit logs for all Bedrock API calls (who, when, what model, what input) |

---

## Supported Models

Switch models via CloudFormation parameters without code changes:

| Model | Input/Output per 1M Tokens | Use Case |
|-------|----------------------------|----------|
| **Nova 2 Lite** (Default) | $0.30 / $2.50 | Daily tasks; 90% cheaper than Claude |
| Nova Pro | $0.80 / $3.20 | Balanced performance; multimodal |
| Claude Opus 4.6 | $15.00 / $75.00 | Maximum capability; complex agentic tasks |
| Claude Opus 4.5 | $15.00 / $75.00 | Deep analysis; extended thinking |
| Claude Sonnet 4.5 | $3.00 / $15.00 | Complex reasoning; coding |
| Claude Sonnet 4 | $3.00 / $15.00 | Reliable coding and analysis |
| Claude Haiku 4.5 | $1.00 / $5.00 | Fast and efficient |
| DeepSeek R1 | $0.55 / $2.19 | Open-source reasoning model |
| Llama 3.3 70B | — | Open-source alternative |
| Kimi K2.5 | $0.60 / $3.00 | Multimodal agentic; 262K context |

> Uses Global CRIS inference profiles; deploy in any Region; requests auto-route to optimal location.

---

## Cost Estimate

### Typical Monthly Cost (Light Usage)

| Component | Cost (us-west-2) | Description |
|-----------|------------------|-------------|
| EC2 (c7g.large, Graviton) | ~$53 | 2 vCPU, 4GB RAM |
| EBS (30GB gp3 x2) | $4.80 | System + data volumes |
| Elastic IP | $0.00 | Free when attached to running instance |
| CloudWatch Monitoring | ~$4 | Auto-recovery + alerts + logs |
| Bedrock (Nova 2 Lite) | $5.55 | ~100 conversations/day |
| **Monthly Total** | **~$67** | |

### Smart Routing Savings Comparison

| Scenario | No Routing (Pure Claude) | Smart Routing (This Solution) | Savings |
|----------|--------------------------|-------------------------------|---------|
| Light Usage (100 conv/day) | ~$45/month | ~$5.55/month | **87%** |
| Medium Usage (300 conv/day) | ~$135/month | ~$16.65/month | **87%** |
| Heavy Usage (1000 conv/day) | ~$450/month | ~$55.50/month | **87%** |

> Based on routing strategy: 80% simple tasks via Nova 2 Lite + 20% complex tasks via Claude Sonnet.

### vs. Competitors

| Solution | Monthly Cost | Difference |
|----------|--------------|------------|
| ChatGPT Plus (1 user) | $20/user/month | Single user; no messaging platform integration |
| This Solution (1 user) | $67/month | Full control + 20+ messaging platforms + cost control |
| This Solution (5 users) | $13.40/user/month | 33% cheaper than ChatGPT |
| This Solution (20 users) | $3.35/user/month | 83% cheaper than ChatGPT |

---

## Quick Start

### Option A: Automated Build with GitHub Actions (Recommended)

Let GitHub Actions build the AMI for you automatically:

1. **Configure AWS Credentials in GitHub Secrets**:
   - Go to your repository **Settings > Secrets and variables > Actions**
   - Add `AWS_ROLE_ARN` (for OIDC) OR `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
   - See [GitHub Actions Setup Guide](./docs/GITHUB_ACTIONS_SETUP.md) for detailed instructions

2. **Trigger the Build**:
   - Push to `main` branch (auto-trigger)
   - Or go to **Actions** tab → **Build OpenClaw AMI** → **Run workflow**

3. **Get AMI ID**:
   - Check the workflow output for the new AMI ID
   - Update `cloudformation/main.yaml` with the AMI ID

4. **Deploy CloudFormation**:
   ```bash
   aws cloudformation create-stack \
     --stack-name openclaw-enterprise \
     --template-body file://cloudformation/main.yaml \
     --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
     --region us-west-2
   ```

### Option B: Manual Build with Packer

1. Click the CloudFormation Launch Stack button (by Region)
2. Select model, instance type, scenario preset, and other parameters
3. Wait approximately 8 minutes
4. Check the Outputs tab for access information

| Region | Launch |
|--------|--------|
| US West (Oregon) | `Launch Stack` |
| US East (Virginia) | `Launch Stack` |
| EU (Ireland) | `Launch Stack` |
| Asia Pacific (Tokyo) | `Launch Stack` |

### Post-Deployment Connection

```bash
# 1. Install SSM Session Manager plugin (one-time)
#    https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# 2. Get the Elastic IP from CloudFormation Outputs
ELASTIC_IP=$(aws cloudformation describe-stacks \
  --stack-name openclaw-enterprise \
  --query 'Stacks[0].Outputs[?OutputKey==`ElasticIP`].OutputValue' \
  --output text --region us-west-2)

# 3. Access via HTTPS in your browser
echo "https://$ELASTIC_IP"
```

### CLI Deployment

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

## CloudFormation Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `OpenClawModel` | `global.amazon.nova-2-lite-v1:0` | Bedrock Model ID |
| `InstanceType` | `c7g.large` | EC2 instance type (Graviton ARM) |
| `ScenarioPreset` | `general` | Scenario preset: `general` / `ecommerce` / `devops` / `knowledge` / `support` |
| `OpenClawVersion` | `2026.4.27` | OpenClaw version (locked to avoid compatibility issues) |
| `EnableLiteLLM` | `true` | Enable LiteLLM smart routing + caching |
| `MonthlyTokenBudget` | `50` | Monthly token budget (USD); alerts on exceedance |
| `EnableGuardrails` | `false` | Enable Bedrock Guardrails content filtering |
| `GuardrailId` | `""` | Bedrock Guardrail ID (pre-created or auto-created by template) |
| `EnableSandbox` | `true` | Docker sandbox isolation (recommended) |
| `EnableAutoUpdate` | `false` | Auto-update OpenClaw version |
| `EnableBackup` | `true` | S3 daily auto-backup of workspace |
| `EnableMonitoring` | `true` | CloudWatch monitoring + alerts + logs (~$4/month) |
| `CreateVPCEndpoints` | `false` | VPC private endpoints (~$88/month) |

---

## Connect Messaging Platforms

After deployment, connect your required platforms in the Web UI under "Channels":

| Platform | Configuration Method |
|----------|---------------------|
| WhatsApp | Scan QR code |
| Telegram | Create Bot via @BotFather; paste Token |
| Discord | Create App in Developer Portal; paste Bot Token |
| Slack | Create App at api.slack.com; install to Workspace |
| Feishu / Lark | Community plugin openclaw-feishu |
| Microsoft Teams | Azure Bot registration |
| WebChat | Built-in; no additional configuration needed |

---

## Project Structure

```
OpenClawBedrock/
├── packer/                           # AMI Build
│   ├── openclaw-bedrock.pkr.hcl     # Packer configuration
│   └── files/                       # Pre-installed files and service configs
│       ├── nginx/                   # Nginx SSL configuration templates
│       ├── certbot/                 # Let's Encrypt certificate automation scripts
│       └── userdata/                # UserData initialization scripts
├── cloudformation/                   # Deployment Templates
│   ├── main.yaml                    # Main template
│   └── nested/                      # Nested templates (VPC/IAM/LiteLLM/Monitoring)
├── dashboard/                        # Management Console (Static Web)
├── skills/                           # Pre-audited Skills
├── scenarios/                        # Scenario Presets (SOUL.md + Skills)
│   ├── general/                     # General Assistant
│   ├── ecommerce/                   # Cross-Border E-commerce
│   ├── devops/                      # DevOps Automation
│   ├── knowledge/                   # Knowledge Management
│   └── support/                     # Customer Service
├── compliance/                       # Compliance Documentation Pack
├── scripts/                          # Build/Deploy/Test Scripts
└── docs/                             # User Documentation
```

---

## Security Architecture

| Layer | Measures |
|-------|----------|
| **Network** | SSM Session Manager encrypted tunnel; no open ports; minimized security group inbound rules |
| **Identity** | IAM Role (EC2 Instance Profile); automatic credential rotation; no long-term keys |
| **Instance** | IMDSv2 enforced (HttpTokens: required); Docker sandbox isolation |
| **Data** | SSM Parameter Store (KMS encrypted) for Gateway Token; S3 server-side encryption |
| **Supply Chain** | Docker GPG-signed repository; NVM download then execute (no curl | sh); fixed npm registry |
| **Audit** | CloudTrail records all Bedrock API calls; CloudWatch Logs retains operational logs |
| **Content** | Bedrock Guardrails filters违规 content, PII redaction, topic restrictions |
| **Transport** | Let's Encrypt SSL certificate for IP; TLS 1.2/1.3 enforced; HSTS enabled |

---

## License & Compliance

- **OpenClaw**: [MIT License](https://github.com/openclaw/openclaw/blob/main/LICENSE)
- **This Product**: Built on OpenClaw with additional security hardening, cost control, operational automation, and scenario presets
- **Third-Party Licenses**: See [THIRD-PARTY-LICENSES.txt](./THIRD-PARTY-LICENSES.txt)
- **AWS Services**: Uses Amazon Bedrock, EC2, S3, CloudWatch, SSM, CloudTrail, etc.; billed per AWS official pricing

---

## Support

- **Issue Reporting**: GitHub Issues
- **OpenClaw Community**: [Discord](https://discord.gg/openclaw) / [GitHub Issues](https://github.com/openclaw/openclaw/issues)
- **AWS Bedrock**: [AWS re:Post](https://repost.aws/)
