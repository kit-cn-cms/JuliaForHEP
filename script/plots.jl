using Arrow, DataFrames, Flux
using PyPlot
using Printf
using Trapz

_reshape(a, dims...) = invoke(Base._reshape, Tuple{AbstractArray, Base.Dims}, a, Base._reshape_uncolon(a, dims))

#layer_params = DataFrame(Arrow.Table(joinpath(output_dir, "layer_params.arrow")))
all_features = DataFrame(Arrow.Table(joinpath(output_dir, "all_features.arrow")))

fig1, axs1 = subplots(ncols=2, nrows=2, figsize=(12, 9))
linestyles = (train = "-", test = "--", validation="-.")
for ((kind,), df) in pairs(groupby(all_features, :kind))
    kind !== :test && foreach(
        pairs(groupby(df, :output_expected, sort=true)),
        [:C0, :C1, :C2, :C3],
    ) do ((class,), df), color
        foreach(axs1, classes) do ax1, class_predicted
            ax1.hist(
                df[!, Symbol(:output_predicted_, class_predicted)];
                label="true $class ($kind)", density=true,
                bins=30, histtype=:step, color, ls=linestyles[kind],
            )
        end
    end

    ŷ = mapreduce(vcat, classes) do class
        df[!, Symbol(:output_predicted_, class)]'
    end
    outputs_onehot = Flux.onehotbatch(df.output_expected, classes)

    confusion_mat = sum(
        _reshape(Flux.onehotbatch(Flux.onecold(ŷ, classes), classes), 1, 4, :) .===
            _reshape(outputs_onehot, 4, 1, :);
        dims=3,
    )
    confusion_mat = confusion_mat ./ sum(confusion_mat; dims=2)

    fig, ax = subplots()

    img = ax.imshow(confusion_mat)
    for i in axes(confusion_mat, 1), j in axes(confusion_mat, 2)
        ax.text(j-1, i-1, @sprintf("%.3g", confusion_mat[i, j]), ha=:center, va=:center)
    end
    ax.set_xlabel("predicted output")
    ax.set_xticks(eachindex(classes).-1)
    ax.set_xticklabels(classes)
    ax.set_ylabel("true output")
    ax.set_yticks(eachindex(classes).-1)
    ax.set_yticklabels(classes)
    fig.colorbar(img)
    fig.suptitle(kind)
    fig.savefig(joinpath(output_dir, "confusion_matrix_$kind.pdf"))

    #fig, axes = subplots(ncols=6, nrows=8, figsize=(25, 25))
    #idx = df.output_predicted_Hbb .> .5
    #foreach(Vars.variables["ge4j_ge3t"], axes) do i, ax
    #    ax.hist(
    #        [df[idx, i], df[.!idx, i]],
    #        label=["predicted Hbb", "predicted Zbb"],
    #        bins=20, rwidth=.8, density=true,
    #    )
    #    ax.set_title("feature $i")
    #    ax.legend()
    #end
    #fig.suptitle(kind)
    #fig.tight_layout()
    #fig.savefig(joinpath(output_dir, "input_features_hist_$kind.pdf"))

    fig_eff, axs_eff = subplots(ncols=2, nrows=2, figsize=(12, 9))
    fig_roc, axs_roc = subplots(ncols=2, nrows=2, figsize=(12, 9))
    for (ax_roc, ax_eff, class) in zip(axs_roc, axs_eff, classes)
        predictions_positives = df[df.output_expected .=== class, Symbol(:output_predicted_, class)]
        predictions_background = df[df.output_expected .!== class, Symbol(:output_predicted_, class)]
        eff_s, = ax_eff.hist(
            predictions_positives;
            cumulative=true, bins=range(0, 1; length=30), density=true, histtype=:step,
            label="signal efficiency"
        )
        eff_bg, = ax_eff.hist(
            predictions_background;
            cumulative=true, bins=range(0, 1; length=30), density=true, histtype=:step,
            label="background efficiency",
        )
        ax_eff.legend()
        ax_eff.set_ylabel("efficiency")
        ax_eff.set_xlabel("1 - specificity")
        ax_eff.set_title("$class")

        x, y = 1 .- eff_s, eff_bg
        ax_roc.plot(x, y)
        idx = sortperm(x)
        auc = trapz(x[idx], y[idx])
        ax_roc.text(.2, .2, @sprintf("AUC = %.3f", auc); fontsize=16)
        ax_roc.set_xlim(0, 1)
        ax_roc.set_ylim(0, 1)
        ax_roc.set_ylabel("1 - background efficiency")
        ax_roc.set_xlabel("signal efficiency")
        ax_roc.set_title("$class")
    end
    fig_eff.suptitle("Efficiencies - $kind")
    fig_eff.tight_layout()
    fig_eff.savefig(joinpath(output_dir, "efficiencies_$kind.pdf"))

    fig_roc.suptitle("ROC curves - $kind")
    fig_roc.tight_layout()
    fig_roc.savefig(joinpath(output_dir, "roc_curves_$kind.pdf"))
end

foreach(axs1, classes) do ax1, class_predicted
    ax1.set_title(String(class_predicted))
    ax1.set_xlabel("p($class_predicted)")
    ax1.legend()
end
#fig1.suptitle("Predicted Hbb")
fig1.tight_layout()
fig1.savefig(joinpath(output_dir, "output_features_hist.pdf"))
