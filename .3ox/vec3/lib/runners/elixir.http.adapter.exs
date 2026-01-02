# elixir_http_adapter.exs :: HTTP Adapter for Imprint.ID Integration
# Provides HTTP interface between PHENO vec3 and Imprint.ID system

defmodule Vec3.HttpAdapter do
  @moduledoc """
  HTTP adapter for PHENO vec3 operations to communicate with Imprint.ID
  """

  @imprint_url "http://localhost:4000"  # Default Imprint.ID server
  @timeout 30000  # 30 second timeout

  def submit_pheno_operation(operation_data) do
    url = "#{@imprint_url}/api/pheno/execute"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Vec3-Version", "1.0.0"}
    ]

    body = Jason.encode!(operation_data)

    case HTTPoison.post(url, body, headers, timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
        {:error, {:http_error, status, error_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:connection_error, reason}}
    end
  end

  def get_active_imprint do
    url = "#{@imprint_url}/api/imprint/active"

    case HTTPoison.get(url, [], timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :no_active_imprint}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:connection_error, reason}}
    end
  end

  def submit_receipt(receipt_data) do
    url = "#{@imprint_url}/api/receipt"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Vec3-Version", "1.0.0"}
    ]

    body = Jason.encode!(receipt_data)

    case HTTPoison.post(url, body, headers, timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 201}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
        {:error, {:http_error, status, error_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:connection_error, reason}}
    end
  end

  def validate_route(imprint_id, user_input) do
    url = "#{@imprint_url}/api/route/validate"

    headers = [
      {"Content-Type", "application/json"},
      {"X-Imprint-ID", imprint_id}
    ]

    body = Jason.encode!(%{input: user_input})

    case HTTPoison.post(url, body, headers, timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_response}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
        {:error, {:http_error, status, error_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:connection_error, reason}}
    end
  end

  # Configuration helpers
  def configure(base_url \\ @imprint_url) do
    Application.put_env(:vec3, :imprint_url, base_url)
  end

  def configured_url do
    Application.get_env(:vec3, :imprint_url, @imprint_url)
  end
end

# Script execution for testing (when run directly)
if __ENV__.file == __FILE__ do
  # Test the adapter if HTTPoison is available
  case Code.ensure_loaded?(HTTPoison) do
    true ->
      IO.puts("✓ HTTPoison available - adapter ready")
    false ->
      IO.puts("⚠ HTTPoison not loaded - install with: mix deps.get")
  end

  IO.puts("Vec3 HTTP Adapter loaded")
  IO.puts("Configured Imprint.ID URL: #{Vec3.HttpAdapter.configured_url()}")
end