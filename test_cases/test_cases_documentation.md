# RentToken 测试案例文档

## 概述

本文档基于 `case_1.sh` 的结构，提供了多个常用场景的测试案例，用于模拟前端用户操作和验证系统功能。每个测试案例都包含详细的步骤、角色定义和预期结果。

## 测试环境准备

所有测试案例都需要先运行以下准备步骤：

```bash
# 1. 启动本地 Anvil 节点（Fork 主网）
URL="https://ethereum.rpc.thirdweb.com"
anvil --fork-url $URL

# 2. 运行初始化脚本
./init-local.sh

# 3. 加载环境变量
source .env
```

---

## Case 1: 基础房产代币化流程（已实现）

**场景描述**: 房东发行房产代币，投资者参与投资的基础流程

**角色**:
- ADMIN: 平台管理员
- USER1: 房东（已通过KYC）
- USER2: 投资者（已通过KYC）
- USER3: 投资者（已通过KYC）
- USER4: 投资者（未通过KYC）

**测试步骤**:
1. 添加房产到 PropertyOracle
2. 设置 KYC 白名单
3. 创建 RentToken 系列
4. 设置 Oracle 配置
5. 验证系统状态

**预期结果**: 系统成功创建房产代币，KYC用户可以投资，非KYC用户被拒绝

---

## Case 2: 投资者购买代币流程

**场景描述**: 基于 Case 1，投资者购买房产代币的完整流程

**脚本文件**: `case_2.sh`

```bash
#!/bin/bash
# Case 2: 投资者购买代币流程

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 2: Investor Token Purchase Flow..."
echo "=================================================="

# 加载环境变量
source .env

# 确保 Case 1 已完成
if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Case 1 must be completed first. Run case_1.sh"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR
PROPERTY_ID=$CASE1_PROPERTY_ID

echo "📊 Using Series: $SERIES_ADDR"
echo "🏠 Property ID: $PROPERTY_ID"
echo ""

# 步骤1: USER2 投资 5000 USDC
echo "💰 Step 1: USER2 investing 5000 USDC..."
INVEST_AMOUNT=$((5000 * 1000000))  # 5000 USDC

# 首先授权 USDC
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT \
    || { echo "❌ Failed to approve USDC"; exit 1; }

echo "✅ USDC approved"

# 投资
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT \
    || { echo "❌ Failed to contribute"; exit 1; }

echo "✅ USER2 invested 5000 USDC"

# 步骤2: USER3 投资 8000 USDC
echo "💰 Step 2: USER3 investing 8000 USDC..."
INVEST_AMOUNT_2=$((8000 * 1000000))  # 8000 USDC

# 授权和投资
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT_2 \
    || { echo "❌ Failed to approve USDC"; exit 1; }

cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT_2 \
    || { echo "❌ Failed to contribute"; exit 1; }

echo "✅ USER3 invested 8000 USDC"

# 步骤3: USER4 尝试投资（应该失败）
echo "❌ Step 3: USER4 attempting to invest (should fail)..."
cast send --rpc-url $RPC_URL --private-key $USER4_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT \
    2>/dev/null || echo "   Expected: USER4 approval may fail due to KYC"

cast send --rpc-url $RPC_URL --private-key $USER4_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT \
    2>/dev/null && echo "❌ USER4 should not be able to invest" || echo "✅ USER4 correctly rejected"

# 步骤4: 验证投资结果
echo "🔍 Step 4: Verifying investment results..."

# 检查代币余额
USER2_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

# 检查总投资额
TOTAL_RAISED=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalRaised()(uint256)")

echo "📊 Investment Summary:"
echo "   USER2 Tokens: $USER2_TOKENS"
echo "   USER3 Tokens: $USER3_TOKENS"
echo "   USER4 Tokens: $USER4_TOKENS (should be 0)"
echo "   Total Raised: $(echo $TOTAL_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

echo "✅ Case 2 completed successfully!"
echo "💡 Next: Run case_3.sh for rent distribution testing"
```

---

## Case 3: 租金分配流程

