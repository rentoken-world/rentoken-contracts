#!/bin/bash

# Sepolia 测试网部署脚本
# 部署合约到 Sepolia 测试网并设置环境

set -e

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Sepolia Testnet Deployment..."
echo "=================================================="

# 检查环境变量
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it first."
    exit 1
fi

# 加载环境变量
source .env

# 验证必要的环境变量
required_vars=(
    "RPC_URL" "ADMIN_PRIVATE_KEY"
    "CHAIN_ID" "NETWORK"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Missing required environment variable: $var"
        exit 1
    fi
done

echo "✅ Environment variables loaded"
echo "🌐 Network: $NETWORK"
echo "🔗 RPC URL: $RPC_URL"
echo "⛓️  Chain ID: $CHAIN_ID"
echo "👤 ADMIN: $(./bin/rwa addr:show ADMIN)"

# 检查账户余额
echo ""
echo "💰 Checking account balances..."
ADMIN_BALANCE=$(cast balance $(./bin/rwa addr:show ADMIN) --rpc-url $RPC_URL)
echo "ADMIN ETH Balance: $ADMIN_BALANCE wei"

# 转换为 ETH 单位显示
ADMIN_BALANCE_ETH=$(echo "scale=18; $ADMIN_BALANCE / 1000000000000000000" | bc -l 2>/dev/null || echo "0")
echo "ADMIN ETH Balance: $ADMIN_BALANCE_ETH ETH"

# 检查余额是否足够（至少 0.01 ETH）
MIN_BALANCE=10000000000000000  # 0.01 ETH in wei
if [ $ADMIN_BALANCE -lt $MIN_BALANCE ]; then
    echo ""
    echo "⚠️  Warning: ADMIN account balance is low ($ADMIN_BALANCE_ETH ETH)"
    echo "📝 You need testnet ETH from Sepolia faucet:"
    echo "   - https://sepoliafaucet.com/"
    echo "   - https://www.alchemy.com/faucets/ethereum-sepolia"
    echo "   - Address to fund: $(./bin/rwa addr:show ADMIN)"
    echo ""
    echo "⏱️  Continuing deployment (it may fail if balance is insufficient)..."
fi

echo ""
echo "📦 Starting contract deployment..."

# 部署 KYC Oracle
echo "🔐 Deploying KYC Oracle..."
KYC_ORACLE_ADDR=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    src/KYCOracle.sol:KYCOracle --broadcast --json | jq -r '.deployedTo')

if [ "$KYC_ORACLE_ADDR" = "null" ] || [ -z "$KYC_ORACLE_ADDR" ]; then
    echo "❌ Failed to deploy KYC Oracle"
    exit 1
fi

echo "✅ KYC Oracle deployed at: $KYC_ORACLE_ADDR"

# 部署 Property Oracle
echo "🏠 Deploying Property Oracle..."
PROPERTY_ORACLE_ADDR=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    src/PropertyOracle.sol:PropertyOracle --broadcast --json | jq -r '.deployedTo')

if [ "$PROPERTY_ORACLE_ADDR" = "null" ] || [ -z "$PROPERTY_ORACLE_ADDR" ]; then
    echo "❌ Failed to deploy Property Oracle"
    exit 1
fi

echo "✅ Property Oracle deployed at: $PROPERTY_ORACLE_ADDR"

# 部署 RentToken Implementation
echo "🪙 Deploying RentToken Implementation..."
RENT_TOKEN_IMPL_ADDR=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    src/RentToken.sol:RentToken --broadcast --json | jq -r '.deployedTo')

if [ "$RENT_TOKEN_IMPL_ADDR" = "null" ] || [ -z "$RENT_TOKEN_IMPL_ADDR" ]; then
    echo "❌ Failed to deploy RentToken Implementation"
    exit 1
fi

echo "✅ RentToken Implementation deployed at: $RENT_TOKEN_IMPL_ADDR"

# 部署 Series Factory
echo "🏭 Deploying Series Factory..."
SERIES_FACTORY_ADDR=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    src/SeriesFactory.sol:SeriesFactory \
    --constructor-args $PROPERTY_ORACLE_ADDR --broadcast --json | jq -r '.deployedTo')

