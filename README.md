# Rentoken - 房产租金收益代币化平台

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Forge-orange.svg)](https://getfoundry.sh/)

## 项目概述

Rentoken 是一个面向房产租金收益的 RWA（Real World Asset）协议，允许房东将未来
1-5 年的房租应收款上链，发行合规受限的 ERC20 Token。每个房产对应一个 ERC20
Token，房租定期打入合约，持有人可以随时提取利润。

## 核心特性

- 🏠 **房产代币化**: 将线下房产租金收益转化为链上可交易代币
- 🔒 **合规控制**: 集成 KYC 和制裁检查，确保合规性
- 💰 **收益分配**: 自动化的租金收益分配机制
- 🚀 **流动性支持**: 内置 AMM 流动性池，支持代币交易
- 🛡️ **安全设计**: 基于 Foundry 开发，采用最佳安全实践

## 系统架构

### 核心合约

- **SeriesFactory**: 平台控制入口，管理房产系列和资金路由
- **RentToken**: 基于ERC20 代币合约，支持发行流程控制，收益分配和受限转账
- **PropertyOracle**: 房产信息 Oracle，提供链上房产数据
- **KYCOracle**: KYC 白名单管理
- **SanctionOracle**: 制裁地址检查
- **KycPool**: KYC 版本的 Uniswap v2 流动性池

### 业务流程

1. **房产注册**: 房东通过 PropertyOracle 注册房产信息
2. **系列创建**: SeriesFactory 为房产创建对应的 RentToken 系列
3. **投资募集**: 合格投资者参与代币认购
4. **收益分配**: 租金定期分配，持有人可随时提取
5. **流动性交易**: 通过 KycPool 进行代币交易

## 项目结构

```
rentoken-contracts/
├── src/                   # 智能合约源码
│   ├── ammpool/           # AMM 流动性池相关合约
│   ├── interfaces/        # 合约接口定义
│   ├── mocks/             # 测试用模拟合约
│   ├── SeriesFactory.sol  # 系列工厂合约
│   ├── RentToken.sol      # 租金代币合约
│   ├── PropertyOracle.sol # 房产信息 Oracle
│   └── KYCOracle.sol      # KYC 管理合约
├── test/                  # 测试文件
│   ├── json0755/          # 核心合约测试
│   ├── e2e_test_cases/    # 端到端测试用例
│   └── KycPool.t.sol      # 流动性池测试
├── lib/                   # 外部依赖库
├── dev_scripts/           # 开发和部署脚本
├── foundry.toml           # Foundry 配置文件
└── .env.example           # 环境变量示例
```

## 快速开始

### 环境要求

- [Foundry](https://getfoundry.sh/) (推荐最新版本)
- Git

### 安装依赖

```bash
# 克隆项目
git clone <repository-url>
cd rentoken-contracts

# 安装 Foundry 依赖
forge install
```

### 编译合约

```bash
# 编译所有合约
forge build

# 格式化代码
forge fmt

# 运行测试
forge test
```

### 本地开发

```bash
# 启动本地节点
anvil

# 在另一个终端中部署到本地网络
forge script dev_scripts/init-local.sh --rpc-url http://localhost:8545 --broadcast

# 或者使用环境变量文件
source dev_scripts/anvil.env
forge script dev_scripts/init-local.sh --rpc-url $RPC_URL --broadcast
```

## 测试

项目包含完整的测试套件：

- **单元测试**: 核心合约功能测试
- **模糊测试**: 边界条件和异常情况测试
- **不变量测试**: 关键业务逻辑验证
- **端到端测试**: 完整业务流程测试

运行测试：

```bash
# 运行所有测试
forge test

# 运行测试并显示详细输出
forge test -vvv

# 运行特定测试文件
forge test --match-contract RentTokenTest

# 生成测试覆盖率报告
forge coverage
```

## 部署

### 环境配置

1. 复制 `.env.example` 为 `.env`
2. 配置网络 RPC 和私钥信息
3. 设置目标网络参数

### 部署命令

```bash
# 部署到测试网
forge script dev_scripts/init-sepolia.sh --rpc-url $RPC_URL --broadcast --verify

# 部署到主网（需要相应的部署脚本）
# forge script dev_scripts/init-mainnet.sh --rpc-url $MAINNET_RPC --broadcast --verify
```

## 开发指南

### 代码规范

- 遵循
  [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- 使用 `forge fmt` 自动格式化代码
- 所有公开函数必须包含 NatSpec 注释
- 使用自定义错误替代 require 字符串

### 安全实践

- 所有外部调用必须处理返回值
- 使用 `nonReentrant` 修饰符防止重入攻击
- 输入参数必须进行边界检查
- 关键操作需要适当的权限控制

### 测试要求

- 测试覆盖率不低于 90%
- 必须包含单元测试、模糊测试和不变量测试
- 关键路径需要 100% 覆盖

## 文档

- **[项目规范](.cursorrules)**: 开发规范和最佳实践
- **[测试用例文档](test/e2e_test_cases/test_cases_documentation.md)**: 端到端测
  试用例说明
- **[开发脚本](dev_scripts/)**: 各种环境的部署和初始化脚本

## 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 提交规范

使用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

- `feat:` 新功能
- `fix:` 错误修复
- `docs:` 文档更新
- `style:` 代码格式调整
- `refactor:` 代码重构
- `test:` 测试相关
- `chore:` 构建过程或辅助工具的变动

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 联系我们

- 项目主页: [https://github.com/rentoken-world/rentoken-contracts]
- 问题反馈: [https://github.com/rentoken-world/rentoken-contracts/issues]

## 免责声明

本软件按"原样"提供，不提供任何明示或暗示的保证。使用本软件的风险由用户自行承担。

---

**注意**: 这是一个金融协议，涉及真实资产和资金。在生产环境使用前，请确保充分理解
相关风险，并咨询法律和金融专业人士。
