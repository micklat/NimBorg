# solve a random linear system of equations using scipy

import "../high_level"
import "../low_level"
import strutils
from math import sin

# values of x1..xk
let truth = [13, -2, 4, 19]
let np = pyImport("numpy")
let random = pyImport("numpy.random")
let linalg = pyImport("scipy.linalg")
# plenty of equations ensure a good condition number 
let A = random.randn(30,4)  
let pyTruth = np.array(truth).reshape(mkTuple(truth.len, 1))
let b = np.dot(A, pyTruth)

# solve for x: Ax = b 
let estimate = linalg.lstsq(A, b)[0]
let epsilon = 0.0001
for i in 0..len(truth)-1: 
  assert(abs(estimate[i]-truth[i])<epsilon)

# get the buffer interface for this array
assert isPyBufferable(estimate)
var buff = float64Buffer(estimate)
for i in 0..buff.nElements-1:
  assert(abs(buff[i]-truth[i])<epsilon)

# test write access to a buffer
for i in 0..buff.nElements-1:
  buff[i] = sin(float(i))
  assert toFloat(estimate[i])==sin(float(i))
