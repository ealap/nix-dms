pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Scope {
    id: root

    property string sharedPasswordBuffer: ""
    property bool shouldLock: false
    property bool processingExternalEvent: false

    Component.onCompleted: {
        IdleService.lockComponent = this;
    }

    function lock() {
        if (SettingsData.customPowerActionLock && SettingsData.customPowerActionLock.length > 0) {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionLock]);
            return;
        }
        shouldLock = true;
        if (!processingExternalEvent && SettingsData.loginctlLockIntegration && DMSService.isConnected) {
            DMSService.lockSession(response => {
                if (response.error)
                    console.warn("Lock: loginctl.lock failed:", response.error);
            });
        }
    }

    function unlock() {
        if (!processingExternalEvent && SettingsData.loginctlLockIntegration && DMSService.isConnected) {
            DMSService.unlockSession(response => {
                if (response.error) {
                    console.warn("Lock: Failed to call loginctl.unlock:", response.error);
                    shouldLock = false;
                }
            });
        } else {
            shouldLock = false;
        }
    }

    function activate() {
        lock();
    }

    Connections {
        target: SessionService

        function onSessionLocked() {
            processingExternalEvent = true;
            shouldLock = true;
            processingExternalEvent = false;
        }

        function onSessionUnlocked() {
            processingExternalEvent = true;
            shouldLock = false;
            processingExternalEvent = false;
        }
    }

    Connections {
        target: IdleService

        function onLockRequested() {
            lock();
        }
    }

    WlSessionLock {
        id: sessionLock

        locked: shouldLock

        onLockedChanged: {
            if (locked)
                dpmsReapplyTimer.start();
        }

        WlSessionLockSurface {
            id: lockSurface

            property string currentScreenName: screen?.name ?? ""
            property bool isActiveScreen: {
                if (Quickshell.screens.length <= 1)
                    return true;
                if (SettingsData.lockScreenActiveMonitor === "all")
                    return true;
                return currentScreenName === SettingsData.lockScreenActiveMonitor;
            }

            color: isActiveScreen ? "transparent" : SettingsData.lockScreenInactiveColor

            LockSurface {
                anchors.fill: parent
                visible: lockSurface.isActiveScreen
                lock: sessionLock
                sharedPasswordBuffer: root.sharedPasswordBuffer
                screenName: lockSurface.currentScreenName
                isLocked: shouldLock
                onUnlockRequested: {
                    root.unlock();
                }
                onPasswordChanged: newPassword => {
                    root.sharedPasswordBuffer = newPassword;
                }
            }
        }
    }

    LockScreenDemo {
        id: demoWindow
    }

    IpcHandler {
        target: "lock"

        function lock() {
            root.shouldLock = true;
            if (SettingsData.loginctlLockIntegration && DMSService.isConnected) {
                DMSService.lockSession(response => {
                    if (response.error)
                        console.warn("Lock: loginctl.lock failed:", response.error);
                });
            }
        }

        function demo() {
            demoWindow.showDemo();
        }

        function isLocked(): bool {
            return sessionLock.locked;
        }
    }

    Timer {
        id: dpmsReapplyTimer
        interval: 100
        repeat: false
        onTriggered: IdleService.reapplyDpmsIfNeeded()
    }
}
