import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Gorelo pinwheel mark, rendered natively from the official SVG's eight
// pieces so it scales crisply into a bar slot. Monochrome by default (the
// piece opacities keep the pinwheel legible in one colour); `colorful` paints
// the brand palette instead.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool colorful: false
  property real dim: 1.0

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Source geometry: the mark occupies 0..113 × 0..128 in the SVG.
  readonly property real sourceWidth: 113
  readonly property real sourceHeight: 128
  readonly property real unit: iconSize / sourceHeight

  Shape {
    id: shape
    width: root.sourceWidth
    height: root.sourceHeight
    x: (root.iconSize - root.sourceWidth * root.unit) / 2
    y: 0
    transform: Scale { xScale: root.unit; yScale: root.unit }
    preferredRendererType: Shape.CurveRenderer
    opacity: root.dim

    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#E72525" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 1.0)
      PathSvg { path: "M32.6183 112.736L15.8549 64.3652L0 80.1914L32.6183 112.736Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#8AEFDD" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.55)
      PathSvg { path: "M49.1152 31.1879L80.0823 0.291016C82.3031 11.5276 98.0787 21.8865 103.479 29.3534C105.606 32.3028 105.642 35.5617 103.313 37.094C98.4464 35.6121 94.142 35.13 90.7461 36.2162C88.1721 37.0653 85.8288 38.058 84.9637 39.9212C84.019 41.9497 84.7184 46.3092 88.2371 45.4891C89.3689 45.2227 89.9312 42.8777 89.7294 41.6548C94.7477 38.5328 105.058 39.5973 105.851 54.071C105.909 57.5312 104.164 60.4879 99.3836 62.5883C91.3445 65.4371 84.6535 63.9479 78.5612 60.5527L49.1296 31.1879H49.1152Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#71D0BB" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.8)
      PathSvg { path: "M80.2163 0.296436L49.2812 31.1614H49.2956L73.161 54.9725C73.201 54.9741 73.2413 54.9757 73.2815 54.977C62.5423 44.2622 73.4056 13.8727 80.3014 0.520743C80.2849 0.444209 80.2689 0.367633 80.2536 0.291016L80.2163 0.296436Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#B5CE00" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 1.0)
      PathSvg { path: "M48.5391 31.7559L77.7036 92.3338L96.7526 111.34C92.4266 107.023 92.4266 99.9593 96.7526 95.6429C101.078 91.3268 108.159 91.3268 112.485 95.6429L112.918 96.0746L112.961 96.0315L48.5391 31.7559Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#6FBA2C" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.55)
      PathSvg { path: "M77.7177 92.3338L48.5529 31.7559L32.7773 47.4956L77.7177 92.3338Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#9A1C56" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.8)
      PathSvg { path: "M96.7041 112.26L35.9884 83.1616L16.9395 64.1556C21.2655 68.472 28.3457 68.472 32.6718 64.1556C36.9978 59.8395 36.9978 52.7753 32.6718 48.4592L32.2392 48.0275L32.2824 47.9844L96.7041 112.26Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#E5016F" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 1.0)
      PathSvg { path: "M35.9883 83.1641L96.7042 112.262L80.9286 128.002L35.9883 83.1641Z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: root.colorful ? "#F29100" : Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.55)
      PathSvg { path: "M15.8516 64.3654L32.6148 112.736L48.4699 96.9097L15.8516 64.3654Z" }
    }
  }
}
