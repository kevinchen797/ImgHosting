#!/bin/bash
# 文件名：app_launch_benchmark.sh
# 描述：安卓App启动时间测试工具

# ============================================
# 配置部分
# ============================================
DEFAULT_CONFIG="app_config.cfg"
DEFAULT_ITERATIONS=3
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="launch_report_${TIMESTAMP}.txt"

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ============================================
# 工具函数
# ============================================

print_msg() {
    local msg="$1"
    local color="$2"
    echo -e "${color}${msg}${NC}"
    # 同时写入报告文件（去掉颜色代码）
    echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT_FILE"
}

print_to_report() {
    echo "$1" >> "$REPORT_FILE"
}

print_to_both() {
    local msg="$1"
    local color="$2"
    echo -e "${color}${msg}${NC}"
    echo "$msg" >> "$REPORT_FILE"
}

# ============================================
# 核心函数
# ============================================

init_report() {
    # 清空并初始化报告文件
    echo "==========================================" > "$REPORT_FILE"
    echo "          APP启动时间测试报告" >> "$REPORT_FILE"
    echo "==========================================" >> "$REPORT_FILE"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "配置文件: $CONFIG_FILE" >> "$REPORT_FILE"
    echo "测试次数: $ITERATIONS" >> "$REPORT_FILE"
    echo "设备信息: $(adb shell getprop ro.product.model 2>/dev/null || echo '未知')" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "测试详情" >> "$REPORT_FILE"
    echo "--------" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

check_adb() {
    print_msg "检查ADB连接..." "$BLUE"
    
    if ! adb devices | grep -q "device$"; then
        print_msg "错误：未找到已连接的Android设备" "$RED"
        exit 1
    fi
    
    print_msg "✓ ADB连接正常" "$GREEN"
}

create_config_template() {
    cat > app_config_template.cfg << 'EOF'
# App启动时间测试配置文件
# 格式：包名|Activity类名|显示名称

# 系统应用
com.android.deskclock|com.android.deskclock.DeskClock|时钟
com.android.settings|com.android.settings.Settings|系统设置
com.android.dialer|com.android.dialer.main.impl.MainActivity|拨号器

# 第三方应用示例
# com.tencent.mm|com.tencent.mm.ui.LauncherUI|微信
# com.taobao.taobao|com.taobao.tao.homepage.MainActivity3|淘宝

# 测试参数
ITERATIONS=3
WAIT_TIME=2
EOF
    print_msg "配置文件模板已创建：app_config_template.cfg" "$GREEN"
}

parse_config() {
    local config_file=$1
    
    if [[ ! -f "$config_file" ]]; then
        print_msg "错误：配置文件不存在: $config_file" "$RED"
        exit 1
    fi
    
    APPS=()
    ITERATIONS=$DEFAULT_ITERATIONS
    WAIT_TIME=2
    
    # 读取参数
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        case $key in
            ITERATIONS)
                if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
                    ITERATIONS=$value
                fi
                ;;
            WAIT_TIME)
                if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
                    WAIT_TIME=$value
                fi
                ;;
        esac
    done < "$config_file"
    
    # 读取App配置
    while IFS='|' read -r package activity name; do
        package=$(echo "$package" | xargs)
        activity=$(echo "$activity" | xargs)
        name=$(echo "$name" | xargs)
        
        [[ -z "$package" ]] && continue
        [[ "$package" == \#* ]] && continue
        [[ -z "$activity" ]] && continue
        [[ -z "$name" ]] && name="$package"
        
        APPS+=("$package|$activity|$name")
    done < <(grep -v -E "^(#|$|ITERATIONS|WAIT_TIME)" "$config_file")
    
    if [[ ${#APPS[@]} -eq 0 ]]; then
        print_msg "错误：配置文件中未找到有效的App配置" "$RED"
        exit 1
    fi
    
    print_msg "✓ 加载了 ${#APPS[@]} 个应用" "$GREEN"
    print_msg "测试次数: $ITERATIONS" "$CYAN"
    print_msg "等待时间: ${WAIT_TIME}秒" "$CYAN"
    
    # 记录到报告
    print_to_report "应用数量: ${#APPS[@]}"
    print_to_report "测试次数: $ITERATIONS"
    print_to_report "等待时间: ${WAIT_TIME}秒"
    print_to_report ""
}

stop_app() {
    local package=$1
    adb shell am force-stop "$package" > /dev/null 2>&1
    sleep 0.5
}

launch_and_measure() {
    local package=$1
    local activity=$2
    
    # 停止应用确保冷启动
    stop_app "$package"
    
    # 执行启动命令
    local output
    output=$(adb shell am start -n "$package/$activity" -W 2>&1)
    
    # 调试：输出原始结果
    # echo "DEBUG: $output"
    
    # 解析时间
    local total_time=0
    
    # 尝试多种方式提取TotalTime
    if echo "$output" | grep -q "TotalTime:"; then
        total_time=$(echo "$output" | grep "TotalTime:" | awk '{print $2}' | tr -d '\r')
    elif echo "$output" | grep -q "TotalTime"; then
        total_time=$(echo "$output" | tr ' ' '\n' | grep -A1 "TotalTime" | tail -1 | tr -d '\r')
    fi
    
    # 验证是否为数字
    if ! [[ "$total_time" =~ ^[0-9]+$ ]]; then
        total_time=0
    fi
    
    echo "$total_time"
}

test_single_app() {
    local package=$1
    local activity=$2
    local name=$3
    local app_num=$4
    local total_apps=$5
    
    print_to_both "" ""
    print_to_both "========================================" "$PURPLE"
    print_to_both "[$app_num/$total_apps] 测试应用: $name" "$YELLOW"
    print_to_both "包名: $package" "$CYAN"
    print_to_both "Activity: $activity" "$CYAN"
    print_to_both "----------------------------------------" "$PURPLE"
    
    local times=()
    local success_count=0
    
    for ((i=1; i<=ITERATIONS; i++)); do
        print_msg "  第 $i/$ITERATIONS 次测试..." "$BLUE"
        print_to_report "  第 $i 次测试:"
        
        local launch_time=$(launch_and_measure "$package" "$activity")
        
        if [[ "$launch_time" -gt 0 ]]; then
            times+=("$launch_time")
            success_count=$((success_count + 1))
            
            # 显示结果
            local status_msg="    耗时: ${launch_time}ms"
            if [[ "$launch_time" -lt 500 ]]; then
                print_msg "${status_msg} 🚀" "$GREEN"
            elif [[ "$launch_time" -lt 1000 ]]; then
                print_msg "${status_msg} ⚡" "$GREEN"
            elif [[ "$launch_time" -lt 2000 ]]; then
                print_msg "${status_msg}" "$YELLOW"
            else
                print_msg "${status_msg} 🐌" "$RED"
            fi
            
            # 记录到报告
            print_to_report "    结果: ${launch_time}ms"
        else
            print_msg "    ✗ 启动失败" "$RED"
            print_to_report "    结果: 启动失败"
        fi
        
        # 返回桌面，等待下一次测试
        adb shell input keyevent KEYCODE_HOME
        sleep "$WAIT_TIME"
    done
    
    # 显示和记录统计结果
    if [[ ${#times[@]} -gt 0 ]]; then
        calculate_and_record_stats "$name" times[@]
    else
        print_msg "  ✗ 所有测试均失败" "$RED"
        print_to_report "  统计结果: 所有测试均失败"
    fi
    
    print_to_both "========================================" "$PURPLE"
    print_to_both "" ""
}

calculate_and_record_stats() {
    local name=$1
    local times_array=("${!2}")
    
    local sum=0
    local count=${#times_array[@]}
    local min=999999
    local max=0
    
    for time in "${times_array[@]}"; do
        sum=$((sum + time))
        if [[ $time -lt $min ]]; then min=$time; fi
        if [[ $time -gt $max ]]; then max=$time; fi
    done
    
    local avg=$((sum / count))
    
    # 计算标准差
    local variance_sum=0
    for time in "${times_array[@]}"; do
        local diff=$((time - avg))
        variance_sum=$((variance_sum + diff * diff))
    done
    local std_dev=$(echo "scale=0; sqrt($variance_sum / $count)" | bc 2>/dev/null || echo 0)
    
    # 显示统计结果
    print_msg "  📊 统计结果:" "$CYAN"
    print_msg "    成功次数: $count/$ITERATIONS" "$CYAN"
    print_msg "    平均时间: ${avg}ms" "$CYAN"
    print_msg "    最短时间: ${min}ms" "$CYAN"
    print_msg "    最长时间: ${max}ms" "$CYAN"
    
    if [[ "$std_dev" -gt 0 ]]; then
        print_msg "    标准差: ${std_dev}ms" "$CYAN"
    fi
    
    # 评价
    local evaluation=""
    if [[ $avg -lt 300 ]]; then
        evaluation="🚀 极快"
    elif [[ $avg -lt 600 ]]; then
        evaluation="⚡ 快速"
    elif [[ $avg -lt 1000 ]]; then
        evaluation="✅ 良好"
    elif [[ $avg -lt 2000 ]]; then
        evaluation="⚠️ 一般"
    else
        evaluation="🐌 较慢"
    fi
    print_msg "    评价: $evaluation" "$GREEN"
    
    # 记录到报告
    print_to_report "  统计结果:"
    print_to_report "    成功次数: $count/$ITERATIONS"
    print_to_report "    平均时间: ${avg}ms"
    print_to_report "    最短时间: ${min}ms"
    print_to_report "    最长时间: ${max}ms"
    if [[ "$std_dev" -gt 0 ]]; then
        print_to_report "    标准差: ${std_dev}ms"
    fi
    print_to_report "    评价: $evaluation"
}

generate_summary() {
    print_to_both "" ""
    print_to_both "========================================" "$PURPLE"
    print_to_both "              测试总结" "$YELLOW"
    print_to_both "========================================" "$PURPLE"
    
    # 这里可以添加总结逻辑
    print_to_both "测试完成时间: $(date '+%Y-%m-%d %H:%M:%S')" "$CYAN"
    print_to_both "报告文件: $REPORT_FILE" "$GREEN"
    
    print_to_both "" ""
    print_to_both "提示: 查看详细结果请打开报告文件:" "$BLUE"
    print_to_both "  cat $REPORT_FILE" "$CYAN"
    print_to_both "  或" "$BLUE"
    print_to_both "  less $REPORT_FILE" "$CYAN"
}

run_all_tests() {
    print_msg "开始测试..." "$YELLOW"
    print_msg "总共 ${#APPS[@]} 个应用，每个测试 $ITERATIONS 次" "$BLUE"
    echo ""
    
    # 初始化报告
    init_report
    
    local app_index=1
    local total_apps=${#APPS[@]}
    
    for app_info in "${APPS[@]}"; do
        IFS='|' read -r package activity name <<< "$app_info"
        
        # 测试单个应用
        test_single_app "$package" "$activity" "$name" "$app_index" "$total_apps"
        
        app_index=$((app_index + 1))
    done
    
    # 生成总结
    generate_summary
    
    print_msg "" ""
    print_msg "✓ 测试完成！" "$GREEN"
    print_msg "详细报告已保存到: $REPORT_FILE" "$CYAN"
    
    # 显示报告最后几行
    echo ""
    print_msg "报告最后几行内容:" "$YELLOW"
    tail -10 "$REPORT_FILE" | while read line; do
        echo "  $line"
    done
}

test_command_format() {
    print_msg "测试命令格式..." "$CYAN"
    
    local test_package="com.android.deskclock"
    local test_activity="com.android.deskclock.DeskClock"
    
    print_msg "执行命令: adb shell am start -n $test_package/$test_activity -W" "$BLUE"
    
    local output
    output=$(adb shell am start -n "$test_package/$test_activity" -W 2>&1)
    
    echo "命令输出:"
    echo "$output"
    echo ""
    
    local total_time=$(echo "$output" | grep "TotalTime" | awk '{print $2}' 2>/dev/null)
    if [[ -n "$total_time" ]] && [[ "$total_time" =~ ^[0-9]+$ ]]; then
        print_msg "✓ 命令执行成功，获取到时间: ${total_time}ms" "$GREEN"
        return 0
    else
        print_msg "✗ 命令执行失败或格式不正确" "$RED"
        echo "建议:"
        echo "1. 检查包名和Activity是否正确"
        echo "2. 手动执行命令测试: adb shell am start -n com.android.deskclock/com.android.deskclock.DeskClock -W"
        return 1
    fi
}

# ============================================
# 主程序
# ============================================

show_help() {
    cat << EOF
App启动时间测试工具作者：AI+（千里马wx号：androidframework007） v2.0

用法: $0 [选项]

选项:
  -c, --config FILE     指定配置文件 (默认: app_config.cfg)
  -n, --iterations N    指定测试次数 (默认: 3)
  -t, --template        创建配置文件模板
  -T, --test            测试命令格式
  -h, --help            显示帮助信息

示例:
  $0                     # 使用默认配置测试
  $0 -c my_apps.cfg -n 5 # 自定义配置，测试5次
  $0 -T                  # 测试命令格式

报告文件:
  测试完成后会生成: launch_report_YYYYMMDD_HHMMSS.txt
EOF
}

# 参数解析
CONFIG_FILE="$DEFAULT_CONFIG"
ITERATIONS="$DEFAULT_ITERATIONS"
TEST_CMD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -n|--iterations)
            if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
                ITERATIONS="$2"
            fi
            shift 2
            ;;
        -t|--template)
            create_config_template
            exit 0
            ;;
        -T|--test)
            TEST_CMD=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_msg "未知参数: $1" "$RED"
            show_help
            exit 1
            ;;
    esac
done

# 主函数
main() {
    echo ""
    print_msg "========================================" "$PURPLE"
    print_msg "      APP启动时间测试工具 v2.0" "$YELLOW"
    print_msg "========================================" "$PURPLE"
    echo ""
    
    # 检查ADB
    check_adb
    
    if [[ "$TEST_CMD" == true ]]; then
        test_command_format
        exit 0
    fi
    
    # 解析配置
    parse_config "$CONFIG_FILE"
    
    # 运行测试
    run_all_tests
}

# 运行主函数
main