// Capture subprocess/filesystem seam: fake Omarchy, real private files/helpers.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawnSync, spawn } = require("node:child_process")
const project = path.resolve(__dirname, "..")
const source = fs.readFileSync(path.join(project, "Capture.qml"), "utf8")
const root = fs.mkdtempSync(path.join(os.tmpdir(), "gorelo-capture-test-"))
const bin = path.join(root, "bin"), home = path.join(root, "home")
async function main() {
try {
  fs.mkdirSync(bin, { mode: 0o700 })
  fs.mkdirSync(home, { mode: 0o700 })
  // Only these filesystem/process-supervision tools may run for real. No desktop tools.
  for (const name of ["bash", "stat", "rm", "mktemp", "ln", "timeout", "head", "mkfifo", "sleep", "rmdir", "mv"]) {
    fs.symlinkSync(`/usr/bin/${name}`, path.join(bin, name))
  }
  const grandchildScript = path.join(root, "grandchild.js")
  fs.writeFileSync(grandchildScript, `
const fs=require('node:fs')
process.on('SIGTERM',()=>fs.writeFileSync(process.env.CAPTURE_RECORD+'.grandchild-term','TERM'))
fs.writeFileSync(process.env.CAPTURE_RECORD+'.grandchild-ready',String(process.pid))
setInterval(()=>{},1000)
`)
  fs.writeFileSync(path.join(bin, "omarchy"), `#!${process.execPath}
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict')
assert.deepEqual(process.argv.slice(2),['capture','screenshot','region','save'])
if(process.env.CAPTURE_CALLED)fs.writeFileSync(process.env.CAPTURE_CALLED,'called')
if(process.env.CAPTURE_LOCALE_RECORD)fs.writeFileSync(process.env.CAPTURE_LOCALE_RECORD,JSON.stringify({
 LANG:process.env.LANG,LANGUAGE:process.env.LANGUAGE,LC_ALL:process.env.LC_ALL
}))
const scenario=process.env.CAPTURE_SCENARIO
if(scenario==='cancel')process.exit(0)
if(scenario==='hang'){
 const child=require('node:child_process').spawn(process.execPath,[process.env.GRANDCHILD_SCRIPT],{stdio:'ignore'})
 process.on('SIGTERM',()=>{
  fs.writeFileSync(process.env.CAPTURE_RECORD+'.term','TERM')
  setTimeout(()=>{fs.writeFileSync(process.env.CAPTURE_RECORD+'.cleaned','cleanup');process.exit(143)},300)
 })
 fs.writeFileSync(process.env.CAPTURE_RECORD,JSON.stringify({pid:process.pid,child:child.pid}))
 setInterval(()=>{},1000)
}else{
 const file=path.join(process.env.OMARCHY_SCREENSHOT_DIR,'screenshot-2026-10-02_12-00-00.png')
 fs.writeFileSync(file,process.env.CAPTURE_CONTENT,{mode:0o600})
 if(process.env.CAPTURE_SIZE)fs.truncateSync(file,Number(process.env.CAPTURE_SIZE))
 if(scenario==='failed')process.exit(23)
 if(scenario==='symlink'){
  fs.unlinkSync(file);fs.symlinkSync(process.env.OUTSIDE_FILE,file)
 }
 if(scenario==='nonregular'){
  fs.unlinkSync(file);fs.mkdirSync(file)
 }
 if(scenario==='collision'){
  const token=path.basename(fs.realpathSync(process.env.OMARCHY_SCREENSHOT_DIR)).slice('.capture-'.length)
  fs.writeFileSync('/dev/fd/8/screenshot-'+token+'.png','existing destination')
 }
 if(scenario==='stage-swap'){
  const stage=fs.realpathSync(process.env.OMARCHY_SCREENSHOT_DIR)
  fs.renameSync(stage,stage+'.held');fs.symlinkSync(process.env.OUTSIDE_DIR,stage)
 }
 if(scenario==='root-swap'){
  const parent=fs.realpathSync('/dev/fd/8')
  fs.renameSync(parent,parent+'.held');fs.symlinkSync(process.env.OUTSIDE_DIR,parent)
 }
 if(scenario==='delayed'){
  const child=require('node:child_process').spawn(process.execPath,[process.env.GRANDCHILD_SCRIPT],{stdio:['ignore',1,2]})
  fs.writeFileSync(process.env.CAPTURE_RECORD,JSON.stringify({pid:process.pid,child:child.pid}))
  child.unref()
 }
 if(scenario==='poison-output'){
  fs.writeFileSync(process.env.OUTSIDE_FILE,file+'\\n')
  fs.unlinkSync(path.join(process.env.OMARCHY_SCREENSHOT_DIR,'.stdout'))
  fs.symlinkSync(process.env.OUTSIDE_FILE,path.join(process.env.OMARCHY_SCREENSHOT_DIR,'.stdout'))
 }
 if(scenario==='poison-status'){
  fs.symlinkSync(process.env.OUTSIDE_FILE,path.join(process.env.OMARCHY_SCREENSHOT_DIR,'.done'))
 }
 if(scenario==='stdout-flood'||scenario==='stderr-flood'){
  const stream=scenario==='stdout-flood'?process.stdout:process.stderr
  stream.on('error',()=>{})
  if(scenario==='stderr-flood')process.stdout.write(file+'\\n')
  stream.write('X'.repeat(1024*1024))
  setTimeout(()=>{
   const size=fs.statSync(path.join(process.env.OMARCHY_SCREENSHOT_DIR,scenario==='stdout-flood'?'.stdout':'.stderr')).size
   fs.writeFileSync(process.env.CAPTURE_RECORD,String(size));process.exit(0)
  },100)
 }else if(scenario==='delayed')setTimeout(()=>process.stdout.write(file+'\\n'),200)
 else process.stdout.write((process.env.CAPTURE_HINT||file)+'\\n')
}
`, { mode: 0o700 })
  function fixture() {
    const dir = fs.mkdtempSync(path.join(root, "private-"))
    fs.chmodSync(dir, 0o700)
    return dir
  }
  function extract(name) {
    const start = source.indexOf("  function " + name + "("), end = source.indexOf("\n  }", start)
    assert(start >= 0 && end > start)
    return source.slice(start, end + 4)
  }
  function captureContext(dir) {
    const c = { String, screenshotDir: dir, deleteQueue: [], cleanupProcess: { running: true },
      captureHelperPath: path.join(project, "scripts/gorelo-capture") }
    c.root = c; vm.createContext(c)
    vm.runInContext(["validAttachmentName", "nameFromCaptureHint", "deleteAttachment"].map(extract).join("\n"), c)
    c.command = vm.runInContext(source.match(/property Process captureProcess: Process \{\s*command: ([^\n]+)/)[1], c)
    return c
  }
  function environment(dir, extra = {}) {
    return { PATH: bin, HOME: home, XDG_RUNTIME_DIR: root, OMARCHY_SCREENSHOT_DIR: dir, ...extra }
  }
  function run(c, extra = {}) {
    return spawnSync(c.command[0], c.command.slice(1), {
      env: environment(c.screenshotDir, { CAPTURE_CONTENT: "private capture", ...extra }), encoding: "utf8", timeout: 5000
    })
  }
  function take(c, content) {
    const result = run(c, { CAPTURE_CONTENT: content })
    assert.equal(result.status, 0, result.stderr)
    const name = c.nameFromCaptureHint(result.stdout.trim().split("\n").at(-1))
    assert(name, "capture returns a validated root-scoped attachment")
    assert.match(name, /^screenshot-[A-Za-z0-9]{24}\.png$/, "published identifier comes from the fresh long random token")
    return name
  }
  // Faithful localized-stat boundary independent of installed translations.
  fs.unlinkSync(path.join(bin, "stat"))
  fs.writeFileSync(path.join(bin, "stat"), `#!/usr/bin/bash
output=$(LC_ALL=C /usr/bin/stat "$@") || exit "$?"
if [[ \${LANGUAGE:-} == de && \${LC_ALL:-} != C ]]; then
 output=\${output//regular empty file/leere reguläre Datei}
 output=\${output//regular file/reguläre Datei}
 output=\${output//symbolic link/symbolische Verknüpfung}
 output=\${output//directory/Verzeichnis}
 output=\${output//fifo/FIFO}
fi
printf '%s\\n' "$output"
`, { mode: 0o700 })
  const localized = captureContext(fixture()), localeRecord = path.join(root, "capture-locale.json")
  const parentLocale = { LANG: "en_US.utf8", LANGUAGE: "de", LC_ALL: "en_US.utf8" }
  const localizedResult = run(localized, { ...parentLocale, CAPTURE_LOCALE_RECORD: localeRecord })
  assert.equal(localizedResult.status, 0, "capture works with localized parent metadata: " + localizedResult.stderr)
  const localizedName = localized.nameFromCaptureHint(localizedResult.stdout.trim())
  assert(localizedName)
  assert.equal(fs.readFileSync(path.join(localized.screenshotDir, localizedName), "utf8"), "private capture")
  assert.deepEqual(JSON.parse(fs.readFileSync(localeRecord, "utf8")), parentLocale, "metadata locale isolation must not change the screenshot child's locale")
  assert.deepEqual(fs.readdirSync(localized.screenshotDir), [localizedName])
  fs.unlinkSync(path.join(bin, "stat")); fs.symlinkSync("/usr/bin/stat", path.join(bin, "stat"))
  console.log("ok: localized capture metadata is isolated while screenshot child retains parent locale")
  if (process.argv.includes("--locale-only")) return
  const c = captureContext(fixture())
  const oldName = take(c, "old capture")
  c.deleteAttachment(oldName) // Worker busy: old cleanup starts only after the next capture.
  const newName = take(c, "new capture")
  const result = spawnSync("/bin/bash", [path.join(project, "scripts/gorelo-attachment"), "delete",
    c.screenshotDir, c.deleteQueue[0]], { env: environment(c.screenshotDir), encoding: "utf8", timeout: 5000 })
  assert.equal(result.status, 0, result.stderr)
  assert(fs.existsSync(path.join(c.screenshotDir, newName)), "delayed old delete cannot remove the newer capture")
  assert.equal(fs.readFileSync(path.join(c.screenshotDir, newName), "utf8"), "new capture")
  assert.notEqual(oldName, newName, "same pinned timestamp captures have different stable basenames")
  console.log("ok: pinned timestamp captures stay distinct and delayed old cleanup preserves the newer file")
  const hang = captureContext(fixture()), record = path.join(root, "hang.json")
  const child = spawn(hang.command[0], hang.command.slice(1), {
    env: environment(hang.screenshotDir, { CAPTURE_SCENARIO: "hang", CAPTURE_RECORD: record,
      GRANDCHILD_SCRIPT: grandchildScript }), stdio: ["ignore", "pipe", "pipe"]
  })
  let stderr = "", stdout = "", pids
  child.stderr.on("data", data => { stderr += data })
  child.stdout.on("data", data => { stdout += data })
  const exited = new Promise((resolve, reject) => {
    child.on("error", reject)
    child.on("exit", (code, signal) => resolve({ code, signal }))
  })
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms))
  function alive(pid) {
    try { return !fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].startsWith("Z ") }
    catch (error) { if (error.code === "ENOENT") return false; throw error }
  }
  try {
    const readyDeadline = Date.now() + 3000
    while ((!fs.existsSync(record) || !fs.existsSync(record + ".grandchild-ready")) && Date.now() < readyDeadline) await pause(10)
    assert(fs.existsSync(record + ".grandchild-ready"), "fake capture and grandchild ready: " + stderr)
    pids = JSON.parse(fs.readFileSync(record, "utf8"))
    child.kill("SIGTERM")
    const stopDeadline = Date.now() + 1800
    while (child.exitCode === null && child.signalCode === null && Date.now() < stopDeadline) await pause(10)
    assert(child.exitCode !== null || child.signalCode !== null, "capture wrapper must stop within QML's 2s escalation grace")
    await exited
    assert(fs.existsSync(record + ".term"), "TERM reaches the screenshot tool")
    assert(fs.existsSync(record + ".cleaned"), "screenshot tool gets time for its own cleanup")
    assert(!alive(pids.pid) && !alive(pids.child), "wrapper reaps/terminates its tool and TERM-resistant grandchild")
    assert.equal(stdout, "", "cancellation never publishes an attachment")
    const leftovers = fs.readdirSync(hang.screenshotDir)
    assert.deepEqual(leftovers, [], "cancellation removes owned staging artifacts: " + JSON.stringify(
      leftovers.map(name => [name, fs.readdirSync(path.join(hang.screenshotDir, name))])) + ": " + stderr)
    console.log("ok: cancellation allows tool cleanup, kills delayed grandchild and removes staging")
  } finally {
    // Exact fixture PIDs only; keep red runs from leaking controlled child processes.
    if (!pids && fs.existsSync(record)) pids = JSON.parse(fs.readFileSync(record, "utf8"))
    for (const pid of pids ? [pids.pid, pids.child] : []) {
      if (alive(pid)) try { process.kill(pid, "SIGKILL") } catch (error) { if (error.code !== "ESRCH") throw error }
    }
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL")
    await exited
  }
  const poisoned = captureContext(fixture()), outside = path.join(root, "outside-output")
  const rejected = run(poisoned, { CAPTURE_SCENARIO: "poison-output", OUTSIDE_FILE: outside })
  assert.notEqual(rejected.status, 0, "refuse a symlink-swapped output collector instead of reading/publishing its target")
  assert.equal(rejected.stdout, "")
  assert(fs.existsSync(outside), "refused collector never deletes its external target")
  assert.deepEqual(fs.readdirSync(poisoned.screenshotDir), [], "refused collector cleans only its owned staging artifacts")
  console.log("ok: symlink-swapped output collector is refused without touching its external target")
  const statusPoisoned = captureContext(fixture()), statusOutside = path.join(root, "outside-status")
  fs.writeFileSync(statusOutside, "outside must remain unchanged")
  const statusRejected = run(statusPoisoned, { CAPTURE_SCENARIO: "poison-status", OUTSIDE_FILE: statusOutside })
  assert.notEqual(statusRejected.status, 0, "refuse symlink-swapped completion status")
  assert.equal(fs.readFileSync(statusOutside, "utf8"), "outside must remain unchanged", "completion status must never write through a tool-created symlink")
  assert.equal(statusRejected.stdout, "")
  assert.deepEqual(fs.readdirSync(statusPoisoned.screenshotDir), [])
  console.log("ok: symlink-swapped completion status cannot overwrite an external target")
  for (const extra of [
    { CAPTURE_HINT: "/outside/screenshot-test.png" },
    { CAPTURE_HINT: "/dev/fd/9/screenshot-evil..png" },
    { CAPTURE_HINT: "/dev/fd/9/screenshot-../test.png" },
    { CAPTURE_HINT: "/dev/fd/9/screenshot-test.png\nextra line" },
    { CAPTURE_SCENARIO: "symlink" }, { CAPTURE_SIZE: String(20 * 1024 * 1024 + 1) },
    { CAPTURE_SCENARIO: "failed" }
  ]) {
    const target = captureContext(fixture()), external = path.join(root, "outside-attachment")
    fs.writeFileSync(external, "outside stays untouched")
    const result = run(target, { ...extra, OUTSIDE_FILE: external })
    assert.notEqual(result.status, 0, "refuse unsafe capture: " + JSON.stringify(extra))
    assert.equal(result.stdout, "")
    assert.equal(fs.readFileSync(external, "utf8"), "outside stays untouched")
    assert.deepEqual(fs.readdirSync(target.screenshotDir), [], "unsafe capture cleans only owned files")
  }
  console.log("ok: malformed/outside/symlink/oversized outputs and tool failures are refused")
  const canceled = captureContext(fixture()), cancellation = run(canceled, { CAPTURE_SCENARIO: "cancel" })
  assert.equal(cancellation.status, 0, cancellation.stderr)
  assert.equal(cancellation.stdout, "")
  assert.deepEqual(fs.readdirSync(canceled.screenshotDir), [])
  const exact = captureContext(fixture()), exactResult = run(exact, { CAPTURE_SIZE: String(20 * 1024 * 1024) })
  assert.equal(exactResult.status, 0, exactResult.stderr)
  assert.equal(fs.statSync(exactResult.stdout.trim()).size, 20 * 1024 * 1024)
  assert.deepEqual(fs.readdirSync(exact.screenshotDir), [path.basename(exactResult.stdout.trim())])
  console.log("ok: empty cancellation leaves no files; exact 20 MiB remains allowed")
  const collision = captureContext(fixture()), collided = run(collision, { CAPTURE_SCENARIO: "collision" })
  assert.notEqual(collided.status, 0)
  assert.equal(collided.stdout, "")
  const collisionFiles = fs.readdirSync(collision.screenshotDir)
  assert.equal(collisionFiles.length, 1)
  assert.equal(fs.readFileSync(path.join(collision.screenshotDir, collisionFiles[0]), "utf8"), "existing destination")
  console.log("ok: publication collision fails closed without clobbering its destination")
  for (const scenario of ["stdout-flood", "stderr-flood"]) {
    const target = captureContext(fixture()), count = path.join(root, scenario + ".count")
    const flooded = run(target, { CAPTURE_SCENARIO: scenario, CAPTURE_RECORD: count })
    assert.equal(Number(fs.readFileSync(count, "utf8")), 8192, scenario + " collector is capped")
    if (scenario === "stdout-flood") {
      assert.notEqual(flooded.status, 0)
      assert.equal(flooded.stdout, "")
      assert.deepEqual(fs.readdirSync(target.screenshotDir), [])
    } else {
      assert.equal(flooded.status, 0, flooded.stderr)
      assert.equal(flooded.stderr, "", "diagnostics stay bounded and are not forwarded")
    }
  }
  console.log("ok: stdout and stderr collectors are capped before parsing")
  for (const kind of ["nonprivate", "symlink"]) {
    const dir = fixture(), called = path.join(root, "root-called-" + kind)
    let target = dir
    if (kind === "nonprivate") fs.chmodSync(dir, 0o755)
    else { target += ".link"; fs.symlinkSync(dir, target) }
    const rejected = run(captureContext(target), { CAPTURE_CALLED: called })
    assert.notEqual(rejected.status, 0)
    assert.equal(rejected.stdout, "")
    assert(!fs.existsSync(called), "unsafe root never starts the capture tool")
    assert.deepEqual(fs.readdirSync(dir), [])
  }
  console.log("ok: nonprivate and symlink roots are refused before capture")
  for (const scenario of ["stage-swap", "root-swap"]) {
    const target = captureContext(fixture()), outsideDir = fixture()
    const external = path.join(outsideDir, "screenshot-unrelated.png")
    fs.writeFileSync(external, "unrelated file")
    const swapped = run(target, { CAPTURE_SCENARIO: scenario, OUTSIDE_DIR: outsideDir })
    assert.notEqual(swapped.status, 0)
    assert.equal(swapped.stdout, "")
    assert.equal(fs.readFileSync(external, "utf8"), "unrelated file", "swapped symlink target is never followed by publication/cleanup")
    if (scenario === "stage-swap") {
      const stageLink = fs.readdirSync(target.screenshotDir).find(name => !name.endsWith(".held"))
      assert(fs.lstatSync(path.join(target.screenshotDir, stageLink)).isSymbolicLink(), "unvalidated stage entry is not removed")
    } else assert(fs.lstatSync(target.screenshotDir).isSymbolicLink(), "unvalidated root entry is not removed")
  }
  console.log("ok: root/staging pathname swaps cannot publish or clean through replacement symlinks")
  const nonregular = captureContext(fixture()), directoryOutput = run(nonregular, { CAPTURE_SCENARIO: "nonregular" })
  assert.notEqual(directoryOutput.status, 0)
  assert.equal(directoryOutput.stdout, "")
  const retainedStage = path.join(nonregular.screenshotDir, fs.readdirSync(nonregular.screenshotDir)[0])
  assert(fs.statSync(path.join(retainedStage, "screenshot-2026-10-02_12-00-00.png")).isDirectory(), "cleanup never recursively removes unexpected tool-created directories")
  console.log("ok: nonregular output is refused and unvalidated directories are retained, not recursively deleted")
  fs.unlinkSync(path.join(bin, "stat"))
  fs.writeFileSync(path.join(bin, "stat"), `#!/usr/bin/bash
output=$(/usr/bin/stat "$@") || exit "$?"
if [[ "$*" == *'%F:%u:'* ]]; then
 target=\${!#}
 if [[ ( \${TEST_UNOWNED:-} == root && $target == "$TEST_ROOT" ) ||
       ( \${TEST_UNOWNED:-} == stage && $target == .capture-* ) ||
       ( \${TEST_UNOWNED:-} == file && $target == screenshot-*.png ) ]]; then
  IFS=: read -r type uid rest <<< "$output"
  output="$type:$((EUID+1)):$rest"
 fi
fi
printf '%s\\n' "$output"
`, { mode: 0o700 })
  for (const kind of ["root", "stage", "file"]) {
    const target = captureContext(fixture()), called = path.join(root, "unowned-called-" + kind)
    const refused = run(target, { TEST_UNOWNED: kind, TEST_ROOT: target.screenshotDir, CAPTURE_CALLED: called })
    assert.notEqual(refused.status, 0, "refuse simulated unowned " + kind)
    assert.equal(refused.stdout, "")
    if (kind !== "file") assert(!fs.existsSync(called), "unowned root/stage never starts the tool")
    if (kind === "root") assert.deepEqual(fs.readdirSync(target.screenshotDir), [])
    if (kind === "file") {
      const stage = path.join(target.screenshotDir, fs.readdirSync(target.screenshotDir)[0])
      assert.equal(fs.readFileSync(path.join(stage, "screenshot-2026-10-02_12-00-00.png"), "utf8"), "private capture", "cleanup must retain an unowned file")
    }
  }
  console.log("ok: unowned root/stage/file metadata is refused without privilege changes or deleting unowned artifacts")
  fs.unlinkSync(path.join(bin, "stat")); fs.symlinkSync("/usr/bin/stat", path.join(bin, "stat"))
  fs.unlinkSync(path.join(bin, "ln"))
  fs.writeFileSync(path.join(bin, "ln"), `#!/usr/bin/bash
mv -- screenshot-2026-10-02_12-00-00.png screenshot-bound-original.png
printf '%s' 'replacement must not be published' > screenshot-2026-10-02_12-00-00.png
exec /usr/bin/ln "$@"
`, { mode: 0o700 })
  const bound = captureContext(fixture()), boundName = take(bound, "bound original capture")
  assert.equal(fs.readFileSync(path.join(bound.screenshotDir, boundName), "utf8"), "bound original capture", "publication follows the verified fd, not a replaced source name")
  assert.deepEqual(fs.readdirSync(bound.screenshotDir), [boundName])
  console.log("ok: publication remains inode-bound when the source pathname is replaced")
  fs.unlinkSync(path.join(bin, "ln")); fs.symlinkSync("/usr/bin/ln", path.join(bin, "ln"))
  const delayed = captureContext(fixture()), delayedRecord = path.join(root, "delayed.json")
  try {
    const completed = run(delayed, { CAPTURE_SCENARIO: "delayed", CAPTURE_RECORD: delayedRecord,
      GRANDCHILD_SCRIPT: grandchildScript })
    assert.equal(completed.status, 0, completed.stderr)
    const owned = JSON.parse(fs.readFileSync(delayedRecord, "utf8"))
    assert(fs.existsSync(delayedRecord + ".grandchild-ready"), "delayed grandchild was actually running")
    assert(!alive(owned.pid) && !alive(owned.child), "successful capture also terminates delayed stdout-holding descendants")
    assert.equal(fs.readFileSync(completed.stdout.trim(), "utf8"), "private capture")
    assert.deepEqual(fs.readdirSync(delayed.screenshotDir), [path.basename(completed.stdout.trim())])
  } finally {
    if (fs.existsSync(delayedRecord)) {
      const owned = JSON.parse(fs.readFileSync(delayedRecord, "utf8"))
      for (const pid of [owned.pid, owned.child]) if (alive(pid)) try { process.kill(pid, "SIGKILL") } catch (error) { if (error.code !== "ESRCH") throw error }
    }
  }
  console.log("ok: successful capture kills delayed stdout-holding grandchildren before publication")
  fs.unlinkSync(path.join(bin, "timeout"))
  fs.writeFileSync(path.join(bin, "timeout"), `#!/usr/bin/bash
args=("$@")
args[1]=0.5s
exec /usr/bin/timeout "\${args[@]}"
`, { mode: 0o700 })
  const deadline = captureContext(fixture()), deadlineRecord = path.join(root, "deadline.json")
  let helperTimeoutResult
  try {
    const expired = run(deadline, { CAPTURE_SCENARIO: "hang", CAPTURE_RECORD: deadlineRecord,
      GRANDCHILD_SCRIPT: grandchildScript })
    helperTimeoutResult = expired
    assert.notEqual(expired.status, 0, "internal capture deadline fails closed")
    assert.equal(expired.stdout, "")
    const owned = JSON.parse(fs.readFileSync(deadlineRecord, "utf8"))
    assert(fs.existsSync(deadlineRecord + ".term") && fs.existsSync(deadlineRecord + ".cleaned"), "internal deadline also permits screenshot-tool cleanup")
    assert(!alive(owned.pid) && !alive(owned.child))
    assert.deepEqual(fs.readdirSync(deadline.screenshotDir), [])
  } finally {
    if (fs.existsSync(deadlineRecord)) {
      const owned = JSON.parse(fs.readFileSync(deadlineRecord, "utf8"))
      for (const pid of [owned.pid, owned.child]) if (alive(pid)) try { process.kill(pid, "SIGKILL") } catch (error) { if (error.code !== "ESRCH") throw error }
    }
  }
  fs.unlinkSync(path.join(bin, "timeout")); fs.symlinkSync("/usr/bin/timeout", path.join(bin, "timeout"))
  console.log("ok: real coreutils timeout (shortened only by fixture shim) terminates/reaps and cleans staging")
  // Existing Capture entry-point/callback seam, with timers/processes modeled.
  const lifecycle = captureContext(fixture()), patches = [], errors = []
  let summons = 0
  Object.assign(lifecycle, { draftRevision: 7, captureRevision: -1, capturePending: false, capturing: false,
    capturePath: "", captureProcess: { running: false }, captureDirProcess: { running: false },
    captureKillDeadline: { stop() {} }, captureDelay: { restart() {} },
    captureDeadline: { restart() {}, stop() {} }, updateDraft: patch => patches.push(patch),
    reportError: error => errors.push(error), summon: () => summons++ })
  vm.runInContext(["fail", "captureScreenshot"].map(extract).join("\n"), lifecycle)
  const exitStart = source.indexOf("    onExited: function(exitCode) {", source.indexOf("  property Process captureProcess: Process {"))
  const exitEnd = source.indexOf("\n    }\n  }", exitStart)
  const onExited = vm.runInContext("(" + source.slice(exitStart + "    onExited: ".length, exitEnd + 6) + ")", lifecycle)
  assert.equal(lifecycle.captureScreenshot(), true)
  assert.equal(lifecycle.captureRevision, 7)
  assert.equal(lifecycle.captureScreenshot(), false, "capture cannot overlap while preparation is running")
  lifecycle.captureDirProcess.running = false
  lifecycle.capturePath = lifecycle.screenshotDir + "/" + newName
  onExited(0)
  assert.equal(patches.length, 1)
  assert.equal(patches[0].attachmentPath, newName, "current revision accepts the helper's unique basename")
  assert.equal(lifecycle.captureRevision, -1)
  lifecycle.captureScreenshot(); lifecycle.captureDirProcess.running = false
  lifecycle.draftRevision++
  lifecycle.capturePath = lifecycle.screenshotDir + "/" + oldName
  onExited(0)
  assert.equal(patches.length, 1, "stale capture never replaces a newer draft")
  assert.equal(lifecycle.deleteQueue.at(-1), oldName, "stale helper output is queued for cleanup by its own unique name")
  lifecycle.captureScreenshot(); lifecycle.captureDirProcess.running = false
  lifecycle.fail("Screenshot capture timed out.")
  lifecycle.capturePath = lifecycle.screenshotDir + "/" + boundName
  onExited(0)
  assert.equal(patches.length, 1, "late output after timeout never updates the draft")
  assert.equal(lifecycle.deleteQueue.at(-1), boundName)
  assert.equal(lifecycle.capturePending, false)
  assert.equal(lifecycle.capturing, false)
  assert(errors.includes("Screenshot capture timed out."))
  assert(summons > 0)
  console.log("ok: capture revisions, overlap guard, timeout and late-output draft behavior are preserved")
  // Connect real helper completion results to the actual QML exit callback.
  assert(Number.isInteger(helperTimeoutResult.status) && helperTimeoutResult.status > 0,
    "real shortened helper deadline returns a nonzero exit status, not a harness timeout")
  for (const completion of [
    { name: "current timeout", result: helperTimeoutResult, stale: false,
      errors: ["Screenshot capture failed or timed out. Please try again."], summons: 1 },
    { name: "empty success cancellation", result: cancellation, stale: false, errors: [], summons: 1 },
    { name: "stale timeout", result: helperTimeoutResult, stale: true, errors: [], summons: 0 }
  ]) {
    const feedback = captureContext(fixture()), feedbackErrors = [], feedbackPatches = []
    const draft = { title: "Existing draft", attachmentPath: "screenshot-existing.png" }
    const existingAttachment = path.join(feedback.screenshotDir, draft.attachmentPath)
    fs.writeFileSync(existingAttachment, "existing screenshot", { mode: 0o600 })
    let feedbackSummons = 0, deadlineStops = 0
    Object.assign(feedback, { draftRevision: completion.stale ? 8 : 7, captureRevision: 7,
      capturePending: true, capturing: true, capturePath: completion.result.stdout.trim().split("\n").at(-1),
      captureDirProcess: { running: false }, captureKillDeadline: { stop() {} },
      captureDeadline: { stop() { deadlineStops++ } },
      updateDraft: patch => { feedbackPatches.push(patch); Object.assign(draft, patch) },
      reportError: error => feedbackErrors.push(error), summon: () => feedbackSummons++ })
    const exited = vm.runInContext("(" + source.slice(exitStart + "    onExited: ".length, exitEnd + 6) + ")", feedback)
    exited(completion.result.status)
    assert.deepEqual(feedbackErrors, completion.errors, completion.name + " has correct visible failure feedback")
    assert.deepEqual(draft, { title: "Existing draft", attachmentPath: "screenshot-existing.png" }, completion.name + " preserves the existing draft")
    assert.equal(fs.readFileSync(existingAttachment, "utf8"), "existing screenshot", completion.name + " preserves the existing attachment")
    assert.deepEqual(feedbackPatches, [], completion.name + " never mutates the draft")
    assert.equal(feedback.deleteQueue.length, 0, completion.name + " never queues existing attachment deletion")
    assert.equal(feedbackSummons, completion.summons, completion.name + " only summons the current draft")
    assert.equal(deadlineStops, 1)
    assert.equal(feedback.capturePending, false)
    assert.equal(feedback.capturing, false)
    assert.equal(feedback.captureRevision, -1)
    assert.equal(feedback.capturePath, "")
  }
  console.log("ok: actual helper timeout reports current failure without draft loss; empty cancellation and stale timeout stay silent")
  fs.unlinkSync(path.join(bin, "stat"))
  const prepRecord = path.join(root, "prepare.ready")
  fs.writeFileSync(path.join(bin, "stat"), `#!/usr/bin/bash
if [[ \${!#} == /dev/fd/9 ]]; then
 printf '%s' 'ready' > "$TEST_PREP_RECORD"
 sleep 0.1
fi
exec /usr/bin/stat "$@"
`, { mode: 0o700 })
  const preparing = captureContext(fixture())
  const prep = spawn(preparing.command[0], preparing.command.slice(1), {
    env: environment(preparing.screenshotDir, { TEST_PREP_RECORD: prepRecord }), stdio: "ignore"
  })
  const prepExited = new Promise((resolve, reject) => { prep.on("error", reject); prep.on("exit", resolve) })
  try {
    const until = Date.now() + 2000
    while (!fs.existsSync(prepRecord) && Date.now() < until) await pause(10)
    assert(fs.existsSync(prepRecord), "validated staging preparation reached before cancellation")
    prep.kill("SIGTERM")
    await prepExited
    assert.deepEqual(fs.readdirSync(preparing.screenshotDir), [], "cancellation during verified staging preparation must remove the owned staging directory")
  } finally {
    if (prep.exitCode === null && prep.signalCode === null) prep.kill("SIGKILL")
    await prepExited
    fs.unlinkSync(path.join(bin, "stat")); fs.symlinkSync("/usr/bin/stat", path.join(bin, "stat"))
  }
  console.log("ok: cancellation during verified staging preparation leaves no owned temporary directory")
  fs.unlinkSync(path.join(bin, "timeout"))
  const launchRecord = path.join(root, "launch.ready"), launchToolRecord = path.join(root, "launch-tool.json")
  fs.writeFileSync(path.join(bin, "timeout"), `#!/usr/bin/bash
printf '%s' "$BASHPID" > "$TEST_LAUNCH_RECORD"
sleep 0.1
exec /usr/bin/timeout "$@"
`, { mode: 0o700 })
  const launching = captureContext(fixture())
  const launch = spawn(launching.command[0], launching.command.slice(1), {
    env: environment(launching.screenshotDir, { TEST_LAUNCH_RECORD: launchRecord, CAPTURE_SCENARIO: "hang",
      CAPTURE_RECORD: launchToolRecord, GRANDCHILD_SCRIPT: grandchildScript }), stdio: "ignore"
  })
  const launchExited = new Promise((resolve, reject) => { launch.on("error", reject); launch.on("exit", resolve) })
  let launchIdentity
  try {
    const ready = Date.now() + 2000
    while (!fs.existsSync(launchRecord) && Date.now() < ready) await pause(10)
    assert(fs.existsSync(launchRecord), "controlled timeout launch reached before group registration")
    const pid = Number(fs.readFileSync(launchRecord, "utf8"))
    const fields = fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].split(" ")
    launchIdentity = { pid, start: fields[19] }
    launch.kill("SIGTERM")
    const stopped = Date.now() + 1800
    while (launch.exitCode === null && launch.signalCode === null && Date.now() < stopped) await pause(10)
    assert(launch.exitCode !== null || launch.signalCode !== null, "cancellation during group registration must not wait for the full capture deadline")
    await launchExited
    assert.deepEqual(fs.readdirSync(launching.screenshotDir), [])
  } finally {
    // If red blocks startup cancellation, terminate only its now-established,
    // fixture-owned timeout group. Never signal its initial inherited group.
    if (launchIdentity) {
      const { pid, start } = launchIdentity
      try {
        const fields = fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].split(" ")
        if (Number(fields[2]) === pid && fields[19] === start) process.kill(pid, "SIGTERM")
      } catch (error) { if (error.code !== "ENOENT" && error.code !== "ESRCH") throw error }
    }
    if (fs.existsSync(launchToolRecord)) {
      const owned = JSON.parse(fs.readFileSync(launchToolRecord, "utf8"))
      for (const pid of [owned.pid, owned.child]) if (alive(pid)) try { process.kill(pid, "SIGKILL") } catch (error) { if (error.code !== "ESRCH") throw error }
    }
    const cleanupDeadline = Date.now() + 1500
    while (launch.exitCode === null && launch.signalCode === null && Date.now() < cleanupDeadline) await pause(10)
    if (launch.exitCode === null && launch.signalCode === null) launch.kill("SIGKILL")
    await launchExited
    fs.unlinkSync(path.join(bin, "timeout")); fs.symlinkSync("/usr/bin/timeout", path.join(bin, "timeout"))
  }
  console.log("ok: cancellation during verified child-group registration stays within parent grace")
  fs.unlinkSync(path.join(bin, "timeout"))
  const slowRecord = path.join(root, "slow-launch.ready"), slowCalled = path.join(root, "slow-launch.called")
  fs.writeFileSync(path.join(bin, "timeout"), `#!/usr/bin/bash
printf '%s' "$BASHPID" > "$TEST_LAUNCH_RECORD"
sleep 0.35
exec /usr/bin/timeout "$@"
`, { mode: 0o700 })
  const slow = captureContext(fixture())
  const slowChild = spawn(slow.command[0], slow.command.slice(1), {
    env: environment(slow.screenshotDir, { TEST_LAUNCH_RECORD: slowRecord, CAPTURE_CALLED: slowCalled,
      CAPTURE_CONTENT: "capture must never run" }), stdio: "ignore"
  })
  const slowExited = new Promise((resolve, reject) => { slowChild.on("error", reject); slowChild.on("exit", resolve) })
  let slowIdentity
  try {
    const ready = Date.now() + 2000
    while (!fs.existsSync(slowRecord) && Date.now() < ready) await pause(10)
    assert(fs.existsSync(slowRecord))
    const pid = Number(fs.readFileSync(slowRecord, "utf8"))
    const fields = fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].split(" ")
    slowIdentity = { pid, start: fields[19] }
    const stopped = Date.now() + 1800
    while (slowChild.exitCode === null && slowChild.signalCode === null && Date.now() < stopped) await pause(10)
    assert(slowChild.exitCode !== null || slowChild.signalCode !== null, "failed group registration must stop promptly, not wait 290s")
    await slowExited
    assert.notEqual(slowChild.exitCode, 0)
    assert(!fs.existsSync(slowCalled), "unverified startup must never launch the screenshot tool")
    assert.deepEqual(fs.readdirSync(slow.screenshotDir), [])
  } finally {
    if (slowIdentity) {
      const { pid, start } = slowIdentity
      try {
        const fields = fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].split(" ")
        if (Number(fields[2]) === pid && fields[19] === start) process.kill(pid, "SIGTERM")
      } catch (error) { if (error.code !== "ENOENT" && error.code !== "ESRCH") throw error }
    }
    const cleanupDeadline = Date.now() + 1500
    while (slowChild.exitCode === null && slowChild.signalCode === null && Date.now() < cleanupDeadline) await pause(10)
    if (slowChild.exitCode === null && slowChild.signalCode === null) slowChild.kill("SIGKILL")
    await slowExited
    fs.unlinkSync(path.join(bin, "timeout")); fs.symlinkSync("/usr/bin/timeout", path.join(bin, "timeout"))
  }
  console.log("ok: failed group registration cannot launch a screenshot or leave owned staging")
  console.log("test_capture: ok")
} finally {
  fs.rmSync(root, { recursive: true, force: true })
}
}
main().catch(error => { console.error(error); process.exitCode = 1 })
