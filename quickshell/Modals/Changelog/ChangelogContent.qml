import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    readonly property real logoSize: Math.round(Theme.iconSize * 2.8)
    readonly property real badgeHeight: Math.round(Theme.fontSizeSmall * 1.7)

    topPadding: Theme.spacingL
    spacing: Theme.spacingL

    Column {
        width: parent.width
        spacing: Theme.spacingM

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingM

            Image {
                width: root.logoSize
                height: width * (569.94629 / 506.50931)
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
                source: "file://" + Theme.shellDir + "/assets/danklogonormal.svg"
                layer.enabled: true
                layer.smooth: true
                layer.mipmap: true
                layer.effect: MultiEffect {
                    saturation: 0
                    colorization: 1
                    colorizationColor: Theme.primary
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Row {
                    spacing: Theme.spacingS

                    StyledText {
                        text: "DMS " + ChangelogService.currentVersion
                        font.pixelSize: Theme.fontSizeXLarge + 2
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: codenameText.implicitWidth + Theme.spacingM * 2
                        height: root.badgeHeight
                        radius: root.badgeHeight / 2
                        color: Theme.primaryContainer
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: codenameText
                            anchors.centerIn: parent
                            text: "Spicy Miso"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.primary
                        }
                    }
                }

                StyledText {
                    text: "Desktop widgets, theme registry, native clipboard & more"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineMedium
        opacity: 0.3
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: "What's New"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Grid {
            width: parent.width
            columns: 2
            rowSpacing: Theme.spacingS
            columnSpacing: Theme.spacingS

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "widgets"
                title: "Desktop Widgets"
                description: "Widgets on your desktop"
                onClicked: PopoutService.openSettingsWithTab("desktop_widgets")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "palette"
                title: "Theme Registry"
                description: "Community themes"
                onClicked: PopoutService.openSettingsWithTab("theme")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "content_paste"
                title: "Native Clipboard"
                description: "Zero-dependency history"
                onClicked: PopoutService.openSettingsWithTab("clipboard")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "display_settings"
                title: "Monitor Config"
                description: "Full display setup"
                onClicked: PopoutService.openSettingsWithTab("display_config")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "notifications_active"
                title: "Notifications"
                description: "History & gestures"
                onClicked: PopoutService.openSettingsWithTab("notifications")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "healing"
                title: "DMS Doctor"
                description: "Diagnose issues"
                onClicked: FirstLaunchService.showDoctor()
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "keyboard"
                title: "Keybinds Editor"
                description: "niri, Hyprland, & MangoWC"
                visible: KeybindsService.available
                onClicked: PopoutService.openSettingsWithTab("keybinds")
            }

            ChangelogFeatureCard {
                width: (parent.width - Theme.spacingS) / 2
                iconName: "search"
                title: "Settings Search"
                description: "Find settings fast"
                onClicked: PopoutService.openSettings()
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineMedium
        opacity: 0.3
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: "warning"
                size: Theme.iconSizeSmall
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Upgrade Notes"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            width: parent.width
            height: upgradeNotesColumn.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.warning, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(Theme.warning, 0.2)

            Column {
                id: upgradeNotesColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                ChangelogUpgradeNote {
                    width: parent.width
                    text: "Ghostty theme path changed to ~/.config/ghostty/themes/danktheme"
                }

                ChangelogUpgradeNote {
                    width: parent.width
                    text: "VS Code theme reinstall required"
                }

                ChangelogUpgradeNote {
                    width: parent.width
                    text: "Clipboard history migration available from cliphist"
                }
            }
        }

        StyledText {
            text: "See full release notes for migration steps"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
        }
    }
}
