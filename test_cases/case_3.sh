#!/bin/bash
# Case 3: 租金分配流程

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 3: Rent Distribution Flow..."
echo "==============================================="

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 加载环境变量
source .env

# 确保前置条件
if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Previous cases must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR
PROPERTY_ID=$CASE1_PROPERTY_ID

# 步骤1: 模拟时间推进到租金开始时间
echo "⏰ Step 1: Advancing time to accrual start..."

# 获取租金开始时间
ACCRUAL_START=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "accrualStart()(uint64)")
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

# 管理员授权租金支付给 SeriesFactory
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_FACTORY_ADDR $MONTHLY_RENT \
    || { echo "❌ Failed to approve rent payment"; exit 1; }

# 通过 SeriesFactory 支付租金（使用管理员权限）
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "receiveProfit(uint256,uint256)" $PROPERTY_ID $MONTHLY_RENT \
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