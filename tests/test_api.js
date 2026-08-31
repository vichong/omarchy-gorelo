const { loadModule, assert, equal, done } = require("./helpers")
const Api = loadModule("Api.js")

equal(Api.baseUrl("aue"), "https://api.aue.gorelo.io", "aue base url")
equal(Api.baseUrl("bogus"), "https://api.usw.gorelo.io", "unknown region falls back to usw")
assert(Api.isRegion("usw") && !Api.isRegion("eu"), "region validation")
equal(Api.errorResult("network", "offline"),
  { ok: false, status: 0, kind: "network", error: "offline", code: "", data: null, pagination: null },
  "shared error result shape")

equal(Api.query({ PageSize: 100, StatusIds: [1, 2], Empty: "", None: null, List: [] }),
  "?PageSize=100&StatusIds=1%2C2", "query skips empty values and joins lists")

const ok = Api.parseResponse(200, JSON.stringify({ IsSuccess: true, Data: [1], DataContext: { Pagination: { HasMore: true, NextCursor: "abc" } } }))
assert(ok.ok && ok.data.length === 1, "success parse")
equal(Api.nextCursor(ok.pagination), "abc", "next cursor from pagination")
equal(Api.nextCursor({ HasMore: false, NextCursor: "x" }), "", "no cursor when HasMore is false")

const denied = Api.parseResponse(401, "")
equal([denied.ok, denied.kind], [false, "credential"], "401 is a credential error")
equal(Api.parseResponse(403, "").kind, "credential", "403 is a credential error")
equal(Api.parseResponse(429, "").kind, "ratelimit", "429 is rate limit")
equal(Api.parseResponse(0, "").kind, "network", "status 0 is network")
const apiErr = Api.parseResponse(400, JSON.stringify({ IsSuccess: false, Notifications: [{ Code: "1", Message: "Bad title" }] }))
equal([apiErr.kind, apiErr.error], ["api", "Bad title"], "API notification messages surface")
equal(apiErr.code, "1", "first notification code surfaces separately")
equal(Api.parseResponse(500, "not json").error, "Gorelo API error (HTTP 500).", "non-JSON body")
equal(Api.parseResponse(200, "").kind, "protocol", "empty 2xx body is a protocol error")
equal(Api.parseResponse(200, "<html>nope</html>").kind, "protocol", "HTML 2xx body is a protocol error")
equal(Api.parseResponse(200, JSON.stringify({ Data: [] })).kind, "protocol", "2xx wrapper must explicitly succeed")
equal(Api.parseResponse(200, JSON.stringify({ IsSuccess: false })).kind, "protocol", "failed 2xx wrapper is a protocol error")

const statuses = [
  { Id: 3, Name: "Closed", SortOrder: 9 }, { Id: 1, Name: "New", SortOrder: 1 },
  { Id: 2, Name: "In progress", SortOrder: 2 }, { Id: 4, Name: "Resolved", SortOrder: 8 },
  { Id: 5, Name: "Cancelled", SortOrder: 7 }
]
equal(Api.defaultStatusIds(statuses), [1, 2], "closed-looking statuses excluded by default")
equal(Api.sortStatuses(statuses).map(s => s.Id), [1, 2, 5, 4, 3], "statuses sort by SortOrder")

const names = Api.nameMap([{ Id: 7, Name: "Acme" }, { Id: "constructor", Name: "x" }])
equal(names["7"], "Acme", "name map by id")
assert(Object.getPrototypeOf(names) === null, "name map is prototype-free")

equal(Api.userDisplayName({ FirstName: "Ada", LastName: "Lovelace" }), "Ada Lovelace", "user display name")
equal(Api.userDisplayName({ Email: "a@b.c" }), "a@b.c", "user display name falls back to email")

equal(Api.ticketUrl("https://x/{id}/{number}/{displayNumber}", { Id: "a b", Number: 12, DisplayNumber: "T#12" }),
  "https://x/a%20b/12/T%2312", "ticket url template substitution is encoded")
equal(Api.deviceUrl("https://x/{id}?name={name}", { Id: "a b", Name: "PC #1" }),
  "https://x/a%20b?name=PC%20%231", "device url template substitution is encoded")
equal(Api.deviceUrl("", { Id: "d1", Name: "host" }),
  "https://app.gorelo.io/asset/device-detail/d1?hostName=host", "device url has a default")
equal(Api.escapeHtml("<b>&\n\"x\""), "&lt;b&gt;&amp;<br>&quot;x&quot;", "html escape")
equal(Api.validTicketList([{ Id: 1 }, null, { NoId: true }, "x"]).length, 1, "ticket list validation")

done("test_api")
