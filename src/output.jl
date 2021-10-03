function 产生目录(时间戳, 代码, 年化收益率, 最大回撤, 夏普率)
    结果名 = @sprintf("%.2f倍%d%%%.1f", 1 + 年化收益率, -100最大回撤, 夏普率)
    结束时间戳 = maximum(时间戳)
    开始时间戳 = minimum(t -> ifelse(iszero(t), 结束时间戳, t), 时间戳)
    测试区间 = unix2str6(开始时间戳) * "-" * unix2str6(结束时间戳)
    目录名 = join([结果名, 测试区间, getpid()], '_')
    rm(目录名, force = true, recursive = true)
    return 目录名
end

function 输出每日持股明细(代码, 时间戳, 实际仓位)
    median(diff(时间戳[1, :])) < 3600 * 12 && return
    fid = open("每日持股明细.csv", "w")
    for t in 1:size(实际仓位, 2)
        print(fid, unix2date(时间戳[1, t]), ',')
        for n in 1:size(实际仓位, 1)
            实际仓位[n, t] == 1 && print(fid, 代码[n, t], ',')
        end
        println(fid)
    end
    close(fid)
end

function 输出资金和仓位曲线(时间戳, 实际仓位, 资金曲线)
    fid = open("资金和仓位曲线.csv", "w")
    之前日期 = unix2date(时间戳[1, 1]) - Day(1)
    之前实际仓位 = zeros(Float32, size(实际仓位, 1))
    write(fid, g"日期,资金曲线,持仓份额,多空份额,开仓份额,平仓份额,买入份额,卖出份额", '\n')
    for t in 1:size(实际仓位, 2)
        iszero(时间戳[1, t]) && continue
        持仓份额 = 多空份额 = 开仓份额 = 平仓份额 = 买入份额 = 卖出份额 = 0f0
        for n in 1:size(实际仓位, 1)
            当前仓位, 之前仓位 = 实际仓位[n, t], 之前实际仓位[n]
            当前仓位绝对值, 之前仓位绝对值 = abs(当前仓位), abs(之前仓位)
            仓位变化, 仓位绝对值变化 = 当前仓位 - 之前仓位, 当前仓位绝对值 - 之前仓位绝对值
            持仓份额 += 当前仓位
            多空份额 += 当前仓位绝对值
            开仓份额 += max(0f0, 仓位绝对值变化)
            平仓份额 += max(0f0, -仓位绝对值变化)
            买入份额 += max(0f0, 仓位变化)
            卖出份额 += max(0f0, -仓位变化)
            之前实际仓位[n] = 当前仓位
        end
        当前日期 = unix2date(时间戳[1, t])
        if 当前日期 != 之前日期
            for x in (当前日期, 资金曲线[t], 持仓份额, 多空份额, 开仓份额, 平仓份额, 买入份额, 卖出份额)
                print(fid, x, ',')
            end
            skip(fid, -1)
            println(fid)
        end
        之前日期 = 当前日期
    end
    close(fid)
end

