CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -pthread

tpdemo: src/tpdemo.c src/threadpool.c src/threadpool.h
	$(CC) $(CFLAGS) -o $@ src/tpdemo.c src/threadpool.c

tsan:
	$(CC) -O1 -g -Wall -Wextra -pthread -fsanitize=thread -o tpdemo src/tpdemo.c src/threadpool.c

test: tpdemo
	sh tests/run_tests.sh

clean:
	rm -f tpdemo

.PHONY: tsan test clean
