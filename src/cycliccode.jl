# Copyright (c) 2021, Eric Sabo
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

mutable struct CyclicCode <: AbstractCyclicCode
    F::FqNmodFiniteField # base field
    E::FqNmodFiniteField # splitting field
    R::FqNmodPolyRing # polynomial ring of generator polynomial
    β::fq_nmod # n-th root of primitive element of splitting field
    n::Int # length
    k::Int # dimension
    d::Union{Int, Missing} # minimum distance
    b::Int # offset
    δ::Int # BCH bound
    HT::Int # Hartmann-Tzeng refinement
    lbound::Int # lower bound on d
    ubound::Int # upper bound on d
    qcosets::Vector{Vector{Int}}
    qcosetsreps::Vector{Int}
    defset::Vector{Int}
    g::fq_nmod_poly
    h::fq_nmod_poly
    e::fq_nmod_poly
    G::fq_nmod_mat
    Gorig::Union{fq_nmod_mat, Missing}
    H::fq_nmod_mat
    Horig::Union{fq_nmod_mat, Missing}
    Gstand::fq_nmod_mat
    Hstand::fq_nmod_mat
    P::Union{fq_nmod_mat, Missing} # permutation matrix for G -> Gstand
    weightenum::Union{WeightEnumerator, Missing}
end

mutable struct BCHCode <: AbstractBCHCode
    F::FqNmodFiniteField # base field
    E::FqNmodFiniteField # splitting field
    R::FqNmodPolyRing # polynomial ring of generator polynomial
    β::fq_nmod # n-th root of primitive element of splitting field
    n::Int # length
    k::Int # dimension
    d::Union{Int, Missing} # minimum distance
    b::Int # offset
    δ::Int # BCH bound
    HT::Int # Hartmann-Tzeng refinement
    lbound::Int # lower bound on d
    ubound::Int # upper bound on d
    qcosets::Vector{Vector{Int}}
    qcosetsreps::Vector{Int}
    defset::Vector{Int}
    g::fq_nmod_poly
    h::fq_nmod_poly
    e::fq_nmod_poly
    G::fq_nmod_mat
    Gorig::Union{fq_nmod_mat, Missing}
    H::fq_nmod_mat
    Horig::Union{fq_nmod_mat, Missing}
    Gstand::fq_nmod_mat
    Hstand::fq_nmod_mat
    P::Union{fq_nmod_mat, Missing} # permutation matrix for G -> Gstand
    weightenum::Union{WeightEnumerator, Missing}
end

mutable struct ReedSolomonCode <: AbstractReedSolomonCode
    F::FqNmodFiniteField # base field
    E::FqNmodFiniteField # splitting field
    R::FqNmodPolyRing # polynomial ring of generator polynomial
    β::fq_nmod # n-th root of primitive element of splitting field
    n::Int # length
    k::Int # dimension
    d::Union{Int, Missing} # minimum distance
    b::Int # offset
    δ::Int # BCH bound
    HT::Int # Hartmann-Tzeng refinement
    lbound::Int # lower bound on d
    ubound::Int # upper bound on d
    qcosets::Vector{Vector{Int}}
    qcosetsreps::Vector{Int}
    defset::Vector{Int}
    g::fq_nmod_poly
    h::fq_nmod_poly
    e::fq_nmod_poly
    G::fq_nmod_mat
    Gorig::Union{fq_nmod_mat, Missing}
    H::fq_nmod_mat
    Horig::Union{fq_nmod_mat, Missing}
    Gstand::fq_nmod_mat
    Hstand::fq_nmod_mat
    P::Union{fq_nmod_mat, Missing} # permutation matrix for G -> Gstand
    weightenum::Union{WeightEnumerator, Missing}
end

function _generatorpolynomial(R::FqNmodPolyRing, β::fq_nmod, Z::Vector{Int})
    # from_roots(R, [β^i for i in Z]) - R has wrong type for this
    g = one(R)
    x = gen(R)
    for i in Z
        g *= (x - β^i)
    end
    return g
end
_generatorpolynomial(R::FqNmodPolyRing, β::fq_nmod, qcosets::Vector{Vector{Int}}) = _generatorpolynomial(R, β, vcat(qcosets...))

function _generatormatrix(F::FqNmodFiniteField, n::Int, k::Int, g::fq_nmod_poly)
    # if g = x^10 + α^2*x^9 + x^8 + α*x^7 + x^3 + α^2*x^2 + x + α
    # g.coeffs = [α  1  α^2  1  0  0  0  α  1  α^2  1]
    coeffs = collect(coefficients(g))
    len = length(coeffs)
    k + len - 1 <= n || error("Too many coefficients for $k shifts in _generatormatrix.")

    G = zero_matrix(F, k, n)
    for i in 1:k
        G[i, i:i + len - 1] = coeffs
    end
    return G
