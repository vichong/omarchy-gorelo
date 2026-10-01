// Real LiveBackend entry points, with transport/process boundaries replaced.
const fs=require("fs"), vm=require("vm"), path=require("path")
const {loadModule,assert,equal,done}=require("./helpers")
const Api=loadModule("Api.js")
const source=fs.readFileSync(path.join(__dirname, "..", "LiveBackend.qml"),"utf8")
function extract(name) {
  const start=source.indexOf("  function "+name+"("), lineEnd=source.indexOf("\n",start)
  if(source.slice(start,lineEnd).endsWith(" }"))return source.slice(start,lineEnd)
  return source.slice(start,lineEnd+source.slice(lineEnd).search(/^  }$/m)+3)
}
const requests=[]
const c={Api,String,Math,parseInt,isNaN,Date,encodeURIComponent,region:"usw",apiKey:"key",generation:1,
 screenshotDir:"/private/gorelo",attachmentHelperPath:"/plugin/scripts/gorelo-attachment",uploadOperation:null,
 uploadProcess:{running:false},uploadDeadline:{restart(){}},request(method,path,body,cb){requests.push({method,path,body,cb});return {}}}
c.root=c;vm.createContext(c)
vm.runInContext(["searchTickets","searchDevices","uploadAttachment","getTicket","parseCurlResult"].map(extract).join("\n"),c)
let error
c.searchTickets("x".repeat(201),r=>error=r)
equal(requests.length,0,"oversized ticket query never requests")
assert(error.error.includes("200"),"query error clear")
c.searchDevices("x".repeat(201),r=>error=r)
equal(requests.length,0,"oversized device query never requests")
c.searchDevices("PC #1",()=>{})
equal(requests[0].path,"/v1/assets/agents?Query=PC%20%231&PageSize=200","one bounded server device query")
c.getTicket("test/id",()=>{})
equal(requests[1].path,"/v1/tickets/test%2Fid","timeout authoritative detail read encodes ID")
c.uploadAttachment("@/etc/passwd","screenshot-test.png",r=>error=r)
assert(!c.uploadProcess.running && error.error.includes("UUID"),"live upload validates UUID before spawn")
const id="12345678-1234-1234-1234-123456789abc"
c.uploadAttachment(id,"screenshot-test.png",()=>{})
equal(c.uploadProcess.command,["bash","/plugin/scripts/gorelo-attachment","upload","/private/gorelo","screenshot-test.png","https://api.usw.gorelo.io/v1/attachments","5242880","115","20971520",id],"supported upload route and helper UUID interface")
assert(!c.uploadProcess.command.includes("key"),"upload credentials never in argv")
equal(c.parseCurlResult('{"IsSuccess":false,"Notifications":[{"Message":"Cannot choose New"}]}\n400',22,"large").error,"Cannot choose New","curl failure preserves API Notifications")
equal(c.parseCurlResult("\n000",28,"large").kind,"network","curl timeout remains ambiguous network outcome")
done("test_backend")
