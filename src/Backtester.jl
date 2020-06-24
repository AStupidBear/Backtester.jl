__precompile__(true)

module Backtester

using Distributed, Statistics, Printf, Dates, DelimitedFiles
using Glob, DataStructures, Parameters, ProgressMeter, MacroTools
using PyCall, BSON, StandardMarketData, MLSuiteBase
using Iconv, HDF5Utils, PandasLite, PyCallUtils, BSONMmap
using StatsBase: corspearman

export Strategy, backtest
export @roll, @indir, @gc

include("util.jl")
include("strategy.jl")
include("backtest.jl")
include("output.jl")
include("simulator.jl")

end