end

"""
    definingset(nums::Vector{Int}, q::Int, n::Int, flat::Bool=true)

Returns the set of `q`-cyclotomic cosets of the numbers in `nums` modulo
`n`.

If `flat` is set to true, the result will be a single flattened and sorted
array.
"""
function definingset(nums::Vector{Int}, q::Int, n::Int, flat::Bool=true)
    arr = Vector{Vector{Int}}()
    arrflat = Vector{Int}()
    for x in nums
        Cx = cyclotomiccoset(x, q, n)
        if Cx[1] ∉ arrflat
            arrflat = [arrflat; Cx]
            push!(arr, Cx)
        end
    end

    flat && return sort!(vcat(arr...))
    return arr
end

function _idempotent(g::fq_nmod_poly, h::fq_nmod_poly, n::Int)
    # solve 1 = a(x) g(x) + b(x) h(x) for a(x) then e(x) = a(x) g(x) mod x^n - 1
    d, a, b = gcdx(g, h)
    return mod(g * a, gen(parent(g))^n - 1)
end

# MattsonSolomontransform(f, n)
# inverseMattsonSolomontransform

"""
    field(C::AbstractCyclicCode)

Return the base field of the generator matrix as a Nemo object.
"""
field(C::AbstractCyclicCode) = C.F

"""
    splittingfield(C::AbstractCyclicCode)

Return the splitting field of the generator polynomial as a Nemo object.
"""
splittingfield(C::AbstractCyclicCode) = C.E

"""
    polynomialring(C::AbstractCyclicCode)

Return the polynomial ring of the generator polynomial as a Nemo object.
"""
polynomialring(C::AbstractCyclicCode) = C.R

"""
    primitiveroot(C::AbstractCyclicCode)

Return the primitive root of the splitting field as a Nemo object.
"""
primitiveroot(C::AbstractCyclicCode) = C.β

"""
    offset(C::AbstractBCHCode)

Return the offset of the BCH code.
"""
offset(C::AbstractBCHCode) = C.b

"""
    designdistance(C::AbstractBCHCode)

Return the design distance of the BCH code.
"""
designdistance(C::AbstractBCHCode) = C.δ

"""
    mindistlowerbound(C::AbstractCyclicCode)

Return a lower bound on the minimum distance of the code.

At the moment, this is only the BCH bound with the Hartmann-Tzeng Bound
refinement. The minimum distance is returned if known.
"""
mindistlowerbound(C::AbstractCyclicCode) = C.δ

"""
    qcosets(C::AbstractCyclicCode)

Return the q-cyclotomic cosets of the cyclic code.
"""
qcosets(C::AbstractCyclicCode) = C.qcosets

"""
    qcosetsreps(C::AbstractCyclicCode)

Return the set of representatives for the q-cyclotomic cosets of the cyclic code.
"""
qcosetsreps(C::AbstractCyclicCode) = C.qcosetsreps

"""
    definingset(C::AbstractCyclicCode)

Return the defining set of the cyclic code.
"""
definingset(C::AbstractCyclicCode) = C.defset

"""
    zeros(C::AbstractCyclicCode)

Return the zeros of `C`.
"""
zeros(C::AbstractCyclicCode) = [C.β^i for i in C.defset]

"""
    nonzeros(C::AbstractCyclicCode)

Return the nonzeros of `C`.
"""
nonzeros(C::AbstractCyclicCode) = [C.β^i for i in setdiff(0:C.n - 1, C.defset)]

"""
    generatorpolynomial(C::AbstractCyclicCode)

Return the generator polynomial of the cyclic code as a Nemo object.
"""
generatorpolynomial(C::AbstractCyclicCode) = C.g

"""
    paritycheckpolynomial(C::AbstractCyclicCode)

Return the parity-check polynomial of the cyclic code as a Nemo object.
"""
paritycheckpolynomial(C::AbstractCyclicCode) = C.h

"""
    idempotent(C::AbstractCyclicCode)

Return the idempotent (polynomial) of the cyclic code as a Nemo object.
"""
idempotent(C::AbstractCyclicCode) = C.e

"""
    isprimitive(C::AbstractBCHCode)

Return `true` if the BCH code is primitive.
"""
isprimitive(C::AbstractBCHCode) = C.n == Int(order(C.F)) - 1

