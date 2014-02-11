tests: test_lua
	./test_lua

COMPILE = nimrod -p=../../.. c

test_lua: test_lua.nim ../high_level.nim
	$(COMPILE) $<