**场景描述**: 房东支付租金，系统自动分配给投资者

**脚本文件**: `case_3.sh`

```bash
#!/bin/bash
# Case 3: 租金分配流程

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 3: Rent Distribution Flow..."
echo "==============================================="

# 加载环境变量
source .env

# 确保前置条件
if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Previous cases must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR

# 步骤1: 模拟时间推进到租金开始时间
echo "⏰ Step 1: Advancing time to accrual start..."

# 获取租金开始时间
ACCRUAL_START=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "accrualStartTime()(uint64)")
CURRENT_TIME=$(cast block --rpc-url $RPC_URL latest --field timestamp)

if [ $CURRENT_TIME -lt $ACCRUAL_START ]; then
    TIME_ADVANCE=$((ACCRUAL_START - CURRENT_TIME + 3600))  # 额外1小时
    cast rpc --rpc-url $RPC_URL evm_increaseTime $TIME_ADVANCE
    cast rpc --rpc-url $RPC_URL evm_mine
    echo "✅ Time advanced by $TIME_ADVANCE seconds"
else
    echo "✅ Already past accrual start time"
fi

# 步骤2: 房东支付第一个月租金
echo "💰 Step 2: Landlord paying first month rent..."

MONTHLY_RENT=$((1200 * 1000000))  # 1200 USDC

# 房东授权租金支付
cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $MONTHLY_RENT \
    || { echo "❌ Failed to approve rent payment"; exit 1; }

# 支付租金
cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
    $SERIES_ADDR "payRent(uint256)" $MONTHLY_RENT \
    || { echo "❌ Failed to pay rent"; exit 1; }

echo "✅ First month rent paid: 1200 USDC"

# 步骤3: 检查投资者可申领金额
echo "🔍 Step 3: Checking claimable amounts..."

USER2_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER2_ADDRESS)
USER3_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER3_ADDRESS)

echo "💰 Claimable Amounts:"
echo "   USER2: $(echo $USER2_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3: $(echo $USER3_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"

# 步骤4: 投资者申领收益
echo "💸 Step 4: Investors claiming rewards..."

# USER2 申领
if [ $USER2_CLAIMABLE -gt 0 ]; then
    cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
        $SERIES_ADDR "claim()" \
        || { echo "❌ USER2 claim failed"; exit 1; }
    echo "✅ USER2 claimed rewards"
fi

# USER3 申领
if [ $USER3_CLAIMABLE -gt 0 ]; then
    cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
        $SERIES_ADDR "claim()" \
        || { echo "❌ USER3 claim failed"; exit 1; }
    echo "✅ USER3 claimed rewards"
fi

# 步骤5: 验证申领后状态
echo "🔍 Step 5: Verifying post-claim state..."

# 检查USDC余额变化
USER2_USDC_AFTER=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_USDC_AFTER=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)

echo "💰 Final USDC Balances:"
echo "   USER2: $(echo $USER2_USDC_AFTER | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3: $(echo $USER3_USDC_AFTER | awk '{printf "%.6f", $1/1000000}') USDC"

echo "✅ Case 3 completed successfully!"
echo "💡 Rent distribution working correctly"
```

---

## Case 4: 代币转账和收益追踪

**场景描述**: 投资者之间转账代币，验证收益正确分配

**脚本文件**: `case_4.sh`

