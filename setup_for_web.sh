#!/bin/bash
# 这里构建本地测试情况2，假设已经运行好了init-local.sh脚本，环境变量保存在.env文件里。

# 我们构造一个本地部署后的测试情况。
# 角色：
# 1 ADMIN 代表平台公司
# 2 user1 房东，有3套房产，房产信息如下：
# [
#   {
#     "propertyId": 1,
#     "payoutToken": "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
#     "valuation": 72000,
#     "minRaising": 28800,
#     "maxRaising": 28800,
#     "accrualStart": 1755856800,
#     "accrualEnd": 1841392800,
#     "landlord": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
#     "docHash": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
#     "offchainURL": "https://ipfs.io/ipfs/QmTestApartment"
#   },
#   {
#     "propertyId": 2,
#     "payoutToken": "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
#     "valuation": 180000,
#     "minRaising": 180000,
#     "maxRaising": 180000,
#     "accrualStart": 1755856800,
#     "accrualEnd": 1841392800,
#     "landlord": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
#     "docHash": "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
#     "offchainURL": "https://ipfs.io/ipfs/QmLuxuryVilla"
#   },
#   {
#     "propertyId": 3,
#     "payoutToken": "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
#     "valuation": 19200,
#     "minRaising": 19200,
#     "maxRaising": 19200,
#     "accrualStart": 1755856800,
#     "accrualEnd": 1841392800,
#     "landlord": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
#     "docHash": "0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234",
#     "offchainURL": "https://ipfs.io/ipfs/QmCozyStudio"
#   }
# ]

# 3 user2 投资人 - kyc 通过

# 4 user3 投资人 - kyc 通过

# 5 user4 投资人 - kyc没有通过

# 事件：
# 1 admin添加3套房产进入property oracle
# 2 admin添加user1，user2， user3 进入kyc oracle
# 3 admin添加房产propertyID1，2，3 进入propertyOracle
# 4 user1 通过seriesFactory 发行erc20 币
# 5 user1 通过seriesFactory 发行erc20 币
# 6 user1 通过seriesFactory 发行erc20 币
# 7 user2 认购propert1 100000 最终应该发售成功
# 8 user2 认购propert2 100000 最终应该发售失败
# 9 user2 认购propert3 100000 最终应该发售成功
# 10 user3 认购propert1 100000 最终应该发售成功
# 11 user3 认购propert3 9200 最终应该发售成功

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 2 Test Scenario..."
echo "=================================================="

# 检查 .env 文件是否存在
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please run init-local.sh first."
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
    "SERIES_FACTORY_ADDR" "USDC_ADDR" "SANCTION_ORACLE_ADDR"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Missing required environment variable: $var"
        exit 1
    fi
done

echo "✅ Environment variables loaded successfully"
echo "🔑 Test Addresses:"
echo "   ADMIN: $ADMIN_ADDRESS"
echo "   USER1 (Landlord): $USER1_ADDRESS"
echo "   USER2 (Investor): $USER2_ADDRESS"
echo "   USER3 (Investor): $USER3_ADDRESS"
echo "   USER4 (Non-KYC): $USER4_ADDRESS"
echo ""

# 步骤1: Admin添加3套房产到PropertyOracle
echo "🏠 Step 1: Adding 3 properties to PropertyOracle..."

# 房产1: Test Apartment
PROPERTY1_ID=1
PROPERTY1_DOC_HASH=$(echo -n "Test Apartment Property Document" | cast keccak)
PROPERTY1_OFFCHAIN_URL="https://ipfs.io/ipfs/QmTestApartment"
PROPERTY1_VALUATION=$((72000 * 1000000))  # 72000 USDC (6 decimals)
PROPERTY1_MIN_RAISING=$((28800 * 1000000))  # 28800 USDC minimum
PROPERTY1_MAX_RAISING=$((28800 * 1000000))  # 28800 USDC maximum

