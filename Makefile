VERSION ?= 1.1.0
APP := dist/StickyTop.app

.PHONY: build test app run install quit dmg verify verify-dodge clean

build:            ## Debug build
	swift build

test:             ## Unit tests
	swift test

app:              ## Release StickyTop.app (universal, ad-hoc signed) in dist/
	VERSION=$(VERSION) scripts/build-app.sh

run: app          ## Build and launch the app bundle
	@$(MAKE) --no-print-directory quit
	open $(APP)

install: app      ## Copy to /Applications and launch
	@$(MAKE) --no-print-directory quit
	rm -rf /Applications/StickyTop.app
	cp -R $(APP) /Applications/
	open /Applications/StickyTop.app

quit:             ## Quit StickyTop and wait until it has exited
	@-pkill -x StickyTop; for i in $$(seq 50); do pgrep -x StickyTop >/dev/null || break; sleep 0.1; done

dmg: app          ## Drag-to-install disk image in dist/
	scripts/make-dmg.sh

verify:           ## Check notes float over a full-screen app (StickyTop must be running)
	@mkdir -p build
	swiftc -O scripts/overlay-probe.swift -o build/overlay-probe
	build/overlay-probe build/overlay-probe.png

verify-dodge:     ## Real Accessibility test of Dodge Text Cursor (installed app must have access)
	@mkdir -p build/DodgeProbe.app/Contents/MacOS
	swiftc -O scripts/dodge-probe.swift -o build/DodgeProbe.app/Contents/MacOS/DodgeProbe
	@/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string DodgeProbe' -c 'Add :CFBundleIdentifier string com.sanskarpal.StickyTop.DodgeProbe' -c 'Add :CFBundlePackageType string APPL' build/DodgeProbe.app/Contents/Info.plist >/dev/null 2>&1 || true
	@codesign --force --sign - build/DodgeProbe.app
	@rm -f build/dodge-probe.log
	open -W -n $(if $(CONTROL),--env PROBE_CONTROL=1) $(if $(TRACE),--env PROBE_TRACE=1) --stdout $(CURDIR)/build/dodge-probe.log --stderr $(CURDIR)/build/dodge-probe.log build/DodgeProbe.app
	@cat build/dodge-probe.log
	@grep -q '^PASS' build/dodge-probe.log

clean:
	rm -rf .build build dist
