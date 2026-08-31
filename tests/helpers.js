// Loads a `.pragma library` QML JS module into Node for testing.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

function loadModule(name) {
  const file = path.join(__dirname, "..", name)
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/m, "")
  const context = { Number, Math, Date, JSON, Array, Object, String, RegExp, encodeURIComponent, parseInt, isNaN }
  vm.createContext(context)
  vm.runInContext(source, context, { filename: file })
  return context
}

let failures = 0
function assert(condition, message) {
  if (condition) return
  failures++
  console.error("FAIL: " + message)
}
function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected),
    message + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
}
function done(name) {
  if (failures) { console.error(name + ": " + failures + " failure(s)"); process.exit(1) }
  console.log(name + ": ok")
}

module.exports = { loadModule, assert, equal, done }
