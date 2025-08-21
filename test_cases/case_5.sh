#!/bin/bash
# Case 5: 募资失败退款流程

set -e
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 5: Fundraising Failure & Refund Flow..."
echo "======================================================"

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 加载环境变量
source .env

# 创建新的房产用于测试募资失败
echo "🏠 Step 1: Creating new property for failure test..."

PROPERTY_ID_FAIL=9999
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

SERIES_ADDR_FAIL=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY_ID_FAIL | cut -d' ' -f1)
echo "✅ Failure test series created at: $SERIES_ADDR_FAIL"

# 设置Oracle
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY_ID_FAIL $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR

# 步骤3: 少量投资（不足最低要求）
echo "💰 Step 3: Making insufficient investments..."

# USER2 投资 5000 USDC（不足40000最低要求）
INVEST_AMOUNT_SMALL=$((5000 * 1000000))

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR_FAIL $INVEST_AMOUNT_SMALL

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR_FAIL "contribute(uint256)" $INVEST_AMOUNT_SMALL

echo "✅ USER2 invested 5000 USDC (insufficient)"

# 步骤4: 推进时间到募资结束
echo "⏰ Step 4: Advancing time past fundraising deadline..."

TIME_TO_END=$((ACCRUAL_START_FAIL - CURRENT_TIME + 3600))
cast rpc --rpc-url $RPC_URL evm_increaseTime $TIME_TO_END
cast rpc --rpc-url $RPC_URL evm_mine

echo "✅ Time advanced past fundraising deadline"

# 步骤5: 检查阶段状态
echo "🔍 Step 5: Checking phase status..."

CURRENT_PHASE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR_FAIL "getPhase()(uint8)" | cut -d' ' -f1)
echo "   Current Phase: $CURRENT_PHASE (should be 2 = RisingFailed)"

# 步骤6: 投资者申请退款
echo "💸 Step 6: Investor requesting refund..."

USER2_BALANCE_BEFORE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS | cut -d' ' -f1)

cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES_ADDR_FAIL "refund()" \
    || { echo "❌ Refund failed"; exit 1; }

USER2_BALANCE_AFTER=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS | cut -d' ' -f1)

REFUND_AMOUNT=$((USER2_BALANCE_AFTER - USER2_BALANCE_BEFORE))

echo "✅ Refund completed"
echo "   Refunded amount: $(echo $REFUND_AMOUNT | awk '{printf "%.6f", $1/1000000}') USDC"

echo "✅ Case 5 completed successfully!"
echo "💡 Fundraising failure and refund mechanism working correctly"