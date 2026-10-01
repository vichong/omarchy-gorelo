// Execute selected, actual Service functions and its coordinator wiring. This
// models only ListModel and backend/time boundaries, not a general QML engine.
const fs = require("fs"), vm = require("vm"), path = require("path")
const {loadModule, assert, equal, done} = require("./helpers")
const Api = loadModule("Api.js"), Model = loadModule("Model.js"), Coordinator = loadModule("Coordinator.js")
function listModel() {
  const items = []
  return {get count() {return items.length}, get(i) {return items[i]}, insert(i,t) {items.splice(i,0,t)},
    set(i,t) {items[i]=t}, move(a,b) {items.splice(b,0,items.splice(a,1)[0])}, remove(i,n) {items.splice(i,n)}, clear(){items.length=0}, append(t){items.push(t)}}
}
const source = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
function functions(names) {
  return names.map(name => {
    const start = source.indexOf("  function " + name + "(")
    if (start < 0) throw Error(name)
    const lineEnd = source.indexOf("\n", start)
    if (source.slice(start,lineEnd).endsWith(" }")) return source.slice(start,lineEnd)
    const tail = source.slice(lineEnd)
    const end = tail.search(/^  }$/m)
    return source.slice(start,lineEnd+end+3)
  }).join("\n")
}
function setup() {
  const writes=[], detail=[], polls=[], ticketSearch=[], deviceSearch=[], later=[], notices=[]
  const c = {
    Api, Model, Coordinator, Date, Number, String, Object, JSON, Math, parseInt, isNaN,
    Qt: {callLater(cb) {later.push(cb)}},
    connected:true, hasKey:true, phase:"connected", generation:1, statusRevision:0,
    statuses:[{Id:1,Name:"Open"},{Id:5,Name:"Closed"},{Id:6,Name:"Escalated",AskForReason:true}],
    effectiveStatusIds:[1], effectiveTechnicianId:1, effectiveTechnicianName:"Tech",
    activeTab:"mine", mineTickets:[], allTickets:[], searchResults:[], devices:[], deviceHits:[], currentDeviceResults:[],
    searchQuery:"", searchActive:false, searching:false, deviceSearching:false,
    searchSerial:0, searchRequests:[], searchPendingCount:0, searchPendingQuery:"", searchError:"", deviceSearchError:"",
    rows:listModel(), deviceRows:listModel(), rowsRevision:0, ticketRevision:0, deviceDisplayLimit:8, deviceMatchCount:0,
    searchDebounce:{stop(){}}, rowContext(){return {clientNames:{1:"Acme"},technicianId:1}},
    urlFor(){return ""}, urlForDevice(){return ""}, rowsAboutToChange(){}, toast(s){notices.push(s)},
    pollSerial:0, polling:false, pollRequested:false, notify:false, firstPollDone:true, pollBackoff:0, mineIndex:{},
    clearError(){}, setError(kind,error){c.lastError=error},
    backend:{patchTicket(id,patch,cb){writes.push({id,patch,cb})}, getTicket(id,cb){detail.push({id,cb})},
      listTickets(params,cb){polls.push({params,cb})}, searchTickets(q,cb){ticketSearch.push({q,cb});return {abort(){}}},
      searchDevices(q,cb){deviceSearch.push({q,cb});return {abort(){}}}}
  }
  c.root=c
  vm.createContext(c)
  vm.runInContext(functions(["allDevices","rebuildRows","syncRows","indexOfTicket","indexOfDevice","ticketFor","setStatus","applyConfirmedTicket","refreshAfterMutation","poll","runSearch","abortSearchRequests","finishSearchRequest","leaveSearch","showMoreDevices"]), c)
  const wiring = source.match(/property var statusCoordinator: (Coordinator\.create\([\s\S]*?\n  }\))/)[1]
  c.statusCoordinator=vm.runInContext(wiring,c)
  return {c,writes,detail,polls,ticketSearch,deviceSearch,later,notices}
}
const ticket={Id:"a",Number:123,Title:"Printer",ClientId:1,LeadAssigneeId:1,Status:{Id:1,Name:"Open"}}
const h=setup(), c=h.c
c.mineTickets=[ticket]; c.allTickets=[ticket]; c.rebuildRows()
c.poll(); c.setStatus("a",5)
equal(c.statusCoordinator.pending("a"),"Closing…","real wiring shows service pending")
h.writes[0].cb({ok:true})
equal(c.rows.count,0,"service removes confirmed closed without waiting for poll")
equal(h.notices,["Ticket #123 closed"],"service toasts once")
h.polls[0].cb({ok:true,data:[ticket]})
equal(c.rows.count,0,"in-flight old poll cannot resurrect removed ticket")
h.later.shift()()
h.polls[1].cb({ok:false,kind:"network",error:"offline"})
equal(c.rows.count,0,"poll failure never reinstates known stale status")
const custom=setup()
custom.c.effectiveStatusIds=[1,5]; custom.c.mineTickets=[ticket]; custom.c.rebuildRows()
custom.c.setStatus("a",5); custom.writes[0].cb({ok:true})
equal(custom.c.rows.get(0).statusName,"Closed","custom queue filter retains closed with new label")
const fail=setup()
fail.c.mineTickets=[ticket]; fail.c.rebuildRows(); fail.c.setStatus("a",5)
fail.writes[0].cb({ok:false,kind:"api",status:400,error:"New cannot be selected manually."})
equal(fail.c.rows.get(0).statusId,1,"failed real wiring leaves confirmed dropdown record")
assert(fail.c.actionError.includes("New cannot"),"service surfaces Notifications message")
const search=setup(), sc=search.c
sc.mineTickets=[ticket]; sc.searchQuery="Acme"; sc.runSearch()
equal(sc.rows.count,1,"Enter preserves local-only ticket matches while searching")
search.ticketSearch[0].cb({ok:true,data:[]}); search.deviceSearch[0].cb({ok:true,data:[]})
equal(sc.rows.count,1,"Enter preserves local-only matches after narrow server response")
sc.searchQuery="Printer"; sc.leaveSearch(); sc.runSearch()
search.ticketSearch[1].cb({ok:true,data:[ticket]})
sc.setStatus("a",5)
search.writes[0].cb({ok:true})
equal(sc.rows.get(0).statusName,"Closed","all-status search retains confirmed closed ticket")
search.ticketSearch[1].cb({ok:true,data:[ticket]})
equal(sc.rows.get(0).statusName,"Closed","pre-mutation ticket search cannot undo local status")
search.ticketSearch[2].cb({ok:false,error:"offline"}); search.deviceSearch[2].cb({ok:false,error:"offline"})
equal(sc.rows.count,1,"failed background search retains useful results")
sc.devices=Array.from({length:19},(_,i)=>({Id:"d"+i,Name:"PC-"+i,Status:{Id:2}}))
sc.searchQuery="PC";sc.leaveSearch();sc.rebuildRows()
equal([sc.deviceRows.count,sc.deviceMatchCount],[8,19],"eight devices is presentation batch")
sc.showMoreDevices();equal(sc.deviceRows.count,16,"show more reveals retrieved local matches")
sc.runSearch();const old=search.deviceSearch[3]
sc.searchQuery="Other";sc.leaveSearch();sc.runSearch()
old.cb({ok:true,data:[{Id:"stale",Name:"Other stale"}]})
equal(sc.deviceHits.length,0,"query changes reject stale device response")
search.deviceSearch[4].cb({ok:true,data:[{Id:"remote",Name:"Other",Status:{Id:3}}],pagination:{HasMore:true}})
equal(sc.deviceRows.get(0).searchSource,"Gorelo result","current-query server matches distinct from older cache")
assert(sc.deviceSearchTruncated,"HasMore retained for honest refine label")
const reason=setup()
reason.c.mineTickets=[ticket];reason.c.rebuildRows();reason.c.setStatus("a",6)
equal(reason.writes.length,0,"service reason-required choice makes no PATCH")
equal(reason.c.rows.get(0).statusId,1,"reason handoff retains confirmed record")
const ambiguous=setup()
ambiguous.c.mineTickets=[ticket];ambiguous.c.rebuildRows();ambiguous.c.setStatus("a",5)
ambiguous.writes[0].cb({ok:false,kind:"network",error:"timeout"})
equal(ambiguous.c.rows.count,1,"timeout retains row pending detail read")
ambiguous.detail[0].cb({ok:true,data:ticket})
equal(ambiguous.c.rows.get(0).statusId,1,"authoritative unchanged status keeps failed/ambiguous ticket visible")
equal(ambiguous.notices.length,0,"unconfirmed target never toasts success")
// Payload fixtures use the independently verified CreateCommentCommand contract.
const comment=setup(), cc=comment.c, sent=[]
vm.runInContext(functions(["addPrivateNote", "createTicket"]),cc)
cc.pendingActions=0; cc.backend.addComment=(id,payload,cb)=>sent.push({id,payload,cb})
cc.addPrivateNote("a", "<private> & note")
equal(sent[0].payload,{ConversationTypeId:2,Body:"&lt;private&gt; &amp; note",CreatedByName:"Tech"},"private note uses only published comment fields")
cc.creating=false;cc.demoBackend={};
cc.draft={title:" Test ",clientId:1,description:"Description",priorityId:3,attachmentPath:"screenshot-test.png"}
cc.createDefaults={statusId:1,groupId:1,typeId:1};cc.clientNames={1:"Acme"}
cc.effectiveDefaultStatusId=1;cc.effectiveDefaultGroupId=1;cc.effectiveDefaultTypeId=1
let createBody, createCb, uploadId, uploadCb
cc.backend.createTicket=(body,cb)=>{createBody=body;createCb=cb}
cc.backend.uploadAttachment=(id,path,cb)=>{uploadId=id;uploadCb=cb}
cc.finishCreate=(id,warning)=>{cc.finished={id,warning}}
cc.createTicket()
equal(createBody,{Title:"Test",ClientId:1,StatusId:1,GroupId:1,TypeId:1,PriorityId:3,IsUnread:false,Description:"Description",LeadAssigneeId:1,CreatedByName:"Tech"},"create payload preserves documented fields")
createCb({ok:true,data:{Id:"12345678-1234-1234-1234-123456789abc"}})
equal(uploadId,"12345678-1234-1234-1234-123456789abc","screenshot target is newly-created ID")
uploadCb({ok:true,data:{Name:"shot.png",Url:"https://attachment.example/expiring"}})
equal(sent[1].payload,{ConversationTypeId:2,Body:"Screenshot",Attachments:[{Name:"shot.png",Url:"https://attachment.example/expiring"}],CreatedByName:"Tech"},"uploaded Name/Url passed into private attachment comment without extra fields")
sent[1].cb({ok:true});equal(cc.finished.warning,"","create finishes only after private comment")
const isolatedFilter=setup(), dc=isolatedFilter.c
const Demo=loadModule("Demo.js")
dc.statuses=Demo.demoReference().statuses;dc.statusIds=[17,18];dc.demoBackend={};dc.backend=dc.demoBackend
const filterExpression=source.match(/readonly property var effectiveStatusIds: ([^\n]+(?:\n    \?[^\n]+)?)/)[1]
equal(vm.runInContext(filterExpression,dc),[1,2,3,4,6],"demo ignores persisted live status IDs that do not exist in fixtures")
equal(Model.statusQueue(Demo.demoTickets(Date.parse("2026-10-02T10:00:00Z")),vm.runInContext(filterExpression,dc)).length,13,"live [17,18] does not empty demo ticket queue")
dc.backend={};equal(vm.runInContext(filterExpression,dc),[17,18],"live custom filters stay unchanged")
const membership=setup(), mc=membership.c
mc.searchQuery="accent query";mc.runSearch()
membership.ticketSearch[0].cb({ok:true,data:[{...ticket,Title:"Different server collation"}]})
equal(mc.rows.count,1,"service retains server-only keyword match")
mc.applyConfirmedTicket({...ticket,Status:{Id:5,Name:"Closed"}})
equal(mc.rows.get(0).statusName,"Closed","confirmed status updates existing server membership even without local match")
mc.applyConfirmedTicket({...ticket,Id:"unrelated",Title:"Another ticket"})
equal(mc.searchResults.map(t=>t.Id),["a"],"confirmed mutation never adds unrelated ticket to current server membership")
const fresh=setup(), fc=fresh.c
fc.searchActive=true;fc.searchQuery="Printer";fc.effectiveStatusIds=[1,5]
fc.searchResults=[{...ticket,Title:"Old search",UpdatedOn:"2026-10-02T10:00:00Z"}]
fc.mineTickets=[{...ticket,Title:"Fresh mine",LeadAssigneeId:2,UpdatedOn:"2026-10-02T10:02:00Z"}]
fc.allTickets=[{...ticket,Title:"Middle all",UpdatedOn:"2026-10-02T10:01:00Z"}]
equal(fc.ticketFor("a").Title,"Fresh mine","ticketFor chooses latest poll/search snapshot rather than first source")
fc.setStatus("a",5);fresh.writes[0].cb({ok:true})
equal(fc.searchResults[0].Title,"Fresh mine","successful status update built from freshest snapshot")
equal(fc.mineTickets.length,0,"older search assignment cannot restore ticket to Mine during status update")
const ties=setup(), tc=ties.c
const timestamp="2026-10-02T12:00:00Z"
tc.allTickets=[{...ticket,Title:"All",UpdatedOn:timestamp}]
tc.mineTickets=[{...ticket,Title:"Mine",UpdatedOn:timestamp}]
tc.searchResults=[{...ticket,Title:"Search",UpdatedOn:timestamp}]
equal(tc.ticketFor("a").Title,"Search","ticketFor tie uses same search precedence as displayed records")
tc.searchResults=[];equal(tc.ticketFor("a").Title,"Mine","ticketFor queue tie chooses Mine consistently")
const oversized=setup(), oc=oversized.c
oc.searchQuery="x".repeat(201);oc.runSearch()
equal([oc.searchError,oc.deviceSearchError].filter(Boolean).length,1,"oversized combined query presents one error message")
equal([oversized.ticketSearch.length,oversized.deviceSearch.length],[0,0],"oversized combined query sends neither server request")
const displayed=setup(), pc=displayed.c
pc.searchActive=true;pc.searchQuery="remote keyword"
pc.mineTickets=[{...ticket,Title:"Older Mine",UpdatedOn:"2026-10-02T10:00:00Z"}]
pc.allTickets=[{...ticket,Title:"Newest All poll",UpdatedOn:"2026-10-02T10:02:00Z"}]
pc.searchResults=[{...ticket,Title:"Older Search",UpdatedOn:"2026-10-02T10:01:00Z"}]
pc.rebuildRows()
equal(pc.rows.get(0).title,"Newest All poll","display and mutation snapshot agree on freshest duplicate across both poll queues and search")
pc.mineTickets=[];pc.rebuildRows()
equal(pc.rows.get(0).title,"Newest All poll","server-only membership also uses newer poll copy outside active local queue")
const revealing=setup(), rc=revealing.c
rc.searchQuery="PC";rc.devices=Array.from({length:19},(_,i)=>({Id:"r"+i,Name:"PC-"+i}))
rc.rebuildRows()
let matchCount=rc.deviceMatchCount;const completenessChanges=[]
Object.defineProperty(rc,"deviceMatchCount",{get(){return matchCount},set(value){if(value!==matchCount)completenessChanges.push(value);matchCount=value}})
rc.showMoreDevices()
equal(completenessChanges,[],"growing presentation batch never temporarily hides keyboard Show more by resetting match count")
done("test_service")
