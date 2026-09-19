.PHONY: build test run app clean

build:
	swift build

test:
	swift test

run:
	swift run PaneSpace

app:
	./scripts/build-app.sh

clean:
	swift package clean
	rm -rf dist