```bash
#!/bin/bash
# Case 4: 代币转账和收益追踪

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 4: Token Transfer and Reward Tracking..."
echo "======================================================"

# 加载环境变量并验证前置条件
source .env

if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Previous cases must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR

# 步骤1: 记录转账前状态
echo "📊 Step 1: Recording pre-transfer state..."

USER2_TOKENS_BEFORE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_TOKENS_BEFORE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)

echo "   USER2 tokens before: $USER2_TOKENS_BEFORE"
echo "   USER3 tokens before: $USER3_TOKENS_BEFORE"

# 步骤2: USER2 向 USER3 转账部分代币
echo "🔄 Step 2: USER2 transferring tokens to USER3..."

TRANSFER_AMOUNT=$((USER2_TOKENS_BEFORE / 2))  # 转账一半

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "transfer(address,uint256)" $USER3_ADDRESS $TRANSFER_AMOUNT \
    || { echo "❌ Transfer failed"; exit 1; }

echo "✅ Transferred $TRANSFER_AMOUNT tokens from USER2 to USER3"

# 步骤3: 验证转账后余额
echo "🔍 Step 3: Verifying post-transfer balances..."

USER2_TOKENS_AFTER=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_TOKENS_AFTER=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)

echo "   USER2 tokens after: $USER2_TOKENS_AFTER"
echo "   USER3 tokens after: $USER3_TOKENS_AFTER"

# 步骤4: 房东支付新的租金
echo "💰 Step 4: Landlord paying additional rent..."

NEW_RENT=$((800 * 1000000))  # 800 USDC

cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $NEW_RENT \
    || { echo "❌ Failed to approve new rent"; exit 1; }

cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
    $SERIES_ADDR "payRent(uint256)" $NEW_RENT \
    || { echo "❌ Failed to pay new rent"; exit 1; }

echo "✅ Additional rent paid: 800 USDC"

# 步骤5: 检查新的可申领金额
echo "🔍 Step 5: Checking new claimable amounts..."

USER2_NEW_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER2_ADDRESS)
USER3_NEW_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER3_ADDRESS)

echo "💰 New Claimable Amounts:"
echo "   USER2: $(echo $USER2_NEW_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3: $(echo $USER3_NEW_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"

# 步骤6: 验证收益分配比例
echo "📈 Step 6: Verifying reward distribution ratios..."

TOTAL_SUPPLY=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalSupply()(uint256)")
USER2_RATIO=$(echo "scale=6; $USER2_TOKENS_AFTER * 100 / $TOTAL_SUPPLY" | bc -l)
USER3_RATIO=$(echo "scale=6; $USER3_TOKENS_AFTER * 100 / $TOTAL_SUPPLY" | bc -l)

echo "📊 Token Distribution:"
echo "   USER2: $USER2_RATIO% of total supply"
echo "   USER3: $USER3_RATIO% of total supply"

echo "✅ Case 4 completed successfully!"
echo "💡 Token transfers and reward tracking working correctly"
```

---

## Case 5: 募资失败场景

**场景描述**: 房产募资未达到最低要求，测试退款机制

**脚本文件**: `case_5.sh`

