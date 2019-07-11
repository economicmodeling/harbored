.PHONY: all clean doc

DC?=dmd

SRC:=src/*.d\
	libddoc/src/ddoc/*.d\
	libdparse/src/std/experimental/*.d\
	libdparse/src/dparse/*.d\
	stdx-allocator/source/stdx/allocator/common.d\
	stdx-allocator/source/stdx/allocator/gc_allocator.d\
	stdx-allocator/source/stdx/allocator/internal.d\
	stdx-allocator/source/stdx/allocator/mallocator.d\
	stdx-allocator/source/stdx/allocator/building_blocks/bitmapped_block.d\
	stdx-allocator/source/stdx/allocator/building_blocks/stats_collector.d\
	stdx-allocator/source/stdx/allocator/building_blocks/segregator.d\
	stdx-allocator/source/stdx/allocator/building_blocks/region.d\
	stdx-allocator/source/stdx/allocator/building_blocks/null_allocator.d\
	stdx-allocator/source/stdx/allocator/building_blocks/free_list.d\
	stdx-allocator/source/stdx/allocator/building_blocks/fallback_allocator.d\
	stdx-allocator/source/stdx/allocator/building_blocks/allocator_list.d\
	stdx-allocator/source/stdx/allocator/building_blocks/bucketizer.d\
	stdx-allocator/source/stdx/allocator/mmap_allocator.d\
	stdx-allocator/source/stdx/allocator/package.d\
	stdx-allocator/source/stdx/allocator/typed.d

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
	$(DC) $(SRC) $(IMPORTS) -g -unittest -ofbin/harbored-tests
	./bin/harbored-tests
	rm -f bin/*.o
	rm -f bin/harbored-tests


clean:
	rm -rf bin/

doc:
	./bin/harbored src/
