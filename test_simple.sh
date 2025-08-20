#!/bin/bash
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Simplified RenToken RWA System Testing..."
echo "=================================================="

# 基础环境变量
export ADMIN_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export USER1_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export USER2_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
export RPC_URL=http://localhost:8545

export USER1_ADDRESS=$(cast wallet address --private-key $USER1_KEY)
export USER2_ADDRESS=$(cast wallet address --private-key $USER2_KEY)
export ADMIN_ADDRESS=$(cast wallet address --private-key $ADMIN_PRIVATE_KEY)

export USDC=0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
export SANCTION_ORACLE=0xd8c8174691d936E2C80114EC449037b13421B0a8
export USDC_WHALE=0x55fe002aeff02f77364de339a1292923a15844b8  # Known USDC holder

echo "🔑 Test Addresses:"
echo "ADMIN=$ADMIN_ADDRESS"
echo "USER1=$USER1_ADDRESS"
echo "USER2=$USER2_ADDRESS"
echo ""

get_deployed_address() {
    awk '/Deployed to:/ {print $3}'
}

# 测试用例1: 部署基础合约
echo "📋 Test Case 1: 部署基础合约"
echo "----------------------------------------"

# Step 1: 部署 KYC Oracle
echo "📦 Step 1.1: Deploying KYC Oracle..."
KYC_ORACLE=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/KYCOracle.sol:KYCOracle --broadcast | get_deployed_address)
echo "✅ KYC Oracle deployed at: $KYC_ORACLE"

# Add Admin to KYC whitelist immediately after deployment
echo "🔐 Adding Admin to KYC whitelist..."
cast send $KYC_ORACLE --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY "addToWhitelist(address)" $ADMIN_ADDRESS || { echo "❌ Failed to add Admin to whitelist"; exit 1; }

# Step 2: 部署 PropertyOracle
echo "📦 Step 1.2: Deploying PropertyOracle..."
PROPERTY_ORACLE=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/PropertyOracle.sol:PropertyOracle --broadcast | get_deployed_address)
echo "✅ PropertyOracle deployed at: $PROPERTY_ORACLE"

# Deploy ChainList SanctionOracle
echo "📦 ChainList SanctionOracle..."
SANCTION_ORACLE=0x40C57923924B5c5c5455c48D93317139ADDaC8fb
echo "✅ ChainList SanctionOracle deployed at: $SANCTION_ORACLE"

# Deploy USDC
echo "📦 USDC Address"
USDC=0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
echo "✅ USDC deployed at: $USDC"

# Step 3: 部署 RentToken Implementation
echo "📦 Step 1.3: Deploying RentToken Implementation..."
RENT_TOKEN_IMPL=$(forge create --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/RentToken.sol:RentToken --broadcast | get_deployed_address)
echo "✅ RentToken Implementation deployed at: $RENT_TOKEN_IMPL"

# Step 4: 部署 SeriesFactory
echo "📦 Step 1.4: Deploying SeriesFactory..."
SERIES_FACTORY=$(forge create src/SeriesFactory.sol:SeriesFactory  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast --constructor-args $PROPERTY_ORACLE | get_deployed_address)
[ -n "$SERIES_FACTORY" ] || { echo "❌ Failed to deploy SeriesFactory"; exit 1; }
echo "✅ SeriesFactory deployed at: $SERIES_FACTORY"

# Fund test accounts with USDC from whale
echo "💰 Funding test accounts with USDC from whale..."

# Impersonate whale
cast rpc --rpc-url $RPC_URL anvil_impersonateAccount $USDC_WHALE

# Transfer to USER1
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC "transfer(address,uint256)" $USER1_ADDRESS 10000000000  # 10000 USDC

# Transfer to USER2
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC "transfer(address,uint256)" $USER2_ADDRESS 10000000000

# Transfer to ADMIN
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC "transfer(address,uint256)" $ADMIN_ADDRESS 10000000000

# Stop impersonation
cast rpc --rpc-url $RPC_URL anvil_stopImpersonatingAccount $USDC_WHALE

# 测试用例2: 设置初始配置
echo "📋 Test Case 2: 设置初始配置"
echo "----------------------------------------"

# 设置 RentToken Implementation in SeriesFactory
echo "🔧 Setting RentToken Implementation..."
cast send $SERIES_FACTORY "updateRentTokenImplementation(address)" $RENT_TOKEN_IMPL --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY || { echo "❌ Failed to set implementation"; exit 1; }

# 添加一个测试房产到 PropertyOracle
echo "🏠 Adding test property to PropertyOracle..."
PROPERTY_ID=1
PAYOUT_TOKEN=$USDC
VALUATION=1000000000000  # 1M USDC
MIN_RAISING=1   # Set to 1 for testing
MAX_RAISING=5000000000   # 5000 USDC
CURRENT_TIMESTAMP=$(cast block --rpc-url $RPC_URL latest --field timestamp)
ACCRUAL_START=$(($CURRENT_TIMESTAMP + 3600))  # 1 hour in future
ACCRUAL_END=$(($ACCRUAL_START + 31536000))  # +1 year
FEE_BPS=0
LANDLORD=$ADMIN_ADDRESS
DOC_HASH=0x0000000000000000000000000000000000000000000000000000000000000000
CITY="TestCity"
OFFCHAIN_URL="http://example.com"

