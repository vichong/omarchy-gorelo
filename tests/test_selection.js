// Selection policy from the actual Panel; Qt focus still needs manual checks.
const fs=require("fs"),vm=require("vm"),path=require("path")
const {equal,done}=require("./helpers")
const text=fs.readFileSync(path.join(__dirname, "..", "Panel.qml"),"utf8")
const names=["rememberCursor","restoreRowsState","tabFromCursor"]
const src=names.map(name=>{
 const start=text.indexOf("  function "+name+"("), rest=text.slice(start)
 return rest.slice(0,rest.indexOf("\n  }")+4)
}).join("\n")
let rows=[{ticketId:"a"},{ticketId:"b"},{ticketId:"c"}], focuses=0
const c={String,Math,Qt:{callLater(cb){cb()}},keyCatcher:{forceActiveFocus(){focuses++}},
 serviceReady:true,cursorActive:true,cursorIndex:1,cursorTicketId:"b",cursorDeviceId:"",expandedTicketId:"b",expandedDeviceId:"",
 restoreRowFocus:false,focusedRowId:"",gorelo:{rows:{get(i){return rows[i]}},deviceRows:{get(){}},indexOfTicket(id){return rows.findIndex(r=>r.ticketId===id)},indexOfDevice(){return -1}}}
Object.defineProperties(c,{rowCount:{get(){return rows.length}},totalRowCount:{get(){return rows.length}}})
c.root=c;vm.createContext(c);vm.runInContext(src,c)
rows=[{ticketId:"a"},{ticketId:"c"}];c.restoreRowsState()
equal([c.cursorIndex,c.cursorTicketId,c.expandedTicketId],[1,"c",""],"removed middle row selects next ticket")
c.expandedTicketId="c";rows=[{ticketId:"a"}];c.restoreRowsState()
equal([c.cursorIndex,c.cursorTicketId],[0,"a"],"last row removal selects previous")
rows=[{ticketId:"z"},{ticketId:"a"}];c.restoreRowsState()
equal([c.cursorIndex,c.cursorTicketId],[1,"a"],"identity preserved across reorder")
equal(focuses,0,"unrelated editing focus not stolen")
c.restoreRowFocus=true;c.focusedRowId="a";rows=[];c.restoreRowsState()
equal(focuses,1,"removed focused row requests keyboard navigation focus")
equal(c.cursorIndex,0,"empty queue cursor safe")
let moreFocus=0, actionDirection=0, switched=0
c.showMoreButton={visible:true,forceActiveFocus(){moreFocus++}}
c.currentRow=()=>({expanded:false});c.switchPanel=(direction)=>{switched=direction}
c.tabFromCursor(1)
equal(moreFocus,1,"Tab from unexpanded cursor can reach Show more")
c.currentRow=()=>({expanded:true,expansionItem:{focusFirstAction(direction){actionDirection=direction}}})
c.tabFromCursor(-1)
equal([actionDirection,moreFocus],[-1,1],"expanded-row Tab conventions remain first priority")
c.showMoreButton.visible=false;c.currentRow=()=>null;c.tabFromCursor(-1)
equal(switched,-1,"panel switching remains fallback without expanded actions or Show more")
// Execute the actual distinct snapshot-warning visibility binding.
const capacityBlock=text.match(/visible: (root.connected && root.serviceReady && root.gorelo.searchActive && root.gorelo.localSearchFull)\n          text: "([^"]+)"/)
c.connected=true;c.gorelo.searchActive=true;c.gorelo.localSearchFull=false
function snapshotWarningVisible(){return vm.runInContext(capacityBlock[1],c)}
equal(snapshotWarningVisible(),false,"snapshot warning stays hidden before local capacity is reached")
c.gorelo.localSearchFull=true
equal(snapshotWarningVisible(),true,"full snapshot exposes an independent visible warning")
equal(capacityBlock[2],"The retained search snapshot is full (1,000 local tickets). New local matches are not added; clear and search again to refill it.","capacity warning accurately explains local retention bound and recovery, not API truncation")
c.gorelo.searchActive=false
equal(snapshotWarningVisible(),false,"clearing search hides retained-snapshot warning")
done("test_selection")
