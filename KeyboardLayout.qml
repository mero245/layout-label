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
// with a "labels" object, so each layout gets its own spelling. Right-clicking
// opens a settings card whose picker chooses which installed layout to name, so
// a layout can be edited without switching the keyboard to it.
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
  // The same table read as records, so the settings picker can name each
  // configured layout by the description hyprctl reports for it.
  property var layoutCatalog: []
  // The selected keyboard's parallel layout/variant lists from hyprctl. The
  // picker zips them against the catalog to list what is installed.
  property string keyboardLayouts: ""
  property string keyboardVariants: ""
  // The active layout index from hyprctl, used to map the active_keymap to
  // the xkbcli description for the same layout+variant pair.
  property int activeLayoutIndex: 0
  // The layout the settings card is editing. Pinned when the card opens so a
  // keyboard switch while it is up does not retarget the edit, and chosen from
  // the picker so any installed layout can be named without switching to it.
  property string editingLayout: ""
  // Every layout the typing keyboard is set to, for the card's picker.
  readonly property var layoutChoices: KeyboardLayoutModel.configuredLayouts(layoutCatalog, keyboardLayouts, keyboardVariants)
  // Per-entry "labels" overrides, blank unless the bar entry carries them.
  readonly property var layoutLabels: root.settings && root.settings.labels ? root.settings.labels : ({})
  // Look up the override by the xkbcli description for the active layout, not
  // by hyprctl's active_keymap which can disagree on the human-readable name
  // (e.g. hyprctl says "Arabic (No Tashkeel)" but xkbcli says "Arabic").
  readonly property string activeDescription: descriptionForActiveLayout()
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(activeDescription, layoutBriefs, layoutLabels)
  // What the edited layout would show without a per-entry override, so the card
  // can say what it is editing on top of.
  readonly property string defaultLabelFor: KeyboardLayoutModel.shortLabel(editingLayout, layoutBriefs, {})
  readonly property string currentOverride: labelOverride(editingLayout, layoutFull)
  // The override for the layout the bar is actually showing, so the tooltip
  // keeps describing the label on screen rather than whatever the card last
  // edited.
  readonly property string activeOverride: labelOverride(activeDescription, layoutFull)

  // ---- Settings editing. Right-clicking the label opens a small editor that
  //      sets the per-layout label for the layout the picker names; changes
  //      persist to shell.json the same way the built-in widgets do
  //      (updateEntryInline).
  property string draftLabel: ""

  // Map the active hyprctl layout (by index) to the xkbcli description for the
  // same layout+variant pair. hyprctl and xkbcli can disagree on the human
  // description for the same XKB layout (e.g. hyprctl says "Arabic (No
  // Tashkeel)" while xkbcli says "Arabic"), so overrides must be keyed by the
  // xkbcli description to match what the picker stores and what shortLabel can
  // find. Falls back to layoutFull when the catalog hasn't loaded yet or the
  // index is out of range.
  function descriptionForActiveLayout() {
    var layouts = String(root.keyboardLayouts || "").split(",")
    var variants = String(root.keyboardVariants || "").split(",")
    var idx = root.activeLayoutIndex
    if (idx < 0 || idx >= layouts.length) return root.layoutFull
    var layout = (layouts[idx] || "").trim()
    var variant = (variants[idx] || "").trim()
    if (!layout) return root.layoutFull
    var match = (root.layoutCatalog || []).find(function (e) {
      return e.layout === layout && String(e.variant || "") === variant
    })
    return (match && match.description) ? match.description : root.layoutFull
  }

  // Look up an override by the xkbcli description first, then by hyprctl's
  // keymap name as a fallback.  This handles custom layouts whose xkbcli
  // catalog entry is missing (so the picker and the active-description
  // lookup use different strings) as well as any overrides that were saved
  // before the xkbcli-based keying was introduced.
  function labelOverride(description, keymap) {
    var labels = root.layoutLabels || {}
    if (description && labels[description] !== undefined) return String(labels[description])
    if (keymap && labels[keymap] !== undefined) return String(labels[keymap])
    return ""
  }

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
    if (!root.editingLayout) return
    var labels = {}
    for (var key in root.layoutLabels) labels[key] = root.layoutLabels[key]
    var trimmed = String(value || "").trim()
    if (trimmed !== "") labels[root.editingLayout] = trimmed
    else delete labels[root.editingLayout]
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

  // Open the card on the layout the label is describing right now, then let the
  // picker move to another. The seeding runs in the panel's onOpenChanged, which
  // is the moment the content is guaranteed to exist.
  function openSettings() {
    settingsCard.open = true
  }

  function toggleSettings() {
    if (settingsCard.open) settingsCard.open = false
    else root.openSettings()
  }

  function summarizeLabels(labels, active) {
    if (typeof labels !== "object" || labels === null) return
    var keys = Object.keys(labels)
    var summary = keys.length > 0 ? "Per-layout labels: " + keys.length + " set." : ""
    if (active !== undefined && active !== "") summary += " Label for \"" + root.editingLayout + "\" = \"" + active + "\"."
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
        root.keyboardLayouts = String(kb.layout || "")
        root.keyboardVariants = String(kb.variant || "")
        root.activeLayoutIndex = kb.active_layout_index || 0
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
      onStreamFinished: {
        var listing = text || ""
        root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(listing)
        root.layoutCatalog = KeyboardLayoutModel.layoutEntries(listing)
      }
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
    tooltipText: root.layoutFull + (root.activeOverride !== "" ? " · " + root.activeOverride : "")
    onPressed: function(buttonPressed) {
      if (buttonPressed === Qt.RightButton) root.toggleSettings()
      else root.cycleLayout()
    }
  }

  // ---- Settings card, anchored to the label and opened by right-click above.
  //      Built on KeyboardPanel rather than PopupCard: its layer-shell surface
  //      primes keyboard focus, which is what lets the label field be typed in,
  //      where an xdg-popup only gets keys after a click routes focus through
  //      the bar. The field is the focus target, so it is ready on open.
  KeyboardPanel {
    id: settingsCard
    bar: root.bar
    anchorItem: button
    focusTarget: labelField
    contentWidth: Style.space(340)
    contentHeight: settingsList.implicitHeight + settingsCard.verticalContentInset
    onOpenChanged: {
      if (!settingsCard.open) return
      root.editingLayout = root.activeDescription
      root.draftLabel = root.currentOverride
      layoutPicker.value = root.editingLayout
    }

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

        Dropdown {
          id: layoutPicker
          Layout.fillWidth: true
          label: ""
          showLabel: false
          options: root.layoutChoices.length > 0
            ? root.layoutChoices
            : [{ value: root.editingLayout, label: root.editingLayout }]
          value: root.editingLayout
          fontFamily: Style.font.family
          onChanged: function(value) {
            root.editingLayout = value
            root.draftLabel = root.currentOverride
          }
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
          id: labelField
          Layout.fillWidth: true
          text: root.draftLabel
          horizontalAlignment: Text.AlignHCenter
          placeholderText: root.defaultLabelFor
          onTextEdited: root.draftLabel = text
          onAccepted: root.setLayoutLabel(root.draftLabel)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              settingsCard.open = false
              event.accepted = true
            }
          }
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