#!/bin/bash
# 这里构建本地测试情况1，假设已经运行好了init-local.sh脚本，环境变量保存在.env文件里。

# 我们构造一个本地部署后的测试情况。
# 角色：
# 1 ADMIN 代表平台公司
# 2 user1 房东，有一套房产，房产信息如下：
# propertyID：1
# 房产地址：0x1234567890123456789012345678901234567890
# 房产名称：Test Apartment
# 房产描述：This is a test property
# 每月租金：1200$
# 抵押年限，5年，每年12000$
# 抵押开始时间，当前block时间+1h
# 抵押结束时间，当前block时间+1h+5年
# 抵押token，USDC
# 抵押token数量，28800$
# 抵押token地址，USDC_ADDR

# 3 user2 投资人 - kyc 通过

# 4 user3 投资人 - kyc 通过

# 5 user4 投资人 - kyc没有通过

# 事件：
# 1 admin添加房产进入property oracle
# 2 admin添加user1，user2， user3 进入kyc oracle
# 3 admin添加房产propertyID1 进入propertyOracle
# 4 user1 通过seriesFactory 发行erc20 币

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Case 1 Test Scenario..."
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
echo "   ADMIN: $ADMIN_ADDRESS"
echo "   USER1 (Landlord): $USER1_ADDRESS"
echo "   USER2 (Investor): $USER2_ADDRESS"
echo "   USER3 (Investor): $USER3_ADDRESS"
echo "   USER4 (Non-KYC): $USER4_ADDRESS"
echo ""

# 计算时间戳
CURRENT_TIME=$(cast block --rpc-url $RPC_URL latest --field timestamp)
ACCRUAL_START=$((CURRENT_TIME + 3600))  # 当前时间 + 1小时
ACCRUAL_END=$((ACCRUAL_START + 157680000))  # 5年后 (5 * 365 * 24 * 3600)

echo "⏰ Time Configuration:"
echo "   Current Block Time: $CURRENT_TIME"
echo "   Accrual Start: $ACCRUAL_START ($(date -r $ACCRUAL_START))"
echo "   Accrual End: $ACCRUAL_END ($(date -r $ACCRUAL_END))"
echo ""

# 步骤1: Admin添加房产到PropertyOracle
echo "🏠 Step 1: Adding Test Apartment to PropertyOracle..."

# 房产信息
PROPERTY_ID=1
PROPERTY_ADDRESS="0x1234567890123456789012345678901234567890"
DOC_HASH=$(echo -n "Test Apartment Property Document" | cast keccak)
OFFCHAIN_URL="https://example.com/property/1"
VALUATION=$((28800 * 1000000))  # 28800 USDC (6 decimals)
MIN_RAISING=$((20000 * 1000000))  # 20000 USDC minimum
MAX_RAISING=$((30000 * 1000000))  # 30000 USDC maximum

# 构造PropertyData结构体参数
PROPERTY_DATA="($PROPERTY_ID,$USDC_ADDR,$VALUATION,$MIN_RAISING,$MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$DOC_HASH,\"$OFFCHAIN_URL\")"

echo "📝 Property Details:"
echo "   Property ID: $PROPERTY_ID"
echo "   Landlord: $USER1_ADDRESS"
echo "   Payout Token: $USDC_ADDR"
echo "   Valuation: $VALUATION (28800 USDC)"
echo "   Min Raising: $MIN_RAISING (20000 USDC)"
echo "   Max Raising: $MAX_RAISING (30000 USDC)"
echo "   Doc Hash: $DOC_HASH"
echo ""

# 调用addOrUpdateProperty
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY_ID "$PROPERTY_DATA" \
    || { echo "❌ Failed to add property"; exit 1; }

echo "✅ Property added to PropertyOracle"

# 验证房产添加成功
PROPERTY_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY_ID)
if [ "$PROPERTY_EXISTS" = "true" ]; then
    echo "✅ Property verification successful"
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

# 步骤3: Admin通过SeriesFactory创建ERC20代币系列
echo "🪙 Step 3: Creating RentToken series through SeriesFactory..."

TOKEN_NAME="RenToken Test Apartment 001"
TOKEN_SYMBOL="RTTA1"

