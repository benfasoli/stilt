#' stilt_apply parallel apply function selection
#' @author Ben Fasoli
#'
#' Chooses apply function based on user parameters and available parallelization
#' options. Uses lapply if n_cores is 1, slurm_apply if SLURM job management is
#' available, and mclapply if SLURM is not available.
#'
#' @param X a vector to apply function FUN over
#' @param FUN the function to be applied to each element of X
#' @param slurm logical that forces job submission via SLURM
#' @param slurm_options a named list of options recognized by \code{sbatch};
#'   passed to rslurm::slurm_apply()
#' @param n_nodes number of nodes to submit SLURM jobs to using \code{sbatch}
#' @param n_cores number of CPUs to utilize per node
#' @param ... arguments to FUN
#'
#' @return if using slurm, returns sjob information. Otherwise, will return a
#'   TRUE for every successful model completion
#'
#' @export

stilt_apply <- function(X, FUN, slurm = F, slurm_options = list(),
                        n_nodes = 1, n_cores = 1, ...) {
  
  if (slurm && n_nodes > 1) {
    stop('n_nodes > 1 but but slurm is disabled. ',
         'Did you mean to set slurm = T in run_stilt.r?')
  }
  
  # Expand arguments to form a data_frame where rows serve as iterations of FUN
  # using named columns as arguments to FUN
  Y <- data_frame(X = X, ...)

  if (slurm) {
    # Confirm availability of sbatch executable and dispatch simulation
    # configurations to SLURM
    sbatch_avail <- system('which sbatch', intern = T)
    if (length(sbatch_avail) == 0 || nchar(sbatch_avail[1]) == 0)
      stop('Problem identifying sbatch executable for slurm...')
    
    # Shuffle receptor order for quasi-load balancing
    if (n_nodes > 1 || n_cores > 1) Y <- Y[sample.int(nrow(Y), nrow(Y)), ]
    
    message('Multi node parallelization using slurm. Dispatching jobs...')
    load_libs('rslurm')
    sjob <- rslurm::slurm_apply(FUN, Y,
                                jobname = basename(getwd()), pkgs = 'base',
                                nodes = n_nodes, cpus_per_node = n_cores,
                                slurm_options = slurm_options)
    return(sjob)
  }
  
  if (n_cores > 1) {
    # Load parallel backend and dispatch simulations to worker processes using
    # dynamic load balancing
    message('Single node parallelization. Dispatching worker processes...')
    load_libs('parallel')
    cl <- setDefaultCluster(makeForkCluster(n_cores, outfile = ''))
    out <- do.call(clusterMap,
                   c(fun = FUN,
                     .scheduling = 'dynamic',
                     Y))
    stopCluster(cl)
    return(out)
  }
  
  # Call FUN for each row of Y
  message('Parallelization disabled. Executing simulations sequentially...')
  for (i in 1:nrow(Y)) do.call(FUN, Y[i, ])
}
