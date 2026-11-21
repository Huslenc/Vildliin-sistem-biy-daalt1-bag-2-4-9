CC ?= gcc
CFLAGS = -Wall -Wextra -O2 -pthread
SRC = src/tpdemo.c src/threadpool.c

tpdemo: $(SRC) src/threadpool.h
	$(CC) $(CFLAGS) -o tpdemo $(SRC)

# sanitizer builds (Linux gcc/clang): run with  make tsan && ./tpdemo_tsan 4 4 20 10 50 0 1
tsan: $(SRC) src/threadpool.h
	$(CC) -Wall -Wextra -O1 -g -pthread -fsanitize=thread -o tpdemo_tsan $(SRC)
asan: $(SRC) src/threadpool.h
	$(CC) -Wall -Wextra -O1 -g -pthread -fsanitize=address,undefined -o tpdemo_asan $(SRC)

test: tpdemo
	sh tests/run_tests.sh
	python3 tests/test_server.py
	sh tests/check_docs.sh

# slower checks: stability (30 seeds), worker scaling table, sanitizers
bench: tpdemo
	sh tests/bench.sh

clean:
	rm -f tpdemo tpdemo_tsan tpdemo_asan
