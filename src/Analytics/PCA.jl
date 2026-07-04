
export RollingPCA,
  rolling_pca,
  fit!,
  project,
  explained_variance,
  residual_corr,
  plot_residual_corr

"""
    RollingPCA(window, n_factors)

Rolling PCA factor model. Maintains top `n_factors` eigenvectors of the
return covariance matrix, estimated over a sliding `window` of bars.

Fields set after `fit!`:
- `eigvecs` — [N × K] matrix, columns are factor loadings (descending variance)
- `eigvals` — K eigenvalues (descending)
- `fitted`  — false until first `fit!` call
"""
mutable struct RollingPCA
  window::Int
  n_factors::Int
  eigvecs::Matrix{Float64}
  eigvals::Vector{Float64}    # top K eigenvalues (descending)
  total_var::Float64          # trace of full covariance matrix (sum of all eigenvalues)
  fitted::Bool
end

rolling_pca(window::Int, n_factors::Int) =
  RollingPCA(window, n_factors, Matrix{Float64}(undef, 0, 0), Float64[], 0.0, false)

Base.show(io::IO, pca::RollingPCA) = print(io,
  "RollingPCA(window=$(pca.window), n_factors=$(pca.n_factors), fitted=$(pca.fitted))")

"""
    fit!(pca::RollingPCA, R::Matrix{Float64})

Fit PCA on return matrix `R` of shape `[N × T]`.  Stores the top K eigenvectors
(by variance explained) and their eigenvalues.  Requires T ≥ 2 and N ≥ n_factors.
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
    project(pca::RollingPCA, r::Vector{Float64}) -> (factors, residuals)

Project a single bar's return vector `r` [N] through the fitted PCA.
Returns:
- `factors`   — [K] factor returns (projection onto eigenvectors)
- `residuals` — [N] idiosyncratic residual after removing factor component
"""
function project(pca::RollingPCA, r::Vector{Float64})
  pca.fitted || error("RollingPCA not fitted — call fit! first")
  factors = pca.eigvecs' * r
  residuals = r - pca.eigvecs * factors
  return factors, residuals
end

"""
    project(pca::RollingPCA, R::Matrix{Float64}) -> (F, E)

Batch projection of return matrix `R` [N × T].
Returns factor matrix `F` [K × T] and residual matrix `E` [N × T].
"""
function project(pca::RollingPCA, R::Matrix{Float64})
  pca.fitted || error("RollingPCA not fitted — call fit! first")
  F = pca.eigvecs' * R
  E = R - pca.eigvecs * F
  return F, E
end

"""
    explained_variance(pca::RollingPCA) -> Vector{Float64}

Fraction of total variance explained by each factor (sums to ≤ 1).
Length equals n_factors.
"""
function explained_variance(pca::RollingPCA)
  pca.fitted || error("RollingPCA not fitted")
  pca.total_var == 0 && return zeros(length(pca.eigvals))
  return pca.eigvals ./ pca.total_var
end

"""
    residual_corr(E::Matrix{Float64}) -> Matrix{Float64}

[N × N] Pearson correlation matrix of the residual rows.
After good PCA factorization this should be close to the identity matrix —
off-diagonal entries indicate remaining common structure.
"""
function residual_corr(E::Matrix{Float64})
  N, T = size(E)
  T < 2 && return Matrix{Float64}(I, N, N)
  return cor(E')   # cor expects [T × N]
end

"""
    plot_residual_corr(E::Matrix{Float64}, names::Vector{String})

Print the residual correlation matrix as a formatted table.
Returns the [N × N] correlation matrix.
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
