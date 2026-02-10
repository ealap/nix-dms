import QtQuick
import qs.Common

// Material Design 3 ripple effect component
MouseArea {
    id: root

    property color rippleColor: Theme.primary
    property real cornerRadius: 0
    property bool enableRipple: typeof SettingsData !== "undefined" ? (SettingsData.enableRippleEffects ?? true) : true

    property real _rippleX: 0
    property real _rippleY: 0
    property real _rippleRadius: 0

    enabled: false
    hoverEnabled: false

    function trigger(x, y) {
        if (!enableRipple || Theme.currentAnimationSpeed === SettingsData.AnimationSpeed.None)
            return;

        _rippleX = x;
        _rippleY = y;

        const dist = (ox, oy) => ox * ox + oy * oy;
        _rippleRadius = Math.sqrt(Math.max(dist(x, y), dist(x, height - y), dist(width - x, y), dist(width - x, height - y)));

        rippleAnim.restart();
    }

    SequentialAnimation {
        id: rippleAnim

        PropertyAction {
            target: ripple
            property: "x"
            value: root._rippleX
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: root._rippleY
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 0.08
        }

        ParallelAnimation {
            DankAnim {
                target: ripple
                property: "implicitWidth"
                from: 0
                to: root._rippleRadius * 2
                duration: Theme.expressiveDurations.expressiveEffects
                easing.bezierCurve: Theme.expressiveCurves.standardDecel
            }
            DankAnim {
                target: ripple
                property: "implicitHeight"
                from: 0
                to: root._rippleRadius * 2
                duration: Theme.expressiveDurations.expressiveEffects
                easing.bezierCurve: Theme.expressiveCurves.standardDecel
            }
        }

        DankAnim {
            target: ripple
            property: "opacity"
            to: 0
            duration: Theme.expressiveDurations.expressiveEffects
            easing.bezierCurve: Theme.expressiveCurves.standard
        }
    }

    Rectangle {
        id: ripple

        radius: Math.min(width, height) / 2
        color: root.rippleColor
        opacity: 0

        transform: Translate {
            x: -ripple.width / 2
            y: -ripple.height / 2
        }
    }
}