function 输出资金曲线(时间戳, 代码, 实际仓位, 收益率, 最大持仓)
    复利 = get(ENV, "USE_COMPLEX", "0") == "1"
    N, T = size(收益率)
    nttype = NamedTuple{(:时间戳, :代码, :收益率, :仓位, :行数),
            Tuple{Float64, String, Float32, Float32, Int64}}
    nts = nttype[]
    dict = DefaultDict{Int, Int}(() -> 0)
    @showprogress 10 "pnl..." for n in 1:N
        pnl, date = 0f0, 0.0
        for t in 1:T
            if date == 0 && 时间戳[n, t] > 0
                date = 时间戳[n, t] ÷ 86400 * 86400
            end
            pos = 实际仓位[n, t]
            pnl += 收益率[n, t]
            date′ = 时间戳[n, min(end, t + 1)] ÷ 86400 * 86400
            if date > 0 && date′ > 0 && date′ != date || t == T
                code = replace(代码[n, t], r"(?<=[a-zA-Z])\d+" => "")
                nt = nttype((date, code, pnl, pos, n))
                push!(nts, nt)
                dict[date] += 1
                pnl = 0f0
                date = date′
            end
        end
    end
    df = DataFrame(nts)
    df["时间戳"] = df["时间戳"].mul(1e9).astype("datetime64[ns]")
    每行每股每日收益率 = df.groupby(["时间戳", "行数", "代码"])["收益率"].sum()
    最大持仓 = min(最大持仓, df.groupby("时间戳")["代码"].nunique().max())
    每日收益率 = 每行每股每日收益率.groupby("时间戳").sum().div(最大持仓).to_frame()
    资金曲线 = (复利 ? (1 + 每日收益率).cumprod() : 1 + 每日收益率.cumsum()).rename(columns = Dict("收益率" => "资金曲线"))
    资金曲线["持仓份额"] = df.groupby("时间戳")["仓位"].sum()
    资金曲线["持仓份额"] = df["仓位"].groupby(df["时间戳"]).sum()
    资金曲线["多空份额"] = df["仓位"].abs().groupby(df["时间戳"]).sum()
    if df["代码"].nunique() < 50 && df["时间戳"].nunique() > 1
        分品种每日收益率 = 每行每股每日收益率.groupby(["时间戳", "代码"]).mean()
        分品种每日收益率 = 分品种每日收益率.to_frame().pivot_table(columns = "代码", index = "时间戳", values = "收益率").fillna(0)
        分品种资金曲线 = 复利 ? (1 + 分品种每日收益率).cumprod() : 1 + 分品种每日收益率.cumsum()
        资金曲线 = pd.concat([资金曲线, 分品种资金曲线], axis = 1, sort = true)
    end
    资金曲线 = 添加指数(资金曲线)
    资金曲线.index.name = "日期"
    to_csv(资金曲线.reset_index(), "资金曲线.csv", encoding = "gbk", index = false)
    资金曲线 = 资金曲线["资金曲线"].values
    最大回撤, 最大回撤期 = drawdown(资金曲线)
    夏普率 = sharperatio(资金曲线)
    年化收益率 = 240f0 * (资金曲线[end] - 1f0) / length(资金曲线)
    产生目录(时间戳, 代码, 年化收益率, 最大回撤, 夏普率)
end

function 输出个股交易记录(时间戳, 代码, 最新价, 买1价, 卖1价, 手续费率, 收益率, 实际仓位)
    复利 = get(ENV, "USE_COMPLEX", "0") == "1"
    # fid = open("个股交易记录.csv", "w")
    fid′ = open("交易记录表.csv", "w")
    # io = IOBuffer()
    # # 写表头
    # write(fid, g"代码,总交易次数,总收益率,平均收益率,")
    # write(fid, g"总开多次数,总开多收益,平均开多收益,")
    # write(fid, g"总开空次数,总开空收益,平均开空收益,")
    # for i in 1:20, h in [g"持仓", g"开仓天", g"开仓时间", g"平仓天", g"平仓时间", g"开仓价格", g"平仓价格", g"收益率"]
    #     write(fid, h)
    #     print(fid, i, ',')
    # end
    # println(fid)
    write(fid′, g"代码,持仓,开仓时间,平仓时间,开仓价格,平仓价格,开仓手续费率,平仓手续费率,开仓滑点,平仓滑点,收益率,复利收益率", '\n')
    # 逐行写表体
    N, T = size(实际仓位)
    for n in 1:N
        总收益率 = 总开多收益 = 总开空收益 = zeroel(收益率)
        开仓索引 = 总交易次数 = 总开多次数 = 总开空次数 = 0
        持仓 = 开仓价格 = 之前仓位 = 开仓手续费率 = 开仓滑点 = zeroel(实际仓位)
        for t in 1:T
            当前仓位 = ifelse(t == T, 0f0, 实际仓位[n, t])
            买滑点 = (卖1价[n, t] - 最新价[n, t]) / 最新价[n, t]
            卖滑点 = (最新价[n, t] - 买1价[n, t]) / 最新价[n, t]
            之前仓位 == 当前仓位 && continue
            if abs(之前仓位) == 1 # 平仓或反手
                平仓天 = unix2date(时间戳[n, t])
                平仓时间 = unix2time(时间戳[n, t])
                平仓价格 = ifelse(之前仓位 > 0, 买1价[n, t], 卖1价[n, t])
                平仓滑点 = ifelse(之前仓位 > 0, 卖滑点, 买滑点)
                平仓手续费率 = 手续费率[n, t]
                if 复利
                    单笔收益率 = 1f0
                    for t′ in (开仓索引 + 1):t
                        单笔收益率 *= 1 + 收益率[n, t′]
                    end
                    单笔收益率 -= 1
                else
                    单笔收益率 = 0f0
                    for t′ in (开仓索引 + 1):t
                        单笔收益率 += 收益率[n, t′]
                    end
                end
                总收益率 += 单笔收益率
                总交易次数 += 1
                if 持仓 > 0
                    总开多收益 += 单笔收益率
                    总开多次数 += 1
                elseif 持仓 < 0
                    总开空收益 += 单笔收益率
                    总开空次数 += 1
                end
                # print(io, 平仓天, ',', 平仓时间, ',')
                # print(io, 开仓价格, ',', 平仓价格, ',', 单笔收益率, ',')
                print(fid′, 平仓天, ' ', 平仓时间, ',')
                print(fid′, 开仓价格, ',', 平仓价格, ',')
                复利收益率 = (之前仓位 * (平仓价格 - 开仓价格) - 开仓价格 * 开仓手续费率 - 开仓价格 * 平仓手续费率) / 开仓价格
                print(fid′, 开仓手续费率, ',', 平仓手续费率, ',')
                print(fid′, 开仓滑点, ',', 平仓滑点, ',')
                println(fid′, 单笔收益率, ',', 复利收益率)
            end
            if abs(当前仓位) == 1 # 开仓或反手
                持仓 = 当前仓位
                开仓价格 = ifelse(当前仓位 > 0, 卖1价[n, t], 买1价[n, t])
                开仓滑点 = ifelse(当前仓位 > 0, 买滑点, 卖滑点)
                开仓手续费率 = 手续费率[n, t]
                开仓天 = unix2date(时间戳[n, t])
                开仓时间 = unix2time(时间戳[n, t])
                开仓索引 = max(1, ifelse(之前仓位 == 0, t - 1, t))
                # print(io, 持仓, ',', 开仓天, ',', 开仓时间, ',')
                print(fid′, 代码[n, t], ',')
                print(fid′, 持仓, ',', 开仓天, ' ', 开仓时间, ',')
            end
            之前仓位 = 当前仓位
        end
        平均收益率 = 总收益率 ⧶ 总交易次数
        平均开多收益 = 总开多收益 ⧶ 总开多次数
        平均开空收益 = 总开空收益 ⧶ 总开空次数
        # print(fid, 代码[n, 1], ',')
        # print(fid, 总交易次数, ',', 总收益率, ',', 平均收益率, ',')
        # print(fid, 总开多次数, ',', 总开多收益, ',', 平均开多收益, ',')
        # print(fid, 总开空次数, ',', 总开空收益, ',', 平均开空收益, ',')
        # write(fid, take!(io), '\n')
    end
    # close(fid)
    close(fid′)
