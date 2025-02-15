# Copyright (c) 2021, 2022 Eric Sabo
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

struct WeightEnumerator
    # polynomial::Union{fmpz_mpoly, LaurentMPolyElem{fmpz}}
    polynomial::Union{fmpz_mpoly, AbstractAlgebra.Generic.MPoly{nf_elem}}
    type::String
end

mutable struct LinearCode <: AbstractLinearCode
    F::FqNmodFiniteField # base field
    n::Int # length
    k::Int # dimension
    d::Union{Int, Missing} # minimum distance
    lbound::Int # lower bound on d
    ubound::Int # upper bound on d
    G::fq_nmod_mat
    Gorig::Union{fq_nmod_mat, Missing}
    H::fq_nmod_mat
    Horig::Union{fq_nmod_mat, Missing}
    Gstand::fq_nmod_mat
    Hstand::fq_nmod_mat
    P::Union{fq_nmod_mat, Missing} # permutation matrix for G -> Gstand
    weightenum::Union{WeightEnumerator, Missing}
end

function _standardform(G::fq_nmod_mat)
    rnk, Gstand, P = _rref_col_swap(G, 1:nrows(G), 1:ncols(G))
    nrows(Gstand) > rnk && (Gstand = _removeempty(Gstand, "rows");)
    A = Gstand[:, (nrows(Gstand) + 1):ncols(Gstand)]
    T = MatrixSpace(base_ring(Gstand), ncols(Gstand) - nrows(Gstand),
        ncols(Gstand) - nrows(Gstand))
    Hstand = hcat(-transpose(A), T(1))
    return Gstand, Hstand, P, rnk
end

"""
    LinearCode(G::fq_nmod_mat, parity::Bool=false)

Return the linear code constructed with generator matrix `G`.

If `G` is not full rank, a row-reduced form is computed for the generator matrix.
The dimension of the code is the number of rows of the full-rank matrix, and the
length the number of columns. If the optional paramater `parity` is set to `true`,
a LinearCode is built with `G` as the parity-check matrix.

# Arguments
* `G`: a matrix over a finite field of type `FqNmodFiniteField`
* `parity`: a boolean

# Notes
* At the moment, no convention is used for G = 0 and an error is thrown.
* Zero columns are not removed.
* Row reduction is based on Nemo's rref function. It should be monitored to make
  sure that this does not introduce column swapping in a future version.

# Examples
```julia
julia> F, _ = FiniteField(2, 1, "α");
julia> G = matrix(F, 4, 7, [1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1]);
julia> C = LinearCode(G)
[7, 4]_2 linear code.
Generator matrix: 4 × 7
        1 0 0 0 0 1 1
        0 1 0 0 1 0 1
        0 0 1 0 1 1 0
        0 0 0 1 1 1 1
```
"""
function LinearCode(Gorig::fq_nmod_mat, parity::Bool=false)
    # if passed a VS, just ask for the basis
    iszero(Gorig) && error("Zero matrix passed into LinearCode constructor.")

    Gorig = _removeempty(Gorig, "rows")
    G = Gorig
    Gstand, Hstand, P, k = _standardform(G)
    if ismissing(P)
        _, H = right_kernel(G)
        # note the H here is transpose of the standard definition
        H = _removeempty(transpose(H), "rows")
    else
        H = Hstand * P
    end

    if parity
        ub1, _ = _minwtrow(H)
        ub2, _ = _minwtrow(Hstand)
        ub = minimum([ub1, ub2])
        # treat G as the parity-check matrix H
        return LinearCode(base_ring(G), ncols(H), nrows(Hstand), missing,
            1, ub, H, missing, G, Gorig, Hstand, Gstand, P, missing)
    else
        ub1, _ = _minwtrow(G)
        ub2, _ = _minwtrow(Gstand)
        ub = minimum([ub1, ub2])
        return LinearCode(base_ring(G), ncols(G), k, missing, 1, ub, G,
            Gorig, H, missing, Gstand, Hstand, P, missing)
    end
end

function show(io::IO, C::AbstractLinearCode)
    if ismissing(C.d)
        println(io, "[$(C.n), $(C.k)]_$(order(C.F)) linear code.")
    else
        println(io, "[$(C.n), $(C.k), $(C.d)]_$(order(C.F)) linear code.")
    end
    if get(io, :compact, false) && C.n <= 30
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
        # if !ismissing(C.weightenum)
        #     println(io, "\nComplete weight enumerator:")
        #     print(io, "\t", C.weightenum.polynomial)
        # end
    end
end

"""
    field(C::AbstractLinearCode)

Return the base ring of the generator matrix.
"""
field(C::AbstractLinearCode) = C.F

"""
    length(C::AbstractLinearCode)

Return the length of the code.
"""
length(C::AbstractLinearCode) = C.n

"""
    dimension(C::AbstractLinearCode)

Return the dimension of the code.
"""
dimension(C::AbstractLinearCode) = C.k

"""
    cardinality(C::AbstractLinearCode)

Return the cardinality of the code.

No size checking is done on the parameters of the code, returns a BitInt by default.
"""
cardinality(C::AbstractLinearCode) = BigInt(order(C.F))^C.k

"""
    rate(C::AbstractLinearCode)

Return the rate, `R = k/n', of the code.
"""
rate(C::AbstractLinearCode) = C.k / C.n

"""
    setdistancelowerbound!(C::AbstractLinearCode, l::Integer)

Set the lower bound on the minimum distance of `C`, if `l` is better than the current bound.
"""

function setdistancelowerbound!(C::AbstractLinearCode, l::Integer)
    1 <= l <= C.ubound || throw(DomainError("The lower bound must be between 1 and the upper bound."))
    C.lbound < l && (C.lbound = l;)
    if C.lbound == C.ubound
        @warn "The new lower bound is equal to the upper bound; setting the minimum distance."
        C.d = C.lbound
    end
end

"""
    setdistanceupperbound!(C::AbstractLinearCode, u::Integer)

Set the upper bound on the minimum distance of `C`, if `u` is better than the current bound.
"""

function setdistanceupperbound!(C::AbstractLinearCode, u::Integer)
    C.lbound <= u <= C.n || throw(DomainError("The upper bound must be between the lower bound and the code length."))
    u < C.ubound && (C.ubound = u;)
    if C.lbound == C.ubound
        @warn "The new upper bound is equal to the lower bound; setting the minimum distance."
        C.d = C.lbound
    end
end

"""
    setminimumdistance(C::AbstractLinearCode, d::Integer)

Set the minimum distance of the code to `d`.

Warning: The only check done on the value of `d` is that `1 ≤ d ≤ n`.
"""
function setminimumdistance!(C::AbstractLinearCode, d::Integer)
    d > 0 && d <= C.n || throw(DomainError("The minimum distance of a code must be ≥ 1; received: d = $d."))
    C.d = d
end

