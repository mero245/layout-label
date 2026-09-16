import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

// The active xkb layout as a short clickable label. Which keyboard the seat is
// being typed on decides the label; a click switches that keyboard's layout.
// Labels come from KeyboardLayoutModel.js and can be overridden per bar entry
// with a "labels" object, so each layout gets its own spelling.
BarWidget {
  id: root
  moduleName: "mero.layout-label"

  // Injected by the bar from the widget entry.
  property var settings: ({})

  property string layoutFull: ""
  // The keyboard the last reading spoke for, which is the one a click switches,
  // and separately the one activelayout named as being typed on. A reading
  // confirms the first is really there, so the click has a keyboard to reach
  // from the first reading onwards rather than only after a switch, and stops
  // naming one that has been unplugged.
  property string keyboardName: ""
  property string typedKeyboardName: ""
  // Keyboards on the seat, buttons and virtual ones excluded, and whether the
  // last reading left that shape in doubt.
  property int keyboardCount: 0
  property bool keyboardUnresolved: false
  // Nothing to read or switch on the single-layout install most people run, so
  // the widget ships on the bar and stays out of the way until there are two.
  // An older Hyprland that doesn't report the list keeps showing the label.
  property bool multipleLayouts: true
  // Short language code per layout description ("English (US)": "en"), read from
  // xkb's own table rather than maintained by hand.
  property var layoutBriefs: ({})
  // Per-entry "labels" overrides, blank unless the bar entry carries them.
  readonly property var layoutLabels: root.settings && root.settings.labels ? root.settings.labels : ({})
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs, layoutLabels)
  // What this layout would show without a per-entry override, so the card can
  // say what it is editing on top of.
  readonly property string defaultLabelFor: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs, {})
  readonly property string currentOverride: layoutLabels && layoutFull && layoutLabels[layoutFull] !== undefined
    ? String(layoutLabels[layoutFull]) : ""

  // ---- Settings editing. Right-clicking the label opens a small editor that
  //      sets the per-layout label for the layout on screen; changes persist to
  //      shell.json the same way the built-in widgets do (updateEntryInline).
  property string draftLabel: ""

  function mergedSettings(changes) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var change in changes) entry[change] = changes[change]
    return entry
  }

  function commitSettings(changes) {
    var entry = root.mergedSettings(changes)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setLayoutLabel(value) {
    if (!root.layoutFull) return
    var labels = {}
    for (var key in root.layoutLabels) labels[key] = root.layoutLabels[key]
    var trimmed = String(value || "").trim()
    if (trimmed !== "") labels[root.layoutFull] = trimmed
    else delete labels[root.layoutFull]
    root.summarizeLabels(labels, trimmed)
    root.commitSettings({ labels: labels })
  }

  function clearLayoutLabel() {
    root.draftLabel = ""
    root.setLayoutLabel("")
  }

  function resetAllLabels() {
    root.draftLabel = ""
    root.commitSettings({ labels: {} })
  }

  function toggleSettings() {
    settingsCard.open = !settingsCard.open
  }

  function summarizeLabels(labels, active) {
    if (typeof labels !== "object" || labels === null) return
    var keys = Object.keys(labels)
    var summary = keys.length > 0 ? "Per-layout labels: " + keys.length + " set." : ""
    if (active !== undefined && active !== "") summary += " Label for \"" + root.layoutFull + "\" = \"" + active + "\"."
    root.editNote = summary
  }

  property string editNote: ""

  // A query already in flight was started before this event, so it may read the
  // layout the switch replaced. Remember the request and re-run once it lands
  // rather than dropping it; nothing else would correct the label afterwards.
  property bool refreshPending: false

  function refresh() {
    if (queryProc.running) {
      refreshPending = true
      return
    }

    refreshPending = false
    queryProc.running = true
  }

  // Keyboards someone can actually type on, which is not everything Hyprland
  // calls a keyboard.
  function typedKeyboards(keyboards) {
    return keyboards.filter(k => KeyboardLayoutModel.isTypedKeyboard(k.name))
  }

  // The main flag names no keyboard for long: fcitx5 takes it with the virtual
  // keyboard it binds to inject, which leaves no typed keyboard holding it and
  // nothing to read at all, and once that unbinds it lands on whichever device
  // Hyprland saw last, a power button included. Go by layout progress instead,
  // and by the keyboard activelayout named.
  function selectKeyboard(typed) {
    return KeyboardLayoutModel.selectKeyboard(typed, root.typedKeyboardName)
  }

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run rather than sent over the dispatch socket. It switches the keyboard
  // the last reading spoke for, so a click always advances the device the label
  // is describing. Switching the seat together would reach the typed keyboard
  // without having to name it, but it would also carry the buttons along, as
  // described in the model.
  function cycleLayout() {
    if (!root.keyboardName || !root.bar) return
    root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
    refreshTimer.restart()
  }

  Component.onCompleted: {
    briefsProc.running = true
    refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // The event names the keyboard that switched ahead of the layout it moved
      // to, and that is the keyboard being typed on whatever holds the main flag.
      if (name === "activelayout") {
        const named = KeyboardLayoutModel.eventKeyboardName(event)
        if (named) root.typedKeyboardName = named
      }

      // A reload that adds a layout to kb_layout decides whether the widget
      // shows at all, and leaves every keyboard on the layout it was already
      // reading, so it raises no activelayout to notice it by.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "devices"]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }

      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let listed
        try {
          listed = JSON.parse(text || "{}").keyboards
        } catch (e) {
          return
        }

        // A query the watchdog killed reports nothing at all, and an empty
        // string parses into the same shape a seat with no keyboards would.
        // Tell them apart by the list itself, so only a reading that reached
        // hyprctl gets to speak for the seat.
        if (!Array.isArray(listed)) return

        const typed = root.typedKeyboards(listed)
        const kb = root.selectKeyboard(typed)
        if (!kb || !kb.active_keymap) {
          // Either the last keyboard has been unplugged, which the label has to
          // stop describing and the click has to stop naming, or keyboards are
          // there and none of them reports a keymap. Both leave the shape in
          // doubt, so keep asking rather than letting a count from before it
          // changed settle the poll.
          root.keyboardUnresolved = true
          if (typed.length === 0) {
            root.layoutFull = ""
            root.keyboardName = ""
          }
          return
        }

        root.keyboardUnresolved = false
        root.keyboardCount = typed.length
        root.keyboardName = String(kb.name || "")
        root.multipleLayouts = kb.layout === undefined || String(kb.layout).indexOf(",") !== -1
        root.layoutFull = kb.active_keymap
      }
    }
  }

  // The table only changes when xkb data is upgraded, so read it at startup and
  // leave it alone. The bar is built per monitor, so this runs once per widget.
  // The exotic rulesets cover layouts like trans (IPA) that ship in the same xkb
  // package and set just as well, so load them or those labels lose their code.
  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // A query that never returns would freeze the label until the shell restarts,
  // since a Process that is already running can't be re-run. Give up on one that
  // overstays so the next refresh gets through, and ask again: the reading it
  // never delivered may have been the only one due on a settled seat, and
  // nothing else would come back for it.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      queryProc.running = false
      refreshTimer.restart()
    }
  }

  // Which keyboard on a crowded seat the label is describing can change without
  // Hyprland announcing it, since a device arriving or leaving raises no event
  // of its own, and that can only be learned by asking. Poll while there is that
  // ambiguity, until a first reading lands so a query that failed at login still
  // recovers, and while a reading has left the seat's shape in doubt. The
  // one-keyboard install has none of those, and is left alone rather than
  // spawning hyprctl forever for an answer that cannot change.
  Timer {
    interval: 1000
    running: root.visible && (root.keyboardUnresolved || (root.keyboardCount === 0 && root.layoutFull === ""))
    repeat: true
    onTriggered: root.refresh()
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    bar: root.bar
    anchors.centerIn: parent
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull + (root.currentOverride !== "" ? " · " + root.currentOverride : "")
    onPressed: function(buttonPressed) {
      if (buttonPressed === Qt.RightButton) root.toggleSettings()
      else root.cycleLayout()
    }
  }

  // ---- Settings card, anchored to the label and opened by right-click above.
  PopupCard {
    id: settingsCard
    bar: root.bar
    anchorItem: button
    contentWidth: Style.space(340)
    contentHeight: settingsList.implicitHeight + settingsCard.verticalContentInset
    onOpenChanged: if (settingsCard.open) root.draftLabel = root.currentOverride

    ColumnLayout {
      id: settingsList
      width: settingsCard.contentWidth - settingsCard.padding * 2
        - Border.left(settingsCard.borderSpec) - Border.right(settingsCard.borderSpec)
      spacing: Style.spacing.controlGap

      RowLayout {
        Layout.fillWidth: true

        Text {
          text: "Layout label"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.5
        }

        Item { Layout.fillWidth: true }

        Button {
          text: "Reset labels"
          fontSize: Style.font.caption
          tooltipText: "Forget every per-layout label override"
          onClicked: root.resetAllLabels()
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        Text {
          Layout.minimumWidth: Style.space(108)
          text: "Layout"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.layoutFull
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
          horizontalAlignment: Text.AlignRight
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        Text {
          Layout.minimumWidth: Style.space(108)
          text: "Label"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        TextField {
          Layout.fillWidth: true
          text: root.draftLabel
          horizontalAlignment: Text.AlignHCenter
          placeholderText: root.defaultLabelFor
          onTextEdited: root.draftLabel = text
          onAccepted: root.setLayoutLabel(root.draftLabel)
        }

        Button {
          text: "Apply"
          fontSize: Style.font.caption
          onClicked: root.setLayoutLabel(root.draftLabel)
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.editNote
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        visible: root.editNote !== ""
      }

      RowLayout {
        Layout.fillWidth: true

        Text {
          Layout.fillWidth: true
          text: "Left-click cycles layouts · right-click opens these settings"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          opacity: 0.6
          elide: Text.ElideRight
        }

        Button {
          text: "Clear"
          fontSize: Style.font.caption
          visible: root.draftLabel !== "" || root.currentOverride !== ""
          tooltipText: "Remove this layout's override"
          onClicked: root.clearLayoutLabel()
        }
      }
    }
  }
}