echo "📝 Token Details:"
echo "   Name: $TOKEN_NAME"
echo "   Symbol: $TOKEN_SYMBOL"
echo "   Property ID: $PROPERTY_ID"
echo ""

# 检查系列是否已经存在
SERIES_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY_ID)

if [ "$SERIES_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   Creating new series..."
    # 创建系列
    SERIES_TX=$(cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY_ID "$TOKEN_NAME" "$TOKEN_SYMBOL" \
        || { echo "❌ Failed to create series"; exit 1; })

    echo "✅ Series creation transaction sent"

    # 重新获取创建的系列合约地址
    SERIES_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY_ID)
else
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
echo "⚙️ Step 4: Setting oracles for the series..."

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ Failed to set oracles"; exit 1; }

echo "✅ Oracles set for series"

# 步骤5: 验证设置并显示关键信息
echo "🔍 Step 5: Final verification and summary..."

# 验证代币信息
TOKEN_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "name()(string)")
TOKEN_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "symbol()(string)")
TOKEN_DECIMALS=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "decimals()(uint8)")
TOTAL_SUPPLY=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalSupply()(uint256)")

echo "📊 Series Contract Information:"
echo "   Contract Address: $SERIES_ADDR"
echo "   Name: $TOKEN_NAME_ACTUAL"
echo "   Symbol: $TOKEN_SYMBOL_ACTUAL"
echo "   Decimals: $TOKEN_DECIMALS"
echo "   Total Supply: $TOTAL_SUPPLY"
echo ""

# 验证合约配置
SERIES_PROPERTY_ID=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "propertyId()(uint256)")
SERIES_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "minRaising()(uint256)")
SERIES_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "maxRaising()(uint256)")
SERIES_LANDLORD=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "landlordWalletAddress()(address)")

echo "🏠 Property Configuration:"
echo "   Property ID: $SERIES_PROPERTY_ID"
echo "   Min Raising: $SERIES_MIN_RAISING USDC"
echo "   Max Raising: $SERIES_MAX_RAISING USDC"
echo "   Landlord: $SERIES_LANDLORD"
echo ""

# 检查当前阶段
CURRENT_PHASE=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "getPhase()(uint8)")
PHASE_NAME=""
case $CURRENT_PHASE in
    0) PHASE_NAME="Fundraising" ;;
    1) PHASE_NAME="AccrualStarted" ;;
    2) PHASE_NAME="RisingFailed" ;;
    3) PHASE_NAME="AccrualFinished" ;;
    4) PHASE_NAME="Terminated" ;;
    *) PHASE_NAME="Unknown" ;;
esac

echo "📈 Current Phase: $CURRENT_PHASE ($PHASE_NAME)"
echo ""

# 显示用户USDC余额
echo "💰 User USDC Balances:"
USER1_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

# 使用 awk 进行数学计算，避免 bc 的依赖问题
echo "   USER1 (Landlord): $(echo $USER1_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER2 (Investor): $(echo $USER2_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER3 (Investor): $(echo $USER3_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER4 (Non-KYC): $(echo $USER4_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

# 保存关键信息到环境变量文件
echo "# Case 1 Test Results - $(date)" >> .env
echo "CASE1_PROPERTY_ID=$PROPERTY_ID" >> .env
echo "CASE1_SERIES_ADDR=$SERIES_ADDR" >> .env
echo "CASE1_TOKEN_NAME=\"$TOKEN_NAME\"" >> .env
echo "CASE1_TOKEN_SYMBOL=$TOKEN_SYMBOL" >> .env

echo "✅ Case 1 setup completed successfully!"
echo "=================================================="
echo "🎯 Summary:"
echo "   - Property ID $PROPERTY_ID added to PropertyOracle"
echo "   - USER1, USER2, USER3 added to KYC whitelist"
echo "   - USER4 remains non-KYC for testing"
echo "   - RentToken series '$TOKEN_SYMBOL' created at $SERIES_ADDR"
echo "   - Series is in $PHASE_NAME phase"
echo "   - All users have USDC for testing investments"
echo ""
echo "🚀 Ready for investment testing!"
echo "💡 Next steps: Users can now contribute USDC to purchase tokens"
echo "   - Use: cast send $SERIES_ADDR \"contribute(uint256)\" [amount]"
echo "   - Remember: USER4 will be rejected due to KYC requirements"
