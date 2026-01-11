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
    property bool lockInitiatedLocally: false
    property bool pendingLock: false

    Component.onCompleted: {
        IdleService.lockComponent = this;
    }

    function notifyLoginctl(lockAction: bool) {
        if (!SettingsData.loginctlLockIntegration || !DMSService.isConnected)
            return;
        if (lockAction)
            DMSService.lockSession(() => {});
        else
            DMSService.unlockSession(() => {});
    }

    function lock() {
        if (SettingsData.customPowerActionLock?.length > 0) {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionLock]);
            return;
        }
        if (shouldLock || pendingLock)
            return;

        lockInitiatedLocally = true;

        if (!SessionService.active && SessionService.loginctlAvailable) {
            pendingLock = true;
            notifyLoginctl(true);
            return;
        }

        shouldLock = true;
        notifyLoginctl(true);
    }

    function unlock() {
        if (!shouldLock)
            return;
        lockInitiatedLocally = false;
        notifyLoginctl(false);
        shouldLock = false;
    }

    function forceReset() {
        lockInitiatedLocally = false;
        pendingLock = false;
        shouldLock = false;
    }

    function activate() {
        lock();
    }

    Connections {
        target: SessionService

        function onSessionLocked() {
            if (shouldLock || pendingLock)
                return;
            if (!SessionService.active && SessionService.loginctlAvailable) {
                pendingLock = true;
                lockInitiatedLocally = false;
                return;
            }
            lockInitiatedLocally = false;
            shouldLock = true;
        }

        function onSessionUnlocked() {
            if (pendingLock) {
                pendingLock = false;
                lockInitiatedLocally = false;
                return;
            }
            if (!shouldLock || lockInitiatedLocally)
                return;
            shouldLock = false;
        }

        function onLoginctlStateChanged() {
            if (SessionService.active && pendingLock) {
                pendingLock = false;
                lockInitiatedLocally = true;
                shouldLock = true;
                return;
            }
            if (SessionService.locked && !shouldLock && !pendingLock) {
                lockInitiatedLocally = false;
                shouldLock = true;
            }
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
            if (locked) {
                pendingLock = false;
                dpmsReapplyTimer.start();
            }
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
                onUnlockRequested: root.unlock()
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
            root.lock();
        }

        function unlock() {
            root.unlock();
        }

        function forceReset() {
            root.forceReset();
        }

        function demo() {
            demoWindow.showDemo();
        }

        function isLocked(): bool {
            return sessionLock.locked;
        }

        function status(): string {
            return JSON.stringify({
                shouldLock: root.shouldLock,
                sessionLockLocked: sessionLock.locked,
                lockInitiatedLocally: root.lockInitiatedLocally,
                pendingLock: root.pendingLock,
                loginctlLocked: SessionService.locked,
                loginctlActive: SessionService.active
            });
        }
    }

    Timer {
        id: dpmsReapplyTimer
        interval: 100
        repeat: false
        onTriggered: IdleService.reapplyDpmsIfNeeded()
    }
}
