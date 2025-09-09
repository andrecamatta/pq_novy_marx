using Pkg

println("Instalando pacotes necessários...")

packages = [
    "YFinance",
    "DataFrames",
    "Dates",
    "Statistics",
    "CSV",
    "HTTP",
    "GLM",
    "Plots",
    "StatsBase",
    "LinearAlgebra",
    "Printf",
    "Distributions"
]

for pkg in packages
    println("Instalando $pkg...")
    try
        Pkg.add(pkg)
    catch e
        println("Erro ao instalar $pkg: $e")
    end
end

println("\nTodos os pacotes foram processados!")
println("Execute agora: julia low_volatility_anomaly.jl")