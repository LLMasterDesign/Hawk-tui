#!/bin/bash
# imprint.sh :: Imprint.ID Bootstrap and Management
# Ensures Imprint.ID system is running and integrated with vec3

set -e

VEC3_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMPRINT_ROOT="/root/!CMD.BRIDGE/!ZENS3N.CMD/ZENS3N.BASE/Z3N.LABS/Imprint.ID"
SCRIPT_NAME="Imprint.ID Bootstrap"

echo "▛//▞▞ ⟦⎊⟧ :: ⧗-25.125 // $SCRIPT_NAME ▞▞"
echo ""

# Check if Imprint.ID directory exists
if [ ! -d "$IMPRINT_ROOT" ]; then
    echo "✗ Imprint.ID not found at: $IMPRINT_ROOT"
    exit 1
fi

echo "✓ Imprint.ID located"

# Check if already running
if pgrep -f "imprint.*server" > /dev/null 2>&1; then
    echo "✓ Imprint.ID already running"
    exit 0
fi

# Check prerequisites
echo ""
echo "Checking prerequisites..."

# Check Elixir
if ! command -v elixir &> /dev/null; then
    echo "✗ Elixir is required but not installed"
    echo "  Install with: sudo apt install elixir"
    exit 1
fi

ELIXIR_VERSION=$(elixir -v | grep -oP '\d+\.\d+\.\d+' | head -1)
echo "✓ Elixir detected: $ELIXIR_VERSION"

# Check Redis
if ! redis-cli ping &> /dev/null; then
    echo "✗ Redis not running"
    echo "  Starting Redis..."
    redis-server --daemonize yes
    sleep 2

    if ! redis-cli ping &> /dev/null; then
        echo "✗ Failed to start Redis"
        exit 1
    fi
fi

echo "✓ Redis running"

# Check if Imprint.ID is compiled
cd "$IMPRINT_ROOT"
if [ ! -d "_build" ]; then
    echo ""
    echo "Compiling Imprint.ID..."
    mix deps.get
    mix compile
fi

# Create a simple Imprint.ID server script if it doesn't exist
SERVER_SCRIPT="$IMPRINT_ROOT/imprint_server.exs"

if [ ! -f "$SERVER_SCRIPT" ]; then
    echo ""
    echo "Creating Imprint.ID server..."

    cat > "$SERVER_SCRIPT" << 'EOF'
#!/usr/bin/env elixir
# Imprint.ID Server - Simple HTTP server for Imprint.ID operations

Mix.install([
  {:plug_cowboy, "~> 2.5"},
  {:jason, "~> 1.4"},
  {:redix, "~> 1.2"}
])

# Add Imprint.ID to path
Code.append_path("_build/dev/lib/imprint/ebin")

defmodule Imprint.Server do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # Get active imprint
  get "/api/imprint/active" do
    try do
      case Imprint.load_active() do
        {:ok, imprint} ->
          send_resp(conn, 200, Jason.encode!(imprint))
        {:error, :no_active_imprint} ->
          send_resp(conn, 404, Jason.encode!(%{error: "no_active_imprint"}))
        {:error, reason} ->
          send_resp(conn, 500, Jason.encode!(%{error: to_string(reason)}))
      end
    rescue
      e ->
        Logger.error("Error loading active imprint: #{inspect(e)}")
        send_resp(conn, 500, Jason.encode!(%{error: "internal_error"}))
    end
  end

  # Submit receipt
  post "/api/receipt" do
    try do
      receipt = conn.body_params
      Imprint.ReceiptWriter.write_receipt(receipt)
      send_resp(conn, 201, Jason.encode!(%{status: "ok"}))
    rescue
      e ->
        Logger.error("Error writing receipt: #{inspect(e)}")
        send_resp(conn, 500, Jason.encode!(%{error: "receipt_write_failed"}))
    end
  end

  # Health check
  get "/health" do
    redis_status = case Redix.command(:imprint_redis, ["PING"]) do
      {:ok, "PONG"} -> "ok"
      _ -> "error"
    end

    send_resp(conn, 200, Jason.encode!(%{
      status: "ok",
      redis: redis_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }))
  end

  # 404 for unmatched routes
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not_found"}))
  end
end

# Start Redis connection
{:ok, redis} = Redix.start_link(host: "localhost", port: 6379, name: :imprint_redis)

# Start the server
Logger.info("Starting Imprint.ID server on port 4000")
Plug.Cowboy.http(Imprint.Server, [], port: 4000)

# Keep running
Process.sleep(:infinity)
EOF

    chmod +x "$SERVER_SCRIPT"
    echo "✓ Imprint.ID server script created"
fi

# Start Imprint.ID server in background
echo ""
echo "Starting Imprint.ID server..."
cd "$IMPRINT_ROOT"
elixir "$SERVER_SCRIPT" &
SERVER_PID=$!

# Wait a moment for startup
sleep 3

# Check if server started successfully
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✓ Imprint.ID server started (PID: $SERVER_PID)"

    # Test health endpoint
    if curl -s http://localhost:4000/health > /dev/null; then
        echo "✓ Imprint.ID health check passed"

        # Save PID for management
        echo $SERVER_PID > "$VEC3_ROOT/var/state/imprint.pid"

        echo ""
        echo "▛▞ $SCRIPT_NAME Complete ▞▞"
        echo ""
        echo "Imprint.ID is now running and integrated with vec3"
        echo "  - Server PID: $SERVER_PID"
        echo "  - Health: http://localhost:4000/health"
        echo "  - Active Imprint: http://localhost:4000/api/imprint/active"
        echo ""

    else
        echo "⚠ Imprint.ID server started but health check failed"
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi
else
    echo "✗ Failed to start Imprint.ID server"
    exit 1
fi

:: ∎