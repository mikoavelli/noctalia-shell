pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../../Helpers/sha256.js" as Checksum
import qs.Commons
import qs.Services.Power
import qs.Services.UI

Singleton {
  id: root

  // Configuration
  property int maxVisible: 5

  // State
  property real lastSeenTs: 0
  // Volatile property that doesn't persist to settings (similar to noctaliaPerformanceMode)
  property bool doNotDisturb: false

  // Models
  property ListModel activeList: ListModel {}

  // Internal state
  property var activeNotifications: ({}) // Maps internal ID to {notification, watcher, metadata}
  property var quickshellIdToInternalId: ({})

  // Rate limiting for notification sounds (minimum 100ms between sounds)
  property var lastSoundTime: 0
  readonly property int minSoundInterval: 100

  // Notification server
  property var notificationServerLoader: null

  Component {
    id: notificationServerComponent
    NotificationServer {
      keepOnReload: false
      imageSupported: true
      actionsSupported: true
      onNotification: notification => handleNotification(notification)
    }
  }

  Component {
    id: notificationWatcherComponent
    Connections {
      property var targetNotification
      property var targetDataId
      target: targetNotification

      function onSummaryChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onBodyChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onAppNameChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onUrgencyChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onAppIconChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onImageChanged() {
        updateNotificationFromObject(targetDataId);
      }
      function onActionsChanged() {
        updateNotificationFromObject(targetDataId);
      }
    }
  }

  function updateNotificationServer() {
    if (notificationServerLoader) {
      notificationServerLoader.destroy();
      notificationServerLoader = null;
    }

    if (Settings.isLoaded && Settings.data.notifications.enabled !== false) {
      notificationServerLoader = notificationServerComponent.createObject(root);
    }
  }

  Component.onCompleted: {
    if (Settings.isLoaded) {
      updateNotificationServer();
    }

    // Load state from ShellState
    Qt.callLater(() => {
                   if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
                     loadState();
                   }
                 });
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadState();
      }
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      updateNotificationServer();
    }
    function onSettingsSaved() {
      updateNotificationServer();
    }
  }

  // Helper function to generate content-based ID for deduplication
  function getContentId(summary, body, appName) {
    return Checksum.sha256(JSON.stringify({
                                            "summary": summary || "",
                                            "body": body || "",
                                            "app": appName || ""
                                          }));
  }

  // Main handler
  function handleNotification(notification) {
    const quickshellId = notification.id;
    const data = createData(notification);

    if (root.doNotDisturb || PowerProfileService.noctaliaPerformanceMode)
      return;

    // Check if this is a replacement notification
    const existingInternalId = quickshellIdToInternalId[quickshellId];
    if (existingInternalId && activeNotifications[existingInternalId]) {
      updateExistingNotification(existingInternalId, notification, data);
      return;
    }

    // Check for duplicate content
    const duplicateId = findDuplicateNotification(data);
    if (duplicateId) {
      removeNotification(duplicateId);
    }

    // Add new notification
    addNewNotification(quickshellId, notification, data);
  }

  function updateExistingNotification(internalId, notification, data) {
    const index = findNotificationIndex(internalId);
    if (index < 0)
      return;
    const existing = activeList.get(index);
    const oldTimestamp = existing.timestamp;
    const oldProgress = existing.progress;

    // Update properties (keeping original timestamp and progress)
    activeList.setProperty(index, "summary", data.summary);
    activeList.setProperty(index, "body", data.body);
    activeList.setProperty(index, "appName", data.appName);
    activeList.setProperty(index, "urgency", data.urgency);
    activeList.setProperty(index, "expireTimeout", data.expireTimeout);
    activeList.setProperty(index, "originalImage", data.originalImage);
    activeList.setProperty(index, "cachedImage", data.cachedImage);
    activeList.setProperty(index, "actionsJson", data.actionsJson);
    activeList.setProperty(index, "timestamp", oldTimestamp);
    activeList.setProperty(index, "progress", oldProgress);

    // Update stored notification object
    const notifData = activeNotifications[internalId];
    notifData.notification = notification;

    // Deep copy actions to preserve them even if QML object clears list
    var safeActions = [];
    if (notification.actions) {
      for (var i = 0; i < notification.actions.length; i++) {
        safeActions.push({
                           "identifier": notification.actions[i].identifier,
                           "actionObject": notification.actions[i]
                         });
      }
    }
    notifData.cachedActions = safeActions;
    notifData.metadata.originalId = data.originalId;

    notification.tracked = true;

    function onClosed() {
      userDismissNotification(internalId);
    }
    notification.closed.connect(onClosed);
    notifData.onClosed = onClosed;

    // Update metadata
    notifData.metadata.urgency = data.urgency;
    notifData.metadata.duration = calculateDuration(data);
  }

  function addNewNotification(quickshellId, notification, data) {
    // Map IDs
    quickshellIdToInternalId[quickshellId] = data.id;

    // Create watcher
    const watcher = notificationWatcherComponent.createObject(root, {
                                                                "targetNotification": notification,
                                                                "targetDataId": data.id
                                                              });

    // Deep copy actions
    var safeActions = [];
    if (notification.actions) {
      for (var i = 0; i < notification.actions.length; i++) {
        safeActions.push({
                           "identifier": notification.actions[i].identifier,
                           "actionObject": notification.actions[i]
                         });
      }
    }

    // Store notification data
    activeNotifications[data.id] = {
      "notification": notification,
      "watcher": watcher,
      "cachedActions": safeActions // Cache actions
                       ,
      "metadata": {
        "originalId": data.originalId // Store original ID
                      ,
        "timestamp": data.timestamp.getTime(),
        "duration": calculateDuration(data),
        "urgency": data.urgency,
        "paused": false,
        "pauseTime": 0
      }
    };

    notification.tracked = true;

    function onClosed() {
      userDismissNotification(data.id);
    }
    notification.closed.connect(onClosed);
    activeNotifications[data.id].onClosed = onClosed;

    // Add to list
    activeList.insert(0, data);

    // Remove overflow
    while (activeList.count > maxVisible) {
      const last = activeList.get(activeList.count - 1);
      activeNotifications[last.id]?.notification?.dismiss();
      removeNotification(last.id);
    }
  }

  function findDuplicateNotification(data) {
    const contentId = getContentId(data.summary, data.body, data.appName);

    for (var i = 0; i < activeList.count; i++) {
      const existing = activeList.get(i);
      const existingContentId = getContentId(existing.summary, existing.body, existing.appName);
      if (existingContentId === contentId) {
        return existing.id;
      }
    }
    return null;
  }

  function calculateDuration(data) {
    const durations = [Settings.data.notifications?.lowUrgencyDuration * 1000 || 3000, Settings.data.notifications?.normalUrgencyDuration * 1000 || 8000, Settings.data.notifications?.criticalUrgencyDuration * 1000 || 15000];

    if (Settings.data.notifications?.respectExpireTimeout) {
      if (data.expireTimeout === 0)
        return -1; // Never expire
      if (data.expireTimeout > 0)
        return data.expireTimeout;
    }

    return durations[data.urgency];
  }

  function createData(n) {
    const time = new Date();
    const id = Checksum.sha256(JSON.stringify({
                                                "summary": n.summary,
                                                "body": n.body,
                                                "app": n.appName,
                                                "time": time.getTime()
                                              }));

    const image = n.image || getIcon(n.appIcon);
    const imageId = generateImageId(n, image);
    queueImage(image, n.appName || "", n.summary || "", id);

    return {
      "id": id,
      "summary": processNotificationText(n.summary || ""),
      "body": processNotificationText(n.body || ""),
      "appName": getAppName(n.appName || n.desktopEntry || ""),
      "urgency": n.urgency < 0 || n.urgency > 2 ? 1 : n.urgency,
      "expireTimeout": n.expireTimeout,
      "timestamp": time,
      "progress": 1.0,
      "originalImage": image,
      "cachedImage": image  // Start with original, update when cached
                     ,
      "originalId": n.originalId || n.id || 0 // Ensure originalId is passed through
                    ,
      "actionsJson": JSON.stringify((n.actions || []).map(a => ({
                                                                  "text": (a.text || "").trim() || "Action",
                                                                  "identifier": a.identifier || ""
                                                                })))
    };
  }

  function findNotificationIndex(internalId) {
    for (var i = 0; i < activeList.count; i++) {
      if (activeList.get(i).id === internalId) {
        return i;
      }
    }
    return -1;
  }

  function updateNotificationFromObject(internalId) {
    const notifData = activeNotifications[internalId];
    if (!notifData)
      return;
    const index = findNotificationIndex(internalId);
    if (index < 0)
      return;
    const data = createData(notifData.notification);
    const existing = activeList.get(index);

    // Update properties (keeping timestamp and progress)
    activeList.setProperty(index, "summary", data.summary);
    activeList.setProperty(index, "body", data.body);
    activeList.setProperty(index, "appName", data.appName);
    activeList.setProperty(index, "urgency", data.urgency);
    activeList.setProperty(index, "expireTimeout", data.expireTimeout);
    activeList.setProperty(index, "originalImage", data.originalImage);
    activeList.setProperty(index, "cachedImage", data.cachedImage);
    activeList.setProperty(index, "actionsJson", data.actionsJson);

    // Update metadata
    notifData.metadata.urgency = data.urgency;
    notifData.metadata.duration = calculateDuration(data);
  }

  function removeNotification(id) {
    const index = findNotificationIndex(id);
    if (index >= 0) {
      activeList.remove(index);
    }
    cleanupNotification(id);
  }

  function cleanupNotification(id) {
    const notifData = activeNotifications[id];
    if (notifData) {
      notifData.watcher?.destroy();
      delete activeNotifications[id];
    }

    // Clean up quickshell ID mapping
    for (const qsId in quickshellIdToInternalId) {
      if (quickshellIdToInternalId[qsId] === id) {
        delete quickshellIdToInternalId[qsId];
        break;
      }
    }
  }

  // Progress updates
  Timer {
    interval: 50
    repeat: true
    running: activeList.count > 0
    onTriggered: updateAllProgress()
  }

  function updateAllProgress() {
    const now = Date.now();
    const toRemove = [];

    for (var i = 0; i < activeList.count; i++) {
      const notif = activeList.get(i);
      const notifData = activeNotifications[notif.id];
      if (!notifData)
        continue;
      const meta = notifData.metadata;
      if (meta.duration === -1 || meta.paused)
        continue;
      const elapsed = now - meta.timestamp;
      const progress = Math.max(1.0 - (elapsed / meta.duration), 0.0);

      if (progress <= 0) {
        toRemove.push(notif.id);
      } else if (Math.abs(notif.progress - progress) > 0.005) {
        activeList.setProperty(i, "progress", progress);
      }
    }

    if (toRemove.length > 0) {
      animateAndRemove(toRemove[0]);
    }
  }

  // Image handling
  function queueImage(path, appName, summary, notificationId) {
    if (!path || !path.startsWith("image://") || !notificationId)
      return;

    ImageCacheService.getNotificationIcon(path, appName, summary, function (cachedPath, success) {
      if (success && cachedPath) {
        updateImagePath(notificationId, "file://" + cachedPath);
      }
    });
  }

  function updateImagePath(notificationId, path) {
    updateModel(activeList, notificationId, "cachedImage", path);
  }

  function updateModel(model, notificationId, prop, value) {
    for (var i = 0; i < model.count; i++) {
      if (model.get(i).id === notificationId) {
        model.setProperty(i, prop, value);
        break;
      }
    }
  }

  function loadState() {
    try {
      const notifState = ShellState.getNotificationsState();
      root.lastSeenTs = notifState.lastSeenTs || 0;

      Logger.d("Notifications", "Loaded state from ShellState");
    } catch (e) {
      Logger.e("Notifications", "Load state failed:", e);
    }
  }

  function saveState() {
    try {
      ShellState.setNotificationsState({
                                         lastSeenTs: root.lastSeenTs
                                       });
      Logger.d("Notifications", "Saved state to ShellState");
    } catch (e) {
      Logger.e("Notifications", "Save state failed:", e);
    }
  }

  function updateLastSeenTs() {
    root.lastSeenTs = Time.timestamp * 1000;
    saveState();
  }

  // Utility functions
  function getAppName(name) {
    if (!name || name.trim() === "")
      return "Unknown";
    name = name.trim();

    if (name.includes(".") && (name.startsWith("com.") || name.startsWith("org.") || name.startsWith("io.") || name.startsWith("net."))) {
      const parts = name.split(".");
      let appPart = parts[parts.length - 1];

      if (!appPart || appPart === "app" || appPart === "desktop") {
        appPart = parts[parts.length - 2] || parts[0];
      }

      if (appPart)
        name = appPart;
    }

    if (name.includes(".")) {
      const parts = name.split(".");
      let displayName = parts[parts.length - 1];

      if (!displayName || /^\d+$/.test(displayName)) {
        displayName = parts[parts.length - 2] || parts[0];
      }

      if (displayName) {
        displayName = displayName.charAt(0).toUpperCase() + displayName.slice(1);
        displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
        displayName = displayName.replace(/app$/i, '').trim();
        displayName = displayName.replace(/desktop$/i, '').trim();
        displayName = displayName.replace(/flatpak$/i, '').trim();

        if (!displayName) {
          displayName = parts[parts.length - 1].charAt(0).toUpperCase() + parts[parts.length - 1].slice(1);
        }
      }

      return displayName || name;
    }

    let displayName = name.charAt(0).toUpperCase() + name.slice(1);
    displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
    displayName = displayName.replace(/app$/i, '').trim();
    displayName = displayName.replace(/desktop$/i, '').trim();

    return displayName || name;
  }

  function getIcon(icon) {
    if (!icon)
      return "";
    if (icon.startsWith("/") || icon.startsWith("file://"))
      return icon;
    return ThemeIcons.iconFromName(icon);
  }

  function escapeHtml(text) {
    if (!text)
      return "";
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function processNotificationText(text) {
    if (!text)
      return "";

    // Split by tags to process segments separately
    const parts = text.split(/(<[^>]+>)/);
    let result = "";
    const allowedTags = ["b", "i", "u", "a", "br"];

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (part.startsWith("<") && part.endsWith(">")) {
        const content = part.substring(1, part.length - 1);
        const firstWord = content.split(/[\s/]/).filter(s => s.length > 0)[0]?.toLowerCase();

        if (allowedTags.includes(firstWord)) {
          // Preserve valid HTML tag
          result += part;
        } else {
          // Unknown tag: drop tag without leaking attributes
          result += "";
        }
      } else {
        // Normal text: escape everything
        result += escapeHtml(part);
      }
    }
    return result;
  }

  function generateImageId(notification, image) {
    if (image && image.startsWith("image://")) {
      if (image.startsWith("image://qsimage/")) {
        const key = (notification.appName || "") + "|" + (notification.summary || "");
        return Checksum.sha256(key);
      }
      return Checksum.sha256(image);
    }
    return "";
  }

  function pauseTimeout(id) {
    const notifData = activeNotifications[id];
    if (notifData && !notifData.metadata.paused) {
      notifData.metadata.paused = true;
      notifData.metadata.pauseTime = Date.now();
    }
  }

  function resumeTimeout(id) {
    const notifData = activeNotifications[id];
    if (notifData && notifData.metadata.paused) {
      notifData.metadata.timestamp += Date.now() - notifData.metadata.pauseTime;
      notifData.metadata.paused = false;
    }
  }

  // Public API
  function dismissActiveNotification(id) {
    userDismissNotification(id);
  }

  function userDismissNotification(id) {
    removeNotification(id);
  }

  function invokeAction(id, actionId) {
    // 1. Try invoking via live object
    let invoked = false;
    const notifData = activeNotifications[id];

    if (!notifData) {
      // No data
    } else if (!notifData.notification) {
      // No notification object
    } else {
      // Use cached actions if live actions are empty (which happens if app closed notification)
      const actionsToUse = (notifData.notification.actions && notifData.notification.actions.length > 0) ? notifData.notification.actions : (notifData.cachedActions || []);

      if (actionsToUse && actionsToUse.length > 0) {
        for (const item of actionsToUse) {
          const id = item.identifier; // Works for both raw object and wrapper (if properties match)
          const actionObj = item.actionObject ? item.actionObject : item; // Unwrap if wrapper

          if (id === actionId) {
            if (actionObj.invoke) {
              try {
                actionObj.invoke();
                invoked = true;
              } catch (e) {
                if (manualInvoke(notifData.metadata.originalId, id)) {
                  invoked = true;
                }
              }
            } else {
              if (manualInvoke(notifData.metadata.originalId, id)) {
                invoked = true;
              }
            }
          }
        }
      }
    }

    if (!invoked) {
      return false;
    }

    updateModel(activeList, id, "actionsJson", "[]");

    return true;
  }

  function manualInvoke(originalId, actionId) {
    if (!originalId) {
      return false;
    }

    try {
      // Construct the signal emission using dbus-send
      // dbus-send --session --type=signal /org/freedesktop/Notifications org.freedesktop.Notifications.ActionInvoked uint32:ID string:"KEY"
      const args = ["dbus-send", "--session", "--type=signal", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActionInvoked", "uint32:" + originalId, "string:" + actionId];

      Quickshell.execDetached(args);
      return true;
    } catch (e) {
      Logger.e("NotificationService", "Manual invoke failed: " + e);
      return false;
    }
  }

  // Signals
  signal animateAndRemove(string notificationId)

  onDoNotDisturbChanged: {
    ToastService.showNotice(doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled") : I18n.tr("toast.do-not-disturb.disabled"), doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled-desc") : I18n.tr("toast.do-not-disturb.disabled-desc"), doNotDisturb ? "bell-off" : "bell");
  }
}
