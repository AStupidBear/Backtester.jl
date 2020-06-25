function update_param!(o, param)
    for s in fieldnames(typeof(o))
        x = getfield(o, s)
        if fieldcount(typeof(x)) > 0
            update_param!(x, param)
        else
            x′ = get(param, string(s), x)
            x !== x′ && setproperty!(o, s, x′)
        end
    end
end

function update_param!(o::PyObject, param)
    for (k, v) in param
        s = Symbol(k)
        PyCall.hasproperty(o, s) &&
        setproperty!(o, s, v)
    end
end

function gridsearch(f, bounds)
    xs = collect(Iterators.product(bounds...))
    ys = pmap(f ∘ collect, xs)
    yᵒ, i = findmin(ys)
    x = xs[i]
    return x, y, xs, ys
end

amploss(x, λ = zero(x)) = ifelse(x < zero(x), λ, one(x)) * x

entropy(p, ϵ = 1f-9) = -sum(p .* log.(p .+ ϵ)) / log(length(p))

mae(x, ϵ = 1f-2) = sum(z -> max(abs(z) - ϵ , zero(x)), x) / length(x)

eglob(pattern::String, prefix = pwd()) = eglob(Regex(pattern), prefix)

eglob(pattern::Regex, prefix = pwd()) = glob([pattern], prefix)

rglob(pattern, prefix = pwd()) = Iterators.flatten(map(rdf -> glob(pattern, rdf[1]), walkdir(prefix)))

function lcp(strs)
    io = IOBuffer()
    if !isempty(strs)
        i = 1
        while all(i ≤ length(s) for s in strs) &&
            all(s == strs[1][i] for s in getindex.(strs, i))
            print(io, strs[1][i])
            i += 1
        end
    end
    return String(take!(io))
end


function findtoroot(file)
    dir = pwd()
    while !isfile(file)
        dir = joinpath(dir, "..")
        file = joinpath(dir, file)
    end
    return realpath(file)
end

macro everydir(dir, ex)
    cwd = gensym()
    dir_quot, cwd_quot = Expr(:$, dir), Expr(:$, cwd)
    quote
        mkpath($dir); $cwd = pwd(); @everywhere cd($dir_quot)
        try $ex finally @everywhere cd($cwd_quot) end
    end |> esc
end

macro indir(dir, ex)
    cwd = gensym()
    quote
        mkpath($dir); $cwd = pwd(); cd($dir)
        try $ex finally cd($cwd) end
    end |> esc
end

macro roll(ex)
    quote
        if isdir("roll")
            date = Dates.format(today(), "yymmdd")
            mv("roll", "roll-" * date, force = true)
        end
        $(esc(ex))
        combine(glob("*%*", "roll"))
    end
end

macro NT(xs...)
    @static if VERSION >= v"0.7.0"
        xs = [:($x = $x) for x in xs]
        esc(:(($(xs...),)))
    else
        esc(:(@NT($(xs...))($(xs...))))
    end
end

macro redirect(src, ex)
    src = src == :devnull ? "/dev/null" : src
    quote
        io = open($(esc(src)), "a")
        o, e = stdout, stderr
        redirect_stdout(io)
        redirect_stderr(io)
        try
            $(esc(ex)); sleep(0.01)
        finally
            flush(io); close(io)
            redirect_stdout(o)
            redirect_stderr(e)
        end
    end
end

zeroel(x) = zero(eltype(x))

oneel(x) = one(eltype(x))

lvcha(资金曲线) = 10000 * mean(amploss.(diff(资金曲线), 2f0))

function cumsum_reset(x, r)
    z = zero(x)
    s = zero(eltype(x))
    for i in 1:length(x)
        s = ifelse(r[i], zero(s), s + x[i])
        z[i] = s
    end
    return z
end

function drawdown(资金曲线)
    最大值 = 当前回撤 = 最大回撤 = zeroel(资金曲线)
    回撤期 = 最大回撤期 = 0
    for i in eachindex(资金曲线)
        回撤期 = ifelse(资金曲线[i] > 最大值, 0, 回撤期 + 1)
        最大值 = max(最大值, 资金曲线[i])
        当前回撤 = (资金曲线[i] / 最大值 - 1)
        最大回撤 = min(当前回撤, 最大回撤)
        最大回撤期 = max(最大回撤期, 回撤期)
    end
    return 最大回撤, 最大回撤期
end

function pct_change(x, T)
    ϵ = eps(eltype(x))
    z = zero(x)
    for t in 1:length(x)
        t′ = clamp(t - T, 1, length(x))
        t1, t2 = minmax(t, t′)
        z[t] = (x[t2] - x[t1]) / (x[t1] + ϵ)
    end
    return z
end

@noinline function sharperatio(资金曲线, 一年天数 = 224)
    日收益率 = pct_change(资金曲线, 1)
    年化夏普率 = eltype(资金曲线)(mean(日收益率) ⧶ std(日收益率) * √一年天数)
end

@noinline function sortinoratio(资金曲线, 一年天数 = 224)
    日收益率 = pct_change(资金曲线, 1)
    eltype(r)(mean(日收益率) ⧶ std(min.(日收益率, 0)) * √一年天数)
end

