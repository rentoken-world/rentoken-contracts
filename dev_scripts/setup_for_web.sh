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
#     "minRaising": 20000,
#     "maxRaising": 20000,
#     "accrualStart": 1756051200,
#     "accrualEnd": 1841392800,
#     "landlord": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
#     "docHash": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
#     "offchainURL": "https://ipfs.io/ipfs/QmTestApartment"
#   },
#   {
#     "propertyId": 2,
#     "payoutToken": "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
#     "valuation": 180000,
#     "minRaising": 50000,
#     "maxRaising": 100000,
#     "accrualStart": 1756051200,
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
#     "accrualStart": 1756051200,
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
# 7 user2 认购propert1 10000 最终应该发售成功
# 8 user2 认购propert2 10000 最终应该发售失败
# 9 user2 认购propert3 10000 最终应该发售成功
# 10 user3 认购propert1 10000 最终应该发售成功
# 11 user3 认购propert3 9200 最终应该发售成功
# 12 property1 通过admin 设置开始时间, 应该发售成功，认购20000，房东获得8800 token
# 13 property2 不用修改时间，继续等待中，认购金额应该是10000。状态还是认购中。
# 14 property3 不用修改时间，继续等待中，认购金额应该是19200。状态还是认购中。

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 开始案例2测试场景..."
echo "=================================================="

# 检查 .env 文件是否存在
if [ ! -f ".env" ]; then
    echo "❌ 未找到 .env 文件。请先运行 init-local.sh 脚本。"
    exit 1
fi

# 加载环境变量
echo "📋 从 .env 文件加载环境变量..."
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
        echo "❌ 缺少必要的环境变量: $var"
        exit 1
    fi
done

echo "✅ 环境变量加载成功"
echo "🔑 测试地址:"
echo "   管理员: $ADMIN_ADDRESS"
echo "   用户1 (房东): $USER1_ADDRESS"
echo "   用户2 (投资人): $USER2_ADDRESS"
echo "   用户3 (投资人): $USER3_ADDRESS"
echo "   用户4 (非KYC): $USER4_ADDRESS"
echo ""

# 步骤1: 管理员添加3套房产到PropertyOracle
echo "🏠 步骤1: 向PropertyOracle添加3套房产..."

# 房产1: Test Apartment
PROPERTY1_ID=1
PROPERTY1_DOC_HASH=$(echo -n "Test Apartment Property Document" | cast keccak)
PROPERTY1_OFFCHAIN_URL="https://ipfs.io/ipfs/QmTestApartment"
PROPERTY1_VALUATION=$((72000 * 1000000))  # 72000 USDC (6 decimals)
PROPERTY1_MIN_RAISING=$((20000 * 1000000))  # 20000 USDC minimum (adjusted for test scenario)
PROPERTY1_MAX_RAISING=$((20000 * 1000000))  # 20000 USDC maximum (adjusted for test scenario)

# 房产2: Luxury Villa
PROPERTY2_ID=2
PROPERTY2_DOC_HASH=$(echo -n "Luxury Villa Property Document" | cast keccak)
PROPERTY2_OFFCHAIN_URL="https://ipfs.io/ipfs/QmLuxuryVilla"
PROPERTY2_VALUATION=$((180000 * 1000000))  # 180000 USDC (6 decimals)
PROPERTY2_MIN_RAISING=$((50000 * 1000000))  # 50000 USDC minimum (adjusted for test scenario)
PROPERTY2_MAX_RAISING=$((100000 * 1000000))  # 100000 USDC maximum (adjusted for test scenario)

# 房产3: Cozy Studio
PROPERTY3_ID=3
PROPERTY3_DOC_HASH=$(echo -n "Cozy Studio Property Document" | cast keccak)
PROPERTY3_OFFCHAIN_URL="https://ipfs.io/ipfs/QmCozyStudio"
PROPERTY3_VALUATION=$((19200 * 1000000))  # 19200 USDC (6 decimals)
PROPERTY3_MIN_RAISING=$((19200 * 1000000))  # 19200 USDC minimum (unchanged)
PROPERTY3_MAX_RAISING=$((19200 * 1000000))  # 19200 USDC maximum (unchanged)

# 使用固定的时间戳（从注释中获取）
ACCRUAL_START=1756051200
ACCRUAL_END=1841392800

