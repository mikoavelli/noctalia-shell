pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

/*
Noctalia uses a restricted set of colors following Material Design 3 naming.

NOTE: All color names are prefixed with 'm' (e.g., mPrimary) to prevent QML from
misinterpreting them as signals (e.g., the 'onPrimary' property name).
*/
Singleton {
  id: root

  // Default colors: Catppuccin

  // --- Key Colors: These are the main accent colors that define app's style
  readonly property color mPrimary: "#cba6f7"
  readonly property color mOnPrimary: "#11111b"
  readonly property color mSecondary: "#fab387"
  readonly property color mOnSecondary: "#11111b"
  readonly property color mTertiary: "#94e2d5"
  readonly property color mOnTertiary: "#11111b"

  // --- Utility Colors: These colors serve specific, universal purposes like indicating errors
  readonly property color mError: "#f38ba8"
  readonly property color mOnError: "#11111b"

  // --- Surface and Variant Colors: These provide additional options for surfaces and their contents, creating visual hierarchy
  readonly property color mSurface: "#1e1e2e"
  readonly property color mOnSurface: "#cdd6f4"
  readonly property color mSurfaceVariant: "#313244"
  readonly property color mOnSurfaceVariant: "#a3b4eb"

  readonly property color mOutline: "#4c4f69"
  readonly property color mShadow: "#11111b"
  readonly property color mHover: "#94e2d5"
  readonly property color mOnHover: "#11111b"

  function resolveColorKey(key) {
    switch (key) {
    case "primary":
      return root.mPrimary;
    case "secondary":
      return root.mSecondary;
    case "tertiary":
      return root.mTertiary;
    case "error":
      return root.mError;
    default:
      return root.mOnSurface;
    }
  }

  function resolveOnColorKey(key) {
    switch (key) {
    case "primary":
      return root.mOnPrimary;
    case "secondary":
      return root.mOnSecondary;
    case "tertiary":
      return root.mOnTertiary;
    case "error":
      return root.mOnError;
    default:
      return root.mSurface;
    }
  }

  function resolveColorKeyOptional(key) {
    switch (key) {
    case "primary":
      return root.mPrimary;
    case "secondary":
      return root.mSecondary;
    case "tertiary":
      return root.mTertiary;
    case "error":
      return root.mError;
    default:
      return "transparent";
    }
  }

  readonly property var colorKeyModel: [
    {
      "key": "none",
      "name": I18n.tr("common.none")
    },
    {
      "key": "primary",
      "name": I18n.tr("common.primary")
    },
    {
      "key": "secondary",
      "name": I18n.tr("common.secondary")
    },
    {
      "key": "tertiary",
      "name": I18n.tr("common.tertiary")
    },
    {
      "key": "error",
      "name": I18n.tr("common.error")
    }
  ]
}
