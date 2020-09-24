require 'socket'
require 'json'
require 'dotenv'
require 'jwt'
require 'base64'
require 'digest'

env = Dotenv.parse(".env")

if not env['HTTP_PORT']
    env['HTTP_PORTP'] = 8002
end

if not env['SERVER_HOSTNAME']
    env['SERVER_HOSTNAME'] = '127.0.0.1'
end

if not env['APPROOV_BASE64_SECRET']
    raise "Missing in the .env file the value for the variable: APPROOV_BASE64_SECRET"
end

APPROOV_SECRET = Base64.decode64(env['APPROOV_BASE64_SECRET'])

def verifyApproovToken headers
    begin
        approov_token = headers['approov-token']

        if not approov_token
            # You may want to add some logging here
            return nil
        end

        options = { algorithm: 'HS256' }
        approov_token_claims, header = JWT.decode approov_token, APPROOV_SECRET, true, options

        return approov_token_claims
    rescue JWT::DecodeError => e
        # You may want to add some logging here
        return nil
    rescue JWT::ExpiredSignature => e
        # You may want to add some logging here
        return nil
    rescue JWT::InvalidIssuerError => e
        # You may want to add some logging here
        return nil
    rescue JWT::InvalidIatError
        # You may want to add some logging here
        return nil
    end

    return nil
end

def verifyApproovTokenBinding headers, approov_token_claims
    # Note that the `pay` claim will, under normal circumstances, be present,
    # but if the Approov failover system is enabled, then no claim will be
    # present, and in this case you want to return true, otherwise you will not
    # be able to benefit from the redundancy afforded by the failover system.
    if not approov_token_claims['pay']
        # You may want to add some logging here
        return true
    end

    # We use the Authorization token, but feel free to use another header in
    # the request. Beqar in mind that it needs to be the same header used in the
    # mobile app to qbind the request with the Approov token.
    token_binding_header = headers['authorization']

    if not token_binding_header
        # You may want to add some logging here
        return false
    end

    # We need to hash and base64 encode the token binding header, because that's
    # how it was included in the Approov token on the mobile app.
    token_binding_header_encoded = Digest::SHA256.base64digest token_binding_header

    if not approov_token_claims['pay'] === token_binding_header_encoded
        # You may want to add some logging here
        return false
    end

    return true
end

def requestHeaders connection
    headers = {}

    while line = connection.gets
        case line
        when "\r\n"
            break
        else
            key, value = line.split(': ')
            headers[key.downcase] = value.strip
        end
    end

    headers
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
    headers = requestHeaders(connection)

    if not approov_token_claims = verifyApproovToken(headers)
        sendResponse(connection, 401, JSON.generate({}))
        next
    end

    if not verifyApproovTokenBinding(headers, approov_token_claims)
        sendResponse(connection, 401, JSON.generate({}))
        next
    end

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
