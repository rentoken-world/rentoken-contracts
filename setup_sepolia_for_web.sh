#!/bin/bash
# 这里构建Sepolia测试情况2，已经运行好了init-sepolia.sh脚本，环境变量保存在.env文件里。

# 我们构造一个Sepolia部署后的测试情况。
# 角色：
# 1 ADMIN 代表平台公司，同时ADMIN拥有房产1, 注意用cast send 的时候，通过--account myMetaMaskAcc --password '' 来获取ADMIN的私钥
# 2 user7 房东，有2套房产，房产信息如下：
# [
#   {
#     "propertyId": 1,
#     "payoutToken": $USDC_ADDR,
#     "valuation": 72000,
#     "minRaising": 30000,
#     "maxRaising": 72000,
#     "accrualStart": 1756051200, // Sun Aug 24 2025 16:00:00 GMT+0000
#     "accrualEnd": 1841392800,
#     "landlord": $ADMIN_ADDRESS,
#     "docHash": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
#     "offchainURL": "https://ipfs.io/ipfs/QmTestApartment"
#   },
#   {
#     "propertyId": 2,
#     "payoutToken": $USDC_ADDR,
#     "valuation": 180000,
#     "minRaising": 50000,
#     "maxRaising": 100000,
#     "accrualStart": 1756051200,
#     "accrualEnd": 1841392800,
#     "landlord": $USER7_ADDRESS,
#     "docHash": "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
#     "offchainURL": "https://ipfs.io/ipfs/QmLuxuryVilla"
#   },
#   {
#     "propertyId": 3,
#     "payoutToken": $USDC_ADDR,
#     "valuation": 19200,
#     "minRaising": 15000,
#     "maxRaising": 19200,
#     "accrualStart": 1756051200,
#     "accrualEnd": 1841392800,
#     "landlord": $USER7_ADDRESS,
#     "docHash": "0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234",
#     "offchainURL": "https://ipfs.io/ipfs/QmCozyStudio"
#   }
# ]

# 事件：
# 1 admin添加房产propertyID1，2，3 进入propertyOracle
# 2 admin 通过seriesFactory createSeries 发行erc20 币
# 3 admin 通过seriesFactory createSeries 发行erc20 币
# 4 admin 通过seriesFactory createSeries 发行erc20 币
# 5 admin 认购propert3 16000
# 6 property3 通过admin 设置开始时间, 应该发售成功，认购16000，房东获得 3200 token
# 7 admin 通过seriesFactory 给 property3 调用 receiveProfit 1000 USDC

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 开始Sepolia案例2测试场景..."
echo "=================================================="

# 检查 sepolia.env 文件是否存在
if [ ! -f "sepolia.env" ]; then
    echo "❌ 未找到 sepolia.env 文件。请先运行 init-sepolia.sh 脚本。"
    exit 1
fi

# 加载环境变量
echo "📋 从 sepolia.env 文件加载环境变量..."
source sepolia.env

