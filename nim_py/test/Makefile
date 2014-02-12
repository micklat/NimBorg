tests: test_py test_py_eval test_pylab 
	./test_py
	./test_py_eval
	./test_pylab

COMPILE = nimrod -p=../.. c 

test_py: test_py.nim ../high_level.nim
	$(COMPILE) $<

test_pylab: test_pylab.nim ../high_level.nim
	$(COMPILE) $<

test_py_eval: test_py_eval.nim ../high_level.nim
	$(COMPILE) $<
