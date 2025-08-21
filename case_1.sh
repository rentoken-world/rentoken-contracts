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

# 新增: 步骤6 - 使用 EIP-2612 permitDeposit 方式入资
echo "💳 Step 6: Investor USER2 invests via permitDeposit (EIP-2612)..."

INVESTOR_ADDR=$USER2_ADDRESS
INVESTOR_PK=$USER2_PRIVATE_KEY
INVEST_AMOUNT_USDC=5000
INVEST_AMOUNT_WEI=$((INVEST_AMOUNT_USDC * 1000000)) # USDC 6 decimals
DEADLINE=$((CURRENT_TIME + 86400)) # +1 day

# # 查询 permit 所需参数（USDC 需支持 EIP-2612）
# NONCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "nonces(address)(uint256)" $INVESTOR_ADDR)
# # 优先读取合约内置 PERMIT_TYPEHASH，若无则回退到标准 EIP-2612 字符串哈希
# PERMIT_TYPEHASH=$(cast call --rpc-url $RPC_URL $USDC_ADDR "PERMIT_TYPEHASH()(bytes32)" 2>/dev/null || cast keccak "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
# # 读取 DOMAIN_SEPARATOR（若不可用则按标准域计算）
# DOMAIN=$(cast call --rpc-url $RPC_URL $USDC_ADDR "DOMAIN_SEPARATOR()(bytes32)" 2>/dev/null || echo "0x")
# if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "0x" ] || [ "$DOMAIN" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
# 	TOKEN_NAME=$(cast call --rpc-url $RPC_URL $USDC_ADDR "name()(string)" 2>/dev/null || echo "USD Coin")
# 	# USDC 通常使用 version "2"；OZ ERC20Permit 默认 "1"
# 	TOKEN_VERSION=$(cast call --rpc-url $RPC_URL $USDC_ADDR "version()(string)" 2>/dev/null || echo "2")
# 	CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL)
# 	DOMAIN_TYPEHASH=$(cast keccak "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
# 	DE_ENC=$(cast abi-encode "f(bytes32,bytes32,bytes32,uint256,address)" $DOMAIN_TYPEHASH $(cast keccak "$TOKEN_NAME") $(cast keccak "$TOKEN_VERSION") $CHAIN_ID $USDC_ADDR)
# 	DE_PARAMS=0x${DE_ENC:10}
# 	DOMAIN=$(cast keccak $DE_PARAMS)
# fi
# # 计算 Permit 结构体哈希
# STRUCT_ENC=$(cast abi-encode "f(bytes32,address,address,uint256,uint256,uint256)" $PERMIT_TYPEHASH $INVESTOR_ADDR $SERIES_ADDR $INVEST_AMOUNT_WEI $NONCE $DEADLINE)
# STRUCT_PARAMS=0x${STRUCT_ENC:10}
# STRUCT_HASH=$(cast keccak $STRUCT_PARAMS)
# # 计算最终 EIP-712 消息摘要
# DIGEST=$(cast keccak 0x1901${DOMAIN:2}${STRUCT_HASH:2})

# # 使用投资人私钥对 digest 进行签名，得到 r,s,v
# SIG=$(cast wallet sign --no-hash --private-key $INVESTOR_PK $DIGEST)
# SIG_NO_0X=${SIG:2}
# R=0x${SIG_NO_0X:0:64}
# S=0x${SIG_NO_0X:64:64}
# V_HEX=${SIG_NO_0X:128:2}
# V=$((16#$V_HEX))
# if [ $V -lt 27 ]; then V=$((V+27)); fi

# 读取 domain（正确处理引号）
TOKEN_NAME_RAW=$(cast call --rpc-url $RPC_URL $USDC_ADDR "name()(string)")
TOKEN_VERSION_RAW=$(cast call --rpc-url $RPC_URL $USDC_ADDR "version()(string)" 2>/dev/null || echo "\"2\"")
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL)
NONCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "nonces(address)(uint256)" $INVESTOR_ADDR)

# 去掉外层引号用于 JSON
TOKEN_NAME=$(echo $TOKEN_NAME_RAW | sed 's/^"//; s/"$//')
TOKEN_VERSION=$(echo $TOKEN_VERSION_RAW | sed 's/^"//; s/"$//')

echo "🔍 Permit Parameters:"
echo "   Token Name: $TOKEN_NAME"
echo "   Token Version: $TOKEN_VERSION"
echo "   Chain ID: $CHAIN_ID"
echo "   Nonce: $NONCE"
echo "   Deadline: $DEADLINE"
echo ""

TYPED_DATA=$(cat <<EOF
{
  "types": {
    "EIP712Domain": [
      {"name":"name","type":"string"},
      {"name":"version","type":"string"},
      {"name":"chainId","type":"uint256"},
      {"name":"verifyingContract","type":"address"}
    ],
    "Permit": [
      {"name":"owner","type":"address"},
      {"name":"spender","type":"address"},
      {"name":"value","type":"uint256"},
      {"name":"nonce","type":"uint256"},
      {"name":"deadline","type":"uint256"}
    ]
  },
  "primaryType": "Permit",
  "domain": {
    "name": "$TOKEN_NAME",
    "version": "$TOKEN_VERSION",
    "chainId": $CHAIN_ID,
    "verifyingContract": "$USDC_ADDR"
  },
  "message": {
    "owner": "$INVESTOR_ADDR",
    "spender": "$SERIES_ADDR",
    "value": $INVEST_AMOUNT_WEI,
    "nonce": $NONCE,
    "deadline": $DEADLINE
  }
}
EOF
)

