.PHONY: build test run app install clean

INSTALL_DIR ?= /Applications

build:
	swift build

test:
	swift test

run:
	swift run PaneSpace

app:
	./scripts/build-app.sh

# Replacing a running bundle can leave the app in a broken state, so refuse until it is quit.
install: app
	@if pgrep -f "$(INSTALL_DIR)/PaneSpace.app/Contents/MacOS/PaneSpace" >/dev/null; then \
		echo "PaneSpace is running from $(INSTALL_DIR). Quit it, then run make install again."; \
		exit 1; \
	fi
	rm -rf "$(INSTALL_DIR)/PaneSpace.app"
	ditto dist/PaneSpace.app "$(INSTALL_DIR)/PaneSpace.app"
	codesign --verify --deep --strict "$(INSTALL_DIR)/PaneSpace.app"
	@echo "Installed $(INSTALL_DIR)/PaneSpace.app"

clean:
	swift package clean
	rm -rf dist
