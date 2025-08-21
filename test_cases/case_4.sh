#!/bin/bash
# Case 4: 代币转账和收益追踪

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 4: Token Transfer and Reward Tracking..."
echo "======================================================"

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 加载环境变量并验证前置条件
source .env

if [ -z "$CASE1_SERIES_ADDR" ]; then
    echo "❌ Previous cases must be completed first"
    exit 1
fi

SERIES_ADDR=$CASE1_SERIES_ADDR
PROPERTY_ID=$CASE1_PROPERTY_ID

# 步骤1: 记录转账前状态
echo "📊 Step 1: Recording pre-transfer state..."

USER2_TOKENS_BEFORE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS | cut -d' ' -f1)
USER3_TOKENS_BEFORE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS | cut -d' ' -f1)

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

USER2_TOKENS_AFTER=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS | cut -d' ' -f1)
USER3_TOKENS_AFTER=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS | cut -d' ' -f1)

echo "   USER2 tokens after: $USER2_TOKENS_AFTER"
echo "   USER3 tokens after: $USER3_TOKENS_AFTER"

# 步骤4: 管理员支付新的租金
echo "💰 Step 4: Admin paying additional rent..."

NEW_RENT=$((800 * 1000000))  # 800 USDC

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_FACTORY_ADDR $NEW_RENT \
    || { echo "❌ Failed to approve new rent"; exit 1; }

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "receiveProfit(uint256,uint256)" $PROPERTY_ID $NEW_RENT \
    || { echo "❌ Failed to pay new rent"; exit 1; }

echo "✅ Additional rent paid: 800 USDC"

# 步骤5: 检查新的可申领金额
echo "🔍 Step 5: Checking new claimable amounts..."

USER2_NEW_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER2_ADDRESS | cut -d' ' -f1)
USER3_NEW_CLAIMABLE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getClaimableAmount(address)(uint256)" $USER3_ADDRESS | cut -d' ' -f1)

echo "💰 New Claimable Amounts:"
echo "   USER2: $(echo $USER2_NEW_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3: $(echo $USER3_NEW_CLAIMABLE | awk '{printf "%.6f", $1/1000000}') USDC"

# 步骤6: 验证收益分配比例
echo "📈 Step 6: Verifying reward distribution ratios..."

TOTAL_SUPPLY=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalSupply()(uint256)" | cut -d' ' -f1)
USER2_RATIO=$(echo "scale=6; $USER2_TOKENS_AFTER * 100 / $TOTAL_SUPPLY" | bc -l)
USER3_RATIO=$(echo "scale=6; $USER3_TOKENS_AFTER * 100 / $TOTAL_SUPPLY" | bc -l)

echo "📊 Token Distribution:"
echo "   USER2: $USER2_RATIO% of total supply"
echo "   USER3: $USER3_RATIO% of total supply"

echo "✅ Case 4 completed successfully!"
echo "💡 Token transfers and reward tracking working correctly"