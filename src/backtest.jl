function backtest(strat, data; mode = "train")
    记忆仓位 = @staticvar zeros(Float32, 100000)
    F, N, T = size(data.特征)
    T < 1 && return 0f0
    @unpack sim, 最大持仓, 持仓天数, 是否隔夜, 最多交易次数 = strat
    最大持仓 = iszero(最大持仓) ? ncodes(data) : clamp(最大持仓, 1, ncodes(data))
    虚拟信号, 综合评分 = simulate(sim, data)
    持仓天数′ = size(虚拟信号, 1) ÷ N
    if 持仓天数′ == 1
        虚拟信号 = lockphase(虚拟信号, 持仓天数)
        综合评分 = lockphase(综合评分, 持仓天数)
    else
        持仓天数 = 持仓天数′
    end
    data = repeat(data, 持仓天数)
    @unpack 代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 涨停, 跌停, 最新价 = data
    if size(记忆仓位, 1) != size(虚拟信号, 1)
        fill!(resize!(记忆仓位, size(虚拟信号, 1)), 0f0)
    end
    转移函数 = transition(sim)
    if select(sim)
        是否为ST = repeat(getfeat(data, r"is_st", errors = "ignore"), 持仓天数)
        实际仓位 = select_stocks(涨停, 跌停, 交易池, 是否为ST, 虚拟信号, 综合评分, 记忆仓位, 最大持仓, 持仓天数, 转移函数)
    else
        实际仓位 = constraint(代码, 时间戳, 涨停, 跌停, 虚拟信号, 记忆仓位, 转移函数, 是否隔夜, 最多交易次数)
    end
    if size(实际仓位, 2) == 1 && !hasnan(实际仓位)
        记忆仓位 .= 实际仓位[:, end]
    end
    if T > 1 && parseenv("CLOSE_LAST_POS", true)
        实际仓位[:, end] .= 0
    end
    pnl = if mode == "train"
        summarize_train(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 实际仓位, 综合评分, 最大持仓 * 持仓天数)
    else
        summarize_test(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 最新价, 实际仓位, 综合评分, 虚拟信号, 最大持仓 * 持仓天数)
    end
    return pnl
end

function constraint(代码, 时间戳, 涨停, 跌停, 虚拟信号, 记忆仓位, 转移函数, 是否隔夜, 最多交易次数)
    实际仓位 = zero(虚拟信号)
    三点半 = Time(15, 30)
    N, T = size(实际仓位)
    交易次数 = zeros(Int, N)
    @inbounds for t in 1:T, n in 1:N
        之前仓位 = t > 1 ? 实际仓位[n, t - 1] : 记忆仓位[n]
        当前仓位 = 转移函数(之前仓位, 虚拟信号[n, t])
        if 涨停[n, t] == 1 && 当前仓位 > 之前仓位 ||
            跌停[n, t] == 1 && 当前仓位 < 之前仓位 ||
            交易次数[n] >= 最多交易次数 && abs(当前仓位) > abs(之前仓位)
            当前仓位 = 之前仓位
        end
        if 代码[n, t] != 代码[n, min(t + 1, end)]
            当前仓位 = 0f0
        end
        if 时间戳[n, min(t + 1, end)] - 时间戳[n, t] > 3600 * 5 &&
            (3600 * 9 <= 时间戳[n, t] % (3600 * 24) <= 3600 * 15.5)
            当前仓位 = ifelse(是否隔夜, 当前仓位, 0f0)
            交易次数[n] = 0
        else
            交易次数[n] += 当前仓位 != 之前仓位
        end
        实际仓位[n, t] = 当前仓位
    end
    return 实际仓位
end

function select_stocks(涨停, 跌停, 交易池, 是否为ST, 虚拟信号, 综合评分, 记忆仓位, 最大持仓, 持仓天数, 转移函数)
    实际仓位 = zero(虚拟信号)
    N, T = size(虚拟信号)
    选股池 = zeros(Bool, N)
    for t in 1:T
        fill!(选股池, 0)
        选股数 = 最大持仓 * 持仓天数
        for n in 1:N
            之前仓位 = t > 1 ? 实际仓位[n, t - 1] : 记忆仓位[n]
            当前仓位 = clamp(转移函数(之前仓位, 虚拟信号[n, t]), 0, 1)
            if isnan(虚拟信号[n, t]) || 当前仓位 > 之前仓位
                选股池[n] = 1
                实际仓位[n, t] = 0
            else
                实际仓位[n, t] = 当前仓位
            end
            if 交易池[n, t] == 0 || 是否为ST[n, t] == 1
                实际仓位[n, t] = 0
                选股池[n] = 0
            end
            if 涨停[n, t] == 1 || 跌停[n, t] == 1
                实际仓位[n, t] = 之前仓位
                选股池[n] = 0
            end
            选股数 -= 实际仓位[n, t] == 1
        end
        选股数 = min(选股数, 最大持仓)
        选股列表 = findall(选股池)
        if length(选股列表) <= 选股数
            实际仓位[选股列表, t] .= 1
        else
            选股列表索引 = partialsortperm(综合评分[选股列表, t], 1:选股数, rev = true)
            实际仓位[选股列表[选股列表索引], t] .= 1
        end
    end
    return 实际仓位