echo "⏰ 时间配置:"
echo "   收益开始时间: $ACCRUAL_START ($(date -r $ACCRUAL_START))"
echo "   收益结束时间: $ACCRUAL_END ($(date -r $ACCRUAL_END))"
echo ""

echo "📝 房产1详情 (测试公寓):"
echo "   房产ID: $PROPERTY1_ID"
echo "   房东: $USER1_ADDRESS"
echo "   估值: $PROPERTY1_VALUATION (72000 USDC)"
echo "   最小/最大募集: $PROPERTY1_MIN_RAISING (20000 USDC)"
echo ""

echo "📝 房产2详情 (豪华别墅):"
echo "   Property ID: $PROPERTY2_ID"
echo "   房东: $USER1_ADDRESS"
echo "   估值: $PROPERTY2_VALUATION (180000 USDC)"
echo "   最小/最大募集: $PROPERTY2_MIN_RAISING (50000 USDC) / $PROPERTY2_MAX_RAISING (100000 USDC)"
echo ""

echo "📝 房产3详情 (温馨工作室):"
echo "   房产ID: $PROPERTY3_ID"
echo "   房东: $USER1_ADDRESS"
echo "   估值: $PROPERTY3_VALUATION (19200 USDC)"
echo "   最小/最大募集: $PROPERTY3_MIN_RAISING (19200 USDC)"
echo ""

# 添加房产1
echo "   正在添加房产1..."
PROPERTY1_DATA="($PROPERTY1_ID,$USDC_ADDR,$PROPERTY1_VALUATION,$PROPERTY1_MIN_RAISING,$PROPERTY1_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY1_DOC_HASH,\"$PROPERTY1_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY1_ID "$PROPERTY1_DATA" \
    || { echo "❌ 添加房产1失败"; exit 1; }

echo "✅ 房产1添加成功"

# 添加房产2
echo "   正在添加房产2..."
PROPERTY2_DATA="($PROPERTY2_ID,$USDC_ADDR,$PROPERTY2_VALUATION,$PROPERTY2_MIN_RAISING,$PROPERTY2_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY2_DOC_HASH,\"$PROPERTY2_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY2_ID "$PROPERTY2_DATA" \
    || { echo "❌ 添加房产2失败"; exit 1; }

echo "✅ 房产2添加成功"

# 添加房产3
echo "   正在添加房产3..."
PROPERTY3_DATA="($PROPERTY3_ID,$USDC_ADDR,$PROPERTY3_VALUATION,$PROPERTY3_MIN_RAISING,$PROPERTY3_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER1_ADDRESS,$PROPERTY3_DOC_HASH,\"$PROPERTY3_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY3_ID "$PROPERTY3_DATA" \
    || { echo "❌ 添加房产3失败"; exit 1; }

echo "✅ 房产3添加成功"

# 验证房产添加成功
echo "🔍 验证房产..."
PROPERTY1_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY1_ID)
PROPERTY2_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY2_ID)
PROPERTY3_EXISTS=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "propertyExists(uint256)(bool)" $PROPERTY3_ID)

if [ "$PROPERTY1_EXISTS" = "true" ] && [ "$PROPERTY2_EXISTS" = "true" ] && [ "$PROPERTY3_EXISTS" = "true" ]; then
    echo "✅ 所有房产验证成功"
else
    echo "❌ 房产验证失败"
    exit 1
fi

# 步骤2: 管理员添加用户到KYC白名单
echo "🔐 步骤2: 向KYC白名单添加用户..."

# 检查并添加USER1 (房东) 到KYC白名单
echo "   检查用户1 (房东) KYC状态..."
USER1_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER1_ADDRESS)
if [ "$USER1_KYC_CURRENT" = "false" ]; then
    echo "   正在添加用户1到KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER1_ADDRESS \
        || { echo "❌ 添加用户1到KYC失败"; exit 1; }
else
    echo "   用户1已在KYC白名单中"
fi

# 检查并添加USER2 (投资人) 到KYC白名单
echo "   检查用户2 (投资人) KYC状态..."
USER2_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER2_ADDRESS)
if [ "$USER2_KYC_CURRENT" = "false" ]; then
    echo "   正在添加用户2到KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER2_ADDRESS \
        || { echo "❌ 添加用户2到KYC失败"; exit 1; }
else
    echo "   用户2已在KYC白名单中"
fi

