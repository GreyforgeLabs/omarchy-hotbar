import QtQml

// Compiles every QML file named after `--` without instantiating it, and
// reports the ones that do not parse. Quickshell and the shell's qs.*
// modules are not available here, so a file that parses stops at an import;
// any other first error is a real one. Run by tests/test_qml.sh.
QtObject {
  Component.onCompleted: {
    var args = Qt.application.arguments
    var files = args.slice(args.indexOf("--") + 1)
    var bad = 0
    for (var i = 0; i < files.length; i++) {
      var c = Qt.createComponent(Qt.resolvedUrl("../../" + files[i]))
      if (c.status !== Component.Error) continue
      var first = String(c.errorString()).split("\n")[0]
      if (/module "[^"]+" (is not installed|plugin)|is not a type/.test(first)) continue
      bad++
      console.warn("FAIL: " + files[i] + ": " + first)
    }
    console.warn("parse: " + (files.length - bad) + "/" + files.length + " QML files parse")
    Qt.exit(bad ? 1 : 0)
  }
}
