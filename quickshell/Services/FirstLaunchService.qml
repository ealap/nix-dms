pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation)) + "/DankMaterialShell"
    readonly property string settingsPath: configDir + "/settings.json"
    readonly property string firstLaunchMarkerPath: configDir + "/.firstlaunch"

    property bool isFirstLaunch: false
    property bool checkComplete: false
    property bool greeterDismissed: false
    property int requestedStartPage: 0

    readonly property bool shouldShowGreeter: checkComplete && isFirstLaunch && !greeterDismissed

    signal greeterRequested
    signal greeterCompleted

    function showGreeter(startPage) {
        requestedStartPage = startPage || 0;
        greeterRequested();
    }

    function showWelcome() {
        showGreeter(0);
    }

    function showDoctor() {
        showGreeter(1);
    }

    Component.onCompleted: {
        checkFirstLaunch();
    }

    function checkFirstLaunch() {
        firstLaunchCheckProcess.running = true;
    }

    function markFirstLaunchComplete() {
        greeterDismissed = true;
        touchMarkerProcess.running = true;
        greeterCompleted();
    }

    function dismissGreeter() {
        greeterDismissed = true;
    }

    Process {
        id: firstLaunchCheckProcess

        command: ["sh", "-c", `
            SETTINGS='` + settingsPath + `'
            MARKER='` + firstLaunchMarkerPath + `'
            if [ -f "$MARKER" ]; then
                echo 'skip'
            elif [ -f "$SETTINGS" ]; then
                echo 'existing_user'
            else
                echo 'first'
            fi
        `]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const result = data.trim();

                if (result === "first") {
                    root.isFirstLaunch = true;
                    console.info("FirstLaunchService: First launch detected, greeter will be shown");
                } else if (result === "existing_user") {
                    root.isFirstLaunch = false;
                    console.info("FirstLaunchService: Existing user detected, silently creating marker");
                    touchMarkerProcess.running = true;
                } else {
                    root.isFirstLaunch = false;
                }

                root.checkComplete = true;

                if (root.isFirstLaunch)
                    root.greeterRequested();
            }
        }
    }

    Process {
        id: touchMarkerProcess

        command: ["sh", "-c", "mkdir -p '" + configDir + "' && touch '" + firstLaunchMarkerPath + "'"]
        running: false

        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("FirstLaunchService: First launch marker created");
            } else {
                console.warn("FirstLaunchService: Failed to create first launch marker");
            }
        }
    }
}
