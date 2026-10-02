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
// Exercise the public request entry point at the existing Process-command seam.
const transport={Api,String,Math,Date,JSON,region:"usw",apiKey:"test-only-api-key",generation:1,
 requestTimeoutMs:25000,inflight:[],requestQueue:[],requestOperation:null,
 requestProcess:{running:false},requestDeadline:{restart(){}}}
transport.root=transport;vm.createContext(transport)
vm.runInContext(["request","startNextRequest"].map(extract).join("\n"),transport)
transport.request("GET","/v1/tickets",null,()=>{})
const command=transport.requestProcess.command
equal(command[0],"curl","request uses curl")
equal(command[1],"-q","request disables ambient curl config before all other arguments")
equal(command.slice(2),["-sS","--proto","=https","--max-filesize","5242880","--max-time","25",
 "-K","-","-w","\n%{http_code}","https://api.usw.gorelo.io/v1/tickets"],
 "request retains exact origin, no redirects, HTTPS-only transfer, limits and stdin config")
assert(transport.requestProcess.stdinEnabled,"request keeps stdin enabled for credentials")
assert(!command.join(" ").includes(transport.apiKey),"request credentials never in argv")
done("test_backend")
