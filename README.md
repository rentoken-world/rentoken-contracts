# RenToken Contracts

一个基于 Solidity 和 Foundry 的房地产代币化 (RWA) 系统，支持房产投资、收益分配和 KYC 合规。

## 项目概述

本项目实现了一个完整的房地产代币化平台，包括：

- **房产 Oracle** - 管理房产信息和估值
- **KYC Oracle** - 处理用户身份验证
- **系列工厂** - 为每个房产创建对应的 ERC20 代币系列
- **租金代币** - 代表房产投资份额的 ERC20 代币
- **收益分配** - 自动化的租金收益分配机制

## 技术栈

- **Solidity ^0.8.24** - 智能合约语言
- **Foundry** - 开发和测试框架
- **OpenZeppelin** - 安全的智能合约库
- **Bash** - CLI 工具和脚本

## 项目结构

```
rentoken-contracts/
├── src/                    # 智能合约源码
│   ├── KYCOracle.sol      # KYC 身份验证 Oracle
│   ├── PropertyOracle.sol # 房产信息 Oracle
│   ├── SeriesFactory.sol  # 系列代币工厂
│   ├── RentToken.sol      # 租金代币实现
│   ├── interfaces/        # 合约接口
│   └── mocks/             # 测试模拟合约
├── test/                  # 测试文件
├── script/                # 部署脚本
├── bin/                   # CLI 工具
│   └── rwa               # 主要的 CLI 工具
├── scripts/               # 辅助脚本
├── addresses/             # 合约地址管理
├── docs/                  # 文档
│   └── CLI.md            # CLI 使用文档
├── contracts/             # 旧版合约（兼容）
└── foundry.toml          # Foundry 配置
```

## 快速开始

### 1. 安装依赖

