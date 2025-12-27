.PHONY: all build clean test snapshot fmt

all: build

build:
	forge build

clean:
	forge clean

test:
	forge test -vvv

snapshot:
	forge snapshot

fmt:
	forge fmt