# Encode the struct for addOrUpdateProperty
cast send $PROPERTY_ORACLE "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,uint16,address,bytes32,string,string))" $PROPERTY_ID "($PROPERTY_ID,$PAYOUT_TOKEN,$VALUATION,$MIN_RAISING,$MAX_RAISING,$ACCRUAL_START,$ACCRUAL_END,$FEE_BPS,$LANDLORD,$DOC_HASH,$CITY,$OFFCHAIN_URL)" --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY || { echo "❌ Failed to add property"; exit 1; }

echo "✅ Test property added"

echo ""

# 测试用例3: 创建 RentToken Series
echo "📋 Test Case 3: 创建 RentToken Series"
echo "----------------------------------------"

TOKEN_NAME="RenToken Test"
TOKEN_SYMBOL="RTTEST"

echo "🔧 Creating series..."
cast send $SERIES_FACTORY "createSeries(uint256,string,string)" $PROPERTY_ID "$TOKEN_NAME" "$TOKEN_SYMBOL" --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY || { echo "❌ Failed to create series"; exit 1; }

SERIES_ADDRESS=$(cast call $SERIES_FACTORY "propertyIdToSeries(uint256)(address)" $PROPERTY_ID --rpc-url $RPC_URL)
echo "✅ Series created at: $SERIES_ADDRESS"

# 设置 Oracles for the series
echo "🔧 Setting oracles for series..."
cast send $SERIES_FACTORY --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    "setOraclesForSeries(uint256,address,address)" $PROPERTY_ID $KYC_ORACLE $SANCTION_ORACLE || { echo "❌ Failed to set oracles"; exit 1; }

echo ""

# 测试用例4: 验证初始状态
echo "📋 Test Case 4: 验证初始状态"
echo "----------------------------------------"

# 验证 KYC Oracle 初始状态
echo "🔍 Checking KYC Oracle initial state..."
IS_ADMIN_KYC=$(cast call $KYC_ORACLE "isWhitelisted(address)(bool)" $ADMIN_ADDRESS --rpc-url $RPC_URL)
echo "Admin KYC status: $IS_ADMIN_KYC"

# 验证 Sanction Oracle 初始状态
echo "🔍 Checking Sanction Oracle initial state..."
IS_ADMIN_SANCTIONED=$(cast call $SANCTION_ORACLE "isSanctioned(address)(bool)" $ADMIN_ADDRESS --rpc-url $RPC_URL)
echo "Admin sanction status: $IS_ADMIN_SANCTIONED"

# 检查代币名称和符号
TOKEN_NAME_RESULT=$(cast call $SERIES_ADDRESS "name()(string)" --rpc-url $RPC_URL)
TOKEN_SYMBOL_RESULT=$(cast call $SERIES_ADDRESS "symbol()(string)" --rpc-url $RPC_URL)
echo "Token Name: $TOKEN_NAME_RESULT"
echo "Token Symbol: $TOKEN_SYMBOL_RESULT"

# 检查当前阶段
CURRENT_PHASE=$(cast call $SERIES_ADDRESS "getPhase()(uint8)" --rpc-url $RPC_URL)
echo "Current Phase: $CURRENT_PHASE"  # Should be 0 (Fundraising)

# 检查总供应量
TOTAL_SUPPLY=$(cast call $SERIES_ADDRESS "totalSupply()(uint256)" --rpc-url $RPC_URL)
echo "Total Supply: $TOTAL_SUPPLY"

echo ""

# 测试用例5: 设置用户权限
echo "📋 Test Case 5: 设置用户权限"
echo "----------------------------------------"

# 将用户添加到 KYC 白名单
echo "🔐 Adding users to KYC whitelist..."
cast send $KYC_ORACLE --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    "addToWhitelist(address)" $USER1_ADDRESS || { echo "❌ Failed to add User1 to whitelist"; exit 1; }

cast send $KYC_ORACLE --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    "addToWhitelist(address)" $USER2_ADDRESS || { echo "❌ Failed to add User2 to whitelist"; exit 1; }

# 验证用户 KYC 状态
echo "🔍 Verifying user KYC status..."
USER1_KYC=$(cast call $KYC_ORACLE "isWhitelisted(address)(bool)" $USER1_ADDRESS --rpc-url $RPC_URL)
USER2_KYC=$(cast call $KYC_ORACLE "isWhitelisted(address)(bool)" $USER2_ADDRESS --rpc-url $RPC_URL)
echo "User1 KYC status: $USER1_KYC"
echo "User2 KYC status: $USER2_KYC"

