import QtQuick
import qs.Common
import qs.Modals
import qs.Services
import qs.Widgets
import qs.Modules.Settings.DisplayConfig

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string selectedProfileId: SettingsData.getActiveDisplayProfile(CompositorService.compositor)
    property bool showNewProfileDialog: false
    property bool showDeleteConfirmDialog: false
    property bool showRenameDialog: false
    property string newProfileName: ""
    property string renameProfileName: ""

    function getProfileOptions() {
        const profiles = DisplayConfigState.validatedProfiles;
        const options = [];
        for (const id in profiles)
            options.push(profiles[id].name);
        return options;
    }

    function getProfileIds() {
        return Object.keys(DisplayConfigState.validatedProfiles);
    }

    function getProfileIdByName(name) {
        const profiles = DisplayConfigState.validatedProfiles;
        for (const id in profiles) {
            if (profiles[id].name === name)
                return id;
        }
        return "";
    }

    function getProfileNameById(id) {
        const profiles = DisplayConfigState.validatedProfiles;
        return profiles[id]?.name || "";
    }

    Connections {
        target: DisplayConfigState
        function onChangesApplied(changeDescriptions) {
            confirmationModal.changes = changeDescriptions;
            confirmationModal.open();
        }
        function onChangesConfirmed() {
        }
        function onChangesReverted() {
        }
        function onProfileActivated(profileId, profileName) {
            root.selectedProfileId = profileId;
            ToastService.showInfo(I18n.tr("Profile activated: %1").arg(profileName));
        }
        function onProfileSaved(profileId, profileName) {
            root.selectedProfileId = profileId;
            ToastService.showInfo(I18n.tr("Profile saved: %1").arg(profileName));
        }
        function onProfileDeleted(profileId) {
            root.selectedProfileId = SettingsData.getActiveDisplayProfile(CompositorService.compositor);
            ToastService.showInfo(I18n.tr("Profile deleted"));
        }
        function onProfileError(message) {
            ToastService.showError(I18n.tr("Profile error"), message);
        }
    }

    DankFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL
        contentWidth: width

        Column {
            id: mainColumn
            topPadding: 4

            width: Math.min(550, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXL

            IncludeWarningBox {
                width: parent.width
            }

            StyledRect {
                width: parent.width
                height: profileSection.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)
                border.width: 0
                visible: DisplayConfigState.hasOutputBackend

                Column {
                    id: profileSection
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "tune"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Theme.iconSize - Theme.spacingM - autoSelectColumn.width - Theme.spacingM
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: I18n.tr("Display Profiles")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledText {
                                text: I18n.tr("Save and switch between display configurations")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }
                        }

                        // ! TODO - auto profile switching is buggy on niri and other compositors
                        Column {
                            id: autoSelectColumn
                            visible: false // disabled for now
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: I18n.tr("Auto")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            DankToggle {
                                id: autoSelectToggle
                                checked: false // disabled for now
                                enabled: false
                                onToggled: checked => {
                                // disabled for now
                                // SettingsData.displayProfileAutoSelect = checked;
                                // SettingsData.saveSettings();
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.showNewProfileDialog && !root.showDeleteConfirmDialog && !root.showRenameDialog

                        DankDropdown {
                            id: profileDropdown
                            width: parent.width - newButton.width - deleteButton.width - Theme.spacingS * 2
                            compactMode: true
                            dropdownWidth: width
                            options: root.getProfileOptions()
                            currentValue: root.getProfileNameById(root.selectedProfileId)
                            emptyText: I18n.tr("No profiles")
                            onValueChanged: value => {
                                const profileId = root.getProfileIdByName(value);
                                if (profileId && profileId !== root.selectedProfileId)
                                    DisplayConfigState.activateProfile(profileId);
                            }
                        }

                        DankButton {
                            id: newButton
                            iconName: "add"
                            text: ""
                            buttonHeight: 40
                            horizontalPadding: Theme.spacingM
                            backgroundColor: Theme.surfaceContainer
                            textColor: Theme.surfaceText
                            onClicked: {
                                root.newProfileName = "";
                                root.showNewProfileDialog = true;
                            }
                        }

                        DankButton {
                            id: deleteButton
                            iconName: "delete"
                            text: ""
                            buttonHeight: 40
                            horizontalPadding: Theme.spacingM
                            backgroundColor: Theme.surfaceContainer
                            textColor: Theme.error
                            enabled: root.selectedProfileId !== ""
                            onClicked: root.showDeleteConfirmDialog = true
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: newProfileRow.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainer
                        visible: root.showNewProfileDialog

                        Row {
                            id: newProfileRow
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            DankTextField {
                                id: newProfileField
                                width: parent.width - createButton.width - cancelNewButton.width - Theme.spacingS * 2
                                placeholderText: I18n.tr("Profile name")
                                text: root.newProfileName
                                onTextChanged: root.newProfileName = text
                                onAccepted: {
                                    if (text.trim())
                                        DisplayConfigState.createProfile(text.trim());
                                    root.showNewProfileDialog = false;
                                }
                                Component.onCompleted: forceActiveFocus()
                            }

                            DankButton {
                                id: createButton
                                text: I18n.tr("Create")
                                enabled: root.newProfileName.trim() !== ""
                                onClicked: {
                                    DisplayConfigState.createProfile(root.newProfileName.trim());
                                    root.showNewProfileDialog = false;
                                }
                            }

                            DankButton {
                                id: cancelNewButton
                                text: I18n.tr("Cancel")
                                backgroundColor: "transparent"
                                textColor: Theme.surfaceText
                                onClicked: root.showNewProfileDialog = false
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: deleteConfirmColumn.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainer
                        visible: root.showDeleteConfirmDialog

                        Column {
                            id: deleteConfirmColumn
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS

                            StyledText {
                                text: I18n.tr("Delete profile \"%1\"?").arg(root.getProfileNameById(root.selectedProfileId))
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                width: parent.width
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignLeft
                            }

                            Row {
                                spacing: Theme.spacingS
                                anchors.right: parent.right

                                DankButton {
                                    text: I18n.tr("Delete")
                                    backgroundColor: Theme.error
                                    textColor: Theme.primaryText
                                    onClicked: {
                                        DisplayConfigState.deleteProfile(root.selectedProfileId);
                                        root.showDeleteConfirmDialog = false;
                                    }
                                }

                                DankButton {
                                    text: I18n.tr("Cancel")
                                    backgroundColor: "transparent"
                                    textColor: Theme.surfaceText
                                    onClicked: root.showDeleteConfirmDialog = false
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: DisplayConfigState.matchedProfile !== ""

                        DankIcon {
                            name: "check_circle"
                            size: 16
                            color: Theme.success
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Matches profile: %1").arg(root.getProfileNameById(DisplayConfigState.matchedProfile))
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.success
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: monitorConfigSection.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.2)
                border.width: 0
                visible: DisplayConfigState.hasOutputBackend

                Column {
                    id: monitorConfigSection
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "monitor"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Theme.iconSize - Theme.spacingM - (displayFormatColumn.visible ? displayFormatColumn.width + Theme.spacingM : 0) - (snapColumn.visible ? snapColumn.width + Theme.spacingM : 0)
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: I18n.tr("Monitor Configuration")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledText {
                                text: I18n.tr("Arrange displays and configure resolution, refresh rate, and VRR")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }
                        }

                        Column {
                            id: snapColumn
                            visible: true
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: I18n.tr("Snap")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            DankToggle {
                                id: snapToggle
                                checked: SettingsData.displaySnapToEdge
                                onToggled: checked => {
                                    SettingsData.displaySnapToEdge = checked;
                                    SettingsData.saveSettings();
                                }
                            }
                        }

                        Column {
                            id: displayFormatColumn
                            visible: !CompositorService.isDwl
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: I18n.tr("Config Format")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            DankButtonGroup {
                                id: displayFormatGroup
                                model: [I18n.tr("Name"), I18n.tr("Model")]
                                currentIndex: SettingsData.displayNameMode === "model" ? 1 : 0
                                onSelectionChanged: (index, selected) => {
                                    if (!selected)
                                        return;
                                    const newMode = index === 1 ? "model" : "system";
                                    DisplayConfigState.setOriginalDisplayNameMode(SettingsData.displayNameMode);
                                    SettingsData.displayNameMode = newMode;
                                }

                                Connections {
                                    target: SettingsData
                                    function onDisplayNameModeChanged() {
                                        displayFormatGroup.currentIndex = SettingsData.displayNameMode === "model" ? 1 : 0;
                                    }
                                }
                            }
                        }
                    }

                    MonitorCanvas {
                        width: parent.width
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS
                            visible: {
                                const all = DisplayConfigState.allOutputs || {};
                                const disconnected = Object.keys(all).filter(k => !all[k]?.connected);
                                return disconnected.length > 0;
                            }

                            StyledText {
                                text: {
                                    const all = DisplayConfigState.allOutputs || {};
                                    const disconnected = Object.keys(all).filter(k => !all[k]?.connected);
                                    if (SettingsData.displayShowDisconnected)
                                        return I18n.tr("%1 disconnected").arg(disconnected.length);
                                    return I18n.tr("%1 disconnected (hidden)").arg(disconnected.length);
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: SettingsData.displayShowDisconnected ? I18n.tr("Hide") : I18n.tr("Show")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        SettingsData.displayShowDisconnected = !SettingsData.displayShowDisconnected;
                                        SettingsData.saveSettings();
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: {
                                const keys = Object.keys(DisplayConfigState.allOutputs || {});
                                if (SettingsData.displayShowDisconnected)
                                    return keys;
                                return keys.filter(k => DisplayConfigState.allOutputs[k]?.connected);
                            }

                            delegate: OutputCard {
                                required property string modelData
                                outputName: modelData
                                outputData: DisplayConfigState.allOutputs[modelData]
                            }
                        }
                    }

                    Row {
                        LayoutMirroring.enabled: false
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: DisplayConfigState.hasPendingChanges
                        layoutDirection: Qt.RightToLeft

                        DankButton {
                            text: I18n.tr("Apply Changes")
                            iconName: "check"
                            onClicked: DisplayConfigState.applyChanges()
                        }

                        DankButton {
                            text: I18n.tr("Discard")
                            backgroundColor: "transparent"
                            textColor: Theme.surfaceText
                            onClicked: DisplayConfigState.discardChanges()
                        }
                    }
                }
            }

            NoBackendMessage {
                width: parent.width
                visible: !DisplayConfigState.hasOutputBackend
            }
        }
    }

    DisplayConfirmationModal {
        id: confirmationModal
        onConfirmed: DisplayConfigState.confirmChanges()
        onReverted: DisplayConfigState.revertChanges()
    }
}
