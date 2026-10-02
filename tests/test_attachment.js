// Shell boundary tests: real helper/private files, fake curl, no network.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync, spawn } = require("node:child_process")

const helper = path.resolve(__dirname, "../scripts/gorelo-attachment")
const root = fs.mkdtempSync(path.join(os.tmpdir(), "gorelo-attachment-test-"))
const bin = path.join(root, "bin")
const uuid = "ABCDEF01-2345-6789-abcd-0123456789ef"
const url = "https://api.aue.gorelo.io/v1/attachments"
const key = "test-only-api-key"
const config = `header = "X-Api-Key: ${key}"\n`
const cap = 20 * 1024 * 1024
let cases = 0
fs.mkdirSync(bin, { mode: 0o700 })
fs.writeFileSync(path.join(bin, "curl"), `#!${process.execPath}
const fs = require('node:fs')
const args = process.argv.slice(2)
const stdin = fs.readFileSync(0, 'utf8')
if (process.env.REPLACE_FILE) {
  fs.renameSync(process.env.REPLACE_FILE, process.env.REPLACE_FILE + '.original')
  fs.writeFileSync(process.env.REPLACE_FILE, 'replacement must survive')
}
const fd = fs.openSync('/dev/fd/3', 'r')
const fileSize = fs.fstatSync(fd).size
const buffer = Buffer.alloc(64)
const length = fs.readSync(fd, buffer, 0, buffer.length, 0)
const file = buffer.subarray(0, length).toString('utf8')
fs.closeSync(fd)
if (process.env.CURL_HANG) process.on('SIGTERM', () => {
  fs.writeFileSync(process.env.CURL_RECORD + '.terminated', 'SIGTERM')
  process.exit(143)
})
fs.writeFileSync(process.env.CURL_RECORD, JSON.stringify({ args, stdin, file, fileSize,
  locale: { LANG: process.env.LANG, LANGUAGE: process.env.LANGUAGE, LC_ALL: process.env.LC_ALL } }))
process.stdout.write('{"Name":"shot.png","Url":"test-only"}\\n200')
if (process.env.CURL_HANG) setInterval(() => {}, 1000)
else process.exit(Number(process.env.CURL_EXIT || 0))
`, { mode: 0o700 })

function fixture() {
  const dir = fs.mkdtempSync(path.join(root, "private-"))
  fs.chmodSync(dir, 0o700)
  const name = "screenshot-test.png"
  const file = path.join(dir, name)
  fs.writeFileSync(file, "private screenshot", { mode: 0o600 })
  return { dir, name, file, record: path.join(root, `curl-${cases++}.json`) }
}
function run(f, { id = uuid, mode = "upload", args, env = {} } = {}) {
  const command = args || (mode === "delete" ? [mode, f.dir, f.name]
    : [mode, f.dir, f.name, url, "1048576", "30", String(cap), id])
  return spawnSync(helper, command, {
    input: config, encoding: "utf8", timeout: 5000,
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CURL_RECORD: f.record, ...env }
  })
}
function test(name, fn) {
  fn()
  console.log("ok: " + name)
}

