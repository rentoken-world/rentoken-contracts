#!/bin/bash
# sync_property_to_blockchain.sh
# 将PostgreSQL数据库中的房产数据同步到区块链
# 支持本地Anvil和Sepolia网络

set -e  # 出错时退出

export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'  # 浅蓝色，黑色背景上更醒目
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 数据库配置
DATABASE_URL="postgres://neondb_owner:npg_6T8BdQKZFqME@ep-withered-lab-ad210dqn-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require"

# 网络配置
NETWORK_TYPE="${NETWORK_TYPE:-sepolia}"  # local 或 sepolia

if [ "$NETWORK_TYPE" = "sepolia" ]; then
    RPC_URL="https://eth-sepolia.api.onfinality.io/public"
    CHAIN_ID=11155111
    log_info "使用Sepolia测试网络"
else
    RPC_URL="http://localhost:8545"
    CHAIN_ID=31337
    log_info "使用本地Anvil网络"
fi

echo "🚀 房产数据区块链同步脚本"
echo "================================================="
log_info "网络: $NETWORK_TYPE"
log_info "RPC URL: $RPC_URL"
echo ""

# 检查依赖
check_dependencies() {
    log_info "检查依赖项..."

    # 检查psql
    if ! command -v psql &> /dev/null; then
        log_error "psql 未安装，请安装 PostgreSQL 客户端"
        exit 1
    fi

    # 检查cast
    if ! command -v cast &> /dev/null; then
        log_error "cast 未安装，请安装 Foundry"
        exit 1
    fi

    log_success "依赖项检查完成"
}