if [ "$SERIES_FACTORY_ADDR" = "null" ] || [ -z "$SERIES_FACTORY_ADDR" ]; then
    echo "❌ Failed to deploy Series Factory"
    exit 1
fi

echo "✅ Series Factory deployed at: $SERIES_FACTORY_ADDR"

# 设置 RentToken Implementation in SeriesFactory
echo "⚙️ Setting RentToken Implementation in SeriesFactory..."
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    $SERIES_FACTORY_ADDR "updateRentTokenImplementation(address)" $RENT_TOKEN_IMPL_ADDR

echo "✅ RentToken Implementation set in SeriesFactory"

# 更新 .env 文件
echo ""
echo "📝 Updating .env file with deployed addresses..."

# 更新合约地址到 .env 文件
sed -i.bak "s/KYC_ORACLE_ADDR=.*/KYC_ORACLE_ADDR=$KYC_ORACLE_ADDR/" .env
sed -i.bak "s/PROPERTY_ORACLE_ADDR=.*/PROPERTY_ORACLE_ADDR=$PROPERTY_ORACLE_ADDR/" .env
sed -i.bak "s/SERIES_FACTORY_ADDR=.*/SERIES_FACTORY_ADDR=$SERIES_FACTORY_ADDR/" .env
sed -i.bak "s/RENT_TOKEN_IMPL_ADDR=.*/RENT_TOKEN_IMPL_ADDR=$RENT_TOKEN_IMPL_ADDR/" .env

# 清理备份文件
rm .env.bak

# 更新地址 JSON 文件
ADDRESSES_FILE="addresses/${NETWORK}.json"
cat > "$ADDRESSES_FILE" << EOF
{
  "KYCOracle": "$KYC_ORACLE_ADDR",
  "PropertyOracle": "$PROPERTY_ORACLE_ADDR",
  "SeriesFactory": "$SERIES_FACTORY_ADDR",
  "RentTokenImpl": "$RENT_TOKEN_IMPL_ADDR",
  "SanctionOracle": "$SANCTION_ORACLE_ADDR"
}
EOF

echo "✅ Address files updated"

echo ""
echo "🎯 Deployment Summary:"
echo "=================================================="
echo "Network: $NETWORK (Chain ID: $CHAIN_ID)"
echo "KYC Oracle:      $KYC_ORACLE_ADDR"
echo "Property Oracle: $PROPERTY_ORACLE_ADDR"
echo "Series Factory:  $SERIES_FACTORY_ADDR"
echo "RentToken Impl:  $RENT_TOKEN_IMPL_ADDR"
echo "Sanction Oracle: $SANCTION_ORACLE_ADDR"

echo ""
echo "🔧 CLI Integration Setup..."

# 验证 CLI 工具
if [[ -f "bin/rwa" ]]; then
    echo "🔍 Verifying CLI tool..."
    
    # 测试基本命令
    echo "   Testing addr:show command..."
    ./bin/rwa addr:show ADMIN >/dev/null 2>&1 && echo "   ✅ addr:show working" || echo "   ❌ addr:show failed"
    
    echo "   Testing block:chainid command..."
    ./bin/rwa block:chainid >/dev/null 2>&1 && echo "   ✅ block:chainid working" || echo "   ❌ block:chainid failed"
    
    echo "✅ CLI tool verified"
else
    echo "⚠️  CLI tool not found at bin/rwa"
fi

echo ""
echo "🎯 CLI Quick Start (Sepolia):"
echo "   Check ADMIN address:     ./bin/rwa addr:show ADMIN"
echo "   Check chain ID:          ./bin/rwa block:chainid"
echo "   Add user to KYC:         ./bin/rwa kyc:add USER1 --yes"
echo ""
echo "⚠️  Note: You may need testnet tokens (USDC, ETH) from faucets"
echo "📚 Full command list:      ./bin/rwa help"
echo "📖 Documentation:          docs/CLI.md"

echo ""
echo "✅ Sepolia deployment completed successfully!"
echo "=================================================="
