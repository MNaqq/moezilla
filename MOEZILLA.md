# Moezilla development fork

Moezilla is a community fork of [Reynard](https://github.com/minh-ton/reynard-browser) with an independently installable bundle ID, com.bonewizardry.Moezilla, and a moezilla://open?url=... link scheme.

## Work in this branch

- Webpage keyboard: a targeted iOS 27 compatibility path sends ordinary single-character software keyboard input through Gecko's native text-replacement pipeline, also used for Paste. Composition, Return, and earlier iOS versions keep the original implementation.
- Browser bar: its keyboard docking now recognizes direct address-text editing, even if the search overlay focus lags behind, and expands a previously collapsed toolbar.
- Developer settings: **Continue debugging in background** starts a user-initiated BGContinuedProcessingTask (iOS 26+) while USB remote debugging is enabled. Earlier iOS versions request short, limited beginBackgroundTask time. Explicitly turning it off ends the task.
- Gecko's foreground lifecycle remains active while an allowed continued-processing task is active, and is restored when the session ends. Upon foregrounding, USB debugging preferences are reapplied.

### USB debugging

Under **Settings > Advanced > Developer**, turn on Remote Debugging via USB and then enable Continue debugging in background. On the Mac, pair the device and run iproxy 6000:6000 with libimobiledevice, then connect Firefox about:debugging to localhost:6000.

iOS controls whether continued processing is granted and when the task is suspended or expired. It does not provide an indefinite background execution guarantee. If iOS ends the task, Moezilla restores the debugger preferences and automatically re-requests execution when the app returns to foreground, but only for a previously user-started session. Turning off the switch clears that intent.

### Development validation

Apply the repository's Gecko patch series to the Firefox submodule, build the Gecko engine, and build the iOS Xcode project. On Xcode 27 use tools/development/build-gecko.sh --use-apple-linker --auto-clobber to avoid Firefox 159's bundled LLD failing on the new arm64e.x1 iOS SDK stubs. Test key entry and paste on a real device running iOS 27 in Reddit search and a plain HTML input, test URL editing while the onscreen keyboard is visible, then verify the USB debugging connection survives a foreground-to-background transition when iOS grants a continued-processing task.

This fork retains Reynard's license and attribution. Code is experimental until tested on a real device.

### Debug signing on the paired iPhone

The Debug configuration uses standard development entitlements so Xcode can sign
with the team's wildcard provisioning profile. Apple's bundle ID capabilities
API cannot enable INCREASED_MEMORY_LIMIT on a new identifier. Release retains
the original increased-memory entitlement for use when a matching Apple profile
is available. The Debug build must still be functionally tested on-device.
