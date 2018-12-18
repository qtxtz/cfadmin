local tcp = require "internal.TCP"
local log = require "log"
local cjson = require "cjson"
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode

local DATE = os.date
local time = os.time
local tostring = tostring
local spliter = string.gsub
local lower = string.lower
local upper = string.upper
local match = string.match
local fmt = string.format
local int = math.integer
local find = string.find
local split = string.sub
local insert = table.insert
local remove = table.remove
local concat = table.concat

local CRLF = '\r\n'
local CRLF2 = '\r\n\r\n'


local HTTP_CODE = {

	[100] = "HTTP/1.1 100 Continue",
	[101] = "HTTP/1.1 101 Switching Protocol",
	[102] = "HTTP/1.1 102 Processing",

	[200] = "HTTP/1.1 200 OK",
	[201] = "HTTP/1.1 201 Created",
	[202] = "HTTP/1.1 202 Accepted",
	[203] = "HTTP/1.1 203 Non-Authoritative Information",
	[204] = "HTTP/1.1 204 No Content",
	[205] = "HTTP/1.1 205 Reset Content",
	[206] = "HTTP/1.1 206 Partial Content",
	[207] = "HTTP/1.1 207 Multi-Status",
	[208] = "HTTP/1.1 208 Multi-Status",
	[226] = "HTTP/1.1 226 IM Used",

	[300] = "HTTP/1.1 300 Multiple Choice",
	[301] = "HTTP/1.1 301 Moved Permanently",
	[302] = "HTTP/1.1 302 Found",
	[303] = "HTTP/1.1 303 See Other",
	[304] = "HTTP/1.1 304 Not Modified",
	[305] = "HTTP/1.1 305 Use Proxy",
	[306] = "HTTP/1.1 306 unused",
	[307] = "HTTP/1.1 307 Temporary Redirect",
	[305] = "HTTP/1.1 308 Permanent Redirect",

	[400] = "HTTP/1.1 400 Bad Request",
	[401] = "HTTP/1.1 401 Unauthorized",
	[402] = "HTTP/1.1 402 Payment Required",
	[403] = "HTTP/1.1 403 Forbidden",
	[404] = "HTTP/1.1 404 Not Found",
	[405] = "HTTP/1.1 405 Method Not Allowed",
	[406] = "HTTP/1.1 406 Not Acceptable",
	[407] = "HTTP/1.1 407 Proxy Authentication Required",
	[408] = "HTTP/1.1 408 Request Timeout",
	[409] = "HTTP/1.1 409 Conflict",

	[410] = "HTTP/1.1 410 Gone",
	[411] = "HTTP/1.1 411 Length Required",
	[412] = "HTTP/1.1 412 Precondition Failed",
	[413] = "HTTP/1.1 413 Payload Too Large",
	[414] = "HTTP/1.1 414 URI Too Long",
	[415] = "HTTP/1.1 415 Unsupported Media Type",
	[416] = "HTTP/1.1 416 Requested Range Not Satisfiable",
	[417] = "HTTP/1.1 417 Expectation Failed",
	[418] = "HTTP/1.1 418 I'm a teapot",

	[421] = "HTTP/1.1 421 Misdirected Request",
	[422] = "HTTP/1.1 422 Unprocessable Entity (WebDAV)",
	[423] = "HTTP/1.1 423 Locked (WebDAV)",
	[424] = "HTTP/1.1 424 Failed Dependency",
	[426] = "HTTP/1.1 426 Upgrade Required",
	[428] = "HTTP/1.1 428 Precondition Required",
	[429] = "HTTP/1.1 429 Too Many Requests",
	[431] = "HTTP/1.1 431 Request Header Fields Too Large",
	[451] = "HTTP/1.1 451 Unavailable For Legal Reasons",

	[500] = "HTTP/1.1 500 Internal Server Error",
	[501] = "HTTP/1.1 501 Not Implemented",
	[502] = "HTTP/1.1 502 Bad Gateway",
	[503] = "HTTP/1.1 503 Service Unavailable",
	[504] = "HTTP/1.1 504 Gateway Timeout",
	[505] = "HTTP/1.1 505 HTTP Version Not Supported",
	[506] = "HTTP/1.1 506 Variant Also Negotiates",
	[507] = "HTTP/1.1 507 Insufficient Storage",
	[508] = "HTTP/1.1 508 Loop Detected (WebDAV)",
	[510] = "HTTP/1.1 510 Not Extended",
	[503] = "HTTP/1.1 511 Network Authentication Required",

}