end

function 输出仓位评分信号(代码, 时间戳, 实际仓位, 综合评分, 虚拟信号)
    @from warnings imports filterwarnings
    @from tables imports NaturalNameWarning
    filterwarnings("ignore", category=NaturalNameWarning)
    codes, dates = 代码[:, 1], 时间戳[1, :]
    for (key, x) in pairs(@NT(实际仓位, 综合评分, 虚拟信号))
        df = DataFrame(trunc.(x, digits = 4), columns = dates, index = codes)
        to_hdf(df, "仓位评分信号.h5", key, complib = "lzo", complevel = 9)
    end
end

function 输出分钟仓位(代码, 时间戳, 最新价, 实际仓位, 收益率)
    资金曲线 = cumsum(收益率, dims = 2)
    Δt = 时间戳[1, 2] - 时间戳[1, 1]
    间隔 = round(Int, max(1, 600 / Δt))
    切片 = 1:间隔:size(实际仓位, 2)
    df = DataFrame()
    for n in 1:size(实际仓位, 1)
        code = 代码[n, 1]
        df["时间戳:$code"] = pd.to_datetime(1e9 * 时间戳[n, 切片])
        df["最新价:$code"] = 最新价[n, 切片]
        df["仓位:$code"] = 实际仓位[n, 切片]
        df["资金曲线:$code"] = 资金曲线[n, 切片]
    end
    to_csv(df, "分钟仓位.csv", index = false, encoding = "gbk")
end

function combine(dir; remove = false)
    isdir(dir) || return
    dirs = filter(glob("*%*", dir)) do dir
        !occursin("NaN", dir)
    end
    cdir = 合并汇总(dirs)
    isnothing(cdir) && return
    remove && rm(dir, force = true, recursive = true)
    mv(cdir, dir * "_" * cdir, force = true)
end

