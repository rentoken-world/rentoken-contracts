#!/bin/bash

# 此脚本将合约部署到本地 Anvil 实例并将它们的地址导出为环境变量。
# 假设 Anvil 在 localhost:8545 上运行。使用 source init-local.sh 运行以设置环境变量。

set -e  # 出错时退出
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# 生成5个测试账户
echo "Generating 5 test accounts from Anvil default mnemonic..."
MNEMONIC="test test test test test test test test test test test junk"

for i in {0..4}; do
    PRIVATE_KEY=$(cast wallet derive-private-key --mnemonic "$MNEMONIC" --mnemonic-index $i 2>/dev/null)
    ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null)
    export ACCOUNT_${i}_ADDRESS=$ADDRESS
    export ACCOUNT_${i}_PRIVATE_KEY=$PRIVATE_KEY
done

# 设置常用别名
export ADMIN_ADDRESS=$ACCOUNT_0_ADDRESS
export ADMIN_PRIVATE_KEY=$ACCOUNT_0_PRIVATE_KEY
export USER1_ADDRESS=$ACCOUNT_1_ADDRESS
export USER1_PRIVATE_KEY=$ACCOUNT_1_PRIVATE_KEY
export USER2_ADDRESS=$ACCOUNT_2_ADDRESS
export USER2_PRIVATE_KEY=$ACCOUNT_2_PRIVATE_KEY
export USER3_ADDRESS=$ACCOUNT_3_ADDRESS
export USER3_PRIVATE_KEY=$ACCOUNT_3_PRIVATE_KEY
export USER4_ADDRESS=$ACCOUNT_4_ADDRESS
export USER4_PRIVATE_KEY=$ACCOUNT_4_PRIVATE_KEY

echo "Test accounts generated:"
echo "ADMIN: $ADMIN_ADDRESS"
echo "USER1: $USER1_ADDRESS"
echo "USER2: $USER2_ADDRESS"
echo "USER3: $USER3_ADDRESS"
echo "USER4: $USER4_ADDRESS"

RPC_URL="http://localhost:8545"
# Anvil 默认私钥，用于账户 0（带有 ETH 余额）
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo "Deploying contracts to local Anvil..."

# 注意: 此脚本假设 Anvil 以主网 fork 模式运行 (anvil --fork-url <mainnet_rpc>)，以使用真实的 USDC 和 Sanction Oracle 合约。

# 部署 KYCOracle
KYC_ORACLE_ADDR=$(forge create --broadcast --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/KYCOracle.sol:KYCOracle | grep "Deployed to:" | awk '{print $3}')
echo "Deployed KYCOracle at $KYC_ORACLE_ADDR"
[ -n "$KYC_ORACLE_ADDR" ] || { echo "Error: Failed to deploy KYCOracle"; exit 1; }

# 部署 PropertyOracle
PROPERTY_ORACLE_ADDR=$(forge create --broadcast --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/PropertyOracle.sol:PropertyOracle | grep "Deployed to:" | awk '{print $3}')
echo "Deployed PropertyOracle at $PROPERTY_ORACLE_ADDR"
[ -n "$PROPERTY_ORACLE_ADDR" ] || { echo "Error: Failed to deploy PropertyOracle"; exit 1; }

# 部署 RentToken 实现
RENT_TOKEN_IMPL_ADDR=$(forge create --broadcast --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/RentToken.sol:RentToken | grep "Deployed to:" | awk '{print $3}')
echo "Deployed RentToken implementation at $RENT_TOKEN_IMPL_ADDR"
[ -n "$RENT_TOKEN_IMPL_ADDR" ] || { echo "Error: Failed to deploy RentToken implementation"; exit 1; }

# 使用真实的主网地址
USDC_ADDR=0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
echo "Using real USDC at $USDC_ADDR"
SANCTION_ORACLE_ADDR=0x40C57923924B5c5c5455c48D93317139ADDaC8fb
echo "Using real Sanction Oracle at $SANCTION_ORACLE_ADDR"

# 使用 PropertyOracle 部署 SeriesFactory
SERIES_FACTORY_ADDR=$(forge create --broadcast --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY src/SeriesFactory.sol:SeriesFactory --constructor-args $PROPERTY_ORACLE_ADDR | grep "Deployed to:" | awk '{print $3}')
echo "Deployed SeriesFactory at $SERIES_FACTORY_ADDR"
[ -n "$SERIES_FACTORY_ADDR" ] || { echo "Error: Failed to deploy SeriesFactory"; exit 1; }

# 在 SeriesFactory 中设置 RentToken 实现（部署者具有管理员角色）
cast send --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY $SERIES_FACTORY_ADDR "updateRentTokenImplementation(address)" $RENT_TOKEN_IMPL_ADDR
echo "Set RentToken implementation in SeriesFactory"

# 导出环境变量
export KYC_ORACLE_ADDR
export PROPERTY_ORACLE_ADDR
export RENT_TOKEN_IMPL_ADDR
export SERIES_FACTORY_ADDR
export USDC_ADDR
export SANCTION_ORACLE_ADDR

