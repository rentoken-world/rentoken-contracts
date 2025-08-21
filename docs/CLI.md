# RWA CLI 工具使用文档

## 概述

RWA CLI 工具 (`bin/rwa`) 是基于 Foundry cast 的链下命令行工具，用于管理和测试 RentToken RWA 系统。

## 命名原则

- **动词:名词** 风格，语义单一、原子化
- **读操作** 默认无副作用
- **写操作** 默认需要 `--yes` 或 `FORCE=1` 环境变量
- **统一旗标** `--dry-run` 仅打印将执行的 cast 命令，不落链
- **地址解析** 支持 .env 中的 ROLE（如 ADMIN/USER1）和直接地址

## 命令清单

### 账户/环境

#### `addr:show <ROLE>`
显示角色对应的地址（从 .env 读取）
```bash
bin/rwa addr:show ADMIN
bin/rwa addr:show USER1
```

#### `block:time`
显示当前区块时间戳
```bash
bin/rwa block:time
```

#### `block:chainid`
显示当前链ID
```bash
bin/rwa block:chainid
```

### KYC 管理

#### `kyc:check <addr>`
检查地址的 KYC 状态
```bash
bin/rwa kyc:check $USER1_ADDRESS
bin/rwa kyc:check 0x1234...
```

#### `kyc:add <addr> [--yes] [--dry-run]`
将地址添加到 KYC 白名单
```bash
bin/rwa kyc:add $USER1_ADDRESS --yes
bin/rwa kyc:add USER1 --dry-run  # 使用角色名
```

#### `kyc:remove <addr> [--yes] [--dry-run]`
从 KYC 白名单移除地址
```bash
bin/rwa kyc:remove $USER1_ADDRESS --yes
```

### 房产管理（PropertyOracle）

#### `property:add --id <id> --payout <token> --valuation <amount> --min <amount> --max <amount> --start <timestamp> --end <timestamp> --landlord <addr> --doc-hash <hash> --url <url> [--yes] [--dry-run]`
添加或更新房产信息
```bash
bin/rwa property:add \
    --id 1 \
    --payout $USDC_ADDR \
    --valuation 28800000000 \
    --min 20000000000 \
    --max 30000000000 \
    --start +3600 \
    --end +157680000 \
    --landlord USER1 \
    --doc-hash 0x1234... \
    --url "https://example.com/property/1" \
    --yes
```

### 系列管理（SeriesFactory & RentToken）

#### `series:create <propertyId> <name> <symbol> [--yes] [--dry-run]`
为房产创建 RentToken 系列
```bash
bin/rwa series:create 1 "RenToken Test Apartment 001" "RTTA1" --yes
```

#### `series:oracles:set <propertyId> <kycAddr> <sanctionAddr> [--yes] [--dry-run]`
为系列设置 Oracle 地址
```bash
bin/rwa series:oracles:set 1 $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR --yes
```

#### `series:addr <propertyId>`
查询系列合约地址
```bash
bin/rwa series:addr 1
```

#### `series:info <seriesAddr|propertyId>`
显示系列详细信息（名称、符号、小数位、总供应量、阶段等）
```bash
bin/rwa series:info 1
bin/rwa series:info 0x1234...
```

#### `series:phase <seriesAddr|propertyId>`
显示系列当前阶段
```bash
bin/rwa series:phase 1
```

#### `series:contribute <seriesAddr|propertyId> <amount> [--from <role|addr>] [--yes] [--dry-run]`
向系列贡献资金
```bash
bin/rwa series:contribute 1 100000000 --from USER1 --yes
```

#### `series:transfer <seriesAddr|propertyId> <to> <amount> [--from <role|addr>] [--yes] [--dry-run]`
转移系列代币
```bash
bin/rwa series:transfer 1 USER2 50000000 --from USER1 --yes
```

#### `series:claimable <seriesAddr|propertyId> <addr>`
查询地址的可提取收益
```bash
bin/rwa series:claimable 1 USER1
```

### 工厂收益管理

#### `factory:profit:receive <propertyId> <amount> [--yes] [--dry-run]`
向系列分发收益
```bash
bin/rwa factory:profit:receive 1 100000000 --yes
```

### ERC20 通用操作

#### `erc20:approve <token> <spender> <amount> [--from <role|addr>] [--yes] [--dry-run]`
授权 ERC20 代币
```bash
bin/rwa erc20:approve $USDC_ADDR $SERIES_ADDR 100000000 --from USER1 --yes
```

#### `erc20:balance <token> <addr>`
查询 ERC20 余额
```bash
bin/rwa erc20:balance $USDC_ADDR USER1
```

### 本地测试辅助

#### `imp:start <addr>`
开始模拟地址（anvil impersonate）
```bash
bin/rwa imp:start $USDC_WHALE
```