function 合并汇总(目录列表)
    length(目录列表) < 1 && return
    日期模式 = r"(\d{6})-(\d{6})"
    日期 = map(目录列表) do 目录
        m = match(日期模式, basename(目录))
        String.(m.captures)
    end
    multisort!(日期, 目录列表, by = first)
    ti, tf = minimum(first, 日期), maximum(last, 日期)
    合并目录名 = replace(basename(目录列表[1]), 日期模式 => ti * "-" * tf)
    资金和仓位曲线文件 = @. abspath(目录列表 * "/资金和仓位曲线.csv")
    资金曲线文件 = @. abspath(目录列表 * "/资金曲线.csv")
    个股交易记录文件 = @. abspath(目录列表 * "/个股交易记录.csv")
    交易记录表文件 = @. abspath(目录列表 * "/交易记录表.csv")
    每日持股明细文件 = @. abspath(目录列表 * "/每日持股明细.csv")
    仓位评分信号文件 = @. abspath(目录列表 * "/仓位评分信号.h5")
    分钟仓位文件 = @. abspath(目录列表 * "/分钟仓位.csv")
    结果名 = @indir 合并目录名 begin
        # 合并个股交易记录(个股交易记录文件)
        合并交易记录表(交易记录表文件)
        合并每日持股明细(每日持股明细文件)
        合并仓位评分信号(仓位评分信号文件)
        合并分钟仓位(分钟仓位文件)
        合并资金和仓位曲线(资金和仓位曲线文件)
        合并资金曲线(资金曲线文件)
    end
    @indir 合并目录名 报告后处理()
    目录模式 = r"-?\d+\.\d+倍\d+%\-?\d+\.\d+"
    最终目录名 = "合并汇总" * replace(合并目录名, 目录模式 => 结果名)
    mv(合并目录名, 最终目录名, force = true)
end

function 合并资金和仓位曲线(csvs)
    复利 = get(ENV, "USE_COMPLEX", "0") == "1"
    all(isfile, csvs) || return ""
    df = (dfs = filter(!isempty, pd.read_csv.(csvs, encoding = "gbk"))) |> first
    所有列 = reduce(union, map(x -> x.columns.to_list(), dfs))
    资金有关列 = filter(c -> !occursin(r"日期|份额", c), 所有列)
    for df′ in dfs[2:end]
        for c in 资金有关列
            c ∉ df′.columns && (df′[c] = 1)
            c ∉ df.columns && (df[c] = 1)
            df′[c] = 复利 ? df′[c] * df[c].iloc[end] : df′[c] + (df[c].iloc[end] - 1)
        end
        df = df.append(df′, ignore_index = true, sort = true)
    end
    to_csv(df, "资金和仓位曲线.csv", index = false, encoding = "gbk")
    资金曲线 = Array(df["资金曲线"])
    倍数, 天数 = 资金曲线[end], length(资金曲线)
    年化收益率 = 复利 ? 倍数^(240f0 / 天数) - 1 : 240f0 * (倍数 - 1f0) / 天数
    最大回撤, 最大回撤期 = drawdown(资金曲线)
    夏普率 = sharperatio(资金曲线)
    结果名 = @sprintf("%.2f倍%d%%%.1f", 1 + 年化收益率, -100最大回撤, 夏普率)
    return 结果名
end

function 合并资金曲线(csvs)
    复利 = get(ENV, "USE_COMPLEX", "0") == "1"
    all(isfile, csvs) || return ""
    df = (dfs = filter(!isempty, pd.read_csv.(csvs, encoding = "gbk"))) |> first
    所有列 = reduce(union, map(x -> x.columns.to_list(), dfs))
    资金有关列 = filter(c -> !occursin(r"日期|份额", c), 所有列)
    for df′ in dfs[2:end]
        for c in 资金有关列
            c ∉ df′.columns && (df′[c] = 1)
            c ∉ df.columns && (df[c] = 1)
            df′[c] = 复利 ? df′[c] * df[c].iloc[end] : df′[c] + (df[c].iloc[end] - 1)
        end
        df = df.append(df′, ignore_index = true, sort = true)
    end
    df = df.drop(columns = filter(c -> occursin(r"SZ|HS|ZZ", c), 所有列))
    df = 添加指数(df.groupby("日期").last()).reset_index()
    to_csv(df[所有列], "资金曲线.csv", index = false, encoding = "gbk")
    资金曲线 = Array(df["资金曲线"])
    倍数, 天数 = 资金曲线[end], length(资金曲线)
    年化收益率 = 复利 ? 倍数^(240f0 / 天数) - 1 : 240f0 * (倍数 - 1f0) / 天数
    最大回撤, 最大回撤期 = drawdown(资金曲线)
    夏普率 = sharperatio(资金曲线)
    结果名 = @sprintf("%.2f倍%d%%%.1f", 1 + 年化收益率, -100最大回撤, 夏普率)