"""
    isnarrowsense(C::AbstractBCHCode)

Return `true` if the BCH code is narrowsense.
"""
isnarrowsense(C::AbstractBCHCode) = iszero(C.b) # should we define this as b = 1 instead?

"""
    isreversible(C::AbstractCyclicCode)

Return `true` if the cyclic code is reversible.
"""
isreversible(C::AbstractCyclicCode) = return [C.n - i for i in C.defset] ⊆ C.defset

"""
    isdegenerate(C::AbstractCyclicCode)

Return `true` if the cyclic code is degenerate.

A cyclic code is degenerate if the parity-check polynomial divides `x^r - 1` for
some `r` less than the length of the code.
"""
function isdegenerate(C::AbstractCyclicCode)
    x = gen(C.R)
    for r in 1:C.n - 1
        flag, _ = divides(x^r - 1, C.h)
        flag && return true
    end
    return false
end

"""
    BCHbound(C::AbstractCyclicCode)

Return the BCH bound for `C`.

This is a lower bound on the minimum distance of `C`.
"""
BCHbound(C::AbstractCyclicCode) = C.δ

# """
#     HTbound(C::AbstractCyclicCode)

# Return the Hartmann-Tzeng refinement to the BCH bound for `C`.

# This is a lower bound on the minimum distance of `C`.
# """
# HTbound(C::AbstractCyclicCode) = C.HT

function show(io::IO, C::AbstractCyclicCode)
    if ismissing(C.d)
        if typeof(C) <: ReedSolomonCode
            println(io, "[$(C.n)), $(C.k); $(C.b)]_$(order(C.F)) Reed-Solomon code")
        elseif typeof(C) <: BCHCode
            println(io, "[$(C.n), $(C.k); $(C.b)]_$(order(C.F)) BCH code")
        else
            println(io, "[$(C.n), $(C.k)]_$(order(C.F)) cyclic code")
        end
    else
        if typeof(C) <: ReedSolomonCode
            println(io, "[$(C.n)), $(C.k), $(C.d); $(C.b)]_$(order(C.F)) Reed-Solomon code")
        elseif typeof(C) <: BCHCode
            println(io, "[$(C.n), $(C.k), $(C.d); $(C.b)]_$(order(C.F)) BCH code")
        else
            println(io, "[$(C.n), $(C.k), $(C.d)]_$(order(C.F)) cyclic code")
        end
    end
    if get(io, :compact, true)
        println(io, "$(order(C.F))-Cyclotomic cosets: ")
        len = length(qcosetsreps(C))
        if len == 1
            println("\tC_$(qcosetsreps(C)[1])")
        else
            for (i, x) in enumerate(qcosetsreps(C))
                if i == 1
                    print(io, "\tC_$x ∪ ")
                elseif i == 1 && i == len
                    println(io, "\tC_$x")
                elseif i != len
                    print(io, "C_$x ∪ ")
                else
                    println(io, "C_$x")
                end
            end
        end
        println(io, "Generator polynomial:")
        println(io, "\t", generatorpolynomial(C))
        if C.n <= 30
            G = generatormatrix(C)
            nr, nc = size(G)
            println(io, "Generator matrix: $nr × $nc")
            for i in 1:nr
                print(io, "\t")
                for j in 1:nc
                    if j != nc
                        print(io, "$(G[i, j]) ")
                    elseif j == nc && i != nr
                        println(io, "$(G[i, j])")
                    else
                        print(io, "$(G[i, j])")
                    end
                end
            end
        end
        # if !ismissing(C.weightenum)
        #     println(io, "\nComplete weight enumerator:")
        #     print(io, "\t", polynomial(C.weightenum))
        # end
    end
end