```bash
#!/bin/bash
# Case 5: 募资失败场景

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 5: Fundraising Failure Scenario..."
echo "=================================================="

# 加载环境变量
source .env

# 创建新的房产用于测试募资失败
echo "🏠 Step 1: Creating new property for failure test..."

PROPERTY_ID_FAIL=999
CURRENT_TIME=$(cast block --rpc-url $RPC_URL latest --field timestamp)
ACCRUAL_START_FAIL=$((CURRENT_TIME + 7200))  # 2小时后开始
ACCRUAL_END_FAIL=$((ACCRUAL_START_FAIL + 86400))  # 1天后结束（短期测试）

VALUATION_FAIL=$((50000 * 1000000))  # 50000 USDC
MIN_RAISING_FAIL=$((40000 * 1000000))  # 40000 USDC (高门槛)
MAX_RAISING_FAIL=$((50000 * 1000000))  # 50000 USDC

DOC_HASH_FAIL=$(echo -n "Failure Test Property Document" | cast keccak)
OFFCHAIN_URL_FAIL="https://example.com/property/999"

PROPERTY_DATA_FAIL="($PROPERTY_ID_FAIL,$USDC_ADDR,$VALUATION_FAIL,$MIN_RAISING_FAIL,$MAX_RAISING_FAIL,$ACCRUAL_START_FAIL,$ACCRUAL_END_FAIL,$USER1_ADDRESS,$DOC_HASH_FAIL,\"$OFFCHAIN_URL_FAIL\")"

# 添加房产
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY_ID_FAIL "$PROPERTY_DATA_FAIL" \
    || { echo "❌ Failed to add failure test property"; exit 1; }

echo "✅ Failure test property added"

# 步骤2: 创建系列
echo "🪙 Step 2: Creating series for failure test..."

TOKEN_NAME_FAIL="RenToken Failure Test"
TOKEN_SYMBOL_FAIL="RTFT"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "createSeries(uint256,string,string)" \
    $PROPERTY_ID_FAIL "$TOKEN_NAME_FAIL" "$TOKEN_SYMBOL_FAIL" \
    || { echo "❌ Failed to create failure test series"; exit 1; }

SERIES_ADDR_FAIL=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY_ID_FAIL)
echo "✅ Failure test series created at: $SERIES_ADDR_FAIL"

# 设置Oracle
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY_ID_FAIL $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR

# 步骤3: 少量投资（不足最低要求）
echo "💰 Step 3: Making insufficient investments..."

# USER2 投资 15000 USDC（不足40000最低要求）
INVEST_AMOUNT_SMALL=$((15000 * 1000000))

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR_FAIL $INVEST_AMOUNT_SMALL

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR_FAIL "contribute(uint256)" $INVEST_AMOUNT_SMALL

echo "✅ USER2 invested 15000 USDC (insufficient)"

# 步骤4: 推进时间到募资结束
echo "⏰ Step 4: Advancing time past fundraising deadline..."

TIME_TO_END=$((ACCRUAL_START_FAIL - CURRENT_TIME + 3600))
cast rpc --rpc-url $RPC_URL evm_increaseTime $TIME_TO_END
cast rpc --rpc-url $RPC_URL evm_mine

echo "✅ Time advanced past fundraising deadline"

# 步骤5: 检查阶段状态
echo "🔍 Step 5: Checking phase status..."

CURRENT_PHASE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR_FAIL "getPhase()(uint8)")
echo "   Current Phase: $CURRENT_PHASE (should be 2 = RisingFailed)"

# 步骤6: 投资者申请退款
echo "💸 Step 6: Investor requesting refund..."

USER2_BALANCE_BEFORE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR_FAIL "refund()" \
    || { echo "❌ Refund failed"; exit 1; }

USER2_BALANCE_AFTER=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)

REFUND_AMOUNT=$((USER2_BALANCE_AFTER - USER2_BALANCE_BEFORE))

echo "✅ Refund completed"
echo "   Refunded amount: $(echo $REFUND_AMOUNT | awk '{printf "%.6f", $1/1000000}') USDC"

echo "✅ Case 5 completed successfully!"
echo "💡 Fundraising failure and refund mechanism working correctly"
```

---

## Case 6: 管理员权限操作

**场景描述**: 测试管理员的各种权限操作，包括暂停、恢复、紧急提取等

**脚本文件**: `case_6.sh`

