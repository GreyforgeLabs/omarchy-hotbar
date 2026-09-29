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
// keeps it until it is destroyed.
var socketOwner = null

function register(screen, instance) { if (screen) instances[screen] = instance }
function unregister(screen, instance) { if (screen && instances[screen] === instance) delete instances[screen] }
function lookup(screen) { return instances[String(screen || "")] || null }
function screens() { return Object.keys(instances) }
function claimSocket(instance) {
  if (!instance) return false
  if (socketOwner === null || socketOwner === instance) { socketOwner = instance; return true }
  return false
}
function releaseSocket(instance) { if (socketOwner === instance) socketOwner = null }
function socketOwnedBy(instance) { return socketOwner !== null && socketOwner === instance }