"""
    finddelta(n::Int, cosets::Vector{Vector{Int}})

Return the number of consecutive elements of `cosets`, the offset for this, and
a lower bound on the distance of the code defined with length `n` and
cyclotomic cosets `cosets`.

The lower bound is determined by applying the Hartmann-Tzeng bound refinement to
the BCH bound.
"""
# TODO: check why d is sometimes lower than HT but never than BCH
function finddelta(n::Int, cosets::Vector{Vector{Int}})
    defset = sort!(vcat(cosets...))
    runs = Vector{Vector{Int}}()
    for x in defset
        useddefset = Vector{Int}()
        reps = Vector{Int}()
        cosetnum = 0
        for i in 1:length(cosets)
            if x ∈ cosets[i]
                cosetnum = i
                append!(useddefset, cosets[i])
                append!(reps, x)
                break
            end
        end

        y = x + 1
        while y ∈ defset
            if y ∈ useddefset
                append!(reps, y)
            else
                cosetnum = 0
                for i in 1:length(cosets)
                    if y ∈ cosets[i]
                        cosetnum = i
                        append!(useddefset, cosets[i])
                        append!(reps, y)
                        break
                    end
                end
            end
            y += 1
        end
        push!(runs, reps)
    end

    runlens = [length(i) for i in runs]
    (consec, ind) = findmax(runlens)
    # there are δ - 1 consecutive numbers for designed distance δ
    δ = consec + 1
    # start of run
    offset = runs[ind][1]
    # BCH Bound is thus d ≥ δ

    # moving to Hartmann-Tzeng Bound refinement
    currbound = δ
    # if consec > 1
    #     for A in runs
    #         if length(A) == consec
    #             for b in 1:(n - 1)
    #                 if gcd(b, n) ≤ δ
    #                     for s in 0:(δ - 2)
    #                         B = [mod(j * b, n) for j in 0:s]
    #                         AB = [x + y for x in A for y in B]
    #                         if AB ⊆ defset
    #                             if currbound < δ + s
    #                                 currbound = δ + s
    #                             end
    #                         end
    #                     end
    #                 end
    #             end
    #         end
    #     end
    # end

    return δ, offset, currbound
end

"""
    dualdefiningset(defset::Vector{Int}, n::Int)

Return the defining set of the dual code of length `n` and defining set `defset`.
"""
dualdefiningset(defset::Vector{Int}, n::Int) = sort!([mod(n - i, n) for i in setdiff(0:n - 1, defset)])

"""
    CyclicCode(q::Int, n::Int, cosets::Vector{Vector{Int}})

Return the CyclicCode of length `n` over `GF(q)` with `q`-cyclotomic cosets `cosets`.

This function will auto determine if the constructed code is BCH or Reed-Solomon
and call the appropriate constructor.

# Examples
```julia
julia> q = 2; n = 15; b = 3; δ = 4;
julia> cosets = definingset([i for i = b:(b + δ - 2)], q, n, false);
julia> C = CyclicCode(q, n, cosets)
```
"""
function CyclicCode(q::Int, n::Int, cosets::Vector{Vector{Int}})
    (q <= 1 || n <= 1) && throw(DomainError("Invalid parameters passed to CyclicCode constructor: q = $q, n = $n."))
    factors = AbstractAlgebra.factor(q)
    length(factors) == 1 || throw(DomainError("There is no finite field of order $q."))
    (p, t), = factors

    F, _ = FiniteField(p, t, "α")
    deg = ord(n, q)
    E, α = FiniteField(p, t * deg, "α")
    R, x = PolynomialRing(E, "x")
    β = α^(div(BigInt(q)^deg - 1, n))

    defset = sort!(vcat(cosets...))
    k = n - length(defset)
    comcosets = complementqcosets(q, n, cosets)
    g = _generatorpolynomial(R, β, defset)
    h = _generatorpolynomial(R, β, vcat(comcosets...))
    e = _idempotent(g, h, n)
    G = _generatormatrix(F, n, k, g)
    H = _generatormatrix(F, n, n - k, reverse(h))
    Gstand, Hstand, P, rnk = _standardform(G)
    # HT will serve as a lower bound on the minimum weight
    # take the weight of g as an upper bound
    δ, b, HT = finddelta(n, cosets)
    ub = wt(G[1, :])

    # verify
    trH = transpose(H)
    flag, htest = divides(x^n - 1, g)
    flag || error("Incorrect generator polynomial, does not divide x^$n - 1.")
    htest == h || error("Division of x^$n - 1 by the generator polynomial does not yield the constructed parity check polynomial.")
    # e * e == e || error("Idempotent polynomial is not an idempotent.")
    size(H) == (n - k, k) && (temp = H; H = trH; trH = temp;)
    iszero(G * trH) || error("Generator and parity check matrices are not transpose orthogonal.")

    if δ >= 2 && defset == definingset([i for i = b:(b + δ - 2)], q, n, true)
        if deg == 1 && n == q - 1
            # known distance, should probably not do δ, HT here
            d = n - k + 1
            return ReedSolomonCode(F, E, R, β, n, k, d, b, d, d, d, d, cosets,
                sort!([arr[1] for arr in cosets]), defset, g, h, e, G, missing,
                H, missing, Gstand, Hstand, P, missing)
        end

        return BCHCode(F, E, R, β, n, k, missing, b, δ, HT, HT, ub,
            cosets, sort!([arr[1] for arr in cosets]), defset, g, h, e, G,
            missing, H, missing, Gstand, Hstand, P, missing)
    end

    return CyclicCode(F, E, R, β, n, k, missing, b, δ, HT, HT, ub,
        cosets, sort!([arr[1] for arr in cosets]), defset, g, h, e, G,
        missing, H, missing, Gstand, Hstand, P, missing)