local MIME = {
	-- 文本格式
	['htm']  = 'text/html',
	['html'] = 'text/html',
	['txt']  = 'text/plain',
	['css']  = 'text/css',
	['js']   = 'application/x-javascript',
	['json'] = 'application/json',
	-- 图片格式
	['bmp']  = 'image/bmp',
	['png']  = 'image/png',
	['gif']  = 'image/gif',
	['jpeg'] = 'image/jpeg',
	['jpg']  = 'image/jpeg',
	['ico']  = 'image/x-icon',
	['tif']  = 'image/tiff',
	['tiff'] = 'image/tiff',
	-- 其他格式
	-- TODO
}

local HTTP_PROTOCOL = {
	API = 1,
	[1] = "API",
	USE = 2,
	[2] = "USE",
	STATIC = 3,
	[3] = "STATIC",
}


-- 以下为 HTTP Client 所需所用方法

function HTTP_PROTOCOL.RESPONSE_HEAD_PARSER(head)
	local HEADER = {}
	spliter(head, "(.-): (.-)\r\n", function (key, value)
		if key == 'Content-Length' then
			HEADER['Content-Length'] = tonumber(value)
			return
		end
		HEADER[key] = value
	end)
	return HEADER
end

function HTTP_PROTOCOL.RESPONSE_PROTOCOL_PARSER(protocol)
	local VERSION, CODE, STATUS = match(protocol, "HTTP/([%d%.]+) (%d+) (.+)\r\n")
	return tonumber(CODE)
end


-- 以下为 HTTP Server 所需所用方法

local function REQUEST_STATUCODE_RESPONSE(code)
	return HTTP_CODE[code] or "attempt to Passed A Invaid Code to response message."
end

local function REQUEST_MIME_RESPONSE(mime)
	return MIME[mime] or MIME['html']
end


local function REQUEST_HEADER_PARSER(head)
	local HEADER = {}
	spliter(head, "(.-): (.-)\r\n", function (key, value)
		HEADER[key] = value
	end)
	return HEADER
end

local function REQUEST_PROTOCOL_PARSER(protocol)
	return match(protocol, "(%w+) (.+) HTTP/([%d%.]+)\r\n")
end

function HTTP_PROTOCOL.ROUTE_REGISTERY(routes, route, class, type)
	if route == '' then
		log.warn('Please Do not add empty string in route registery method :)')
		return
	end
	if find(route, '//') then
		log.warn('Please Do not add [//] in route registery method :)')
		return
	end
	if route == '/' then
		route = "/___"
	end
	local fields = {}
	spliter(route, "/([^/?]*)", function (field)
		insert(fields, field)
	end)
	local t 
	for index, field in ipairs(fields) do
		if index == 1 then
			if routes[field] then
				t = routes[field]
				if #fields == index then
					break
				end
			else
				t = {}
				routes[field] = t
				if #fields == index then
					break
				end
			end
		else
			if t[field] then
				t = t[field]
				if #fields == index then
					break
				end
			else
				t[field] = {}
				t = t[field]
				if #fields == index then
					break
				end
			end
		end
	end
	t.route = route
	t.class = class
	t.type = type
	return
end