# 验证必要的环境变量
required_vars=(
    "RPC_URL" "CHAIN_ID"
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
echo "🔑 测试配置:"
echo "   RPC: $RPC_URL"
echo "   链ID: $CHAIN_ID"
echo "   KYC Oracle: $KYC_ORACLE_ADDR"
echo "   Property Oracle: $PROPERTY_ORACLE_ADDR"
echo "   Series Factory: $SERIES_FACTORY_ADDR"
echo "   USDC: $USDC_ADDR"
echo "   Sanction Oracle: $SANCTION_ORACLE_ADDR"
echo ""

# 定义测试用户地址（从init-sepolia.sh中获取）
USER7_ADDRESS="0xcC44277d1d6eC279Cd81e23111B1701758A3f82F"
ADMIN_ADDRESS="0x4DaA04d0B4316eCC9191Ae07102eC08Bded637a2"

echo "👥 测试用户:"
echo "   管理员: $ADMIN_ADDRESS"
echo "   用户7 (房东): $USER7_ADDRESS"
echo ""

# 步骤1: 管理员添加3套房产到PropertyOracle
echo "🏠 步骤1: 向PropertyOracle添加3套房产..."

# 房产1: Test Apartment (ADMIN拥有)
PROPERTY1_ID=1
PROPERTY1_DOC_HASH="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
PROPERTY1_OFFCHAIN_URL="https://ipfs.io/ipfs/QmTestApartment"
PROPERTY1_VALUATION=$((72000 * 1000000))  # 72000 USDC (6 decimals)
PROPERTY1_MIN_RAISING=$((30000 * 1000000))  # 30000 USDC minimum
PROPERTY1_MAX_RAISING=$((72000 * 1000000))  # 72000 USDC maximum

# 房产2: Luxury Villa (USER7拥有)
PROPERTY2_ID=2
PROPERTY2_DOC_HASH="0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
PROPERTY2_OFFCHAIN_URL="https://ipfs.io/ipfs/QmLuxuryVilla"
PROPERTY2_VALUATION=$((180000 * 1000000))  # 180000 USDC (6 decimals)
PROPERTY2_MIN_RAISING=$((50000 * 1000000))  # 50000 USDC minimum
PROPERTY2_MAX_RAISING=$((100000 * 1000000))  # 100000 USDC maximum

# 房产3: Cozy Studio (USER7拥有)
PROPERTY3_ID=3
PROPERTY3_DOC_HASH="0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234"
PROPERTY3_OFFCHAIN_URL="https://ipfs.io/ipfs/QmCozyStudio"
PROPERTY3_VALUATION=$((19200 * 1000000))  # 19200 USDC (6 decimals)
PROPERTY3_MIN_RAISING=$((15000 * 1000000))  # 15000 USDC minimum
PROPERTY3_MAX_RAISING=$((19200 * 1000000))  # 19200 USDC maximum

# 使用固定的时间戳（从注释中获取）
ACCRUAL_START=1756051200
ACCRUAL_END=1841392800

echo "⏰ 时间配置:"
echo "   收益开始时间: $ACCRUAL_START ($(date -r $ACCRUAL_START))"
echo "   收益结束时间: $ACCRUAL_END ($(date -r $ACCRUAL_END))"
echo ""

echo "📝 房产1详情 (测试公寓):"
echo "   房产ID: $PROPERTY1_ID"
echo "   房东: $ADMIN_ADDRESS"
echo "   估值: $PROPERTY1_VALUATION (72000 USDC)"
echo "   最小/最大募集: $PROPERTY1_MIN_RAISING (30000 USDC) / $PROPERTY1_MAX_RAISING (72000 USDC)"
echo ""

echo "📝 房产2详情 (豪华别墅):"
echo "   房产ID: $PROPERTY2_ID"
echo "   房东: $USER7_ADDRESS"
echo "   估值: $PROPERTY2_VALUATION (180000 USDC)"
echo "   最小/最大募集: $PROPERTY2_MIN_RAISING (50000 USDC) / $PROPERTY2_MAX_RAISING (100000 USDC)"
echo ""

echo "📝 房产3详情 (温馨工作室):"
echo "   房产ID: $PROPERTY3_ID"
echo "   房东: $USER7_ADDRESS"
echo "   估值: $PROPERTY3_VALUATION (19200 USDC)"
echo "   最小/最大募集: $PROPERTY3_MIN_RAISING (15000 USDC) / $PROPERTY3_MAX_RAISING (19200 USDC)"
echo ""

# 添加房产1
echo "   正在添加房产1..."
PROPERTY1_DATA="($PROPERTY1_ID,$USDC_ADDR,$PROPERTY1_VALUATION,$PROPERTY1_MIN_RAISING,$PROPERTY1_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$ADMIN_ADDRESS,$PROPERTY1_DOC_HASH,\"$PROPERTY1_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY1_ID "$PROPERTY1_DATA" \
    || { echo "❌ 添加房产1失败"; exit 1; }

echo "✅ 房产1添加成功"

# 添加房产2
echo "   正在添加房产2..."
PROPERTY2_DATA="($PROPERTY2_ID,$USDC_ADDR,$PROPERTY2_VALUATION,$PROPERTY2_MIN_RAISING,$PROPERTY2_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER7_ADDRESS,$PROPERTY2_DOC_HASH,\"$PROPERTY2_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $PROPERTY_ORACLE_ADDR \
    "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
    $PROPERTY2_ID "$PROPERTY2_DATA" \
    || { echo "❌ 添加房产2失败"; exit 1; }

echo "✅ 房产2添加成功"

# 添加房产3
echo "   正在添加房产3..."
PROPERTY3_DATA="($PROPERTY3_ID,$USDC_ADDR,$PROPERTY3_VALUATION,$PROPERTY3_MIN_RAISING,$PROPERTY3_MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$USER7_ADDRESS,$PROPERTY3_DOC_HASH,\"$PROPERTY3_OFFCHAIN_URL\")"

cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
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

# 步骤2-4: 管理员通过SeriesFactory创建3个ERC20代币系列
echo "🪙 步骤2-4: 通过SeriesFactory创建3个RentToken系列..."

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
    cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
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
    cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
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
    cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
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

# 为所有系列设置Oracle
echo "⚙️ 为所有系列设置Oracle..."

echo "   正在为系列1设置Oracle..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY1_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列1设置Oracle失败"; exit 1; }

