defmodule PlatformWeb.AdminlandLive.Index do
  use PlatformWeb, :live_view
  alias Platform.Material

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    # We pass the full socket to children for audit logging
    {:noreply, socket |> assign(:full_socket, socket)}
  end
end