确保你已安装：

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [jq](https://stedolan.github.io/jq/) (用于 JSON 处理)

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 安装 jq (macOS)
brew install jq

# 安装 jq (Ubuntu)
sudo apt-get install jq
```

### 2. 设置环境

```bash
# 克隆仓库
git clone <repository-url>
cd rentoken-contracts

# 安装依赖
forge install
```

### 3. 选择网络环境

#### 选项 A: 本地 Fork (推荐用于开发)

```bash
# 启动 Anvil 主网 fork
scripts/anvil-fork.sh &

# 部署合约并初始化环境
scripts/init-local.sh
```

#### 选项 B: Sepolia 测试网 (推荐用于演示)

```bash
# 复制并配置环境文件
cp .env.example .env
# 编辑 .env 填入你的 Infura URL 和私钥

# 测试 CLI 基本功能（无需合约部署）
scripts/test_sepolia_cli.sh

# 如果有足够的测试 ETH，部署合约
scripts/init-sepolia.sh
```

初始化完成后，你会得到：
- 部署好的合约地址
- 预充值的测试账户（本地）或配置好的测试账户（Sepolia）
- 配置好的 `.env` 文件
- 地址文件 `addresses/mainnet-fork.json` 或 `addresses/sepolia.json`

## CLI 使用 & 本地演练

### 基础验证

```bash
# 检查账户地址
bin/rwa addr:show ADMIN
bin/rwa addr:show USER1

# 检查网络状态
bin/rwa block:chainid
bin/rwa block:time

# 检查合约部署状态
bin/rwa kyc:check $(bin/rwa addr:show ADMIN)
```

### 完整演示流程

#### 1. 房产管理
```bash
# 添加房产
bin/rwa property:add \
  --id 1 \
  --payout $USDC_ADDR \
  --valuation 28800000000 \
  --min 20000000000 \
  --max 30000000000 \
  --start +3600 \
  --end +157680000 \
  --landlord USER1 \
  --doc-hash 0x1234567890123456789012345678901234567890123456789012345678901234 \
  --url https://example.com/property/1 \
  --yes
```

#### 2. 系列创建
```bash
# 创建代币系列
bin/rwa series:create 1 "RenToken Test Apartment 001" "RTTA1" --yes

# 设置 Oracle
bin/rwa series:oracles:set 1 $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR --yes

# 查看系列信息
bin/rwa series:info 1
```

#### 3. KYC 管理
```bash
# 添加用户到 KYC 白名单
bin/rwa kyc:add USER1 --yes
bin/rwa kyc:add USER2 --yes

# 检查 KYC 状态
bin/rwa kyc:check USER1
bin/rwa kyc:check USER4  # 应该是 false
```

#### 4. 投资和交易
```bash
# 用户投资
bin/rwa erc20:approve $USDC_ADDR $(bin/rwa series:addr 1) 100000000 --from USER1 --yes
bin/rwa series:contribute 1 100000000 --from USER1 --yes

# 推进时间到收益阶段
bin/rwa time:increase 3601
bin/rwa mine

# 用户间转账
bin/rwa series:transfer 1 USER2 50000000 --from USER1 --yes

# 分配收益
bin/rwa erc20:approve $USDC_ADDR $SERIES_FACTORY_ADDR 100000000 --from ADMIN --yes
bin/rwa factory:profit:receive 1 100000000 --yes

# 检查可提取收益
bin/rwa series:claimable 1 USER1
```

### 运行演示脚本

我们提供了两个完整的演示脚本：

```bash
# 运行 Case 1 演示（CLI 版本）
scripts/case_1_with_cli.sh

# 运行简化测试（CLI 版本）
scripts/test_simple_with_cli.sh
```

这些脚本展示了从房产添加到收益分配的完整流程。

## 网络支持

### Sepolia 测试网
- **Chain ID**: 11155111  
- **优势**: 真实网络环境，公开可验证
- **要求**: 需要测试网 ETH（可从水龙头获取）
- **配置**: 见 `.env.example`

参考的 Infura URL: `https://sepolia.infura.io/v3/cdfcb5cf1f7b4953862dc9238a7d59e8`

### 主网 Fork (本地)
- **Chain ID**: 1
- **优势**: 快速测试，无需真实 ETH
- **要求**: 主网 RPC URL
- **配置**: 自动设置

## 常见错误排查

### 1. 网络连接问题
```bash
# 错误：connection refused
# 解决（本地）：启动 Anvil
scripts/anvil-fork.sh &

# 解决（Sepolia）：检查 RPC URL
bin/rwa block:chainid
```

### 2. CHAIN_ID 不一致
```bash
# 错误：Chain ID mismatch
# 解决：检查 .env 中的 CHAIN_ID 设置
bin/rwa block:chainid  # 查看当前链ID
# Sepolia: 11155111, Mainnet Fork: 1
```

### 3. 地址文件未填
```bash
# 错误：Address file not found
# 解决：重新初始化
scripts/init-local.sh      # 本地
scripts/init-sepolia.sh    # Sepolia
```

### 4. 缺少依赖
```bash
# 错误：command not found: cast
# 解决：安装 Foundry
curl -L https://foundry.paradigm.xyz | bash

# 错误：command not found: jq  
# 解决：安装 jq
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu

# 错误：library not found
# 解决：安装合约依赖
forge install
```

### 5. Sepolia 测试网余额不足
```bash
# 错误：insufficient funds
# 解决：从水龙头获取测试 ETH
echo "Need to fund: $(bin/rwa addr:show ADMIN)"
# 访问：https://sepoliafaucet.com/
#      https://www.alchemy.com/faucets/ethereum-sepolia
```

### 6. 权限问题
```bash
# 错误：permission denied
# 解决：检查私钥设置和角色权限
bin/rwa addr:show ADMIN  # 确认地址正确
```

## CLI 工具说明

CLI 工具 `bin/rwa` 提供了完整的合约交互功能：

- **账户管理** - 地址查询、区块链信息
- **KYC 管理** - 白名单操作
- **房产管理** - 房产信息管理
- **系列管理** - 代币系列操作
- **收益管理** - 收益分配
- **ERC20 操作** - 通用代币操作
- **测试辅助** - 时间操作、账户模拟

详细使用说明请参考 [CLI 文档](docs/CLI.md)。

## 安全特性

- **访问控制** - 基于角色的权限管理
- **KYC 验证** - 投资者身份验证
- **制裁检查** - 合规性验证
- **重入保护** - 防止重入攻击
- **输入验证** - 严格的参数校验
- **时间锁定** - 阶段控制机制

## 开发指南

### 运行测试
```bash
forge test -vvv
```

### 部署到测试网
```bash
# 设置测试网环境变量
export RPC_URL=https://goerli.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x...

# 运行部署
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

### 代码格式化
```bash
forge fmt
```

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

## 贡献

欢迎贡献代码！请确保：

1. 遵循项目的编码规范（见 `.cursorrules`）
2. 运行测试确保功能正常
3. 更新相关文档
4. 提交清晰的 commit 消息

## 支持

如有问题，请：

1. 查看 [CLI 文档](docs/CLI.md)
2. 检查常见错误排查部分
3. 创建 GitHub Issue
