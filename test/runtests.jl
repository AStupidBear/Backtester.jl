using Backtester
using StandardMarketData
using HDF5Utils
using Statistics
using Dates
using Test

cd(mktempdir())

F, N, T = 2, 5, 100
特征名 = idxmap(string.("f", 1:F))
特征 = randn(Float32, F, N, T)
涨幅 = dropdims(mean(特征, dims = 1), dims = 1)
买手续费率 = 卖手续费率 = fill(1f-4, N, T)
涨停 = 跌停 = zeros(Float32, N, T)
代码 = MLString{8}[string(2t <= T ? n : N + n) for n in 1:N, t in 1:T]
ti, Δt = DateTime(2019, 1, 1), Hour(1)
时间戳 = range(ti, step = Δt, length = T ÷ 2)
时间戳 = datetime2unix.(repeat(reshape(时间戳, 1, :), N, 2))
价格 = cumsum(涨幅, dims = 2)
交易池 = ones(Float32, N, T)
data = Data(特征名, 特征, 涨幅, 买手续费率, 卖手续费率, 涨停, 跌停, 代码, 时间戳, 价格, 交易池)

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