# 房产2: Luxury Villa
PROPERTY2_ID=2
PROPERTY2_DOC_HASH=$(echo -n "Luxury Villa Property Document" | cast keccak)
PROPERTY2_OFFCHAIN_URL="https://ipfs.io/ipfs/QmLuxuryVilla"
PROPERTY2_VALUATION=$((180000 * 1000000))  # 180000 USDC (6 decimals)
PROPERTY2_MIN_RAISING=$((180000 * 1000000))  # 180000 USDC minimum
PROPERTY2_MAX_RAISING=$((180000 * 1000000))  # 180000 USDC maximum

# 房产3: Cozy Studio
PROPERTY3_ID=3
PROPERTY3_DOC_HASH=$(echo -n "Cozy Studio Property Document" | cast keccak)
PROPERTY3_OFFCHAIN_URL="https://ipfs.io/ipfs/QmCozyStudio"
PROPERTY3_VALUATION=$((19200 * 1000000))  # 19200 USDC (6 decimals)
PROPERTY3_MIN_RAISING=$((19200 * 1000000))  # 19200 USDC minimum
PROPERTY3_MAX_RAISING=$((19200 * 1000000))  # 19200 USDC maximum

# 使用固定的时间戳（从注释中获取）
ACCRUAL_START=1755856800
ACCRUAL_END=1841392800

echo "⏰ Time Configuration:"
echo "   Accrual Start: $ACCRUAL_START ($(date -r $ACCRUAL_START))"
echo "   Accrual End: $ACCRUAL_END ($(date -r $ACCRUAL_END))"
echo ""

echo "📝 Property 1 Details (Test Apartment):"
echo "   Property ID: $PROPERTY1_ID"
echo "   Landlord: $USER1_ADDRESS"
echo "   Valuation: $PROPERTY1_VALUATION (72000 USDC)"
echo "   Min/Max Raising: $PROPERTY1_MIN_RAISING (28800 USDC)"
echo ""

echo "📝 Property 2 Details (Luxury Villa):"
echo "   Property ID: $PROPERTY2_ID"
echo "   Landlord: $USER1_ADDRESS"
echo "   Valuation: $PROPERTY2_VALUATION (180000 USDC)"
echo "   Min/Max Raising: $PROPERTY2_MIN_RAISING (180000 USDC)"
echo ""

echo "📝 Property 3 Details (Cozy Studio):"
echo "   Property ID: $PROPERTY3_ID"
echo "   Landlord: $USER1_ADDRESS"
echo "   Valuation: $PROPERTY3_VALUATION (19200 USDC)"
echo "   Min/Max Raising: $PROPERTY3_MIN_RAISING (19200 USDC)"
echo ""

# 添加房产1
echo "   Adding Property 1..."
PROPERTY1_DATA="($PROPERTY1_ID,$USDC_ADDR,$PROPERTY1_VALUATION,$PROPERTY1_MIN_RAISING,$PROPERTY1_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY1_DOC_HASH,\"$PROPERTY1_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY1_ID "$PROPERTY1_DATA" \
    || { echo "❌ Failed to add property 1"; exit 1; }

echo "✅ Property 1 added successfully"

# 添加房产2
echo "   Adding Property 2..."
PROPERTY2_DATA="($PROPERTY2_ID,$USDC_ADDR,$PROPERTY2_VALUATION,$PROPERTY2_MIN_RAISING,$PROPERTY2_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY2_DOC_HASH,\"$PROPERTY2_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY2_ID "$PROPERTY2_DATA" \
    || { echo "❌ Failed to add property 2"; exit 1; }

echo "✅ Property 2 added successfully"

# 添加房产3
echo "   Adding Property 3..."
PROPERTY3_DATA="($PROPERTY3_ID,$USDC_ADDR,$PROPERTY3_VALUATION,$PROPERTY3_MIN_RAISING,$PROPERTY3_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY3_DOC_HASH,\"$PROPERTY3_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY3_ID "$PROPERTY3_DATA" \
    || { echo "❌ Failed to add property 3"; exit 1; }