echo "Deployment complete. Environment variables exported:"
echo "KYC_ORACLE_ADDR=$KYC_ORACLE_ADDR"
echo "PROPERTY_ORACLE_ADDR=$PROPERTY_ORACLE_ADDR"
echo "RENT_TOKEN_IMPL_ADDR=$RENT_TOKEN_IMPL_ADDR"
echo "SERIES_FACTORY_ADDR=$SERIES_FACTORY_ADDR"
echo "USDC_ADDR=$USDC_ADDR"
echo "SANCTION_ORACLE_ADDR=$SANCTION_ORACLE_ADDR"

# 验证合约部署
echo "Verifying deployments..."

# 验证 KYCOracle (调用 owner())
KYC_OWNER=$(cast call --rpc-url $RPC_URL $KYC_ORACLE_ADDR "owner()(address)")
echo "KYCOracle owner: $KYC_OWNER"

# 验证 PropertyOracle (调用 owner())
PROPERTY_OWNER=$(cast call --rpc-url $RPC_URL $PROPERTY_ORACLE_ADDR "owner()(address)")
echo "PropertyOracle owner: $PROPERTY_OWNER"

# 验证 RentToken implementation (调用 decimals()，假设它是可调用的)
RENT_DECIMALS=$(cast call --rpc-url $RPC_URL $RENT_TOKEN_IMPL_ADDR "decimals()(uint8)")
echo "RentToken decimals: $RENT_DECIMALS"

# 验证 SeriesFactory (调用 propertyOracle())
FACTORY_ORACLE=$(cast call --rpc-url $RPC_URL $SERIES_FACTORY_ADDR "propertyOracle()(address)")
echo "SeriesFactory propertyOracle: $FACTORY_ORACLE"

# 验证 USDC (调用 symbol())
USDC_SYMBOL=$(cast call --rpc-url $RPC_URL $USDC_ADDR "symbol()(string)")
echo "USDC symbol: $USDC_SYMBOL"

# 验证 SanctionOracle (调用 isSanctioned(0x000...000))
SANCTION_CHECK=$(cast call --rpc-url $RPC_URL $SANCTION_ORACLE_ADDR "isSanctioned(address)(bool)" 0x0000000000000000000000000000000000000000)
echo "SanctionOracle isSanctioned(0x0): $SANCTION_CHECK"

# 用usdc巨鲸账户给user充值，每人1e4 usdc
echo "💰 Funding test accounts with USDC from whale..."

# 使用已知的 USDC 巨鲸账户
USDC_WHALE=0x55fe002aeff02f77364de339a1292923a15844b8

# 模拟巨鲸账户
cast rpc --rpc-url $RPC_URL anvil_impersonateAccount $USDC_WHALE

# 给每个测试账户充值 10000 USDC (1e4 * 1e6 = 1e10)
echo "💸 Transferring 10000 USDC to each test account..."

# 给 ADMIN 充值
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC_ADDR "transfer(address,uint256)" $ADMIN_ADDRESS 10000000000 || { echo "❌ Failed to fund ADMIN"; exit 1; }
echo "✅ ADMIN funded with 10000 USDC"

# 给 USER1 充值
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC_ADDR "transfer(address,uint256)" $USER1_ADDRESS 10000000000 || { echo "❌ Failed to fund USER1"; exit 1; }
echo "✅ USER1 funded with 10000 USDC"

# 给 USER2 充值
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC_ADDR "transfer(address,uint256)" $USER2_ADDRESS 10000000000 || { echo "❌ Failed to fund USER2"; exit 1; }
echo "✅ USER2 funded with 10000 USDC"

# 给 USER3 充值
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC_ADDR "transfer(address,uint256)" $USER3_ADDRESS 10000000000 || { echo "❌ Failed to fund USER3"; exit 1; }
echo "✅ USER3 funded with 10000 USDC"

# 给 USER4 充值
cast send --rpc-url $RPC_URL --from $USDC_WHALE --unlocked $USDC_ADDR "transfer(address,uint256)" $USER4_ADDRESS 10000000000 || { echo "❌ Failed to fund USER4"; exit 1; }
echo "✅ USER4 funded with 10000 USDC"

# 停止模拟巨鲸账户
cast rpc --rpc-url $RPC_URL anvil_stopImpersonatingAccount $USDC_WHALE

# 验证充值结果
echo "🔍 Verifying USDC balances..."

ADMIN_USDC_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $ADMIN_ADDRESS)
USER1_USDC_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER1_ADDRESS)
USER2_USDC_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER2_ADDRESS)
USER3_USDC_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER3_ADDRESS)
USER4_USDC_BALANCE=$(cast call --rpc-url $RPC_URL $USDC_ADDR "balanceOf(address)(uint256)" $USER4_ADDRESS)

echo "USDC Balances:"
echo "  ADMIN:  $ADMIN_USDC_BALANCE (should be >= 10000000000)"
echo "  USER1:  $USER1_USDC_BALANCE (should be >= 10000000000)"
echo "  USER2:  $USER2_USDC_BALANCE (should be >= 10000000000)"
echo "  USER3:  $USER3_USDC_BALANCE (should be >= 10000000000)"
echo "  USER4:  $USER4_USDC_BALANCE (should be >= 10000000000)"
