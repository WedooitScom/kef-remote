# Raccourcis pour le client macOS KEF Remote.
.PHONY: build test app run demo live-test clean

build:
	swift build

test:
	swift test

# Bundle « build/KEF Remote.app » (release, icône, signature ad hoc).
app:
	./build-app.sh

run: app
	open "build/KEF Remote.app"

demo: app
	open -n "build/KEF Remote.app" --args --demo

# Tests en lecture seule contre une vraie enceinte : make live-test HOST=192.168.1.20
live-test:
	KEF_LIVE_HOST=$(HOST) swift test --filter LiveSpeakerTests

clean:
	rm -rf .build build
