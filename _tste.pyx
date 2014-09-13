#cython: boundscheck=False, wraparound=False, cdivision=True
cimport numpy as cnp
import numpy as np
from libc.math cimport log
cimport cython.parallel

def tste_grad_cython_log(npX,
                         int N,
                         int no_dims,
                         int [:, ::1] triplets,
                         double lamb,
                         double alpha):
    """ Compute the cost function and gradient update of t-STE """
    cdef int[:] triplets_A = triplets[:,0]
    cdef int[:] triplets_B = triplets[:,1]
    cdef int[:] triplets_C = triplets[:,2]
    cdef unsigned int i,t,j,k
    cdef double[:, ::1] X = npX
    cdef double[::1] sum_X = np.zeros((N,), dtype='float64')
    cdef double[:, ::1] K = np.zeros((N, N), dtype='float64')
    cdef unsigned int no_triplets = len(triplets)
    cdef double[::1] P = np.zeros(no_triplets, dtype='float64')
    cdef double C = 0

    C += lamb * np.sum(npX**2)

    # Compute gradient for each point
    npdC = np.zeros((N, no_dims), 'float64')

    cdef double[:, ::1] dC = npdC
    cdef double A_to_B, B_to_C, const

    # Compute student-T kernel for each point
    # i,j range over points; k ranges over dims
    with nogil:
        for i in xrange(N):
            for k in xrange(no_dims):
                sum_X[i] += X[i,k]*X[i,k]
        for i in cython.parallel.prange(N):
            for j in xrange(N):
                K[i,j] = sum_X[i] + sum_X[j]
                for k in xrange(no_dims):
                    K[i,j] += -2 * X[i,k]*X[j,k]
                K[i,j] = (1 + K[i,j] / alpha) ** ((alpha+1)/-2)

        for t in cython.parallel.prange(no_triplets):
            P[t] = K[triplets_A[t], triplets_B[t]] / (
                K[triplets_A[t],triplets_B[t]] +
                K[triplets_A[t],triplets_C[t]])
            C += -(log(P[t]))

            for i in xrange(no_dims):
                # For i = each dimension to use
                const = (alpha+1) / alpha
                A_to_B = ((1 - P[t]) *
                          K[triplets_A[t],triplets_B[t]] *
                          (X[triplets_A[t], i] - X[triplets_B[t], i]))
                B_to_C = ((1 - P[t]) *
                          K[triplets_A[t],triplets_C[t]] *
                          (X[triplets_A[t], i] - X[triplets_C[t], i]))

                dC[triplets_A[t], i] += -const * (A_to_B - B_to_C)
                dC[triplets_B[t], i] += -const * (-A_to_B)
                dC[triplets_C[t], i] += -const * (B_to_C)

    npdC = (npdC*-1) + 2*lamb*npX
    return C, npdC
