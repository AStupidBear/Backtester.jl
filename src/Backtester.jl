__precompile__(true)

module Backtester

using Distributed, Statistics, Printf, Dates, DelimitedFiles, SHA
using Glob, DataStructures, Parameters, ProgressMeter, MacroTools
using JSON, PyCall, BSON, StandardMarketData, Iconv
using HDF5Utils, PandasLite, PyCallUtils, BSONMmap, MLSuiteBase
using StatsBase: corspearman

export Strategy, fit!, fit_code!, fit_roll!, fit_thresh!, backtest
export update_param!, bash, get_index_price, unsqueeze
export @roll, @indir, @staticvar, @staticdef, @gc

include("util.jl")
include("strategy.jl")
include("backtest.jl")
include("output.jl")
include("simulator.jl")

end
