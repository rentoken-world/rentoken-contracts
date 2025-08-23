#!/bin/bash
# Case 1 with CLI - 使用 RWA CLI 工具重写的 case_1.sh
# 这里构建本地测试情况1，使用新的 CLI 工具替代原始的 cast 命令

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 1 Test Scenario (CLI Version)..."
echo "=================================================="

# 检查 .env 文件是否存在
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please run init-local.sh first."
    exit 1
fi

# 检查 CLI 工具是否存在
if [ ! -f "bin/rwa" ]; then
    echo "❌ RWA CLI tool not found at bin/rwa"
    exit 1
fi

# 加载环境变量
echo "📋 Loading environment variables from .env..."
source .env

# 验证必要的环境变量
required_vars=(
    "ADMIN_ADDRESS" "ADMIN_PRIVATE_KEY"
    "USER1_ADDRESS" "USER1_PRIVATE_KEY"
    "USER2_ADDRESS" "USER2_PRIVATE_KEY"
    "USER3_ADDRESS" "USER3_PRIVATE_KEY"
    "USER4_ADDRESS" "USER4_PRIVATE_KEY"
    "RPC_URL"
    "KYC_ORACLE_ADDR" "PROPERTY_ORACLE_ADDR"
    "SERIES_FACTORY_ADDR" "USDC_ADDR"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Missing required environment variable: $var"
        exit 1
    fi
done

echo "✅ Environment variables loaded successfully"
echo "🔑 Test Addresses:"
echo "   ADMIN: $(bin/rwa addr:show ADMIN)"
echo "   USER1 (Landlord): $(bin/rwa addr:show USER1)"
echo "   USER2 (Investor): $(bin/rwa addr:show USER2)"
echo "   USER3 (Investor): $(bin/rwa addr:show USER3)"
echo "   USER4 (Non-KYC): $(bin/rwa addr:show USER4)"
echo ""

# 显示当前区块信息
echo "⏰ Block Information:"
echo "   Current Block Time: $(bin/rwa block:time)"
echo "   Chain ID: $(bin/rwa block:chainid)"
echo ""

# 步骤1: Admin添加房产到PropertyOracle
echo "🏠 Step 1: Adding Test Apartment to PropertyOracle (Using CLI)..."

# 房产信息（与原脚本保持一致）
PROPERTY_ID=1
VALUATION=$((28800 * 1000000))  # 28800 USDC (6 decimals)
MIN_RAISING=$((20000 * 1000000))  # 20000 USDC minimum
MAX_RAISING=$((30000 * 1000000))  # 30000 USDC maximum
DOC_HASH=$(echo -n "Test Apartment Property Document" | cast keccak)
OFFCHAIN_URL="https://example.com/property/1"

echo "📝 Property Details:"
echo "   Property ID: $PROPERTY_ID"
echo "   Landlord: USER1 ($(bin/rwa addr:show USER1))"
echo "   Payout Token: $USDC_ADDR"
echo "   Valuation: $VALUATION (28800 USDC)"
echo "   Min Raising: $MIN_RAISING (20000 USDC)"
echo "   Max Raising: $MAX_RAISING (30000 USDC)"
echo "   Doc Hash: $DOC_HASH"
echo ""

# 使用 CLI 添加房产
bin/rwa property:add \
    --id "$PROPERTY_ID" \
    --payout "$USDC_ADDR" \
    --valuation "$VALUATION" \
    --min "$MIN_RAISING" \
    --max "$MAX_RAISING" \
    --start "+3600" \
    --end "+157680000" \
    --landlord "USER1" \
    --doc-hash "$DOC_HASH" \
    --url "$OFFCHAIN_URL" \
    --yes

echo "✅ Property added to PropertyOracle using CLI"

# 步骤2: Admin添加用户到KYC白名单
echo "🔐 Step 2: Adding users to KYC whitelist (Using CLI)..."

# 检查并添加用户到 KYC 白名单
for user in USER1 USER2 USER3; do
    echo "   Checking $user KYC status..."
    current_status=$(bin/rwa kyc:check "$user")
    
    if [ "$current_status" = "false" ]; then
        echo "   Adding $user to KYC..."
        bin/rwa kyc:add "$user" --yes
    else
        echo "   $user already in KYC whitelist"
    fi
done

# 注意：USER4 故意不添加到KYC白名单中

echo "✅ KYC whitelist updated"

# 验证KYC状态
echo "🔍 Verifying KYC status (Using CLI):"
for user in USER1 USER2 USER3 USER4; do
    status=$(bin/rwa kyc:check "$user")
    echo "   $user KYC Status: $status"
done

if [ "$(bin/rwa kyc:check USER4)" = "true" ]; then
    echo "❌ USER4 should not be in KYC whitelist"
    exit 1
fi

echo ""

# 步骤3: Admin通过SeriesFactory创建ERC20代币系列
echo "🪙 Step 3: Creating RentToken series through SeriesFactory (Using CLI)..."

TOKEN_NAME="RenToken Test Apartment 001"
TOKEN_SYMBOL="RTTA1"

echo "📝 Token Details:"
echo "   Name: $TOKEN_NAME"
echo "   Symbol: $TOKEN_SYMBOL"
echo "   Property ID: $PROPERTY_ID"
echo ""

# 检查系列是否已经存在
EXISTING_SERIES_ADDR=$(bin/rwa series:addr "$PROPERTY_ID" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

if [ "$EXISTING_SERIES_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   Creating new series using CLI..."
    # 使用 CLI 创建系列
    bin/rwa series:create "$PROPERTY_ID" "$TOKEN_NAME" "$TOKEN_SYMBOL" --yes
    
    echo "✅ Series creation transaction sent via CLI"
    
    # 重新获取创建的系列合约地址
    SERIES_ADDR=$(bin/rwa series:addr "$PROPERTY_ID")
else
    SERIES_ADDR="$EXISTING_SERIES_ADDR"
    echo "   Series already exists"
fi

echo "🎯 Series Contract Address: $SERIES_ADDR"

# 验证系列创建成功
if [ "$SERIES_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ Series creation failed"
    exit 1
else
    echo "✅ Series ready for use"
fi

# 步骤4: 设置系列合约的Oracle
echo "⚙️ Step 4: Setting oracles for the series (Using CLI)..."

bin/rwa series:oracles:set "$PROPERTY_ID" "$KYC_ORACLE_ADDR" "$SANCTION_ORACLE_ADDR" --yes

echo "✅ Oracles set for series using CLI"

# 步骤5: 验证设置并显示关键信息
echo "🔍 Step 5: Final verification and summary (Using CLI)..."

# 使用 CLI 显示系列信息
echo "📊 Series Contract Information (from CLI):"
bin/rwa series:info "$PROPERTY_ID"
echo ""

# 检查当前阶段
echo "📈 Current Phase Information:"
CURRENT_PHASE=$(bin/rwa series:phase "$PROPERTY_ID")
PHASE_NAME=""
case $CURRENT_PHASE in
    0) PHASE_NAME="Fundraising" ;;
    1) PHASE_NAME="AccrualStarted" ;;
    2) PHASE_NAME="RisingFailed" ;;
    3) PHASE_NAME="AccrualFinished" ;;
    4) PHASE_NAME="Terminated" ;;
    *) PHASE_NAME="Unknown" ;;
