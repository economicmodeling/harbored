.PHONY: all clean doc

SRC:=src/*.d\
	libddoc/src/ddoc/*.d\
	libdparse/src/std/*.d\
	libdparse/src/std/d/*.d

IMPORTS:=-Ilibdparse/src\
	-Ilibddoc/src\
	-Jstrings

FLAGS:=-O -inline

all: $(SRC)
	dmd $(SRC) $(IMPORTS) $(FLAGS) -ofbin/harbored
	rm -f bin/*.o

unittest: $(SRC)
	dmd $(SRC) $(IMPORTS) -unittest -ofbin/harbored-tests
	./bin/harbored-tests
	rm -f bin/*.o
	rm -f bin/harbored-tests


clean:
	rm -rf bin/

doc:
	./bin/harbored src/
