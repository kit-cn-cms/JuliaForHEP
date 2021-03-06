using Arrow, DataFrames
using Statistics, Distributions, StatsBase
#using Roots
using Optim, Roots
using PyPlot, Printf, PyCall


include("variables.jl")
include("plot_styles.jl")
using .Vars: classes

measures = DataFrame()
basedir = "/work/sschaub/JuliaForHEP/final_plotting/"
tex = true

for i in 1:10, feature in filter(x -> endswith(x, "_$i") && isdir(joinpath(basedir, x)), readdir(basedir))
    output_dir = joinpath(basedir, "$feature/")
    feature = replace(feature, Regex("_$i\$") => "")
    @show feature, i

    all_features = DataFrame(Arrow.Table(joinpath(output_dir, "all_features.arrow")))
    transform!(all_features,
        AsTable(r"output_predicted_.+") => ByRow(x -> Symbol(split(string(argmax(x)), '_')[end])) => :prediction,
    )

    for ((kind,), df) in pairs(groupby(all_features, :kind))
        #kind === :validation || continue
        split = (train=.75 * .8, test=.25, validation=.75 * .2)[kind]

        hists = DataFrame()
        for ((node, true_class), df) in pairs(groupby(df, [:prediction, :output_expected], sort=true))
            data = df[!, Symbol(:output_predicted_, node)]
            weights = Weights(df.weights ./ split)# .* (300 / 41.5))
            bins = range(.25, 1; length=16)
            values = fit(Histogram, data, weights, bins).weights
            append!(hists, DataFrame(; bins=bins[1:end-1], values, node, true_class))
        end
        @show combine(groupby(hists, [:true_class, :node]), :values => sum)
        hists = groupby(hists, [:bins, :node])
        hists = combine(hists) do x
            sig = x.true_class .=== :ttH
            #(signal=round(Int, sum(x[sig, :values])), bg=round(Int, sum(x[Not(sig), :values])))
            (signal=sum(x[sig, :values]), bg=sum(x[Not(sig), :values]))
        end
        #filter!([:signal, :bg] => (s, b) -> s + b > 0, hists)
        k = round.(Int, hists.signal .+ hists.bg)
        λ(μ) = μ .* hists.signal .+ hists.bg
        NLL(μ) = -sum(logpdf.(Poisson.(λ(μ)), k))
        μ_exp = Optim.minimizer(optimize(NLL, 0., 2.))
        z1, z2 = find_zeros(μ -> 2(NLL(μ) - NLL(μ_exp)) - 1, 0, 2)
        push!(measures, (; feature, kind, σ_μ = (z2 - z1) / 2, i))

        μ = range(.5, 1.5; length=100)
        t = NLL.(μ) .- NLL(μ_exp)

        fig, ax = subplots()
        ax.plot(μ, t)
        ax.axhline(.5; color=:grey, ls="--", lw=1)
        ax.axvline.([z1, z2]; color=:grey, ls="--", lw=1)
        fig.suptitle("Likelihood Fit ttH")
        tex && ax.set_title("\\verb|$feature|"; fontsize=16)
        ax.set_xlabel(L"\mu")
        ax.set_xlim(.5, 1.5)
        #tex && ax.set_ylabel(L"-2\log(\mathcal L(\mu) / \mathcal L(\langle \mu \rangle))")
        tex && ax.set_ylabel(L"\mathrm{NLL}(\mu) - \mathrm{NLL}(\langle \mu \rangle)")
        ax.legend([@sprintf("\$\\mu = %.3f^{+%.3f}_{-%.3f}\$", μ_exp, μ_exp-z1, z2-μ_exp)]; loc="upper center")
        annotate_cms(ax)
        display(fig)
        fig.savefig(joinpath(output_dir, "likelihood_ttH_$(kind)_15bins.pdf"))

        fig1, axs1 = subplots(ncols=2, nrows=2, figsize=(16, 14))
        foreach(
            pairs(groupby(hists, :node, sort=true)),
            axs1,
        ) do ((node,), df), ax1
            ax1.set_title("$node Node")
            #ax1.step(df.bins, df.bg; label="background")
            ax1.step(df.bins, df.signal; label="ttH Signal")
            ax1.step(df.bins, df.bg + df.signal; label="Total")
            ax1.legend()
            ax1.set_xlabel("P($node)")
            ax1.set_yscale(:log)
            #ax1.set_ylim(minimum(filter(!=(0), df.bg)) * .8, maximum(df.bg + df.signal) * 2)
            ax1.set_ylim(.05, maximum(df.bg + df.signal) * 2)
            ax1.set_ylabel("Events/Bin")
            annotate_cms(ax1)
        end
        tex && fig1.suptitle("Binning \\verb|$feature|")
        fig1.tight_layout()
        display(fig1)
        fig1.savefig(joinpath(output_dir, "binning_ttH_$(kind)_15bins.pdf"))
    end
end

#replace!(measures.feature, "lola+scalars11" => "lola+all scalars", "scalars2" => "only scalars")
Arrow.write(
    joinpath(basedir, "stddevs_mu_15bins.arrow"),
    measures,
)

begin
idx = sortperm(measures.feature; by=x -> findfirst(==(x), ["lola+" .* ["none", "tier3", "tier2+3", "all"]; "jets_as_scalars+all"; "none+all"]))
measures = measures[idx, :]
fig, ax = subplots(figsize=(11, 11))
marker = (train=:v, test=:P, validation=:o)
foreach(pairs(groupby(measures, :kind))) do ((kind,), df)
    kind === :validation || return
    df = combine(groupby(df, :feature), (:σ_μ .=> (mean, std))...)
    x = axes(df, 1)
    ax.errorbar(
        x, df.σ_μ_mean; yerr=df.σ_μ_std,
        color=:blue#=[:red; fill(:blue, length(x)-3); :green; :orange]=#, marker=marker[kind],
        lw=0, elinewidth=1, capsize=8, markersize=8,
        label=kind,
    )
end

x = unique(measures.feature)
ax.set_xticks(eachindex(x))
ax.set_xticklabels(string.("\\verb|", x, "|"); rotation=90)
ax.legend(; loc="upper right", fontsize=16, frameon=true)
ax.set_ylabel(L"\sigma_\mu")
fig.suptitle("Standard Deviations of \$\\mu\$ for Training with LoLa + X")
annotate_cms(ax)
fig.tight_layout()
fig.savefig(joinpath(basedir, "stddevs_mu_15bins.pdf"))
display(fig)
end
