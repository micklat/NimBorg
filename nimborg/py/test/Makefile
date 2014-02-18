tests: test_py test_py_eval test_pylab test_linalg
	./test_py
	./test_py_eval
	./test_pylab
	./test_linalg

COMPILE = nimrod -p=../../.. c 
DEPS = ../high_level.nim ../low_level.nim

test_linalg: test_linalg.nim $(DEPS)
	$(COMPILE) $<

test_minimize: test_minimize.nim $(DEPS)
	$(COMPILE) $<

test_py: test_py.nim $(DEPS)
	$(COMPILE) $<

test_pylab: test_pylab.nim $(DEPS)
	$(COMPILE) $<

test_py_eval: test_py_eval.nim $(DEPS)
	$(COMPILE) $<
