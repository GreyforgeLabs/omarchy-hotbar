import QtQml
import "../../HotbarModel.js" as M
import "../../PlacesModel.js" as P
import "../../HotbarRegistry.js" as R

// The model files in the engine that ships them (QML's V4, not node): run
// headless by tests/test_qml.sh. Prints one line per failure and exits 1 on
// any, 0 otherwise.
QtObject {
  id: root
  // The shell keeps groups in a `property var`; prototype-free maps must
  // survive that round trip.
  property var groups: ({})
  property int passed: 0
  property int failed: 0

  function check(name, ok) {
    if (ok) passed++
    else { failed++; console.warn("FAIL: " + name) }
  }

  Component.onCompleted: {
    var index = M.buildEntryIndex([{ id: "org.gnome.Nautilus", name: "Files", icon: "nautilus" }])
    var nautilus = M.resolveIdentity({ appId: "org.gnome.Nautilus" }, index, [], null)
    var built = M.buildGroups([{ address: "n1", identity: nautilus }], ["constructor", "org.gnome.nautilus"], [], index, [])
    root.groups = built.groups
    check("prototype pin stays a plain pin", built.pinned[0].key === "constructor" && built.pinned[0].windows.length === 0 && Object.pinned === undefined)
    check("mis-cased pin owns the window", built.pinned[1].key === "org.gnome.Nautilus" && built.pinned[1].count === 1 && built.running.length === 0)
    check("prototype-free groups survive a property var", Object.keys(root.groups).length === 2 && root.groups["toString"] === undefined && root.groups["org.gnome.Nautilus"].count === 1)
    check("app id toString keeps its window", M.resolveIdentity({ appId: "toString" }, index, [], null).key === "class:tostring")
    var target = { ping: function() { return "ok" } }
    check("dispatch answers a declared method", M.dispatchRequest("ping", { ping: 0 }, target) === "ok")
    check("dispatch refuses inherited names", M.dispatchRequest("toString", { ping: 0 }, target) === "Function not found."
      && M.dispatchRequest("constructor", { ping: 0 }, target) === "Function not found.")
    check("settings keys are own keys only", M.isSettingKey("iconSize") && !M.isSettingKey("constructor"))
    // V4 has no TextDecoder: this is the decoder the widget really runs.
    check("hex UTF-8 decode (V4 path)", M.decodeHexUtf8("22e282acf09f988022") === "\"€😀\"")
    check("icon file URL encodes #, ? and %", M.fileUrl("/i/a #1?%.png") === "file:///i/a%20%231%3F%25.png")
    var stacked = { filesystems: [
      { target: "/mnt/usb", source: "/dev/sdb1", fstype: "ext4", label: "Under", options: "rw", fsroot: "/" },
      { target: "/mnt/usb", source: "/dev/sdc1", fstype: "exfat", label: "On Top", options: "rw", fsroot: "/" }
    ] }
    var drives = P.mountEntries(stacked, "/home/ada", {})
    check("over-mount: the top filesystem is shown", drives.length === 1 && drives[0].name === "On Top")
    var a = { id: "a" }, b = { id: "b", told: 0 }
    b.socketFreed = function() { b.told++; R.claimSocket(b) }
    R.claimSocket(a); R.claimSocket(b); R.releaseSocket(a)
    check("socket handover without polling", R.socketOwnedBy(b) && b.told === 1)
    R.releaseSocket(b)
    console.warn("V4: " + passed + " checks passed, " + failed + " failed")
    Qt.exit(failed ? 1 : 0)
  }
}