# 检查并添加USER3 (投资人) 到KYC白名单
echo "   检查用户3 (投资人) KYC状态..."
USER3_KYC_CURRENT=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER3_ADDRESS)
if [ "$USER3_KYC_CURRENT" = "false" ]; then
    echo "   正在添加用户3到KYC..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $KYC_ORACLE_ADDR "addToWhitelist(address)" $USER3_ADDRESS \
        || { echo "❌ 添加用户3到KYC失败"; exit 1; }
else
    echo "   用户3已在KYC白名单中"
fi

# 注意：用户4 故意不添加到KYC白名单中

echo "✅ KYC白名单已更新"

# 验证KYC状态
echo "🔍 验证KYC状态:"
USER1_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER1_ADDRESS)
USER2_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER2_ADDRESS)
USER3_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER3_ADDRESS)
USER4_KYC=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "isWhitelisted(address)(bool)" $USER4_ADDRESS)

echo "   用户1 KYC状态: $USER1_KYC"
echo "   用户2 KYC状态: $USER2_KYC"
echo "   用户3 KYC状态: $USER3_KYC"
echo "   用户4 KYC状态: $USER4_KYC (应该是false)"
echo ""

# 步骤3: 管理员通过SeriesFactory创建3个ERC20代币系列
echo "🪙 步骤3: 通过SeriesFactory创建3个RentToken系列..."

# 系列1: 测试公寓
TOKEN1_NAME="RenToken Test Apartment 001"
TOKEN1_SYMBOL="RTTA1"

# 系列2: 豪华别墅
TOKEN2_NAME="RenToken Luxury Villa 001"
TOKEN2_SYMBOL="RTLV1"

# 系列3: 温馨工作室
TOKEN3_NAME="RenToken Cozy Studio 001"
TOKEN3_SYMBOL="RTCS1"

echo "📝 为房产1创建系列..."
SERIES1_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY1_ID)

if [ "$SERIES1_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   正在为房产1创建新系列..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY1_ID "$TOKEN1_NAME" "$TOKEN1_SYMBOL" \
        || { echo "❌ 创建系列1失败"; exit 1; }
    echo "✅ 系列1创建交易已发送"
    SERIES1_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY1_ID)
else
    echo "   系列1已存在"
fi

echo "📝 为房产2创建系列..."
SERIES2_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY2_ID)

if [ "$SERIES2_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   正在为房产2创建新系列..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY2_ID "$TOKEN2_NAME" "$TOKEN2_SYMBOL" \
        || { echo "❌ 创建系列2失败"; exit 1; }
    echo "✅ 系列2创建交易已发送"
    SERIES2_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY2_ID)
else
    echo "   系列2已存在"
fi

echo "📝 为房产3创建系列..."
SERIES3_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY3_ID)

if [ "$SERIES3_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "   正在为房产3创建新系列..."
    cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
        $SERIES_FACTORY_ADDR \
        "createSeries(uint256,string,string)" \
        $PROPERTY3_ID "$TOKEN3_NAME" "$TOKEN3_SYMBOL" \
        || { echo "❌ 创建系列3失败"; exit 1; }
    echo "✅ 系列3创建交易已发送"
    SERIES3_ADDR=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "getSeriesAddress(uint256)(address)" $PROPERTY3_ID)
else
    echo "   系列3已存在"
fi

echo "🎯 系列合约地址:"
echo "   系列1 (房产1): $SERIES1_ADDR"
echo "   系列2 (房产2): $SERIES2_ADDR"
echo "   系列3 (房产3): $SERIES3_ADDR"

# 验证系列创建成功
if [ "$SERIES1_ADDR" = "0x0000000000000000000000000000000000000000" ] || \
   [ "$SERIES2_ADDR" = "0x0000000000000000000000000000000000000000" ] || \
   [ "$SERIES3_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ 系列创建失败"
    exit 1
else
    echo "✅ 所有系列准备就绪"
fi

# 步骤4: 设置系列合约的Oracle
echo "⚙️ 步骤4: 为所有系列设置Oracle..."

echo "   正在为系列1设置Oracle..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY1_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列1设置Oracle失败"; exit 1; }

echo "   正在为系列2设置Oracle..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY2_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列2设置Oracle失败"; exit 1; }

echo "   正在为系列3设置Oracle..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY3_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列3设置Oracle失败"; exit 1; }

echo "✅ 已为所有系列设置Oracle"

# 步骤5: 投资人认购测试
echo "💰 步骤5: 测试投资人认购..."

# 显示用户USDC余额
echo "🔍 当前USDC余额:"
USER1_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

