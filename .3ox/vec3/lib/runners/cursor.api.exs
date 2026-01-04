# cursor.api.exs :: Elixir-based Cursor Cloud Agent API Client
# Handles external signals outside localized Ruby space
# Called via Ruby bridge (cursor.bridge.rb)

defmodule Cursor.API do
  @moduledoc """
  Elixir module for Cursor Cloud Agent API calls.
  Handles external HTTP signals outside localized Ruby space.
  """

  @cursor_api_base "https://api.cursor.com/v1"
  @timeout 120_000  # 2 minute timeout for AI requests

  # ============================================================================
  # API KEY MANAGEMENT
  # ============================================================================

  def load_api_key do
    # Try environment variable first
    case System.get_env("CURSOR_API_KEY") do
      nil ->
        # Try reading from secrets file (Ruby-compatible path)
        secrets_file = Path.expand("~/.3ox/vec3/rc/secrets/api.keys")
        
        if File.exists?(secrets_file) do
          File.read!(secrets_file)
          |> String.split("\n")
          |> Enum.find_value(fn line ->
            case Regex.run(~r/^CURSOR_API_KEY=(.+)$/, String.trim(line)) do
              [_, key] -> 
                # Remove quotes if present
                String.trim(key, ~r/^["']|["']$/)
              _ -> nil
            end
          end)
        else
          nil
        end
      
      key -> key
    end
  end

  def api_key_configured? do
    load_api_key() != nil
  end

  # ============================================================================
  # CHAT COMPLETIONS
  # ============================================================================

  # Launch a Cursor Cloud Agent
  def launch_agent(prompt, opts \\ []) do
    api_key = load_api_key()
    
    if api_key == nil do
      {:error, :api_key_not_configured}
    else
      model = Keyword.get(opts, :model, nil)  # Optional, Cursor selects if nil
      
      url = "#{@cursor_api_base}/agents"
      
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]
      
      # Cursor API expects prompt as an object with text field
      body = %{
        prompt: %{
          text: prompt
        }
      }
      
      # Add model if specified
      body = if model, do: Map.put(body, :model, model), else: body
      
      body_json = Jason.encode!(body)
      
      case HTTPoison.post(url, body_json, headers, timeout: @timeout, recv_timeout: @timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, reason} -> {:error, {:json_decode_error, reason}}
          end
        
        {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
          {:error, {:http_error, status, error_body}}
        
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, {:connection_error, reason}}
      end
    end
  end
  
  # Legacy chat_completion for compatibility (maps to launch_agent)
  def chat_completion(messages, opts \\ []) do
    # Extract user message from messages array
    user_message = messages
      |> Enum.filter(fn msg -> msg["role"] == "user" || msg[:role] == "user" end)
      |> List.last()
    
    prompt = if user_message do
      Map.get(user_message, "content") || Map.get(user_message, :content) || ""
    else
      ""
    end
    
    # Launch agent with the prompt
    launch_agent(prompt, opts)
  end

  # ============================================================================
  # AGENT COMPLETION (HIGH-LEVEL)
  # ============================================================================

  def agent_completion(prompt, workspace_context \\ nil, opts \\ []) do
    messages = build_messages(prompt, workspace_context)
    
    case chat_completion(messages, opts) do
      {:ok, response} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])
        
        if content do
          {:ok, content}
        else
          {:error, :no_content_in_response}
        end
      
      error -> error
    end
  end

  # ============================================================================
  # CONVERSATION COMPLETION (WITH HISTORY)
  # ============================================================================

  def conversation_completion(prompt, conversation_history \\ [], workspace_context \\ nil, opts \\ []) do
    messages = build_conversation_messages(prompt, conversation_history, workspace_context)
    
    case chat_completion(messages, opts) do
      {:ok, response} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])
        
        if content do
          {:ok, content}
        else
          {:error, :no_content_in_response}
        end
      
      error -> error
    end
  end

  # ============================================================================
  # HEALTH CHECK
  # ============================================================================

  def health_check do
    if not api_key_configured?() do
      {:error, :api_key_not_configured}
    else
      # Check API key info endpoint
      api_key = load_api_key()
      url = "#{@cursor_api_base}/me"
      
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]
      
      case HTTPoison.get(url, headers, timeout: @timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, decoded} -> {:ok, %{available: true, api_info: decoded}}
            {:error, _} -> {:ok, %{available: true}}
          end
        
        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, {:http_error, status}}
        
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, {:connection_error, reason}}
      end
    end
  end

  # ============================================================================
  # MESSAGE BUILDING
  # ============================================================================

  defp build_messages(prompt, workspace_context) do
    system_content = "You are a helpful AI assistant operating within the CMD.BRIDGE framework."
    
    system_content = if workspace_context do
      system_content <> "\n\nWorkspace Context:\n#{workspace_context}"
    else
      system_content
    end
    
    [
      %{role: "system", content: system_content},
      %{role: "user", content: prompt}
    ]
  end

  defp build_conversation_messages(prompt, conversation_history, workspace_context) do
    system_content = "You are a helpful AI assistant operating within the CMD.BRIDGE framework."
    
    system_content = if workspace_context do
      system_content <> "\n\nWorkspace Context:\n#{workspace_context}"
    else
      system_content
    end
    
    messages = [%{role: "system", content: system_content}]
    
    # Add conversation history
    history_messages = Enum.map(conversation_history, fn msg ->
      role = Map.get(msg, "role") || Map.get(msg, :role)
      content = Map.get(msg, "content") || Map.get(msg, :content)
      %{role: role, content: content}
    end)
    
    messages = messages ++ history_messages
    
    # Add current prompt
    messages ++ [%{role: "user", content: prompt}]
  end
end

# ============================================================================
# CLI INTERFACE (for testing)
# ============================================================================

if __ENV__.file do
  # Check dependencies
  http_available = Code.ensure_loaded?(HTTPoison)
  json_available = Code.ensure_loaded?(Jason)
  
  unless http_available do
    IO.puts("⚠ HTTPoison not available - install with: mix deps.get")
  end
  
  unless json_available do
    IO.puts("⚠ Jason not available - install with: mix deps.get")
  end
  
  if http_available and json_available do
    # Test health check
    case Cursor.API.health_check() do
      {:ok, result} ->
        IO.puts("✓ Cursor API health check: #{inspect(result)}")
      
      {:error, :api_key_not_configured} ->
        IO.puts("✗ Cursor API key not configured")
      
      {:error, reason} ->
        IO.puts("✗ Cursor API health check failed: #{inspect(reason)}")
    end
  else
    IO.puts("Install dependencies:")
    IO.puts("  mix deps.get")
  end
end
