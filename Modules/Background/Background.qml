import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI

Variants {
  id: backgroundVariants
  model: Quickshell.screens

  delegate: Loader {

    required property ShellScreen modelData

    active: modelData && Settings.data.wallpaper.enabled

    sourceComponent: PanelWindow {
      id: root

      property bool wallpaperReady: false
      visible: wallpaperReady

      // Used to debounce wallpaper changes
      property string futureWallpaper: ""
      // Track the original wallpaper path being set (before caching)
      property string transitioningToOriginalPath: ""

      // Solid color mode
      property bool isSolid: false
      property color currentSolidColor: Settings.data.wallpaper.solidColor

      Component.onCompleted: setWallpaperInitial()

      Component.onDestruction: {
        debounceTimer.stop();
        wallpaperImage.source = "";
      }

      Connections {
        target: Settings.data.wallpaper
        function onFillModeChanged() {
          wallpaperImage.fillMode = root.getQmlFillMode();
        }
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            requestPreprocessedWallpaper(path);
          }
        }
      }

      Connections {
        target: CompositorService
        function onDisplayScalesChanged() {
          if (!WallpaperService.isInitialized) {
            return;
          }

          const currentPath = WallpaperService.getWallpaper(modelData.name);
          if (!currentPath || WallpaperService.isSolidColorPath(currentPath)) {
            return;
          }

          requestPreprocessedWallpaper(currentPath);
        }
      }

      color: "transparent"
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-wallpaper-" + (screen?.name || "unknown")

      anchors {
        bottom: true
        top: true
        right: true
        left: true
      }

      Timer {
        id: debounceTimer
        interval: 333
        running: false
        repeat: false
        onTriggered: applyWallpaper()
      }

      // Fill color background (visible behind image in fit/center modes, or as solid color)
      Rectangle {
        anchors.fill: parent
        color: root.isSolid ? root.currentSolidColor : Settings.data.wallpaper.fillColor
      }

      Image {
        id: wallpaperImage

        anchors.fill: parent
        source: ""
        smooth: true
        mipmap: false
        visible: !root.isSolid
        cache: true
        asynchronous: true
        fillMode: root.getQmlFillMode()

        onStatusChanged: {
          if (status === Image.Error) {
            Logger.w("Wallpaper failed to load:", source);
          } else if (status === Image.Ready && !wallpaperReady) {
            wallpaperReady = true;
          }
        }
      }

      // Map fill mode setting to QML Image.fillMode enum
      function getQmlFillMode() {
        var uniform = WallpaperService.getFillModeUniform();
        switch (uniform) {
        case 0.0:
          return Image.Pad; // center
        case 1.0:
          return Image.PreserveAspectCrop; // crop
        case 2.0:
          return Image.PreserveAspectFit; // fit
        case 3.0:
          return Image.Stretch; // stretch
        case 4.0:
          return Image.Tile; // repeat
        default:
          return Image.PreserveAspectCrop;
        }
      }

      // Normalize a path (string or QUrl) to a plain string for comparison.
      // QML Image.source is a url type; comparing url === string can return
      // false even for identical paths. This converts both sides to strings.
      function _pathStr(p) {
        var s = p.toString();
        // QUrl.toString() may add a file:// prefix for local paths
        if (s.startsWith("file://")) {
          return s.substring(7);
        }
        return s;
      }

      // ------------------------------------------------------
      function setWallpaperInitial() {
        // On startup, defer assigning wallpaper until the services are ready
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }
        if (!ImageCacheService || !ImageCacheService.initialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }

        // Check if we're in solid color mode
        if (Settings.data.wallpaper.useSolidColor) {
          var solidPath = WallpaperService.createSolidColorPath(Settings.data.wallpaper.solidColor.toString());
          futureWallpaper = solidPath;
          applyWallpaper();
          WallpaperService.wallpaperProcessingComplete(modelData.name, solidPath, "");
          return;
        }

        const wallpaperPath = WallpaperService.getWallpaper(modelData.name);

        // Check if the path is a solid color
        if (WallpaperService.isSolidColorPath(wallpaperPath)) {
          futureWallpaper = wallpaperPath;
          applyWallpaper();
          WallpaperService.wallpaperProcessingComplete(modelData.name, wallpaperPath, "");
          return;
        }

        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const targetWidth = Math.round(modelData.width * compositorScale);
        const targetHeight = Math.round(modelData.height * compositorScale);

        ImageCacheService.getLarge(wallpaperPath, targetWidth, targetHeight, function (cachedPath, success) {
          if (success) {
            futureWallpaper = cachedPath;
          } else {
            // Fallback to original
            futureWallpaper = wallpaperPath;
          }
          applyWallpaper();
          WallpaperService.wallpaperProcessingComplete(modelData.name, wallpaperPath, success ? cachedPath : "");
        });
      }

      // ------------------------------------------------------
      function requestPreprocessedWallpaper(originalPath) {
        transitioningToOriginalPath = originalPath;

        // Handle solid color paths - no preprocessing needed
        if (WallpaperService.isSolidColorPath(originalPath)) {
          futureWallpaper = originalPath;
          debounceTimer.restart();
          WallpaperService.wallpaperProcessingComplete(modelData.name, originalPath, "");
          return;
        }

        const compositorScale = CompositorService.getDisplayScale(modelData.name);
        const targetWidth = Math.round(modelData.width * compositorScale);
        const targetHeight = Math.round(modelData.height * compositorScale);

        ImageCacheService.getLarge(originalPath, targetWidth, targetHeight, function (cachedPath, success) {
          // Ignore stale callback if we've moved on to a different wallpaper
          if (originalPath !== transitioningToOriginalPath) {
            return;
          }
          if (success) {
            futureWallpaper = cachedPath;
          } else {
            futureWallpaper = originalPath;
          }

          // Skip if the resolved path matches what's already displayed
          if (_pathStr(futureWallpaper) === _pathStr(wallpaperImage.source)) {
            transitioningToOriginalPath = "";
            WallpaperService.wallpaperProcessingComplete(modelData.name, originalPath, success ? cachedPath : "");
            return;
          }

          debounceTimer.restart();
          // Pass cached path for blur optimization (already resized)
          WallpaperService.wallpaperProcessingComplete(modelData.name, originalPath, success ? cachedPath : "");
        });
      }

      // ------------------------------------------------------
      function applyWallpaper() {
        transitioningToOriginalPath = "";

        var isSolidSource = WallpaperService.isSolidColorPath(futureWallpaper);
        isSolid = isSolidSource;

        if (isSolidSource) {
          var colorStr = WallpaperService.getSolidColor(futureWallpaper);
          currentSolidColor = colorStr;
          wallpaperImage.source = "";
          if (!wallpaperReady) {
            wallpaperReady = true;
          }
          return;
        }

        wallpaperImage.source = futureWallpaper;
      }
    }
  }
}
