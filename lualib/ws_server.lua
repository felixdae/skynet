-- Copyright (C) Yichun Zhang (agentzh)


local bit = require "bit32"
local wbproto = require "ws_protocol"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string

local socket = require "socket"

local new_tab = wbproto.new_tab
local _recv_frame = wbproto.recv_frame
local _send_frame = wbproto.send_frame
--local http_ver = ngx.req.http_version
--local req_sock = ngx.req.socket
--local ngx_header = ngx.header
--local req_headers = ngx.req.get_headers
local str_lower = string.lower
local char = string.char
local str_find = string.find
local crypto = require "crypt"
--local sha1_bin = ngx.sha1_bin
--local base64 = ngx.encode_base64
--local ngx = ngx
--local read_body = ngx.req.read_body
local band = bit.band
local rshift = bit.rshift
local type = type
local setmetatable = setmetatable
-- local print = print


local _M = new_tab(0, 10)
_M._VERSION = '0.04'

local mt = { __index = _M }

function _M.serve(self)
    local sock_id = self.sock_id
    while socket.block(sock_id) do
        local data, typ, err = self:recv_frame()
        if not data then
            return false
        end
        if typ == "close" then
            self:send_close(1005, "recv close")
        end
        self:send_text(data)
    end
end

function _M.new(sock_id, opts, handle)
    local code, httpver, url, method, headers, body = httpd.read_request(sockethelper.readfunc(sock_id), 8192)
    print (sock_id, opts, code)
    print ("code: "..code)
    print ("url: "..url)
    print ("method: "..method)
    for k, v in pairs(headers) do
        print (k..":"..v)
    end

    if httpver ~= 1.1 then
        return nil, "bad http version"
    end

    local val = headers.upgrade
    if not val or str_lower(val) ~= "websocket" then
        return nil, "bad \"upgrade\" request header"
    end

    val = headers.connection
    if not val or not str_find(str_lower(val), "upgrade", 1, true) then
        return nil, "bad \"connection\" request header"
    end

    local key = headers["sec-websocket-key"]
    if not key then
        return nil, "bad \"sec-websocket-key\" request header"
    end

    local ver = headers["sec-websocket-version"]
    if not ver or ver ~= "13" then
        return nil, "bad \"sec-websocket-version\" request header"
    end

    local protocols = headers["sec-websocket-protocol"]

    local sha1 = crypto.base64encode(crypto.sha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
    local resp = "HTTP/1.1 101 Switching Protocols\r\n"
    resp = resp.."Upgrade: WebSocket\r\n"
    resp = resp.."Connection: Upgrade\r\n"
    resp = resp.."Sec-WebSocket-Accept: "..sha1.."\r\n"
    resp = resp.."\r\n"
    --todo add extension and protocol
    print (resp)

    local max_payload_len, send_masked, timeout
    if opts then
        max_payload_len = opts.max_payload_len
        send_masked = opts.send_masked
        timeout = opts.timeout
    end

    return setmetatable({
        sock_id = sock_id,
        max_payload_len = max_payload_len or 65535,
        send_masked = send_masked,
    }, mt), resp
end


--function _M.set_timeout(self, time)
--    local sock = self.sock
--    if not sock then
--        return nil, nil, "not initialized yet"
--    end
--
--    return sock:settimeout(time)
--end


function _M.recv_frame(self)
    if self.fatal then
        return nil, nil, "fatal error already happened"
    end

    local sock_id = self.sock_id
    if not sock_id then
        return nil, nil, "not initialized yet"
    end

    local data, typ, err =  _recv_frame(sock_id, self.max_payload_len, true)
    if not data and not str_find(err, ": timeout", 1, true) then
        self.fatal = true
    end
    return data, typ, err
end


local function send_frame(self, fin, opcode, payload)
    if self.fatal then
        return nil, "fatal error already happened"
    end

    local sock_id = self.sock_id
    if not sock_id then
        return nil, "not initialized yet"
    end

    local bytes, err = _send_frame(sock_id, fin, opcode, payload,
                                   self.max_payload_len, self.send_masked)
    if not bytes then
        self.fatal = true
    end
    return bytes, err
end
_M.send_frame = send_frame


function _M.send_text(self, data)
    return send_frame(self, true, 0x1, data)
end


function _M.send_binary(self, data)
    return send_frame(self, true, 0x2, data)
end


function _M.send_close(self, code, msg)
    local payload
    if code then
        if type(code) ~= "number" or code > 0x7fff then
        end
        payload = char(band(rshift(code, 8), 0xff), band(code, 0xff))
                        .. (msg or "")
    end
    return send_frame(self, true, 0x8, payload)
end


function _M.send_ping(self, data)
    return send_frame(self, true, 0x9, data)
end


function _M.send_pong(self, data)
    return send_frame(self, true, 0xa, data)
end


return _M