function HTTP_PROTOCOL.ROUTE_FIND(routes, route)
	if route == '/' then
		route = "/___"
	end
	local fields = {}
	spliter(route, "/([^/?]*)", function (field)
		if field ~= "" then
			insert(fields, field)
		end
	end)
	local t, class, type
	for index, field in ipairs(fields) do
		if index == 1 then
			if not routes[field] then
				break
			end
			t = routes[field]
			if #fields == index and t.class then
				type = t.type
				class = t.class
				break
			end
			if t.type == HTTP_PROTOCOL.STATIC then
				type = t.type
				class = t.class
				break
			end
		else
			if not t[field] then
				break
			end
			t = t[field]
			if #fields == index and t.class then
				type = t.type
				class = t.class
				break
			end
		end
	end
	return class, type
end

local function HTTP_DATE(timestamp)
	if not timestamp then
		return DATE("%a, %d %b %Y %X GMT")
	end
	return DATE("%a, %d %b %Y %X GMT", timestamp)
end

local function PASER_METHOD(http, sock, buffer, METHOD, PATH, HEADER)
	local ARGS, FILE
	if METHOD == "HEAD" or METHOD == "GET" then
		local spl_pos = find(PATH, '%?')
		if spl_pos and spl_pos < #PATH then
			ARGS = {}
			spliter(PATH, '([^%?&]*)=([^%?&]*)', function (key, value)
				ARGS[key] = value
			end)
		end
	elseif METHOD == "POST" then
		local body_len = tonumber(HEADER['Content-Length'])
		local BODY = ''
		local RECV_BODY = true
		local CRLF_START, CRLF_END = find(buffer, '\r\n\r\n')
		if #buffer > CRLF_END then
			BODY = split(buffer, CRLF_END + 1, -1)
			if #BODY == body_len then
				RECV_BODY = false
			end
		end
		if RECV_BODY then
			local buffers = {BODY}
			while 1 do
				local buf = sock:recv(8192)
				if not buf then
					return
				end
				insert(buffers, buf)
				local buffer = concat(buffers)
				if #buffer == body_len then
					BODY = buffer
					break
				end
			end
		end
		if HEADER['Content-Type'] then
			local JSON_ENCODE = 'application/json'
			local FILE_ENCODE = 'multipart/form-data'
			local URL_ENCODE = 'application/x-www-form-urlencoded'
			spliter(HEADER['Content-Type'], '(.-/[^;]*)', function(format)
				if format == FILE_ENCODE then
					local BOUNDARY
					spliter(HEADER['Content-Type'], '^.+=[%-]*(.+)', function (boundary)
						BOUNDARY = boundary
					end)
					if BOUNDARY then
						FILE = {}
						spliter(BODY, '\r\n\r\n(.-)\r\n[%-]*'..BOUNDARY, function (file)
							insert(FILE, file)
						end)
					end
				elseif format == JSON_ENCODE then
					local ok, json = pcall(cjson_decode, BODY)
					if ok then
						ARGS = json
					end
				elseif format == URL_ENCODE then
					spliter(BODY, '([^%?&]*)=([^%?&]*)', function (key, value)
						if not ARGS then
							ARGS = {}
						end
						ARGS[key] = value
					end)
				end
			end)
		end
	else
		-- 暂未支持其他方法
		return
	end
	return true, ARGS, FILE
end


-- 一些错误返回
local function ERROR_RESPONSE(http, code)
	return concat({
		REQUEST_STATUCODE_RESPONSE(code),
		'Date: ' .. HTTP_DATE(),
		'Allow: GET, POST, HEAD',
		'Access-Control-Allow-Origin: *',
		'Connection: close',
		'server: ' .. (http.server or 'cf/0.1'),
	}, CRLF) .. CRLF2
end