end

"""
    CyclicCode(n::Int, g::fq_nmod_poly)

Return the length `n` cyclic code generated by the polynomial `g`.
"""
function CyclicCode(n::Int, g::fq_nmod_poly)
    n <= 1 && throw(DomainError("Invalid parameters passed to CyclicCode constructor: n = $n."))
    R = parent(g)
    flag, h = divides(gen(R)^n - 1, g)
    flag || throw(ArgumentError("Given polynomial does not divide x^$n - 1."))

    F = base_ring(R)
    q = Int(order(F))
    p = Int(characteristic(F))
    t = Int(degree(F))
    deg = ord(n, q)
    E, α = FiniteField(p, t * deg, "α")
    β = α^(div(q^deg - 1, n))
    ordE = Int(order(E))
    RE, y = PolynomialRing(E, "y")
    gE = RE([E(i) for i in collect(coefficients(g))])
    # _, h = divides(gen(RE)^n - 1, gE)

    dic = Dict{fq_nmod, Int}()
    for i in 0:ordE - 1
        dic[β^i] = i
    end
    cosets = definingset(sort!([dic[rt] for rt in roots(gE)]), q, n, false)
    defset = sort!(vcat(cosets...))
    k = n - length(defset)
    e = _idempotent(g, h, n)
    G = _generatormatrix(F, n, k, g)
    H = _generatormatrix(F, n, n - k, reverse(h))
    Gstand, Hstand, P, rnk = _standardform(G)
    # HT will serve as a lower bound on the minimum weight
    # take the weight of g as an upper bound
    δ, b, HT = finddelta(n, cosets)
    upper = wt(G[1, :])

    # verify
    trH = transpose(H)
    # e * e == e || error("Idempotent polynomial is not an idempotent.")
    size(H) == (n - k, k) && (temp = H; H = trH; trH = temp;)
    iszero(G * trH) || error("Generator and parity check matrices are not transpose orthogonal.")

    if δ >= 2 && defset == definingset([i for i = b:(b + δ - 2)], q, n, true)
        if deg == 1 && n == q - 1
            d = n - k + 1
            return ReedSolomonCode(F, E, R, β, n, k, d, b, d, d, d, d, cosets,
                sort!([arr[1] for arr in cosets]), defset, g, h, e, G, missing,
                H, missing, Gstand, Hstand, P, missing)
        end

        return BCHCode(F, E, R, β, n, k, missing, b, δ, HT, HT, upper,
            cosets, sort!([arr[1] for arr in cosets]), defset, g, h, e, G,
            missing, H, missing, Gstand, Hstand, P, missing)
    end

    return CyclicCode(F, E, R, β, n, k, missing, b, δ, HT, HT, upper,
        cosets, sort!([arr[1] for arr in cosets]), defset, g, h, e, G,
        missing, H, missing, Gstand, Hstand, P, missing)
end

