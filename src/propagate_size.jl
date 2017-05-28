
# propagate_size.jl - propagate size of variables in AbstractExGraph, saving them into g.ctx[:sizes]

const SIZE_PROP_PHS = [:X, :Y, :Z, :i, :j, :k]

const SIZE_PROP_RULES =
    Dict((:*, [0, 0]) => :(()),
         (:*, [2, 1]) => :((_1[1])),
         (:*, [2, 2]) => :((_1[1], _2[2])),
         (:.*, [1, 1]) => :((_1..., _2...)))

const SIZE_PROP_RULES2 =
    Dict(:(Z[i,j] = X[i,j] .* Y[i]) => :(size__(X)))


function subs_size(ex::Expr, sizes::Dict)
    size_exs = findex(:(size__(_)), ex)
    st = Dict{Any,Any}()
    for size_ex in size_exs
        var, idxs = split_indexed(size_ex.args[2])
        subsex = @get(sizes, var, error("Can't find size for $var in $ex"))
        st[size_ex] = subsex
    end
    return subs(ex, st)
end

subs_size(x, sizes::Dict) = x


function propagate_size!(g::AbstractExGraph, nd::ExNode{:input})  
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    sizes[varname(nd)] = :(size($(varname(nd))))
end

function propagate_size!(g::AbstractExGraph, nd::ExNode{:constant})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    sz = size(getvalue(nd))
    sizes[varname(nd)] = Expr(:tuple, sz...)
end


function propagated_size(g::AbstractExGraph, nd::ExNode{:(=)})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    dep = dependencies(nd)[1]
    idxs = get_indices(to_expr(nd))
    if length(idxs) == 0 || (length(idxs) == 2 && idxs[1] == idxs[2])
        # not indexed or indices on LHS and RHS are equal
        return sizes[dep]
    elseif isempty(varidxs(nd))
        # special case for scalars (produce nicer expression then the following)
        return Expr(:tuple)
    else
        # perm = indexperm(varidxs(nd), get_indices(expr(nd))[1])
        perm = [idx for idx in findperm(idxs[1], idxs[2]) if idx != 0]
        dep_sz = sizes[dep]
        var_sz_maybe = tryrewrite(dep_sz, :(size(_V)), :(size(_V, $(perm...))))
        if !isnull(var_sz_maybe)
            return get(var_sz_maybe)
        elseif length(perm) == 1
            # special case - only one index
            return simplify(:($(dep_sz)[$(perm[1])]))
        else
            return simplify(:($(dep_sz)[[$(perm...)]]))
        end
    end
end

function propagate_size!(g::AbstractExGraph, nd::ExNode{:(=)})
    sizes = @get_or_create(g.ctx, :sizes, Dict())    
    haskey(sizes, varname(nd)) && return
    sizes[varname(nd)] = propagated_size(g, nd)
end


function graph_inputs(g::AbstractExGraph)
    res = Dict()
    for nd in g.tape
        if isa(nd, ExNode{:input})
            res[varname(nd)] = getvalue(nd)
        end
    end
    return res
end

function ndims_from_size(g::AbstractExGraph, var::Symbol)
    inputs = graph_inputs(g)
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    evex = subs(sizes[var], inputs)
    sz = eval(evex)
    return length(sz)
end


function infer_perm_size(vidxs::Vector, depidxs::Vector, dep_sz)
    perm = findperm(vidxs, depidxs)
    var_sz_maybe = tryrewrite(dep_sz, :(size(_V)), :(size(_V, $(perm...))))
    if !isnull(var_sz_maybe)
        return get(var_sz_maybe)
    elseif length(perm) == 0
        # special case - scalar
        return Expr(:tuple)
    elseif length(perm) == 1
        # special case - only one index
        return simplify(:($(dep_sz)[$(perm[1])]))
    else
        return simplify(:($(dep_sz)[[$(perm...)]]))
    end
end


function try_rewrite_size(ex::Expr, sizes::Dict)
    for (pat, rpat) in SIZE_PROP_RULES2
        rex = tryrewrite(ex, pat, rpat; phs=SIZE_PROP_PHS)
        if !isnull(rex)
            sz_ex = subs_size(get(rex), sizes)
            return Nullable{Expr}(sz_ex)
        end
    end
    return Nullable{Expr}()
end


function propagate_size!(g::AbstractExGraph, nd::ExNode{:call})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    deps = dependencies(nd)    
    if !all(dep -> haskey(g, dep), deps)
        error("Can't propagate size of $nd: not all deps present in graph")
    end
    dep_dims = [ndims_from_size(g, dep) for dep in deps]
    sz_key = (getexpr(nd).args[1], dep_dims)
    vidxs = varidxs(nd)
    vname = varname(nd)
    depidxs = forall_indices(getexpr(nd))
    sz_ex_from_rule = try_rewrite_size(to_expr(nd), sizes)
    if isempty(vidxs)
        # special case for scalars (produce nicer expression then the following)
        sizes[vname] = Expr(:tuple)
    elseif !isnull(sz_ex_from_rule)
        sizes[vname] = get(sz_ex_from_rule)
    elseif haskey(SIZE_PROP_RULES, sz_key)
        rpat = SIZE_PROP_RULES[sz_key]
        dep_sizes = [sizes[dep] for dep in deps]
        size_names = [Symbol("_$i") for i=1:length(deps)]
        st = Dict(zip(size_names, dep_sizes))
        size_ex = simplify(subs(rpat, st))
        sizes[varname(nd)] = size_ex
    elseif getexpr(nd).args[1] == :.*
        warn("Not tested!")
        each_dep = get_var_names(getexpr(nd))
        each_dep_idxs = get_indices(getexpr(nd))
        sz_parts = []
        # for each var index find the corresponding dependency and index position
        # make index part as (dep_size[index_position])
        # then make a tuple of all size parts
        for idx in vidxs
            for (cur_dep, cur_dep_idxs) in zip(each_dep, each_dep_idxs)
                i = findfirst(cur_dep_idxs, idx)
                if i != 0
                    push!(sz_parts, :($(sizes[cur_dep])[$i]))
                    continue
                end
            end
        end
        sizes[vname] = simplify(Expr(:tuple, sz_parts...))
    elseif all(idxs -> idxs == vidxs, get_indices(getexpr(nd)))
        # all indices equal - assuming simple broadcasting
        sizes[vname] = sizes[deps[1]]
    else
        # assuming broadcasting
        i = findmax(dep_dims)[2]
        rhs_sz = sizes[deps[i]]
        sizes[vname] = infer_perm_size(vidxs, depidxs, rhs_sz)
    end    
end


function propagate_size!(g::AbstractExGraph, nd::ExNode{:bcast})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    deps = dependencies(nd)
    dep_dims = [ndims_from_size(g, dep) for dep in deps]
    i = findmax(dep_dims)[2]
    size_ex = sizes[deps[i]]
    sizes[varname(nd)] = size_ex
end


function propagate_size!(g::AbstractExGraph)
    for nd in g.tape
        propagate_size!(g, nd)
    end
end