function moving_max(A, k)
    B = similar(A)
    Q = Int[1]
    sizehint!(Q, length(A))
    for t = 1 : k
        if A[t] >= A[Q[1]]
            Q[1] = t
        end
        B[t] = A[Q[1]]
    end
    for t = (k + 1):length(A)
        while !isempty(Q) && A[t] >= A[Q[end]]
            pop!(Q)
        end
        while !isempty(Q) && Q[1] <=  t - k
            popfirst!(Q)
        end
        push!(Q, t)
        B[t] = A[Q[1]]
    end
    return B
end

function moving_min(A, k)
    B = similar(A)
    Q = Int[1]
    sizehint!(Q, length(A))
    for t = 1 : k
        if A[t] <= A[Q[1]]
            Q[1] = t
        end
        B[t] = A[Q[1]]
    end
    for t = (k + 1):length(A)
        while !isempty(Q) && A[t] <= A[Q[end]]
            pop!(Q)
        end
        while !isempty(Q) && Q[1] <=  t - k
            popfirst!(Q)
        end
        push!(Q, t)
        B[t] = A[Q[1]]
    end
    return B
end

parseenv(key, default::String) = get(ENV, string(key), string(default))

function parseenv(key, default::T) where T
    str = get(ENV, string(key), string(default))
    if hasmethod(parse, (Type{T}, String))
        parse(T, str)
    else
        include_string(Main, str)
    end
end

function hasnan(x)
    for i in eachindex(x)
        isnan(x[i]) && return true
    end
    false
end

Base.merge(grids::AbstractArray{<:AbstractDict}...) = map(ds -> merge(ds...), Iterators.product(grids...))

bash(str) = run(`bash -c $str`)

macro staticvar(init)
    var = gensym()
    __module__.eval(:(const $var = $init))
    var = esc(var)
    quote
        global $var
        $var
    end
end

macro staticdef(ex)
    @capture(ex, name_::T_ = val_) || error("invalid @staticvar")
    ref = Ref{__module__.eval(T)}()
    set = Ref(false)
    :($(esc(name)) = if $set[]
        $ref[]
    else
        $ref[] = $(esc(ex))
        $set[] = true
        $ref[]
    end)
end

macro gc(exs...)
    Expr(:block, [:($ex = 0) for ex in exs]..., :(@eval GC.gc())) |> esc
end

function lockphase(x, P)
    P == 1 && return x
    N, T = size(x)
    x′ = zeros(Float32, N * P, T)
    for ph in 1:P, t in ph:P:T, n in 1:N
        n′ = n + N * (ph - 1)
        x′[n′, t] = x[n, t]
    end
    return x′
end

function get_index_price(;update = false)
    haskey(ENV, "JQ_USER") || return nothing
    parquet = joinpath(DEPOT_PATH[1], "index.parquet")
    if isfile(parquet) && !update
        return pd.read_parquet(parquet)
    end
    @from jqdatasdk imports auth, get_price
    auth(ENV["JQ_USER"], ENV["JQ_PASS"])
    dfs = DataFrame[]
    for (pool, code) in zip(["SZ50", "HS300", "ZZ500", "ZZ1000"], 
        ["000016.XSHG", "000300.XSHG", "000905.XSHG", "000852.XSHG"])
        df = get_price(code, start_date = "2010-01-01", end_date = string(Date(now())), fields = "close")
        df.rename(columns = Dict("close" => pool), inplace = true)
        push!(dfs, df)
    end
    df = pdhcat(dfs...)
    df = df.ffill().bfill()
    df.to_parquet(parquet)
    return df
end

macro roll(ex)
    quote
        if isdir("roll")
            date = Dates.format(today(), "yymmdd")
            mv("roll", "roll-" * date, force = true)
        end
        $(esc(ex))
        combine(glob("*%*", "roll"))
    end
end

macro indir(dir, ex)
    cwd = gensym()
    quote
        mkpath($dir); $cwd = pwd(); cd($dir)
        try $ex finally cd($cwd) end
    end |> esc
end

function multisort(xs::AbstractArray...; ka...)
    p = sortperm(first(xs); ka...)
    map(x -> x[p], xs)
end

function multisort!(xs::AbstractArray...; ka...)
    p = sortperm(first(xs); ka...)
    for x in xs
        permute!(x, p)
    end
    return xs
end

unsqueeze(xs, dim) = reshape(xs, (size(xs)[1:dim-1]..., 1, size(xs)[dim:end]...))

function read_csv(csv, a...; ka...)
    cp(csv, "tmp.csv", force = true)
    df = pd.read_csv("tmp.csv", a...; ka...)
    rm("tmp.csv", force = true)
    return df
end

function to_csv(df, csv, a...; ka...)
    df.to_csv("tmp.csv", a...; ka...)
    cp("tmp.csv", csv, force = true)
    return csv
end

function read_hdf(h5, a...; ka...)
    cp(h5, "tmp.h5", force = true)
    df = pd.read_hdf("tmp.h5", a...; ka...)
    rm("tmp.h5", force = true)
    return df
end

function to_hdf(df, h5, a...; ka...)
    df.to_hdf("tmp.h5", a...; ka...)
    cp("tmp.h5", h5, force = true)
    return h5
end