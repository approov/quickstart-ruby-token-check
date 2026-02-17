#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'logger'
require 'thread'
require 'time'
require 'webrick'
require 'jwt'

begin
  require 'dotenv'
  Dotenv.load('.env')
rescue LoadError
  # Optional in production; environment variables may be injected externally.
end

module ApproovApplication
  PLACEHOLDER_SECRET = 'approov_base64url_secret_here'
  APPROOV_HEADER = 'Approov-Token'
  SUCCESS_STATUS = 200
  UNAUTHORIZED_STATUS = 401
  LOG_EVENT_NAME = 'http.request.completed'

  DEFAULT_HEADERS = {
    'Content-Type' => 'application/json',
    'Cache-Control' => 'no-cache'
  }.freeze

  ProtectedRoute = Struct.new(:path, :bound_headers, keyword_init: true)

  # Protected route requirements are defined here.
  PROTECTED_ROUTES = [
    ProtectedRoute.new(path: '/token-check', bound_headers: []),
    ProtectedRoute.new(path: '/token-binding', bound_headers: ['Authorization']),
    ProtectedRoute.new(path: '/token-double-binding', bound_headers: ['Authorization', 'SessionId'])
  ].freeze

  class ValidationError
    attr_reader :reason, :message, :exception

    def initialize(reason:, message: nil, exception: nil)
      @reason = reason
      @message = message
      @exception = exception
    end
  end

  class ValidationResult
    attr_reader :required_headers, :claims, :error

    def initialize(required_headers:, claims: nil, error: nil)
      @required_headers = required_headers.freeze
      @claims = claims
      @error = error
    end

    def success?
      @error.nil?
    end

    def self.success(required_headers, claims: nil)
      new(required_headers: required_headers, claims: claims)
    end

    def self.failure(required_headers, reason:, message: nil, exception: nil)
      new(
        required_headers: required_headers,
        error: ValidationError.new(reason: reason, message: message, exception: exception)
      )
    end
  end

  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  class RuntimeState
    def initialize
      @mutex = Mutex.new
      @approov_enabled = true
      @token_binding_enabled = true
    end

    def approov_enabled?
      @mutex.synchronize { @approov_enabled }
    end

    def token_binding_enabled?
      @mutex.synchronize { @token_binding_enabled }
    end

    def enable_approov!
      @mutex.synchronize do
        @approov_enabled = true
        @token_binding_enabled = true
      end
    end

    def disable_approov!
      @mutex.synchronize do
        @approov_enabled = false
        @token_binding_enabled = false
      end
    end

    def enable_token_binding!
      @mutex.synchronize { @token_binding_enabled = true }
    end

    def disable_token_binding!
      @mutex.synchronize { @token_binding_enabled = false }
    end

    def to_h
      @mutex.synchronize do
        {
          'approovEnabled' => @approov_enabled,
          'tokenBindingEnabled' => @token_binding_enabled
        }
      end
    end
  end

  class Config
    attr_reader :hostname, :http_port, :approov_secret

    def initialize(env:, logger:)
      @hostname = (env['SERVER_HOSTNAME'] || '0.0.0.0').strip
      @http_port = parse_port(env['HTTP_PORT'])
      @approov_secret = parse_secret(env['APPROOV_BASE64URL_SECRET'], logger)
    end

    private

    def parse_port(raw_port)
      normalized = (raw_port || '8080').strip
      Integer(normalized, 10)
    rescue ArgumentError
      raise ArgumentError, "Invalid HTTP_PORT value: #{normalized.inspect}"
    end

    def parse_secret(raw_secret, logger)
      normalized = raw_secret&.strip
      if normalized.nil? || normalized.empty? || normalized == PLACEHOLDER_SECRET
        logger.error('Required secret is not set')
        raise ArgumentError, 'Required secret is not set'
      end

      begin
        decode_base64url(normalized)
      rescue ArgumentError
        logger.error('Required secret is invalid')
        raise ArgumentError, 'Required secret is invalid'
      end
    end

    def decode_base64url(base64url_value)
      padding_size = (4 - (base64url_value.length % 4)) % 4
      padded = base64url_value + ('=' * padding_size)
      Base64.urlsafe_decode64(padded)
    end
  end

  module RequestHeaders
    module_function

    def get(request, header_name)
      values = request.header[header_name.downcase]
      return nil if values.nil? || values.empty?

      normalized = values.first.to_s.strip
      normalized.empty? ? nil : normalized
    end
  end

  class TokenValidator
    def initialize(secret:, state:)
      @secret = secret
      @state = state
    end

    # Middleware calls this and receives errors instead of HTTP responses.
    def validate(request:, protected_route:)
      required_headers = required_headers_for(protected_route.path)

      approov_token = RequestHeaders.get(request, APPROOV_HEADER)
      unless approov_token
        return ValidationResult.failure(required_headers, reason: 'missing_approov_token')
      end

      token_result = verify_approov_token(token: approov_token, required_headers: required_headers)
      return token_result unless token_result.success?

      claims = token_result.claims

      return ValidationResult.success(required_headers, claims: claims) unless token_binding_required?(protected_route)

      verify_token_binding(
        request: request,
        claims: claims,
        bound_headers: protected_route.bound_headers,
        required_headers: required_headers
      )
    end

    def required_headers_for(path)
      route = protected_route_for(path)
      return [] unless route

      if token_binding_required?(route)
        [APPROOV_HEADER, *route.bound_headers]
      else
        [APPROOV_HEADER]
      end
    end

    # JWT Approov Token validation (signature + expiry).
    def verify_approov_token(token:, required_headers:)
      claims, = JWT.decode(token, @secret, true, algorithms: ['HS256'], verify_expiration: true)

      expiration = claims['exp']
      unless expiration
        return ValidationResult.failure(
          required_headers,
          reason: 'token_verification_failed',
          message: 'Approov token missing exp claim'
        )
      end

      if Time.at(expiration.to_i) <= Time.now.utc
        return ValidationResult.failure(
          required_headers,
          reason: 'token_verification_failed',
          message: 'Approov token expired',
          exception: 'JWT::ExpiredSignature'
        )
      end

      ValidationResult.success(required_headers, claims: claims)
    rescue JWT::DecodeError, JWT::ExpiredSignature => error
      ValidationResult.failure(
        required_headers,
        reason: 'token_verification_failed',
        message: error.message,
        exception: error.class.name
      )
    end

    # Token binding (pay + hash): base64(sha256(binding_value)).
    def verify_token_binding(request:, claims:, bound_headers:, required_headers:)
      expected_pay = claims['pay']&.to_s&.strip
      unless expected_pay && !expected_pay.empty?
        return ValidationResult.failure(
          required_headers,
          reason: 'binding_mismatch',
          message: 'Approov token missing pay claim'
        )
      end

      binding_value = binding_value_for(request: request, bound_headers: bound_headers)
      unless binding_value
        return ValidationResult.failure(required_headers, reason: 'missing_binding_header')
      end

      computed_pay = token_binding_hash(binding_value)
      return ValidationResult.success(required_headers, claims: claims) if secure_compare(expected_pay, computed_pay)

      ValidationResult.failure(required_headers, reason: 'binding_mismatch')
    end

    # Binding value selection (what gets hashed).
    # Builds a string by concatenating header values in bound_headers order.
    def binding_value_for(request:, bound_headers:)
      values = bound_headers.map { |header_name| RequestHeaders.get(request, header_name) }
      return nil if values.any?(&:nil?)

      values.join
    end

    def token_binding_hash(binding_value)
      digest = Digest::SHA256.digest(binding_value)
      Base64.strict_encode64(digest)
    end

    private

    def token_binding_required?(route)
      @state.token_binding_enabled? && !route.bound_headers.empty?
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      result = 0
      left.bytes.zip(right.bytes) { |a, b| result |= (a ^ b) }
      result.zero?
    end

    def protected_route_for(path)
      PROTECTED_ROUTES.find { |route| route.path == path }
    end
  end

  class ApiRouter
    def initialize(state:, server_port:)
      @state = state
      @server_port = server_port
    end

    # Protected routes are registered in this router.
    def call(request)
      method = request.request_method
      path = request.path

      case [method, path]
      when ['GET', '/']
        ok(info_payload("Approov demo API is running on port #{@server_port}."))
      when ['GET', '/approov-state']
        ok(@state.to_h)
      when ['POST', '/approov/enable']
        @state.enable_approov!
        ok(@state.to_h)
      when ['POST', '/approov/disable']
        @state.disable_approov!
        ok(@state.to_h)
      when ['POST', '/token-binding/enable']
        @state.enable_token_binding!
        ok(@state.to_h)
      when ['POST', '/token-binding/disable']
        @state.disable_token_binding!
        ok(@state.to_h)
      when ['GET', '/unprotected']
        ok(info_payload("Unprotected endpoint '/unprotected'; no Approov checks performed."))
      when ['GET', '/token-check']
        ok(info_payload("Protected endpoint '/token-check'; Approov token verified."))
      when ['GET', '/token-binding']
        payload = info_payload("Protected endpoint '/token-binding'; Approov token binding enforced.")
        payload['authorizationHeaderPresent'] = !RequestHeaders.get(request, 'Authorization').nil?
        ok(payload)
      when ['GET', '/token-double-binding']
        payload = info_payload("Protected endpoint '/token-double-binding'; dual token binding enforced.")
        payload['authorizationHeaderPresent'] = !RequestHeaders.get(request, 'Authorization').nil?
        payload['sessionIdHeaderPresent'] = !RequestHeaders.get(request, 'SessionId').nil?
        ok(payload)
      else
        unauthorized
      end
    end

    private

    def info_payload(details)
      payload = @state.to_h
      payload['details'] = details
      payload
    end

    def ok(payload)
      json_response(SUCCESS_STATUS, payload)
    end

    def unauthorized
      json_response(UNAUTHORIZED_STATUS, {})
    end

    def json_response(status, payload)
      Response.new(
        status: status,
        headers: DEFAULT_HEADERS.dup,
        body: JSON.generate(payload)
      )
    end
  end

  class ApproovMiddleware
    LOGGABLE_STATUSES = [SUCCESS_STATUS, UNAUTHORIZED_STATUS].freeze

    def initialize(app:, state:, validator:, logger:, server_port:)
      @app = app
      @state = state
      @validator = validator
      @logger = logger
      @server_port = server_port
    end

    # Middleware enforcement for protected routes.
    def call(request)
      protected_route = protected_route_for(request.path)
      return call_unprotected(request) unless protected_route

      required_headers = @validator.required_headers_for(request.path)

      unless @state.approov_enabled?
        response = @app.call(request)
        summary = response.status == UNAUTHORIZED_STATUS ? 'approov_failed:downstream_unauthorized' : 'approov_disabled'
        log_request(request: request, response: response, summary: summary, required_headers: required_headers)
        return response
      end

      validation = @validator.validate(request: request, protected_route: protected_route)
      unless validation.success?
        response = Response.new(status: UNAUTHORIZED_STATUS, headers: DEFAULT_HEADERS.dup, body: JSON.generate({}))
        log_request(
          request: request,
          response: response,
          summary: "approov_failed:#{validation.error.reason}",
          required_headers: validation.required_headers,
          error: validation.error
        )
        return response
      end

      response = @app.call(request)
      summary = response.status == UNAUTHORIZED_STATUS ? 'approov_failed:downstream_unauthorized' : 'approov_ok'
      log_request(request: request, response: response, summary: summary, required_headers: validation.required_headers)
      response
    end

    private

    def call_unprotected(request)
      response = @app.call(request)
      log_request(
        request: request,
        response: response,
        summary: 'unprotected',
        required_headers: []
      )
      response
    end

    def log_request(request:, response:, summary:, required_headers:, error: nil)
      status = response.status.to_i
      return unless LOGGABLE_STATUSES.include?(status)

      fields = []
      fields << %("summary":#{JSON.generate(summary)})
      fields << %("method":#{JSON.generate(request.request_method)})
      fields << %("path":#{JSON.generate(request.path)})
      fields << %("status":#{status})
      fields << %("ip":#{JSON.generate(remote_ip(request))})
      fields << %("port":#{@server_port})
      fields << %("state":#{JSON.generate(@state.to_h)})
      fields << %("required_headers":#{JSON.generate(required_headers)})
      fields << %("error":#{JSON.generate(error.message)}) if error&.message
      fields << %("exception":#{JSON.generate(error.exception)}) if error&.exception

      line = "#{LOG_EVENT_NAME} #{fields.join(',')}"
      if error
        @logger.warn(line)
      else
        @logger.info(line)
      end
    end

    def remote_ip(request)
      request.remote_ip
    rescue StandardError
      'unknown'
    end

    def protected_route_for(path)
      PROTECTED_ROUTES.find { |route| route.path == path }
    end
  end

  class HttpServer
    def initialize(host:, port:, app:, logger:)
      @host = host
      @port = port
      @app = app
      @logger = logger

      @server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: @host,
        AccessLog: [],
        Logger: WEBrick::Log.new($stdout, WEBrick::Log::WARN)
      )

      @server.mount_proc('/') { |request, response| handle(request, response) }

      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @server.shutdown }
      end
    end

    def start
      @logger.info(%(server.started "host":#{JSON.generate(@host)},"port":#{@port}))
      @server.start
    end

    private

    def handle(request, response)
      app_response = @app.call(request)
      response.status = app_response.status
      app_response.headers.each { |name, value| response[name] = value }
      response.body = app_response.body
    rescue StandardError => error
      @logger.error(
        'http.request.failed ' \
        "\"method\":#{JSON.generate(request.request_method)}," \
        "\"path\":#{JSON.generate(request.path)}," \
        "\"error\":#{JSON.generate(error.message)}," \
        "\"exception\":#{JSON.generate(error.class.name)}"
      )
      response.status = 500
      response['Content-Type'] = 'application/json'
      response['Cache-Control'] = 'no-cache'
      response.body = JSON.generate({})
    end
  end

  def self.build_logger
    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    logger.formatter = proc do |_severity, datetime, _prog_name, message|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{message}\n"
    end
    logger
  end

  def self.build_app(env:, logger:)
    config = Config.new(env: env, logger: logger)
    state = RuntimeState.new
    validator = TokenValidator.new(secret: config.approov_secret, state: state)
    router = ApiRouter.new(state: state, server_port: config.http_port)
    middleware = ApproovMiddleware.new(
      app: router,
      state: state,
      validator: validator,
      logger: logger,
      server_port: config.http_port
    )
    [config, middleware]
  end
end

if $PROGRAM_NAME == __FILE__
  logger = ApproovApplication.build_logger

  begin
    config, app = ApproovApplication.build_app(env: ENV, logger: logger)
  rescue ArgumentError => error
    logger.fatal(error.message)
    exit(1)
  end

  ApproovApplication::HttpServer.new(
    host: config.hostname,
    port: config.http_port,
    app: app,
    logger: logger
  ).start
end
