require 'socket'
require 'json'
require 'dotenv'

env = Dotenv.parse(".env")

if not env['HTTP_PORT']
    env['HTTP_PORTP'] = 8002
end

if not env['SERVER_HOSTNAME']
    env['SERVER_HOSTNAME'] = '127.0.0.1'
end

def requestPath connection
    first_line = connection.gets
    puts first_line

    request_verb, full_path = first_line.split(' ')
    path = full_path.split('?')
    path[0]
end

def sendResponse connection, http_status_code, response_body
    connection.write "HTTP/1.1 #{http_status_code}\r\n"
    connection.write "Content-Type: application/json\r\n"
    connection.write "Content-Length: #{response_body.length}\r\n"
    connection.write "\r\n"
    connection.write response_body
    connection.close
end

server = TCPServer.new env['SERVER_HOSTNAME'], env['HTTP_PORT']

while connection = server.accept
    path = requestPath(connection)

    case path
    when "/"
        http_status_code = 200
        response_body = JSON.generate({:message => "Hello, World!"})
    else
        http_status_code = 401
        response_body = JSON.generate({})
    end

    sendResponse(connection, http_status_code, response_body)
end