"""
    relativedistance(C::AbstractLinearCode)

Return the relative minimum distance, `δ = d / n` of the code if `d` is known,
otherwise return `missing`.
"""
function relativedistance(C::AbstractLinearCode)
    ismissing(C.d) && return missing
    return C.d // C.n
end

"""
    generatormatrix(C::AbstractLinearCode, standform::Bool=false)

Return the generator matrix of the code.

If the optional parameter `standform` is set to `true`, the standard form of the
generator matrix is returned instead.
"""
function generatormatrix(C::AbstractLinearCode, standform::Bool=false)
    standform ? (return C.Gstand;) : (return C.G;)
end

"""
    originalgeneratormatrix(C::AbstractLinearCode)

Return the original generator matrix used to create the code.

This should not be interpreted as any kind of generator to the code. For example,
if `G` is not a full-rank matrix, then this function acting on `C = LinearCode(G)`
will return `G` instead of the generator matrix for `C`. This may be used to diagnose
or understand the resulting code after its creation. An important use of this
function is in connection with standard code modification procedures such as
extending, puncturing, shortening, etc where this returns the matrix on which these
procedures have been applied.
"""
function originalgeneratormatrix(C::AbstractLinearCode)
    ismissing(C.Gorig) && return missing
    return C.Gorig
end

"""
    paritycheckmatrix(C::AbstractLinearCode, standform::Bool=false)

Return the parity-check matrix of the code.

If the optional parameter `standform` is set to `true`, the standard form of the
parity-check matrix is returned instead.
"""
function paritycheckmatrix(C::AbstractLinearCode, standform::Bool=false)
    standform ? (return C.Hstand;) : (return C.H;)
end

"""
    originalparitycheckmatrix(C::AbstractLinearCode)

Return the original parity-check matrix used to create the code.

See `originalgeneratormatrix`.
"""
function originalparitycheckmatrix(C::AbstractLinearCode)
    ismissing(C.Horig) && return missing
    return C.Horig
end

"""
    genus(C::AbstractLinearCode)

Return the genus, `n + 1 - k - d`, of the code.
"""
genus(C::AbstractLinearCode) = C.n + 1 - C.k - minimumdistance(C)

function Singletonbound(n::Integer, a::Integer)
    # d ≤ n - k + 1 or k ≤ n - d + 1
    if n >= 0 && a >= 0 && n >= a
        return n - a + 1
    else
        error("Invalid parameters for the Singleton bound. Received n = $n, k/d = $a")
    end
end
Singletonbound(C::AbstractLinearCode) = Singletonbound(C.n, C.k)

"""
    isMDS(C::AbstractLinearCode)

Return `true` if code is maximum distance separable (MDS).

A linear code is MDS if it saturates the Singleton bound, `d = n - k + 1`.
"""
function isMDS(C::AbstractLinearCode)
    minimumdistance(C) != Singletonbound(C.n, C.k) ? (return true;) : (return false;)
end

"""
    numbercorrectableerrors(C::AbstractLinearCode)

Return the number of correctable errors for the code.

The number of correctable errors is `t = floor((d - 1) / 2)`.
"""
numbercorrectableerrors(C::AbstractLinearCode) = Int(floor((minimumdistance(C) - 1) / 2))

"""
    encode(v::Union{fq_nmod_mat, Vector{Int}}, C::AbstractLinearCode)

Return `v * G`, where `G` is the generator matrix of `C`.

# Arguments
* `v`: Either a `1 × k` or a `k × 1` vector.
"""
function encode(v::fq_nmod_mat, C::AbstractLinearCode)
    G = generatormatrix(C)
    nr = nrows(G)
    (size(v) != (1, nr) && size(v) != (nr, 1)) &&
        throw(ArgumentError("Vector has incorrect dimension; expected length $nr, received: $(size(v))."))
    base_ring(v) == C.F || throw(ArgumentError("Vector must have the same base ring as the generator matrix."))
    nrows(v) != 1 || return v * G
    return transpose(v) * G
end
# TODO: combine these two functions
function encode(v::Vector{Int}, C::AbstractLinearCode)
    length(v) == C.k ||
        throw(ArgumentError("Vector has incorrect length; expected length $(C.k), received: $(size(v))."))
    return encode(matrix(C.F, transpose(v)), C)
end

"""
    syndrome(v::Union{fq_nmod_mat, Vector{Int}}, C::AbstractLinearCode)

Return `Hv`, where `H` is the parity-check matrix of `C`.

# Arguments
* `v`: Either a `1 × k` or a `k × 1` vector.
"""
function syndrome(v::fq_nmod_mat, C::AbstractLinearCode)
    H = paritycheckmatrix(C)
    nc = ncols(H)
    (size(v) != (nc, 1) && size(v) != (1, nc)) &&
        throw(ArgumentError("Vector has incorrect dimension; expected length $nc, received: $(size(v))."))
    base_ring(v) == C.F || throw(ArgumentError("Vector must have the same base ring as the parity-check matrix."))
    nrows(v) != 1 || return H * transpose(v)
    return H * v
end
# TODO: combine these two functions
function syndrome(v::Vector{Int}, C::AbstractLinearCode)
    length(v) == C.n ||
        throw(ArgumentError(("Vector to be tested is of incorrect dimension; expected length $(C.n), received: $(size(v)).")))
    return syndrome(matrix(C.F, transpose(v)), C)
end

"""
    in(v::Union{fq_nmod_mat, Vector{Int}}, C::AbstractLinearCode)

Return whether or not `v` is a codeword of `C`.

The vector `v` is a valid codeword of `C` if and only if the syndrome of `v` is zero.
"""
in(v::fq_nmod_mat, C::AbstractLinearCode) = iszero(syndrome(v, C))
in(v::Vector{Int}, C::AbstractLinearCode) = iszero(syndrome(v, C))

"""
    ⊆(C1::AbstractLinearCode, C2::AbstractLinearCode)
    ⊂(C1::AbstractLinearCode, C2::AbstractLinearCode)
    issubcode(C1::AbstractLinearCode, C2::AbstractLinearCode)

Return whether or not `C1` is a subcode of `C2`.

A code `C1` is a subcode of another code `C2` if each row of
the generator matrix of `C1` is a valid codeword of `C2`.
"""
function ⊆(C1::AbstractLinearCode, C2::AbstractLinearCode)
    if C1.n != C2.n || C1.n != C2.n || C1.k > C2.k
        return false
    end

    # eachrow doesn't work on these objects
    G1 = generatormatrix(C1)
    nr = nrows(G1)
    for r in 1:nr
        if G1[r, :] ∉ C2
            return false
        end
    end
    return true
