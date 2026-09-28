VERSION ?= 1.0.0
APP := dist/StickyTop.app

.PHONY: build test app run install dmg verify clean

build:            ## Debug build
	swift build

test:             ## Unit tests
	swift test

app:              ## Release StickyTop.app (universal, ad-hoc signed) in dist/
	VERSION=$(VERSION) scripts/build-app.sh

run: app          ## Build and launch the app bundle
	-pkill -x StickyTop
	open $(APP)

install: app      ## Copy to /Applications and launch
	-pkill -x StickyTop
	rm -rf /Applications/StickyTop.app
	cp -R $(APP) /Applications/
	open /Applications/StickyTop.app

dmg: app          ## Drag-to-install disk image in dist/
	scripts/make-dmg.sh

verify:           ## Check notes float over a full-screen app (StickyTop must be running)
	@mkdir -p build
	swiftc -O scripts/overlay-probe.swift -o build/overlay-probe
	build/overlay-probe build/overlay-probe.png

clean:
	rm -rf .build build dist
