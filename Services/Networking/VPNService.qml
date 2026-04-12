pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property var connections: ({
                               "windscribe": {
                                 "uuid": "windscribe",
                                 "name": "Windscribe",
                                 "active": false
                               }
                             })

  property bool refreshing: false
  property bool connecting: false
  property bool disconnecting: false
  property string connectingUuid: ""
  property string lastError: ""
  property bool refreshPending: false

  readonly property var activeConnections: {
    const conn = connections["windscribe"];
    return (conn && conn.active) ? [conn] : [];
  }

  readonly property var inactiveConnections: {
    const conn = connections["windscribe"];
    return (conn && !conn.active) ? [conn] : [];
  }

  readonly property bool hasActiveConnection: activeConnections.length > 0

  Timer {
    id: refreshTimer
    interval: 3000
    running: true
    repeat: true
    onTriggered: refresh()
  }

  Timer {
    id: delayedRefreshTimer
    interval: 1000
    repeat: false
    onTriggered: refresh()
  }

  Component.onCompleted: {
    Logger.i("VPN", "Windscribe Service started");
    refresh();
  }

  function toggle() {
    if (connecting || disconnecting) {
      return;
    }

    if (hasActiveConnection) {
      disconnect("windscribe");
    } else {
      connect("windscribe");
    }
  }

  function refresh() {
    if (refreshing) {
      refreshPending = true;
      return;
    }
    refreshing = true;
    lastError = "";
    refreshProcess.running = true;
  }

  function connect(uuid) {
    if (connecting)
      return;
    connecting = true;
    connectingUuid = "windscribe";
    connectProcess.running = true;
  }

  function disconnect(uuid) {
    if (disconnecting)
      return;
    disconnecting = true;
    disconnectProcess.running = true;
  }

  function scheduleRefresh(interval) {
    delayedRefreshTimer.interval = interval;
    delayedRefreshTimer.restart();
  }

  Process {
    id: refreshProcess
    command: ["windscribe-cli", "status"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        const isConnected = text.includes("Connect state: Connected");

        let location = "Windscribe";
        if (isConnected) {
          const match = text.match(/Connect state: Connected: (.+)/);
          if (match && match[1])
          location = match[1];
        }

        connections = {
          "windscribe": {
            "uuid": "windscribe",
            "name": location,
            "active": isConnected
          }
        };

        refreshing = false;
        if (refreshPending) {
          refreshPending = false;
          scheduleRefresh(500);
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        refreshing = false;
      }
    }
  }

  Process {
    id: connectProcess
    command: ["windscribe-cli", "connect", "Seine", "protocol", "stealth", "ip", "rotate"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        connecting = false;
        connectingUuid = "";
        ToastService.showNotice("Windscribe", "VPN Connected", "shield-lock");
        scheduleRefresh(500);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.w("VPN", "Connect error: " + text);
          ToastService.showWarning("Windscribe", text.split("\n")[0]);
        }
        connecting = false;
        connectingUuid = "";
        scheduleRefresh(500);
      }
    }
  }

  Process {
    id: disconnectProcess
    command: ["windscribe-cli", "disconnect"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        disconnecting = false;
        ToastService.showNotice("Windscribe", "VPN Disconnected", "shield-off");
        scheduleRefresh(500);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        disconnecting = false;
        scheduleRefresh(500);
      }
    }
  }
}
