/**
 * FlyViewCustomLayer.qml
 * DEEPSEE C2 Station — Custom UI overlay for QGroundControl
 * Crown & Eagle Engineering
 *
 * Layout overview:
 *   ┌───────────────────────────────────────────────────────┐
 *   │                    TOP STATUS BAR                     │
 *   ├─────────────┬─────────────────────────┬───────────────┤
 *   │  LEFT       │   QGC MAP (managed by   │   RIGHT       │
 *   │  SIDEBAR    │   QGC — do not touch)   │  TELEMETRY    │
 *   ├─────────────┴─────────────────────────┴───────────────┤
 *   │                    COMMAND STRIP                      │
 *   └───────────────────────────────────────────────────────┘
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap
import QGroundControl.VideoManager
import QGroundControl.Vehicle

Item {
    id: root

    // ─────────────────────────────────────────────────────────────────────
    // REQUIRED INTERFACE PROPERTIES  (consumed by QGC's FlyView host)
    // ─────────────────────────────────────────────────────────────────────
    property var parentToolInsets
    property var totalToolInsets: _totalToolInsets
    property var mapControl
    property var _rosBridgeClient: (QGroundControl.corePlugin && QGroundControl.corePlugin.rosBridgeClient)
                                   ? QGroundControl.corePlugin.rosBridgeClient
                                   : localRosBridgeClient

    // ─────────────────────────────────────────────────────────────────────
    // LAYOUT CONSTANTS
    // ─────────────────────────────────────────────────────────────────────
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle

    property var _planMasterController: globals.planMasterControllerFlyView
    property var _missionController:    _planMasterController ? _planMasterController.missionController : null
    property int _currentWpIndex:       _missionController ? _missionController.currentMissionIndex    : 0
    property int _totalWpCount:         _missionController ? _missionController.missionItemCount       : 0
    property var _activeWpItem:         (_missionController && _missionController.visualItems && _currentWpIndex < _missionController.visualItems.count)
                                        ? _missionController.visualItems.get(_currentWpIndex) : null

    readonly property real _topBarHeight:    56
    readonly property real _leftPanelWidth:  260
    readonly property real _rightPanelWidth: 260
    readonly property real _bottomBarHeight: 56

    // ─────────────────────────────────────────────────────────────────────
    // COLOR PALETTE
    // ─────────────────────────────────────────────────────────────────────
    readonly property string _clrPanel:       "#1a1c1f"  // main panel background
    readonly property string _clrCard:        "#2a2d32"  // card / control background
    readonly property string _clrPurple:      "#6a0dad"  // demo accent
    readonly property string _clrPurpleDim:   "#4a006d"  // locked-demo shade
    readonly property string _clrBlue:        "#1565C0"  // badge accent
    readonly property string _clrGreen:       "#4CAF50"  // connected / active / continue
    readonly property string _clrRed:         "#f44336"  // disconnected
    readonly property string _clrOrange:      "#e65100"  // return to home
    readonly property string _clrKill:        "#c62828"  // kill switch / land
    readonly property string _clrMuted:       "#888888"  // secondary text
    readonly property string _clrAmber:       "#f0a500"  // current-action label

    // ─────────────────────────────────────────────────────────────────────
    // LIVE TELEMETRY HELPERS
    // Centralized bindings so telemetry cards stay clean.
    // All values update automatically when the vehicle reports new data.
    // When no vehicle is connected, values show "—".
    // ─────────────────────────────────────────────────────────────────────
    readonly property string _telSpeed:    _activeVehicle ? _activeVehicle.vehicle.groundSpeed.value.toFixed(1) : "—"
    readonly property string _telHeading:  _activeVehicle ? _activeVehicle.vehicle.heading.value.toFixed(0)     : "—"
    readonly property string _telAltitude: _activeVehicle ? _activeVehicle.vehicle.altitudeRelative.value.toFixed(1) : "—"
    readonly property string _telLat:      _activeVehicle ? _activeVehicle.coordinate.latitude.toFixed(6)      : "—"
    readonly property string _telLon:      _activeVehicle ? _activeVehicle.coordinate.longitude.toFixed(6)     : "—"

    readonly property string _unitSpeed:    _activeVehicle ? _activeVehicle.vehicle.groundSpeed.units    : "m/s"
    readonly property string _unitAltitude: _activeVehicle ? _activeVehicle.vehicle.altitudeRelative.units : "m"

    // Battery: first battery in the vehicle's battery list
    property var  _battery:     _activeVehicle && _activeVehicle.batteries.count > 0
                                ? _activeVehicle.batteries.get(0) : null
    property real _batteryPct:  _battery && !isNaN(_battery.percentRemaining.rawValue)
                                ? _battery.percentRemaining.rawValue : -1

    // ─────────────────────────────────────────────────────────────────────
    // FLIGHT MODE
    // PX4 flight mode names used by _activeVehicle.flightMode / setFlightMode.
    //   Position — manual flying with GPS position + altitude hold
    //   Mission  — autonomous waypoint flight
    //   Hold     — pause / loiter at current position
    // Return and Land are handled by dedicated buttons, not the dropdown.
    // ─────────────────────────────────────────────────────────────────────
    readonly property var flightModes: ["Position", "Mission", "Hold"]

    // Read the vehicle's actual current flight mode
    readonly property string _currentFlightMode: _activeVehicle ? _activeVehicle.flightMode : "—"

    // ─────────────────────────────────────────────────────────────────────
    // DEMO STATE
    // selectedDemoIndex: -1 = no demo chosen; 0-3 = one of the four demos
    // demoLocked: true once a demo is selected; cleared by Complete Demo or RTH
    // ─────────────────────────────────────────────────────────────────────
    property int    selectedDemoIndex: -1
    property bool   demoLocked:        false

    // Demo #1 state
    property string demo1Color: "Red"

    // Demo #2 state
    property string demo2Shape: "Triangle"

    // Demo #3 & #4 state — pending selections for the "add asset" row
    property string pendingColor: "Red"
    property string pendingShape: "Triangle"

    // ─────────────────────────────────────────────────────────────────────
    // VEHICLE CONTROL STATE
    // isArmed: toggled by ARM/DISARM button; arming is only permitted in Demo #4
    // ─────────────────────────────────────────────────────────────────────
    property bool isArmed: false

    readonly property bool _canArm: demoLocked

    property int selectedRoundSpecIndex: 0
    property string cameraMode: "survey"
    property string bridgeSendStatus: "Bridge: no sends yet"
    property int selectedMissionRoundIndex: 0
    property string selectedMissionMode: "MANUAL_STEP"
    property int selectedManualTaskIndex: 0
    property string selectedTaskName: "TAKEOFF"
    property string selectedTaskLabel: "TAKEOFF"
    property string selectedGripperAction: ""
    property bool missionPanelCollapsed: false
    property string missionModeDisplay: "MANUAL_STEP"
    property string missionTaskDisplay: "IDLE"
    property string missionAssetDisplay: "Asset 0/0"
    property string missionStatusText: "Waiting for operator command"

    readonly property var missionRoundOptions: ["Round 1", "Round 2", "Round 3", "Round 4"]
    readonly property var missionTaskOptions: [
        { label: "TAKEOFF", task: "TAKEOFF" },
        { label: "SURVEY", task: "SURVEY_FOR_ASSET" },
        { label: "GAAP", task: "GAAP" },
        { label: "BATTLESHIP", task: "BATTLESHIP", round_id: 3 },
        { label: "GRIPPER CLOSE", task: "GRIPPER", gripper_action: "CLOSE" },
        { label: "GRIPPER OPEN", task: "GRIPPER", gripper_action: "OPEN" }
    ]

    property var _arenaOverlay
    property var _fobMarkers: []
    readonly property var roundSpecOptions: [
        {
            label: "Outfield",
            territory: "outfield",
            ceFobCoordinates: [38.75065209603611, -77.49701011362711, 0],
            wvxFobCoordinates: [38.75084010396389, -77.49721463637287, 0],
            geofenceFilePath: ":/Custom/qml/geofences/ce_geofence_outfield.plan"
        },
        {
            label: "Home Base",
            territory: "bases",
            ceFobCoordinates: [38.75084010396389, -77.49721463637287, 0],
            wvxFobCoordinates: [38.75065209603611, -77.49701011362711, 0],
            geofenceFilePath: ":/Custom/qml/geofences/ce_geofence_home_base.plan"
        }
    ]
    readonly property var _arenaPath: [
        QtPositioning.coordinate(38.7507608625056, -77.49735908548331),
        QtPositioning.coordinate(38.75094024382851, -77.49709285710168),
        QtPositioning.coordinate(38.75073132744176, -77.49686508648041),
        QtPositioning.coordinate(38.750551952470936, -77.49713235890398)
    ]
    

    CEVideoStatus {
        id: ceVideoStatus
    }

    QGCRosBridgeClient {
        id: localRosBridgeClient
        host: "127.0.0.1"
        port: 5010
        statusPort: 5011
    }

    readonly property var _bridgeClient: (root._rosBridgeClient ? root._rosBridgeClient : localRosBridgeClient)

    function bridgeCommandSummary(jsonText) {
        try {
            var payload = JSON.parse(jsonText)
            if (payload.type === "mission_command") {
                var detail = payload.task_name || payload.task || payload.mode || ""
                return "Sent: " + payload.command + (detail !== "" ? " " + detail : "")
            }
            if (payload.type === "round_config") {
                return "Sent: ROUND_CONFIG R" + payload.round_id
            }
            if (payload.type === "operator_command") {
                return "Sent: " + payload.command
            }
        } catch (err) {
            return "Sent: bridge message"
        }
        return "Sent: bridge message"
    }

    Connections {
        target: root._bridgeClient
        onMessageSent: function(json) {
            root.bridgeSendStatus = root.bridgeCommandSummary(json)
            console.log("QGC ROS bridge sent:", json)
        }
        onSendFailed: function(reason) {
            root.bridgeSendStatus = "Bridge send failed: " + reason
            console.warn("QGC ROS bridge send failed:", reason)
        }
        onMessageReceived: function(json) {
            root.handleMissionStatusMessage(json)
        }
    }

    readonly property string _videoHealthState: ceVideoStatus.hasStatus ? ceVideoStatus.state : "NO_VIDEO"
    readonly property bool _videoLive: _videoHealthState === "OK"
    readonly property bool _videoStale: _videoHealthState === "STALE"
    readonly property string _videoStatusLabel: _videoLive ? "Video: Live" : (_videoStale ? "Video: Stale" : "Video: No Video")
    readonly property color _videoStatusColor: _videoLive ? _clrGreen : (_videoStale ? _clrAmber : _clrRed)

    // ─────────────────────────────────────────────────────────────────────
    // DEMO LOOKUP TABLES  (read-only data, safe to treat as constants)
    // ─────────────────────────────────────────────────────────────────────
    readonly property var demoNames: [
        "DEMONSTRATION #1: Identify Asset By Color",
        "DEMONSTRATION #2: Identify Asset by Shape",
        "DEMONSTRATION #3: Battleship",
        "DEMONSTRATION #4: Points Round"
    ]

    readonly property var colorOptions:  ["Red", "Orange", "Yellow", "Green", "Blue", "Purple"]
    readonly property var shapeOptions:  ["Triangle", "Circle", "Square", "Heart", "Star", "Hexagon"]

    // Demo #4 (Points Round) adds three special assets on top of the standard shapes.
    readonly property var demo4SpecialShapes: ["Grenade", "Jet Boat", "Grey Tank"]
    readonly property var demo4ShapeOptions:  shapeOptions.concat(demo4SpecialShapes)

    // These special shapes are not paired with a color.
    function isColorlessShape(shape) { return demo4SpecialShapes.indexOf(shape) !== -1 }

    // The Add Asset shape picker is shared by Demo #3 and #4; Demo #4 gets the extra shapes.
    readonly property var assetShapeOptions: selectedDemoIndex === 3 ? demo4ShapeOptions : shapeOptions

    // Demo #4 point values are entered by the operator per asset on the day
    // (the customer supplies them on the spot), so there is no fixed table.

    // ─────────────────────────────────────────────────────────────────────
    // HELPER FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────

    function lockDemo(index) {
        selectedDemoIndex = index
        selectedMissionRoundIndex = index
        demoLocked        = true
    }

    function unlockDemo() {
        demoLocked        = false
        selectedDemoIndex = -1
        selectedMissionRoundIndex = 0
        isArmed           = false
        demo1Color        = "Red"
        demo2Shape        = "Triangle"
        pendingColor      = "Red"
        pendingShape      = "Triangle"
        assetModel.clear()
    }

    function assetList() {
        var assets = []
        for (var i = 0; i < assetModel.count; i++) {
            var asset = assetModel.get(i)
            assets.push({
                color: asset.assetColor,
                shape: asset.assetShape,
                points: asset.points
            })
        }
        return assets
    }

    function targetClass() {
        if (!demoLocked) {
            return "unset"
        }
        if (selectedDemoIndex === 0) {
            return demo1Color.toLowerCase()
        }
        if (selectedDemoIndex === 1) {
            return demo2Shape.toLowerCase()
        }
        if (assetModel.count > 0) {
            var firstAsset = assetModel.get(0)
            var label = firstAsset.assetColor ? (firstAsset.assetColor + "_" + firstAsset.assetShape) : firstAsset.assetShape
            return label.toLowerCase().replace(/[^a-z0-9]+/g, "_")
        }
        return root.demoNames[selectedDemoIndex].toLowerCase().replace(/[^a-z0-9]+/g, "_")
    }

    function assetColor() {
        if (!demoLocked) {
            return "unset"
        }
        if (selectedDemoIndex === 0) {
            return demo1Color.toLowerCase()
        }
        if (assetModel.count > 0) {
            return assetModel.get(0).assetColor.toLowerCase()
        }
        return "unset"
    }

    function selectedTerritory() {
        var roundSpec = roundSpecOptions[selectedRoundSpecIndex]
        return roundSpec && roundSpec.territory ? roundSpec.territory : "outfield"
    }

    function selectedSurveyPlanFile() {
        var territory = selectedTerritory()
        var roundId = demoLocked ? selectedDemoIndex + 1 : selectedMissionRoundId()
        if (roundId === 4) {
            return "full_field_from_" + territory + "_enemy.plan"
        }
        return "enemy_survey_from_" + territory + ".plan"
    }

    function selectedSurveyPlanResourcePath() {
        return ":/Custom/qml/plans/" + selectedSurveyPlanFile()
    }

    function selectedSurveyPlanFilePath() {
        return "/home/izzy/Desktop/CrownEagle/ce_lcp/qgc-interface/scripts/plans/" + selectedSurveyPlanFile()
    }

    function displaySelectedSurveyPlan() {
        if (_planMasterController) {
            var path = selectedSurveyPlanFilePath()
            console.log("Loading C&E survey plan:", path)
            _planMasterController.loadFromFile(path)
        }
    }

    function roundConfigMessage() {
        var roundSpec = roundSpecOptions[selectedRoundSpecIndex]
        return {
            type: "round_config",
            round_id: demoLocked ? selectedDemoIndex + 1 : 0,
            territory: selectedTerritory(),
            target_class: targetClass(),
            asset_color: assetColor(),
            round_spec_label: roundSpec.label,
            fob_coordinates_label: "C&E",
            fob_coordinates: roundSpec.ceFobCoordinates,
            geofence_label: roundSpec.label,
            geofence_plan_file: roundSpec.geofenceFilePath,
            geofence_height_ft: 30,
            camera_mode: cameraMode,
            survey_plan_file: selectedSurveyPlanFile(),
            demo_name: demoLocked ? root.demoNames[selectedDemoIndex] : "",
            assets: assetList()
        }
    }

    function sendRoundConfig() {
        root.bridgeSendStatus = "Sending: ROUND_CONFIG R" + selectedMissionRoundId()
        if (!root._bridgeClient) {
            root.bridgeSendStatus = "Bridge sender unavailable"
            return
        }
        if (!root._bridgeClient.sendJsonMessage(roundConfigMessage())) {
            root.bridgeSendStatus = "Send failed"
            return
        }
        root.displaySelectedSurveyPlan()
    }

    function deploySelectedGeofence() {
        var roundSpec = roundSpecOptions[selectedRoundSpecIndex]
        if (_planMasterController && roundSpec.geofenceFilePath) {
            _planMasterController.loadFromFile(roundSpec.geofenceFilePath)
        }
        showTemporaryMapOverlays()
    }

    function _clearMapObject(object) {
        if (!object) {
            return
        }
        if (mapControl && mapControl.removeMapItem) {
            mapControl.removeMapItem(object)
        }
        object.destroy()
    }

    function clearTemporaryMapOverlays() {
        _clearMapObject(_arenaOverlay)
        _arenaOverlay = null
        for (var i = 0; i < _fobMarkers.length; i++) {
            _clearMapObject(_fobMarkers[i])
        }
        _fobMarkers = []
    }

    function pathCenter(path) {
        var lat = 0
        var lon = 0
        for (var i = 0; i < path.length; i++) {
            lat += path[i].latitude
            lon += path[i].longitude
        }
        return QtPositioning.coordinate(lat / path.length, lon / path.length)
    }

    function showTemporaryMapOverlays() {
        if (!mapControl) {
            return
        }

        clearTemporaryMapOverlays()

        _arenaOverlay = arenaOverlayComponent.createObject(mapControl, {
            path: _arenaPath
        })
        mapControl.addMapItem(_arenaOverlay)

        var selectedSpec = roundSpecOptions[selectedRoundSpecIndex]

        var ceMarker = fobMarkerComponent.createObject(mapControl, {
            coordinate: QtPositioning.coordinate(selectedSpec.ceFobCoordinates[0], selectedSpec.ceFobCoordinates[1], selectedSpec.ceFobCoordinates[2]),
            label: "C&E",
            selected: true
        })
        mapControl.addMapItem(ceMarker)
        _fobMarkers.push(ceMarker)

        var wvxMarker = fobMarkerComponent.createObject(mapControl, {
            coordinate: QtPositioning.coordinate(selectedSpec.wvxFobCoordinates[0], selectedSpec.wvxFobCoordinates[1], selectedSpec.wvxFobCoordinates[2]),
            label: "WvX",
            selected: false
        })
        mapControl.addMapItem(wvxMarker)
        _fobMarkers.push(wvxMarker)

        mapControl.center = QtPositioning.coordinate(38.750765, -77.497116)
        if (mapControl.zoomLevel < 20) {
            mapControl.zoomLevel = 20
        }
    }

    function sendOperatorCommand(commandName) {
        root.bridgeSendStatus = "Sending: " + commandName
        if (!root._bridgeClient) {
            root.bridgeSendStatus = "Bridge sender unavailable"
            return
        }

        var payload = {
            type: "operator_command",
            command: commandName,
            source: "qgc",
            round_id: selectedMissionRoundId(),
        }

        if (!root._bridgeClient.sendJsonMessage(payload)) {
            root.bridgeSendStatus = "Send failed"
        }
    }


    function handleMissionStatusMessage(jsonText) {
        var status = null
        try {
            status = JSON.parse(jsonText)
        } catch (err) {
            missionStatusText = jsonText
            return
        }
        if (!status || status.type !== "mission_status") {
            return
        }
        missionModeDisplay = status.current_mission_mode || missionModeDisplay
        missionTaskDisplay = status.current_task || missionTaskDisplay
        var assetIndex = status.current_asset_index || 0
        var assetTotal = status.total_asset_count || 0
        missionAssetDisplay = "Asset " + assetIndex + "/" + assetTotal
        missionStatusText = status.status_text || status.last_failure_reason || missionStatusText
    }

    function selectedMissionRoundId() {
        return selectedMissionRoundIndex + 1
    }

    function selectMissionTask(taskName, label, gripperAction) {
        selectedTaskName = taskName
        selectedTaskLabel = label || taskName
        selectedGripperAction = gripperAction || ""
        missionTaskDisplay = selectedTaskLabel
        missionStatusText = "Task selected"
    }

    function loadSelectedMissionTask() {
        var payload = {
            task_name: selectedTaskName,
            round_id: demoLocked ? selectedDemoIndex + 1 : selectedMissionRoundId(),
            territory: selectedTerritory()
        }
        if (selectedGripperAction !== "") {
            payload.gripper_action = selectedGripperAction
        }
        if (selectedTaskName === "SURVEY_FOR_ASSET") {
            payload.survey_plan_file = selectedSurveyPlanFile()
            root.displaySelectedSurveyPlan()
        }
        root.sendMissionCommand("RUN_TASK", payload)
        if (selectedTaskName === "TAKEOFF" && _activeVehicle) {
            var takeoffAltitude = Math.max(10, _activeVehicle.minimumTakeoffAltitudeMeters())
            if (_activeVehicle.guidedTakeoffSupported) {
                _activeVehicle.guidedModeTakeoff(takeoffAltitude)
            } else if (_activeVehicle.takeoffVehicleSupported) {
                _activeVehicle.startTakeoff()
            }
        }
    }

    function runGripperTask(action) {
        selectedTaskName = "GRIPPER"
        selectedTaskLabel = action === "OPEN" ? "OPEN GRIPPER" : "CLOSE GRIPPER"
        selectedGripperAction = action
        missionTaskDisplay = selectedTaskLabel
        missionStatusText = selectedTaskLabel + " sent"
        root.sendMissionCommand("RUN_TASK", {
            task_name: "GRIPPER",
            gripper_action: action
        })
    }

    function updateLocalMissionStatus(commandName, taskName) {
        if (commandName === "START_AUTO") {
            missionModeDisplay = "AUTO_SEQUENCE"
            missionTaskDisplay = "PRECHECK"
            missionAssetDisplay = selectedMissionRoundId() === 3 ? "Asset 1/3" : "Asset 1/1"
            missionStatusText = "Auto start sent"
            return
        }
        if (commandName === "SET_MODE") {
            missionModeDisplay = selectedMissionMode
            missionStatusText = "Mode command sent"
            return
        }
        if (commandName === "RUN_TASK") {
            missionModeDisplay = "MANUAL_STEP"
            missionTaskDisplay = selectedTaskLabel || taskName
            missionStatusText = "Task load sent"
            return
        }
        if (commandName === "PAUSE") {
            missionModeDisplay = "PAUSED"
            missionStatusText = "Pause sent"
            return
        }
        if (commandName === "RESUME") {
            missionStatusText = "Resume sent"
            return
        }
        if (commandName === "ABORT") {
            missionModeDisplay = "ABORT"
            missionTaskDisplay = "IDLE"
            missionStatusText = "Abort sent"
            return
        }
        if (commandName === "RETURN_HOME") {
            missionTaskDisplay = "RTL"
            missionStatusText = "RTL sent"
            return
        }
        if (commandName === "DISARM") {
            isArmed = false
            missionStatusText = "Disarm sent"
            return
        }
        if (commandName === "OPERATOR_APPROVAL") {
            missionStatusText = taskName ? "Target approved" : "Target rejected"
        }
    }

    function sendMissionCommand(commandName, extra) {
        root.bridgeSendStatus = "Sending: " + commandName
        if (!root._bridgeClient) {
            root.bridgeSendStatus = "Bridge sender unavailable"
            return
        }

        var payload = {
            type: "mission_command",
            command: commandName,
            source: "qgc",
            round_id: selectedMissionRoundId(),
        }
        if (extra) {
            for (var key in extra) {
                payload[key] = extra[key]
            }
        }

        if (!root._bridgeClient.sendJsonMessage(payload)) {
            root.bridgeSendStatus = "Send failed"
            return
        }
        updateLocalMissionStatus(commandName, payload.task_name || payload.approved)
    }

    // ─────────────────────────────────────────────────────────────────────
    // DATA MODELS
    // ─────────────────────────────────────────────────────────────────────
    ListModel { id: assetModel }

    Component.onCompleted: showTemporaryMapOverlays()
    Component.onDestruction: clearTemporaryMapOverlays()

    Component {
        id: arenaOverlayComponent

        MapPolygon {
            z: QGroundControl.zOrderMapItems + 10
            border.color: "#00c853"
            border.width: 3
            color: "#2200c853"
            opacity: 0.85
        }
    }

    Component {
        id: fobMarkerComponent

        MapQuickItem {
            property string label: ""
            property bool selected: false

            z: QGroundControl.zOrderMapItems + 20
            anchorPoint.x: sourceItem.width / 2
            anchorPoint.y: sourceItem.height / 2

            sourceItem: Rectangle {
                width: fobLabel.width + 16
                height: 28
                radius: 14
                color: selected ? "#1976d2" : "#263238"
                border.color: "white"
                border.width: selected ? 2 : 1

                Text {
                    id: fobLabel
                    anchors.centerIn: parent
                    text: label
                    color: "white"
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // QGC TOOL INSETS
    // ─────────────────────────────────────────────────────────────────────
    QGCToolInsets {
        id:                  _totalToolInsets
        leftEdgeTopInset:    _leftPanelWidth
        leftEdgeCenterInset: _leftPanelWidth
        leftEdgeBottomInset: _leftPanelWidth
        rightEdgeTopInset:   _rightPanelWidth
        rightEdgeCenterInset:_rightPanelWidth
        rightEdgeBottomInset:_rightPanelWidth
        topEdgeLeftInset:    parentToolInsets.topEdgeLeftInset   + _topBarHeight
        topEdgeCenterInset:  parentToolInsets.topEdgeCenterInset + _topBarHeight
        topEdgeRightInset:   parentToolInsets.topEdgeRightInset  + _topBarHeight
        bottomEdgeLeftInset: _bottomBarHeight
        bottomEdgeCenterInset: _bottomBarHeight
        bottomEdgeRightInset:  _bottomBarHeight
    }


    // =========================================================================
    // TOP STATUS BAR
    // =========================================================================
    Rectangle {
        id:             topBar
        anchors.top:    parent.top
        anchors.left:   parent.left
        anchors.right:  parent.right
        height:         _topBarHeight
        color:          _clrPanel

        RowLayout {
            anchors.fill:        parent
            anchors.leftMargin:  14
            anchors.rightMargin: 14
            spacing:             12

            Rectangle {
                Layout.preferredWidth:  70
                Layout.preferredHeight: 34
                radius: 5
                color:  _clrCard
                Text {
                    id:               planBtn
                    anchors.centerIn: parent
                    text:             "PLAN"
                    color:            "white"
                    font.pixelSize:   12
                    font.bold:        true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked:    mainWindow.showToolSelectDialog()
                    cursorShape:  Qt.PointingHandCursor
                }
            }

            Column {
                Layout.preferredWidth:  128
                Layout.preferredHeight: 34
                spacing: 0
                Text {
                    text:           "Crown & Eagle"
                    color:          "white"
                    font.pixelSize: 13
                    font.bold:      true
                    elide:          Text.ElideRight
                    width:          parent.width
                }
                Text {
                    text:           "Engineering"
                    color:          _clrMuted
                    font.pixelSize: 10
                    elide:          Text.ElideRight
                    width:          parent.width
                }
            }

            Rectangle {
                Layout.preferredWidth:  144
                Layout.preferredHeight: 34
                color:  _clrCard
                radius: 5
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: _activeVehicle ? _clrGreen : _clrRed
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id:               uavLabel
                        text:             _activeVehicle ? "UAV-" + _activeVehicle.id : "UAV-01"
                        color:            "white"
                        font.pixelSize:   12
                        font.bold:        true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text:             _activeVehicle ? "ONLINE" : "OFFLINE"
                        color:            _activeVehicle ? _clrGreen : _clrRed
                        font.pixelSize:   10
                        font.bold:        true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                Layout.preferredHeight: 34
                spacing: 8

                Rectangle {
                    width: 118; height: 34; color: _clrCard; radius: 5
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: "DEEPSEE"; color: _clrMuted; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            text: _activeVehicle ? "ACTIVE" : "INACTIVE"
                            color: _activeVehicle ? _clrGreen : _clrMuted
                            font.pixelSize: 12
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                Rectangle {
                    width: 104; height: 34; color: _videoStatusColor; radius: 5
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: "VIDEO"; color: "white"; opacity: 0.75; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: _videoStatusLabel; color: "white"; font.pixelSize: 12; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }

                Rectangle {
                    width: 122; height: 34; color: _clrCard; radius: 5
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: "ELAPSED"; color: _clrMuted; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            id: topElapsedClock
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                            property int _secs: 0
                            property var _t: Timer {
                                interval: 1000
                                running: true
                                repeat: true
                                onTriggered: topElapsedClock._secs++
                            }
                            text: {
                                var h = Math.floor(_secs / 3600).toString().padStart(2, "0")
                                var m = Math.floor((_secs % 3600) / 60).toString().padStart(2, "0")
                                var sec = (_secs % 60).toString().padStart(2, "0")
                                return h + ":" + m + ":" + sec
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth:  150
                Layout.preferredHeight: 34
                color:  _clrBlue
                radius: 5
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text:                   "MODE"
                        color:                  "white"
                        opacity:                0.75
                        font.pixelSize:         9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id:               topModeLabel
                        text:             root._currentFlightMode
                        color:            "white"
                        font.pixelSize:   12
                        font.bold:        true
                        anchors.verticalCenter: parent.verticalCenter
                        width:            86
                        elide:            Text.ElideRight
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth:  94
                Layout.preferredHeight: 34
                color: _clrCard
                radius: 5
                Text {
                    id:             utcClock
                    anchors.centerIn: parent
                    color:          "white"
                    font.pixelSize: 11
                    font.bold:      true

                    property var _timer: Timer {
                        interval:    1000
                        running:     true
                        repeat:      true
                        onTriggered: utcClock.tick()
                    }

                    function tick() {
                        var now = new Date()
                        utcClock.text = now.getUTCHours().toString().padStart(2, "0") + ":"
                            + now.getUTCMinutes().toString().padStart(2, "0") + ":"
                            + now.getUTCSeconds().toString().padStart(2, "0") + "Z"
                    }

                    Component.onCompleted: tick()
                }
            }
        }
    }


    // =========================================================================
    // LEFT SIDEBAR  (260 px)
    // =========================================================================
    Rectangle {
        id:             leftPanel
        anchors.top:    topBar.bottom
        anchors.left:   parent.left
        anchors.bottom: bottomBar.top
        width:          _leftPanelWidth
        color:          _clrPanel

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: 12
            spacing:         10

            // Mission controls
            Rectangle { Layout.fillWidth: true; height: 1; color: _clrCard }

            Column {
                Layout.fillWidth: true
                spacing: 6

                Text { text: "Mission Specs"; color: "white"; font.pixelSize: 13; font.bold: true }

            // Demo selector
            ComboBox {
                id:             demoComboBox
                enabled:        !demoLocked
                model:          ["Select Demonstration…"].concat(root.demoNames)
                currentIndex:   root.selectedDemoIndex + 1
                width:          236
                implicitHeight: 30

                // Hover shows the full demo name (the closed selector elides long ones).
                ToolTip.text:    demoComboBox.displayText
                ToolTip.delay:   300
                ToolTip.visible: hovered && demoText.truncated

                onActivated: function(index) {
                    if (index > 0) root.lockDemo(index - 1)
                }

                background: Rectangle {
                    color:   demoLocked ? _clrPurpleDim : _clrPurple
                    radius:  4
                    opacity: demoComboBox.enabled ? 1.0 : 0.75
                }

                contentItem: Text {
                    id:                demoText
                    text:              demoComboBox.displayText
                    color:             "white"
                    font.pixelSize:    12
                    font.bold:         true
                    verticalAlignment: Text.AlignVCenter
                    leftPadding:       10
                    rightPadding:      24
                    elide:             Text.ElideRight
                }

                indicator: Text {
                    text:                   "▼"
                    color:                  "white"
                    font.pixelSize:         10
                    anchors.right:          parent.right
                    anchors.rightMargin:    8
                    anchors.verticalCenter: parent.verticalCenter
                    visible:                !demoLocked
                }

                popup: Popup {
                    y:       demoComboBox.height
                    width:   demoComboBox.width
                    padding: 1
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: ListView {
                        clip:           true
                        implicitHeight: contentHeight
                        model:          demoComboBox.delegateModel
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                }

                delegate: ItemDelegate {
                    width:       demoComboBox.width
                    highlighted: demoComboBox.highlightedIndex === index
                    background: Rectangle { color: highlighted ? _clrPurple : _clrCard }
                    // Hover shows the full demo name when the row is truncated.
                    ToolTip.text:    modelData
                    ToolTip.delay:   300
                    ToolTip.visible: hovered && itemText.truncated
                    contentItem: Text {
                        id:                itemText
                        text:              modelData
                        color:             "white"
                        font.pixelSize:    12
                        leftPadding:       10
                        rightPadding:      10
                        elide:             Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Demo #1
            Column {
                Layout.fillWidth: true; spacing: 6
                visible: demoLocked && selectedDemoIndex === 0
                Text { text: "Target Color"; color: _clrMuted; font.pixelSize: 11 }
                ComboBox {
                    id: d1Color; model: root.colorOptions; width: 236
                    currentIndex: root.colorOptions.indexOf(root.demo1Color)
                    onActivated: function(i) { root.demo1Color = root.colorOptions[i] }
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: Text { text: d1Color.displayText; color: "white"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; leftPadding: 10 }
                    popup: Popup {
                        y: d1Color.height; width: d1Color.width; padding: 1
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: d1Color.delegateModel }
                    }
                    delegate: ItemDelegate {
                        width: d1Color.width; highlighted: d1Color.highlightedIndex === index
                        background: Rectangle { color: highlighted ? "#444" : _clrCard }
                        contentItem: Text { text: modelData; color: "white"; font.pixelSize: 12; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // Demo #2
            Column {
                Layout.fillWidth: true; spacing: 6
                visible: demoLocked && selectedDemoIndex === 1
                Text { text: "Target Shape"; color: _clrMuted; font.pixelSize: 11 }
                ComboBox {
                    id: d2Shape; model: root.shapeOptions; width: 236
                    currentIndex: root.shapeOptions.indexOf(root.demo2Shape)
                    onActivated: function(i) { root.demo2Shape = root.shapeOptions[i] }
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: Text { text: d2Shape.displayText; color: "white"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; leftPadding: 10 }
                    popup: Popup {
                        y: d2Shape.height; width: d2Shape.width; padding: 1
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: d2Shape.delegateModel }
                    }
                    delegate: ItemDelegate {
                        width: d2Shape.width; highlighted: d2Shape.highlightedIndex === index
                        background: Rectangle { color: highlighted ? "#444" : _clrCard }
                        contentItem: Text { text: modelData; color: "white"; font.pixelSize: 12; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }

            // Demo #3 & #4
            Column {
                Layout.fillWidth: true; spacing: 8
                visible: demoLocked && (selectedDemoIndex === 2 || selectedDemoIndex === 3)
                Text { text: "Add Asset (max 3)"; color: _clrMuted; font.pixelSize: 11 }
                Row {
                    spacing: 6
                    ComboBox {
                        id: assetColorPicker; model: root.colorOptions; width: 104
                        // The special Demo #4 shapes are not paired with a color.
                        enabled: !root.isColorlessShape(root.pendingShape)
                        opacity: enabled ? 1.0 : 0.4
                        currentIndex: root.colorOptions.indexOf(root.pendingColor)
                        onActivated: function(i) { root.pendingColor = root.colorOptions[i] }
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: Text { text: assetColorPicker.enabled ? assetColorPicker.displayText : "— none —"; color: "white"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        popup: Popup {
                            y: assetColorPicker.height; width: assetColorPicker.width; padding: 1
                            background: Rectangle { color: _clrCard; radius: 4 }
                            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: assetColorPicker.delegateModel }
                        }
                        delegate: ItemDelegate {
                            width: assetColorPicker.width; highlighted: assetColorPicker.highlightedIndex === index
                            background: Rectangle { color: highlighted ? "#444" : _clrCard }
                            contentItem: Text { text: modelData; color: "white"; font.pixelSize: 11; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    ComboBox {
                        id: assetShapePicker; model: root.assetShapeOptions; width: 88
                        currentIndex: root.assetShapeOptions.indexOf(root.pendingShape)
                        onActivated: function(i) { root.pendingShape = root.assetShapeOptions[i] }
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: Text { text: assetShapePicker.displayText; color: "white"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 6 }
                        popup: Popup {
                            y: assetShapePicker.height; width: assetShapePicker.width; padding: 1
                            background: Rectangle { color: _clrCard; radius: 4 }
                            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: assetShapePicker.delegateModel }
                        }
                        delegate: ItemDelegate {
                            width: assetShapePicker.width; highlighted: assetShapePicker.highlightedIndex === index
                            background: Rectangle { color: highlighted ? "#444" : _clrCard }
                            contentItem: Text { text: modelData; color: "white"; font.pixelSize: 11; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                    // Operator-entered points for this asset (Demo #4 only).
                    // The customer supplies values on the day, so they are typed in.
                    TextField {
                        id: assetPointsField
                        visible: selectedDemoIndex === 3
                        width: 44; height: 28
                        placeholderText: "pts"
                        color: "white"; font.pixelSize: 11
                        horizontalAlignment: TextInput.AlignHCenter
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 0; top: 9999 }
                        background: Rectangle { color: _clrCard; radius: 4 }
                    }
                    Rectangle {
                        // Demo #4 requires a points value before an asset can be added.
                        property bool _canAdd: assetModel.count < 3
                                               && (selectedDemoIndex !== 3 || assetPointsField.text.length > 0)
                        width: 30; height: 28
                        color: _canAdd ? _clrGreen : "#555"; radius: 4
                        Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 18; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent._canAdd
                            onClicked: {
                                var pts = parseInt(assetPointsField.text) || 0
                                var clr = root.isColorlessShape(root.pendingShape) ? "" : root.pendingColor
                                assetModel.append({ assetColor: clr, assetShape: root.pendingShape, points: pts })
                                assetPointsField.text = ""
                            }
                        }
                    }
                }
                Column {
                    spacing: 4; width: 236
                    Repeater {
                        model: assetModel
                        delegate: Rectangle {
                            width: 236; height: 30; color: _clrCard; radius: 4
                            Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: model.assetColor ? (model.assetColor + " / " + model.assetShape) : model.assetShape; color: "white"; font.pixelSize: 11 }
                            Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: removeBtn.left; anchors.rightMargin: 8; visible: selectedDemoIndex === 3; text: model.points + " pts"; color: _clrGreen; font.pixelSize: 11 }
                            Rectangle {
                                id: removeBtn; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 8
                                width: 20; height: 20; color: _clrKill; radius: 3
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; onClicked: assetModel.remove(index) }
                            }
                        }
                    }
                }
                Rectangle {
                    width: 236; height: 32; color: _clrCard; radius: 4
                    visible: selectedDemoIndex === 3 && assetModel.count > 0
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; spacing: 8
                        Text { text: "Total Points:"; color: _clrMuted; font.pixelSize: 12 }
                        Text {
                            color: _clrGreen; font.pixelSize: 14; font.bold: true
                            text: { var sum = 0; for (var i = 0; i < assetModel.count; i++) sum += assetModel.get(i).points; return sum }
                        }
                    }
                }
            }


                ComboBox {
                    id: roundSpecCombo
                    model: root.roundSpecOptions.map(function(option) { return option.label })
                    width: 236
                    implicitHeight: 30
                    currentIndex: root.selectedRoundSpecIndex
                    onActivated: function(i) {
                        root.selectedRoundSpecIndex = i
                        root.deploySelectedGeofence()
                    }
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: Text {
                        text: "C&E Territory: " + roundSpecCombo.displayText
                        color: "white"
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                    popup: Popup {
                        y: roundSpecCombo.height; width: roundSpecCombo.width; padding: 1
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: roundSpecCombo.delegateModel }
                    }
                    delegate: ItemDelegate {
                        width: roundSpecCombo.width; highlighted: roundSpecCombo.highlightedIndex === index
                        background: Rectangle { color: highlighted ? "#444" : _clrCard }
                        contentItem: Text { text: modelData; color: "white"; font.pixelSize: 12; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    }
                }

                ComboBox {
                    id: cameraModeCombo
                    model: ["survey", "retrieve", "manual"]
                    width: 236
                    implicitHeight: 30
                    currentIndex: model.indexOf(root.cameraMode)
                    onActivated: function(i) {
                        root.cameraMode = model[i]
                    }
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: Text {
                        text: "Camera: " + cameraModeCombo.displayText
                        color: "white"
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                    popup: Popup {
                        y: cameraModeCombo.height; width: cameraModeCombo.width; padding: 1
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: cameraModeCombo.delegateModel }
                    }
                    delegate: ItemDelegate {
                        width: cameraModeCombo.width; highlighted: cameraModeCombo.highlightedIndex === index
                        background: Rectangle { color: highlighted ? "#444" : _clrCard }
                        contentItem: Text { text: modelData; color: "white"; font.pixelSize: 12; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    }
                }

                Row {
                    spacing: 6
                    Rectangle {
                        width: 115; height: 34; color: _clrBlue; radius: 6
                        Text { anchors.centerIn: parent; text: "Send Config"; color: "white"; font.pixelSize: 11; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.sendRoundConfig() }
                    }
                    Rectangle {
                        width: 115; height: 34; color: _clrGreen; radius: 6
                        Text { anchors.centerIn: parent; text: "Start Mission"; color: "white"; font.pixelSize: 11; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("START_AUTO") }
                    }
                }

                Text {
                    width: 236
                    text: root.bridgeSendStatus
                    color: _clrMuted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: _clrCard }

            Column {
                Layout.fillWidth: true
                spacing: 6

                Text { text: "Mission Mode"; color: "white"; font.pixelSize: 13; font.bold: true }

Row {
                    spacing: 6
                    Rectangle {
                        width: 115; height: 28; radius: 4
                        color: selectedMissionMode === "AUTO_SEQUENCE" ? _clrBlue : _clrCard
                        Text { anchors.centerIn: parent; text: "Auto Sequence"; color: "white"; font.pixelSize: 10; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectedMissionMode = "AUTO_SEQUENCE"
                                root.sendMissionCommand("SET_MODE", { mode: selectedMissionMode })
                            }
                        }
                    }
                    Rectangle {
                        width: 115; height: 28; radius: 4
                        color: selectedMissionMode === "MANUAL_STEP" ? _clrBlue : _clrCard
                        Text { anchors.centerIn: parent; text: "Manual Step"; color: "white"; font.pixelSize: 10; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectedMissionMode = "MANUAL_STEP"
                                root.sendMissionCommand("SET_MODE", { mode: selectedMissionMode })
                            }
                        }
                    }
                }

                Row {
                    spacing: 6
                    Rectangle {
                        width: 74; height: 28; radius: 4; color: _clrCard
                        Text { anchors.centerIn: parent; text: "Pause"; color: "white"; font.pixelSize: 10 }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("PAUSE") }
                    }
                    Rectangle {
                        width: 74; height: 28; radius: 4; color: _clrBlue
                        Text { anchors.centerIn: parent; text: "Resume"; color: "white"; font.pixelSize: 10 }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("RESUME") }
                    }
                    Rectangle {
                        width: 76; height: 28; radius: 4; color: _clrKill
                        Text { anchors.centerIn: parent; text: "Abort"; color: "white"; font.pixelSize: 10; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("ABORT") }
                    }
                }

                Rectangle {
                    width: 236; height: 74; color: _clrCard; radius: 4
                    Column {
                        anchors.fill: parent; anchors.margins: 8; spacing: 3
                        Text { text: "Mode: " + missionModeDisplay; color: "white"; font.pixelSize: 11; font.bold: true; width: parent.width; elide: Text.ElideRight }
                        Text { text: "Task: " + missionTaskDisplay; color: "white"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                        Text { text: missionAssetDisplay; color: _clrGreen; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                        Text { text: missionStatusText; color: _clrAmber; font.pixelSize: 10; width: parent.width; elide: Text.ElideRight }
                    }
                }

                Row {
                    spacing: 6
                    visible: missionTaskDisplay === "SURVEY_FOR_ASSET"
                    Rectangle {
                        width: 150; height: 28; radius: 4; color: _clrGreen
                        Text { anchors.centerIn: parent; text: "Approve Target"; color: "white"; font.pixelSize: 10; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("OPERATOR_APPROVAL", { approved: true }) }
                    }
                    Rectangle {
                        width: 80; height: 28; radius: 4; color: _clrKill
                        Text { anchors.centerIn: parent; text: "Reject"; color: "white"; font.pixelSize: 10; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.sendMissionCommand("OPERATOR_APPROVAL", { approved: false }) }
                    }
                }

                Rectangle {
                    width: 236; height: 30; color: _clrCard; radius: 4
                    Text {
                        anchors.centerIn: parent
                        text: "Task: " + selectedTaskLabel
                        color: "white"
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width - 14
                    }
                }

                Grid {
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: root.missionTaskOptions
                        delegate: Rectangle {
                            property bool roundAllowed: !modelData.round_id || root.selectedMissionRoundId() === modelData.round_id
                            width: 115; height: 28; radius: 4
                            color: root.selectedTaskName === modelData.task && root.selectedTaskLabel === modelData.label ? _clrBlue : _clrCard
                            opacity: roundAllowed ? 1.0 : 0.35
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "white"
                                font.pixelSize: 9
                                font.bold: root.selectedTaskLabel === modelData.label
                                elide: Text.ElideRight
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: parent.roundAllowed
                                onClicked: root.selectMissionTask(modelData.task, modelData.label, modelData.gripper_action || "")
                            }
                        }
                    }
                }

                Rectangle {
                    width: 236; height: 32; radius: 4; color: _clrPurple
                    Text { anchors.centerIn: parent; text: "Load Task"; color: "white"; font.pixelSize: 12; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: root.loadSelectedMissionTask() }
                }
            }
        }
    }




    // =========================================================================
    // RIGHT TELEMETRY PANEL  (260 px)
    // =========================================================================
    Rectangle {
        id:             rightPanel
        anchors.top:    topBar.bottom
        anchors.right:  parent.right
        anchors.bottom: bottomBar.top
        width:          _rightPanelWidth
        color:          _clrPanel

        Column {
            anchors.fill:    parent
            anchors.margins: 12
            spacing:         8

            Text { text: "Telemetry"; color: "white"; font.pixelSize: 16; font.bold: true }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⟳"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "SPEED"; color: _clrMuted; font.pixelSize: 10 }
                        Text { text: root._telSpeed + " " + root._unitSpeed; color: "white"; font.pixelSize: 18; font.bold: true }
                    }
                }
            }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⊙"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "HEADING"; color: _clrMuted; font.pixelSize: 10 }
                        Text { text: root._telHeading + "°"; color: "white"; font.pixelSize: 18; font.bold: true }
                    }
                }
            }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "▲"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "ALTITUDE"; color: _clrMuted; font.pixelSize: 10 }
                        Row {
                            spacing: 6
                            Text { text: root._telAltitude + " " + root._unitAltitude; color: "white"; font.pixelSize: 18; font.bold: true }
                            Text { text: "AGL"; color: _clrGreen; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⊕"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "LATITUDE"; color: _clrMuted; font.pixelSize: 10 }
                        Text { text: root._telLat + "°"; color: "white"; font.pixelSize: 18; font.bold: true }
                    }
                }
            }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⊕"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "LONGITUDE"; color: _clrMuted; font.pixelSize: 10 }
                        Text { text: root._telLon + "°"; color: "white"; font.pixelSize: 18; font.bold: true }
                    }
                }
            }

            Rectangle {
                width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⏱"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "TIME"; color: _clrMuted; font.pixelSize: 10 }
                        Text {
                            id: telUtcClock; color: "white"; font.pixelSize: 18; font.bold: true
                            property var _timer: Timer { interval: 1000; running: true; repeat: true; onTriggered: telUtcClock.tick() }
                            function tick() {
                                var now = new Date()
                                telUtcClock.text = now.getUTCHours().toString().padStart(2, "0") + ":" + now.getUTCMinutes().toString().padStart(2, "0") + ":" + now.getUTCSeconds().toString().padStart(2, "0") + " UTC"
                            }
                            Component.onCompleted: tick()
                        }
                    }
                }
            }

            Rectangle {
                id: batteryCard; width: 236; height: 60; color: _clrCard; radius: 6
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                    Text { text: "⚡"; color: _clrMuted; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "BATTERY"; color: _clrMuted; font.pixelSize: 10 }
                        Row {
                            spacing: 6
                            Text {
                                text: root._batteryPct >= 0 ? root._batteryPct.toFixed(0) + "%" : "—%"
                                color: "white"; font.pixelSize: 18; font.bold: true
                            }
                            Text {
                                visible: root._batteryPct >= 0
                                text: root._batteryPct > 50 ? "GOOD" : root._batteryPct > 20 ? "LOW" : "CRITICAL"
                                color: root._batteryPct > 50 ? _clrGreen : root._batteryPct > 20 ? _clrAmber : _clrRed
                                font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }


    // =========================================================================
    // COMMAND STRIP  (bottom bar)
    // Center: Arm | Hold Position | Land Mission | Return To Home | Complete Demo | Kill Switch
    // =========================================================================
    Rectangle {
        id:             bottomBar
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height:         _bottomBarHeight
        color:          _clrPanel

        RowLayout {
            anchors.fill:        parent
            anchors.leftMargin:  12
            anchors.rightMargin: 12
            spacing:             8

            // Info — bottom-left instruction guide. Toggles a plain-English panel
            // explaining what each control does (incl. the safety buttons).
            Rectangle {
                width: 38; height: 38; radius: 19
                color: infoPanel.visible ? _clrBlue : _clrCard
                border.color: _clrMuted; border.width: 1
                Text { anchors.centerIn: parent; text: "i"; color: "white"; font.pixelSize: 18; font.bold: true; font.italic: true }
                MouseArea { anchors.fill: parent; onClicked: infoPanel.visible = !infoPanel.visible }
            }

            Item { Layout.fillWidth: true }

            // Arm — manual (re-)arm. Issues a real PX4 arm via ROS
            // (sendMissionCommand("ARM") -> px4_command_bridge -> COMPONENT_ARM_DISARM)
            // and also arms directly over MAVLink for redundancy.
            //
            // WHEN TO USE: normally you do NOT need this. px4_control auto-arms on
            // entering AUTONOMY (DESIGN item F), so Start Mission -> Takeoff arms by
            // itself, including a re-takeoff after a LAND. Press ARM only to manually
            // spin up the motors WITHOUT starting a takeoff (e.g. a pre-arm check, or
            // to re-arm after a LAND without re-running the round config). Arming alone
            // does not fly the vehicle — you still need AUTONOMY + Takeoff to lift off.
            //
            // Color + label reflect the LIVE vehicle arm state (_activeVehicle.armed):
            // green "ARMED" when armed (incl. px4_control auto-arm on AUTONOMY),
            // blue "ARM" when disarmed (incl. PX4 auto-disarm after a LAND).
            Rectangle {
                id: armBtn
                readonly property bool vehArmed: _activeVehicle ? _activeVehicle.armed : false
                width: Math.max(armLbl.width + 28, 96); height: 38; radius: 6
                color: vehArmed ? _clrGreen : _clrBlue
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "●"; color: "white"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: armLbl; text: armBtn.vehArmed ? "ARMED" : "ARM"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("ARM")
                        if (_activeVehicle) {
                            _activeVehicle.armed = true
                        }
                        root.isArmed = true
                    }
                }
            }

            // Hold Position — publishes ROS command and switches PX4/QGC to Hold
            Rectangle {
                width: holdLbl.width + 28; height: 38; color: _clrCard; radius: 6; border.color: _clrMuted; border.width: 1
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "Ⅱ"; color: "white"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: holdLbl; text: "HOLD POSITION"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("HOLD_POSITION")
                        if (_activeVehicle) {
                            _activeVehicle.flightMode = _activeVehicle.pauseFlightMode || "Hold"
                        }
                    }
                }
            }

            // Land Mission — publishes ROS command and asks PX4/QGC for guided land
            Rectangle {
                width: landMissionLbl.width + 28; height: 38; color: _clrOrange; radius: 6
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "↓"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: landMissionLbl; text: "LAND MISSION"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("LAND_MISSION")
                        if (_activeVehicle) {
                            _activeVehicle.guidedModeLand()
                        }
                    }
                }
            }

            // Return to Home — commands guidedModeRTL (demo reset is the COMPLETE DEMO button)
            Rectangle {
                width: rthLbl.width + 32; height: 38; color: _clrGreen; radius: 6
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "⌂"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: rthLbl; text: "RETURN TO HOME"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("RETURN_HOME")
                        if (_activeVehicle) {
                            _activeVehicle.guidedModeRTL(false)
                        }
                    }
                }
            }

            // Complete Demo — clears the round config (locally + on the autonomy stack)
            // so the operator can select and send a fresh round config for the next demo.
            Rectangle {
                width: completeLbl.width + 28; height: 38; color: _clrPurple; radius: 6
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "✓"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: completeLbl; text: "COMPLETE DEMO"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("COMPLETE_DEMO")
                        root.unlockDemo()
                    }
                }
            }

            // Kill Switch — emergency stop intent
            Rectangle {
                width: landLbl.width + 32; height: 38; color: _clrKill; radius: 6
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "↓"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: landLbl; text: "KILL SWITCH"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sendMissionCommand("ABORT")
                        if (_activeVehicle) {
                            _activeVehicle.emergencyStop()
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // =========================================================================
    // INFORMATION GUIDE (info button)
    // =========================================================================

    // Operator instruction guide: a plain-English explanation of what each
    // bottom-bar control does, with emphasis on the safety actions (Hold, Land,
    // Return, Kill). Toggled by the bottom-left "i" button; sits just above the
    // command bar, left-aligned.
    Rectangle {
        id:                  infoPanel
        visible:             false
        z:                   1000
        width:               400
        implicitHeight:      infoCol.implicitHeight + 24
        height:              implicitHeight
        anchors.left:        parent.left
        anchors.leftMargin:  12
        anchors.bottom:      bottomBar.top
        anchors.bottomMargin: 8
        color:               "#F2111820"
        border.color:        _clrAmber
        border.width:        1
        radius:              8

        Column {
            id:             infoCol
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.margins: 12
            spacing:        8

            // Header with close button
            Item {
                width:  parent.width
                height: 20
                Text { text: "Control Guide — what each button does"; color: "white"; font.pixelSize: 14; font.bold: true; anchors.left: parent.left }
                Text {
                    text: "✕"; color: _clrMuted; font.pixelSize: 15; anchors.right: parent.right
                    MouseArea { anchors.fill: parent; onClicked: infoPanel.visible = false }
                }
            }

            Repeater {
                model: [
                    { n: "ARM",             d: "Spin up the motors manually. Usually NOT needed — Start Mission arms by itself. Green = armed, blue = disarmed." },
                    { n: "HOLD POSITION",   d: "Stop and hover in place. The drone must already be flying." },
                    { n: "LAND MISSION",    d: "Land straight down, right where the drone is now." },
                    { n: "RETURN TO HOME",  d: "Fly back to the launch point and land there." },
                    { n: "COMPLETE DEMO",   d: "End the run and clear the round so you can set up a new demo." },
                    { n: "KILL SWITCH",     d: "EMERGENCY ONLY: cuts the motors instantly — the drone will drop. Last resort." }
                ]
                delegate: Row {
                    width:   infoCol.width
                    spacing: 10
                    Text {
                        width: 112; text: modelData.n; color: _clrAmber
                        font.pixelSize: 12; font.bold: true; wrapMode: Text.WordWrap
                    }
                    Text {
                        width: infoCol.width - 122; text: modelData.d; color: "white"
                        font.pixelSize: 12; wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

}