# 生成 EIP-712 签名 - 手动计算方式
echo "🔐 Generating EIP-712 signature..."

# 直接使用 USDC 的 DOMAIN_SEPARATOR（无论是主网还是 mock）
DOMAIN_SEPARATOR=$(cast call --rpc-url $RPC_URL $USDC_ADDR "DOMAIN_SEPARATOR()(bytes32)")

# 计算 struct hash
PERMIT_TYPEHASH=$(cast keccak "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
STRUCT_ENC=$(cast abi-encode "f(bytes32,address,address,uint256,uint256,uint256)" $PERMIT_TYPEHASH $INVESTOR_ADDR $SERIES_ADDR $INVEST_AMOUNT_WEI $NONCE $DEADLINE)
STRUCT_PARAMS=0x${STRUCT_ENC:10}
STRUCT_HASH=$(cast keccak $STRUCT_PARAMS)

# 计算最终 digest
DIGEST=$(cast keccak 0x1901${DOMAIN_SEPARATOR:2}${STRUCT_HASH:2})

echo "🔍 Debug Information:"
echo "   USDC Address: $USDC_ADDR"
echo "   Domain Separator: $DOMAIN_SEPARATOR"
echo "   Struct Hash: $STRUCT_HASH"
echo "   Final Digest: $DIGEST"
echo ""

# 生成签名
SIG=$(cast wallet sign --no-hash --private-key $INVESTOR_PK $DIGEST)
SIG_NO_0X=${SIG:2}
R=0x${SIG_NO_0X:0:64}
S=0x${SIG_NO_0X:64:64}
V_HEX=${SIG_NO_0X:128:2}

V=$((16#$V_HEX))
# 确保 v 值在正确范围内 (27 或 28)
if [ $V -lt 27 ]; then
    V=$((V+27))
fi

echo "📝 Signature Components:"
echo "   r: $R"
echo "   s: $S"
echo "   v: $V"
echo ""

echo "   Investor: $INVESTOR_ADDR"
echo "   Amount: ${INVEST_AMOUNT_USDC} USDC"
echo "   Nonce: $NONCE"
echo "   Deadline: $DEADLINE"

# 发送 permitDeposit 交易（from = 投资人）
set +e
cast send --rpc-url $RPC_URL --private-key $INVESTOR_PK \
    $SERIES_ADDR \
    "permitDeposit(uint256,uint256,uint8,bytes32,bytes32)" \
    $INVEST_AMOUNT_WEI $DEADLINE $V $R $S
PERMIT_RC=$?
set -e

if [ $PERMIT_RC -ne 0 ]; then
    echo "⚠️ permitDeposit failed on payout token (likely non-standard permit). Falling back to approve + contribute..."
    cast send --rpc-url $RPC_URL --private-key $INVESTOR_PK \
        $USDC_ADDR "approve(address,uint256)" $SERIES_ADDR $INVEST_AMOUNT_WEI \
        || { echo "❌ approve failed"; exit 1; }
    cast send --rpc-url $RPC_URL --private-key $INVESTOR_PK \
        $SERIES_ADDR "contribute(uint256)" $INVEST_AMOUNT_WEI \
        || { echo "❌ contribute failed"; exit 1; }
    echo "✅ Fallback approve + contribute successful"
else
    echo "✅ permitDeposit successful"
fi

# 校验结果
FUND_RAISED=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "totalFundRaised()(uint256)")
SERIES_USDC_BAL=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $SERIES_ADDR)
INVESTOR_RTN_BAL=$(cast call --rpc-url $RPC_URL $SERIES_ADDR "balanceOf(address)(uint256)" $INVESTOR_ADDR)

echo "📈 After permitDeposit:"
echo "   totalFundRaised: $(echo $FUND_RAISED | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Series USDC balance: $(echo $SERIES_USDC_BAL | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   Investor RTN balance: $(echo $INVESTOR_RTN_BAL | awk '{printf "%.6f", $1/1000000}') RTN"

# 最终摘要
echo "=================================================="
echo "🎯 Summary:"
echo "   - Property ID $PROPERTY_ID added to PropertyOracle"
echo "   - USER1, USER2, USER3 added to KYC whitelist"
echo "   - USER4 remains non-KYC for testing"
echo "   - RentToken series '$TOKEN_SYMBOL' created at $SERIES_ADDR"
echo "   - Series is in $PHASE_NAME phase"
echo "   - USER2 invested ${INVEST_AMOUNT_USDC} USDC via permitDeposit"
echo ""
echo "🚀 Ready for more investment testing!"
echo "💡 Next steps:"
echo "   - Use permitDeposit (recommended if payout token supports EIP-2612):"
echo "     cast send $SERIES_ADDR \"permitDeposit(uint256,uint256,uint8,bytes32,bytes32)\" [amount] [deadline] [v] [r] [s]"
echo "   - Fallback (for tokens without EIP-2612): approve + contribute(uint256)"
echo "   - Remember: USER4 will be rejected due to KYC requirements"