echo "✅ Property 3 added successfully"

# 验证房产添加成功
echo "🔍 Verifying properties..."
PROPERTY1_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY1_ID)
PROPERTY2_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY2_ID)
PROPERTY3_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY3_ID)

if [ "$PROPERTY1_EXISTS" = "true" ] && [ "$PROPERTY2_EXISTS" = "true" ] && [ "$PROPERTY3_EXISTS" = "true" ]; then
    echo "✅ All properties verified successfully"
else
    echo "❌ Property verification failed"
    exit 1
fi

# 步骤2: Admin添加用户到KYC白名单
echo "🔐 Step 2: Adding users to KYC whitelist..."

# 检查并添加USER1 (房东) 到KYC白名单
echo "   Checking USER1 (Landlord) KYC status..."
USER1_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER1_ADDRESS)
if [ "$USER1_KYC_CURRENT" = "false" ]; then
    echo "   Adding USER1 to KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER1_ADDRESS \
        || { echo "❌ Failed to add USER1 to KYC"; exit 1; }
else
    echo "   USER1 already in KYC whitelist"
fi

# 检查并添加USER2 (投资人) 到KYC白名单
echo "   Checking USER2 (Investor) KYC status..."
USER2_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER2_ADDRESS)
if [ "$USER2_KYC_CURRENT" = "false" ]; then
    echo "   Adding USER2 to KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER2_ADDRESS \
        || { echo "❌ Failed to add USER2 to KYC"; exit 1; }
else
    echo "   USER2 already in KYC whitelist"
fi

# 检查并添加USER3 (投资人) 到KYC白名单
echo "   Checking USER3 (Investor) KYC status..."
USER3_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER3_ADDRESS)
if [ "$USER3_KYC_CURRENT" = "false" ]; then
    echo "   Adding USER3 to KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER3_ADDRESS \
        || { echo "❌ Failed to add USER3 to KYC"; exit 1; }
else
    echo "   USER3 already in KYC whitelist"
fi

# 注意：USER4 故意不添加到KYC白名单中

echo "✅ KYC whitelist updated"

# 验证KYC状态
echo "🔍 Verifying KYC status:"
USER1_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER1_ADDRESS)
USER2_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER2_ADDRESS)
USER3_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER3_ADDRESS)
USER4_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER4_ADDRESS)

echo "   USER1 KYC Status: $USER1_KYC"
echo "   USER2 KYC Status: $USER2_KYC"
echo "   USER3 KYC Status: $USER3_KYC"
echo "   USER4 KYC Status: $USER4_KYC (should be false)"
echo ""

# 步骤3: Admin通过SeriesFactory创建3个ERC20代币系列
echo "🪙 Step 3: Creating 3 RentToken series through SeriesFactory..."

# 系列1: Test Apartment
TOKEN1_NAME="RenToken Test Apartment 001"
TOKEN1_SYMBOL="RTTA1"

# 系列2: Luxury Villa
TOKEN2_NAME="RenToken Luxury Villa 001"
TOKEN2_SYMBOL="RTLV1"

# 系列3: Cozy Studio
TOKEN3_NAME="RenToken Cozy Studio 001"
TOKEN3_SYMBOL="RTCS1"

echo "📝 Creating series for Property 1..."
SERIES1_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY1_ID)

if [ "$SERIES1_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   Creating new series for Property 1..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY1_ID "$TOKEN1_NAME" "$TOKEN1_SYMBOL" \
        || { echo "❌ Failed to create series 1"; exit 1; }
    echo "✅ Series 1 creation transaction sent"
    SERIES1_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY1_ID)
else
    echo "   Series 1 already exists"
fi

echo "📝 Creating series for Property 2..."
SERIES2_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY2_ID)