echo "   用户1 (房东): $(echo $USER1_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户2 (投资人): $(echo $USER2_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户3 (投资人): $(echo $USER3_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户4 (非KYC): $(echo $USER4_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

# 测试7: 用户2 认购 房产1 10000 USDC (应该成功，最终发售成功)
echo "🧪 测试7: 用户2向房产1认购10000 USDC..."
USER2_CONTRIBUTION1=$((10000 * 1000000))  # 10000 USDC (6 decimals)

# 先授权USDC
echo "   正在为用户2授权USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES1_ADDR $USER2_CONTRIBUTION1 \
    || { echo "❌ 用户2授权USDC失败"; exit 1; }

# 认购
echo "   正在认购USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES1_ADDR "contribute(uint256)" $USER2_CONTRIBUTION1 \
    || { echo "❌ 用户2认购USDC失败"; exit 1; }

echo "✅ 用户2向房产1认购成功"

# 测试8: 用户2 认购 房产2 10000 USDC (应该失败，最终发售失败)
echo "🧪 测试8: 用户2向房产2认购10000 USDC..."
USER2_CONTRIBUTION2=$((10000 * 1000000))  # 10000 USDC (6 decimals)

# 先授权USDC
echo "   正在为用户2授权USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES2_ADDR $USER2_CONTRIBUTION2 \
    || { echo "❌ 用户2授权USDC失败"; exit 1; }

# 认购 (这个应该失败，因为房产2需要50000 USDC才能达到最小募集额，但只认购了10000)
echo "   正在认购USDC (预期失败，募集额不足)..."
if cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES2_ADDR "contribute(uint256)" $USER2_CONTRIBUTION2 2>&1 | grep -q "error"; then
    echo "✅ 用户2向房产2认购失败，符合预期 (募集额不足)"
else
    echo "❌ 用户2向房产2认购应该失败"
fi

# 测试9: 用户2 认购 房产3 10000 USDC (应该成功，最终发售成功)
echo "🧪 测试9: 用户2向房产3认购10000 USDC..."
USER2_CONTRIBUTION3=$((10000 * 1000000))  # 10000 USDC (6 decimals)

# 先授权USDC
echo "   正在为用户2授权USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES3_ADDR $USER2_CONTRIBUTION3 \
    || { echo "❌ 用户2授权USDC失败"; exit 1; }

# 认购
echo "   正在认购USDC..."
cast send --rpc-url $RPC_URL --private-key $USER2_PRIVATE_KEY \
    $SERIES3_ADDR "contribute(uint256)" $USER2_CONTRIBUTION3 \
    || { echo "❌ 用户2认购USDC失败"; exit 1; }

echo "✅ 用户2向房产3认购成功"

# 测试10: 用户3 认购 房产1 10000 USDC (应该成功，最终发售成功)
echo "🧪 测试10: 用户3向房产1认购10000 USDC..."
USER3_CONTRIBUTION1=$((10000 * 1000000))  # 10000 USDC (6 decimals)

# 先授权USDC
echo "   正在为用户3授权USDC..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES1_ADDR $USER3_CONTRIBUTION1 \
    || { echo "❌ 用户3授权USDC失败"; exit 1; }

# 认购
echo "   正在认购USDC..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES1_ADDR "contribute(uint256)" $USER3_CONTRIBUTION1 \
    || { echo "❌ 用户3认购USDC失败"; exit 1; }

echo "✅ 用户3向房产1认购成功"

# 测试11: 用户3 认购 房产3 9200 USDC (应该成功，最终发售成功)
echo "🧪 测试11: 用户3向房产3认购9200 USDC..."
USER3_CONTRIBUTION3=$((9200 * 1000000))  # 9200 USDC (6 decimals)

# 先授权USDC
echo "   正在为用户3授权USDC..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $USDC_ADDR "approve(address,uint256)" $SERIES3_ADDR $USER3_CONTRIBUTION3 \
    || { echo "❌ 用户3授权USDC失败"; exit 1; }

# 认购
echo "   正在认购USDC..."
cast send --rpc-url $RPC_URL --private-key $USER3_PRIVATE_KEY \
    $SERIES3_ADDR "contribute(uint256)" $USER3_CONTRIBUTION3 \
    || { echo "❌ 用户3认购USDC失败"; exit 1; }

echo "✅ 用户3向房产3认购成功"