# self orthogonal cyclic codes are even-like
# does this require them too have even minimum distance?
# self orthogonal code must contain all of its self orthogonal q-cosets and at least one of every q-coset pair
"""
    BCHCode(q::Int, n::Int, δ::Int, b::Int=0)

Return the BCHCode of length `n` over `GF(q)` with design distance `δ` and offset
`b`.

This function will auto determine if the constructed code is Reed-Solomon
and call the appropriate constructor.

# Examples
```julia
julia> q = 2; n = 15; b = 3; δ = 4;
julia> B = BCHCode(q, n, δ, b)
[15, 5, ≥7; 1]_2 BCH code over splitting field GF(16).
2-Cyclotomic cosets:
        C_1 ∪ C_3 ∪ C_5
Generator polynomial:
        x^10 + x^8 + x^5 + x^4 + x^2 + x + 1
Generator matrix: 5 × 15
        1 1 1 0 1 1 0 0 1 0 1 0 0 0 0
        0 1 1 1 0 1 1 0 0 1 0 1 0 0 0

        0 0 1 1 1 0 1 1 0 0 1 0 1 0 0
        0 0 0 1 1 1 0 1 1 0 0 1 0 1 0
        0 0 0 0 1 1 1 0 1 1 0 0 1 0 1
```
"""
function BCHCode(q::Int, n::Int, δ::Int, b::Int=0)
    δ >= 2 || throw(DomainError("BCH codes require δ ≥ 2 but the constructor was given δ = $δ."))
    (q <= 1 || n <= 1) && throw(DomainError("Invalid parameters passed to BCHCode constructor: q = $q, n = $n."))
    factors = AbstractAlgebra.factor(q)
    length(factors) == 1 || throw(DomainError("There is no finite field of order $q."))
    (p, t), = factors

    F, _ = FiniteField(p, t, "α")
    deg = ord(n, q)
    E, α = FiniteField(p, t * deg, "α")
    R, x = PolynomialRing(E, "x")
    β = α^(div(q^deg - 1, n))

    cosets = definingset([i for i = b:(b + δ - 2)], q, n, false)
    defset = sort!(vcat(cosets...))
    k = n - length(defset)
    comcosets = complementqcosets(q, n, cosets)
    g = _generatorpolynomial(R, β, defset)
    h = _generatorpolynomial(R, β, vcat(comcosets...))
    e = _idempotent(g, h, n)
    G = _generatormatrix(F, n, k, g)
    H = _generatormatrix(F, n, n - k, reverse(h))
    Gstand, Hstand, P, rnk = _standardform(G)
    # HT will serve as a lower bound on the minimum weight
    # take the weight of g as an upper bound
    δ, b, HT = finddelta(n, cosets)
    upper = wt(G[1, :])

    # verify
    trH = transpose(H)
    flag, htest = divides(x^n - 1, g)
    flag || error("Incorrect generator polynomial, does not divide x^$n - 1.")
    htest == h || error("Division of x^$n - 1 by the generator polynomial does not yield the constructed parity check polynomial.")
    # e * e == e || error("Idempotent polynomial is not an idempotent.")
    size(H) == (n - k, k) && (temp = H; H = trH; trH = temp;)
    iszero(G * trH) || error("Generator and parity check matrices are not transpose orthogonal.")

    if deg == 1 && n == q - 1
        d = n - k + 1
        return ReedSolomonCode(F, E, R, β, n, k, d, b, d, d, d, d, cosets,
            sort!([arr[1] for arr in cosets]), defset, g, h, e, G, missing,
            H, missing, Gstand, Hstand, P, missing)
    end

    return BCHCode(F, E, R, β, n, k, missing, b, δ, HT, HT, upper,
        cosets, sort!([arr[1] for arr in cosets]), defset, g, h, e, G,
        missing, H, missing, Gstand, Hstand, P, missing)
end

"""
    ReedSolomonCode(q::Int, δ::Int, b::Int=0)

Return the ReedSolomonCode over `GF(q)` with distance `d` and offset `b`.

# Examples
```julia
julia> ReedSolomonCode(8, 3, 0)
[7, 5, ≥3; 0]_8 Reed Solomon code.
8-Cyclotomic cosets:
        C_0 ∪ C_1
Generator polynomial:
        x^2 + (α + 1)*x + α
Generator matrix: 5 × 7
        α α + 1 1 0 0 0 0
        0 α α + 1 1 0 0 0
        0 0 α α + 1 1 0 0
        0 0 0 α α + 1 1 0
        0 0 0 0 α α + 1 1

julia> ReedSolomonCode(13, 5, 1)
[12, 8, ≥5; 1]_13 Reed Solomon code.
13-Cyclotomic cosets:
        C_1 ∪ C_2 ∪ C_3 ∪ C_4
Generator polynomial:
        x^4 + 9*x^3 + 7*x^2 + 2*x + 10
Generator matrix: 8 × 12
        10 2 7 9 1 0 0 0 0 0 0 0
        0 10 2 7 9 1 0 0 0 0 0 0
        0 0 10 2 7 9 1 0 0 0 0 0
        0 0 0 10 2 7 9 1 0 0 0 0
        0 0 0 0 10 2 7 9 1 0 0 0
        0 0 0 0 0 10 2 7 9 1 0 0
        0 0 0 0 0 0 10 2 7 9 1 0
        0 0 0 0 0 0 0 10 2 7 9 1
```
"""
function ReedSolomonCode(q::Int, d::Int, b::Int=0)
    d >= 2 || throw(DomainError("Reed Solomon codes require δ ≥ 2 but the constructor was given d = $d."))
    q > 4 || throw(DomainError("Invalid or too small parameters passed to ReedSolomonCode constructor: q = $q."))

    # n = q - 1
    # if ord(n, q) != 1
    #     error("Reed Solomon codes require n = q - 1.")
    # end

    factors = AbstractAlgebra.factor(q)
    length(factors) == 1 || error("There is no finite field of order $q.")
    (p, t), = factors

    F, α = FiniteField(p, t, "α")
    R, x = PolynomialRing(F, "x")

    n = q - 1
    cosets = definingset([i for i = b:(b + d - 2)], q, n, false)
    defset = sort!(vcat(cosets...))
    k = n - length(defset)
    comcosets = complementqcosets(q, n, cosets)
    g = _generatorpolynomial(R, α, defset)
    h = _generatorpolynomial(R, α, vcat(comcosets...))
    e = _idempotent(g, h, n)
    G = _generatormatrix(F, n, k, g)
    H = _generatormatrix(F, n, n - k, reverse(h))
    Gstand, Hstand, P, rnk = _standardform(G)

    # verify
    trH = transpose(H)
    flag, htest = divides(x^n - 1, g)
    flag || error("Incorrect generator polynomial, does not divide x^$n - 1.")
    htest == h || error("Division of x^$n - 1 by the generator polynomial does not yield the constructed parity check polynomial.")
    # e * e == e || error("Idempotent polynomial is not an idempotent.")
    size(H) == (n - k, k) && (temp = H; H = trH; trH = temp;)
    iszero(G * trH) || error("Generator and parity check matrices are not transpose orthogonal.")
    iszero(Gstand * trH) || error("Column swap appeared in _standardform.")

    return ReedSolomonCode(F, F, R, α, n, k, d, b, d, d, d, d, cosets,
        sort!([arr[1] for arr in cosets]), defset, g, h, e, G, missing, H,
        missing, Gstand, Hstand, P, missing)