esac

echo "Current Phase: $CURRENT_PHASE ($PHASE_NAME)"
echo ""

# 显示用户USDC余额
echo "💰 User USDC Balances (Using CLI):"
for user in USER1 USER2 USER3 USER4; do
    balance=$(bin/rwa erc20:balance "$USDC_ADDR" "$user")
    # 转换为人类可读格式（USDC 有6位小数）
    readable_balance=$(echo "$balance" | awk '{printf "%.6f", $1/1000000}')
    echo "   $user: $readable_balance USDC"
done
echo ""

# 保存关键信息到环境变量文件
echo "# Case 1 CLI Test Results - $(date)" >> .env
echo "CASE1_CLI_PROPERTY_ID=$PROPERTY_ID" >> .env
echo "CASE1_CLI_SERIES_ADDR=$SERIES_ADDR" >> .env
echo "CASE1_CLI_TOKEN_NAME=\"$TOKEN_NAME\"" >> .env
echo "CASE1_CLI_TOKEN_SYMBOL=$TOKEN_SYMBOL" >> .env

echo "✅ Case 1 CLI setup completed successfully!"
echo "=================================================="
echo "🎯 Summary:"
echo "   - Property ID $PROPERTY_ID added to PropertyOracle using CLI"
echo "   - USER1, USER2, USER3 added to KYC whitelist using CLI"
echo "   - USER4 remains non-KYC for testing"
echo "   - RentToken series '$TOKEN_SYMBOL' created at $SERIES_ADDR using CLI"
echo "   - Series is in $PHASE_NAME phase"
echo "   - All users have USDC for testing investments"
echo ""
echo "🚀 Ready for investment testing!"
echo "💡 Next steps using CLI:"
echo "   - Contribute: bin/rwa series:contribute $PROPERTY_ID 100000000 --from USER1 --yes"
echo "   - Check balance: bin/rwa erc20:balance $SERIES_ADDR USER1"
echo "   - Remember: USER4 will be rejected due to KYC requirements"
echo ""
echo "🔧 CLI Demo Commands:"
echo "   bin/rwa series:info $PROPERTY_ID"
echo "   bin/rwa kyc:check USER4"
echo "   bin/rwa erc20:balance $USDC_ADDR USER2"
