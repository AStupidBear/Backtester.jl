@with_kw mutable struct Strategy{S}
    sim::S
    最大持仓::Int = 0
    持仓天数::Int = 1
    是否隔夜::Bool = true
    最多交易次数::Int = 1000
end

function simulate end

function transition end

function threshgrid end

select(::Any) = false
