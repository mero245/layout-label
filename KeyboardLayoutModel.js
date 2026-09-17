// Label math for the keyboard layout widget, kept Qt-free so it can be unit
// tested under node (test/shell.d/keyboard-layout-test.sh).

// Labels shown per layout, overriding what xkb's own brief table would say.
// "English (Colemak)": "cole", "English (US, intl., with dead keys)": "int",
// "Arabic": "ar". A layout entered here keeps exactly this spelling (case and
// length), so a short lowercase label is fine. Per bar entry, a settings
// "labels" object with the same layout descriptions overrides this table.
var LAYOUT_LABELS = {
  "English (Colemak)": "cole",
  "English (US, intl., with dead keys)": "int",
  "Arabic": "ar"
}

// xkbcli list prints YAML, and every layout and variant block pairs a brief with
// the description hyprctl reports as the active keymap:
//
//   - layout: 'us'
//     variant: ''
//     brief: 'en'
//     description: English (US)
//
// The models and option groups it also prints carry no brief of their own, and
// a brief never carries past the block it was printed in, so neither reaches
// the table.
function layoutBriefs(text) {
  var briefs = {}
  var brief = ""

  String(text || "").split("\n").forEach(function (line) {
    if (/^\s*- /.test(line)) brief = ""

    var field = line.match(/^  (brief|description): (.*)$/)
    if (!field) return

    if (field[1] === "brief") {
      brief = field[2].replace(/^'|'$/g, "")
    } else if (brief) {
      briefs[field[2]] = brief
      brief = ""
    }
  })

  return briefs
}

// The same xkbcli list output read as ordered records rather than a flat brief
// table, so a configured layout can be named by the description hyprctl reports
// for it. Each block carries a layout name and usually a variant, which together
// are what hyprctl's parallel layout/variant lists spell out.
//
//   - layout: 'us'
//     variant: 'colemak'
//     brief: 'en'
//     description: English (Colemak)
//
// Blocks that name no layout (models, option groups) are skipped, so only the
// layouts table comes back.
function layoutEntries(text) {
  var entries = []
  var entry = null

  String(text || "").split("\n").forEach(function (line) {
    var start = line.match(/^-\s+layout:\s*(.*)$/)
    if (start) {
      if (entry && entry.description) entries.push(entry)
      entry = { layout: unquote(start[1]), variant: "", brief: "", description: "" }
      return
    }

    if (!entry) return

    var field = line.match(/^ {2}(variant|brief|description):\s*(.*)$/)
    if (!field) return
    entry[field[1]] = unquote(field[2])
  })

  if (entry && entry.description) entries.push(entry)
  return entries
}

function unquote(value) {
  return String(value || "").replace(/^'|'$/g, "")
}

// The layouts the typing keyboard is set to, named the way the rest of the
// widget names them. hyprctl reports `layout` and `variant` as parallel
// comma-separated lists, so the two are zipped position by position and looked
// up in the xkb table; the description that comes back is exactly the key a
// per-layout label override uses.
//
// A layout the table does not know, or one whose variant the list omits, still
// gets an option under its raw name rather than disappearing, so the picker
// never hides a layout the keyboard actually has.
function configuredLayouts(entries, layoutCsv, variantCsv) {
  var layouts = String(layoutCsv || "").split(",")
  var variants = String(variantCsv || "").split(",")
  var options = []
  var seen = {}

  layouts.forEach(function (rawLayout, index) {
    var layout = rawLayout.trim()
    if (!layout) return

    var variant = String(variants[index] || "").trim()
    var match = (entries || []).find(function (candidate) {
      return candidate.layout === layout && String(candidate.variant || "") === variant
    })
    var description = match && match.description ? match.description : layout

    if (seen[description]) return
    seen[description] = true
    options.push({ value: description, label: description })
  })

  return options
}

