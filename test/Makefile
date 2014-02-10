tests: test_py test_py_eval test_pylab
	./test_py
	./test_py_eval
	./test_pylab

test_py: test_py.nim ../py2.nim
	nimrod -p=../.. c $<

test_pylab: test_pylab.nim ../py2.nim
	nimrod -p=../.. c $<

test_py_eval: test_py_eval.nim ../py2.nim
	nimrod -p=../.. c $<