end

function summarize_core(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 实际仓位, 综合评分, 最大持仓)
    记忆收益率 = @staticvar Dict{UInt64, Array{Float32}}()
    N, T = size(实际仓位)
    天数 = sortednunique(unix2date, 时间戳[1, :])
    复利 = get(ENV, "USE_COMP", "0") == "1"
    收益率 = zero(实际仓位)
    之前仓位 = zeros(Float32, N)
    之前盈亏 = zeros(Float32, N)
    @inbounds for t in 1:T
        当前平均涨幅 = @views mean(涨幅[:, t])
        for n in 1:N
            当前仓位 = 实际仓位[n, t]
            当前涨幅 = 涨幅[n, t]
            仓位变化 = 当前仓位 - 之前仓位[n]
            手续费率 = ifelse(仓位变化 > 0, 买手续费率[n, t], -卖手续费率[n, t]) * 仓位变化
            收益率[n, t] = 之前盈亏[n] - 手续费率
            之前仓位[n] = 当前仓位
            之前盈亏[n] = 当前仓位 * 当前涨幅
        end
    end
    if T ==  1
        收益率[:, end] .+= 之前盈亏
    end
    倍数 = 年化收益率 = 1f0
    资金曲线 = ones(Float32, T)
    if 复利
        @inbounds for t in 1:size(实际仓位, 2)
            Δ = @views sum(收益率[:, t]) ⧶ 最大持仓
            资金曲线[t] = 倍数 = (1 + Δ)  * 倍数
        end
        年化收益率 = 倍数^(224f0 / 天数) - 1
    else
        @inbounds for t in 1:T
            Δ = @views sum(收益率[:, t]) ⧶ 最大持仓
            资金曲线[t] = 倍数 = 倍数 + Δ
        end
        年化收益率 = 224f0 * (倍数 - 1f0) / 天数
    end
    最大回撤, 最大回撤期 = drawdown(资金曲线)
    夏普率 = sharperatio(资金曲线, 224T / 天数)
    length(记忆收益率) > 10 && empty!(记忆收益率)
    记忆收益率[hash(时间戳)] = 收益率
    return 收益率, 资金曲线, 年化收益率, 最大回撤, 夏普率
end

function summarize_train(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 实际仓位, 综合评分, 最大持仓)
    收益率, 资金曲线, 年化收益率, 最大回撤, 夏普率 = summarize_core(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 实际仓位, 综合评分, 最大持仓)
    评分模式 = parseenv("SCORE", "R")
    if 评分模式 == "R" # Return
        分数 = 年化收益率
    elseif 评分模式 == "SHARPE"
        分数 = 夏普率
    elseif 评分模式 == "RoMaD" # Return Over Maximum Drawdown
        分数 = 年化收益率 ⧶ abs(最大回撤)
    elseif occursin("LAR", 评分模式)  # Loss Amplified Return
        λ = Meta.parse(split(评分模式, '_')[2])
        分数 = sum(x -> amploss(x, λ), 年化收益率)
    elseif occursin("IR", 评分模式)  # Information Rank
        nonan(x) = ifelse(isnan(x), zero(x), x)
        分数 = mean(nonan(corspearman(综合评分[:, t], 涨幅[:, t])) for t in 1:size(实际仓位, 2))
    elseif occursin("WR", 评分模式)  # Average Winning Ratio
        分数 = mean(mean(涨幅[实际仓位[:, t] .> 0, t]) >
                    mean(涨幅[交易池[:, t] .> 0, t])
                    for t in 1:(size(实际仓位, 2) - 1))
    elseif occursin("ACC", 评分模式) # Accuracy
        分数 = mean(mean(涨幅[实际仓位[:, t] .> 0, t] .>
                        mean(涨幅[交易池[:, t] .> 0, t]))
                    for t in 1:(size(实际仓位, 2) - 1))
    end
    @assert !isnan(分数)
    return 分数
end

function summarize_test(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 最新价, 实际仓位, 综合评分, 虚拟信号, 最大持仓)
    收益率, 资金曲线, 年化收益率, 最大回撤, 夏普率 = summarize_core(代码, 交易池, 时间戳, 涨幅, 买手续费率, 卖手续费率, 实际仓位, 综合评分, 最大持仓)
    目录名 = mkpath(产生目录(时间戳, 代码, 年化收益率, 最大回撤, 夏普率))
    @indir 目录名 begin
        输出每日持股明细(代码, 时间戳, 实际仓位)
        输出资金和仓位曲线(时间戳, 实际仓位, 资金曲线)
        输出个股交易记录(时间戳, 代码, 最新价, 收益率, 实际仓位)
        新目录名 = 输出资金曲线(时间戳, 代码, 实际仓位, 收益率, 最大持仓)
        输出盈亏报告()
        parseenv("OUTPUT_POS", false) && 输出仓位评分信号(代码, 时间戳, 实际仓位, 综合评分, 虚拟信号)
        parseenv("OUTPUT_MINPOS", false) && 输出分钟仓位(代码, 时间戳, 最新价, 实际仓位, 收益率)
    end
    return 年化收益率
end