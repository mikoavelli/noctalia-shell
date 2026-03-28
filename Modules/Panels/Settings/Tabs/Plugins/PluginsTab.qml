import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property int installedPluginsRefreshCounter: 0

  function stripAuthorEmail(author) {
    if (!author)
      return "";
    var lastBracket = author.lastIndexOf("<");
    if (lastBracket >= 0) {
      return author.substring(0, lastBracket).trim();
    }
    return author;
  }

  // Installed plugins list
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: installedPluginsRepeater

      model: {
        // Force refresh when counter changes
        var _ = root.installedPluginsRefreshCounter;

        var allIds = PluginRegistry.getAllInstalledPluginIds();
        var plugins = [];
        for (var i = 0; i < allIds.length; i++) {
          var pluginId = allIds[i];
          var manifest = PluginRegistry.getPluginManifest(pluginId);
          if (manifest) {
            var pluginData = JSON.parse(JSON.stringify(manifest));
            pluginData.compositeKey = pluginId;
            pluginData.enabled = PluginRegistry.isPluginEnabled(pluginId);
            plugins.push(pluginData);
          }
        }
        return plugins;
      }

      delegate: NBox {
        Layout.fillWidth: true
        Layout.leftMargin: Style.borderS
        Layout.rightMargin: Style.borderS
        implicitHeight: Math.round(contentColumn.implicitHeight + Style.marginL * 2)
        color: Color.mSurface

        ColumnLayout {
          id: contentColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          // Top row: icon, name, spacer, action buttons
          RowLayout {
            spacing: Style.marginM
            Layout.fillWidth: true

            NIcon {
              icon: "plugin"
              pointSize: Style.fontSizeL
              color: PluginService.hasPluginError(modelData.compositeKey) ? Color.mError : Color.mPrimary
            }

            NText {
              text: modelData.name
              color: Color.mPrimary
              elide: Text.ElideRight
            }

            // Spacer
            Item {
              Layout.fillWidth: true
            }

            NIconButtonHot {
              icon: "bug"
              hot: PluginService.isPluginHotReloadEnabled(modelData.id)
              tooltipText: PluginService.isPluginHotReloadEnabled(modelData.id) ? I18n.tr("panels.plugins.development-disable") : I18n.tr("panels.plugins.development-enable")
              baseSize: Style.baseWidgetSize * 0.7
              onClicked: PluginService.togglePluginHotReload(modelData.id)
              visible: Settings.isDebug
            }

            NIconButton {
              icon: "settings"
              tooltipText: I18n.tr("panels.plugins.settings-tooltip")
              baseSize: Style.baseWidgetSize * 0.7
              visible: (modelData.entryPoints?.settings !== undefined)
              enabled: modelData.enabled
              onClicked: {
                pluginSettingsDialog.openPluginSettings(modelData);
              }
            }

            NIconButton {
              icon: "trash"
              tooltipText: I18n.tr("common.uninstall")
              baseSize: Style.baseWidgetSize * 0.7
              onClicked: {
                uninstallDialog.pluginToUninstall = modelData;
                uninstallDialog.open();
              }
            }

            NToggle {
              checked: modelData.enabled
              baseSize: Style.baseWidgetSize * 0.7
              onToggled: checked => {
                           if (checked) {
                             PluginService.enablePlugin(modelData.compositeKey);
                           } else {
                             PluginService.disablePlugin(modelData.compositeKey);
                           }
                         }
            }
          }

          // Description
          NText {
            visible: modelData.description
            text: modelData.description || ""
            font.pointSize: Style.fontSizeXS
            color: Color.mOnSurface
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          // Details row
          RowLayout {
            spacing: Style.marginS
            Layout.fillWidth: true

            NText {
              text: "v" + modelData.version
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: stripAuthorEmail(modelData.author)
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Item {
              Layout.fillWidth: true
            }
          }

          // Error indicator
          RowLayout {
            spacing: Style.marginS
            visible: PluginService.hasPluginError(modelData.compositeKey)

            NIcon {
              icon: "alert-triangle"
              pointSize: Style.fontSizeS
              color: Color.mError
            }

            NText {
              property var errorInfo: PluginService.getPluginError(modelData.compositeKey)
              text: errorInfo ? errorInfo.error : ""
              font.pointSize: Style.fontSizeXXS
              color: Color.mError
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              elide: Text.ElideRight
              maximumLineCount: 3
            }
          }
        }
      }
    }

    NLabel {
      visible: PluginRegistry.getAllInstalledPluginIds().length === 0
      label: I18n.tr("panels.plugins.installed-no-plugins-label")
      description: I18n.tr("panels.plugins.installed-no-plugins-description")
      Layout.fillWidth: true
    }
  }

  // Uninstall confirmation dialog
  Popup {
    id: uninstallDialog
    parent: Overlay.overlay
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 400 * Style.uiScaleRatio
    padding: Style.marginL

    property var pluginToUninstall: null

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    contentItem: ColumnLayout {
      width: parent.width
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("panels.plugins.uninstall-dialog-title")
        description: I18n.tr("panels.plugins.uninstall-dialog-description", {
                               "plugin": uninstallDialog.pluginToUninstall?.name || ""
                             })
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: uninstallDialog.close()
        }

        NButton {
          text: I18n.tr("common.uninstall")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: {
            if (uninstallDialog.pluginToUninstall) {
              root.uninstallPlugin(uninstallDialog.pluginToUninstall.compositeKey);
              uninstallDialog.close();
            }
          }
        }
      }
    }
  }

  // Plugin settings popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: true
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    BarService.widgetsRevision++;

    ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstalling", {
                                                                       "plugin": pluginName
                                                                     }));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-success", {
                                                                           "plugin": pluginName
                                                                         }));
      } else {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-error", {
                                                                          "error": error || "Unknown error"
                                                                        }));
      }
    });
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      root.installedPluginsRefreshCounter++;
    }
  }
}
