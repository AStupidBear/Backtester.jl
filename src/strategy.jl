@with_kw mutable struct Strategy{S}
    sim::S
    nhold::Int = 0
    thold::Int = 1
    rolltrn::String = "3Y"
    rolltst::String = "6M"
    overnight::Bool = true
    maxtrade::Int = 1000
    feats2drop::Vector = []
end

function fit!(strtg::Strategy, data; ka...)
    @unpack sim, feats2drop = strtg
    data = dropfeats(data, feats2drop)
    fit!(sim, data; ka...)
    fit_thresh!(strtg, data; ka...)
    BSON.@save "strategy.bson" strtg
    backtest(strtg, data, mode = "test")
end

function fit_code!(ffit, strtg, data)
    for code in codesof(data)
        ffit(strtg, data[code])
    end
end

function fit_roll!(ffit, strtg, data)
    @unpack rolltrn, rolltst = strtg
    @roll for (dtrn, dtst) in roll(data, rolltrn, rolltst)
        ffit(strtg, dtrn)
        @indir "roll" backtest(strtg, dtst, mode = "test")
    end
end

function fit_thresh!(strtg, data; pattern = "θ")
    params = map(threshgrid(strtg.sim)) do param
        filter(z -> occursin(pattern, z[1]), param)
    end
    isempty(params) && return 
    res = @showprogress map(params) do param
        update_param!(strtg, param)
        param, backtest(strtg, data)
    end
    df = DataFrame()
    dicts = first.(res)
    pnls = last.(res)
    for c in keys(dicts[1])
        df[c] = map(x -> x[c], dicts)
    end
    df["pnl"] = pnls
    df = df.pivot_table(index = "θc", columns = "θo")
    trange = Dates.format.(datespan(data), "yymmdd")
    csv = @sprintf("thresh_%s-%s.csv", trange...)
    to_csv(df, csv, encoding = "gbk")
    paramᵒ, pnlᵒ = sort(res, by = last)[end]
    println([string(k, ':', v, ' ') for (k, v) in paramᵒ]...)
    update_param!(strtg, paramᵒ)
end