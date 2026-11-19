import QtQuick

// The bar icon: one thin vertical cell per provider,
// each with its own geometry so no state rests on color. A cell is
// {kind, left}: "level" fills from the bottom to `left` percent, "unknown" is
// the outline only, "spent" a slash, "fault" an exclamation mark.
Item {
  id: root

  property var cells: []
  property color ink: "white"

  readonly property real cellWidth: 6
  readonly property real cellHeight: 14
  readonly property real cellGap: 3
  readonly property real stroke: 1
  // clearance between the outline and what is drawn inside it
  readonly property real clearance: 0.75
  readonly property real radius: 1.5
  readonly property real fillRadius: 0.5
  // the share of the well the exclamation mark's bar takes; its dot is as
  // tall as the well is wide
  readonly property real barShare: 0.6
  readonly property real full: 100
  readonly property real inset: stroke + clearance
  readonly property real wellWidth: cellWidth - 2 * inset
  readonly property real wellHeight: cellHeight - 2 * inset
  readonly property real slashAngle: -Math.atan2(cellHeight, cellWidth) * 180 / Math.PI

  width: cells.length * cellWidth + Math.max(cells.length - 1, 0) * cellGap
  height: cellHeight

  Row {
    spacing: root.cellGap

    Repeater {
      model: root.cells

      Item {
        id: cell
        required property var modelData
        width: root.cellWidth
        height: root.cellHeight

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: root.stroke
          border.color: root.ink
          radius: root.radius
          antialiasing: true
        }

        // at least a stroke, so a nearly spent account is not outline-only
        Rectangle {
          visible: cell.modelData.kind === "level"
          x: root.inset
          width: root.wellWidth
          height: Math.max(root.stroke, root.wellHeight * cell.modelData.left / root.full)
          y: root.cellHeight - root.inset - height
          radius: root.fillRadius
          color: root.ink
          antialiasing: true
        }

        // corner to corner, bottom left to top right
        Rectangle {
          visible: cell.modelData.kind === "spent"
          width: Math.sqrt(root.cellWidth * root.cellWidth + root.cellHeight * root.cellHeight)
          height: root.stroke
          x: (root.cellWidth - width) / 2
          y: (root.cellHeight - height) / 2
          rotation: root.slashAngle
          color: root.ink
          antialiasing: true
        }

        Rectangle {
          visible: cell.modelData.kind === "fault"
          x: root.inset
          y: root.inset
          width: root.wellWidth
          height: root.wellHeight * root.barShare
          radius: root.fillRadius
          color: root.ink
          antialiasing: true
        }

        Rectangle {
          visible: cell.modelData.kind === "fault"
          x: root.inset
          y: root.cellHeight - root.inset - height
          width: root.wellWidth
          height: root.wellWidth
          radius: width / 2
          color: root.ink
          antialiasing: true
        }
      }
    }
  }
}
