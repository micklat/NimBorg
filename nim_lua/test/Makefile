tests: test_lua
	./test_lua

COMPILE = nimrod --debuginfo --lineDir:on --threads:on -p=../.. c

test_lua: test_lua.nim ../high_level.nim
	$(COMPILE) $<