end

"""
    BCHCode(C::AbstractCyclicCode)

Return the BCH supercode of the cyclic code `C`.

Returns `C` if `C` is already a BCH code.
"""
# TODO: think further about how I use δ here
# sagemath disagrees with my answers here but matching its parameters gives a false supercode
function BCHCode(C::AbstractCyclicCode)
    typeof(C) <: AbstractBCHCode && return C
    δ, b, _ = finddelta(C.n, C.qcosets)
    B = BCHCode(Int(order(C.F)), C.n, δ, b)
    C ⊆ B && return B
    error("Failed to create BCH supercode.")
end

function iscyclic(C::AbstractLinearCode, construct::Bool=true)
    typeof(C) <: AbstractCyclicCode && (return true, C;)
    
    ordF = Int(order(C.F))
    gcd(C.n, ordF) == 1 || return false
    (p, t), = AbstractAlgebra.factor(ordF)
    deg = ord(C.n, ordF)
    E, α = FiniteField(p, t * deg, "α")
    R, x = PolynomialRing(E, "x")
    # β = α^(div(q^deg - 1, n))

    G = generatormatrix(C)
    nc = ncols(G)
    g = R([E(G[1, i]) for i in 1:nc])
    for r in 2:nrows(G)
        g = gcd(g, R([E(G[r, i]) for i in 1:nc]))
    end
    isone(g) && return false
    degree(g) == C.n - C.k || return false
    # need to setup x
    flag, h = divides(x^C.n - 1, g)
    flag || return false
    Gcyc = _generatormatrix(C.F, C.n, C.k, g)
    for r in 1:nrows(Gcyc)
        (Gcyc[r, :] ∈ C) || (return false;)
    end

    if construct
        Ccyc = CyclicCode(C.n, g)
        return true, Ccyc
    end
    return true
end

"""
    complement(C::AbstractCyclicCode)

Return the cyclic code whose cyclotomic cosets are the completement of `C`'s.
"""
function complement(C::AbstractCyclicCode)
    ordC = Int(order(C.F))
    D = CyclicCode(ordC, C.n, complementqcosets(ordC, C.n, C.qcosets))
    (C.h != D.g || D.e != (1 - C.e)) && error("Error constructing the complement cyclic code.")
    return D
end

# C1 ⊆ C2 iff g_2(x) | g_1(x) iff T_2 ⊆ T_1
"""
    ⊆(C1::AbstractCyclicCode, C2::AbstractCyclicCode)
    ⊂(C1::AbstractCyclicCode, C2::AbstractCyclicCode)
    issubcode(C1::AbstractCyclicCode, C2::AbstractCyclicCode)

Return whether or not `C1` is a subcode of `C2`.
"""
⊆(C1::AbstractCyclicCode, C2::AbstractCyclicCode) = C2.defset ⊆ C1.defset
⊂(C1::AbstractCyclicCode, C2::AbstractCyclicCode) = C1 ⊆ C2
issubcode(C1::AbstractCyclicCode, C2::AbstractCyclicCode) = C1 ⊆ C2

