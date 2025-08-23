#!/bin/bash
# Test Simple with CLI - 使用 RWA CLI 工具重写的 test_simple.sh
# 简化版本的测试脚本，演示完整的 RentToken RWA 系统流程

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

echo "🚀 Starting Simplified RenToken RWA System Testing (CLI Version)..."
echo "=================================================="

# 检查 CLI 工具是否存在
if [ ! -f "bin/rwa" ]; then
    echo "❌ RWA CLI tool not found at bin/rwa"
    echo "Please ensure the CLI tool is created and executable"
    exit 1
fi

# 检查环境变量文件
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please run init-local.sh first."
    exit 1
fi

# 加载环境变量
source .env

echo "🔑 Test Addresses (from CLI):"
echo "ADMIN=$(bin/rwa addr:show ADMIN)"
echo "USER1=$(bin/rwa addr:show USER1)"  
echo "USER2=$(bin/rwa addr:show USER2)"
echo ""

echo "⏰ Network Information (from CLI):"
echo "Chain ID: $(bin/rwa block:chainid)"
echo "Current Block Time: $(bin/rwa block:time)"
echo ""

# 验证合约地址是否已部署
echo "🔍 Verifying contract deployments..."
if [[ -z "$KYC_ORACLE_ADDR" || -z "$PROPERTY_ORACLE_ADDR" || -z "$SERIES_FACTORY_ADDR" ]]; then
    echo "❌ Contract addresses not found. Please run init-local.sh first."
    exit 1
fi

echo "✅ Contracts deployed:"
echo "   KYC Oracle: $KYC_ORACLE_ADDR"
echo "   Property Oracle: $PROPERTY_ORACLE_ADDR"
echo "   Series Factory: $SERIES_FACTORY_ADDR"
echo "   RentToken Impl: $RENT_TOKEN_IMPL_ADDR"
echo "   Sanction Oracle: $SANCTION_ORACLE_ADDR"
echo ""

# 测试用例1: 添加测试房产
echo "📋 Test Case 1: 添加测试房产 (Using CLI)"
echo "----------------------------------------"

PROPERTY_ID=1
VALUATION=1000000000000  # 1M USDC
MIN_RAISING=1   # Set to 1 for testing  
MAX_RAISING=5000000000   # 5000 USDC
DOC_HASH=0x0000000000000000000000000000000000000000000000000000000000000000
OFFCHAIN_URL="http://example.com"

echo "🏠 Adding test property to PropertyOracle using CLI..."

bin/rwa property:add \
    --id "$PROPERTY_ID" \
    --payout "$USDC_ADDR" \
    --valuation "$VALUATION" \
    --min "$MIN_RAISING" \
    --max "$MAX_RAISING" \
    --start "+3600" \
    --end "+31536000" \
    --landlord "ADMIN" \
    --doc-hash "$DOC_HASH" \
    --url "$OFFCHAIN_URL" \
    --yes

echo "✅ Test property added using CLI"
echo ""

# 测试用例2: 创建 RentToken Series
echo "📋 Test Case 2: 创建 RentToken Series (Using CLI)"
echo "----------------------------------------"

TOKEN_NAME="RenToken Test"
TOKEN_SYMBOL="RTTEST"

echo "🔧 Creating series using CLI..."
bin/rwa series:create "$PROPERTY_ID" "$TOKEN_NAME" "$TOKEN_SYMBOL" --yes

SERIES_ADDRESS=$(bin/rwa series:addr "$PROPERTY_ID")
echo "✅ Series created at: $SERIES_ADDRESS"

# 设置 Oracles for the series
echo "🔧 Setting oracles for series using CLI..."
bin/rwa series:oracles:set "$PROPERTY_ID" "$KYC_ORACLE_ADDR" "$SANCTION_ORACLE_ADDR" --yes

echo ""

# 测试用例3: 验证初始状态
echo "📋 Test Case 3: 验证初始状态 (Using CLI)"
echo "----------------------------------------"

# 验证系列基本信息
echo "🔍 Checking series information using CLI..."
bin/rwa series:info "$PROPERTY_ID"

echo ""

# 测试用例4: 设置用户权限
echo "📋 Test Case 4: 设置用户权限 (Using CLI)"
echo "----------------------------------------"

# 将用户添加到 KYC 白名单
echo "🔐 Adding users to KYC whitelist using CLI..."
bin/rwa kyc:add USER1 --yes
bin/rwa kyc:add USER2 --yes

# 验证用户 KYC 状态
echo "🔍 Verifying user KYC status using CLI..."
USER1_KYC=$(bin/rwa kyc:check USER1)
USER2_KYC=$(bin/rwa kyc:check USER2)
echo "User1 KYC status: $USER1_KYC"
echo "User2 KYC status: $USER2_KYC"

echo ""

# 测试用例5: 铸造代币 (Contribute)
echo "📋 Test Case 5: 铸造代币 (Using CLI)"
echo "----------------------------------------"

# 用户1 投资 100 USDC
echo "💰 User1 contributing 100 USDC using CLI..."

