import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  readonly property string labelMode: (widgetSettings.labelMode !== undefined) ? widgetSettings.labelMode : widgetMetadata.labelMode
  readonly property bool hasLabel: (labelMode !== "none")
  readonly property bool hideUnoccupied: (widgetSettings.hideUnoccupied !== undefined) ? widgetSettings.hideUnoccupied : widgetMetadata.hideUnoccupied
  readonly property bool followFocusedScreen: (widgetSettings.followFocusedScreen !== undefined) ? widgetSettings.followFocusedScreen : widgetMetadata.followFocusedScreen
  readonly property int characterCount: isVertical ? 2 : ((widgetSettings.characterCount !== undefined) ? widgetSettings.characterCount : widgetMetadata.characterCount)

  // Pill size setting (0.5-1.0 range)
  readonly property real pillSize: (widgetSettings.pillSize !== undefined) ? widgetSettings.pillSize : widgetMetadata.pillSize

  // When no label the pills are smaller
  readonly property real baseDimensionRatio: pillSize

  // Grouped mode settings
  readonly property bool showLabelsOnlyWhenOccupied: (widgetSettings.showLabelsOnlyWhenOccupied !== undefined) ? widgetSettings.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  readonly property bool enableScrollWheel: (widgetSettings.enableScrollWheel !== undefined) ? widgetSettings.enableScrollWheel : widgetMetadata.enableScrollWheel
  readonly property bool reverseScroll: Settings.data.general.reverseScroll
  readonly property string focusedColor: (widgetSettings.focusedColor !== undefined) ? widgetSettings.focusedColor : widgetMetadata.focusedColor
  readonly property string occupiedColor: (widgetSettings.occupiedColor !== undefined) ? widgetSettings.occupiedColor : widgetMetadata.occupiedColor
  readonly property string emptyColor: (widgetSettings.emptyColor !== undefined) ? widgetSettings.emptyColor : widgetMetadata.emptyColor

  readonly property real textRatio: 0.50

  property bool isDestroying: false
  property bool hovered: false

  property ListModel localWorkspaces: ListModel {}
  property int lastFocusedWorkspaceId: -1
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  property int horizontalPadding: Style.marginS
  property int spacingBetweenPills: Style.marginXS

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  signal workspaceChanged(int workspaceId, color accentColor)

  implicitWidth: isVertical ? barHeight : computeWidth()
  implicitHeight: isVertical ? computeHeight() : barHeight

  function getWorkspaceWidth(ws, activeOverride) {
    const d = Math.round(capsuleHeight * root.baseDimensionRatio);
    const isActive = activeOverride !== undefined ? activeOverride : ws.isActive;
    const factor = isActive ? 2.2 : 1;

    // Don't calculate text width if labels are off
    if (labelMode === "none") {
      return Style.toOdd(d * factor);
    }

    var displayText = ws.idx.toString();

    if (ws.name && ws.name.length > 0) {
      if (root.labelMode === "name") {
        displayText = ws.name.substring(0, characterCount);
      } else if (root.labelMode === "index+name") {
        displayText = ws.idx.toString() + " " + ws.name.substring(0, characterCount);
      }
    }

    const textWidth = displayText.length * (d * 0.4); // Approximate width per character
    const padding = d * 0.6;
    return Style.toOdd(Math.max(d * factor, textWidth + padding));
  }

  function getWorkspaceHeight(ws, activeOverride) {
    const d = Math.round(capsuleHeight * root.baseDimensionRatio);
    const isActive = activeOverride !== undefined ? activeOverride : ws.isActive;
    const factor = isActive ? 2.2 : 1;
    return Style.toOdd(d * factor);
  }

  function computeWidth() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceWidth(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
  }

  function computeHeight() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceHeight(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
  }

  function getFocusedLocalIndex() {
    for (var i = 0; i < localWorkspaces.count; i++) {
      if (localWorkspaces.get(i).isFocused === true)
        return i;
    }
    return -1;
  }

  function switchByOffset(offset) {
    if (localWorkspaces.count === 0)
      return;
    var current = getFocusedLocalIndex();
    if (current < 0)
      current = 0;
    var next = (current + offset) % localWorkspaces.count;
    if (next < 0)
      next = localWorkspaces.count - 1;
    const ws = localWorkspaces.get(next);
    if (ws && ws.idx !== undefined)
      CompositorService.switchToWorkspace(ws);
  }

  Component.onCompleted: {
    refreshWorkspaces();
  }

  Component.onDestruction: {
    root.isDestroying = true;
  }

  onScreenChanged: refreshWorkspaces()
  onScreenNameChanged: refreshWorkspaces()
  onHideUnoccupiedChanged: refreshWorkspaces()

  Connections {
    target: CompositorService
    function onWorkspacesChanged() {
      refreshWorkspaces();
    }
    function onWindowListChanged() {
      if (showLabelsOnlyWhenOccupied) {
        refreshWorkspaces();
      }
    }
  }

  function refreshWorkspaces() {
    var targetList = [];
    var focusedOutput = null;
    if (followFocusedScreen) {
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i);
        if (ws.isFocused)
          focusedOutput = ws.output.toLowerCase();
      }
    }

    if (screen !== null) {
      const screenName = screen.name.toLowerCase();
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i);
        const matchesScreen = (followFocusedScreen && ws.output.toLowerCase() == focusedOutput) || (!followFocusedScreen && ws.output.toLowerCase() == screenName);

        if (!matchesScreen)
          continue;
        if (hideUnoccupied && !ws.isOccupied && !ws.isFocused)
          continue;

        // Create a plain JS object for the workspace data
        var workspaceData = {
          id: ws.id,
          idx: ws.idx,
          name: ws.name,
          output: ws.output,
          isFocused: ws.isFocused,
          isActive: ws.isActive,
          isUrgent: ws.isUrgent,
          isOccupied: ws.isOccupied
        };

        if (ws.handle !== null && ws.handle !== undefined) {
          workspaceData.handle = ws.handle;
        }

        // Windows are fetched live via liveWindows property in grouped mode
        // to avoid Qt 6.9 ListModel nested array serialization issues

        targetList.push(workspaceData);
      }
    }

    // In-place update to preserve delegates for animations
    var i = 0;
    while (i < localWorkspaces.count || i < targetList.length) {
      if (i < localWorkspaces.count && i < targetList.length) {
        var existing = localWorkspaces.get(i);
        var target = targetList[i];
        if (existing.id === target.id) {
          // Use set() to update all properties, including arrays like 'windows'
          // This is more reliable than repeated setProperty calls for complex types
          localWorkspaces.set(i, target);
          i++;
        } else {
          // ID mismatch, remove existing and re-evaluate this index
          localWorkspaces.remove(i);
        }
      } else if (i < localWorkspaces.count) {
        // Excess items in local, remove them
        localWorkspaces.remove(i);
      } else {
        // More items in target, append them
        localWorkspaces.append(targetList[i]);
        i++;
      }
    }

    updateWorkspaceFocus();
  }

  function triggerUnifiedWave() {
    effectColor = Color.mPrimary;
    masterAnimation.restart();
  }

  function updateWorkspaceFocus() {
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      if (ws.isFocused === true) {
        if (root.lastFocusedWorkspaceId !== -1 && root.lastFocusedWorkspaceId !== ws.id) {
          root.triggerUnifiedWave();
        }
        root.lastFocusedWorkspaceId = ws.id;
        root.workspaceChanged(ws.id, Color.mPrimary);
        break;
      }
    }
  }

  SequentialAnimation {
    id: masterAnimation
    PropertyAction {
      target: root
      property: "effectsActive"
      value: true
    }
    NumberAnimation {
      target: root
      property: "masterProgress"
      from: 0.0
      to: 1.0
      duration: Style.animationSlow * 2
      easing.type: Easing.OutQuint
    }
    PropertyAction {
      target: root
      property: "effectsActive"
      value: false
    }
    PropertyAction {
      target: root
      property: "masterProgress"
      value: 0.0
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      }
    ]

    onTriggered: (action, item) => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  Rectangle {
    id: workspaceBackground
    width: isVertical ? capsuleHeight : parent.width
    height: isVertical ? parent.height : capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    x: isVertical ? Style.pixelAlignCenter(parent.width, width) : 0
    y: isVertical ? 0 : Style.pixelAlignCenter(parent.height, height)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: mouse => {
                   if (mouse.button === Qt.RightButton) {
                     PanelService.showContextMenu(contextMenu, workspaceBackground, screen);
                   }
                 }
    }
  }

  // Debounce timer for wheel interactions
  Timer {
    id: wheelDebounce
    interval: 150
    repeat: false
    onTriggered: {
      root.wheelCooldown = false;
      root.wheelAccumulatedDelta = 0;
    }
  }

  // Scroll to switch workspaces
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    enabled: root.enableScrollWheel
    onWheel: function (event) {
      if (root.wheelCooldown)
        return;
      // Prefer vertical delta, fall back to horizontal if needed
      var dy = event.angleDelta.y;
      var dx = event.angleDelta.x;
      var useDy = Math.abs(dy) >= Math.abs(dx);
      var delta = useDy ? dy : dx;
      // One notch is typically 120
      root.wheelAccumulatedDelta += delta;
      var step = 120;
      if (Math.abs(root.wheelAccumulatedDelta) >= step) {
        var direction = root.wheelAccumulatedDelta > 0 ? -1 : 1;
        if (root.reverseScroll)
          direction *= -1;
        // For vertical layout, natural mapping: wheel up -> previous, down -> next (already handled by sign)
        // For horizontal layout, same mapping using vertical wheel
        root.switchByOffset(direction);
        root.wheelCooldown = true;
        wheelDebounce.restart();
        root.wheelAccumulatedDelta = 0;
        event.accepted = true;
      }
    }
  }

  // Horizontal layout for top/bottom bars
  Row {
    id: pillRow
    spacing: spacingBetweenPills
    x: horizontalPadding
    y: 0
    visible: !isVertical

    Repeater {
      id: workspaceRepeaterHorizontal
      model: localWorkspaces
      delegate: WorkspacePill {
        required property var model
        workspace: model
        isVertical: false
        baseDimensionRatio: root.baseDimensionRatio
        capsuleHeight: root.capsuleHeight
        barHeight: root.barHeight
        labelMode: root.labelMode
        characterCount: root.characterCount
        textRatio: root.textRatio
        showLabelsOnlyWhenOccupied: root.showLabelsOnlyWhenOccupied
        focusedColor: root.focusedColor
        occupiedColor: root.occupiedColor
        emptyColor: root.emptyColor
        masterProgress: root.masterProgress
        effectsActive: root.effectsActive
        effectColor: root.effectColor
        getWorkspaceWidth: root.getWorkspaceWidth
        getWorkspaceHeight: root.getWorkspaceHeight
      }
    }
  }

  // Vertical layout for left/right bars
  Column {
    id: pillColumn
    spacing: spacingBetweenPills
    x: 0
    y: horizontalPadding
    visible: isVertical

    Repeater {
      id: workspaceRepeaterVertical
      model: localWorkspaces
      delegate: WorkspacePill {
        required property var model
        workspace: model
        isVertical: true
        baseDimensionRatio: root.baseDimensionRatio
        capsuleHeight: root.capsuleHeight
        barHeight: root.barHeight
        labelMode: root.labelMode
        characterCount: root.characterCount
        textRatio: root.textRatio
        showLabelsOnlyWhenOccupied: root.showLabelsOnlyWhenOccupied
        focusedColor: root.focusedColor
        occupiedColor: root.occupiedColor
        emptyColor: root.emptyColor
        masterProgress: root.masterProgress
        effectsActive: root.effectsActive
        effectColor: root.effectColor
        getWorkspaceWidth: root.getWorkspaceWidth
        getWorkspaceHeight: root.getWorkspaceHeight
      }
    }
  }
}
