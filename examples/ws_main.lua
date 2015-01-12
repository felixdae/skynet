local skynet = require "skynet"
local snax = require "snax"
local socket = require "socket"
local ws_server = require "ws_server"

local fid,addr = ...

if fid then
    print(fid..addr)
    fid=tonumber(fid)
    skynet.start(function()
        --local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(fid), 8192)
        --print(code..url..method)
        socket.start(fid)
        local server, msg = ws_server.new(fid, {}, handle)
        if not server then
            print("ws handshake error: "..msg)
            socket.close(fid)
            skynet.exit()
        end
        socket.write(fid, msg)
        server:serve()
    end)
    --socket.close()
else
    skynet.start(function()
        local listen_id = socket.listen("0.0.0.0",6005)
        socket.start(listen_id,function(accept_id,addr)
            print(listen_id,accept_id)
            --socket.close(accept_id)
            skynet.newservice(SERVICE_NAME,accept_id,addr)
        end)
    end)
end