#### `imp:stop <addr>`
停止模拟地址
```bash
bin/rwa imp:stop $USDC_WHALE
```

#### `time:increase <seconds>`
增加区块时间
```bash
bin/rwa time:increase 3600
```

#### `mine`
挖掘新区块
```bash
bin/rwa mine
```

## 函数签名覆盖

如果合约中的实际函数名与默认不同，可以在 CLI 顶部通过环境变量覆盖：

```bash
export SIG_KYC_CHECK="isWhitelisted(address)(bool)"
export SIG_KYC_ADD="addToWhitelist(address)"
export SIG_PROPERTY_ADD="addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))"
export SIG_SERIES_CREATE="createSeries(uint256,string,string)"
export SIG_SERIES_ADDR_BY_ID="getSeriesAddress(uint256)(address)"
export SIG_SERIES_SET_ORACLES="setOraclesForSeries(uint256,address,address)"
export SIG_FACTORY_RECEIVE_PROFIT="receiveProfit(uint256,uint256)"
```

## 演示脚本映射

### Case 1 脚本映射

| 原 case_1.sh 步骤 | 对应 CLI 命令 |
|---|---|
| 添加房产到 PropertyOracle | `bin/rwa property:add --id 1 --payout $USDC_ADDR --valuation 28800000000 --min 20000000000 --max 30000000000 --start +3600 --end +157680000 --landlord USER1 --doc-hash 0x... --url https://... --yes` |
| 添加用户到 KYC 白名单 | `bin/rwa kyc:add USER1 --yes`<br/>`bin/rwa kyc:add USER2 --yes`<br/>`bin/rwa kyc:add USER3 --yes` |
| 创建 RentToken 系列 | `bin/rwa series:create 1 "RenToken Test Apartment 001" "RTTA1" --yes` |
| 设置系列 Oracle | `bin/rwa series:oracles:set 1 $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR --yes` |
| 验证系列信息 | `bin/rwa series:info 1`<br/>`bin/rwa series:phase 1` |
| 查询用户余额 | `bin/rwa erc20:balance $USDC_ADDR USER1` |

### Test Simple 脚本映射

| 原 test_simple.sh 步骤 | 对应 CLI 命令 |
|---|---|
| 创建系列 | `bin/rwa series:create 1 "RenToken Test" "RTTEST" --yes` |
| 设置 Oracle | `bin/rwa series:oracles:set 1 $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR --yes` |
| 添加用户到 KYC | `bin/rwa kyc:add USER1 --yes`<br/>`bin/rwa kyc:add USER2 --yes` |
| 用户投资 | `bin/rwa erc20:approve $USDC_ADDR $SERIES_ADDR 100000000 --from USER1 --yes`<br/>`bin/rwa series:contribute 1 100000000 --from USER1 --yes` |
| 时间推进 | `bin/rwa time:increase 3601`<br/>`bin/rwa mine` |
| 用户转账 | `bin/rwa series:transfer 1 USER2 50000000 --from USER1 --yes` |
| 分发收益 | `bin/rwa erc20:approve $USDC_ADDR $SERIES_FACTORY_ADDR 100000000 --from ADMIN --yes`<br/>`bin/rwa factory:profit:receive 1 100000000 --yes` |
| 查询可提取收益 | `bin/rwa series:claimable 1 USER1` |

## 配置文件

### 环境变量 (.env)
- `RPC_URL` - RPC 端点
- `CHAIN_ID` - 链ID
- `NETWORK` - 网络名称（用于选择 addresses 文件）
- `ADMIN_PRIVATE_KEY`, `USER1_PRIVATE_KEY`, 等 - 私钥
- `USDC_ADDR`, `USDC_WHALE` - 主网地址

### 地址文件 (addresses/${NETWORK}.json)
```json
{
  "KYCOracle": "0x...",
  "PropertyOracle": "0x...", 
  "SeriesFactory": "0x...",
  "RentTokenImpl": "0x...",
  "SanctionOracle": "0x..."
}
```

## 安全特性

- **写操作保护** 所有写操作默认需要 `--yes` 确认
- **干运行模式** `--dry-run` 显示将执行的命令但不执行
- **链校验** 检查当前链ID与配置是否一致
- **私钥保护** 支持 keystore 文件替代明文私钥
- **角色解析** 支持使用角色名替代地址，提高可读性

## 错误处理

常见错误及解决方案：

1. **RPC 未启动** - 确保 anvil 在指定端口运行
2. **CHAIN_ID 不一致** - 检查 .env 中的 CHAIN_ID 设置
3. **地址文件未填** - 运行 `scripts/init-local.sh` 初始化
4. **缺少依赖** - 安装 `cast` 和 `jq`
5. **权限不足** - 检查私钥和角色权限
6. **余额不足** - 确保账户有足够的 ETH 和代币
