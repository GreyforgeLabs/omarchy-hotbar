// Shared across every Hotbar instance in the shell (one per bar / screen).
//
// Quickshell lets exactly one IpcHandler own the `hotbar` target, so on a
// multi-monitor desktop the instance that registered first answers every
// call. Instances register here by screen name so that handler can forward
// screen-addressed calls (`openOn`, `closeOn`) to the right sibling.
.pragma library

var instances = {}

function register(screen, instance) { if (screen) instances[screen] = instance }
function unregister(screen, instance) { if (screen && instances[screen] === instance) delete instances[screen] }
function lookup(screen) { return instances[String(screen || "")] || null }
function screens() { return Object.keys(instances) }
