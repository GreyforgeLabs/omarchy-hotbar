// Shared across every Hotbar instance in the shell (one per bar / screen).
//
// Quickshell lets exactly one IpcHandler own the `hotbar` target, so on a
// multi-monitor desktop the instance that registered first answers every
// call. Instances register here by screen name so that handler can forward
// screen-addressed calls (`openOn`, `closeOn`) to the right sibling.
.pragma library

var instances = {}

// The widget's own Unix socket (bin/hotbar-native) is served by exactly one
// instance per shell, like the `hotbar` IPC target: the first to claim it
// keeps it until it is destroyed. Instances that were refused wait here and
// the oldest one is handed the socket when the owner releases it (a plugin
// hot-reload, a monitor going away) — no instance polls for it.
var socketOwner = null
var socketWaiters = []

function register(screen, instance) { if (screen) instances[screen] = instance }
function unregister(screen, instance) { if (screen && instances[screen] === instance) delete instances[screen] }
function lookup(screen) {
  var key = String(screen || "")
  return Object.prototype.hasOwnProperty.call(instances, key) ? instances[key] : null
}
function screens() { return Object.keys(instances) }
function claimSocket(instance) {
  if (!instance) return false
  if (socketOwner === null || socketOwner === instance) {
    socketOwner = instance
    socketWaiters = socketWaiters.filter(function(w) { return w !== instance })
    return true
  }
  if (socketWaiters.indexOf(instance) === -1) socketWaiters.push(instance)
  return false
}
// On release every waiter's socketFreed() runs, oldest first, until one of
// them claims the socket synchronously; a waiter that claims later (Hotbar
// waits a beat) races fairly and a refused one queues again. A waiter that
// is gone (or throws) is skipped.
function releaseSocket(instance) {
  socketWaiters = socketWaiters.filter(function(w) { return w !== instance })
  if (socketOwner !== instance || instance === null) return
  socketOwner = null
  while (socketOwner === null && socketWaiters.length) {
    var next = socketWaiters.shift()
    try { if (next && typeof next.socketFreed === "function") next.socketFreed() } catch (e) {}
  }
}
function socketOwnedBy(instance) { return socketOwner !== null && socketOwner === instance }