# 首先授权
bin/rwa erc20:approve "$USDC_ADDR" "$SERIES_ADDRESS" 100000000 --from USER1 --yes

# 然后贡献
bin/rwa series:contribute "$PROPERTY_ID" 100000000 --from USER1 --yes

# 检查用户1的代币余额
USER1_BALANCE=$(bin/rwa erc20:balance "$SERIES_ADDRESS" USER1)
echo "✅ User1 RTN balance: $USER1_BALANCE"

# 检查总供应量和阶段
echo "📊 Series status after contribution:"
bin/rwa series:info "$PROPERTY_ID"

echo ""

echo "⏱ Advancing time to start accrual phase using CLI..."
bin/rwa time:increase 3601
bin/rwa mine
CURRENT_PHASE=$(bin/rwa series:phase "$PROPERTY_ID")
echo "Current Phase after time advance: $CURRENT_PHASE"

# 测试用例6: 用户转账
echo "📋 Test Case 6: 用户转账 (Using CLI)"
echo "----------------------------------------"

# 用户1 转账 50 RTN 给用户2
echo "💸 User1 transferring 50 RTN to User2 using CLI..."
bin/rwa series:transfer "$PROPERTY_ID" USER2 50000000 --from USER1 --yes

# 检查转账后的余额
USER1_BALANCE_AFTER=$(bin/rwa erc20:balance "$SERIES_ADDRESS" USER1)
USER2_BALANCE=$(bin/rwa erc20:balance "$SERIES_ADDRESS" USER2)

echo "✅ User1 balance after transfer: $USER1_BALANCE_AFTER"
echo "✅ User2 balance: $USER2_BALANCE"

echo ""

# 测试用例7: 收益分配
echo "📋 Test Case 7: 收益分配 (Using CLI)"
echo "----------------------------------------"

# 确保阶段是 AccrualStarted
CURRENT_PHASE_AFTER=$(bin/rwa series:phase "$PROPERTY_ID")
echo "Current Phase after contribution: $CURRENT_PHASE_AFTER"  # Should be 1

# 授权并调用 receiveProfit
echo "💰 Distributing profit using CLI..."
bin/rwa erc20:approve "$USDC_ADDR" "$SERIES_FACTORY_ADDR" 100000000 --from ADMIN --yes
bin/rwa factory:profit:receive "$PROPERTY_ID" 100000000 --yes

echo "✅ Profit distributed using CLI"

# 用户 claim 收益 (简化, 检查 claimable)
USER1_CLAIMABLE=$(bin/rwa series:claimable "$PROPERTY_ID" USER1)
USER2_CLAIMABLE=$(bin/rwa series:claimable "$PROPERTY_ID" USER2)
echo "User1 claimable: $USER1_CLAIMABLE"
echo "User2 claimable: $USER2_CLAIMABLE"

echo ""

# 最终验证
echo "🎯 Final System Verification (CLI Version)"
echo "============================"
echo "Contract Addresses:"
echo "   KYC Oracle: $KYC_ORACLE_ADDR"
echo "   Sanction Oracle: $SANCTION_ORACLE_ADDR"
echo "   Property Oracle: $PROPERTY_ORACLE_ADDR"
echo "   Series Factory: $SERIES_FACTORY_ADDR"
echo "   RentToken Series: $SERIES_ADDRESS"
echo ""

echo "Token Balances (using CLI):"
echo "   User1 RTN Balance: $USER1_BALANCE_AFTER"
echo "   User2 RTN Balance: $USER2_BALANCE"
echo ""

echo "Claimable Profits (using CLI):"
echo "   User1 Claimable: $USER1_CLAIMABLE"
echo "   User2 Claimable: $USER2_CLAIMABLE"
echo ""

echo "System Status:"
FINAL_PHASE=$(bin/rwa series:phase "$PROPERTY_ID")
echo "   Current Phase: $FINAL_PHASE"

# 显示 USDC 余额
echo ""
echo "💰 Final USDC Balances:"
ADMIN_USDC=$(bin/rwa erc20:balance "$USDC_ADDR" ADMIN)
USER1_USDC=$(bin/rwa erc20:balance "$USDC_ADDR" USER1) 
USER2_USDC=$(bin/rwa erc20:balance "$USDC_ADDR" USER2)

echo "   ADMIN USDC: $(echo $ADMIN_USDC | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER1 USDC: $(echo $USER1_USDC | awk '{printf "%.6f", $1/1000000}') USDC"
echo "   USER2 USDC: $(echo $USER2_USDC | awk '{printf "%.6f", $1/1000000}') USDC"

echo ""
echo "🎉 All CLI test cases completed successfully!"
echo "=========================================="
echo ""
echo "🔧 Useful CLI Commands for Further Testing:"
echo "   Check any balance: bin/rwa erc20:balance <TOKEN> <ADDR>"
echo "   Check KYC status: bin/rwa kyc:check <ADDR>"
echo "   Series info: bin/rwa series:info $PROPERTY_ID"
echo "   Add to KYC: bin/rwa kyc:add <ADDR> --yes"
echo "   Time operations: bin/rwa time:increase <SECONDS> && bin/rwa mine"
