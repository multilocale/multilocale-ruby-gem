# frozen_string_literal: true

require "json"
require "socket"

# A real HTTP server on a real socket, so the specs exercise Net::HTTP, the
# headers this gem sets and the exact bytes it puts on the wire — a mocked
# adapter would happily accept a wrong Authorization scheme forever.
#
#   api = StubApi.new
#   api.on(:get, "/api/projects") { [200, [{ "_id" => "…" }]] }
#   Multilocale::Client.new(api_key: "s3cret", api_url: api.url)
#   api.requests.first.headers["authorization"]
class StubApi
  Request = Struct.new(:method, :path, :query, :headers, :body, keyword_init: true) do
    def json
      body.nil? || body.empty? ? nil : JSON.parse(body)
    end

    # Raw, still-encoded query value: the point of several specs is what the
    # transport actually sent, not what a parser makes of it.
    def raw_param(name)
      (query || "").split("&").each do |pair|
        key, value = pair.split("=", 2)
        return value if key == name
      end
      nil
    end

    def param(name)
      value = raw_param(name)
      value && value.gsub(/%([0-9A-Fa-f]{2})/) { [::Regexp.last_match(1)].pack("H2") }
    end
  end

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @routes = []
    @requests = []
    @mutex = Mutex.new
    @thread = Thread.new { accept_loop }
    @thread.abort_on_exception = false
  end

  def port
    @server.addr[1]
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  # Handlers return [status, body], where body is anything JSON-serialisable or
  # a String sent verbatim. One handler per method+path; a spec that needs a
  # sequence ("429, then 200") counts calls inside its own block.
  def on(method, path, &handler)
    @mutex.synchronize { @routes << { method: method.to_s.upcase, path: path, handler: handler } }
    self
  end

  def requests
    @mutex.synchronize { @requests.dup }
  end

  def stop
    @thread&.kill
    @server.close unless @server.closed?
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      handle(socket)
    rescue IOError, Errno::EBADF
      break
    end
  end

  def handle(socket)
    request = read_request(socket)
    return socket.close if request.nil?

    @mutex.synchronize { @requests << request }

    route = @mutex.synchronize do
      @routes.find { |candidate| candidate[:method] == request.method && candidate[:path] == request.path }
    end

    status, body =
      if route
        route[:handler].call(request)
      else
        [404, { "status" => 404, "message" => "no stub for #{request.method} #{request.path}" }]
      end

    write_response(socket, status, body)
  rescue StandardError => error
    write_response(socket, 500, { "message" => "stub error: #{error.class}: #{error.message}" })
  ensure
    socket.close unless socket.closed?
  end

  def read_request(socket)
    line = socket.gets
    return nil if line.nil?

    method, target, = line.split(" ")
    path, query = target.split("?", 2)

    headers = {}
    while (header = socket.gets) && header != "\r\n"
      name, value = header.split(":", 2)
      headers[name.to_s.strip.downcase] = value.to_s.strip
    end

    length = headers["content-length"].to_i
    body = length.positive? ? socket.read(length) : nil

    Request.new(method: method, path: path, query: query, headers: headers, body: body)
  end

  def write_response(socket, status, body)
    payload = body.is_a?(String) ? body : JSON.generate(body)
    socket.write("HTTP/1.1 #{status} #{status_text(status)}\r\n")
    socket.write("Content-Type: application/json\r\n")
    socket.write("Content-Length: #{payload.bytesize}\r\n")
    socket.write("Connection: close\r\n\r\n")
    socket.write(payload)
  end

  def status_text(status)
    {
      200 => "OK", 201 => "Created", 401 => "Unauthorized", 403 => "Forbidden",
      404 => "Not Found", 429 => "Too Many Requests", 500 => "Internal Server Error",
      503 => "Service Unavailable"
    }.fetch(status, "Status")
  end
end
