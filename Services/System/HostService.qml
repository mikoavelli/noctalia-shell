pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // User info
  readonly property string username: (Quickshell.env("USER") || "")
  readonly property string envRealName: (Quickshell.env("NOCTALIA_REALNAME") || "")
  property string realName: ""

  // Machine info
  property string hostName: ""

  readonly property string displayName: {
    // Explicit override
    if (envRealName && envRealName.length > 0) {
      return envRealName;
    }

    // Name from getent
    if (realName && realName.length > 0) {
      return realName;
    }

    // Fallback: capitalized $USER
    if (username && username.length > 0) {
      return username.charAt(0).toUpperCase() + username.slice(1);
    }

    // Last resort: placeholder
    return "User";
  }

  function init() {
    Logger.i("HostService", "Service started");
  }

  // Resolve GECOS real name once on startup
  Process {
    id: realNameProcess
    command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const name = String(text || "").trim();
        if (name.length > 0) {
          root.realName = name;
          Logger.i("HostService", "resolved real name", name);
        }
      }
    }
    stderr: StdioCollector {}
  }

  // Read /etc/hostname
  FileView {
    id: hostNameView
    path: "/etc/hostname"
    onLoaded: {
      const name = text().trim();
      if (name) {
        root.hostName = name;
        Logger.i("HostService", "resolved hostname", name);
      }
    }
  }
}
