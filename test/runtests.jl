using Backtester
using StandardMarketData
using HDF5Utils
using Statistics
using Dates
using Test

# cd(mktempdir())

F, N, T = 2, 5, 100

特征名 = idxmap(string.("f", 1:F))
特征 = randn(Float32, F, N, T)
涨幅 = reshape(mean(特征, dims = 1) / 10, N, T)
涨幅 = circshift(涨幅, (0, 1))
ti, Δt = DateTime(2019, 1, 1), Hour(1)
时间戳 = range(ti, step = Δt, length = T ÷ 2)
时间戳 = datetime2unix.(repeat(reshape(时间戳, 1, :), N, 2))
代码 = MLString{8}[string(2t <= T ? n : N + n) for n in 1:N, t in 1:T]
最新价 = 买1价 = 卖1价 = 1 .+ cumsum(涨幅, dims = 2)
手续费率 = fill(0f-4, N, T)
涨停 = 跌停 = zeros(Float32, N, T)
交易池 = ones(Float32, N, T)
data = Data(特征名, 特征, 涨幅, 时间戳, 代码, 最新价, 买1价, 卖1价, 手续费率, 涨停, 跌停, 交易池)

import Backtester: simulate, transition
mutable struct SignalSimulator{S}
    sgnl::S
end
simulate(sim::SignalSimulator, data) = (sim.sgnl, sim.sgnl)
transition(sim::SignalSimulator) = (s, a) -> a

sgnl = reshape(sum(特征, dims = 1), N, T)
sgnl = ifelse.(sgnl .> 0, 1f0, -1f0)
strat = Strategy(sim = SignalSimulator(sgnl))
backtest(strat, data, mode = "train")
backtest(strat, data, mode = "test")