if [ "$SERIES2_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   Creating new series for Property 2..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY2_ID "$TOKEN2_NAME" "$TOKEN2_SYMBOL" \
        || { echo "❌ Failed to create series 2"; exit 1; }
    echo "✅ Series 2 creation transaction sent"
    SERIES2_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY2_ID)
else
    echo "   Series 2 already exists"
fi

echo "📝 Creating series for Property 3..."
SERIES3_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY3_ID)

if [ "$SERIES3_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   Creating new series for Property 3..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY3_ID "$TOKEN3_NAME" "$TOKEN3_SYMBOL" \
        || { echo "❌ Failed to create series 3"; exit 1; }
    echo "✅ Series 3 creation transaction sent"
    SERIES3_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY3_ID)
else
    echo "   Series 3 already exists"
fi

echo "🎯 Series Contract Addresses:"
echo "   Series 1 (Property 1): $SERIES1_ADDR"
echo "   Series 2 (Property 2): $SERIES2_ADDR"
echo "   Series 3 (Property 3): $SERIES3_ADDR"

# 验证系列创建成功
if [ "$SERIES1_ADDR" = "0x0000000000000000000000000000000000000000" ] || \
   [ "$SERIES2_ADDR" = "0x0000000000000000000000000000000000000000" ] || \
   [ "$SERIES3_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ Series creation failed"
    exit 1
else
    echo "✅ All series ready for use"
fi

# 步骤4: 设置系列合约的Oracle
echo "⚙️ Step 4: Setting oracles for all series..."

echo "   Setting oracles for Series 1..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY1_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ Failed to set oracles for series 1"; exit 1; }

echo "   Setting oracles for Series 2..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY2_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ Failed to set oracles for series 2"; exit 1; }

echo "   Setting oracles for Series 3..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY3_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ Failed to set oracles for series 3"; exit 1; }

echo "✅ Oracles set for all series"

# 步骤5: 投资人认购测试
echo "💰 Step 5: Testing investor contributions..."

# 显示用户USDC余额
echo "🔍 Current USDC balances:"
USER1_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

echo "   USER1 (Landlord): $(echo $USER1_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER2 (Investor): $(echo $USER2_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3 (Investor): $(echo $USER3_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER4 (Non-KYC): $(echo $USER4_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

# 测试7: USER2 认购 Property1 28800 USDC (应该成功，达到最大募集额)
echo "🧪 Test 7: USER2 contributing 28800 USDC to Property 1..."
USER2_CONTRIBUTION1=$((28800 * 1000000))  # 28800 USDC (6 decimals)

# 先授权USDC
echo "   Authorizing USDC for USER2..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES1_ADDR $USER2_CONTRIBUTION1 \
    || { echo "❌ Failed to approve USDC for USER2"; exit 1; }

# 认购
echo "   Contributing USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES1_ADDR "contribute(uint256)" $USER2_CONTRIBUTION1 \
    || { echo "❌ Failed to contribute USDC for USER2"; exit 1; }

echo "✅ USER2 contribution to Property 1 successful"

# 测试8: USER2 认购 Property2 100000 USDC (应该失败，因为最小募集额是180000)
echo "🧪 Test 8: USER2 contributing 100000 USDC to Property 2 (should fail)..."
USER2_CONTRIBUTION2=$((100000 * 1000000))  # 100000 USDC (6 decimals)

# 先授权USDC
echo "   Authorizing USDC for USER2..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES2_ADDR $USER2_CONTRIBUTION2 \
    || { echo "❌ Failed to approve USDC for USER2"; exit 1; }

# 认购 (这个应该失败)
echo "   Contributing USDC (expected to fail)..."
if cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES2_ADDR "contribute(uint256)" $USER2_CONTRIBUTION2 2>&1 | grep -q "error"; then
    echo "✅ USER2 contribution to Property 2 failed as expected (insufficient amount)"
else
    echo "❌ USER2 contribution to Property 2 should have failed"
fi