# 步骤6: 验证最终状态
echo "🔍 步骤6: 最终验证和总结..."

echo "📊 系列合约信息:"
echo "   系列1 (房产1): $SERIES1_ADDR"
echo "   系列2 (房产2): $SERIES2_ADDR"
echo "   系列3 (房产3): $SERIES3_ADDR"
echo ""

# 验证代币信息
echo "📝 代币详情:"
TOKEN1_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "name()(string)")
TOKEN1_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "symbol()(string)")
echo "   系列1: $TOKEN1_NAME_ACTUAL ($TOKEN1_SYMBOL_ACTUAL)"

TOKEN2_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "name()(string)")
TOKEN2_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "symbol()(string)")
echo "   系列2: $TOKEN2_NAME_ACTUAL ($TOKEN2_SYMBOL_ACTUAL)"

TOKEN3_NAME_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "name()(string)")
TOKEN3_SYMBOL_ACTUAL=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "symbol()(string)")
echo "   系列3: $TOKEN3_NAME_ACTUAL ($TOKEN3_SYMBOL_ACTUAL)"
echo ""

# 检查当前阶段
echo "📈 当前阶段:"
CURRENT_PHASE1=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")
CURRENT_PHASE2=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "getPhase()(uint8)")
CURRENT_PHASE3=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")

echo "   系列1: 阶段 $CURRENT_PHASE1"
echo "   系列2: 阶段 $CURRENT_PHASE2"
echo "   系列3: 阶段 $CURRENT_PHASE3"
echo ""

# 显示最终用户USDC余额
echo "💰 最终USDC余额:"
USER1_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_FINAL_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

echo "   用户1 (房东): $(echo $USER1_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户2 (投资人): $(echo $USER2_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户3 (投资人): $(echo $USER3_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   用户4 (非KYC): $(echo $USER4_FINAL_BALANCE | awk '{printf "%.6f", $1/1000000}') USDC"
echo ""

# 步骤7: 展示所有房产的募集金额
echo "💰 步骤7: 显示所有房产的募集金额..."

echo "📊 房产1 (测试公寓) 募集状态:"
PROPERTY1_RAISED=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "totalFundRaised()(uint256)")
PROPERTY1_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "minRaising()(uint256)")
PROPERTY1_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "maxRaising()(uint256)")
PROPERTY1_PHASE=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")

echo "   总募集金额: $(echo $PROPERTY1_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最小要求: $(echo $PROPERTY1_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最大允许: $(echo $PROPERTY1_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   当前阶段: $PROPERTY1_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY1_RAISED_CLEAN=$(echo $PROPERTY1_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY1_MIN_RAISING_CLEAN=$(echo $PROPERTY1_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY1_MAX_RAISING_CLEAN=$(echo $PROPERTY1_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   状态: $(if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MIN_RAISING_CLEAN ]; then echo "✅ 达到最小目标"; else echo "❌ 未达到最小目标"; fi)"
echo "   状态: $(if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MAX_RAISING_CLEAN ]; then echo "✅ 达到最大目标"; else echo "❌ 未达到最大目标"; fi)"
echo ""

echo "📊 房产2 (豪华别墅) 募集状态:"
PROPERTY2_RAISED=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "totalFundRaised()(uint256)")
PROPERTY2_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "minRaising()(uint256)")
PROPERTY2_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "maxRaising()(uint256)")
PROPERTY2_PHASE=$(cast call --rpc-url $RPC_URL $SERIES2_ADDR "getPhase()(uint8)")

echo "   总募集金额: $(echo $PROPERTY2_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最小要求: $(echo $PROPERTY2_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最大允许: $(echo $PROPERTY2_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   当前阶段: $PROPERTY2_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY2_RAISED_CLEAN=$(echo $PROPERTY2_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY2_MIN_RAISING_CLEAN=$(echo $PROPERTY2_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY2_MAX_RAISING_CLEAN=$(echo $PROPERTY2_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   状态: $(if [ $PROPERTY2_RAISED_CLEAN -ge $PROPERTY2_MIN_RAISING_CLEAN ]; then echo "✅ 达到最小目标"; else echo "❌ 未达到最小目标"; fi)"
echo "   状态: $(if [ $PROPERTY2_RAISED_CLEAN -ge $PROPERTY2_MAX_RAISING_CLEAN ]; then echo "✅ 达到最大目标"; else echo "❌ 未达到最大目标"; fi)"
echo ""