# 加载环境变量
load_environment() {
    log_info "加载环境变量..."

    if [ ! -f "sepolia.env" ]; then
        log_error "sepolia.env 文件不存在，请先运行 init-local.sh"
        exit 1
    fi

    source sepolia.env

    # 验证必要的环境变量
    required_vars=(
        "PROPERTY_ORACLE_ADDR" "SERIES_FACTORY_ADDR"
        "KYC_ORACLE_ADDR" "SANCTION_ORACLE_ADDR"
        "USDC_ADDR"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "缺少必要的环境变量: $var"
            exit 1
        fi
    done

    log_success "环境变量加载完成"
}

# 数据库连接测试
test_database_connection() {
    log_info "测试数据库连接..."

    if ! psql "$DATABASE_URL" -c "SELECT 1;" &> /dev/null; then
        log_error "数据库连接失败"
        exit 1
    fi

    log_success "数据库连接成功"
}

# 从数据库读取最新房产记录
read_latest_property() {
    log_info "从数据库读取最新房产记录..."

    # 查询最新的房产记录
    local query="SELECT id, title, description, location, valuation, \"minRaising\", \"maxRaising\", landlord, \"docHash\", \"offchainURL\", status, owner FROM properties ORDER BY \"createdAt\" DESC LIMIT 1;"

    local result=$(psql "$DATABASE_URL" -t -c "$query" 2>/dev/null)

    if [ -z "$result" ]; then
        log_error "未找到房产记录"
        exit 1
    fi

    # 解析结果并设置变量 (使用数组来处理管道分隔的数据)
    IFS='|' read -ra FIELDS <<< "$result"

    PROPERTY_ID="${FIELDS[0]}"
    PROPERTY_NAME="${FIELDS[1]}"
    PROPERTY_DESC="${FIELDS[2]}"
    PROPERTY_LOCATION="${FIELDS[3]}"
    PROPERTY_VALUATION="${FIELDS[4]}"
    PROPERTY_MIN_RAISING="${FIELDS[5]}"
    PROPERTY_MAX_RAISING="${FIELDS[6]}"
    LANDLORD_ADDRESS="${FIELDS[7]}"
    PROPERTY_DOC_HASH="${FIELDS[8]}"
    PROPERTY_OFFCHAIN_URL="${FIELDS[9]}"
    PROPERTY_STATUS="${FIELDS[10]}"
    PROPERTY_OWNER="${FIELDS[11]}"

    # 清理空格并处理空值
    PROPERTY_ID=$(echo "$PROPERTY_ID" | xargs)
    PROPERTY_NAME=$(echo "$PROPERTY_NAME" | xargs)
    PROPERTY_DESC=$(echo "$PROPERTY_DESC" | xargs)
    PROPERTY_LOCATION=$(echo "$PROPERTY_LOCATION" | xargs)
    # PROPERTY_VALUATION=$(echo "$PROPERTY_VALUATION" | xargs)
    PROPERTY_VALUATION=50000 # fix value
    # PROPERTY_MIN_RAISING=$(echo "$PROPERTY_MIN_RAISING" | xargs)
    PROPERTY_MIN_RAISING=20000 # fix value
    # PROPERTY_MAX_RAISING=$(echo "$PROPERTY_MAX_RAISING" | xargs)
    PROPERTY_MAX_RAISING=40000 # fix value
    LANDLORD_ADDRESS=$(echo "$LANDLORD_ADDRESS" | xargs)
    PROPERTY_DOC_HASH=$(echo "$PROPERTY_DOC_HASH" | xargs)
    PROPERTY_OFFCHAIN_URL=$(echo "$PROPERTY_OFFCHAIN_URL" | xargs)
    PROPERTY_STATUS=$(echo "$PROPERTY_STATUS" | xargs)
    PROPERTY_OWNER=$(echo "$PROPERTY_OWNER" | xargs)



    # 处理空值和格式问题
    # [ -z "$LANDLORD_ADDRESS" ] && LANDLORD_ADDRESS="$ADMIN_ADDRESS"
    [ -z "$PROPERTY_DOC_HASH" ] && PROPERTY_DOC_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"
    [ -z "$PROPERTY_OFFCHAIN_URL" ] && PROPERTY_OFFCHAIN_URL=""

    # 确保PROPERTY_DOC_HASH是32字节的十六进制字符串
    if [[ ! "$PROPERTY_DOC_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        PROPERTY_DOC_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"
    fi

    log_success "读取房产记录成功"
    log_info "房产数字ID: $PROPERTY_ID"
    log_info "房产名称: $PROPERTY_NAME"
    log_info "当前状态: $PROPERTY_STATUS"
    log_info "当前所有者: $PROPERTY_OWNER"
}

# 添加房产到PropertyOracle
add_property_to_oracle() {
    log_info "检查房产是否已存在于PropertyOracle..."

    # 检查房产是否已存在
    local exists=$(cast call --rpc-url "$RPC_URL" "$PROPERTY_ORACLE_ADDR" "propertyExists(uint256)(bool)" "$PROPERTY_ID")

        # 计算时间戳
    current_time=$(cast block --rpc-url "$RPC_URL" latest --field timestamp)
    # local accrual_start=$((current_time + 3600))  # 1小时后开始
    accrual_start=1756137600 # 2025-08-26 00:00:00 UTC
    accrual_end=$((accrual_start + 31536000))  # 1年后结束

    # 转换金额为wei (假设6位小数)
    valuation_wei=$((PROPERTY_VALUATION * 1000000))
    min_raising_wei=$((PROPERTY_MIN_RAISING * 1000000))
    max_raising_wei=$((PROPERTY_MAX_RAISING * 1000000))

    if [ "$exists" = "true" ]; then
        log_warning "房产 $PROPERTY_ID 已存在于PropertyOracle"
        return 0
    fi

    log_info "添加房产 $PROPERTY_ID 到PropertyOracle..."



    # 调试输出
    log_info "调试信息:"
    log_info "PROPERTY_ID: $PROPERTY_ID"
    log_info "USDC_ADDR: $USDC_ADDR"
    log_info "valuation_wei: $valuation_wei"
    log_info "min_raising_wei: $min_raising_wei"
    log_info "max_raising_wei: $max_raising_wei"
    log_info "accrual_start: $accrual_start"
    log_info "accrual_end: $accrual_end"
    log_info "LANDLORD_ADDRESS: $LANDLORD_ADDRESS"
    log_info "PROPERTY_DOC_HASH: $PROPERTY_DOC_HASH"
    log_info "PROPERTY_OFFCHAIN_URL: $PROPERTY_OFFCHAIN_URL"

    # 发送交易 - 使用分离的参数而不是结构体
    cast send --rpc-url "$RPC_URL" --account myMetaMaskAcc --password '' \
        "$PROPERTY_ORACLE_ADDR" \
        "addOrUpdateProperty(uint256,(uint256,address,uint256,uint256,uint256,uint64,uint64,address,bytes32,string))" \
        "$PROPERTY_ID" \
        "($PROPERTY_ID,$USDC_ADDR,$valuation_wei,$min_raising_wei,$max_raising_wei,$accrual_start,$accrual_end,$LANDLORD_ADDRESS,$PROPERTY_DOC_HASH,\"$PROPERTY_OFFCHAIN_URL\")" \
        || { log_error "添加房产到PropertyOracle失败"; exit 1; }

    log_success "房产添加到PropertyOracle成功"
}

# 检查并创建系列合约
check_and_create_series() {
    log_info "检查系列合约是否存在..."

    # 检查系列是否已存在
    SERIES_ADDR=$(cast call --rpc-url "$RPC_URL" "$SERIES_FACTORY_ADDR" "getSeriesAddress(uint256)(address)" "$PROPERTY_ID")

    if [ "$SERIES_ADDR" != "0x0000000000000000000000000000000000000000" ]; then
        log_warning "系列合约已存在: $SERIES_ADDR"
        # 读取Phase
        return 0
    fi

    log_info "为房产 $PROPERTY_ID 创建系列合约..."

    # 生成代币名称和符号
    local token_name="RentToken $PROPERTY_NAME"
    local token_symbol="RT$(echo $PROPERTY_NAME | tr -d ' ' | cut -c1-6 | tr '[:lower:]' '[:upper:]')"

    # 创建系列合约
    cast send --rpc-url "$RPC_URL" --account myMetaMaskAcc --password '' \
        "$SERIES_FACTORY_ADDR" \
        "createSeries(uint256,string,string)" \
        "$PROPERTY_ID" "$token_name" "$token_symbol" \
        || { log_error "创建系列合约失败"; exit 1; }

    # 获取新创建的系列地址
    SERIES_ADDR=$(cast call --rpc-url "$RPC_URL" "$SERIES_FACTORY_ADDR" "getSeriesAddress(uint256)(address)" "$PROPERTY_ID")

    if [ "$SERIES_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
        log_error "获取系列合约地址失败"
        exit 1
    fi

    #

    log_success "系列合约创建成功: $SERIES_ADDR"

    # 设置Oracle
    log_info "为系列合约设置Oracle..."
    cast send --rpc-url "$RPC_URL" --account myMetaMaskAcc --password '' \
        "$SERIES_FACTORY_ADDR" \
        "setOraclesForSeries(uint256,address,address)" \
        "$PROPERTY_ID" "$KYC_ORACLE_ADDR" "$SANCTION_ORACLE_ADDR" \
        || { log_error "设置Oracle失败"; exit 1; }

    log_success "Oracle设置完成"
}

# 更新数据库状态
update_database_status() {
    log_info "更新数据库状态..."

    local CURRENT_PHASE=$(cast call --rpc-url "$RPC_URL" "$SERIES_ADDR" "getPhase()(uint8)")
    log_info "当前阶段: $CURRENT_PHASE"



    # 更新owner字段为系列合约地址，status字段为funding
    local update_query="UPDATE properties SET \"renTokenAddress\" = '$SERIES_ADDR', \"status\" = '$CURRENT_PHASE', \"minRaising\" = $PROPERTY_MIN_RAISING, \"maxRaising\" = $PROPERTY_MAX_RAISING, \"accrualStart\" = $accrual_start, \"accrualEnd\" = $accrual_end, \"updatedAt\" = NOW() WHERE id = '$PROPERTY_ID';"
    echo $update_query

    psql "$DATABASE_URL" -c "$update_query" || { log_error "更新数据库失败"; exit 1; }

    log_success "数据库状态更新成功"
    log_info "房产 $PROPERTY_ID 的 renTokenAddress 已更新为: $SERIES_ADDR"
    log_info "房产 $PROPERTY_ID 的 status 已更新为: $CURRENT_PHASE"
}

# 验证最终状态
verify_final_state() {
    log_info "验证最终状态..."

    # 验证PropertyOracle中的房产
    local property_exists=$(cast call --rpc-url "$RPC_URL" "$PROPERTY_ORACLE_ADDR" "propertyExists(uint256)(bool)" "$PROPERTY_ID")
    if [ "$property_exists" != "true" ]; then
        log_error "PropertyOracle验证失败"
        exit 1
    fi

    # 验证系列合约
    local series_addr=$(cast call --rpc-url "$RPC_URL" "$SERIES_FACTORY_ADDR" "getSeriesAddress(uint256)(address)" "$PROPERTY_ID")
    if [ "$series_addr" = "0x0000000000000000000000000000000000000000" ]; then
        log_error "系列合约验证失败"
        exit 1
    fi

    # 验证数据库状态
    local db_status=$(psql "$DATABASE_URL" -t -c "SELECT status FROM properties WHERE id = '$PROPERTY_ID';" | xargs)
    local renTokenAddress=$(psql "$DATABASE_URL" -t -c "SELECT \"renTokenAddress\" FROM properties WHERE id = '$PROPERTY_ID';" | xargs)

    if [ "$db_status" != $CURRENT_PHASE ] || [ "$renTokenAddress" != "$SERIES_ADDR" ]; then
        log_error "数据库状态验证失败"
        exit 1
    fi

    log_success "所有验证通过"
}

# 主函数
main() {
    echo "开始执行房产数据同步..."
    echo ""

    check_dependencies
    load_environment
    test_database_connection
    read_latest_property
    add_property_to_oracle
    check_and_create_series
    update_database_status
    verify_final_state

    echo ""
    log_success "🎉 房产数据同步完成！"
    echo "================================================="
    log_info "房产数字ID: $PROPERTY_ID"
    log_info "系列合约地址: $SERIES_ADDR"
    log_info "数据库状态: $CURRENT_PHASE"
    echo "================================================="
}

# 错误处理
trap 'log_error "脚本执行失败，请检查错误信息"; exit 1' ERR

# 执行主函数
main "$@"
