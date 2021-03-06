__precompile__(true)

module Backtester

using Distributed, Statistics, Printf, Dates, DelimitedFiles, Random
using Glob, DataStructures, Parameters, ProgressMeter
using PyCall, StandardMarketData, MLSuiteBase
using Iconv, HDF5Utils, PandasLite, PyCallUtils
using StatsBase: corspearman

export Strategy, backtest, combine
export eglob, rglob
export @NT, @redirect, @indir, @gc, @roll

include("util.jl")
include("strategy.jl")
include("backtest.jl")
include("output.jl")

end
