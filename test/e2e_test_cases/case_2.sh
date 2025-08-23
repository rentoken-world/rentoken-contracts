#!/bin/bash
# Case 2: 投资者购买代币流程

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 2: Investor Token Purchase Flow..."
echo "=================================================="

# 切换到项目根目录
cd "$(dirname "$0")/.."

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

# 步骤1: USER2 投资 2000 USDC
echo "💰 Step 1: USER2 investing 2000 USDC..."
INVEST_AMOUNT=$((2000 * 1000000))  # 2000 USDC

# 首先授权 USDC
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT \
    || { echo "❌ Failed to approve USDC"; exit 1; }

echo "✅ USDC approved"

# 投资
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT \
    || { echo "❌ Failed to contribute"; exit 1; }

echo "✅ USER2 invested 2000 USDC"

# 步骤2: USER3 投资 2000 USDC
echo "💰 Step 2: USER3 investing 2000 USDC..."
INVEST_AMOUNT_2=$((2000 * 1000000))  # 2000 USDC

# 授权和投资
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT_2 \
    || { echo "❌ Failed to approve USDC"; exit 1; }

cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT_2 \
    || { echo "❌ Failed to contribute"; exit 1; }

echo "✅ USER3 invested 2000 USDC"

# 步骤3: USER4 尝试投资（应该失败）
echo "❌ Step 3: USER4 attempting to invest (should fail)..."
INVEST_AMOUNT_4=$((1000 * 1000000))  # 1000 USDC
cast send --rpc-url $RPC_URL --private-key $USER4_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT_4 \
    2>/dev/null || echo "   Expected: USER4 approval may fail due to KYC"

cast send --rpc-url $RPC_URL --private-key $USER4_PRIVATE_KEY \
    $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT_4 \
    2>/dev/null && echo "❌ USER4 should not be able to invest" || echo "✅ USER4 correctly rejected"

# 步骤4: 验证投资结果
echo "🔍 Step 4: Verifying investment results..."

# 检查代币余额
USER2_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_TOKENS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

# 检查总投资额
TOTAL_RAISED=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalFundRaised()(uint256)")

echo "📊 Investment Summary:"
echo "   USER2 Tokens: $USER2_TOKENS"
echo "   USER3 Tokens: $USER3_TOKENS"
echo "   USER4 Tokens: $USER4_TOKENS (should be 0)"
echo "   Total Raised: $(echo $TOTAL_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

echo "✅ Case 2 completed successfully!"
echo "💡 Next: Run case_3.sh for rent distribution testing"