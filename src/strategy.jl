@with_kw mutable struct Strategy{S}
    sim::S
    最大持仓::Int = 0
    持仓天数::Int = 1
    是否隔夜::Bool = true
    最多交易次数::Int = 1000
    禁止平今::Bool = false
    夜盘最早开仓时间::Float32 = 0
    夜盘最晚开仓时间::Float32 = Inf
    夜盘最晚平仓时间::Float32 = Inf
    早盘最早开仓时间::Float32 = 0
    早盘最晚开仓时间::Float32 = Inf
    早盘最晚平仓时间::Float32 = Inf
end

function simulate end

function transition end

function threshgrid end

select(::Any) = false
