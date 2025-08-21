#!/bin/bash

# Anvil 主网 Fork 启动脚本
# 启动本地 Anvil 实例，fork 主网数据

set -e

# 加载环境变量（如果存在）
if [[ -f ".env" ]]; then
    source .env
fi

# 默认配置
PORT=${PORT:-8545}
CHAIN_ID=${CHAIN_ID:-1}
ACCOUNTS=${ACCOUNTS:-10}
BALANCE=${BALANCE:-10000}

# 主网 RPC URL（优先使用环境变量）
MAINNET_RPC=${MAINNET_RPC_URL:-$RPC_URL_MAINNET}

if [[ -z "$MAINNET_RPC" ]]; then
    echo "❌ Error: No mainnet RPC URL provided"
    echo "Please set MAINNET_RPC_URL or RPC_URL_MAINNET in .env"
    echo "Example: MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY"
    exit 1
fi

echo "🚀 Starting Anvil mainnet fork..."
echo "=================================================="
echo "📋 Configuration:"
echo "   Mainnet RPC: $MAINNET_RPC"
echo "   Port: $PORT"
echo "   Chain ID: $CHAIN_ID"
echo "   Accounts: $ACCOUNTS"
echo "   Balance per account: $BALANCE ETH"
echo ""

# 检查端口是否被占用
if lsof -Pi ":$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "❌ Error: Port $PORT is already in use"
    echo "Please stop the existing process or use a different port"
    exit 1
fi

# 启动 Anvil
echo "🔧 Starting Anvil..."

anvil \
    --fork-url "$MAINNET_RPC" \
    --port "$PORT" \
    --chain-id "$CHAIN_ID" \
    --accounts "$ACCOUNTS" \
    --balance "$BALANCE" \
    --host 0.0.0.0 \
    --gas-limit 30000000 \
    --gas-price 1 \
    --block-time 2 &

ANVIL_PID=$!

# 等待 Anvil 启动
echo "⏳ Waiting for Anvil to start..."
for i in {1..10}; do
    if cast block-number --rpc-url "http://localhost:$PORT" >/dev/null 2>&1; then
        echo "✅ Anvil started successfully!"
        break
    fi
    if [[ $i -eq 10 ]]; then
        echo "❌ Error: Anvil failed to start within 10 seconds"
        kill $ANVIL_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

echo ""
echo "🎯 Anvil Fork Information:"
echo "   PID: $ANVIL_PID"
echo "   RPC URL: http://localhost:$PORT"
echo "   Chain ID: $CHAIN_ID"
echo "   Fork Block: $(cast block-number --rpc-url "http://localhost:$PORT")"
echo ""

# 显示默认账户
echo "🔑 Default Accounts (from test mnemonic):"
echo "   0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)"
echo "   1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)"
echo "   2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000 ETH)"
echo "   3: 0x90F79bf6EB2c4f870365E785982E1f101E93b906 (10000 ETH)"
echo "   4: 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 (10000 ETH)"
echo ""

echo "💡 Usage Examples:"
echo "   Test connection: cast block-number --rpc-url http://localhost:$PORT"
echo "   Check balance: cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:$PORT"
echo "   Stop Anvil: kill $ANVIL_PID"
echo ""

echo "📝 To stop Anvil manually:"
echo "   kill $ANVIL_PID"
echo ""

# 将 PID 写入文件，便于后续管理
echo $ANVIL_PID > .anvil.pid
echo "✅ PID written to .anvil.pid"

echo "🚀 Anvil is running in the background. Happy testing!"
echo "=================================================="

# 保持脚本运行并捕获信号
trap "echo '🛑 Stopping Anvil...'; kill $ANVIL_PID 2>/dev/null || true; rm -f .anvil.pid; exit 0" SIGINT SIGTERM EXIT

# 等待 Anvil 进程
wait $ANVIL_PID