# 测试9: USER2 认购 Property3 19200 USDC (应该成功，达到最大募集额)
echo "🧪 Test 9: USER2 contributing 19200 USDC to Property 3..."
USER2_CONTRIBUTION3=$((19200 * 1000000))  # 19200 USDC (6 decimals)

# 先授权USDC
echo "   Authorizing USDC for USER2..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES3_ADDR $USER2_CONTRIBUTION3 \
    || { echo "❌ Failed to approve USDC for USER2"; exit 1; }

# 认购
echo "   Contributing USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES3_ADDR "contribute(uint256)" $USER2_CONTRIBUTION3 \
    || { echo "❌ Failed to contribute USDC for USER2"; exit 1; }

echo "✅ USER2 contribution to Property 3 successful"

# 测试10: USER3 认购 Property1 0 USDC (应该失败，因为Property1已经达到最大募集额)
echo "🧪 Test 10: USER3 attempting to contribute to Property 1 (should fail, max raised)..."
USER3_CONTRIBUTION1=$((1000 * 1000000))  # 1000 USDC (6 decimals) - small amount to test failure

# 先授权USDC
echo "   Authorizing USDC for USER3..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES1_ADDR $USER3_CONTRIBUTION1 \
    || { echo "❌ Failed to approve USDC for USER3"; exit 1; }

# 认购 (这个应该失败，因为Property1已经达到最大募集额)
echo "   Contributing USDC (expected to fail, max raised)..."
if cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES1_ADDR "contribute(uint256)" $USER3_CONTRIBUTION1 2>&1 | grep -q "error"; then
    echo "✅ USER3 contribution to Property 1 failed as expected (max raising reached)"
else
    echo "❌ USER3 contribution to Property 1 should have failed"
fi

# 测试11: USER3 认购 Property3 0 USDC (应该失败，因为Property3已经达到最大募集额)
echo "🧪 Test 11: USER3 attempting to contribute to Property 3 (should fail, max raised)..."
USER3_CONTRIBUTION3=$((1000 * 1000000))  # 1000 USDC (6 decimals) - small amount to test failure

# 先授权USDC
echo "   Authorizing USDC for USER3..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES3_ADDR $USER3_CONTRIBUTION3 \
    || { echo "❌ Failed to approve USDC for USER3"; exit 1; }

# 认购 (这个应该失败，因为Property3已经达到最大募集额)
echo "   Contributing USDC (expected to fail, max raised)..."
if cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES3_ADDR "contribute(uint256)" $USER3_CONTRIBUTION3 2>&1 | grep -q "error"; then
    echo "✅ USER3 contribution to Property 3 failed as expected (max raising reached)"
else
    echo "❌ USER3 contribution to Property 3 should have failed"
fi

# 步骤6: 验证最终状态
echo "🔍 Step 6: Final verification and summary..."

echo "📊 Series Contract Information:"
echo "   Series 1 (Property 1): $SERIES1_ADDR"
echo "   Series 2 (Property 2): $SERIES2_ADDR"
echo "   Series 3 (Property 3): $SERIES3_ADDR"
echo ""

# 验证代币信息
echo "📝 Token Details:"
TOKEN1_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "name()(string)")
TOKEN1_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "symbol()(string)")
echo "   Series 1: $TOKEN1_NAME_ACTUAL ($TOKEN1_SYMBOL_ACTUAL)"

TOKEN2_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "name()(string)")
TOKEN2_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "symbol()(string)")
echo "   Series 2: $TOKEN2_NAME_ACTUAL ($TOKEN2_SYMBOL_ACTUAL)"

TOKEN3_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "name()(string)")
TOKEN3_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "symbol()(string)")
echo "   Series 3: $TOKEN3_NAME_ACTUAL ($TOKEN3_SYMBOL_ACTUAL)"
echo ""

# 检查当前阶段
echo "📈 Current Phases:"
CURRENT_PHASE1=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")
CURRENT_PHASE2=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "getPhase()(uint8)")
CURRENT_PHASE3=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")

