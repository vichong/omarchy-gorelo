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
    connected:true, hasKey:true, phase:"connected", generation:1, statusRevision:0,createAttachmentPath:"",createAttachmentConsumed:false,pendingNotes:{},noteRevision:0,actionErrors:{},
    statuses:[{Id:1,Name:"Open"},{Id:5,Name:"Closed"},{Id:6,Name:"Escalated",AskForReason:true}],
    effectiveStatusIds:[1], effectiveTechnicianId:1, effectiveTechnicianName:"Tech",
    activeTab:"mine", mineTickets:[], allTickets:[], searchResults:[], localSearchTickets:[], localSearchFull:false, devices:[], deviceHits:[], currentDeviceResults:[], localDeviceResults:[], deviceRequestSerial:0,deviceListOrder:0,deviceHitOrders:{},currentDeviceOrder:0,localDeviceOrders:{},
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
  vm.runInContext(functions(["reportActionError","clearActionError","pendingNote","deviceSnapshot","allDevices","rebuildRows","syncRows","indexOfTicket","indexOfDevice","ticketFor","setStatus","applyConfirmedTicket","refreshAfterMutation","poll","runSearch","abortSearchRequests","finishSearchRequest","leaveSearch","showMoreDevices"]), c)
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
vm.runInContext(functions(["addPrivateNote", "createTicket", "releaseCreateAttachment"]),cc)
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
// Manual replacement is distinct from startup and transient reconnect.
function connectionSetup() {
  const h=setup(), c=h.c, references=[], stored=[], deleted=[]
  const ConfigStore=loadModule("ConfigStore.js")
  Object.assign(c, ConfigStore.parse("").config, {ConfigStore, configLoaded:true,
    technicianId:1,technicianName:"Old tech",statusIds:[1],defaultStatusId:1,defaultGroupId:2,defaultTypeId:3,
    apiKey:"old-key",credentialBusy:false,draftRevision:0,deviceLoadSerial:0,
    pendingConnection:null,pendingLookupRegion:"",allTruncated:false,mineTruncated:false,pendingActions:0,creating:false})
  c.liveBackend=c.backend;c.demoBackend={supersede(){}};c.backend.supersede=()=>{}
  c.backend.loadReference=cb=>references.push(cb)
  c.credentials={busy:false,store(key,region){stored.push({key,region});return true},lookup(){}}
  c.configFile={setText(){}};c.browserLauncher={browserWarning:""};c.reconnectTimer={stop(){},restart(){}}
  c.deleteAttachment=p=>deleted.push(p);c.draft={...Model.emptyDraft(),title:"Old draft",attachmentPath:"screenshot-old.png"}
  c.devicesLoaded=true;c.devices=[{Id:"old-device",Name:"OLD-PC"}]
  c.mineTickets=[ticket];c.allTickets=[ticket];c.searchActive=true;c.searchQuery="Printer";c.searchResults=[ticket];c.rebuildRows()
  Object.defineProperty(c,"effectiveTechnicianId",{get(){return c.technicianId}})
  Object.defineProperty(c,"effectiveStatusIds",{get(){return c.statusIds.length?c.statusIds:Api.defaultStatusIds(c.statuses)}})
  Object.defineProperty(c,"connected",{get(){return c.phase==="connected"}})
  Object.defineProperty(c,"hasKey",{get(){return !!c.apiKey}})
  Object.defineProperty(c,"transientError",{get(){return ["ratelimit","network","protocol","api"].includes(c.lastErrorKind)}})
  vm.runInContext(functions(["applyConnection","keyringReady","keyHasUnsupportedCharacters","currentConfig","saveConfig","applyConfig","clearDraft","releaseCreateAttachment","resetData","supersedeRequests","connect","loadReference","setError","clearError"]),c)
  function keyReady(key) {
    const body=source.match(/onKeyReady: function\(key, keyRegion\) \{([\s\S]*?)\n    }/)[1]
    vm.runInContext('(function(key,keyRegion){'+body+'})("'+key+'","usw")',c)
  }
  return {...h,references,stored,deleted,keyReady}
}
const replacement=connectionSetup(), rep=replacement.c
rep.pollSeconds=120;rep.browserDesktop="/browser.desktop";rep.notify=false
rep.setStatus("a",5);const oldWrite=replacement.writes[0]
rep.applyConnection("usw","new-key")
equal([rep.rows.count,rep.devices.length,rep.searchResults.length,rep.draft.title],[0,0,0,""],"different manual key clears old account data before credential storage completes")
equal([rep.technicianId,rep.technicianName,rep.statusIds,rep.defaultStatusId,rep.defaultGroupId,rep.defaultTypeId],[0,"",[],0,0,0],"manual replacement clears account-specific settings")
equal([rep.pollSeconds,rep.browserDesktop,rep.notify],[120,"/browser.desktop",false],"replacement preserves general preferences")
equal(rep.statusCoordinator.pending("a"),"","replacement clears pending writes immediately")
oldWrite.cb({ok:true});equal(replacement.notices,[],"old mutation cannot confirm during replacement")
equal(replacement.deleted,["screenshot-old.png"],"replacement cleans old draft attachment")
replacement.keyReady("new-key");replacement.references[0]({ok:true,data:{statuses:rep.statuses,users:[],clients:[]}})
if(replacement.polls.length) replacement.polls[0].cb({ok:true,data:[]})
equal(rep.rows.count,0,"successful replacement never restores old-account search membership")
const storeFailure=connectionSetup();storeFailure.c.applyConnection("usw","new-key")
storeFailure.c.setError("credential","Store failed","")
equal([storeFailure.c.rows.count,storeFailure.c.devices.length,storeFailure.c.apiKey],[0,0,""],"failed replacement remains cleared and cannot poll with old key")
for (const mode of ["startup","same-key","reconnect"]) {
  const keep=connectionSetup(), kc=keep.c
  if(mode==="startup") {kc.apiKey="";keep.keyReady("old-key")}
  else if(mode==="same-key") {kc.applyConnection("usw","old-key");keep.keyReady("old-key")}
  else kc.connect()
  equal([kc.technicianId,kc.defaultGroupId,kc.draft.title,kc.devices.length,kc.searchResults.length],[1,2,"Old draft",1,1],mode+" preserves account settings and useful state")
}
const localClose=setup(), lc=localClose.c
lc.mineTickets=[ticket];lc.allTickets=[ticket];lc.searchQuery="Acme";lc.runSearch()
localClose.ticketSearch[0].cb({ok:true,data:[]});localClose.deviceSearch[0].cb({ok:true,data:[]})
lc.setStatus("a",5);localClose.writes[0].cb({ok:true})
equal(lc.rows.count,1,"confirmed close keeps local-only match in active all-status search")
localClose.ticketSearch[1].cb({ok:true,data:[]});localClose.deviceSearch[1].cb({ok:true,data:[]})
equal(lc.rows.count?lc.rows.get(0).statusName:"missing","Closed","empty fresh server search preserves locally matched closed ticket")
lc.runSearch();localClose.ticketSearch[2].cb({ok:false,error:"offline"});localClose.deviceSearch[2].cb({ok:false,error:"offline"})
equal(lc.rows.count,1,"failed subsequent search preserves local-only confirmed ticket")
equal([lc.mineTickets.length,lc.allTickets.length],[0,0],"local search retention does not bypass queue status filters")
lc.applyConfirmedTicket({...ticket,Id:"unrelated",Title:"Another",ClientId:2})
equal(lc.rows.count,1,"confirmed unrelated ticket is not injected into active local membership")
lc.searchQuery="no-match-query";lc.leaveSearch();lc.runSearch()
equal(lc.rows.count,0,"query change clears retained local search membership")
const capUnion=setup(), cu=capUnion.c
cu.searchQuery="Alice";cu.deviceHits=[{Id:"local-user",Name:"UNIQUE-PC",LastLoggedOnUser:"Alice"}];cu.rebuildRows();cu.runSearch()
capUnion.ticketSearch[0].cb({ok:true,data:[]})
capUnion.deviceSearch[0].cb({ok:true,data:Array.from({length:200},(_,i)=>({Id:"server-"+i,Name:"Alice-PC-"+i})),pagination:{HasMore:false}})
cu.deviceDisplayLimit=300;cu.rebuildRows()
equal(cu.deviceMatchCount,201,"Enter retains a valid prior cache-only user match alongside all 200 current device hits")
assert(Array.from({length:cu.deviceRows.count},(_,i)=>cu.deviceRows.get(i).deviceId).includes("local-user"),"Show more can reveal local-only match after 200-ID response")
equal(cu.deviceHits.length,200,"historical hit cache stays bounded independently of current-query union")
cu.searchQuery="different";cu.leaveSearch();cu.rebuildRows()
equal(cu.deviceMatchCount,0,"new query does not retain previous-query union")
function deviceOrderSetup() {
  const h=setup(), loads=[];h.c.devicesLoading=false;h.c.deviceLoadSerial=0
  h.c.backend.listDevices=cb=>loads.push(cb)
  vm.runInContext(functions(["loadDevices"]),h.c)
  return {...h,loads}
}
const newerList=deviceOrderSetup(), nl=newerList.c
nl.searchQuery="PC";nl.runSearch();newerList.ticketSearch[0].cb({ok:true,data:[]})
newerList.deviceSearch[0].cb({ok:true,data:[{Id:"d",Name:"PC",Status:{Id:3},LastLoggedOnUser:"Old user"}]})
nl.loadDevices();newerList.loads[0]({ok:true,data:[{Id:"d",Name:"RENAMED",Status:{Id:2},LastLoggedOnUser:"New user"}]})
nl.searchQuery="New user";nl.leaveSearch();nl.rebuildRows()
equal(nl.deviceMatchCount,1,"later-started list supersedes older direct hit and rematches its new user")
equal(nl.deviceRows.count?nl.deviceRows.get(0).hostName:"missing","RENAMED","newer list exposes renamed device")
const olderList=deviceOrderSetup(), ol=olderList.c
ol.loadDevices();ol.searchQuery="PC";ol.runSearch();olderList.ticketSearch[0].cb({ok:true,data:[]})
olderList.deviceSearch[0].cb({ok:true,data:[{Id:"d",Name:"PC-new",Status:{Id:2},LastLoggedOnUser:"New user"}]})
olderList.loads[0]({ok:true,data:[{Id:"d",Name:"PC-old",Status:{Id:3},LastLoggedOnUser:"Old user"}]})
ol.searchQuery="New user";ol.leaveSearch();ol.rebuildRows()
equal(ol.deviceRows.count?ol.deviceRows.get(0).hostName:"missing","PC-new","older-started list completing later cannot undo newer direct result")
function createSetup() {
  const h=setup(),c=h.c,creates=[],uploads=[],comments=[],finished=[],deleted=[]
  vm.runInContext(functions(["createTicket","finishCreate","clearDraft","updateDraft","releaseCreateAttachment"]),c)
  Object.assign(c,{demoBackend:{},openAfterCreate:false,creating:false,draftRevision:0,
    draft:{title:"Submitted title",clientId:1,description:"first",priorityId:3,attachmentPath:"screenshot-submitted.png"},
    createDefaults:{statusId:1,groupId:1,typeId:1},clientNames:{1:"Acme"},effectiveDefaultStatusId:1,effectiveDefaultGroupId:1,effectiveDefaultTypeId:1})
  c.deleteAttachment=p=>deleted.push(p);c.created=(id,warning,cleared)=>finished.push({id,warning,cleared})
  c.backend.createTicket=(body,cb)=>creates.push({body,cb});c.backend.uploadAttachment=(id,path,cb)=>uploads.push({id,path,cb});c.backend.addComment=(id,body,cb)=>comments.push({id,body,cb})
  return {...h,creates,uploads,comments,finished,deleted}
}
const laterDraft=createSetup(), ld=laterDraft.c
ld.createTicket();ld.clearDraft();ld.updateDraft({title:"Next ticket draft",clientId:1,description:"unsent"})
equal(laterDraft.deleted,[],"Discard cannot delete a submitted screenshot before its pending workflow finishes")
laterDraft.creates[0].cb({ok:true,data:{Id:"created-id"}})
laterDraft.uploads[0].cb({ok:true,data:{Name:"shot",Url:"attachment"}})
ld.updateDraft({description:"unsent newer edit"});laterDraft.comments[0].cb({ok:true})
equal([ld.draft.title,ld.draft.description],["Next ticket draft","unsent newer edit"],"older create/upload/comment completion preserves a newer draft")
equal(laterDraft.finished[0].cleared,false,"older create completion tells overlay not to dismiss newer work")
equal(laterDraft.deleted,["screenshot-submitted.png"],"submitted screenshot cleaned after its workflow, not on intervening Discard")
const matchingDraft=createSetup();matchingDraft.c.createTicket();matchingDraft.creates[0].cb({ok:true,data:{Id:"id"}});matchingDraft.uploads[0].cb({ok:false,error:"offline"})
equal(matchingDraft.c.draft.title,"","unchanged submitted draft clears even after partial upload failure")
assert(matchingDraft.finished[0].warning.includes("Ticket created, but"),"partial upload failure keeps already-created warning")
const staleCreate=createSetup();staleCreate.c.createTicket();staleCreate.c.generation++;staleCreate.creates[0].cb({ok:true,data:{Id:"old-id"}})
equal([staleCreate.uploads.length,staleCreate.finished.length,staleCreate.notices.length],[0,0,0],"old-generation create cannot upload, dismiss or toast in new connection")
// Execute the actual row action handler with a modeled editor/backend.
const noteEdit=setup(), ne=noteEdit.c, notes=[]
vm.runInContext(functions(["addPrivateNote"]),ne);ne.pendingActions=0
ne.backend.addComment=(id,payload,cb)=>notes.push({id,payload,cb})
const editor={row:{gorelo:ne,ticketId:"a"},noteField:{text:"Sent note"}}
vm.createContext(editor)
const rowSource=fs.readFileSync(path.join(__dirname,"..","TicketRow.qml"),"utf8")
const noteClick=rowSource.match(/if \(!row.gorelo \|\| !noteField.text.trim\(\)\) return([\s\S]*?)\n          }/)[0].replace(/\n          }$/,"")
function clickNote() {vm.runInContext('(function(){'+noteClick+'})()',editor)}
clickNote();editor.noteField.text="New unsent note";clickNote()
equal(notes.length,1,"pending note cannot be double-submitted even after editing its text")
notes[0].cb({ok:true})
equal(editor.noteField.text,"New unsent note","note success clears only its submitted snapshot, not newer edits")
clickNote();notes[notes.length-1].cb({ok:false,error:"Rejected"})
equal(editor.noteField.text,"New unsent note","note failure preserves submitted text for correction")
clickNote();notes[notes.length-1].cb({ok:true})
equal(editor.noteField.text,"","successful unchanged note clears normally after failure/retry")
const concurrentFeedback=setup(), cf=concurrentFeedback.c
cf.mineTickets=[ticket,{...ticket,Id:"b",Number:124}];cf.statuses.push({Id:3,Name:"On Hold"});cf.effectiveStatusIds=[1,3,5]
cf.setStatus("a",5);cf.setStatus("b",3)
concurrentFeedback.writes[0].cb({ok:false,kind:"api",status:400,error:"Rejected A"})
concurrentFeedback.writes[1].cb({ok:true})
assert(cf.actionError.includes("Rejected A"),"unrelated status success retains A's actionable failure")
cf.setStatus("b",1)
assert(cf.actionError.includes("Rejected A"),"starting unrelated ticket action retains A's failure")
cf.setStatus("a",5)
assert(!cf.actionError.includes("Rejected A"),"explicit relevant retry clears A's previous failure")
// Notification argv is the effect boundary: never invoke the installed helper.
const argvBoundary=setup(), ab=argvBoundary.c, argv=[]
ab.Quickshell={execDetached(args){argv.push(Array.from(args))}};ab.brandImage="trusted-logo.png";ab.demoMode=false
ab.urlFor=()=>"https://app.gorelo.io/ticket/a";ab.openUrlCommand=url=>["gio","launch","/browser.desktop",url]
vm.runInContext(functions(["notificationBody","sendNotification","sendNotificationSummary","toast"]),ab)
for(const hostile of ["--app-name=other","--urgency=critical","--image=https://tracking.invalid/x","--exec","-g"]) {
  ab.sendNotification({kind:"assigned",ticket:{...ticket,Title:hostile,Priority:{Id:3}}})
  const args=argv[argv.length-1], body=args[12]
  assert(!body.startsWith("-"),"flag-shaped notification body stays positional: "+hostile)
  equal(body," "+hostile,"leading-hyphen encoding is one transparent ordinary space")
  equal(args.slice(0,9),["omarchy-notification-send","--app-name","Gorelo","-g",Model.BRAND_ICON,"--image","trusted-logo.png","-u","normal"],"hostile body cannot change trusted app/image/urgency argv")
  equal(args.slice(-5),["--exec","gio","launch","/browser.desktop","https://app.gorelo.io/ticket/a"],"click command remains separated unchanged argv")
}
ab.sendNotification({kind:"assigned",ticket:{...ticket,Title:"Normal <title> & details",DisplayNumber:"Q&A",Priority:{Id:1}}})
const normalArgs=argv[argv.length-1]
equal(normalArgs[normalArgs.indexOf("--exec")-2],"Assigned to you: Q&A","plain-text notification headline does not display HTML entities")
equal(normalArgs[normalArgs.indexOf("--exec")-1],"Normal &lt;title&gt; &amp; details","normal body retains markup escaping without extra prefix")
ab.toast("Ticket #123 changed to Q&A","--image=<evil>")
equal(argv[argv.length-1].slice(-2),["Ticket #123 changed to Q&A"," --image=&lt;evil&gt;"],"toast headline remains literal plain text and its body cannot be an option")
const polledLocal=setup(), pl=polledLocal.c
pl.allTruncated=false;pl.mineTickets=[ticket];pl.searchQuery="Acme";pl.runSearch()
polledLocal.ticketSearch[0].cb({ok:true,data:[]});polledLocal.deviceSearch[0].cb({ok:true,data:[]})
pl.poll();polledLocal.polls[0].cb({ok:true,data:[ticket,{...ticket,Id:"new-local",Number:124}]})
pl.setStatus("new-local",5);polledLocal.writes[0].cb({ok:true})
equal(pl.rows.count,2,"local-only ticket first observed by a later poll also survives confirmed close")
// Approved bounded current-query snapshot: no silent eviction or unretained row flash.
const capacity=setup(), cp=capacity.c
cp.allTruncated=false;cp.searchQuery="Acme";cp.mineTickets=Array.from({length:500},(_,i)=>({...ticket,Id:"first-"+i}))
cp.runSearch();capacity.ticketSearch[0].cb({ok:true,data:[]});capacity.deviceSearch[0].cb({ok:true,data:[]})
cp.poll();capacity.polls[0].cb({ok:true,data:Array.from({length:500},(_,i)=>({...ticket,Id:"second-"+i}))})
equal(cp.rows.count,1000,"active-query membership retains two normal 500-ticket local snapshots")
const originalInsert=cp.rows.insert;let unretainedShown=false
cp.rows.insert=(i,row)=>{if(row.ticketId==="overflow")unretainedShown=true;originalInsert(i,row)}
cp.poll();capacity.polls[1].cb({ok:true,data:[{...ticket,Id:"first-0",Title:"Updated record",UpdatedOn:"2026-10-02T12:00:00Z"},{...ticket,Id:"overflow"}]})
equal(cp.rows.count,1000,"full snapshot does not replace retained IDs with newly arrived local-only candidate")
equal(cp.indexOfTicket("overflow"),-1,"unretained overflow candidate is not displayed")
assert(!unretainedShown,"overflow candidate is never briefly inserted before filtering")
equal(cp.rows.get(cp.indexOfTicket("first-0")).title,"Updated record","existing retained ID updates normally at capacity")
assert(cp.localSearchFull,"full retained snapshot exposes a distinct capacity warning")
cp.runSearch();capacity.ticketSearch[1].cb({ok:true,data:Array.from({length:55},(_,i)=>({...ticket,Id:"remote-"+i,ClientId:2}))});capacity.deviceSearch[1].cb({ok:true,data:[]})
equal(cp.rows.count,1050,"separate current server response is capped at 50 beyond 1000 retained local IDs")
cp.leaveSearch();cp.runSearch();capacity.ticketSearch[2].cb({ok:true,data:[]});capacity.deviceSearch[2].cb({ok:true,data:[]})
equal([cp.rows.count,cp.indexOfTicket("overflow")!==-1],[2,true],"clearing and searching again refills from current queue including formerly excluded candidate")
assert(!cp.localSearchFull,"clear/requery removes old snapshot capacity warning")
// Replacement failures and generation changes remain local modeled effects.
const referenceFailure=connectionSetup()
referenceFailure.c.applyConnection("usw","new-key");referenceFailure.keyReady("new-key")
referenceFailure.references[0]({ok:false,kind:"credential",error:"Rejected key"})
equal([referenceFailure.c.phase,referenceFailure.c.rows.count,referenceFailure.c.devices.length,referenceFailure.c.technicianId],["error",0,0,0],"replacement rejected by API cannot redisplay prior-account state")
const busyReplacement=connectionSetup();busyReplacement.c.credentialBusy=true
assert(!busyReplacement.c.applyConnection("usw","new-key"),"busy keyring refuses manual replacement")
equal([busyReplacement.c.draft.title,busyReplacement.c.technicianId,busyReplacement.stored.length],["Old draft",1,0],"busy refusal does not reset existing account")
const invalidReplacement=connectionSetup()
assert(!invalidReplacement.c.applyConnection("usw",'bad"key'),"unsupported credential characters are rejected before replacement")
equal([invalidReplacement.c.draft.title,invalidReplacement.c.technicianId,invalidReplacement.stored.length],["Old draft",1,0],"invalid credential refusal leaves existing account data/settings intact")
for (const stage of ["upload","comment"]) {
  const stale=createSetup();stale.c.createTicket();stale.creates[0].cb({ok:true,data:{Id:"old-id"}})
  if(stage==="comment") stale.uploads[0].cb({ok:true,data:{Name:"shot",Url:"attachment"}})
  stale.c.generation++
  if(stage==="upload") stale.uploads[0].cb({ok:true,data:{Name:"shot",Url:"attachment"}})
  else stale.comments[0].cb({ok:true})
  equal([stale.finished.length,stale.notices.length],[0,0],"old-generation "+stage+" completion cannot affect new connection")
  if(stage==="upload") equal(stale.comments.length,0,"superseded upload cannot create a private comment in a new connection")
}
const overlaySource=fs.readFileSync(path.join(__dirname,"..","Overlay.qml"),"utf8")
const createdHandler=overlaySource.match(/function onCreated\(id, warning, clearedDraft\) \{([\s\S]*?)\n    }/)[1]
let dismisses=0;const overlayContext={root:{dismiss(){dismisses++}}};vm.createContext(overlayContext)
vm.runInContext('(function(id,warning,clearedDraft){'+createdHandler+'})("id","",false)',overlayContext)
equal(dismisses,0,"earlier workflow completion leaves overlay holding newer draft open")
vm.runInContext('(function(id,warning,clearedDraft){'+createdHandler+'})("id","",true)',overlayContext)
equal(dismisses,1,"unchanged successfully submitted draft still dismisses overlay normally")
ab.sendNotificationSummary("--image=<evil>")
equal(argv[argv.length-1].slice(-2),["Gorelo"," --image=&lt;evil&gt;"],"summary boundary also neutralizes flag-shaped body without changing plain headline")
const editedSubmittedPhoto=createSetup(), esp=editedSubmittedPhoto.c
esp.createTicket();esp.updateDraft({title:"New unsent title"})
editedSubmittedPhoto.creates[0].cb({ok:true,data:{Id:"id"}});editedSubmittedPhoto.uploads[0].cb({ok:true,data:{Name:"shot",Url:"attachment"}});editedSubmittedPhoto.comments[0].cb({ok:true})
equal([esp.draft.title,esp.draft.attachmentPath],["New unsent title",""],"new text survives but a consumed submitted screenshot is not left as a dangling draft reference")
const newerPhoto=createSetup(), np=newerPhoto.c
np.createTicket();np.updateDraft({title:"New title",attachmentPath:"screenshot-new.png"})
newerPhoto.creates[0].cb({ok:true,data:{Id:"id"}});newerPhoto.uploads[0].cb({ok:false,error:"offline"})
equal([np.draft.title,np.draft.attachmentPath],["New title","screenshot-new.png"],"old workflow completion never clears a genuinely newer screenshot")
// Re-review: execute real upload completion bookkeeping, with process/file effects modeled.
const liveSource=fs.readFileSync(path.join(__dirname,"..","LiveBackend.qml"),"utf8")
const finishUploadStart=liveSource.indexOf("  function finishUpload(")
const finishUploadText=liveSource.slice(finishUploadStart,finishUploadStart+liveSource.slice(finishUploadStart).indexOf("\n  }")+4)
function consumedLifecycleSetup() {
  const h=createSetup(),c=h.c,references=[]
  const b={...c.backend,generation:1,uploadOperation:null,uploadOutput:"",uploadDeadline:{stop(){}},deleteAttachment:c.deleteAttachment}
  b.root=b;vm.createContext(b);vm.runInContext(finishUploadText,b)
  b.uploadAttachment=(id,path,cb)=>{h.uploads.push({id,path,cb});b.uploadOperation={path,generation:b.generation,callback:cb,done:false}}
  b.supersede=()=>{b.generation++;b.uploadOperation=null}
  b.loadReference=cb=>references.push(cb)
  c.backend=b;c.liveBackend=b;c.demoBackend.supersede=()=>{};c.reconnectTimer={stop(){},restart(){}}
  vm.runInContext(functions(["connect","supersedeRequests","loadReference","setError","clearError"]),c)
  return {...h,b,references}
}
for (const variant of ["unchanged","edited-text","newer-photo"]) {
  const lifecycle=consumedLifecycleSetup(), sc=lifecycle.c
  sc.createTicket();lifecycle.creates[0].cb({ok:true,data:{Id:"id"}})
  if(variant==="edited-text") sc.updateDraft({title:"Newer unsent title"})
  lifecycle.b.finishUpload({ok:true,data:{Name:"shot",Url:"attachment"}})
  equal([lifecycle.b.uploadOperation,lifecycle.deleted[0],lifecycle.comments.length],[null,"screenshot-submitted.png",1],"real upload completion consumes screenshot before comment callback")
  if(variant==="newer-photo") sc.updateDraft({title:"Newer unsent title",attachmentPath:"screenshot-new.png"})
  sc.connect()
  equal(sc.draft.title,variant==="unchanged"?"Submitted title":"Newer unsent title","comment-stage reconnect preserves draft text: "+variant)
  equal(sc.draft.attachmentPath,variant==="newer-photo"?"screenshot-new.png":"","comment-stage reconnect detaches only consumed submitted screenshot: "+variant)
  lifecycle.comments[0].cb({ok:true})
  equal([lifecycle.finished.length,lifecycle.notices.length],[0,0],"late superseded screenshot comment cannot clear/dismiss/confirm draft: "+variant)
  equal([sc.draft.title,sc.draft.attachmentPath],[variant==="unchanged"?"Submitted title":"Newer unsent title",variant==="newer-photo"?"screenshot-new.png":""],"late comment leaves reconnect-preserved draft unchanged: "+variant)
  if(variant==="newer-photo") assert(!lifecycle.deleted.includes("screenshot-new.png"),"supersede never cleans a genuinely newer screenshot")
}
const beforeUpload=consumedLifecycleSetup();beforeUpload.c.createTicket();beforeUpload.c.connect()
equal([beforeUpload.c.draft.title,beforeUpload.c.draft.attachmentPath],["Submitted title","screenshot-submitted.png"],"reconnect before upload preserves a still-safe unconsumed attachment")
beforeUpload.creates[0].cb({ok:true,data:{Id:"old-id"}})
equal(beforeUpload.uploads.length,0,"late superseded create cannot upload preserved pre-upload screenshot")
const cleanLifecycle=consumedLifecycleSetup();cleanLifecycle.c.createTicket();cleanLifecycle.creates[0].cb({ok:true,data:{Id:"id"}})
cleanLifecycle.b.finishUpload({ok:true,data:{Name:"shot",Url:"attachment"}});cleanLifecycle.comments[0].cb({ok:true})
equal([cleanLifecycle.c.draft.title,cleanLifecycle.c.draft.attachmentPath,cleanLifecycle.finished[0].cleared],["","",true],"consumption tracking preserves unchanged successful draft identity and dismissal signal")
// Watched config tab transitions must reset query lifetime independently of filters.
for (const withFilterChange of [false,true]) {
  const watched=connectionSetup(), wc=watched.c
  wc.leaveSearch();wc.searchQuery="Printer"
  wc.mineTickets=Array.from({length:500},(_,i)=>({...ticket,Id:"watched-first-"+i}))
  wc.runSearch();wc.poll()
  watched.polls[0].cb({ok:true,data:Array.from({length:500},(_,i)=>({...ticket,Id:"watched-second-"+i}))})
  equal([wc.rows.count,wc.localSearchFull,wc.searchPendingCount],[1000,true,2],"watched-tab regression starts with full snapshot and pending search callbacks")
  const next={...wc.currentConfig(),activeTab:"all"}
  if(withFilterChange) next.statusIds=[1,5]
  wc.applyConfig(JSON.stringify(next))
  equal([wc.searchActive,wc.localSearchTickets.length,wc.localSearchFull,wc.searchPendingCount,wc.searchResults.length],[false,0,false,0,0],"watched tab change resets retained membership/capacity/search even with filterChange="+withFilterChange)
  watched.ticketSearch[0].cb({ok:true,data:[{...ticket,Id:"previous-tab-remote"}]})
  watched.deviceSearch[0].cb({ok:true,data:[{Id:"previous-tab-device",Name:"Printer"}]})
  equal([wc.searchResults.length,wc.currentDeviceResults.length,wc.indexOfTicket("previous-tab-remote")],[0,0,-1],"previous-tab search callbacks are rejected after watched config transition, filterChange="+withFilterChange)
}
done("test_service")