echo "   正在为系列2设置Oracle..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY2_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列2设置Oracle失败"; exit 1; }

echo "   正在为系列3设置Oracle..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $SERIES_FACTORY_ADDR \
    "setOraclesForSeries(uint256,address,address)" \
    $PROPERTY3_ID $KYC_ORACLE_ADDR $SANCTION_ORACLE_ADDR \
    || { echo "❌ 为系列3设置Oracle失败"; exit 1; }

echo "✅ 已为所有系列设置Oracle"

# 步骤5: admin 认购房产3 31000 USDC
echo "💰 步骤5: admin认购房产3 31000 USDC..."

ADMIN_CONTRIBUTION3=$((16000 * 1000000))  # 31000 USDC (6 decimals)

# 先授权USDC
echo "   正在为admin授权USDC..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $USDC_ADDR "approve(address,uint256)" $SERIES3_ADDR $ADMIN_CONTRIBUTION3 \
    || { echo "❌ admin授权USDC失败"; exit 1; }

# 认购
echo "   正在认购USDC..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $SERIES3_ADDR "contribute(uint256)" $ADMIN_CONTRIBUTION3 \
    || { echo "❌ admin认购USDC失败"; exit 1; }

echo "✅ admin向房产3认购成功"

# 验证认购结果
echo "🔍 验证认购结果..."
PROPERTY3_RAISED=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "totalFundRaised()(uint256)")
PROPERTY3_MIN_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "minRaising()(uint256)")
PROPERTY3_MAX_RAISING=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "maxRaising()(uint256)")

echo "   房产3总募集金额: $(echo $PROPERTY3_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最小要求: $(echo $PROPERTY3_MIN_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   最大允许: $(echo $PROPERTY3_MAX_RAISING | awk '{printf "%.6f", $1/1000000}') USDC"

# 步骤6: property3 通过admin 设置开始时间
echo "🚀 步骤6: admin设置房产3开始收益阶段..."

# 检查房产3是否达到最小募集目标
PROPERTY3_RAISED_CLEAN=$(echo $PROPERTY3_RAISED | sed 's/\[.*\]//' | tr -d ' ')
PROPERTY3_MIN_RAISING_CLEAN=$(echo $PROPERTY3_MIN_RAISING | sed 's/\[.*\]//' | tr -d ' ')

if [ $PROPERTY3_RAISED_CLEAN -ge $PROPERTY3_MIN_RAISING_CLEAN ]; then
    echo "   房产3已达到最小募集目标"

    # 检查当前阶段
    CURRENT_PHASE=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")
    echo "   当前阶段: $CURRENT_PHASE"

    # 检查是否还在募资阶段
    if [ $CURRENT_PHASE -eq 0 ]; then
        echo "   房产3处于募资阶段，正在通过SeriesFactory开始收益阶段..."

        # 通过SeriesFactory调用startSeriesNow()函数
        cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
            $SERIES_FACTORY_ADDR "startSeriesNow(uint256)" $PROPERTY3_ID \
            || { echo "❌ 通过SeriesFactory开始房产3失败"; exit 1; }

        echo "✅ 房产3通过SeriesFactory开始收益阶段成功"

        # 验证状态变化
        NEW_PHASE=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")
        echo "   新阶段: $NEW_PHASE"

    else
        echo "   房产3不处于募资阶段 (当前阶段: $CURRENT_PHASE)"
    fi