function HTTP_PROTOCOL.EVENT_DISPATCH(fd, ipaddr, http)
	local buffers = {}
	local routes = http.routes
	local server = http.server
	local ttl = http.ttl
	local sock = tcp:new():set_fd(fd):timeout(http.timeout or 30)
	while 1 do
		local buf = sock:recv(8192)
		if not buf then
			return sock:close()
		end
		insert(buffers, buf)
		local buffer = concat(buffers)
		local CRLF_START, CRLF_END = find(buffer, CRLF2)
		if CRLF_START and CRLF_END then
			local PROTOCOL_START, PROTOCOL_END = find(buffer, CRLF)
			local METHOD, PATH, VERSION = REQUEST_PROTOCOL_PARSER(split(buffer, 1, PROTOCOL_START + 1))
			-- 协议有问题返回400
			if not METHOD or not PATH or not VERSION then
				sock:send(ERROR_RESPONSE(http, 400))
				sock:close()
				return 
			end
			-- 没有HEADER返回400
			local HEADER = REQUEST_HEADER_PARSER(split(buffer, PROTOCOL_END + 1, CRLF_START + 2))
			if not next(HEADER) then
				sock:send(ERROR_RESPONSE(http, 400))
				sock:close()
				return 
			end
			-- 这里根据PATH先查找路由, 如果没有直接返回404.
			local cls, typ = HTTP_PROTOCOL.ROUTE_FIND(routes, PATH)
			if not cls or not typ then
				sock:send(ERROR_RESPONSE(http, 404))
				sock:close()
				return 
			end
			-- 根据请求方法进行解析, 解析失败返回501
			local ok, ARGS, FILE = PASER_METHOD(http, sock, buffer, METHOD, PATH, HEADER)
			if not ok then
				sock:send(ERROR_RESPONSE(http, 501))
				sock:close()
				return 
			end

			local header = { }

			local ok, data, static, statucode

			if typ ~= HTTP_PROTOCOL.STATIC then

				local c = cls:new({args = ARGS, file = FILE, method = METHOD, path = PATH, header = HEADER})
				ok, data = pcall(c)
				if not ok then
					log.warn(data)
					statucode = 500
					sock:send(ERROR_RESPONSE(http, statucode))
					sock:close()
					return 
				end
				statucode = 200
				insert(header, REQUEST_STATUCODE_RESPONSE(statucode))
			else
				local file_type
				ok, data, file_type = pcall(cls, './'..PATH)
				if not ok then
					log.warn(data)
					statucode = 500
					sock:send(ERROR_RESPONSE(http, statucode))
					sock:close()
					return
				end
				if not data then
					statucode = 404
					sock:send(ERROR_RESPONSE(http, statucode))
					sock:close()
				else
					statucode = 200
					insert(header, REQUEST_STATUCODE_RESPONSE(statucode))
					static = fmt('Content-Type: %s', REQUEST_MIME_RESPONSE(lower(file_type or '')))
				end
			end

			insert(header, 'Date: ' .. HTTP_DATE())
			insert(header, 'Allow: GET, POST, HEAD')
			insert(header, 'Access-Control-Allow-Origin: *')
			insert(header, 'server: ' .. (server or 'cf/0.1'))

			local Connection = 'Connection: keep-alive'
			if not HEADER['Connection'] or lower(HEADER['Connection']) == 'close' then
				Connection = 'Connection: close'
			end
			insert(header, Connection)
			if typ == HTTP_PROTOCOL.API then
				insert(header, 'Content-Type: '..REQUEST_MIME_RESPONSE('json'))
				insert(header, 'Cache-Control: no-cache, no-store, must-revalidate')
				insert(header, 'Cache-Control: no-cache')
			elseif typ == HTTP_PROTOCOL.USE then
				insert(header, 'Content-Type: '..REQUEST_MIME_RESPONSE('html')..';charset=utf-8')
				insert(header, 'Cache-Control: no-cache, no-store, must-revalidate')
				insert(header, 'Cache-Control: no-cache')
			else
				local cache = 'Cache-Control: no-cache'
				if ttl then
					cache = fmt('Expires: %s', HTTP_DATE(time() + ttl))
				end
				insert(header, cache)
				insert(header, static)
			end
			if data and type(data) == 'string' and #data > 0 then
				insert(header, 'Transfer-Encoding: identity')
				insert(header, fmt('Content-Length: %d', #data))
			end
			sock:send(concat(header, CRLF) .. CRLF2 .. (data or ''))
			if statucode ~= 200 or Connection == 'Connection: keep-alive' then
				return sock:close()
			end
			buffers = {}
		end
	end
end

return HTTP_PROTOCOL