end

function 合并个股交易记录(csvs)
    all(isfile, csvs) || return
    nstock = countlines(first(csvs)) - 1
    buffs = [IOBuffer() for n in 1:nstock]
    buff = IOBuffer()
    codes = ["" for n in 1:nstock]
    stats = zeros(nstock, 9)
    header = ""
    for csv in csvs
        fid = open(csv, "r")
        header = readline(fid, keep = true)
        for n in 1:nstock
            codes[n] = readuntil(fid, ',', keep = true)
            for i in 1:9
                write(buff, readuntil(fid, ',', keep = true))
            end
            skip(buff, -1); write(buff, '\n')
            seek(buff, 0)
            stats[n:n, :] .+= readdlm(buff, ',', Float64)
            truncate(buff, 0)
            write(buffs[n], readline(fid))
        end
        close(fid)
    end
    stats[:, 3:3:9] .= stats[:, 2:3:8] .⧶ stats[:, 1:3:7]
    fid = open("个股交易记录.csv", "w")
    write(fid, header)
    for n in 1:nstock
        write(fid, codes[n])
        writedlm(fid, stats[n:n, :], ',')
        skip(fid, -1)
        write(fid, ',', take!(buffs[n]), '\n')
    end
    close(fid)
end

function 合并每日持股明细(csvs)
    all(isfile, csvs) || return
    SMD.concat_txts("每日持股明细.csv", csvs)
end

function 合并仓位评分信号(h5s)
    all(isfile, h5s) || return
    for key in ["实际仓位", "综合评分", "虚拟信号"]
        df = pd.concat(pd.read_hdf.(h5s, key), axis = 1, sort = true)
        to_hdf(df, "仓位评分信号.h5", key, complib = "lzo", complevel = 9)
    end
end

function 合并分钟仓位(csvs)
    all(isfile, csvs) || return
    SMD.concat_txts("每日持股明细.csv", csvs)
end

function 合并交易记录表(csvs)
    all(isfile, csvs) || return
    SMD.concat_txts("交易记录表.csv", csvs)
end

function 报告后处理()
    汇总交易记录表()
    输出盈亏报告()
end

function 输出盈亏报告()
    df = pd.read_csv("资金曲线.csv", encoding = "gbk", parse_dates = ["日期"], index_col = "日期")
    df["收益率"] = df["资金曲线"].pct_change()
    df′ = pd.read_csv("交易记录表.csv", encoding = "gbk", parse_dates = ["开仓时间", "平仓时间"])
    isempty(df′) && return
    for freq in ["A"]
        srs = map(df.groupby(pd.Grouper(freq = freq))) do (t, dft)
            isempty(dft) && return Series()
            topen = df′["开仓时间"].dt.to_period(freq)
            dft′ = df′.loc[topen.eq(pd.Period(t, freq))]
            if isempty(dft′)
                sr = Series()
            else
                sr = 单周期盈亏报告(dft, dft′)
                p = freq == "A" ? Year : Month
                sr.name = Date(round(t, p))
            end
            return sr
        end
        pushfirst!(srs, Series(单周期盈亏报告(df, df′), name = "ALL"))
        filter!(!isempty, srs)
        dfc = pd.concat(srs, axis = 1, sort = true)
        dfc = freq == "A" ? dfc : dfc.T
        cn = freq == "A" ? "年" : "月"
        to_csv(dfc, cn * "盈亏报告.csv", encoding = "gbk")
    end
end

function 汇总交易记录表()
    df = pd.read_csv("交易记录表.csv", encoding = "gbk", parse_dates = ["开仓时间", "平仓时间"])
    if isempty(df)
        df["开仓时刻"] = df["平仓时刻"] = 0
    else
        df["开仓时刻"] = df["开仓时间"].dt.time
        df["平仓时刻"] = df["平仓时间"].dt.time
    end
    to_csv(df, "交易记录表.csv", encoding = "gbk", index = false)
    if !isempty(df)
        df["日期"] = pd.to_datetime(df["开仓时间"]).dt.date
        df.set_index("日期", inplace = true)
        df′ = DataFrame()
        df′["交易次数"] = df["代码"].groupby("日期").count()
        df′["最大仓位"] = df["代码"].groupby("日期").nunique().max()
        df′["平均开仓滑点"] = df["开仓滑点"].groupby("日期").mean()
        df′["平均平仓滑点"] = df["平仓滑点"].groupby("日期").mean()
        df′["平均收益率"] = df["收益率"].groupby("日期").sum() / df′["最大仓位"]
        df′["平均开仓时间"] = df["开仓时间"].view("int64").groupby("日期").mean().astype("datetime64[ns]")
        df′["平均平仓时间"] = df["平仓时间"].view("int64").groupby("日期").mean().astype("datetime64[ns]")
        to_csv(df′.reset_index(), "交易记录表汇总.csv", encoding = "gbk", index = false)
    end
    return nothing
