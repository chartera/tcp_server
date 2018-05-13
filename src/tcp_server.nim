import asyncdispatch, asyncnet, protocol, sequtils, osproc, net, os,
       tables
  
var server: Server
var ctx: SslContext

var callbacks = tables.initTable[string, seq[proc(client: Client, msg: Message): void]]()


proc subscribe*(cmd: string, callback: proc(client: Client, msg: Message): void): void =
  if tables.hasKey(callbacks, cmd):
    callbacks[cmd].add(callback)
  else:
    tables.add(callbacks, cmd, @[callback])
    
proc publish(cmd: string, client: Client, msg: Message): void =
  if tables.hasKey(callbacks, cmd):
    let clbs = callbacks[cmd]
    for clb in clbs:
      clb(client, msg)

proc `$`(client: Client): string =
  $client.id & "(" & client.netAddr & ")"

proc remove_socket(id: int): void =
  for index, client in server.clients:
    if id == client.id:
      if client.connected == false:
        sequtils.delete(server.clients, index, index)
        break
    
proc cleaning_clients(): void =
  if server.clients.len > 1:
    sequtils.delete(server.clients, 1, server.clients.len)

proc processMessages(server: Server, client: Client) {.async.} =
  while true:
    let line = await asyncnet.recvLine(client.socket)
    if line.len == 0:
      echo(client, " disconnected")

      client.connected = false
      asyncnet.close(client.socket)
      remove_socket(client.id)
      return

    let msg = parse_message(line)
    # Todo! Outsourcing
    case msg.cmd:
      of "error":
        echo("Protocol error")
        client.connected = false
        asyncnet.close(client.socket)
        remove_socket(client.id)
        return
      of "ping":
        publish(msg.cmd, client, msg)
        let msg = create_message("pong", client.netAddr)
        asyncCheck asyncnet.send(client.socket, msg)
      else:
        publish(msg.cmd, client, msg)
    
proc loop(server: Server, port: int) {.async.} =
  asyncnet.bindAddr(server.socket, Port(port))
  asyncnet.listen(server.socket)
  echo("Server started on port ", port)
  while true:
    # accepting clients
    let (netAddr, clientSocket) =
      await asyncnet.acceptAddr(server.socket)

    echo("Accepted connection from client ", netAddr & ", ssl: " &
      $ isSsl(server.socket))

    let client = Client(
      socket: clientSocket,
      netAddr: netAddr,
      id: server.clients.len,
      connected: true
    )
    server.clients.add(client)
    cleaning_clients()
    asyncCheck processMessages(server, client)

proc echo_ping(client: Client, msg: Message): void =
  echo("Pong ", "(" & msg.cmd & ")")
  
proc start_server*(port: int): void =
  server = Server(socket: asyncnet.newAsyncSocket(), clients: @[])
    
  let csr = getCurrentDir() & "/" & "domain.csr"
  let key = getCurrentDir() & "/" & "domain.key"
  ctx = net.newContext(protSSLv23, CVerifyPeer, csr, key)
  wrapSocket(ctx, server.socket)
  subscribe("ping", echo_ping)
  asyncdispatch.asyncCheck loop(server, port)
  
