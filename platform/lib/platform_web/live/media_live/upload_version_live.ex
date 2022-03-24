defmodule PlatformWeb.MediaLive.UploadVersionLive do
  use PlatformWeb, :live_component
  alias Platform.Material
  alias Platform.Utils

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_version()
     |> assign(:internal_params, %{}) # Internal params for uploaded data to keep in the form
     |> assign_changeset()
     |> assign(:form_id, Utils.generate_random_sequence(10))
     |> allow_upload(:media_upload,
      accept: ~w(.png .jpg .jpeg .gif .avi .mp4),
      max_entries: 1,
      max_file_size: 250_000_000,
      auto_upload: true,
      progress: &handle_progress/3
    )
  }
  end

  defp assign_version(socket) do
    socket |> assign(:version, %Material.MediaVersion{media: socket.assigns.media})
  end

  defp assign_changeset(socket) do
    socket |> assign(:changeset, Material.change_media_version(socket.assigns.version))
  end

  defp update_internal_params(socket, key, value) do
    socket |> assign(:internal_params, Map.put(socket.assigns.internal_params, key, value))
  end

  defp all_params(socket, params) do
    Map.merge(params, socket.assigns.internal_params)
  end

  defp handle_static_file(%{path: path}) do
    # Just make a copy of the file; all the real processing is done later in handle_uploaded_file.
    to_path = Temp.path!
    File.cp!(path, to_path)
    {:ok, to_path}
  end

  def handle_event("validate", %{"media_version" => params}, socket) do
    changeset =
      socket.assigns.version |> Material.change_media_version(params) |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:changeset, changeset)}
  end

  def handle_event("save", %{"media_version" => params}, socket) do
    case Material.create_media_version(all_params(socket, params)) do
      {:ok, version} ->
        send(self(), {:version_created, version})
        {:noreply, socket |> assign(:disabled, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media_upload, ref)}
  end

  defp handle_uploaded_file(socket, entry) do
    path = consume_uploaded_entry(socket, entry, &handle_static_file(&1))

    {:ok, path, thumb_path, duration, type} = Material.process_uploaded_media(path, socket.assigns.media.slug)

    socket
    |> update_internal_params("file_location", path)
    |> update_internal_params("duration_seconds", duration)
    |> update_internal_params("mime_type", entry.client_type)
    |> update_internal_params("thumbnail_location", thumb_path)
    |> update_internal_params("client_name", entry.client_name)
  end

  def handle_progress(:media_upload, entry, socket) do
    if entry.done? do
      socket = socket |> handle_uploaded_file(hd(socket.assigns.uploads.media_upload.entries))
    end
    {:noreply, socket}
  end

  defp truncate(str) do
    if String.length(str) > 30 do
      "#{String.slice(str, 0, 27) |> String.trim() }..."
    else
      str
    end
  end

  defp friendly_error(:too_large), do: "This file is too large; the maximum size is 250 megabytes."
  defp friendly_error(:not_accepted), do: "The file type you are uploading is not supported. Please contact us if you think this is an error."

  def render(assigns) do
    uploads = Enum.filter(assigns.uploads.media_upload.entries, &(!&1.cancelled?))
    is_uploading = length(uploads) > 0
    is_invalid = Enum.any?(assigns.uploads.media_upload.entries, &(!&1.valid?))
    is_complete = Enum.any?(assigns.uploads.media_upload.entries, &(&1.done?))

    cancel_upload = if is_uploading do
      ~H"""
      <button phx-click="cancel_upload" phx-target={@myself} phx-value-ref={hd(uploads).ref} class="text-sm label ~neutral" type="button">Cancel Upload</button>
      """
    end

    ~H"""
    <article>
      <.form
        let={f}
        for={@changeset}
        id={"media-upload-#{@form_id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="phx-form"
      >
        <div class="space-y-6">
          <div class="w-full flex justify-center items-center px-6 pt-5 pb-6 border-2 h-40 border-gray-300 border-dashed rounded-md" phx-drop-target={@uploads.media_upload.ref}>
            <%= live_file_input @uploads.media_upload, class: "sr-only" %>
            <%= cond do %>
            <% is_complete -> %>
              <div class="space-y-1 text-center">
                <svg xmlns="http://www.w3.org/2000/svg" class="mx-auto h-12 w-12 text-positive-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div class="w-full text-sm text-gray-600">
                  <%= for entry <- @uploads.media_upload.entries do %>
                    <div class="w-42 mt-4 text-center">
                      <p>Uploaded <%= truncate(entry.client_name) %>.</p>
                    </div>
                  <% end %>
                </div>
                <div>
                  <%= cancel_upload %>
                </div>
              </div>
            <% is_invalid -> %>
              <div class="space-y-1 text-center">
                <svg xmlns="http://www.w3.org/2000/svg" class="mx-auto h-12 w-12 text-critical-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <div class="w-full text-sm text-gray-600">
                  <%= for entry <- @uploads.media_upload.entries do %>
                    <%= for err <- upload_errors(@uploads.media_upload, entry) do %>
                      <p class="my-2"><%= friendly_error(err) %></p>
                    <% end %>
                  <% end %>
                  <label for={@uploads.media_upload.ref} class="relative cursor-pointer bg-white rounded-md font-medium !text-urge-600 hover:text-urge-500 focus-within:outline-none focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-urge-500">
                    <span>Upload another file</span>
                  </label>
                </div>
              </div>
            <% is_uploading -> %>
              <div class="space-y-1 text-center w-full">
                <svg class="mx-auto h-9 w-9 text-gray-400 animate-spin text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <div class="w-full text-sm text-gray-600">
                  <%= for entry <- @uploads.media_upload.entries do %>
                    <%= if entry.progress < 100 and entry.progress > 0 do %>
                    <div class="w-42 mt-4 text-center">
                      <p>Uploading <%= truncate(entry.client_name) %> <span class="text-gray-500">(<%= entry.progress %>%)</span></p>
                      <progress value={entry.progress} max="100" class="progress ~urge mt-2"> <%= entry.progress %>% </progress>
                    </div>
                    <% end %>
                  <% end %>
                </div>
                <div>
                  <%= cancel_upload %>
                </div>
              </div>
            <% true -> %>
              <div class="space-y-1 text-center">
                <svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
                </svg>
                <div class="flex text-sm text-gray-600 justify-center">
                  <label for={@uploads.media_upload.ref} class="relative cursor-pointer bg-white rounded-md font-medium !text-urge-600 hover:text-urge-500 focus-within:outline-none focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-urge-500">
                    <span>Upload a file</span>
                  </label>
                  <p class="pl-1 text-center">or drag and drop</p>
                </div>
                <p class="text-xs text-gray-500">PNG, JPG, GIF, MP4, or AVI up to 250MB</p>
              </div>
            <% end %>
          </div>
          <div>
            <%= label f, :source_url, "Where did this media come from?" %>
            <%= url_input f, :source_url, placeholder: "https://example.com/...", phx_debounce: "blur" %>
            <p class="support">This might be a Twitter post, a Telegram link, or something else. Where did the file come from?</p>
            <%= error_tag f, :source_url %>
          </div>
          <%= submit "Save", phx_disable_with: "Uploading...", class: "button ~urge @high", disabled: @changeset.changes == %{} %>
        </div>
      </.form>
    </article>
    """
  end
end