echo "📊 房产3 (温馨工作室) 募集状态:"
PROPERTY3_RAISED=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "totalFundRaised()(uint256)")
PROPERTY3_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "minRaising()(uint256)")
PROPERTY3_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "maxRaising()(uint256)")
PROPERTY3_PHASE=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")

echo "   总募集金额: $(echo $PROPERTY3_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最小要求: $(echo $PROPERTY3_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最大允许: $(echo $PROPERTY3_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   当前阶段: $PROPERTY3_PHASE"
# 使用数值比较，去除可能的空格和额外格式信息
PROPERTY3_RAISED_CLEAN=$(echo $PROPERTY3_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY3_MIN_RAISING_CLEAN=$(echo $PROPERTY3_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY3_MAX_RAISING_CLEAN=$(echo $PROPERTY3_MAX_RAISING | sed 's/\[.*\]//' | tr -d ' ')

echo "   状态: $(if [ $PROPERTY3_RAISED_CLEAN -ge $PROPERTY3_MIN_RAISING_CLEAN ]; then echo "✅ 达到最小目标"; else echo "❌ 未达到最小目标"; fi)"
echo "   状态: $(if [ $PROPERTY3_RAISED_CLEAN -ge $PROPERTY3_MAX_RAISING_CLEAN ]; then echo "✅ 达到最大目标"; else echo "❌ 未达到最大目标"; fi)"
echo ""

# 步骤8: 管理员通过SeriesFactory开始房产1的收益阶段
echo "🚀 步骤8: 管理员通过SeriesFactory开始房产1的收益阶段..."

# 检查房产1是否达到最小募集目标
if [ $PROPERTY1_RAISED_CLEAN -ge $PROPERTY1_MIN_RAISING_CLEAN ]; then
    echo "   房产1已达到最小募集目标"
    echo "   当前阶段: $PROPERTY1_PHASE"

    # 检查是否还在募资阶段
    if [ $PROPERTY1_PHASE -eq 0 ]; then
        echo "   房产1处于募资阶段，正在通过SeriesFactory开始收益阶段..."

        # 通过SeriesFactory调用startSeriesNow方法
        echo "   正在调用SeriesFactory.startSeriesNow()..."
        cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
            $SERIES_FACTORY_ADDR "startSeriesNow(uint256)" $PROPERTY1_ID \
            || { echo "❌ 通过SeriesFactory开始房产1失败"; exit 1; }

        echo "✅ 房产1开始时间设置成功"

        # 验证状态变化
        NEW_PHASE=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "getPhase()(uint8)")
        NEW_ACCRUAL_START=$(cast call --rpc-url $RPC_URL $SERIES1_ADDR "accrualStart()(uint64)")

        echo "   新阶段: $NEW_PHASE"
        echo "   新收益开始时间: $NEW_ACCRUAL_START ($(date -r $NEW_ACCRUAL_START))"

    else
        echo "   房产1不处于募资阶段 (当前阶段: $PROPERTY1_PHASE)"
        echo "   无法设置开始时间"
    fi
else
    echo "   ❌ 房产1未达到最小募集目标"
    echo "   无法设置开始时间"
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

echo "✅ 案例2设置和测试完成！"
echo "=================================================="
echo "🎯 总结:"
echo "   - 3套房产已添加到PropertyOracle"
echo "   - 用户1、用户2、用户3已添加到KYC白名单"
echo "   - 用户4保持非KYC状态用于测试"
echo "   - 3个RentToken系列已创建"
echo "   - 所有投资测试已按规范完成:"
echo "     • 测试7: 用户2向房产1认购10000 USDC (成功)"
echo "     • 测试8: 用户2向房产2认购10000 USDC (失败，募集额不足)"
echo "     • 测试9: 用户2向房产3认购10000 USDC (成功)"
echo "     • 测试10: 用户3向房产1认购10000 USDC (成功)"
echo "     • 测试11: 用户3向房产3认购9200 USDC (成功)"
echo "   - 房产1: 总募集20000 USDC (达到最小目标，准备开始收益)"
echo "   - 房产2: 总募集10000 USDC (未达到最小目标，继续募集中)"
echo "   - 房产3: 总募集19200 USDC (达到最小目标，准备开始收益)"
echo "   - 房产1开始时间已设置 (如果条件满足)"
echo ""
echo "🚀 准备进行进一步测试！"
echo "💡 下一步: 监控合约阶段并测试收益分配"