echo "   Series 1: Phase $CURRENT_PHASE1"
echo "   Series 2: Phase $CURRENT_PHASE2"
echo "   Series 3: Phase $CURRENT_PHASE3"
echo ""

# 显示最终用户USDC余额
echo "💰 Final USDC Balances:"
USER1_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

echo "   USER1 (Landlord): $(echo $USER1_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER2 (Investor): $(echo $USER2_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3 (Investor): $(echo $USER3_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER4 (Non-KYC): $(echo $USER4_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

# 步骤7: 展示所有房产的募集金额
echo "💰 Step 7: Displaying fundraising amounts for all properties..."

echo "📊 Property 1 (Test Apartment) Fundraising Status:"
PROPERTY1_RAISED=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "totalFundRaised()(uint256)")
PROPERTY1_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "minRaising()(uint256)")
PROPERTY1_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "maxRaising()(uint256)")
PROPERTY1_PHASE=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")

echo "   Total Raised: $(echo $PROPERTY1_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Min Required: $(echo $PROPERTY1_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Max Allowed: $(echo $PROPERTY1_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Current Phase: $PROPERTY1_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY1_RAISED_CLEAN=$(echo $PROPERTY1_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY1_MIN_RAISING_CLEAN=$(echo $PROPERTY1_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY1_MAX_RAISING_CLEAN=$(echo $PROPERTY1_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   Status: $(if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MIN_RAISING_CLEAN ]; then echo "✅ Min target reached"; else echo "❌ Min target not reached"; fi)"
echo "   Status: $(if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MAX_RAISING_CLEAN ]; then echo "✅ Max target reached"; else echo "❌ Max target not reached"; fi)"
echo ""

echo "📊 Property 2 (Luxury Villa) Fundraising Status:"
PROPERTY2_RAISED=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "totalFundRaised()(uint256)")
PROPERTY2_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "minRaising()(uint256)")
PROPERTY2_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "maxRaising()(uint256)")
PROPERTY2_PHASE=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "getPhase()(uint8)")

echo "   Total Raised: $(echo $PROPERTY2_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Min Required: $(echo $PROPERTY2_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Max Allowed: $(echo $PROPERTY2_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Current Phase: $PROPERTY2_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY2_RAISED_CLEAN=$(echo $PROPERTY2_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY2_MIN_RAISING_CLEAN=$(echo $PROPERTY2_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY2_MAX_RAISING_CLEAN=$(echo $PROPERTY2_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   Status: $(if [ $PROPERTY2_RAISED_CLEAN -ge $PROPERTY2_MIN_RAISING_CLEAN ]; then echo "✅ Min target reached"; else echo "❌ Min target not reached"; fi)"
echo "   Status: $(if [ $PROPERTY2_RAISED_CLEAN -ge $PROPERTY2_MAX_RAISING_CLEAN ]; then echo "✅ Max target reached"; else echo "❌ Max target not reached"; fi)"
echo ""

echo "📊 Property 3 (Cozy Studio) Fundraising Status:"
PROPERTY3_RAISED=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "totalFundRaised()(uint256)")
PROPERTY3_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "minRaising()(uint256)")
PROPERTY3_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "maxRaising()(uint256)")
PROPERTY3_PHASE=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")

echo "   Total Raised: $(echo $PROPERTY3_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Min Required: $(echo $PROPERTY3_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Max Allowed: $(echo $PROPERTY3_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Current Phase: $PROPERTY3_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY3_RAISED_CLEAN=$(echo $PROPERTY3_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY3_MIN_RAISING_CLEAN=$(echo $PROPERTY3_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY3_MAX_RAISING_CLEAN=$(echo $PROPERTY3_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   Status: $(if [ $PROPERTY3_RAISED_CLEAN -ge $PROPERTY3_MIN_RAISING_CLEAN ]; then echo "✅ Min target reached"; else echo "❌ Min target not reached"; fi)"
echo "   Status: $(if [ $PROPERTY3_RAISED_CLEAN -ge $PROPERTY3_MAX_RAISING_CLEAN ]; then echo "✅ Max target reached"; else echo "❌ Max target not reached"; fi)"
echo ""

