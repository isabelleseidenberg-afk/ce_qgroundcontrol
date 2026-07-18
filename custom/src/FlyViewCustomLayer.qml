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
import QtTextToSpeech

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
    property string selectedTaskName: "NO_ACTION"
    property bool fineTuningActive: false
    property string selectedTaskLabel: "NO ACTION"
    property string selectedGripperAction: ""
    property string selectedBattleshipDestinationId: ""
    property var completedBattleshipDestinations: ({})
    property bool missionPanelCollapsed: false
    property string missionModeDisplay: "MANUAL_STEP"
    property string missionTaskDisplay: "IDLE"
    property string selectedTaskDisplay: "Selected: NO ACTION"
    property string missionStatusText: "Waiting for operator command"
    property var pendingAssetMatch: null
    property var latestMissionGoalWaypoint: null
    property var previousMissionGoalWaypoint: null
    property var _confirmedAssetMarkers: []


    // Territory status driven by territory_status messages from the geofence monitor.
    // "undetermined" until FOB side is set via mission specs; then "home" or "enemy".
    property string territoryStatus: "undetermined"
    onTerritoryStatusChanged: {
        if (!_activeVehicle || !_activeVehicle.armed) return
        if (territoryStatus === "enemy") {
            _tts.say("Entering enemy territory")
        } else if (territoryStatus === "home") {
            _tts.say("Exiting enemy territory")
        }
    }

    TextToSpeech { id: _tts }

    readonly property var missionRoundOptions: ["Round 1", "Round 2", "Round 3", "Round 4"]
    readonly property var missionTaskOptions: [
        { label: "TAKEOFF", task: "TAKEOFF" },
        { label: "SURVEY", task: "SURVEY_FOR_ASSET" },
        { label: "GRIPPER CLOSE", task: "GRIPPER", gripper_action: "CLOSE" },
        { label: "GRIPPER OPEN", task: "GRIPPER", gripper_action: "OPEN" },
        { label: "GAAP", task: "GAAP" },
        { label: "NO ACTION", task: "NO_ACTION" }
    ]

    readonly property string battleshipCoordinatesConfigPath: ":/Custom/qml/config/set_plan_coordinates.yaml"
    property var battleshipOrigins: ({ bases: [], outfield: [] })
    property var battleshipShipCorners: ({ bases: [], outfield: [] })
    property var battleshipTerritoryShipSets: ({})
    property var configuredHomeOrigins: ({ bases: null, outfield: null })
    property bool battleshipCoordinatesLoaded: false
    property string battleshipCoordinatesError: ""
    property string homeLockStatus: "HOME NOT CONFIGURED"
    property string homeLockReason: ""
    property bool homeGroundContact: false

    property var _arenaOverlay
    property var _divisionLineOverlay
    property var _fobMarkers: []
    property var _shipBoxOverlays: []
    readonly property var roundSpecOptions: [
        {
            label: "Outfield",
            territory: "outfield",
            ceFobCoordinates: [38.750675, -77.497024, 0],
            wvxFobCoordinates: [38.750839, -77.497208, 0],
            geofenceFilePath: ":/Custom/qml/geofences/ce_geofence_outfield.plan"
        },
        {
            label: "Home Base",
            territory: "bases",
            ceFobCoordinates: [38.750839, -77.497208, 0],
            wvxFobCoordinates: [38.750675, -77.497024, 0],
            geofenceFilePath: ":/Custom/qml/geofences/ce_geofence_home_base.plan"
        }
    ]
    readonly property var _arenaPath: [
        QtPositioning.coordinate(38.75077, -77.49736),
        QtPositioning.coordinate(38.75094645, -77.4970914),
        QtPositioning.coordinate(38.75073705, -77.49686506),
        QtPositioning.coordinate(38.7505606, -77.49713366)
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
                var detail = payload.task_name || payload.task || payload.mode || payload.direction || ""
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

    readonly property string _videoHealthState: !QGroundControl.videoManager.decoding
                                                 ? "NO_VIDEO"
                                                 : (ceVideoStatus.hasStatus ? ceVideoStatus.state : "OK")
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
        // Points Round: (re)populate the scoring table from the default YAML
        // every time round 4 is selected, resetting demo4PointsPath back to
        // the default even if the operator had pointed it at a custom file in
        // a previous session - so re-selecting round 4 always starts from the
        // live default file rather than silently keeping stale/custom data.
        // The operator can still reload / point at their own file afterward.
        if (index === 3) {
            root.demo4PointsPath = root._demo4DefaultPointsPath
            root.loadDemo4Points(root.demo4PointsPath)
        }
        // Redraw map overlays on every round change, not just territory changes:
        // battleshipShipBoxPaths() only returns ships for round 3, so switching
        // into/out of Battleship needs its own refresh - otherwise picking Round 3
        // after territory was already selected leaves the ship boxes undrawn
        // until the operator happens to touch the territory dropdown too.
        showTemporaryMapOverlays()
    }

    // Parse a flat-mapping YAML scoring table: lines of "<Color> <Shape>: <points>"
    // (colorless specials use just "<Shape>"). Comments (#), blank lines and a
    // leading "- " list marker are tolerated. Returns [{label, color, shape, points}].
    // Note: QML has no real YAML parser, so the file must use this flat format.
    function parsePointsYaml(text) {
        var out = []
        var lines = text.split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var hash = line.indexOf("#")
            if (hash !== -1) line = line.substring(0, hash)  // strip comment
            line = line.trim()
            if (line.length === 0) continue
            if (line.charAt(0) === "-") line = line.substring(1).trim()  // list marker
            var colon = line.indexOf(":")
            if (colon === -1) continue
            var key = line.substring(0, colon).trim().replace(/^['"]|['"]$/g, "")
            var pts = parseInt(line.substring(colon + 1).trim())
            if (key.length === 0 || isNaN(pts)) continue   // skips wrapper keys like "assets:"
            var parts = key.split(" ")
            var color = ""
            var shape = key
            if (parts.length >= 2 && root.colorOptions.indexOf(parts[0]) !== -1) {
                color = parts[0]
                shape = parts.slice(1).join(" ")
            }
            out.push({ label: key, color: color, shape: shape, points: pts })
        }
        return out
    }

    // Built-in scoring catalog (every color/shape combo + colorless specials, 1 pt
    // each). Used as the guaranteed default so the dropdown always populates even if
    // the bundled YAML resource can't be read at runtime. Mirrors res/points/
    // demo4_asset_points.yaml.
    function defaultDemo4Catalog() {
        var out = []
        for (var c = 0; c < colorOptions.length; c++) {
            for (var s = 0; s < shapeOptions.length; s++) {
                out.push({ label: colorOptions[c] + " " + shapeOptions[s],
                           color: colorOptions[c], shape: shapeOptions[s], points: 1 })
            }
        }
        for (var k = 0; k < demo4SpecialShapes.length; k++) {
            out.push({ label: demo4SpecialShapes[k], color: "",
                       shape: demo4SpecialShapes[k], points: 1 })
        }
        return out
    }

    // Load a YAML scoring table from a Qt resource (":/…"), an absolute path, or a
    // URL, and populate demo4PointsModel.
    function loadDemo4Points(path) {
        var url = path
        if (path.charAt(0) === ":")       url = "qrc" + path
        else if (path.charAt(0) === "/")  url = "file://" + path
        var entries = []
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", url, false)   // synchronous read; files are small
            xhr.send()
            entries = root.parsePointsYaml(xhr.responseText || "")
        } catch (err) {
            console.warn("loadDemo4Points read failed for", url, err)
        }
        // Guarantee the default path yields the full built-in catalog even if the
        // bundled resource can't be read from QML at runtime.
        var usedDefault = false
        if (entries.length === 0 && path === root._demo4DefaultPointsPath) {
            entries = root.defaultDemo4Catalog()
            usedDefault = true
        }
        demo4PointsModel.clear()
        for (var i = 0; i < entries.length; i++) demo4PointsModel.append(entries[i])
        root.demo4PointsLoaded = entries.length > 0
        root.demo4PointsStatus = entries.length > 0
            ? ("Loaded " + entries.length + " assets" + (usedDefault ? " (defaults)" : ""))
            : "No assets found — check the file path/format"
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
        root.clearDisplayedSurveyPlan()
        latestMissionGoalWaypoint = null
        previousMissionGoalWaypoint = null
        root.clearConfirmedAssetMarkers()
        root.resetBattleshipState()
        root.clearShipBoxOverlays()
        demo4TotalPoints = 0
        demo4ConfirmedAssetsModel.clear()
        demo4LoadConfirmVisible = false
    }

    // Round 3 (Battleship, demo index 2): each asset must be returned to a specific
    // opponent battleship position, in list order. Return all three to sink them.
    // Shared by the asset row UI and the round_config payload so they never diverge.
    function battleshipReturnLabel(index) {
        return "Return to opponent battleship position " + (index + 1)
    }

    function resetBattleshipState() {
        selectedBattleshipDestinationId = ""
        completedBattleshipDestinations = ({})
    }

    function battleshipDestinationId(index) {
        return "battleship_" + (index + 1)
    }

    function battleshipCompleted(index) {
        return completedBattleshipDestinations[battleshipDestinationId(index)] === true
    }

    function selectBattleship(index) {
        var destinationId = battleshipDestinationId(index)
        if (selectedMissionRoundId() !== 3 || completedBattleshipDestinations[destinationId]) return
        selectMissionTask("GO_TO_WAYPOINT", "BATTLESHIP " + (index + 1), "")
        selectedBattleshipDestinationId = destinationId
    }

    function parseBattleshipCoordinatesYaml(text) {
        var origins = { bases: [null, null, null], outfield: [null, null, null] }
        var homeOrigins = { bases: null, outfield: null }
        // 4 corners per ship, same [lat, lon] pairs as origin - used to draw each
        // ship's box overlay (see battleshipShipBoxPaths/showTemporaryMapOverlays).
        var corners = {
            bases: [[null, null, null, null], [null, null, null, null], [null, null, null, null]],
            outfield: [[null, null, null, null], [null, null, null, null], [null, null, null, null]]
        }
        var routing = {}
        var currentShipSet = ""
        var currentShipIndex = -1
        var currentFobTerritory = ""
        var inRouting = false
        var lines = String(text || "").split(/\r?\n/)

        for (var i = 0; i < lines.length; i++) {
            var raw = lines[i]
            var trimmed = raw.trim()
            if (trimmed === "" || trimmed.charAt(0) === "#") continue

            if (trimmed === "battleship_territory_ship_sets:") {
                inRouting = true
                currentShipSet = ""
                currentShipIndex = -1
                currentFobTerritory = ""
                continue
            }

            var fobHeader = trimmed.match(/^(bases|outfield)_fob:$/)
            if (fobHeader) {
                inRouting = false
                currentShipSet = ""
                currentShipIndex = -1
                currentFobTerritory = fobHeader[1]
                continue
            }

            var shipHeader = trimmed.match(/^(bases|outfield)_ship_([1-3]):$/)
            if (shipHeader) {
                inRouting = false
                currentShipSet = shipHeader[1]
                currentShipIndex = Number(shipHeader[2]) - 1
                currentFobTerritory = ""
                continue
            }

            // Any other unindented top-level key ends both the routing block and
            // whichever ship block we were reading origin/corner_1..4 out of -
            // without this, a later section (assets:, bases_fob:, ...) could get
            // misattributed to the last ship seen.
            if (/^\S/.test(raw)) {
                inRouting = false
                currentShipSet = ""
                currentShipIndex = -1
                currentFobTerritory = ""
                continue
            }

            if (inRouting) {
                var route = trimmed.match(/^(bases|outfield):\s*(bases|outfield)$/)
                if (route) routing[route[1]] = route[2]
                continue
            }

            var origin = trimmed.match(/^origin:\s*\[\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\]$/)
            if (origin) {
                var coordinate = [Number(origin[1]), Number(origin[2])]
                if (currentFobTerritory !== "") {
                    homeOrigins[currentFobTerritory] = coordinate
                } else if (currentShipSet !== "") {
                    origins[currentShipSet][currentShipIndex] = coordinate
                }
                continue
            }

            if (currentShipSet === "") continue
            var corner = trimmed.match(/^corner_([1-4]):\s*\[\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\]$/)
            if (corner) {
                corners[currentShipSet][currentShipIndex][Number(corner[1]) - 1] = [Number(corner[2]), Number(corner[3])]
            }
        }

        if (routing.bases !== "bases" && routing.bases !== "outfield") {
            throw new Error("missing battleship territory mapping for bases")
        }
        if (routing.outfield !== "bases" && routing.outfield !== "outfield") {
            throw new Error("missing battleship territory mapping for outfield")
        }
        for (var setName of ["bases", "outfield"]) {
            if (!homeOrigins[setName]) {
                throw new Error("missing " + setName + "_fob.origin for fixed PX4 home")
            }
            for (var ship = 0; ship < 3; ship++) {
                if (!origins[setName][ship]) {
                    throw new Error("missing " + setName + "_ship_" + (ship + 1) + ".origin")
                }
                for (var c = 0; c < 4; c++) {
                    if (!corners[setName][ship][c]) {
                        throw new Error("missing " + setName + "_ship_" + (ship + 1) + ".corner_" + (c + 1))
                    }
                }
            }
        }
        return { origins: origins, routing: routing, corners: corners, homeOrigins: homeOrigins }
    }

    function loadBattleshipCoordinates() {
        battleshipCoordinatesLoaded = false
        battleshipCoordinatesError = ""
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "qrc" + battleshipCoordinatesConfigPath, false)
            xhr.send()
            var parsed = parseBattleshipCoordinatesYaml(xhr.responseText || "")
            battleshipOrigins = parsed.origins
            battleshipShipCorners = parsed.corners
            battleshipTerritoryShipSets = parsed.routing
            configuredHomeOrigins = parsed.homeOrigins
            battleshipCoordinatesLoaded = true
            console.log("Loaded battleship coordinates:", battleshipCoordinatesConfigPath)
        } catch (err) {
            battleshipCoordinatesError = String(err)
            console.error("Failed to load battleship coordinates:", battleshipCoordinatesError)
        }
    }

    function battleshipWaypoint(index) {
        if (!battleshipCoordinatesLoaded) return null
        var territory = selectedTerritory()
        var shipSet = battleshipTerritoryShipSets[territory]
        var origins = battleshipOrigins[shipSet]
        var origin = origins && origins[index]
        if (!origin) return null
        return { latitude: origin[0], longitude: origin[1], altitude: 2 }
    }

    function configuredHomeCoordinate() {
        if (!battleshipCoordinatesLoaded) return null
        var origin = configuredHomeOrigins[selectedTerritory()]
        if (!origin) return null
        return { latitude: origin[0], longitude: origin[1] }
    }

    // Round 3 only. Same territory->shipSet resolution as battleshipWaypoint:
    // selecting the outfield FOB shows the bases ships (and vice versa) - the
    // OPPOSING territory's ships are the ones this FOB's operator is meant to
    // attack. Returns one coordinate-corner-path per ship, for a green box
    // overlay per ship (see showTemporaryMapOverlays).
    function battleshipShipBoxPaths() {
        if (!battleshipCoordinatesLoaded || selectedMissionRoundId() !== 3) {
            return []
        }
        var territory = selectedTerritory()
        var shipSet = battleshipTerritoryShipSets[territory]
        var shipsCorners = battleshipShipCorners[shipSet]
        if (!shipsCorners) return []
        var paths = []
        for (var i = 0; i < shipsCorners.length; i++) {
            var corners = shipsCorners[i]
            if (!corners || corners.length !== 4) continue
            var path = []
            for (var c = 0; c < 4; c++) {
                if (!corners[c]) { path = null; break }
                path.push(QtPositioning.coordinate(corners[c][0], corners[c][1]))
            }
            if (path) paths.push(path)
        }
        return paths
    }

    function assetList() {
        // Demo #4 (Points Round): the asset catalog is the loaded YAML scoring
        // table, not a hand-built list. Send every possible asset + its point value
        // so CV / route planning in ce_lcp can maximize the points collected.
        if (selectedDemoIndex === 3) {
            var catalog = []
            for (var k = 0; k < demo4PointsModel.count; k++) {
                var e = demo4PointsModel.get(k)
                catalog.push({ color: e.color, shape: e.shape, points: e.points, label: e.label })
            }
            return catalog
        }
        var assets = []
        for (var i = 0; i < assetModel.count; i++) {
            var asset = assetModel.get(i)
            var entry = {
                color: asset.assetColor,
                shape: asset.assetShape,
                points: asset.points
            }
            // Battleship round: tag each asset with its 1-based return position and
            // human label so the ce_lcp ROS node knows where to return it.
            if (selectedDemoIndex === 2) {
                entry.battleship_position = i + 1
                entry.return_label = root.battleshipReturnLabel(i)
            }
            assets.push(entry)
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
            return "full_field_from_" + territory + "_home.plan"
        }
        return "enemy_survey_from_" + territory + ".plan"
    }

    function selectedSurveyPlanResourcePath() {
        return ":/Custom/qml/plans/" + selectedSurveyPlanFile()
    }

    function displaySelectedSurveyPlan() {
        if (_planMasterController) {
            var path = selectedSurveyPlanResourcePath()
            console.log("Loading C&E survey plan:", path)
            _planMasterController.loadFromFile(path)
        }
    }

    function clearDisplayedSurveyPlan() {
        if (_planMasterController) {
            console.log("Clearing C&E survey plan from map")
            _planMasterController.removeAll()
        }
    }

    // Read the ENEMY sub-geofence (the "inclusion: false" exclusion polygon) out of
    // a geofence .plan resource so the ROS geofence monitor tracks the exact fence
    // QGC deploys. Returns [[lat, lon], ...] (empty if not found). Keeping the .plan
    // the single source of truth means editing it updates both the map and the
    // monitor — no drifting copy of coordinates.
    function enemyGeofenceFromPlan(resourcePath) {
        if (!resourcePath) return []
        var url = resourcePath.charAt(0) === ":" ? "qrc" + resourcePath : resourcePath
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", url, false)   // synchronous read of a bundled resource
            xhr.send()
            var plan = JSON.parse(xhr.responseText)
            var polys = (plan.geoFence && plan.geoFence.polygons) ? plan.geoFence.polygons : []
            for (var i = 0; i < polys.length; i++) {
                if (polys[i].inclusion === false && polys[i].polygon && polys[i].polygon.length >= 3) {
                    return polys[i].polygon
                }
            }
        } catch (err) {
            console.warn("enemyGeofenceFromPlan failed for", resourcePath, err)
        }
        return []
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
            enemy_geofence: enemyGeofenceFromPlan(roundSpec.geofenceFilePath),
            geofence_height_ft: 30,
            camera_mode: cameraMode,
            survey_plan_file: selectedSurveyPlanFile(),
            home_coordinate: configuredHomeCoordinate(),
            demo_name: demoLocked ? root.demoNames[selectedDemoIndex] : "",
            assets: assetList()
        }
    }

    function sendRoundConfig() {
        root.bridgeSendStatus = "Sending: ROUND_CONFIG R" + selectedMissionRoundId()
        if (!configuredHomeCoordinate()) {
            root.bridgeSendStatus = "Send blocked: fixed home coordinate unavailable"
            root.missionStatusText = battleshipCoordinatesError || "Reload shared coordinate configuration"
            return
        }
        if (!root._bridgeClient) {
            root.bridgeSendStatus = "Bridge sender unavailable"
            return
        }
        if (!root._bridgeClient.sendJsonMessage(roundConfigMessage())) {
            root.bridgeSendStatus = "Send failed"
            return
        }
        root.resetBattleshipState()
        root.displaySelectedSurveyPlan()
    }

    // True once the plan controller is connected to a vehicle and idle -- the two
    // preconditions PlanMasterController.sendToVehicle() requires (it warns and
    // no-ops otherwise, per PlanMasterController::sendToVehicle in upstream QGC).
    readonly property bool _canUploadPlanToVehicle: !!_planMasterController
                                                      && !_planMasterController.offline
                                                      && !_planMasterController.syncInProgress

    // Territory selection is visual only (the division line + arena overlay drawn
    // by showTemporaryMapOverlays) - it must NOT touch _planMasterController, since
    // loadFromFile()/sendToVehicle() here would replace the full-field geofence
    // (deployFullFieldGeofence, the only geofence actually enforced on the vehicle)
    // with a narrower per-territory one. roundSpec.geofenceFilePath is still read
    // directly (enemyGeofenceFromPlan) for the ROS geofence *monitor's* territory
    // tracking in roundConfigMessage() - that's a separate, software-side polygon
    // check for game logic, not a flight-boundary upload.
    function deploySelectedGeofence() {
        showTemporaryMapOverlays()
    }

    // Auto-deploy on launch so the vehicle always has a geofence covering the
    // whole arena as a safety floor, even before an operator picks a round/territory
    // and sends round config (which would otherwise deploy a narrower per-territory
    // fence). loadFromFile() only stages the fence in QGC's local plan editor --
    // actually enforcing it on the vehicle needs sendToVehicle(), which requires
    // being connected, so that part is retried (by the Connections block below and
    // the fallback Timer) until a vehicle is actually online.
    property bool _fullFieldGeofenceLoaded: false
    property bool _fullFieldGeofenceUploaded: false
    readonly property string _fullFieldGeofencePath: ":/Custom/qml/geofences/ce_geofence_full_field.plan"

    function deployFullFieldGeofence() {
        if (!_planMasterController) {
            return
        }
        if (!_fullFieldGeofenceLoaded) {
            _planMasterController.loadFromFile(_fullFieldGeofencePath)
            _fullFieldGeofenceLoaded = true
        }
        if (!_fullFieldGeofenceUploaded && _canUploadPlanToVehicle) {
            _planMasterController.sendToVehicle()
            _fullFieldGeofenceUploaded = true
        }
    }

    // Reacts quickly once _planMasterController already has a vehicle target and its
    // offline/syncInProgress state changes. Connections retargets itself automatically
    // whenever _planMasterController is reassigned (e.g. null -> ready).
    Connections {
        target: _planMasterController
        function onOfflineChanged() { deployFullFieldGeofence() }
        function onSyncInProgressChanged() { deployFullFieldGeofence() }
    }

    // Fallback for the null -> ready transition itself, which Connections retargeting
    // does not fire a handler for on its own (only for signals emitted *after*
    // retargeting). Self-stops once uploaded.
    Timer {
        interval: 1000
        repeat: true
        running: !_fullFieldGeofenceUploaded
        onTriggered: deployFullFieldGeofence()
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
        _clearMapObject(_divisionLineOverlay)
        _divisionLineOverlay = null
        for (var i = 0; i < _fobMarkers.length; i++) {
            _clearMapObject(_fobMarkers[i])
        }
        _fobMarkers = []
        clearShipBoxOverlays()
    }

    // Split out from clearTemporaryMapOverlays so Complete Demo (unlockDemo)
    // can drop just the round-3 ship boxes without also tearing down the
    // arena/FOB overlay, which isn't round-specific and should persist.
    function clearShipBoxOverlays() {
        for (var j = 0; j < _shipBoxOverlays.length; j++) {
            _clearMapObject(_shipBoxOverlays[j])
        }
        _shipBoxOverlays = []
    }

    function clearConfirmedAssetMarkers() {
        for (var i = 0; i < _confirmedAssetMarkers.length; i++) {
            _clearMapObject(_confirmedAssetMarkers[i])
        }
        _confirmedAssetMarkers = []
    }

    function colorForAssetMarker(value) {
        var key = String(value || "").toLowerCase().trim()
        var colors = {
            red: "#e53935",
            orange: "#fb8c00",
            yellow: "#fdd835",
            green: "#43a047",
            blue: "#1e88e5",
            purple: "#8e24aa",
            violet: "#8e24aa",
            pink: "#d81b60",
            black: "#212121",
            white: "#f5f5f5",
            gray: "#757575",
            grey: "#757575",
            brown: "#795548",
            tan: "#d2b48c"
        }
        return colors[key] || _clrAmber
    }

    function validMapCoordinate(coord) {
        if (!coord) return false
        var lat = Number(coord.latitude)
        var lon = Number(coord.longitude)
        return !isNaN(lat) && !isNaN(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
    }

    function coordinateFromGoalWaypoint(goal) {
        if (!goal) return null
        var lat = Number(goal.latitude)
        var lon = Number(goal.longitude)
        var alt = Number(goal.altitude || 0)
        if (isNaN(lat) || isNaN(lon)) {
            return null
        }
        return QtPositioning.coordinate(lat, lon, isNaN(alt) ? 0 : alt)
    }

    function confirmedAssetCoordinate(candidate) {
        var goal = candidate && candidate.marker_goal_waypoint ? candidate.marker_goal_waypoint : latestMissionGoalWaypoint
        var goalCoord = root.coordinateFromGoalWaypoint(goal)
        if (root.validMapCoordinate(goalCoord)) {
            return goalCoord
        }
        if (root.validMapCoordinate(_activeVehicle && _activeVehicle.coordinate)) {
            return _activeVehicle.coordinate
        }
        return null
    }

    function assetMarkerColor(candidate) {
        if (!candidate) return _clrAmber
        if (candidate.matched_target && candidate.matched_target.color) {
            return root.colorForAssetMarker(candidate.matched_target.color)
        }
        if (candidate.detected_color) {
            return root.colorForAssetMarker(candidate.detected_color)
        }
        return _clrAmber
    }

    function assetMarkerTextColor(fillColor) {
        var key = String(fillColor || "").toLowerCase()
        return key === "#f5f5f5" || key === "#fdd835" || key === "#d2b48c" ? "#111111" : "white"
    }

    function addConfirmedAssetMarker(candidate) {
        if (!mapControl || !assetMarkerComponent) {
            return
        }
        var coord = root.confirmedAssetCoordinate(candidate)
        if (!root.validMapCoordinate(coord)) {
            console.warn("Cannot place confirmed asset marker: no valid map coordinate")
            return
        }
        var fillColor = root.assetMarkerColor(candidate)
        var marker = assetMarkerComponent.createObject(mapControl, {
            coordinate: coord,
            markerColor: fillColor,
            markerTextColor: root.assetMarkerTextColor(fillColor),
            label: String(_confirmedAssetMarkers.length + 1)
        })
        if (!marker) {
            console.warn("Cannot create confirmed asset marker")
            return
        }
        mapControl.addMapItem(marker)
        _confirmedAssetMarkers.push(marker)
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

        _divisionLineOverlay = divisionLineComponent.createObject(mapControl)
        mapControl.addMapItem(_divisionLineOverlay)

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

        // Round 3 only: green box per opposing-territory ship (reuses the same
        // arenaOverlayComponent style as the geofence, just one instance per ship).
        var shipPaths = battleshipShipBoxPaths()
        for (var s = 0; s < shipPaths.length; s++) {
            var shipBox = arenaOverlayComponent.createObject(mapControl, {
                path: shipPaths[s]
            })
            mapControl.addMapItem(shipBox)
            _shipBoxOverlays.push(shipBox)
        }

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
        if (status && status.type === "territory_status") {
            root.territoryStatus = status.status || "undetermined"
            return
        }
        if (status && status.type === "asset_match_candidate") {
            root.showAssetMatchCandidate(status)
            return
        }
        if (status && status.type === "asset_match_resolved") {
            if (pendingAssetMatch && status.candidate_id === pendingAssetMatch.candidate_id) {
                pendingAssetMatch = null
                assetMatchPopup.close()
            }
            missionStatusText = status.message || missionStatusText
            return
        }
        if (!status || status.type !== "mission_status") {
            return
        }
        missionModeDisplay = status.current_mission_mode || missionModeDisplay
        missionTaskDisplay = status.current_task || missionTaskDisplay
        var completedDestination = status.last_completed_destination_id || ""
        if (status.last_completed_task === "GO_TO_WAYPOINT" && completedDestination.indexOf("battleship_") === 0
                && !completedBattleshipDestinations[completedDestination]) {
            var completed = ({})
            for (var destinationKey in completedBattleshipDestinations) completed[destinationKey] = completedBattleshipDestinations[destinationKey]
            completed[completedDestination] = true
            completedBattleshipDestinations = completed
            if (selectedBattleshipDestinationId === completedDestination) selectedBattleshipDestinationId = ""
        }
        if (status.previous_goal_waypoint && status.previous_goal_waypoint.latitude !== undefined && status.previous_goal_waypoint.longitude !== undefined) {
            previousMissionGoalWaypoint = status.previous_goal_waypoint
        }
        if (status.active_goal_waypoint && status.active_goal_waypoint.latitude !== undefined && status.active_goal_waypoint.longitude !== undefined) {
            latestMissionGoalWaypoint = status.active_goal_waypoint
        }
        var px4Reason = ""
        var px4Status = status.px4_control_status || {}
        homeLockStatus = px4Status.home_status || homeLockStatus
        homeLockReason = px4Status.home_reason || ""
        homeGroundContact = px4Status.ground_contact === true
        if (status.px4_control_ready === false && status.px4_control_ready_reason) {
            px4Reason = "PX4: " + status.px4_control_ready_reason
        }
        if (px4Reason !== "" && (missionTaskDisplay === "TAKEOFF" || missionTaskDisplay === "SURVEY_FOR_ASSET" || missionTaskDisplay === "GO_TO_WAYPOINT")) {
            missionStatusText = px4Reason
        } else {
            missionStatusText = status.status_text || status.last_failure_reason || px4Reason || missionStatusText
        }
    }

    function selectedMissionRoundId() {
        return selectedMissionRoundIndex + 1
    }

    function candidateConfidenceText(candidate) {
        if (!candidate || candidate.confidence === undefined || candidate.confidence === null) {
            return "n/a"
        }
        var confidence = Number(candidate.confidence)
        if (isNaN(confidence)) {
            return "n/a"
        }
        if (confidence <= 1.0) {
            confidence = confidence * 100.0
        }
        return confidence.toFixed(1) + "%"
    }

    function assetCandidateText(candidate) {
        if (!candidate) {
            return "Waiting for candidate"
        }
        var parts = []
        if (candidate.detected_color) parts.push(candidate.detected_color)
        if (candidate.detected_shape) parts.push(candidate.detected_shape)
        if (parts.length === 0 && candidate.label) parts.push(candidate.label)
        return parts.length > 0 ? parts.join(" ") : "unknown"
    }

    function assetTargetText(candidate) {
        if (!candidate || !candidate.matched_target) {
            return "configured target"
        }
        var label = candidate.matched_target.display_label || candidate.matched_target.label || "configured target"
        var rank = Number(candidate.priority_rank || candidate.matched_target.priority || 0)
        return rank > 0 ? ("Priority " + rank + ": " + label) : label
    }

    function showAssetMatchCandidate(candidate) {
        if (candidate && candidate.marker_goal_waypoint && candidate.marker_goal_waypoint.latitude !== undefined && candidate.marker_goal_waypoint.longitude !== undefined) {
            // The asset_match_node selected this waypoint at detection time. Keep it frozen.
        } else if (candidate && previousMissionGoalWaypoint) {
            candidate.marker_goal_waypoint = previousMissionGoalWaypoint
        } else if (candidate && latestMissionGoalWaypoint) {
            candidate.marker_goal_waypoint = latestMissionGoalWaypoint
        }
        pendingAssetMatch = candidate
        missionModeDisplay = "HOLD"
        missionStatusText = "Target candidate found"
        assetMatchPopup.open()
    }

    // Demo #4 (Points Round): look up a confirmed candidate's point value in
    // demo4PointsModel (loaded from demo4_asset_points.yaml). Matched by
    // color+shape, case-insensitive since the AI detection pipeline's strings
    // aren't guaranteed to match the YAML's casing exactly. Colorless specials
    // (Grenade/Jet Boat/Grey Tank) have an empty color on both sides. Returns 0
    // or an unrecognized asset just doesn't add to the total.
    function demo4PointsForCandidate(candidate) {
        if (!candidate) return 0
        var color = String(candidate.detected_color || "").toLowerCase()
        var shape = String(candidate.detected_shape || "").toLowerCase()
        if (shape.length === 0) return 0
        for (var i = 0; i < demo4PointsModel.count; i++) {
            var entry = demo4PointsModel.get(i)
            if (String(entry.shape || "").toLowerCase() !== shape) continue
            if (String(entry.color || "").toLowerCase() === color) return entry.points
        }
        return 0
    }

    function resolveAssetMatchCandidate(approved) {
        if (!pendingAssetMatch) {
            return
        }
        var candidate = pendingAssetMatch
        var candidateId = candidate.candidate_id || ""
        root.sendMissionCommand("OPERATOR_APPROVAL", {
            approved: approved,
            candidate_id: candidateId
        })
        if (approved) {
            root.addConfirmedAssetMarker(candidate)
            if (demoLocked && selectedDemoIndex === 3) {
                var pts = root.demo4PointsForCandidate(candidate)
                root.demo4TotalPoints += pts
                demo4ConfirmedAssetsModel.append({
                    label: root.assetCandidateText(candidate),
                    points: pts
                })
            }
        }
        root.sendMissionCommand("RESUME", { candidate_id: candidateId })
        missionStatusText = approved ? "Target approved" : "Target rejected"
        pendingAssetMatch = null
        assetMatchPopup.close()
    }


    function selectMissionTask(taskName, label, gripperAction) {
        selectedTaskName = taskName
        selectedTaskLabel = label || taskName
        selectedTaskDisplay = "Selected: " + selectedTaskLabel
        selectedGripperAction = gripperAction || ""
        if (taskName !== "GO_TO_WAYPOINT") selectedBattleshipDestinationId = ""
        missionStatusText = "Task selected"
    }

    function loadSelectedMissionTask() {
        // "2ft Hover" / "Fine Tuning" are sent by their own command name, not
        // wrapped in RUN_TASK. HOVER_2FT IS a real mission_manager task (see
        // build_task_registry in mission_manager_node.py) -- mission_manager's
        // _on_qgc_command recognizes the bare "HOVER_2FT" command and calls
        // run_task() itself, so no task_name/RUN_TASK wrapper is needed here.
        // FINE_TUNE_MODE is NOT a task -- mission_manager only recognizes it so
        // it doesn't log "Unsupported QGC command"; px4_control_node is the one
        // that actually acts on it, over its own dedicated topic.
        if (selectedTaskName === "HOVER_2FT") {
            root.fineTuningActive = false
            root.sendMissionCommand("HOVER_2FT")
            return
        }
        if (selectedTaskName === "FINE_TUNE_MODE") {
            root.fineTuningActive = true
            root.sendMissionCommand("FINE_TUNE_MODE")
            return
        }

        root.fineTuningActive = false
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
        if (selectedTaskName === "GO_TO_WAYPOINT" && selectedBattleshipDestinationId !== "") {
            var shipIndex = Number(selectedBattleshipDestinationId.split("_")[1]) - 1
            var shipWaypoint = battleshipWaypoint(shipIndex)
            if (!shipWaypoint) {
                missionStatusText = "Battleship coordinates unavailable: " + battleshipCoordinatesError
                bridgeSendStatus = "Load blocked: battleship coordinate config"
                return
            }
            payload.destination_id = selectedBattleshipDestinationId
            payload.waypoint_coordinate = shipWaypoint
        }
        root.sendMissionCommand("RUN_TASK", payload)
    }

    function runGripperTask(action) {
        selectedTaskName = "GRIPPER"
        selectedTaskLabel = action === "OPEN" ? "OPEN GRIPPER" : "CLOSE GRIPPER"
        selectedGripperAction = action
        selectedTaskDisplay = "Selected: " + selectedTaskLabel
        missionStatusText = selectedTaskLabel + " sent"
        root.sendMissionCommand("RUN_TASK", {
            task_name: "GRIPPER",
            gripper_action: action
        })
    }

    function updateLocalMissionStatus(commandName, taskName) {
        if (commandName === "START_AUTO") {
            selectedMissionMode = "MANUAL_STEP"
            selectedMissionMode = "MANUAL_STEP"
            missionModeDisplay = "MANUAL_STEP"
            missionTaskDisplay = "IDLE"
            selectedTaskDisplay = "Selected: " + selectedTaskLabel
            missionStatusText = "Awaiting operator input"
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
        if (commandName === "RESET_KILL") {
            missionModeDisplay = "MANUAL_STEP"
            missionTaskDisplay = "IDLE"
            missionStatusText = "Kill reset requested — vehicle remains disarmed"
            return
        }
        if (commandName === "RESTORE_HOME") {
            missionStatusText = "Restore home requested"
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
            return
        }
        if (commandName === "HOVER_2FT") {
            missionStatusText = "2ft hover sent"
            return
        }
        if (commandName === "FINE_TUNE_MODE") {
            missionStatusText = "Fine tuning enabled"
            return
        }
    }

    function sendMissionCommand(commandName, extra) {
        // Surface the nudge direction (FORWARD/BACKWARD/LEFT/RIGHT) in the status
        // line instead of a bare "FINE_TUNE_NUDGE" that's indistinguishable per-arrow.
        var label = (extra && extra.direction) ? commandName + " " + extra.direction : commandName
        root.bridgeSendStatus = "Sending: " + label
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

    // Demo #4 (Points Round) scoring table, loaded from a YAML file. Each row:
    // { label, color, shape, points }. This replaces the old per-asset manual
    // points entry so the customer can change scoring on the fly by editing the
    // YAML instead of re-typing values.
    ListModel { id: demo4PointsModel }
    // The DEFAULT path is now the live ce_lcp file directly (an absolute path,
    // not the ":/…" Qt resource custom.qrc also bundles) - loadDemo4Points()
    // reads absolute paths straight off disk (file://) every time it runs, so
    // editing this file and reloading (or just re-locking round 4) picks up
    // new scoring with NO rebuild required. asset_match_node in ce_lcp reads
    // the same file (see asset_match_node.py's _default_round4_points_path())
    // for its round 4 confirm-prompt shortlist, so both sides stay in sync.
    // The compiled-in ":/Custom/qml/points/demo4_asset_points.yaml" resource
    // still exists as a fallback the operator can manually type in if this
    // path is ever unavailable (e.g. running QGC on a machine without ce_lcp
    // checked out at this exact path).
    readonly property string _demo4DefaultPointsPath: "/home/julieherrick/ce_lcp/C2_delivery/demo4_asset_points.yaml"
    property string demo4PointsPath:   _demo4DefaultPointsPath
    property bool   demo4PointsLoaded:  false
    property string demo4PointsStatus:  ""
    property bool   demo4LoadConfirmVisible: false

    // Running score for Demo #4 (Points Round): each row an operator confirms
    // (resolveAssetMatchCandidate) adds its looked-up demo4_asset_points.yaml
    // value here. See demo4PointsForCandidate() / resolveAssetMatchCandidate().
    property int demo4TotalPoints: 0
    ListModel { id: demo4ConfirmedAssetsModel }

    Component.onCompleted: {
        loadBattleshipCoordinates()
        showTemporaryMapOverlays()
        deployFullFieldGeofence()
    }
    Component.onDestruction: {
        clearTemporaryMapOverlays()
        clearConfirmedAssetMarkers()
    }

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
        id: divisionLineComponent

        MapPolyline {
            z: QGroundControl.zOrderMapItems + 11
            line.color: "white"
            line.width: 2
            path: [
                QtPositioning.coordinate(38.750665, -77.497247),
                QtPositioning.coordinate(38.750842, -77.496978)
            ]
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

    Component {
        id: assetMarkerComponent

        MapQuickItem {
            property color markerColor: _clrAmber
            property color markerTextColor: "white"
            property string label: ""

            z: QGroundControl.zOrderMapItems + 30
            anchorPoint.x: sourceItem.width / 2
            anchorPoint.y: sourceItem.height / 2

            sourceItem: Rectangle {
                width: 22
                height: 22
                radius: 11
                color: markerColor
                border.color: "white"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: label
                    color: markerTextColor
                    font.pixelSize: 10
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

        // Consumes clicks on empty chrome so they don't fall through to the map
        // underneath (e.g. accidentally setting a waypoint/origin).
        MouseArea {
            anchors.fill: parent
        }

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
                id:      statusTileRow
                Layout.preferredHeight: 34
                spacing: 8

                Rectangle {
                    width: 104; height: 34; radius: 5
                    color: !_activeVehicle ? _clrCard
                           : _activeVehicle.messageTypeError   ? _clrRed
                           : _activeVehicle.messageTypeWarning ? _clrAmber
                           : _clrCard
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: "MESSAGES"; color: "white"; opacity: 0.75; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            text: _activeVehicle ? _activeVehicle.messageCount : "—"
                            color: "white"
                            font.pixelSize: 12; font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: messagesPanel.visible ? messagesPanel.close() : messagesPanel.open()
                    }
                }

                Rectangle {
                    width: 118; height: 34
                    color: territoryStatus === "enemy" ? _clrRed : _clrCard
                    radius: 5
                    Column {
                        anchors.centerIn: parent; spacing: 0
                        Text { text: "TERRITORY"; color: "white"; opacity: 0.75; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            text: territoryStatus === "enemy" ? "ENEMY" :
                                  territoryStatus === "home"  ? "HOME"  : "UNKNOWN"
                            color: territoryStatus === "home"  ? _clrGreen :
                                   territoryStatus === "enemy" ? "white" : _clrMuted
                            font.pixelSize: 12; font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

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

            ComboBox {
                id:                      topModeCombo
                Layout.preferredWidth:   150
                Layout.preferredHeight:  34
                model:                   root.flightModes
                currentIndex:            root.flightModes.indexOf(root._currentFlightMode)

                onActivated: function(index) {
                    if (_activeVehicle) _activeVehicle.flightMode = root.flightModes[index]
                }

                background: Rectangle {
                    color:  _clrBlue
                    radius: 5
                }

                contentItem: Row {
                    leftPadding: 10
                    spacing:     6
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
                        width:            70
                        elide:            Text.ElideRight
                    }
                }

                indicator: Text {
                    text:                   "▼"
                    color:                  "white"
                    font.pixelSize:         10
                    anchors.right:          parent.right
                    anchors.rightMargin:    8
                    anchors.verticalCenter: parent.verticalCenter
                }

                popup: Popup {
                    y:       topModeCombo.height
                    width:   topModeCombo.width
                    padding: 1
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: ListView {
                        clip:           true
                        implicitHeight: contentHeight
                        model:          topModeCombo.delegateModel
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                }

                delegate: ItemDelegate {
                    width:       topModeCombo.width
                    highlighted: topModeCombo.highlightedIndex === index
                    background: Rectangle { color: highlighted ? _clrBlue : _clrCard }
                    contentItem: Text {
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

    // Vehicle messages dropdown, toggled by the MESSAGES tile in topBar.
    //
    // Deliberately does NOT reuse QGC's stock VehicleMessageList: PX4 can spam
    // the exact same STATUSTEXT (e.g. "Critical: Arming denied: Resolve system
    // health failures first") on every retry of a rejected command, and stock
    // VehicleMessageList inserts a brand new line per message with no dedup,
    // so a stuck retry loop balloons the panel into a wall of identical red
    // lines. This list collapses consecutive messages that are identical once
    // their timestamp is stripped into a single line with a "(xN)" counter
    // that just keeps updating in place, using the same raw
    // "<font style=\"<#X>\">[time] Severity: body</font><br/>" format
    // StatusTextHandler::processStatusText emits (see
    // src/MAVLink/StatusTextHandler.cc) so severity coloring still matches
    // stock QGC.
    //
    // Parented to the window's Overlay (like QGC's own QGCPopupDialog/checklist)
    // instead of living in the normal FlyView item tree -- plain Item z-values
    // are only compared against SIBLINGS and can never escape above another
    // branch's stacking (e.g. the preflight checklist, which is itself a Popup
    // living in this same Overlay). Overlay content always paints above the
    // window's regular content, and within the Overlay our z wins explicitly.
    Popup {
        id:           messagesPanel
        parent:       Overlay.overlay
        x:            statusTileRow.mapToItem(Overlay.overlay, 0, 0).x
        y:            topBar.mapToItem(Overlay.overlay, 0, topBar.height + 8).y
        z:            10000
        modal:        false
        focus:        false
        closePolicy:  Popup.NoAutoClose
        padding:      0
        width:        420
        height:       Math.min(messagesCol.implicitHeight + 24, 420)

        // White/translucent theme for this popup only (rest of the custom
        // overlay is dark) - matches the operator-preferred look, so text
        // colors here are dark-on-light rather than the app's usual white-on-dark.
        readonly property color _msgTextColor:    "#1a1c1f"
        readonly property color _msgMutedColor:   "#666666"
        readonly property color _msgDividerColor: "#dddddd"

        // Raw format from StatusTextHandler::processStatusText: style tag is
        // itself the literal placeholder (<#E>/<#I>/<#N>) that stock QGC's
        // formatMessage() would normally substitute with real CSS - we do our
        // own substitution in _severityColorFor instead.
        readonly property var _rawMessageRe: /^<font style="(<#[A-Z]>)">\[([^\]]*)\] ([^:]*): ([\s\S]*)<\/font>\s*<br\/>\s*$/

        function _severityColorFor(styleTag) {
            if (styleTag === "<#E>") return _clrRed
            if (styleTag === "<#I>") return _clrAmber
            return _msgTextColor
        }

        function _renderEntry(color, time, severity, body, count) {
            var suffix = count > 1 ? (' <font style="color:' + _msgMutedColor + '">(×' + count + ')</font>') : ''
            return '<font style="color:' + color + '">[' + time + '] ' + severity + ': ' + body + '</font>' + suffix
        }

        // Feed raw "<font ...>...</font><br/>" chunks through here in
        // chronological (oldest-first) order; each call either collapses into
        // the current newest entry (if identical once the timestamp is
        // stripped) or inserts a new one at the front.
        function _ingestRawMessage(raw) {
            var m = _rawMessageRe.exec(raw)
            if (!m) {
                // Unrecognized format - show verbatim rather than silently drop it.
                vehicleMessageModel.insert(0, { dedupKey: raw, displayText: raw, count: 1 })
                return
            }
            var style = m[1], time = m[2], severity = m[3], body = m[4]
            var dedupKey = style + "|" + severity + "|" + body
            var color = _severityColorFor(style)

            if (vehicleMessageModel.count > 0 && vehicleMessageModel.get(0).dedupKey === dedupKey) {
                var newCount = vehicleMessageModel.get(0).count + 1
                vehicleMessageModel.setProperty(0, "count", newCount)
                vehicleMessageModel.setProperty(0, "displayText", _renderEntry(color, time, severity, body, newCount))
            } else {
                vehicleMessageModel.insert(0, {
                    dedupKey:    dedupKey,
                    displayText: _renderEntry(color, time, severity, body, 1),
                    count:       1
                })
            }
        }

        ListModel { id: vehicleMessageModel }

        Connections {
            target: _activeVehicle
            onNewFormattedMessage: function(formattedMessage) { messagesPanel._ingestRawMessage(formattedMessage) }
        }

        Component.onCompleted: {
            if (_activeVehicle) {
                // _activeVehicle.formattedMessages is the full history, newest
                // chunk first; re-ingest oldest-first so insert(0,...) rebuilds
                // the same newest-first order (and so duplicate runs already in
                // history collapse too), then reset the badge/counter state.
                var chunks = _activeVehicle.formattedMessages.match(/<font[\s\S]*?<\/font>\s*<br\/>/g) || []
                for (var i = chunks.length - 1; i >= 0; i--) {
                    _ingestRawMessage(chunks[i])
                }
                _activeVehicle.resetAllMessages()
            }
        }

        background: Rectangle {
            color:        "#E6FFFFFF"
            border.color: _clrAmber
            border.width: 1
            radius:       8
        }

        contentItem: Column {
            id:              messagesCol
            anchors.left:    parent.left
            anchors.right:   parent.right
            anchors.top:     parent.top
            anchors.margins: 12
            spacing:         8

            Item {
                width:  parent.width
                height: 20
                Text { text: "Vehicle Messages"; color: messagesPanel._msgTextColor; font.pixelSize: 14; font.bold: true; anchors.left: parent.left }
                Text {
                    text: "✕"; color: messagesPanel._msgMutedColor; font.pixelSize: 15; anchors.right: parent.right
                    MouseArea { anchors.fill: parent; onClicked: messagesPanel.close() }
                }
                Rectangle {
                    anchors.right:  parent.right
                    anchors.rightMargin: 20
                    width:  16; height: 16; radius: 3
                    color:  "#eeeeee"
                    visible: vehicleMessageModel.count > 0
                    Text { anchors.centerIn: parent; text: "🗑"; font.pixelSize: 10 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (_activeVehicle) _activeVehicle.clearMessages()
                            vehicleMessageModel.clear()
                        }
                    }
                }
            }

            Flickable {
                width:         parent.width
                height:        Math.min(vehicleMessagesColumn.height, 340)
                contentWidth:  width
                contentHeight: vehicleMessagesColumn.height
                clip:          true

                Column {
                    id:      vehicleMessagesColumn
                    width:   parent.width
                    spacing: 4

                    Repeater {
                        model: vehicleMessageModel
                        delegate: Text {
                            width:          vehicleMessagesColumn.width
                            wrapMode:       Text.Wrap
                            textFormat:     Text.RichText
                            font.pixelSize: 12
                            text:           model.displayText
                        }
                    }

                    Text {
                        visible:  vehicleMessageModel.count === 0
                        width:    vehicleMessagesColumn.width
                        text:     "No Messages"
                        color:    messagesPanel._msgMutedColor
                        font.pixelSize: 12
                    }
                }
            }

            // Mirrors stock QGC's MainStatusIndicator "Overall Status" section
            // (src/QmlControls/MainStatusIndicator.qml) - PX4's current
            // health/arming-check problem list (e.g. "No manual control
            // input"). Unlike the STATUSTEXT log above, this is a live current
            // -state list, not an event stream, so it can't spam duplicates.
            // The rounded-bordered box below (matching stock's
            // SettingsGroupLayout container, src/QmlControls/SettingsGroupLayout.qml)
            // is what reads as a "dropdown" with a single problem in it.
            Column {
                id:      overallStatusColumn
                width:   parent.width
                spacing: 6
                visible: _activeVehicle && _healthAndArmingChecksSupported
                          && _activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode.count > 0

                readonly property bool _healthAndArmingChecksSupported:
                    _activeVehicle ? _activeVehicle.healthAndArmingCheckReport.supported : false

                Rectangle { width: overallStatusColumn.width; height: 1; color: messagesPanel._msgDividerColor }

                Text { text: "Overall Status"; color: messagesPanel._msgTextColor; font.pixelSize: 13; font.bold: true }

                Rectangle {
                    width:        overallStatusColumn.width
                    height:       overallStatusRepeaterCol.implicitHeight + 16
                    radius:       10
                    color:        "transparent"
                    border.color: messagesPanel._msgDividerColor
                    border.width: 1

                    Column {
                        id:      overallStatusRepeaterCol
                        anchors.left:           parent.left
                        anchors.right:          parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins:        12
                        spacing: 4

                        Repeater {
                            model: _activeVehicle ? _activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode : null
                            delegate: Text {
                                width:          overallStatusRepeaterCol.width
                                wrapMode:       Text.Wrap
                                textFormat:     Text.RichText
                                font.pixelSize: 12
                                text:           object.message
                                color:          object.severity === 'error'   ? _clrRed
                                              : object.severity === 'warning' ? _clrAmber
                                              : messagesPanel._msgTextColor
                            }
                        }
                    }
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

        // Consumes clicks on empty chrome so they don't fall through to the map
        // underneath (e.g. accidentally setting a waypoint/origin).
        MouseArea {
            anchors.fill: parent
        }

        // The sidebar content can be taller than the panel (e.g. Demo #4 adds the
        // YAML scoring section), so it lives inside a vertical Flickable and scrolls
        // instead of overflowing off the bottom bar.
        Flickable {
            id:                 leftPanelFlick
            anchors.fill:       parent
            anchors.margins:    12
            contentWidth:       width
            contentHeight:      leftColumn.implicitHeight
            clip:               true
            boundsBehavior:     Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id:      leftColumn
            width:   leftPanelFlick.width
            spacing: 10

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

            // Demo #3 (Battleship) — add up to 3 assets, one per battleship position.
            Column {
                Layout.fillWidth: true; spacing: 8
                visible: demoLocked && selectedDemoIndex === 2
                Text { text: "Add Asset (battleship positions, max 3)"; color: _clrMuted; font.pixelSize: 11 }
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
                    Rectangle {
                        property bool _canAdd: assetModel.count < 3   // exactly 3 battleship positions
                        width: 30; height: 28
                        color: _canAdd ? _clrGreen : "#555"; radius: 4
                        Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 18; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent._canAdd
                            onClicked: {
                                var clr = root.isColorlessShape(root.pendingShape) ? "" : root.pendingColor
                                assetModel.append({ assetColor: clr, assetShape: root.pendingShape, points: 0 })
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
                            // Per-asset return instruction shown on HOVER only, so the
                            // row stays one line and doesn't push the panel down.
                            HoverHandler { id: rowHover }
                            ToolTip.visible: rowHover.hovered
                            ToolTip.delay:   300
                            ToolTip.text:    root.battleshipReturnLabel(index)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.leftMargin: 10
                                text: model.assetColor ? (model.assetColor + " / " + model.assetShape) : model.assetShape
                                color: "white"; font.pixelSize: 11
                            }
                            Rectangle {
                                id: removeBtn; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 8
                                width: 20; height: 20; color: _clrKill; radius: 3
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; onClicked: assetModel.remove(index) }
                            }
                        }
                    }
                }
            }

            // Demo #4 (Points Round) — running score. Points are added when the
            // operator confirms a detected asset (resolveAssetMatchCandidate),
            // looked up from the loaded demo4_asset_points.yaml scoring table.
            Column {
                Layout.fillWidth: true; spacing: 6
                visible: demoLocked && selectedDemoIndex === 3
                Text {
                    text: "Total Round Points: " + root.demo4TotalPoints
                    color: "white"; font.pixelSize: 13; font.bold: true
                }
                Column {
                    spacing: 2; width: 236
                    Repeater {
                        model: demo4ConfirmedAssetsModel
                        delegate: Text {
                            text: model.label + " — " + model.points + " pt" + (model.points === 1 ? "" : "s")
                            color: _clrMuted
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Demo #4 (Points Round) — asset point values loaded from a YAML scoring
            // table instead of typed per asset. Editing the YAML lets the customer
            // change scoring on the fly; every possible asset is listed with its value
            // and the whole table is sent to ce_lcp for CV / route planning.
            Column {
                Layout.fillWidth: true; spacing: 6
                visible: demoLocked && selectedDemoIndex === 3
                Text { text: "Asset Point Values (YAML)"; color: _clrMuted; font.pixelSize: 11 }
                Row {
                    spacing: 6
                    TextField {
                        id: demo4PathField
                        width: 176; height: 28
                        text: root.demo4PointsPath
                        color: "white"; font.pixelSize: 10
                        placeholderText: "path to points .yaml"
                        background: Rectangle { color: _clrCard; radius: 4 }
                        // Path is wider than the field; show the full value on hover.
                        hoverEnabled:    true
                        ToolTip.visible: hovered && text.length > 0
                        ToolTip.delay:   300
                        ToolTip.text:    text
                    }
                    Rectangle {
                        width: 54; height: 28; radius: 4; color: _clrGreen
                        Text { anchors.centerIn: parent; text: "Load"; color: "white"; font.pixelSize: 12; font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.demo4PointsPath = demo4PathField.text
                                root.loadDemo4Points(demo4PathField.text)
                                root.demo4LoadConfirmVisible = true
                                demo4LoadConfirmTimer.restart()
                            }
                        }
                    }
                }
                // Transient confirmation shown only right after a Load click - auto-hides
                // itself after a few seconds via demo4LoadConfirmTimer.
                Text {
                    visible: root.demo4LoadConfirmVisible
                    text: (root.demo4PointsLoaded ? "✓ " : "⚠ ") + root.demo4PointsStatus
                    color: root.demo4PointsLoaded ? _clrGreen : _clrAmber
                    font.pixelSize: 11
                    font.bold: true
                    Timer {
                        id: demo4LoadConfirmTimer
                        interval: 3000
                        onTriggered: root.demo4LoadConfirmVisible = false
                    }
                }
                // Reference-only dropdown: press to browse every asset/color combo and
                // its point value. This is purely for operator awareness — picking a row
                // does NOT select an asset, so the closed field always shows the same
                // browse prompt rather than reflecting a "selection".
                ComboBox {
                    id: demo4PointsDropdown
                    width: 236
                    implicitHeight: 30
                    model: demo4PointsModel
                    enabled: demo4PointsModel.count > 0
                    // Keep the field neutral so no row ever looks "chosen".
                    onActivated: currentIndex = -1
                    background: Rectangle { color: _clrCard; radius: 4 }
                    contentItem: Text {
                        leftPadding: 8; verticalAlignment: Text.AlignVCenter
                        color: "white"; font.pixelSize: 11
                        text: demo4PointsModel.count === 0
                                  ? "No values loaded"
                                  : "Browse asset point values (" + demo4PointsModel.count + ")"
                    }
                    popup: Popup {
                        y: demo4PointsDropdown.height; width: demo4PointsDropdown.width; padding: 1
                        implicitHeight: Math.min(contentItem.implicitHeight, 240)
                        background: Rectangle { color: _clrCard; radius: 4 }
                        contentItem: ListView { clip: true; implicitHeight: contentHeight; model: demo4PointsDropdown.delegateModel; ScrollBar.vertical: ScrollBar {} }
                    }
                    delegate: ItemDelegate {
                        width: demo4PointsDropdown.width; highlighted: demo4PointsDropdown.highlightedIndex === index
                        background: Rectangle { color: highlighted ? "#444" : _clrCard }
                        contentItem: Row {
                            spacing: 8; leftPadding: 8
                            Text { width: 150; text: model.label; color: "white"; font.pixelSize: 11; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                            Text { text: model.points + " pt"; color: _clrGreen; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
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
                        Text { text: selectedTaskDisplay; color: _clrGreen; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                        Text { text: missionStatusText; color: _clrAmber; font.pixelSize: 10; width: parent.width; elide: Text.ElideRight }
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

                Row {
                    spacing: 6
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            property bool roundAllowed: root.selectedMissionRoundId() === 3
                            property bool destinationCompleted: root.battleshipCompleted(index)
                            property string destinationId: root.battleshipDestinationId(index)
                            width: 74; height: 28; radius: 4
                            color: destinationCompleted ? "#555"
                                  : root.selectedBattleshipDestinationId === destinationId ? _clrBlue : _clrCard
                            opacity: roundAllowed && !destinationCompleted ? 1.0 : 0.35
                            Text {
                                anchors.centerIn: parent
                                text: "BATTLESHIP " + (index + 1)
                                color: "white"; font.pixelSize: 7; font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: parent.roundAllowed && !parent.destinationCompleted
                                onClicked: root.selectBattleship(index)
                            }
                        }
                    }
                }

                // 2ft Hover — slow ease down/up to a 2ft-above-ground hold, measured
                // via the rangefinder (see px4_control_node's hover_2ft_altitude_m /
                // hover_2ft_descent_rate_m_s), latched over the current horizontal
                // position so it doesn't drift sideways.
                // Fine Tuning — arms the bottom-right nudge arrows; they are a no-op
                // until this is pressed (px4_control_node's _fine_tune_enabled gate),
                // and it turns back off automatically when a new task is loaded.
                // These share selectedTaskName with the task grid above (via
                // selectMissionTask) so exactly one button in this whole section --
                // TAKEOFF/SURVEY/BATTLESHIP/GRIPPER/GAAP/2ft Hover/Fine Tuning -- is
                // ever highlighted at a time. Same two-step flow as the grid too:
                // clicking only selects (highlight), "Load Task" is what actually
                // sends the command (see loadSelectedMissionTask's HOVER_2FT /
                // FINE_TUNE_MODE branch).
                Row {
                    spacing: 6
                    Rectangle {
                        width: 115; height: 28; radius: 4
                        color: root.selectedTaskName === "HOVER_2FT" ? _clrBlue : _clrCard
                        Text {
                            anchors.centerIn: parent
                            text: "2FT HOVER"
                            color: "white"
                            font.pixelSize: 9
                            font.bold: root.selectedTaskName === "HOVER_2FT"
                            elide: Text.ElideRight
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectMissionTask("HOVER_2FT", "2FT HOVER", "")
                        }
                    }
                    Rectangle {
                        width: 115; height: 28; radius: 4
                        color: root.selectedTaskName === "FINE_TUNE_MODE" ? _clrBlue : _clrCard
                        Text {
                            anchors.centerIn: parent
                            text: "FINE TUNING"
                            color: "white"
                            font.pixelSize: 9
                            font.bold: root.selectedTaskName === "FINE_TUNE_MODE"
                            elide: Text.ElideRight
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectMissionTask("FINE_TUNE_MODE", "FINE TUNING", "")
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

        // Consumes clicks on empty chrome so they don't fall through to the map
        // underneath (e.g. accidentally setting a waypoint/origin).
        MouseArea {
            anchors.fill: parent
        }

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
    // FINE TUNE POSITION  (manual 1-inch nudge arrows + 5-degree yaw arrows)
    // Bottom-right corner of the map/video area — left of the telemetry panel,
    // above the command bar. Each press is a single one-shot nudge in the
    // vehicle's current body/heading frame (px4_control_node's nudge_step_m,
    // default 1 inch) added to whatever position it's currently holding/flying;
    // it is NOT a continuous jog. The curved arrows below rotate yaw by
    // yaw_nudge_step_deg (default 5°) the same way, clockwise/counter-clockwise.
    // These are a no-op until the "Fine Tuning" button (left panel, above Load
    // Task) has been loaded at least once since the last task change
    // (px4_control_node's _fine_tune_enabled gate) -- loading it also breaks
    // HOLD/PAUSE back to AUTONOMY (mirrors legacy RESUME), since px4_control_node
    // only streams setpoints, and therefore only acts on nudges, while in
    // AUTONOMY. See ce_px4_bridge/px4_control_node.py _on_fine_tune_nudge /
    // _on_fine_tune_mode / _manual_offset_*.
    // Mirrored client-side via root.fineTuningActive (set true when Fine Tuning
    // is loaded, false when any other task loads) so the arrows refuse to send
    // at all -- rather than silently sending a command px4_control_node would
    // just ignore -- until Fine Tuning has actually been loaded.
    // =========================================================================
    Rectangle {
        id:                   fineTunePanel
        width:                128
        height:               172
        anchors.right:        rightPanel.left
        anchors.rightMargin:  12
        anchors.bottom:       bottomBar.top
        anchors.bottomMargin: 12
        color:                "#F2111820"
        border.color:         _clrMuted
        border.width:         1
        radius:               8
        z:                    900
        opacity:              root.fineTuningActive ? 1.0 : 0.4

        // Consumes clicks on empty chrome (gaps between arrow buttons, panel
        // margins) so they don't fall through to the map underneath.
        MouseArea {
            anchors.fill: parent
        }

        function nudge(direction) {
            if (!root.fineTuningActive) {
                root.missionStatusText = "Select Fine Tuning and Load Task before nudging"
                return
            }
            root.sendMissionCommand("FINE_TUNE_NUDGE", { direction: direction })
        }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
                width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "▲"; color: "white"; font.pixelSize: 18; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("FORWARD") }
            }

            Row {
                spacing: 4
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                    Text { anchors.centerIn: parent; text: "◄"; color: "white"; font.pixelSize: 18; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("LEFT") }
                }

                Rectangle {
                    width: 34; height: 34; radius: 6; color: "transparent"
                    Text { anchors.centerIn: parent; text: "1 in"; color: _clrMuted; font.pixelSize: 11 }
                }

                Rectangle {
                    width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                    Text { anchors.centerIn: parent; text: "►"; color: "white"; font.pixelSize: 18; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("RIGHT") }
                }
            }

            Rectangle {
                width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "▼"; color: "white"; font.pixelSize: 18; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("BACKWARD") }
            }

            Row {
                spacing: 4
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                    Text { anchors.centerIn: parent; text: "↺"; color: "white"; font.pixelSize: 20; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("YAW_CCW") }
                }

                Rectangle {
                    width: 34; height: 34; radius: 6; color: "transparent"
                    Text { anchors.centerIn: parent; text: "5°"; color: _clrMuted; font.pixelSize: 11 }
                }

                Rectangle {
                    width: 34; height: 34; radius: 6; color: _clrCard; border.color: _clrMuted; border.width: 1
                    Text { anchors.centerIn: parent; text: "↻"; color: "white"; font.pixelSize: 20; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: fineTunePanel.nudge("YAW_CW") }
                }
            }
        }
    }

    // =========================================================================
    // COMMAND STRIP  (bottom bar)
    // Center: Arm | Hold | Land | Restore Home | RTL | Complete Demo | Reset Kill | Kill
    // =========================================================================
    Rectangle {
        id:             bottomBar
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height:         _bottomBarHeight
        color:          _clrPanel

        // Consumes clicks on empty chrome so they don't fall through to the map
        // underneath (e.g. accidentally setting a waypoint/origin).
        MouseArea {
            anchors.fill: parent
        }

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

            // Arm/Disarm — manual (re-)arm, or disarm if already armed. Issues a real
            // PX4 arm/disarm via ROS (sendMissionCommand("ARM"/"DISARM") ->
            // px4_command_bridge -> COMPONENT_ARM_DISARM).
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
                        root.sendMissionCommand(armBtn.vehArmed ? "DISARM" : "ARM")
                    }
                }
            }

            // Hold Position — ROS commands PX4 Auto Loiter and stops Offboard.
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
                    }
                }
            }

            // Land Mission — ROS sends PX4 NAV_LAND.
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
                    }
                }
            }

            // Return to Home — ROS sends PX4 RTL (demo reset is the COMPLETE DEMO button)
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

            // Debug — grey, far right. Expands (via debugPopup) to reveal Restore Home,
            // Reset Kill, and stock QGC's own Messages/status and GPS indicators - all
            // tucked away here since none is needed in normal operation: home now
            // restores/verifies automatically before every arm, reset-kill is a rare
            // ground-safety recovery action, and Messages/GPS are stock QGC components
            // mounted for debugging (the CrownEagle FlyView hides QGC's stock toolbar
            // that would normally show them, same Loader pattern as the gimbal indicator
            // in FlyViewWidgetLayer.qml).
            Rectangle {
                id: debugBtn
                width: debugLbl.width + 28; height: 38; radius: 6; color: _clrMuted
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "⚙"; color: "white"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                    Text { id: debugLbl; text: "DEBUG"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: debugPopup.visible = !debugPopup.visible
                }
            }
        }
    }

    Popup {
        id: debugPopup
        modal: false
        focus: false
        closePolicy: Popup.CloseOnPressOutside
        width: 260
        padding: 10
        x: Math.max(12, root.width - width - 12)
        y: Math.max(_topBarHeight + 12, root.height - _bottomBarHeight - height - 12)
        z: 1300
        background: Rectangle { color: _clrPanel; border.color: _clrMuted; border.width: 1; radius: 8 }
        contentItem: Column {
            spacing: 10

            // Stock QGC's own Messages/status indicator (message log + "Overall
            // Status" health/arming-check list) and GPS/satellite indicator, mounted
            // directly since the stock toolbar that normally hosts them is hidden.
            // Sharing one bar, spaced apart rather than stacked. _clrCard (not white)
            // since both components render qgcPal.text, which is white/light under
            // this app's dark theme - white-on-white would be illegible.
            Rectangle {
                width: parent.width; height: 38; radius: 6
                color: _clrCard
                Row {
                    anchors.centerIn: parent
                    spacing: 24
                    Loader {
                        height: 30
                        source: "qrc:/qml/QGroundControl/Controls/MainStatusIndicator.qml"
                    }
                    Loader {
                        height: 30
                        source: "qrc:/qml/QGroundControl/Toolbar/VehicleGPSIndicator.qml"
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: _clrMuted; opacity: 0.4 }

            // Mirrors the main mission status line (missionStatusText, see line ~2563)
            // so feedback from Restore Home / Reset Kill is visible right here without
            // closing this popup to go look at the mission panel on the other side of
            // the screen.
            Text {
                width: parent.width
                text: missionStatusText
                color: _clrAmber
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            // Restore Home — ROS asks px4_control_node to (re-)send and verify the
            // configured fixed home while landed/disarmed. Manual retry only: home
            // now restores and is gated before every arm automatically on its own.
            Rectangle {
                id: restoreHomeBtn
                readonly property bool vehArmed: _activeVehicle ? _activeVehicle.armed : false
                readonly property bool canRestore: demoLocked && homeGroundContact && !vehArmed
                width: parent.width; height: 38; radius: 6
                color: homeLockStatus === "HOME LOCKED" ? _clrGreen : (canRestore ? _clrBlue : _clrCard)
                opacity: canRestore ? 1.0 : 0.55
                border.color: _clrMuted; border.width: 1
                HoverHandler { id: restoreHomeHover }
                // Explicit ToolTip (not the attached ToolTip.visible/.text shorthand)
                // parented straight to the window's Overlay with a z above debugPopup's
                // (1300) - this button lives inside another Popup's contentItem, and the
                // implicit attached tooltip was getting painted under debugPopup's own
                // later Column siblings instead of on top of the whole popup.
                ToolTip {
                    parent:  Overlay.overlay
                    visible: restoreHomeHover.hovered
                    text:    homeLockStatus + (homeLockReason ? (": " + homeLockReason) : "")
                    x:       restoreHomeBtn.mapToItem(Overlay.overlay, 0, 0).x
                    y:       restoreHomeBtn.mapToItem(Overlay.overlay, 0, 0).y - height - 4
                    z:       1500
                }
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "⌂"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "RESTORE HOME"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: restoreHomeBtn.canRestore
                    onClicked: root.sendMissionCommand("RESTORE_HOME")
                }
            }

            // Reset Kill — ground-safety lockout reset (rare recovery action).
            Rectangle {
                id: resetKillBtn
                readonly property bool canRequestReset: !_activeVehicle || !_activeVehicle.armed
                width: parent.width; height: 38; radius: 6
                color: canRequestReset ? _clrOrange : _clrCard
                opacity: canRequestReset ? 1.0 : 0.55
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Text { text: "↺"; color: "white"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "RESET KILL"; color: "white"; font.pixelSize: 12; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: resetKillBtn.canRequestReset
                    onClicked: {
                        debugPopup.visible = false
                        resetKillConfirmPopup.open()
                    }
                }
            }
        }
    }

    Popup {
        id: resetKillConfirmPopup
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        width: 400
        height: 190
        padding: 18
        x: Math.max(12, (root.width - width) / 2)
        y: Math.max(12, (root.height - height) / 2)
        z: 1400
        background: Rectangle {
            color: _clrPanel
            border.color: _clrOrange
            border.width: 2
            radius: 8
        }
        contentItem: Column {
            spacing: 14
            Text {
                width: parent.width
                text: "RESET KILL LOCKOUT?"
                color: "white"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "Reset is accepted only with fresh PX4 telemetry, a healthy link, the vehicle disarmed, and valid ground-level AGL. It will not arm or resume autonomy."
                color: _clrMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Rectangle {
                    width: 120; height: 36; radius: 6; color: _clrCard; border.color: _clrMuted
                    Text { anchors.centerIn: parent; text: "CANCEL"; color: "white"; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: resetKillConfirmPopup.close() }
                }
                Rectangle {
                    width: 150; height: 36; radius: 6; color: _clrOrange
                    Text { anchors.centerIn: parent; text: "CONFIRM RESET"; color: "white"; font.bold: true }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            resetKillConfirmPopup.close()
                            root.sendMissionCommand("RESET_KILL")
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: assetMatchPopup
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        width: 340
        padding: 0
        x: Math.max(12, root.width - _rightPanelWidth - width - 12)
        y: Math.max(_topBarHeight + 12, root.height - _bottomBarHeight - height - 12)
        z: 1200
        background: Rectangle {
            color: "#F2111820"
            border.color: _clrAmber
            border.width: 1
            radius: 8
        }
        contentItem: Item {
            implicitWidth: assetMatchPopup.width
            implicitHeight: assetMatchContent.implicitHeight + 32
            Column {
                id: assetMatchContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10

                Text {
                    width: parent.width
                    text: "Target Candidate"
                    color: "white"
                    font.pixelSize: 17
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: "Detected: " + root.assetCandidateText(pendingAssetMatch)
                    color: "white"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "Target: " + root.assetTargetText(pendingAssetMatch)
                    color: _clrMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "Confidence: " + root.candidateConfidenceText(pendingAssetMatch)
                    color: _clrAmber
                    font.pixelSize: 12
                    font.bold: true
                }
                Row {
                    spacing: 10
                    Rectangle {
                        width: 145; height: 34; radius: 4; color: _clrGreen
                        Text { anchors.centerIn: parent; text: "Confirm"; color: "white"; font.pixelSize: 12; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.resolveAssetMatchCandidate(true) }
                    }
                    Rectangle {
                        width: 145; height: 34; radius: 4; color: _clrKill
                        Text { anchors.centerIn: parent; text: "Reject"; color: "white"; font.pixelSize: 12; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.resolveAssetMatchCandidate(false) }
                    }
                }
            }
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

        // Consumes clicks on empty chrome so they don't fall through to the map
        // underneath.
        MouseArea {
            anchors.fill: parent
        }

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