end
⊂(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊆ C2
issubcode(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊆ C2

"""
    codecomplement(C1::AbstractLinearCode, C2::AbstractLinearCode)
    quo(C1::AbstractLinearCode, C2::AbstractLinearCode)
    quotient(C1::AbstractLinearCode, C2::AbstractLinearCode)
    /(C2::AbstractLinearCode, C1::AbstractLinearCode)

Return the code `C2 / C1` given `C1 ⊆ C2`.

Credit to Tommy Hofmann of the AbstractAlgebra/Nemo/Hecke packages for help with
debugging and providing the most elegant implementation now used here.
"""
function codecomplement(C1::AbstractLinearCode, C2::AbstractLinearCode)
    C1 ⊆ C2 || throw(ArgumentError("C1 ⊈ C2"))
    F = C1.F
    G1 = generatormatrix(C1)
    G2 = generatormatrix(C2)
    V = VectorSpace(F, C1.n)
    U, UtoV = sub(V, [V(G1[i, :]) for i in 1:nrows(G1)])
    W, WtoV = sub(V, [V(G2[i, :]) for i in 1:nrows(G2)])
    gensofUinW = [preimage(WtoV, UtoV(g)) for g in gens(U)]
    UinW, _ = sub(W, gensofUinW)
    Q, WtoQ = quo(W, UinW)
    C2modC1basis = [WtoV(x) for x in [preimage(WtoQ, g) for g in gens(Q)]]
    Fbasis = [[F(C2modC1basis[j][i]) for i in 1:dim(parent(C2modC1basis[1]))] for j in 1:length(C2modC1basis)]
    G = matrix(F, length(Fbasis), length(Fbasis[1]), vcat(Fbasis...))
    for r in 1:length(Fbasis)
        v = G[r, :]
        (v ∈ C2 && v ∉ C1) || error("Error in creation of basis for C2 / C1.")
    end
    return LinearCode(G)
end
quo(C1::AbstractLinearCode, C2::AbstractLinearCode) = codecomplement(C1, C2)
quotient(C1::AbstractLinearCode, C2::AbstractLinearCode) = codecomplement(C1, C2)
/(C2::AbstractLinearCode, C1::AbstractLinearCode) = codecomplement(C1, C2)

"""
    dual(C::AbstractLinearCode)
    Euclideandual(C::AbstractLinearCode)

Return the dual of the code `C`.
"""
function dual(C::AbstractLinearCode)
    G = generatormatrix(C)
    Gstand = generatormatrix(C, true)
    Gorig = originalgeneratormatrix(C)
    H = paritycheckmatrix(C)
    Hstand = paritycheckmatrix(C, true)
    Horig = originalparitycheckmatrix(C)
    ub1, _ = _minwtrow(H)
    ub2, _ = _minwtrow(Hstand)
    ub = minimum([ub1, ub2])

    if !ismissing(C.weightenum)
        dualwtenum = MacWilliamsIdentity(C, C.weightenum)
        HWE = CWEtoHWE(dualwtenum)
        d = minimum([collect(exponent_vectors(polynomial(HWE)))[i][1]
            for i in 1:length(polynomial(HWE))])
        return LinearCode(C.F, C.n, C.n - C.k, d, 1, ub, deepcopy(H),
            deepcopy(Horig), deepcopy(G), deepcopy(Gorig),
            deepcopy(Hstand), deepcopy(Gstand), deepcopy(C.P), dualwtenum)
    else
        return LinearCode(C.F, C.n, C.n - C.k, missing, 1, ub, deepcopy(H),
            deepcopy(Horig), deepcopy(G), deepcopy(Gorig),
            deepcopy(Hstand), deepcopy(Gstand), deepcopy(C.P), missing)
    end
end
Euclideandual(C::AbstractLinearCode) = dual(C)

"""
    Hermitiandual(C::AbstractLinearCode)

Return the Hermitian dual of a code defined over a quadratic extension.
"""
Hermitiandual(C::AbstractLinearCode) = dual(LinearCode(Hermitianconjugatematrix(C.G)))
# also valid to do LinearCode(Hermitianconjugatematrix(generatormatrix(dual(C))))

"""
    isequivalent(C1::AbstractLinearCode, C2::AbstractLinearCode)

Return `true` if `C1 ⊆ C2` and `C2 ⊆ C1`.
"""
isequivalent(C1::AbstractLinearCode, C2::AbstractLinearCode) = (C1 ⊆ C2 && C2 ⊆ C1)

"""
    isselfdual(C::AbstractLinearCode)

Return `true` if `isequivalent(C, dual(C))`.
"""
isselfdual(C::AbstractLinearCode) = isequivalent(C, dual(C))

"""
    isselforthogonal(C::AbstractLinearCode)
    isweaklyselfdual(C::AbstractLinearCode)
    isEuclideanselforthogonal(C::AbstractLinearCode)

Return `true` if `C ⊆ dual(C)`.
"""
isselforthogonal(C::AbstractLinearCode) = C ⊆ dual(C)
isweaklyselfdual(C::AbstractLinearCode) = isselforthogonal(C)
isEuclideanselforthogonal(C::AbstractLinearCode) = isselforthogonal(C)

"""
    isdualcontaining(C::AbstractLinearCode)
    isEuclideandualcontaining(C::AbstractLinearCode)

Return `true` if `dual(C) ⊆ C`.
"""
isdualcontaining(C::AbstractLinearCode) = dual(C) ⊆ C
isEuclideandualcontaining(C::AbstractLinearCode) = isdualcontaining(C)

"""
    isHermitianselfdual(C::AbstractLinearCode)

Return `true` if `isequivalent(C, Hermitiandual(C))`.
"""
isHermitianselfdual(C::AbstractLinearCode) = isequivalent(C, Hermitiandual(C))

"""
    isHermitianselforthogonal(C::AbstractLinearCode)
    isHermitianweaklyselfdual(C::AbstractLinearCode)

Return `true` if `C ⊆ Hermitiandual(C)`.
"""
isHermitianselforthogonal(C::AbstractLinearCode) = C ⊆ Hermitiandual(C)
isHermitianweaklyselfdual(C::AbstractLinearCode) = isHermitianselforthogonal(C)

"""
    isHermitiandualcontaining(C::AbstractLinearCode)

Return `true` if `Hermitiandual(C) ⊆ C`.
"""
isHermitiandualcontaining(C::AbstractLinearCode) = Hermitiandual(C) ⊆ C

# TODO: add l-Galois dual and self-dual/orthogonal based functions

"""
    ⊕(C1::AbstractLinearCode, C2::AbstractLinearCode)
    directsum(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊕ C2

Return the direct sum code of `C1` and `C2`.

The direct sum code has generator matrix `G1 ⊕ G2` and parity-check matrix `H1 ⊕ H2`.
"""
function ⊕(C1::AbstractLinearCode, C2::AbstractLinearCode)
    C1.F == C2.F || throw(ArgumentError("Codes must be over the same field."))

    G1 = generatormatrix(C1)
    G2 = generatormatrix(C2)
    G = directsum(G1, G2)
    H1 = paritycheckmatrix(C1)
    H2 = paritycheckmatrix(C2)
    H = directsum(H1, H2)
    # should just be direct sum, but need to recompute P - also direct sum?
    Gstand, Hstand, P, k = _standardform(G)
    k == C1.k + C2.k || error("Unexpected dimension in direct sum output.")

    if !ismissing(C1.d) && !ismissing(C2.d)
        d = minimum([C1.d, C2.d])
        return LinearCode(C1.F, C1.n, k, d, d, d, G, missing, H, missing, Gstand,
            Hstand, P, missing)
    else
        lb = minimum([C1.lbound, C2.lbound])
        ub = minimum([C1.ubound, C2.ubound])
        return LinearCode(C1.F, C1.n, k, missing, lb, ub, G, missing, H, missing,
            Gstand, Hstand, P, missing)
    end
end
directsum(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊕ C2

"""
    ⊗(C1::AbstractLinearCode, C2::AbstractLinearCode)
    kron(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
    tensorproduct(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
    directproduct(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
    productcode(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2

Return the (direct/tensor) product code of `C1` and `C2`.

The product code has generator matrix `G1 ⊗ G2` and parity-check matrix `H1 ⊗ H2`.

# Notes
* The resulting product is not checked for any zero columns but is checked for zero rows.
"""
function ⊗(C1::AbstractLinearCode, C2::AbstractLinearCode)
    C1.F == C2.F || throw(ArgumentError("Codes must be over the same field."))

    G = generatormatrix(C1) ⊗ generatormatrix(C2)
    H = paritycheckmatrix(C1) ⊗ paritycheckmatrix(C2)

    Gstand, Hstand, P, k = _standardform(G)
    k == C1.k * C2.k || error("Unexpected dimension in direct product output.")

    if !ismissing(C1.d) && !ismissing(C2.d)
        d = C1.d * C2.d
        return LinearCode(C1.F, C1.n * C2.n, k, d, d, d, G, missing, H, missing,
            Gstand, Hstand, P, missing)
    else
        return LinearCode(C1.F, C1.n * C2.n, k, missing, C1.lbound * C2.lbound,
            C1.ubound * C2.ubound, G, missing, H, missing, Gstand, Hstand, P, missing)

    end
end
kron(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
tensorproduct(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
directproduct(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2
productcode(C1::AbstractLinearCode, C2::AbstractLinearCode) = C1 ⊗ C2

"""
    characteristicpolynomial(C::AbstractLinearCode)

Return the characteristic polynomial of `C`.

The characteristic polynomial is defined in [Lin1999]_
"""
function characteristicpolynomial(C::AbstractLinearCode)
    _, x = PolynomialRing(Nemo.QQ, "x")
    D = dual(C)
    supD = support(D)
    q = Int(order(C.F))
    return q^(n - k) * prod([1 - x / j for j in supD if j > 0])
end

# TODO: need to write extend such that the ternay Golay codes come out
"""
    extend(C::AbstractLinearCode)

Return the extended code of `C`.

This implementation chooses the most common form of extending a code, which is to
add an extra column to the generator matrix such that the sum of the coordinates
of each row is 0.
"""
# TODO: do the general extension and call this the even extension
function extend(C::AbstractLinearCode)
    p = Int(characteristic(C.F))
    # produce standard form of extended G
    G = generatormatrix(C)
    nrG = nrows(G)
    col = [sum(G[i, :]) for i in 1:nrG]
    M = MatrixSpace(C.F, nrG, 1)
    G = hcat(G, M([p - i for i in col]))

    # produce standard form of extended H
    H = paritycheckmatrix(C)
    nrH = nrows(H)
    M = MatrixSpace(C.F, 1, C.n + 1)
    toprow = M([1 for _ in 1:(C.n + 1)])
    rightcol = zero_matrix(C.F, nrH, 1)
    H = vcat(toprow, hcat(paritycheckmatrix(C), rightcol))
    Gstand, Hstand, P, k = _standardform(G)

    # d is either d or d + 1
    # using this even extension construction
    # if binary, if d is even, then new d = d, otherwise d = d + 1
    # for nonbinary, have to calculate the d of the even/odd-like subcodes
    if !ismissing(C.d)
        if iseven(C.d)
            return LinearCode(C.F, C.n + 1, k, C.d, C.d, C.d, G, C.G, H, C.H, Gstand,
                Hstand, P, missing)
        else
            d = C.d + 1
            return LinearCode(C.F, C.n + 1, k, d, d, d, G, C.G, H, C.H, Gstand,
                Hstand, P, missing)
        end
    else
        ub1, _ = _minwtrow(G)
        ub2, _ = _minwtrow(Gstand)
        ub = minimum([ub1, ub2])
        return LinearCode(C.F, C.n + 1, k, missing, C.lbound, ub, G, C.G, H, C.H,
            Gstand, Hstand, P, missing)
    end
end

"""
    puncture(C::AbstractLinearCode, cols::Vector{Int})
    puncture(C::AbstractLinearCode, cols::Int)

Return the code of `C` punctured at the columns in `cols`.

Deletes the columns from the generator matrix and then removes any potentially
resulting zero rows.
"""
function puncture(C::AbstractLinearCode, cols::Vector{Int})
    isempty(cols) && return C
    cols ⊆ 1:C.n || throw(ArgumentError("Columns to puncture are not a subset of the index set."))
    length(cols) == C.n && throw(ArgumentError("Cannot puncture all columns of a generator matrix."))

    Gorig = generatormatrix(C)
    G = Gorig[:, setdiff(1:C.n, cols)]
    G = _removeempty(G, "rows")
    Gstand, Hstand, P, k = _standardform(G)
    if ismissing(P)
        _, H = right_kernel(G)
        # note the H here is transpose of the standard definition
        H = _removeempty(transpose(H), "rows")
    else
        H = Hstand * P
    end

    ub1, _ = _minwtrow(G)
    ub2, _ = _minwtrow(Gstand)
    ub = minimum([ub1, ub2])
    return LinearCode(C.F, ncols(G), k, missing, 1, ub, G, Gorig, H,
        paritycheckmatrix(C), Gstand, Hstand, P, missing)
end
puncture(C::AbstractLinearCode, cols::Int) = puncture(C, [cols])

"""
    expurgate(C::AbstractLinearCode, rows::Vector{Int})
    expurgate(C::AbstractLinearCode, rows::Int)

Return the code of `C` expuragated at the rows in `rows`.

Deletes the rows from the generator matrix and then removes any potentially
resulting zero columns.
"""
function expurgate(C::AbstractLinearCode, rows::Vector{Int})
    isempty(rows) && return C
    Gorig = generatormatrix(C)
    nr = nrows(Gorig)
    rows ⊆ 1:nr || throw(ArgumentError("Rows to expurgate are not a subset of the index set."))
    length(rows) == nr && throw(ArgumentError("Cannot expurgate all rows of a generator matrix."))

    Gorig = generatormatrix(C)
    G = Gorig[setdiff(1:nr, rows), :]
    Gstand, Hstand, P, k = _standardform(G)
    if ismissing(P)
        _, H = right_kernel(G)
        # note the H here is transpose of the standard definition
        H = _removeempty(transpose(H), "rows")
    else
        H = Hstand * P
    end

    ub1, _ = _minwtrow(G)
    ub2, _ = _minwtrow(Gstand)
    ub = minimum([ub1, ub2])
    return LinearCode(C.F, C.n, k, missing, 1, ub, G, Gorig, H,
        paritycheckmatrix(C), Gstand, Hstand, P, missing)
end
expurgate(C::AbstractLinearCode, rows::Int) = expurgate(C, [rows])

"""
    augment(C::AbstractLinearCode, M::fq_nmod_mat)

Return the code of `C` whose generator matrix is augmented with `M`.

Vertically joins the matrix `M` to the bottom of the generator matrix of `C`.
"""
function augment(C::AbstractLinearCode, M::fq_nmod_mat)
    iszero(M) && error("Zero matrix passed to augment.")
    C.n == ncols(M) || error("Rows to augment must have the same number of columns as the generator matrix.")
    C.F == base_ring(M) || error("Rows to augment must have the same base field as the code.")

    Gorig = generatormatrix(C)
    M = _removeempty(M, "rows")
    G = vcat(Gorig, M)
    Gstand, Hstand, P, k = _standardform(G)
    if ismissing(P)
        _, H = right_kernel(G)
        # note the H here is transpose of the standard definition
        H = _removeempty(transpose(H), "rows")
    else
        H = Hstand * P
    end

    ub1, _ = _minwtrow(G)
    ub2, _ = _minwtrow(Gstand)
    ub = minimum([ub1, ub2])
    return LinearCode(C.F, C.n, k, missing, 1, ub, G, Gorig, H,
        paritycheckmatrix(C), Gstand, Hstand, P, missing)
end

"""
    shorten(C::AbstractLinearCode, L::Vector{Int})
    shorten(C::AbstractLinearCode, L::Int)

Return the code of `C` shortened on the indices `L`.

Shortening is expurgating followed by puncturing. This implementation uses the
theorem that the dual of code shortened on `L` is equal to the puncture of the
dual code on `L`, i.e., `dual(puncture(dual(C), L))`.
"""
# most parameter checks here done in puncture
shorten(C::AbstractLinearCode, L::Vector{Int}) = isempty(L) ? (return C;) : (return dual(puncture(dual(C), L));)
shorten(C::AbstractLinearCode, L::Int) = shorten(C, [L])

"""
    lengthen(C::AbstractLinearCode)

Return the lengthened code of `C`.

This augments the all 1's row and then extends.
"""
lengthen(C::AbstractLinearCode) = extend(augment(C, matrix(C.F, transpose([1 for _ in 1:C.n]))))

"""
    uuplusv(C1::AbstractLinearCode, C2::AbstractLinearCode)
    Plotkinconstruction(C1::AbstractLinearCode, C2::AbstractLinearCode)

Return the Plotkin- or so-called (u | u + v)-construction with `u ∈ C1` and `v ∈ C2`.
"""
function uuplusv(C1::AbstractLinearCode, C2::AbstractLinearCode)
    # Returns the Plotkin `(u|u+v)`-construction with u = C1 and v = C2
    C1.F == C2.F || error("Base field must be the same in the Plotkin (u|u + v)-construction.")
    C1.n == C2.n || error("Both codes must have the same length in the Plotkin (u|u + v)-construction.")

    G1 = generatormatrix(C1)
    G2 = generatormatrix(C2)
    G = vcat(hcat(G1, G1), hcat(parent(G2)(0), G2))
    H1 = paritycheckmatrix(C1)
    H2 = paritycheckmatrix(C2)
    H = vcat(hcat(H1, parent(H1)(0)), hcat(-H2, H2))
    Gstand, Hstand, P, k = _standardform(G)
    k = C1.k + C2.k ||  error("Something went wrong in the Plotkin (u|u + v)-construction;
        dimension ($k) and expected dimension ($(C1.k + C2.k)) are not equal.")

    if ismissing(C1.d) || ismissing(C2.d)
        # probably can do better than this
        lb = minimum([2 * C1.lbound, C2.lbound])
        ub1, _ = _minwtrow(G)
        ub2, _ = _minwtrow(Gstand)
        ub = minimum([ub1, ub2])
        return LinearCode(C1.F, 2 * C1.n, k, missing, lb, ub, G, missing, H, missing,
            Gstand, Hstand, P, missing)
    else
        d = minimum([2 * C1.d, C2.d])
        return LinearCode(C1.F, 2 * C1.n, k, d, d, d, G, missing, H, missing,
            Gstand, Hstand, P, missing)
    end
end
Plotkinconstruction(C1::AbstractLinearCode, C2::AbstractLinearCode) = uuplusv(C1, C2)

"""
    subcode(C::AbstractLinearCode, k::Integer)

Return a `k`-dimensional subcode of `C`.
"""
function subcode(C::AbstractLinearCode, k::Integer)
    k >= 1 && k < C.k || error("Cannot construct a $k-dimensional subcode of an $(C.k)-dimensional code.")
    k != C.k || return C
    return LinearCode(generatormatrix(C)[1:k, :])
end

"""
    subcode(C::AbstractLinearCode, rows::Vector{Int})

Return a subcode of `C` using the rows of the generator matrix of `C` listed in
`rows`.
"""
function subcode(C::AbstractLinearCode, rows::Vector{Int})
    isempty(rows) && error("Row index set empty in subcode.")
    rows ⊆ 1:C.k || error("Rows are not a subset of the index set.")
    length(rows) == C.k && return C
    return LinearCode(generatormatrix(C)[setdiff(1:C.k, rows), :])
end

"""
    subcodeofdimensionbetweencodes(C1::AbstractLinearCode, C2::AbstractLinearCode, k::Int)

Return a subcode of dimenion `k` between `C1` and `C2`.

This function arguments generators of `C1 / C2` to  `C2` until the desired dimenion
is reached.
"""
function subcodeofdimensionbetweencodes(C1::AbstractLinearCode, C2::AbstractLinearCode, k::Int)
    C2 ⊆ C1 || throw(ArgumentError("C2 must be a subcode of C1"))
    C2.k <= k <= C1.k || throw(ArgumentError("The dimension must be between that of C1 and C2."))
    
    k == C2.k && return C2
    k == C1.k && return C1
    C = C1 / C2
    return augment(C2, generatormatrix(C)[1:k - C2.k, :])
end

"""
    juxtaposition(C1::AbstractLinearCode, C2::AbstractLinearCode)

Return the code generated by the horizontal concatenation of the generator
matrices of `C1` then `C2`.
"""
function juxtaposition(C1::AbstractLinearCode, C2::AbstractLinearCode)
    C1.F == C2.F || error("Cannot juxtapose two codes over different fields.")
    C1.k == C2.k || error("Cannot juxtapose two codes of different dimensions.")
    return LinearCode(hcat(generatormatrix(C1), generatormatrix(C2)))
end

"""
    constructionX(C1::AbstractLinearCode, C2::AbstractLinearCode, C3::AbstractLinearCode)

Return the code generated by the construction X procedure.

Let `C1` be an [n, k, d], `C2` be an [n, k - l, d + e], and `C3` be an [m, l, e] linear code
with `C2 ⊂ C1` be proper. Construction X creates a [n + m, k, d + e] linear code.
"""
function constructionX(C1::AbstractLinearCode, C2::AbstractLinearCode, C3::AbstractLinearCode)
    C1 ⊆ C2 || error("The first code must be a subcode of the second in construction X.")
    isequivalent(C1, C2) && error("The first code must be a proper subcode of the second in construction X.")
    # the above line checks C1.F == C2.F
    C1.F == field(C3) || error("All codes must be over the same base ring in construction X.")
    C2.k == C1.k + dimension(C3) ||
        error("The dimension of the second code must be the sum of the dimensions of the first and third codes.")

    # could do some verification steps on parameters
    C = LinearCode(vcat(hcat(generatormatrix(C1 / C2), generatormatrix(C3)),
        hcat(C1.G, zero_matrix(C1.F, C1.k, length(C3)))))
    C.n == C1.n + C3.n || error("Something went wrong in construction X. Expected length
        $(C1.n + C3.n) but obtained length $(C.n)")

    if !ismissing(C1.d) && !ismissing(C2.d) && !ismissing(C3.d)
        C.d = minimum([C1.d, C2.d + C3.d])
    else
        # pretty sure this holds
        setdistancelowerbound!(C, minimum([C1.lbound, C2.lbound + C3.lbound]))
    end
    return C
end

"""
    constructionX3(C1::AbstractLinearCode, C2::AbstractLinearCode, C3::AbstractLinearCode,
        C4::AbstractLinearCode, C5::AbstractLinearCode))

Return the code generated by the construction X3 procedure.

Let C1 = [n, k1, d1], C2 = [n, k2, d2], C3 = [n, k3, d3], C4 = [n4, k2 - k1, d4], and
C5 = [n5, k3 - k2, d5] with `C1 ⊂ C2 ⊂ C3`. Construction X3 creates an [n + n4 + n5, k3, d]
linear code with d ≥ min{d1, d2 + d4, d3 + d5}.
"""
function constructionX3(C1::AbstractLinearCode, C2::AbstractLinearCode, C3::AbstractLinearCode,
    C4::AbstractLinearCode, C5::AbstractLinearCode)

    C1 ⊆ C2 || error("The first code must be a subcode of the second in construction X3.")
    isequivalent(C1, C2) && error("The first code must be a proper subcode of the second in construction X3.")
    C2 ⊆ C3 || error("The second code must be a subcode of the third in construction X3.")
    isequivalent(C2, C3) && error("The second code must be a proper subcode of the third in construction X3.")
    # the above lines check C1.F == C2.F == field(C3)
    C1.F == C4.F  == C5.F || error("All codes must be over the same base ring in construction X3.")
    C3.k == C2.k + C4.k ||
        error("The dimension of the third code must be the sum of the dimensions of the second and fourth codes in construction X3.")
    C2.k == C1.k + C5.k ||
        error("The dimension of the second code must be the sum of the dimensions of the first and fifth codes in construction X3.")

    C2modC1 = C2 / C1
    C3modC2 = C3 / C2
    F = C1.F

    # could do some verification steps on parameters
    G = vcat(hcat(generatormatrix(C1), zero_matrix(F, C1.k, C4.n), zero_matrix(F, C1.k, C5.n)),
    hcat(C2modC1.G, C4.G, zero_matrix(F, C4.k, C5.n)),
    hcat(C3modC2.G, zero_matrix(F, C5.k, C4.n), generatormatrix(C5)))
    C = LinearCode(G)
    if !ismissing(C1.d) && !ismissing(C2.d) && !ismissing(C3.d) && !ismissing(C4.d) && !ismissing(C5.d)
        setlowerdistancebound!(C, minimum([C1.d, C2.d + C4.d, C3.d + C5.d]))
    end
    return C
end

"""
    upluswvpluswuplusvplusw(C1::AbstractLinearCode, C2::AbstractLinearCode)

Return the code generated by the (u + w | v + w | u + v + w)-construction.

Let C1 = [n, k1, d1] and C2 = [n, k2, d2]. This construction produces an [3n, 2k1 + k2]
linear code. For binary codes, wt(u + w | v + w | u + v + w) = 2 wt(u ⊻ v) - wt(w) + 4s,
where s = |{i | u_i = v_i = 0, w_i = 1}|.
"""
function upluswvpluswuplusvplusw(C1::AbstractLinearCode, C2::AbstractLinearCode)
    C1.F == C2.F || error("All codes must be over the same base ring in the (u + w | v + w | u + v + w)-construction.")
    C1.n == C2.n || error("All codes must be the same length in the (u + w | v + w | u + v + w)-construction.")

    G1 = generatormatrix(C1)
    G2 = generatormatrix(C2)
    # could do some verification steps on parameters
    return LinearCode(vcat(hcat(G1, zero_matrix(C1.F, C1.k, C1.n), G1),
        hcat(G2, G2, G2),
        hcat(zero_matrix(C1.F, C1.k, C1.n), G1, G1)))
end

"""
    expandedcode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod})

Return the expanded code of `C` constructed by exapnding the generator matrix
to the subfield `K` using the provided dual `basis` for the field of `C`
over `K`.
"""
expandedcode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod}) = LinearCode(expandmatrix(generatormatrix(C), K, basis))

# """
#     subfieldsubcode(C::AbstractLinearCode, K::FqNmodFiniteField)
#
# Return the subfield subcode code of `C` over `K` using Delsarte's theorem.
#
# Use this method if you are unsure of the dual basis to the basis you which
# to expand with.
# """
# function subfieldsubcode(C::AbstractLinearCode, K::FqNmodFiniteField)
#     return dual(tracecode(dual(C), K))
# end

"""
    subfieldsubcode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod})

Return the subfield subcode code of `C` over `K` using the provided dual `basis`
for the field of `C` over `K`.
"""
subfieldsubcode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod}) = LinearCode(transpose(expandmatrix(transpose(paritycheckmatrix(C)), K, basis)), true)

"""
    tracecode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod})

Return the trace code of `C` over `K` using the provided dual `basis`
for the field of `C` over `K` using Delsarte's theorem.
"""
tracecode(C::AbstractLinearCode, K::FqNmodFiniteField, basis::Vector{fq_nmod}) = dual(subfieldsubcode(dual(C), K, basis))

# R.Pellikaan, On decoding by error location and dependent sets of error
# positions, Discrete Mathematics, 106107 (1992), 369-381.
# the Schur product of vector spaces is highly basis dependent and is often the
# full vector space (an [n, n, 1] code)
# might be a cyclic code special case in
# "On the Schur Product of Vector Spaces over Finite Fields"
# Christiaan Koster
"""
    entrywiseproductcode(C::AbstractLinearCode, D::AbstractLinearCode)
    *(C::AbstractLinearCode, D::AbstractLinearCode)
    Schurproductcode(C::AbstractLinearCode, D::AbstractLinearCode)
    Hadamardproductcode(C::AbstractLinearCode, D::AbstractLinearCode)
    componentwiseproductcode(C::AbstractLinearCode, D::AbstractLinearCode)

Return the entrywise product of `C` and `D`.

Note that this is known to often be the full ambient space.
"""
# TODO: Oscar doesn't work well with dot operators
function entrywiseproductcode(C::AbstractLinearCode, D::AbstractLinearCode)
    C.F == field(D) || error("Codes must be over the same field in the Schur product.")
    C.n == length(D) || error("Codes must have the same length in the Schur product.")

    GC = generatormatrix(G)
    GD = generatormatrix(D)
    nrC = nrows(GC)
    nrD = nrows(GD)
    indices = Vector{Tuple{Int, Int}}()
    for i in 1:nrC
        for j in 1:nrD
            i <= j && push!(indices, (i, j))
        end
    end
    return LinearCode(matrix(C.F, vcat([GC[i, :] .* GD[j, :] for (i, j) in indices]...)))

    # verify C ⊂ it
end
*(C::AbstractLinearCode, D::AbstractLinearCode) = entrywiseproductcode(C, D)
Schurproductcode(C::AbstractLinearCode, D::AbstractLinearCode) = entrywiseproductcode(C, D)
Hadamardproductcode(C::AbstractLinearCode, D::AbstractLinearCode) = entrywiseproductcode(C, D)
componentwiseproductcode(C::AbstractLinearCode, D::AbstractLinearCode) = entrywiseproductcode(C, D)

"""
    VectorSpace(C::AbstractLinearCode)

Return the code `C` as a vector space object.
"""
function VectorSpace(C::AbstractLinearCode)
    V = VectorSpace(C.F, C.n)
    G = generatormatrix(C)
    return sub(V, [V(G[i, :]) for i in 1:nrows(G)])
end

# needs significant testing, works so far
function evensubcode(C::AbstractLinearCode)
    F = C.F
    Int(order(F)) == 2 || throw(ArgumentError("Even-ness is only defined for binary codes."))

    VC, ψ = VectorSpace(C)
    GFVS = VectorSpace(F, 1)
    homo1quad = ModuleHomomorphism(VC, GFVS, matrix(F, dim(VC), 1,
        vcat([F(weight(ψ(g).v) % 2) for g in gens(VC)]...)))
    evensub, ϕ1 = kernel(homo1quad)
    iszero(dim(evensub)) ? (return missing;) : (return LinearCode(vcat([ψ(ϕ1(g)).v for g in gens(evensub)]...));)
end

"""
    iseven(C::AbstractLinearCode)

Return `true` if `C` is even.
"""
function iseven(C::AbstractLinearCode)
    Int(order(C.F)) == 2 || throw(ArgumentError("Even-ness is only defined for binary codes."))
    
    # A binary code generated by G is even if and only if each row of G has
    # even weight.
    G = generatormatrix(C)
    for r in 1:nrows(G)
        wt(G[r, :]) % 2 == 0 || (return false;)
    end
    return true
end

"""
    isdoublyeven(C::AbstractLinearCode)

Return `true` if `C` is doubly-even.
"""
function isdoublyeven(C::AbstractLinearCode)
    Int(order(C.F)) == 2 || throw(ArgumentError("Even-ness is only defined for binary codes."))

    # A binary code generated by G is doubly-even if and only if each row of G
    # has weight divisible by 4 and the sum of any two rows of G has weight
    # divisible by 4.
    G = generatormatrix(C)
    nr = nrows(G)
    for r in 1:nr
        # TODO: allocates a lot, should redo calculation here
        wt(G[r, :]) % 4 == 0 || (return false;)
    end
    for r1 in 1:nr
        for r2 in 1:nr
            # or by Ward's thm can do * is % 2 == 0
            wt(G[r1, :] + G[r2, :]) % 4 == 0 || (return false;)
        end
    end
    return true
end

"""
    istriplyeven(C::AbstractLinearCode)

Return `true` if `C` is triply-even.
"""
function istriplyeven(C::AbstractLinearCode)
    Int(order(C.F)) == 2 || throw(ArgumentError("Even-ness is only defined for binary codes."))

    # following Ward's divisibility theorem
    G = FpmattoJulia(generatormatrix(C))
    nr, _ = size(G)
    for r in 1:nr
        wt(G[r, :]) % 8 == 0 || (return false;)
    end
    for r1 in 1:nr
        for r2 in 1:nr
            wt(G[r1, :] .* G[r2, :]) % 4 == 0 || (return false;)
        end
    end
    for r1 in 1:nr
        for r2 in 1:nr
            for r3 in 1:nr
                wt(G[r1, :] .* G[r2, :] .* G[r3, :])% 2 == 0 || (return false;)
            end
        end
    end
    return true
end

# needs significant testing, works so far
function doublyevensubcode(C::AbstractLinearCode)
    F = C.F
    Int(order(C.F)) == 2 || throw(ArgumentError("Even-ness is only defined for binary codes."))

    VC, ψ = VectorSpace(C)
    GFVS = VectorSpace(F, 1)

    # first get the even subspace
    homo1quad = ModuleHomomorphism(VC, GFVS, matrix(F, dim(VC), 1,
        vcat([F(weight(ψ(g).v) % 2) for g in gens(VC)]...)))
    evensub, ϕ1 = kernel(homo1quad)

    if !iszero(dim(evensub))
        # now control the overlap (Ward's divisibility theorem)
        homo2bi = ModuleHomomorphism(evensub, evensub, matrix(F, dim(evensub),
            dim(evensub),
            vcat([F(weight(matrix(F, 1, C.n, ψ(ϕ1(gens(evensub)[i])).v .*
                ψ(ϕ1(gens(evensub)[j])).v)) % 2)
            for i in 1:dim(evensub), j in 1:dim(evensub)]...)))
        evensubwoverlap, μ1 = kernel(homo2bi)

        if !iszero(dim(evensubwoverlap))
            # now apply the weight four condition
            homo2quad = ModuleHomomorphism(evensubwoverlap, GFVS, matrix(F,
                dim(evensubwoverlap), 1, vcat([F(div(weight(ψ(ϕ1(μ1(g))).v),
                2) % 2) for g in gens(evensubwoverlap)]...)))
            foursub, ϕ2 = kernel(homo2quad)

            if !iszero(dim(foursub))
                return LinearCode(vcat([ψ(ϕ1(μ1(ϕ2(g)))).v for g in gens(foursub)]...))
            end
        end
    end
    return missing
end

# currently incomplete
# function triplyevensubcode(C::AbstractLinearCode)
#     F = C.F
#     VC, ψ = VectorSpace(C)
#     GFVS = VectorSpace(F, 1)
#
#     # first get the even subspace
#     homo1quad = ModuleHomomorphism(VC, GFVS, matrix(F, dim(VC), 1, vcat([F(weight(ψ(g).v) % 2) for g in gens(VC)]...)))
#     evensub, ϕ1 = kernel(homo1quad)
#
#     # now control the overlap (Ward's divisibility theorem)
#     homo2bi = ModuleHomomorphism(evensub, evensub, matrix(F, dim(evensub), dim(evensub),
#         vcat([F(weight(matrix(F, 1, C.n, ψ(ϕ1(gens(evensub)[i])).v .* ψ(ϕ1(gens(evensub)[j])).v)) % 2)
#         for i in 1:dim(evensub), j in 1:dim(evensub)]...)))
#     evensubwoverlap, μ1 = kernel(homo2bi)
#
#     # now apply the weight four condition
#     homo2quad = ModuleHomomorphism(evensubwoverlap, GFVS, matrix(F, dim(evensubwoverlap), 1,
#         vcat([F(div(weight(ψ(ϕ1(μ1(g))).v), 2) % 2) for g in gens(evensubwoverlap)]...)))
#     foursub, ϕ2 = kernel(homo2quad)
#
#     # now control the triple overlap
#     ###########
#     # how do we actually represent this?
#
#
#     # now apply the weight eight condition
#     homo3 = ModuleHomomorphism(foursub, GFVS, matrix(F, dim(foursub), 1, vcat([F(div(weight(ψ(ϕ1(ϕ2(g))).v), 4) % 2) for g in gens(foursub)]...)))
#     eightsub, ϕ3 = kernel(homo3)
#     # # println(dim(eightsub))
#     # # println(vcat([ψ(ϕ1(ϕ2(ϕ3(g)))).v for g in gens(eightsub)]...))
#     #
#     # q, γ = quo(foursub, eightsub)
#     # println(dim(q))
#     # # println([preimage(γ, g).v for g in gens(q)])
#     # return LinearCode(vcat([ψ(ϕ1(ϕ2(preimage(γ, g)))).v for g in gens(q)]...))
#     # # return LinearCode(vcat([ψ(ϕ1(ϕ2(ϕ3(g)))).v for g in gens(eightsub)]...))
#
#     return LinearCode(vcat([ψ(ϕ1(μ1(ϕ2(g)))).v for g in gens(foursub)]...))
# end

"""
    permutecode(C::AbstractLinearCode, σ::Union{Perm{T}, Vector{T}}) where T <: Integer

Return the code whose generator matrix is `C`'s with the columns permuted by `σ`.

If `σ` is a vector, it is interpreted as the desired column order for the
generator matrix of `C`.
"""
function permutecode(C::AbstractLinearCode, σ::Union{Perm{T}, Vector{T}}) where T <: Integer
    F = C.F
    G = generatormatrix(C)
    if typeof(σ) <: Perm
        return LinearCode(G * matrix(F, Array(matrix_repr(σ))))
    else
        length(unique(σ)) == C.n || error("Incorrect number of digits in permutation.")
        (1 == minimum(σ) && C.n == maximum(σ)) || error("Digits are not in the range `1:n`.")
        return LinearCode(G[:, σ])
    end
end

"""
    words(C::AbstractLinearCode, onlyprint::Bool=false)
    codewords(C::AbstractLinearCode, onlyprint::Bool=false)
    elements(C::AbstractLinearCode, onlyprint::Bool=false)

Return the elements of `C`.

If `onlyprint` is `true`, the elements are only printed to the console and not
returned.
"""
function words(C::AbstractLinearCode, onlyprint::Bool=false)
    words = Vector{fq_nmod_mat}()
    G = generatormatrix(C)
    E = base_ring(G)
    # Nemo.AbstractAlgebra.ProductIterator
    for iter in Base.Iterators.product([0:(Int(characteristic(E)) - 1) for _ in 1:nrows(G)]...)
        row = E(iter[1]) * G[1, :]
        for r in 2:nrows(G)
            if !iszero(iter[r])
                row += E(iter[r]) * G[r, :]
            end
        end
        if !onlyprint
            push!(words, row)
        else
            println(row)
        end
    end
    if !onlyprint
        return words
    else
        return
    end
end
codewords(C::AbstractLinearCode, onlyprint::Bool=false) = words(C, onlyprint)
elements(C::AbstractLinearCode, onlyprint::Bool=false) = words(C, onlyprint)

"""
    hull(C::AbstractLinearCode)
    Euclideanhull(C::AbstractLinearCode)

Return the (Euclidean) hull of `C` and its dimension.

The hull of a code is the intersection of it and its dual.
"""
function hull(C::AbstractLinearCode)
    G = generatormatrix(C)
    H = paritycheckmatrix(C)
    VS = VectorSpace(F, C.n)
    U, _ = sub(VS, [VS(G[i, :]) for i in 1:nrows(G)])
    W, WtoVS = sub(VS, [VS(H[i, :]) for i in 1:nrows(H)])
    I, _ = intersect(U, W)
    if !iszero(AbstractAlgebra.dim(I))
        Ibasis = [WtoVS(g) for g in gens(I)]
        GI = vcat(Ibasis...)
        return LinearCode(GI), AbstractAlgebra.dim(I)
    else
        return missing, 0 # is this the behavior I want?
    end
end
Euclideanhull(C::AbstractLinearCode) = hull(C)

"""
    Hermitianhull::AbstractLinearCode)
    
Return the Hermitian hull of `C` and its dimension.

The Hermitian hull of a code is the intersection of it and its Hermitian dual.
"""
function Hermitianhull(C::AbstractLinearCode)
    D = Hermitiandual(C)
    G = generatormatrix(C)
    H = generatormatrix(D)
    VS = VectorSpace(F, C.n)
    U, _ = sub(VS, [VS(G[i, :]) for i in 1:nrows(G)])
    W, WtoVS = sub(VS, [VS(H[i, :]) for i in 1:nrows(H)])
    I, _ = intersect(U, W)
    if !iszero(AbstractAlgebra.dim(I))
        Ibasis = [WtoVS(g) for g in gens(I)]
        GI = vcat(Ibasis...)
        return LinearCode(GI), AbstractAlgebra.dim(I)
    else
        return missing, 0 # is this the behavior I want?
    end
end

"""
    isLCD(C::AbstractLinearCode)

Return `true` if `C` is linear complementary dual.

A code is linear complementary dual if the dimension of `hull(C)` is zero.
"""
function isLCD(C::AbstractLinearCode)
    # return true if dim(hull) = 0
    _, dimhullC = hull(C)
    dimhullC == 0 ? (return true;) : (return false;)
end

"""
    isHermitianLCD(C::AbstractLinearCode)

Return `true` if `C` is linear complementary Hermitian dual.

A code is linear complementary Hermitian dual if the dimension of `Hermitianhull(C)` is zero.
"""
function isHermitianLCD(C::AbstractLinearCode)
    # return true if dim(hull) = 0
    _, dimhullC = Hermitianhull(C)
    dimhullC == 0 ? (return true;) : (return false;)
end

# TODO: add l-Galois hull and isLCD functions for that dual
