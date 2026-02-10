pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

// Reusable ListView/GridView transitions
Singleton {
    id: root

    readonly property Transition add: Transition {
        DankAnim {
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.expressiveDurations.expressiveEffects
            easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
        }
    }

    readonly property Transition remove: Transition {
        DankAnim {
            property: "opacity"
            to: 0
            duration: Theme.expressiveDurations.fast
            easing.bezierCurve: Theme.expressiveCurves.emphasizedAccel
        }
    }

    readonly property Transition displaced: Transition {
        DankAnim {
            property: "y"
            duration: Theme.expressiveDurations.normal
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    readonly property Transition move: Transition {
        DankAnim {
            property: "y"
            duration: Theme.expressiveDurations.normal
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }
}
