.PHONY: all clean doc

DC?=dmd

SRC:=src/*.d\
	libddoc/src/ddoc/*.d\
	libdparse/src/std/experimental/*.d\
	libdparse/src/dparse/*.d\
	stdx-allocator/source/stdx/allocator/mallocator.d\
	stdx-allocator/source/stdx/allocator/common.d\

IMPORTS:=-Ilibdparse/src\
	-Ilibddoc/src\
	-Istdx-allocator/source\
	-Jstrings

FLAGS:=-O -inline
DEBUG_FLAGS:=-g

all: $(SRC)
	$(DC) $(SRC) $(IMPORTS) $(FLAGS) -ofbin/harbored
	rm -f bin/*.o

debug: $(SRC)
	$(DC) $(SRC) $(IMPORTS) $(DEBUG_FLAGS) -ofbin/harbored
	rm -f bin/*.o

unittest: $(SRC)
	$(DC) $(SRC) stdx-allocator/source/stdx/allocator/internal.d $(IMPORTS) -g -unittest -ofbin/harbored-tests
	./bin/harbored-tests
	rm -f bin/*.o
	rm -f bin/harbored-tests


clean:
	rm -rf bin/

doc:
	./bin/harbored src/