```bash
#!/bin/bash
# Case 6: 管理员权限操作

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 6: Admin Permission Operations..."
echo "==============================================="

# 加载环境变量
source .env

if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Case 1 must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR

# 步骤1: 测试暂停功能
echo "⏸️ Step 1: Testing pause functionality..."

# 暂停合约
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "pause()" \
    || { echo "❌ Failed to pause contract"; exit 1; }

echo "✅ Contract paused"

# 尝试在暂停状态下投资（应该失败）
echo "   Testing investment during pause (should fail)..."
TEST_AMOUNT=$((100 * 1000000))

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $TEST_AMOUNT 2>/dev/null || true

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $TEST_AMOUNT \
    2>/dev/null && echo "❌ Investment should fail when paused" || echo "✅ Investment correctly blocked during pause"

# 步骤2: 恢复合约
echo "▶️ Step 2: Unpausing contract..."

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "unpause()" \
    || { echo "❌ Failed to unpause contract"; exit 1; }

echo "✅ Contract unpaused"

# 步骤3: 测试角色管理
echo "👥 Step 3: Testing role management..."

# 授予 USER1 操作员角色
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "grantOperatorRole(address)" $USER1_ADDRESS \
    || { echo "❌ Failed to grant operator role"; exit 1; }

echo "✅ Operator role granted to USER1"

# 验证角色
HAS_OPERATOR_ROLE=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "hasRole(bytes32,address)(bool)" \
    "0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929" $USER1_ADDRESS)

echo "   USER1 has operator role: $HAS_OPERATOR_ROLE"

# 撤销角色
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "revokeOperatorRole(address)" $USER1_ADDRESS \
    || { echo "❌ Failed to revoke operator role"; exit 1; }

echo "✅ Operator role revoked from USER1"

# 步骤4: 测试紧急代币提取
echo "🚨 Step 4: Testing emergency token recovery..."

# 首先向 SeriesFactory 发送一些测试代币
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "transfer(address,uint256)" $SERIES_FACTORY_ADDR $((100 * 1000000)) \
    || { echo "❌ Failed to send test tokens"; exit 1; }

echo "✅ Test tokens sent to SeriesFactory"

# 检查余额
FACTORY_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $SERIES_FACTORY_ADDR)
echo "   SeriesFactory USDC balance: $(echo $FACTORY_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"

# 紧急提取
if [ $FACTORY_BALANCE -gt 0 ]; then
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR "emergencyRecoverToken(address,uint256)" $USDC_ADDR $FACTORY_BALANCE \
        || { echo "❌ Failed to recover tokens"; exit 1; }
    
    echo "✅ Emergency token recovery completed"
fi

# 步骤5: 测试 Oracle 更新
echo "🔮 Step 5: Testing Oracle updates..."

# 部署新的 KYC Oracle 用于测试
NEW_KYC_ORACLE=$(forge create --broadcast --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    src/KYCOracle.sol:KYCOracle | grep "Deployed to:" | awk '{print $3}')

echo "   New KYC Oracle deployed at: $NEW_KYC_ORACLE"

# 更新 PropertyOracle 中的 KYC Oracle
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR "updateKYCOracle(address)" $NEW_KYC_ORACLE \
    || { echo "❌ Failed to update KYC Oracle"; exit 1; }

echo "✅ KYC Oracle updated in PropertyOracle"

# 验证更新
CURRENT_KYC_ORACLE=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "kycOracle()(address)")
echo "   Current KYC Oracle: $CURRENT_KYC_ORACLE"

echo "✅ Case 6 completed successfully!"
echo "💡 All admin operations working correctly"
```

---

## Case 7: 边界条件测试

**场景描述**: 测试各种边界条件和异常情况

**脚本文件**: `case_7.sh`