end

function 单周期盈亏报告(df, df′)
    资金曲线 = Array(df["资金曲线"])
    收益 = 资金曲线[end] - 资金曲线[1]
    最大回撤, 最大回撤期 = drawdown(资金曲线)
    收益回撤比 = 收益 / abs(最大回撤)
    夏普率 = sharperatio(资金曲线)

    交易天数 = length(df)
    盈利天数 = (df["收益率"] > 0).sum()
    亏损天数 = (df["收益率"] < 0).sum()
    最长连续盈利天数 = SMD.lngstconsec(df["收益率"] > 0)
    最长连续亏损天数 = SMD.lngstconsec(df["收益率"] < 0)
    平均日盈利率 = df["收益率"].mean()
    平均盈利日盈利率 = df["收益率"].loc[df["收益率"] > 0].mean()
    平均亏损日亏损率 = df["收益率"].loc[df["收益率"] < 0].mean()
    日盈亏比 = 平均盈利日盈利率 / abs(平均亏损日亏损率)
    最大日盈利率 = df["收益率"].max()
    最大日亏损率 = df["收益率"].min()

    交易次数 = length(df′)
    做多次数 = (df′["持仓"] > 0).sum()
    做空次数 = 交易次数 - 做多次数
    做多收益率 = df′.loc[df′["持仓"] > 0, "收益率"].sum()
    做空收益率 = df′.loc[df′["持仓"] < 0, "收益率"].sum()
    盈利次数 = (df′["收益率"] > 0).sum()
    亏损次数 = (df′["收益率"] < 0).sum()
    平均每次交易盈利率 = df′["收益率"].mean()
    平均盈利交易盈利率 = df′["收益率"].loc[df′["收益率"] > 0].mean()
    平均亏损交易亏损率 = df′["收益率"].loc[df′["收益率"] < 0].mean()
    次盈亏比 = 平均盈利交易盈利率 / abs(平均亏损交易亏损率)
    最大单次盈利率 = df′["收益率"].max()
    最大单次亏损率 = df′["收益率"].min()
    最长连续盈利次数 = SMD.lngstconsec(df′["收益率"] > 0)
    最长连续亏损次数 = SMD.lngstconsec(df′["收益率"] < 0)
    平均持仓时间 = round((df′["平仓时间"] - df′["开仓时间"]).mean(), Second)

    nt = @NT(收益, 夏普率, 最大回撤, 最大回撤期, 收益回撤比, 平均持仓时间, 交易天数,
        盈利天数, 亏损天数, 最长连续盈利天数, 最长连续亏损天数, 平均日盈利率,
        平均盈利日盈利率, 平均亏损日亏损率, 日盈亏比, 最大日盈利率, 最大日亏损率,
        交易次数, 做多次数, 做空次数, 做多收益率, 做空收益率, 盈利次数, 亏损次数, 
        平均每次交易盈利率, 平均盈利交易盈利率, 平均亏损交易亏损率, 次盈亏比, 
        最大单次盈利率,最大单次亏损率, 最长连续盈利次数, 最长连续亏损次数)
    sr = Series(OrderedDict(pairs(nt)))

    对冲 = df.filter(regex = "对冲")
    对冲 = 对冲.iloc[end] - 对冲.iloc[1]
    sr = sr.append(对冲)
    return sr
end

function 添加指数(df)
    df_index = get_index_price()
    isnothing(df_index) && return df
    df = df.merge(df_index, how = "left", left_index = true, right_index = true)
    for pool in df_index.columns
        Δ = df["资金曲线"].diff() - df[pool].pct_change()
        df["对冲" * pool] = Δ.fillna(0).cumsum()
        df[pool] = df[pool] / df[pool].iloc[1]
    end
    return df
end