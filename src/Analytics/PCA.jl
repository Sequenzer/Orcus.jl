
"""
    RollingPCA(window::Int, n_factors::Int, eigvecs::Matrix{Float64}, eigvals::Vector{Float64}, total_var::Float64, fitted::Bool)

Rolling PCA factor model. Maintains top `n_factors` eigenvectors of the
return covariance matrix, estimated over a sliding `window` of bars. Use [`rolling_pca`](@ref)
to build an unfitted one. Fields set after `fit!`:
- `eigvecs` — [N × K] matrix, columns are factor loadings (descending variance)
- `eigvals` — K eigenvalues (descending)
- `fitted`  — false until first `fit!` call

```jldoctest
rolling_pca(20, 2)
# output

RollingPCA(window=20, n_factors=2, fitted=false)
```
"""
mutable struct RollingPCA
  window::Int
  n_factors::Int
  eigvecs::Matrix{Float64}
  eigvals::Vector{Float64}    # top K eigenvalues (descending)
  total_var::Float64          # trace of full covariance matrix (sum of all eigenvalues)
  fitted::Bool
end

"""
    rolling_pca(window::Int, n_factors::Int)

Build an unfitted `RollingPCA` — call [`fit!`](@ref) before using it.

```jldoctest
rolling_pca(20, 2)
# output

RollingPCA(window=20, n_factors=2, fitted=false)
```
"""
rolling_pca(window::Int, n_factors::Int) =
  RollingPCA(window, n_factors, Matrix{Float64}(undef, 0, 0), Float64[], 0.0, false)

Base.show(io::IO, pca::RollingPCA) = print(io,
  "RollingPCA(window=$(pca.window), n_factors=$(pca.n_factors), fitted=$(pca.fitted))")

"""
    fit!(pca::RollingPCA, R::Matrix{Float64})

Fit PCA on return matrix `R` of shape `[N × T]`, storing the top K eigenvectors (by variance
explained) and their eigenvalues. Requires T ≥ 2 and N ≥ n_factors.

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
pca.fitted
# output

true
```
"""
function fit!(pca::RollingPCA, R::Matrix{Float64})
  N, T = size(R)
  (T < 2 || N < 1) && return pca

  C = Symmetric(cov(R'))          # [N × N] covariance matrix; cov expects [T × N]
  F = eigen(C)                    # eigenvalues ascending
  idx = length(F.values):-1:1    # reverse → descending
  k = min(pca.n_factors, N)

  pca.total_var = sum(F.values)
  pca.eigvals = F.values[idx][1:k]
  pca.eigvecs = F.vectors[:, idx][:, 1:k]
  pca.fitted = true
  return pca
end

"""
    project(pca::RollingPCA, r::Vector{Float64})

Project a single bar's return vector `r` [N] through the fitted PCA, returning `(factors,
residuals)` — [K] factor returns and [N] idiosyncratic residual.

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
factors, residuals = project(pca, R[:,1]);
size(factors), size(residuals)
# output

((2,), (3,))
```
"""
function project(pca::RollingPCA, r::Vector{Float64})
  pca.fitted || error("RollingPCA not fitted — call fit! first")
  factors = pca.eigvecs' * r
  residuals = r - pca.eigvecs * factors
  return factors, residuals
end

"""
    project(pca::RollingPCA, R::Matrix{Float64})

Batch projection of return matrix `R` [N × T], returning factor matrix `F` [K × T] and
residual matrix `E` [N × T].

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
F, E = project(pca, R);
size(F), size(E)
# output

((2, 4), (3, 4))
```
"""
function project(pca::RollingPCA, R::Matrix{Float64})
  pca.fitted || error("RollingPCA not fitted — call fit! first")
  F = pca.eigvecs' * R
  E = R - pca.eigvecs * F
  return F, E
end

"""
    explained_variance(pca::RollingPCA)

Fraction of total variance explained by each factor (sums to ≤ 1), length `n_factors`.

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
explained_variance(pca)
# output

2-element Vector{Float64}:
 0.9942561416261809
 0.00574385837381898
```
"""
function explained_variance(pca::RollingPCA)
  pca.fitted || error("RollingPCA not fitted")
  pca.total_var == 0 && return zeros(length(pca.eigvals))
  return pca.eigvals ./ pca.total_var
end

"""
    residual_corr(E::Matrix{Float64})

[N × N] Pearson correlation matrix of the residual rows. After good PCA factorization this
should be close to the identity matrix — off-diagonal entries indicate remaining common
structure.

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
F, E = project(pca, R);
round.(residual_corr(E); digits=3)
# output

3×3 Matrix{Float64}:
 1.0     0.545   0.721
 0.545   1.0    -0.182
 0.721  -0.182   1.0
```
"""
function residual_corr(E::Matrix{Float64})
  N, T = size(E)
  T < 2 && return Matrix{Float64}(I, N, N)
  return cor(E')   # cor expects [T × N]
end

"""
    plot_residual_corr(E::Matrix{Float64}, names::Vector{String})

Print the residual correlation matrix as a formatted table, and return it.

```jldoctest
pca=rolling_pca(20, 2);
R=[1.0 2.0 3.0 4.0; 2.0 4.0 6.0 8.0; 1.0 1.5 1.2 1.8];
fit!(pca, R);
F, E = project(pca, R);
C = redirect_stdout(devnull) do
    plot_residual_corr(E, ["AAA","BBB","CCC"])
end;
round.(C; digits=3)
# output

3×3 Matrix{Float64}:
 1.0     0.545   0.721
 0.545   1.0    -0.182
 0.721  -0.182   1.0
```
"""
function plot_residual_corr(E::Matrix{Float64}, names::Vector{String})
  C = residual_corr(E)
  N = length(names)
  col_w = max(10, maximum(length.(names)) + 2)

  println("Residual Correlation Matrix:")
  print(repeat(" ", col_w))
  for nm in names
    print(rpad(nm, col_w))
  end
  println()
  for i in 1:N
    print(rpad(names[i], col_w))
    for j in 1:N
      print(rpad(string(round(C[i, j]; digits=3)), col_w))
    end
    println()
  end
  return C
end
