@with_kw mutable struct Strategy{S}
    sim::S
    nhold::Int = 0
    thold::Int = 1
    overnight::Bool = true
    maxtrade::Int = 1000
end

function simulate end

function transition end

function threshgrid end

select(::Any) = false