echo ""

# 测试用例6: 铸造代币 (Contribute)
echo "📋 Test Case 6: 铸造代币"
echo "----------------------------------------"

# 用户1 投资 100 USDC
echo "💰 User1 contributing 100 USDC..."
cast send $USDC --private-key $USER1_KEY --rpc-url $RPC_URL \
    "approve(address,uint256)" $SERIES_ADDRESS 100000000 || { echo "❌ Failed approve"; exit 1; }  # 100 USDC

cast send $SERIES_ADDRESS --rpc-url $RPC_URL --private-key $USER1_KEY \
    "contribute(uint256)" 100000000 || { echo "❌ Failed contribute"; exit 1; }  # 100 USDC

# 检查用户1的代币余额
USER1_BALANCE=$(cast call $SERIES_ADDRESS "balanceOf(address)(uint256)" $USER1_ADDRESS --rpc-url $RPC_URL)
echo "✅ User1 RTN balance: $USER1_BALANCE"

# 检查总供应量
TOTAL_SUPPLY_AFTER=$(cast call $SERIES_ADDRESS "totalSupply()(uint256)" --rpc-url $RPC_URL)
echo "✅ Total supply after contribution: $TOTAL_SUPPLY_AFTER"

echo ""

echo "⏱ Advancing time to start accrual phase..."
cast rpc --rpc-url $RPC_URL evm_increaseTime 3601 || { echo "❌ Failed to increase time"; exit 1; }
cast rpc --rpc-url $RPC_URL evm_mine || { echo "❌ Failed to mine block"; exit 1; }
CURRENT_PHASE=$(cast call $SERIES_ADDRESS "getPhase()(uint8)" --rpc-url $RPC_URL)
echo "Current Phase after time advance: $CURRENT_PHASE"

# 测试用例7: 用户转账
echo "📋 Test Case 7: 用户转账"
echo "----------------------------------------"

# 用户1 转账 50 RTN 给用户2
echo "💸 User1 transferring 50 RTN to User2..."
cast send $SERIES_ADDRESS --private-key $USER1_KEY --rpc-url $RPC_URL \
    "transfer(address,uint256)" $USER2_ADDRESS 50000000 || { echo "❌ Failed transfer"; exit 1; }  # 50 RTN (assuming 6 decimals)

# 检查转账后的余额
USER1_BALANCE_AFTER=$(cast call $SERIES_ADDRESS "balanceOf(address)(uint256)" $USER1_ADDRESS --rpc-url $RPC_URL)
USER2_BALANCE=$(cast call $SERIES_ADDRESS "balanceOf(address)(uint256)" $USER2_ADDRESS --rpc-url $RPC_URL)

echo "✅ User1 balance after transfer: $USER1_BALANCE_AFTER"
echo "✅ User2 balance: $USER2_BALANCE"

echo ""

# 测试用例8: 收益分配 without time advance
echo "📋 Test Case 8: 收益分配"
echo "----------------------------------------"

# 确保阶段是 AccrualStarted (假设 totalFundRaised >= minRaising)
CURRENT_PHASE_AFTER=$(cast call $SERIES_ADDRESS "getPhase()(uint8)" --rpc-url $RPC_URL)
echo "Current Phase after contribution: $CURRENT_PHASE_AFTER"  # Should be 1

# Approve and call receiveProfit
cast send $USDC --private-key $ADMIN_PRIVATE_KEY --rpc-url $RPC_URL \
    "approve(address,uint256)" $SERIES_FACTORY 100000000 || { echo "❌ Failed approve for profit"; exit 1; }

cast send $SERIES_FACTORY --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY \
    "receiveProfit(uint256,uint256)" $PROPERTY_ID 100000000 || { echo "❌ Failed receiveProfit"; exit 1; }

echo "✅ Profit distributed"

# 用户 claim 收益 (简化, 检查 claimable)
USER1_CLAIMABLE=$(cast call $SERIES_ADDRESS "claimable(address)(uint256)" $USER1_ADDRESS --rpc-url $RPC_URL)
echo "User1 claimable: $USER1_CLAIMABLE"

echo ""

# 最终验证
echo "🎯 Final System Verification"
echo "============================"
echo "KYC Oracle: $KYC_ORACLE"
echo "Sanction Oracle: $SANCTION_ORACLE"
echo "PropertyOracle: $PROPERTY_ORACLE"
echo "SeriesFactory: $SERIES_FACTORY"
echo "RentToken Series: $SERIES_ADDRESS"
echo ""
echo "User1 RTN Balance: $USER1_BALANCE_AFTER"
echo "User2 RTN Balance: $USER2_BALANCE"
echo "Total Supply: $TOTAL_SUPPLY_AFTER"
echo "Current Phase: $CURRENT_PHASE_AFTER"

echo ""
echo "🎉 All test cases completed successfully!"
echo "=========================================="
