import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  // Helper functions to update arrays immutably
  function addMonitor(list, name) {
    const arr = (list || []).slice();
    if (!arr.includes(name))
      arr.push(name);
    return arr;
  }
  function removeMonitor(list, name) {
    return (list || []).filter(function (n) {
      return n !== name;
    });
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: false // this is too cramped on this tab to split evenly
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("common.appearance")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.duration")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
    NTabButton {
      text: I18n.tr("common.history")
      tabIndex: 2
      checked: subTabBar.currentIndex === 2
    }
    NTabButton {
      text: I18n.tr("common.toast")
      tabIndex: 3
      checked: subTabBar.currentIndex === 3
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    GeneralSubTab {
      addMonitor: root.addMonitor
      removeMonitor: root.removeMonitor
    }
    DurationSubTab {}
    HistorySubTab {}
    ToastSubTab {}
  }
}