else
    echo "   ❌ 房产3未达到最小募集目标"
    echo "   无法设置开始时间"
fi

# 步骤7: admin 通过seriesFactory 给 property3 调用 receiveProfit 1000 USDC
echo "💸 步骤7: admin为房产3调用receiveProfit 1000 USDC..."

PROFIT_AMOUNT=$((1000 * 1000000))  # 1000 USDC (6 decimals)

# 先授权USDC给SeriesFactory
echo "   正在为SeriesFactory授权USDC..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $USDC_ADDR "approve(address,uint256)" $SERIES_FACTORY_ADDR $PROFIT_AMOUNT \
    || { echo "❌ 为SeriesFactory授权USDC失败"; exit 1; }

# 调用receiveProfit
echo "   正在调用receiveProfit..."
cast send --rpc-url $RPC_URL --account myMetaMaskAcc --password '' \
    $SERIES_FACTORY_ADDR \
    "receiveProfit(uint256,uint256)" \
    $PROPERTY3_ID $PROFIT_AMOUNT \
    || { echo "❌ 调用receiveProfit失败"; exit 1; }

echo "✅ 房产3收益接收成功"

# 验证收益分配
echo "🔍 验证收益分配..."
# 这里可以添加验证逻辑，检查代币持有者是否收到了相应的收益代币

# 最终状态总结
echo "🔍 最终状态总结..."

echo "📊 所有房产状态:"
echo "   房产1 (测试公寓): $SERIES1_ADDR"
echo "   房产2 (豪华别墅): $SERIES2_ADDR"
echo "   房产3 (温馨工作室): $SERIES3_ADDR"
echo ""

echo "📈 房产3最终状态:"
PROPERTY3_FINAL_RAISED=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "totalFundRaised()(uint256)")
PROPERTY3_FINAL_PHASE=$(cast call --rpc-url $RPC_URL $SERIES3_ADDR "getPhase()(uint8)")

echo "   总募集金额: $(echo $PROPERTY3_FINAL_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   当前阶段: $PROPERTY3_FINAL_PHASE"
echo "   收益接收: 1000 USDC"
echo ""

# 保存关键信息到环境变量文件
echo "# Sepolia Case 2 Test Results - $(date)" >> sepolia.env
echo "SEPOLIA_CASE2_PROPERTY1_ID=$PROPERTY1_ID" >> sepolia.env
echo "SEPOLIA_CASE2_PROPERTY2_ID=$PROPERTY2_ID" >> sepolia.env
echo "SEPOLIA_CASE2_PROPERTY3_ID=$PROPERTY3_ID" >> sepolia.env
echo "SEPOLIA_CASE2_SERIES1_ADDR=$SERIES1_ADDR" >> sepolia.env
echo "SEPOLIA_CASE2_SERIES2_ADDR=$SERIES2_ADDR" >> sepolia.env
echo "SEPOLIA_CASE2_SERIES3_ADDR=$SERIES3_ADDR" >> sepolia.env
echo "SEPOLIA_CASE2_TOKEN1_SYMBOL=$TOKEN1_SYMBOL" >> sepolia.env
echo "SEPOLIA_CASE2_TOKEN2_SYMBOL=$TOKEN2_SYMBOL" >> sepolia.env
echo "SEPOLIA_CASE2_TOKEN3_SYMBOL=$TOKEN3_SYMBOL" >> sepolia.env

echo "✅ Sepolia案例2设置和测试完成！"
echo "=================================================="
echo "🎯 总结:"
echo "   - 3套房产已添加到PropertyOracle"
echo "   - 3个RentToken系列已创建"
echo "   - 所有系列Oracle已设置"
echo "   - admin认购房产3 31000 USDC成功"
echo "   - 房产3开始时间已设置 (如果条件满足)"
echo "   - 房产3收益接收1000 USDC成功"
echo ""
echo "🚀 准备进行进一步测试！"
echo "💡 下一步: 监控合约阶段并测试收益分配"
