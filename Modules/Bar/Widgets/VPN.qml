import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property bool isBarVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: {
      const items = [];
      const active = VPNService.activeConnections;

      if (active.length > 0) {
        items.push({
                     "label": "Disconnect Windscribe",
                     "action": "disconnect",
                     "icon": "shield-off"
                   });
      } else {
        items.push({
                     "label": "Connect Windscribe (Seine)",
                     "action": "connect",
                     "icon": "shield-lock"
                   });
      }

      items.push({
                   "label": I18n.tr("actions.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow)
                   popupMenuWindow.close();

                   if (!action)
                   return;

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   } else if (action === "connect") {
                     VPNService.connect("windscribe");
                   } else if (action === "disconnect") {
                     VPNService.disconnect("windscribe");
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen

    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: VPNService.hasActiveConnection ? "shield-lock" : "shield"

    text: {
      if (VPNService.activeConnections.length > 0) {
        return VPNService.activeConnections[0].name;
      }
      if (VPNService.connectingUuid) {
        const pending = VPNService.connections[VPNService.connectingUuid];
        if (pending) {
          return pending.name;
        }
      }
      return "";
    }

    suffix: {
      if (VPNService.activeConnections.length > 1) {
        return ` + ${VPNService.activeConnections.length - 1}`;
      }
      return "";
    }

    autoHide: false
    forceOpen: !isBarVertical && root.displayMode === "alwaysShow"
    forceClose: isBarVertical || root.displayMode === "alwaysHide" || !pill.text

    onClicked: {
      VPNService.toggle();
    }

    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        popupMenuWindow.showContextMenu(contextMenu);
        contextMenu.openAtItem(pill, screen);
      }
    }

    tooltipText: {
      if (pill.text !== "") {
        return pill.text;
      }
      return I18n.tr("tooltips.manage-vpn");
    }
  }
}
