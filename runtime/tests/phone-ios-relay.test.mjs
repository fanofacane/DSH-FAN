import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createServer } from 'node:net'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
const relay=fileURLToPath(new URL('../../apple/Resources/Phone/relay.cjs',import.meta.url))
test('iOS relay authenticates first, forwards lines, drains trailing output and never logs secret',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'phone-ios-'))
 const secret='test-fixture-not-a-credential-'.repeat(2)
 const server=createServer()
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve))
 const config=join(folder,'bridge.json')
 await writeFile(config,JSON.stringify({v:1,tcpPort:server.address().port,token:secret}),{mode:0o600})
 const child=spawn(process.execPath,[relay,config],{stdio:['pipe','pipe','pipe']})
 let output='',errors='';child.stdout.on('data',b=>{output+=b});child.stderr.on('data',b=>{errors+=b})
 try{
  const [socket]=await once(server,'connection');let buffer='';const lines=[]
  socket.on('data',b=>{buffer+=b;let end;while((end=buffer.indexOf('\n'))>=0){lines.push(JSON.parse(buffer.slice(0,end)));buffer=buffer.slice(end+1);if(lines.length===2){socket.end(JSON.stringify({jsonrpc:'2.0',id:9,result:{text:'tail'.repeat(32768)}})+'\n')}}})
  child.stdin.write('{"jsonrpc":"2.0","id":9,"method":"ping"}\n')
  const [code]=await once(child,'close')
  assert.equal(code,0);assert.equal(lines[0].dshPhone,1);assert.equal(lines[0].token===secret,true)
  assert.equal(lines[1].method,'ping');assert.equal(JSON.parse(output).result.text.length,131072)
  assert.equal(output.includes(secret),false);assert.equal(errors.includes(secret),false)
 }finally{child.kill();server.close();await rm(folder,{recursive:true,force:true})}
})
test('invalid configuration reports a generic error, not its contents',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'phone-ios-'))
 try{
  const config=join(folder,'invalid.json');await writeFile(config,'{"token":"fixture-private","tcpPort":-1}')
  const child=spawn(process.execPath,[relay,config],{stdio:['ignore','pipe','pipe']});let error='';child.stderr.on('data',b=>{error+=b})
  const [code]=await once(child,'close');assert.equal(code,1);assert.equal(error.includes('fixture-private'),false);assert.match(error,/configuration unavailable/)
 }finally{await rm(folder,{recursive:true,force:true})}
})
test('overlay uses Node executable and private config path with a fixed phone name',async()=>{
 const patch=await readFile(new URL('../../apple/Resources/Phone/phone.patch.yml',import.meta.url),'utf8')
 assert.match(patch,/serverName: phone/);assert.match(patch,/command: !!js process\.execPath/);assert.match(patch,/\/var\/lib\/dsh-app\/phone\/bridge\.json/)
})