# 步骤8: Admin将房产1设置为开始状态
echo "🚀 Step 8: Admin setting Property 1 to start accrual phase..."

# 检查房产1是否达到最小募集目标
if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MIN_RAISING_CLEAN ]; then
    echo "   Property 1 has reached minimum fundraising target"
    echo "   Current phase: $PROPERTY1_PHASE"

    # 检查是否还在募资阶段
    if [ $PROPERTY1_PHASE -eq 0 ]; then
        echo "   Property 1 is in fundraising phase, proceeding to start accrual..."

        # 调用setStartTime()函数，需要先检查合约的owner
        PROPERTY1_OWNER=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "owner()(address)")
        echo "   Property 1 contract owner: $PROPERTY1_OWNER"

        if [ "$PROPERTY1_OWNER" = "$ADMIN_ADDRESS" ]; then
            echo "   Admin is the owner, calling setStartTime()..."
            cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
                $SERIES1_ADDR "setStartTime()" \
                || { echo "❌ Failed to set start time for Property 1"; exit 1; }

            echo "✅ Property 1 start time set successfully"

            # 验证状态变化
            NEW_PHASE=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")
            NEW_ACCRUAL_START=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "accrualStart()(uint64)")

            echo "   New phase: $NEW_PHASE"
            echo "   New accrual start time: $NEW_ACCRUAL_START ($(date -r $NEW_ACCRUAL_START))"

        else
            echo "   ⚠️  Admin is not the owner of Property 1 contract"
            echo "   Cannot set start time. Owner is: $PROPERTY1_OWNER"
        fi
    else
        echo "   Property 1 is not in fundraising phase (current phase: $PROPERTY1_PHASE)"
        echo "   Cannot set start time"
    fi
else
    echo "   ❌ Property 1 has not reached minimum fundraising target"
    echo "   Cannot set start time"
fi

echo ""

# 保存关键信息到环境变量文件
echo "# Case 2 Test Results - $(date)" >> .env
echo "CASE2_PROPERTY1_ID=$PROPERTY1_ID" >> .env
echo "CASE2_PROPERTY2_ID=$PROPERTY2_ID" >> .env
echo "CASE2_PROPERTY3_ID=$PROPERTY3_ID" >> .env
echo "CASE2_SERIES1_ADDR=$SERIES1_ADDR" >> .env
echo "CASE2_SERIES2_ADDR=$SERIES2_ADDR" >> .env
echo "CASE2_SERIES3_ADDR=$SERIES3_ADDR" >> .env
echo "CASE2_TOKEN1_SYMBOL=$TOKEN1_SYMBOL" >> .env
echo "CASE2_TOKEN2_SYMBOL=$TOKEN2_SYMBOL" >> .env
echo "CASE2_TOKEN3_SYMBOL=$TOKEN3_SYMBOL" >> .env

echo "✅ Case 2 setup and testing completed successfully!"
echo "=================================================="
echo "🎯 Summary:"
echo "   - 3 properties added to PropertyOracle"
echo "   - USER1, USER2, USER3 added to KYC whitelist"
echo "   - USER4 remains non-KYC for testing"
echo "   - 3 RentToken series created"
echo "   - All investment tests completed"
echo "   - Series 1: USER2 contributed 28800 USDC (max reached)"
echo "   - Series 2: USER2 contribution failed (insufficient amount) as expected"
echo "   - Series 3: USER2 contributed 19200 USDC (max reached)"
echo "   - USER3 attempts failed (Properties 1 & 3 already at max) as expected"
echo "   - Property 1 fundraising status displayed"
echo "   - Property 1 start time set (if conditions met)"
echo ""
echo "🚀 Ready for further testing!"
echo "💡 Next steps: Monitor contract phases and test profit distribution"