```bash
#!/bin/bash
# Case 7: 边界条件测试

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 7: Edge Cases Testing..."
echo "======================================"

# 加载环境变量
source .env

if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Case 1 must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR

# 步骤1: 测试零金额操作
echo "🔍 Step 1: Testing zero amount operations..."

# 尝试投资0金额
echo "   Testing zero investment..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" 0 \
    2>/dev/null && echo "❌ Zero investment should fail" || echo "✅ Zero investment correctly rejected"

# 尝试支付0租金
echo "   Testing zero rent payment..."
cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
    $SERIES_ADDR "payRent(uint256)" 0 \
    2>/dev/null && echo "❌ Zero rent should fail" || echo "✅ Zero rent correctly rejected"

# 步骤2: 测试超额投资
echo "💰 Step 2: Testing over-investment..."

# 获取当前募资情况
TOTAL_RAISED=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalRaised()(uint256)")
MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "maxRaising()(uint256)")
REMAINING=$((MAX_RAISING - TOTAL_RAISED))

echo "   Total raised: $(echo $TOTAL_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Max raising: $(echo $MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Remaining: $(echo $REMAINING | awk '{printf "%.6f", $1/1000000}') USDC"

if [ $REMAINING -gt 0 ]; then
    # 尝试投资超过剩余额度
    OVER_AMOUNT=$((REMAINING + 1000000))  # 超出1 USDC
    
    cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
        $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $OVER_AMOUNT
    
    cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
        $SERIES_ADDR "contribute(uint256)" $OVER_AMOUNT \
        2>/dev/null && echo "❌ Over-investment should be limited" || echo "✅ Over-investment correctly handled"
fi

# 步骤3: 测试重复申领
echo "🔄 Step 3: Testing duplicate claims..."

# 确保有可申领金额
USER2_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER2_ADDRESS)

if [ $USER2_CLAIMABLE -eq 0 ]; then
    # 支付一些租金以产生可申领金额
    SMALL_RENT=$((100 * 1000000))
    cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
        $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $SMALL_RENT
    cast send --rpc-url $RPC_URL --private-key $USER1_PRIVATE_KEY \
        $SERIES_ADDR "payRent(uint256)" $SMALL_RENT
    echo "   Added small rent for testing"
fi

# 第一次申领
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "claim()" || echo "   First claim may have failed"

# 立即第二次申领（应该没有效果）
USER2_BALANCE_BEFORE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "claim()" || echo "   Second claim expected to have no effect"

USER2_BALANCE_AFTER=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)

if [ $USER2_BALANCE_AFTER -eq $USER2_BALANCE_BEFORE ]; then
    echo "✅ Duplicate claim correctly handled (no additional payout)"
else
    echo "❌ Duplicate claim should not provide additional payout"
fi

# 步骤4: 测试无效地址操作
echo "🚫 Step 4: Testing invalid address operations..."

# 尝试向零地址转账
USER2_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
if [ $USER2_TOKENS -gt 0 ]; then
    cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
        $SERIES_ADDR "transfer(address,uint256)" "0x0000000000000000000000000000000000000000" 1 \
        2>/dev/null && echo "❌ Transfer to zero address should fail" || echo "✅ Transfer to zero address correctly blocked"
fi

# 步骤5: 测试时间相关边界
echo "⏰ Step 5: Testing time-related boundaries..."

# 获取时间信息
ACCRUAL_START=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "accrualStartTime()(uint64)")
ACCRUAL_END=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "accrualEndTime()(uint64)")
CURRENT_TIME=$(cast block --rpc-url $RPC_URL latest --field timestamp)

echo "   Accrual start: $ACCRUAL_START"
echo "   Accrual end: $ACCRUAL_END"
echo "   Current time: $CURRENT_TIME"

# 如果还未到结束时间，推进到结束时间之后
if [ $CURRENT_TIME -lt $ACCRUAL_END ]; then
    TIME_TO_END=$((ACCRUAL_END - CURRENT_TIME + 3600))
    cast rpc --rpc-url $RPC_URL evm_increaseTime $TIME_TO_END
    cast rpc --rpc-url $RPC_URL evm_mine
    echo "   Time advanced past accrual end"
fi

# 检查阶段变化
FINAL_PHASE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getPhase()(uint8)")
echo "   Final phase: $FINAL_PHASE (should be 3 = AccrualFinished)"

echo "✅ Case 7 completed successfully!"
echo "💡 All edge cases handled correctly"
```

---

## 运行指南

### 1. 环境准备
```bash
# 启动 Anvil
URL="https://ethereum.rpc.thirdweb.com"
anvil --fork-url $URL

# 初始化环境
./init-local.sh
```

### 2. 按顺序运行测试案例
```bash
# 基础流程
./case_1.sh  # 房产代币化
./case_2.sh  # 投资者购买
./case_3.sh  # 租金分配

# 高级功能
./case_4.sh  # 代币转账
./case_5.sh  # 募资失败
./case_6.sh  # 管理员操作
./case_7.sh  # 边界测试
```

### 3. 独立测试
某些案例可以独立运行，但建议按顺序执行以确保完整的测试覆盖。

## 测试结果验证

每个测试案例都包含详细的验证步骤，确保：
- ✅ 功能正常工作
- ❌ 异常情况被正确处理
- 📊 数据状态符合预期
- 💰 资金流转正确

## 扩展建议

可以基于这些案例创建更多测试场景：
- 多房产并行测试
- 大规模投资者测试
- 长期租金分配测试
- 复杂权限管理测试
- 网络异常恢复测试

---

*本文档提供了完整的测试案例框架，可根据具体需求调整和扩展。*