// The brief is a short language code rather than a country one, which keeps the
// label sensible for the layouts named after a language: Esperanto reads EO and
// Arabic reads AR. It is the same code GNOME shows in its own indicator.
//
// Layouts missing from the table fall back to the first word of the description,
// which reads as ENG/POR but at least says something.
//
// Nearly every brief is a bare two-letter code, but a few tack a script onto it
// (Burmese (Zawgyi) is my-zwg) and the custom layout's is a word, so drop the
// script and cap the result at the same three characters the fallback gets.
// The widget sits between fixed neighbours on the bar and has no room to grow.
function shortLabel(description, briefs, labels) {
  if (!description) return ""

  // The per-entry settings win, then the table in this file, then xkb's briefs.
  var override = (labels || {})[description] || LAYOUT_LABELS[description]
  if (typeof override === "string" && override !== "") return override

  // A description like "constructor" reaches an inherited member rather than a
  // brief, so take the lookup only when it hands back the string it promises.
  var brief = (briefs || {})[description]
  var label = typeof brief === "string" && brief ? brief.split("-")[0] : description.split(/\s+/)[0]
  return label.substring(0, 3).toUpperCase()
}

// Hyprland's activelayout event pairs the keyboard that switched with the layout
// it moved to. Quickshell cuts the event into that many fields, so a description
// carrying a comma of its own stays in one piece; a binding old enough to hand
// back only the raw string gets split by hand. The virtual keyboard fcitx5 binds
// to inject announces switches too, and names a keyboard nobody types on.
function eventKeyboardName(event) {
  var parts

  try {
    if (event && event.parse) parts = event.parse(2)
  } catch (error) {
  }

  if (!parts) parts = String(event && event.data ? event.data : "").split(",")

  var name = String(parts[0] || "")
  return name.indexOf("hl-virtual-keyboard") === 0 ? "" : name
}

// Hyprland reports more than keyboards as keyboards. fcitx5 binds a virtual one
// to inject through, which keeps the us layout the input method gave it, and the
// ACPI power button, lid switch and sleep key each arrive carrying the seat's
// layout list without anyone ever typing on them. Both answer to switchxkblayout
// and both can hold the main flag, so a widget that reads or switches whatever
// the seat hands it ends up describing a button. Leave them out and what remains
// is keyboards, which is what the rest of this file can then assume.
//
// Missing a name here costs the accuracy the seat had before, never a keyboard:
// anything unrecognised stays in the list.
var UNTYPED_KEYBOARDS = /^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus)/

function isTypedKeyboard(name) {
  return !UNTYPED_KEYBOARDS.test(String(name || ""))
}

// Every keyboard on the seat carries the same layout list unless one was given
// its own, but only the one being typed on advances through it. So the
// furthest-advanced is the one worth reading, and a switch names the keyboard it
// moved, which settles a seat holding two real keyboards outright.
//
// The name is taken whenever a keyboard still answers to it, wherever that
// keyboard sits in the list. Comparing positions instead would read the wrong
// keyboard the moment one wrapped from the last layout back to the first, which
// is the ordinary way round a pair of them. Applying a layout to the whole seat
// names a keyboard too, but leaves every one of them on the same layout, so the
// label reads the same whichever of them the name settles on.
function selectKeyboard(typed, namedByEvent) {
  var keyboards = typed || []

  var named = keyboards.find(function (keyboard) {
    return keyboard.name === namedByEvent
  })
  if (named) return named

  // The seat lists devices that are not keyboards (radio controls, hotkey
  // arrays, HID event sinks); prefer a device that is really a keyboard when
  // one is present so the widget reads and switches one that gets key events.
  // On machines whose physical keyboards are grabbed by keyd, the keys typed
  // travel through keyd's merged uinput device and not the grabbed originals,
  // so it must come first or the widget would switch a device nothing types
  // on: the label would change while the characters never did.
  var keyd = keyboards.find(function (keyboard) {
    return String(keyboard.name || "").toLowerCase().indexOf("keyd-virtual-keyboard") === 0
  })
  if (keyd) return keyd

  var keyboardish = keyboards.find(function (keyboard) {
    return /keyboard/i.test(String(keyboard.name || ""))
  })
  if (keyboardish) return keyboardish

  return keyboards.reduce(function (furthest, keyboard) {
    return layoutIndex(keyboard) > layoutIndex(furthest) ? keyboard : furthest
  }, keyboards[0])
}

function layoutIndex(keyboard) {
  return (keyboard && keyboard.active_layout_index) || 0
}

if (typeof module !== "undefined") {
  module.exports = {
    configuredLayouts: configuredLayouts,
    eventKeyboardName: eventKeyboardName,
    isTypedKeyboard: isTypedKeyboard,
    layoutBriefs: layoutBriefs,
    layoutEntries: layoutEntries,
    selectKeyboard: selectKeyboard,
    shortLabel: shortLabel
  }
}