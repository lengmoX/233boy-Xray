is_route_rule_list=(bt cn private ads openai)

route_rule_mark() {
    case $1 in
    bt) echo ban_bt ;;
    cn) echo ban_geoip_cn ;;
    private) echo ban_private ;;
    ads) echo ban_ad ;;
    openai) echo fix_openai ;;
    esac
}

route_rule_name() {
    case $1 in
    bt) echo "屏蔽 BT" ;;
    cn) echo "屏蔽中国 IP" ;;
    private) echo "屏蔽私有 IP" ;;
    ads) echo "屏蔽广告" ;;
    openai) echo "OpenAI 直连" ;;
    esac
}

route_rule_json() {
    case $1 in
    bt) echo '{type:"field",protocol:["bittorrent"],marktag:"ban_bt",outboundTag:"block"}' ;;
    cn) echo '{type:"field",ip:["geoip:cn"],marktag:"ban_geoip_cn",outboundTag:"block"}' ;;
    private) echo '{type:"field",ip:["geoip:private"],marktag:"ban_private",outboundTag:"block"}' ;;
    ads) echo '{type:"field",domain:["geosite:category-ads-all"],marktag:"ban_ad",outboundTag:"block"}' ;;
    openai) echo '{type:"field",domain:["geosite:openai"],marktag:"fix_openai",outboundTag:"direct"}' ;;
    esac
}

route_rule_exists() {
    local mark=$(route_rule_mark $1)
    if [[ $1 == private ]]; then
        jq -e '.routing.rules[]? | select((.marktag == "ban_private") or ((.ip // []) | index("geoip:private")) and .outboundTag == "block")' $is_config_json &>/dev/null
        return
    fi
    jq -e --arg mark "$mark" '.routing.rules[]? | select(.marktag == $mark)' $is_config_json &>/dev/null
}

route_ensure_base() {
    jq -e '.routing.rules' $is_config_json &>/dev/null || {
        cat <<<$(jq '.routing={domainStrategy:"IPIfNonMatch",rules:[{type:"field",inboundTag:["api"],outboundTag:"api"}]}' $is_config_json) >$is_config_json
    }
}

route_ensure_block() {
    jq -e '.outbounds[]? | select(.tag == "block")' $is_config_json &>/dev/null && return
    cat <<<$(jq '.outbounds += [{tag:"block",protocol:"blackhole"}]' $is_config_json) >$is_config_json
}

route_cleanup_block() {
    jq -e '.routing.rules[]? | select(.outboundTag == "block")' $is_config_json &>/dev/null && return
    cat <<<$(jq 'del(.outbounds[] | select(.tag == "block"))' $is_config_json) >$is_config_json
}

route_enable_one() {
    local rule=$1
    local data=$(route_rule_json $rule)
    [[ ! $data ]] && err "无法识别路由规则: $rule"
    route_rule_exists $rule && {
        msg "$(route_rule_name $rule): $(_green 已开启)"
        return
    }
    [[ $rule != openai ]] && route_ensure_block
    cat <<<$(jq ".routing.rules += [$data]" $is_config_json) >$is_config_json
    is_route_changed=1
    msg "$(route_rule_name $rule): $(_green 已开启)"
}

route_disable_one() {
    local rule=$1
    local mark=$(route_rule_mark $rule)
    [[ ! $mark ]] && err "无法识别路由规则: $rule"
    route_rule_exists $rule || {
        msg "$(route_rule_name $rule): $(_yellow 未开启)"
        return
    }
    if [[ $rule == private ]]; then
        cat <<<$(jq 'del(.routing.rules[] | select((.marktag == "ban_private") or ((.ip // []) | index("geoip:private")) and .outboundTag == "block"))' $is_config_json) >$is_config_json
    else
        cat <<<$(jq --arg mark "$mark" 'del(.routing.rules[] | select(.marktag == $mark))' $is_config_json) >$is_config_json
    fi
    route_cleanup_block
    is_route_changed=1
    msg "$(route_rule_name $rule): $(_green 已关闭)"
}

route_status() {
    msg "\n当前路由屏蔽规则:\n"
    for rule in ${is_route_rule_list[@]}; do
        if route_rule_exists $rule; then
            msg "$(route_rule_name $rule): $(_green 已开启)"
        else
            msg "$(route_rule_name $rule): $(_yellow 已关闭)"
        fi
    done
    msg
}

route_pick_rule() {
    is_tmp_list=("屏蔽 BT" "屏蔽中国 IP" "屏蔽私有 IP" "屏蔽广告" "OpenAI 直连" "全部规则")
    ask list is_route_pick null "\n请选择路由规则:\n"
    case $REPLY in
    1) is_route_rule=bt ;;
    2) is_route_rule=cn ;;
    3) is_route_rule=private ;;
    4) is_route_rule=ads ;;
    5) is_route_rule=openai ;;
    6) is_route_rule=all ;;
    esac
}

route_apply() {
    local action=$1
    local rule=$2
    [[ ! $rule ]] && route_pick_rule && rule=$is_route_rule
    if [[ $rule == all ]]; then
        for v in ${is_route_rule_list[@]}; do
            route_${action}_one $v
        done
    else
        route_${action}_one $rule
    fi
}

route_set() {
    route_ensure_base
    case ${1,,} in
    status | s)
        route_status
        return
        ;;
    enable | on)
        route_apply enable ${2,,}
        ;;
    disable | off)
        route_apply disable ${2,,}
        ;;
    '')
        is_tmp_list=("查看状态" "开启规则" "关闭规则")
        ask list is_route_action null "\n请选择路由设置:\n"
        case $REPLY in
        1) route_status && return ;;
        2) route_apply enable ;;
        3) route_apply disable ;;
        esac
        ;;
    *)
        err "无法识别 route 参数: $@\n请使用: $is_core route [status|enable|disable] [bt|cn|private|ads|openai|all]"
        ;;
    esac
    [[ $is_route_changed ]] && manage restart &
}