"""
    ==(C1::AbstractCyclicCode, C2::AbstractCyclicCode)

Return whether or not `C1` and `C2` have the same fields, lengths, and defining sets.
"""
==(C1::AbstractCyclicCode, C2::AbstractCyclicCode) = C1.F == C2.F && C1.n == C2.n && C1.defset == C2.defset && C1.β == C2.β

"""
    dual(C::AbstractCyclicCode)

Return the dual of the cyclic code `C`.

Unlike with `LinearCode`, everything is recomputed here so the proper
polynomials and cyclotomic cosets are stored.
"""
# one is even-like and the other is odd-like
dual(C::AbstractCyclicCode) = CyclicCode(Int(order(C.F)), C.n, dualqcosets(Int(order(C.F)), C.n, C.qcosets))

# this checks def set, need to rewrite == for linear first
"""
    isselfdual(C::AbstractCyclicCode)

Return whether or not `C == dual(C)`.
"""
isselfdual(C::AbstractCyclicCode) = C == dual(C)

# don't think this is necessary in order to invoke the ⊆ for CyclicCode
# function isselforthogonal(C::AbstractCyclicCode)
#     # A code is self-orthogonal if it is a subcode of its dual.
#     return C ⊆ dual(C)
# end

# function μa(C::CyclicCode)
#     # check gcd(a, n) = 1
#     # technically changes g(x) and e(x) but the q-cosets are the same?
# end

"""
    ∩(C1::AbstractCyclicCode, C2::AbstractCyclicCode)

Return the intersection code of `C1` and `C2`.
"""
function ∩(C1::AbstractCyclicCode, C2::AbstractCyclicCode)
    # has generator polynomial lcm(g_1(x), g_2(x))
    # has generator idempotent e_1(x) e_2(x)
    if C1.F == C2.F && C1.n == C2.n
        ordC1 = Int(order(C1.F))
        return CyclicCode(ordC1, C1.n, definingset(C1.defset ∪ C2.defset, ordC1,
            C1.n, false))
    else
        throw(ArgumentError("Cannot intersect two codes over different base fields or lengths."))
    end
end

"""
    +(C1::AbstractCyclicCode, C2::AbstractCyclicCode)

Return the addition code of `C1` and `C2`.
"""
function +(C1::AbstractCyclicCode, C2::AbstractCyclicCode)
    # has generator polynomial gcd(g_1(x), g_2(x))
    # has generator idempotent e_1(x) + e_2(x) - e_1(x) e_2(x)
    if C1.F == C2.F && C1.n == C2.n
        defset = C1.defset ∩ C2.defset
        if length(defset) != 0
            ordC1 = Int(order(C1.F))
            return CyclicCode(ordC1, C1.n, definingset(defset, ordC1, C1.n, false))
        else
            error("Addition of codes has empty defining set.")
        end
    else
        throw(ArgumentError("Cannot add two codes over different base fields or lengths."))
    end
end

# "Schur products of linear codes: a study of parameters"
# Diego Mirandola
# """
#     entrywiseproductcode(C::AbstractCyclicCode)
#     *(C::AbstractCyclicCode)
#     Schurproductcode(C::AbstractCyclicCode)
#     Hadamardproductcode(C::AbstractCyclicCode)
#     componentwiseproductcode(C::AbstractCyclicCode)
#
# Return the entrywise product of `C` with itself, which is also a cyclic code.
#
# Note that this is known to often be the full ambient space.
# """
# function entrywiseproductcode(C::AbstractCyclicCode)
#     # generator polynomial is gcd(g*g, g*g*x, g*g*x^{k - 1})
#     R = parent(g)
#     g = generatorpolynomial(C)
#     coefsg = collect(coefficients(g))
#     n = length(coefsg)
#     cur = R([coefsg[i] * coefsg[i] for i in 1:n])
#     for i in 1:dimension(C) - 1
#         coefsgx = collect(coefficents(g * x^i))
#         cur = gcd(cur, R([coefsg[i] * coefsgx[i] for i in 1:n]))
#     end
#     return CyclicCode(cur)
# end
# *(C::AbstractCyclicCode) = entrywiseproductcode(C)
# Schurproductcode(C::AbstractCyclicCode) = entrywiseproductcode(C)
# Hadamardproductcode(C::AbstractCyclicCode) = entrywiseproductcode(C)
# componentwiseproductcode(C::AbstractCyclicCode) = entrywiseproductcode(C)

"""
    QuadraticResidueCode(q::Int, n::Int)

Return the cyclic code whose roots are the quadratic residues of `q, n`.
"""
# covered nicely in van Lint and Betten et al
QuadraticResidueCode(q::Int, n::Int) = CyclicCode(q, n, [quadraticresidues(q, n)])