async function main() {
  try {
    test("upload and delete work under localized metadata without changing child locale", () => {
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
      const locale = { LANG: "en_US.utf8", LANGUAGE: "de", LC_ALL: "en_US.utf8" }
      try {
        const operations = ["upload", "delete"].map(mode => {
          const f = fixture()
          return { mode, f, result: run(f, { mode, env: locale }) }
        })
        assert.deepEqual(operations.map(({ mode, result }) => ({ mode, status: result.status })),
          [{ mode: "upload", status: 0 }, { mode: "delete", status: 0 }], "localized private attachment operations succeed")
        for (const { mode, f, result } of operations) {
          assert(!fs.existsSync(f.file), mode + " still cleans the bound attachment")
          if (mode === "delete") assert(!fs.existsSync(f.record), "localized deletion never calls curl")
          else {
            const sent = JSON.parse(fs.readFileSync(f.record, "utf8"))
            assert.equal(sent.args[0], "-q", "locale isolation retains first-argument curl config isolation")
            assert.equal(sent.stdin, config)
            assert(!sent.args.join(" ").includes(key))
            assert.equal(sent.file, "private screenshot")
            assert.deepEqual(sent.locale, locale, "stat locale isolation is not exported to curl")
            assert.equal(result.stdout, '{"Name":"shot.png","Url":"test-only"}\n200')
          }
        }
      } finally { fs.unlinkSync(path.join(bin, "stat")) }
    })
    if (process.argv.includes("--locale-only")) return
    test("uploads a UUID-bound Ticket with literal metadata and stdin-only credentials", () => {
      const f = fixture()
      const result = run(f)
      assert.equal(result.status, 0, result.stderr)
      const sent = JSON.parse(fs.readFileSync(f.record, "utf8"))
      assert.equal(sent.args[0], "-q", "upload disables ambient curl config before all other arguments")
      assert.equal(sent.args.at(-1), url)
      assert.deepEqual(sent.args.filter((_, i) => sent.args[i - 1] === "--form-string"),
        ["itemType=Ticket", `itemId=${uuid}`])
      assert.deepEqual(sent.args.filter((_, i) => sent.args[i - 1] === "-F"),
        ["file=@/dev/fd/3;filename=screenshot-test.png;type=image/png"])
      // Multipart selects POST unless overridden explicitly.
      for (const option of ["-X", "--request"]) {
        if (sent.args.includes(option)) assert.equal(sent.args[sent.args.indexOf(option) + 1], "POST")
      }
      assert(!sent.args.includes("-G") && !sent.args.includes("--get"))
      assert(!sent.args.includes("-L") && !sent.args.includes("--location"))
      assert.equal(sent.args[sent.args.indexOf("--proto") + 1], "=https")
      assert.equal(sent.args[sent.args.indexOf("--max-filesize") + 1], "1048576")
      assert.equal(sent.args[sent.args.indexOf("--max-time") + 1], "30")
      assert.equal(sent.args[sent.args.indexOf("-K") + 1], "-")
      assert.equal(sent.stdin, config)
      assert(!sent.args.join(" ").includes(key))
      assert(!result.stdout.includes(key) && !result.stderr.includes(key))
      assert.equal(sent.file, "private screenshot")
      assert.equal(result.stdout, '{"Name":"shot.png","Url":"test-only"}\n200')
      assert(!fs.existsSync(f.file), "uploaded inode is cleaned up")
    })
    test("refuses malformed and file-interpolating IDs without calling curl", () => {
      for (const id of ["", "@/etc/passwd", "<secret", "demo-ticket-1042", "abcdef01-2345-6789-abcd-0123456789e",
        "abcdef01-2345-6789-abcd-0123456789egg", "abcdef0123456789abcd0123456789ef",
        uuid + "\n", " " + uuid, uuid + ";x=y"]) {
        const f = fixture()
        assert.equal(run(f, { id }).status, 64, `refuse ${JSON.stringify(id)}`)
        assert(!fs.existsSync(f.record), "no curl or credential disclosure")
        assert(fs.existsSync(f.file), "invalid request leaves caller-owned file alone")
      }
      const f = fixture()
      const oldArgs = ["upload", f.dir, f.name, url, "1048576", "30", String(cap)]
      assert.equal(run(f, { args: oldArgs }).status, 64, "old seven-argument upload is refused")
      assert(!fs.existsSync(f.record))
    })
    test("accepts UUID shape without imposing version or variant bits", () => {
      const f = fixture()
      assert.equal(run(f, { id: "00000000-0000-0000-0000-000000000000" }).status, 0)
      assert(fs.existsSync(f.record))
    })
    test("refuses insecure URLs and invalid numeric bounds", () => {
      for (const overrides of [[3, "http://example.test/v1/attachments"], [4, "0"],
        [4, "-1"], [5, "1.5"], [5, "0"]]) {
        const f = fixture()
        const args = ["upload", f.dir, f.name, url, "1048576", "30", String(cap), uuid]
        args[overrides[0]] = overrides[1]
        assert.equal(run(f, { args }).status, 64)
        assert(!fs.existsSync(f.record))
        assert(fs.existsSync(f.file))
      }
    })
    test("refuses symlinks and nonprivate directories without network or deletion", () => {
      for (const kind of ["file symlink", "directory symlink", "nonprivate directory", "nonregular file"]) {
        const f = fixture()
        if (kind === "file symlink") {
          fs.renameSync(f.file, f.file + ".target")
          fs.symlinkSync(f.file + ".target", f.file)
        } else if (kind === "directory symlink") {
          const original = f.dir
          f.dir += ".link"
          fs.symlinkSync(original, f.dir)
        } else if (kind === "nonprivate directory") {
          fs.chmodSync(f.dir, 0o755)
        } else {
          fs.unlinkSync(f.file)
          fs.mkdirSync(f.file)
        }
        assert.equal(run(f).status, 64, kind)
        assert(!fs.existsSync(f.record), kind + " never reaches curl")
        assert(fs.existsSync(f.file), kind + " is not deleted")
      }
    })
    test("enforces the hard 20 MiB cap and cleans up an oversized attachment", () => {
      const f = fixture()
      fs.truncateSync(f.file, cap + 1)
      assert.equal(run(f).status, 64)
      assert(!fs.existsSync(f.record))
      assert(!fs.existsSync(f.file), "oversized bound inode is removed")
      const exact = fixture()
      fs.truncateSync(exact.file, cap)
      assert.equal(run(exact).status, 0, "exactly 20 MiB remains allowed")
      assert.equal(JSON.parse(fs.readFileSync(exact.record)).fileSize, cap)
      assert(!fs.existsSync(exact.file))
      const relaxed = fixture()
      assert.equal(run(relaxed, { args: ["upload", relaxed.dir, relaxed.name, url,
        "1048576", "30", String(cap + 1), uuid] }).status, 64, "caller cannot relax the cap")
      assert(!fs.existsSync(relaxed.record))
    })
    test("curl failure propagates its exit status and still cleans up", () => {
      const f = fixture()
      assert.equal(run(f, { env: { CURL_EXIT: "28" } }).status, 28)
      assert(fs.existsSync(f.record))
      assert(!fs.existsSync(f.file))
    })
    test("upload stays bound to the verified inode and never deletes a replacement", () => {
      const f = fixture()
      assert.equal(run(f, { env: { REPLACE_FILE: f.file } }).status, 0)
      assert.equal(JSON.parse(fs.readFileSync(f.record)).file, "private screenshot")
      assert.equal(fs.readFileSync(f.file, "utf8"), "replacement must survive")
    })
    test("delete retains its three-argument semantics with no curl", () => {
      const f = fixture()
      assert.equal(run(f, { mode: "delete" }).status, 0)
      assert(!fs.existsSync(f.file))
      assert(!fs.existsSync(f.record))
      const extra = fixture()
      assert.equal(run(extra, { args: ["delete", extra.dir, extra.name, uuid] }).status, 64)
      assert(fs.existsSync(extra.file))
      assert(!fs.existsSync(extra.record))
    })
    // Wait for curl's readiness record before signalling: no timing-dependent race.
    const f = fixture()
    const child = spawn(helper, ["upload", f.dir, f.name, url, "1048576", "30", String(cap), uuid], {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, CURL_RECORD: f.record, CURL_HANG: "1" },
      stdio: ["pipe", "ignore", "pipe"]
    })
    child.stdin.end(config)
    let stderr = ""
    child.stderr.on("data", data => { stderr += data })
    const exited = new Promise((resolve, reject) => {
      child.on("error", reject)
      child.on("exit", (code, signal) => resolve({ code, signal }))
    })
    const watchdog = setTimeout(() => child.kill("SIGTERM"), 5000)
    try {
      const deadline = Date.now() + 3000
      while (!fs.existsSync(f.record) && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 10))
      }
      assert(fs.existsSync(f.record), "fake curl is ready before termination: " + stderr)
      child.kill("SIGTERM")
      const result = await exited
      assert.equal(result.code, 143, stderr)
      assert.equal(result.signal, null)
      assert.equal(fs.readFileSync(f.record + ".terminated", "utf8"), "SIGTERM")
      assert(!fs.existsSync(f.file), "signal forwarding still cleans up the bound file")
      console.log("ok: SIGTERM forwards to curl and cleans up before exit")
    } finally {
      clearTimeout(watchdog)
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGTERM")
        await exited
      }
    }
    console.log("test_attachment: ok")
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}
main().catch(error => { console.error(error); process.exitCode = 1 })
