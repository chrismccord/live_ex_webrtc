defmodule LiveExWebRTC.Publisher do
  use Phoenix.LiveComponent

  alias ExWebRTC.{PeerConnection, SessionDescription}

  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="Publisher" class="h-full w-full flex justify-between gap-6">
      <div class="w-full flex flex-col">
        <details>
          <summary class="font-bold text-[#0d0d0d] py-2.5">Devices</summary>
          <div class="text-[#606060] flex flex-col gap-6 py-2.5">
            <div class="flex gap-2.5 items-center">
              <label for="lex-audio-devices" class="font-medium">Audio Device</label>
              <select
                id="lex-audio-devices"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              >
              </select>
            </div>
            <div class="flex gap-2.5 items-center">
              <label for="lex-video-devices" class="">Video Device</label>
              <select
                id="lex-video-devices"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              >
              </select>
            </div>
          </div>
        </details>
        <details>
          <summary class="font-bold text-[#0d0d0d] py-2.5">Audio Settings</summary>
          <div class="text-[#606060] flex flex-col gap-6 py-2.5">
            <div class="flex gap-2.5 items-center">
              <label for="lex-echo-cancellation">Echo Cancellation</label>
              <input type="checkbox" id="lex-echo-cancellation" class="rounded-full" checked />
            </div>
            <div class="flex gap-2.5 items-center">
              <label for="lex-auto-gain-control">Auto Gain Control</label>
              <input type="checkbox" id="lex-auto-gain-control" class="rounded-full" checked />
            </div>
            <div class="flex gap-2.5 items-center">
              <label for="lex-noise-suppression">Noise Suppression</label>
              <input type="checkbox" id="lex-noise-suppression" class="rounded-full" checked />
            </div>
          </div>
          <button id="lex-audio-apply-button" class="rounded-lg px-10 py-2.5 bg-brand disabled:bg-brand/50 hover:bg-brand/90 text-white font-bold" disabled>Apply</button>
        </details>
        <details>
          <summary class="font-bold text-[#0d0d0d] py-2.5">Video Settings</summary>
          <div class="text-[#606060] flex flex-col gap-6 py-2.5">
            <div id="lex-resolution" class="flex gap-2.5 items-center">
              <label for="lex-width">Width</label>
              <input
                type="text"
                id="lex-width"
                value="1280"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              />
              <label for="lex-height">Height</label>
              <input
                type="text"
                id="lex-height"
                value="720"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              />
            </div>
            <div class="flex gap-2.5 items-center">
              <label for="lex-fps">FPS</label>
              <input
                type="text"
                id="lex-fps"
                value="24"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              />
            </div>
            <div class="flex gap-2.5 items-center">
              <label for="lex-bitrate">Max Bitrate (kbps)</label>
              <input
                type="text"
                id="lex-bitrate"
                value="1500"
                class="rounded-lg disabled:text-gray-400 disabled:border-gray-400 focus:border-brand focus:outline-none focus:ring-0"
              />
            </div>
          </div>
          <button id="lex-video-apply-button" class="rounded-lg px-10 py-2.5 bg-brand disabled:bg-brand/50 hover:bg-brand/90 text-white font-bold" disabled>Apply</button>
        </details>
        <div id="lex-videoplayer-wrapper" class="flex flex-1 flex-col min-h-0 pt-2.5">
          <video id="lex-preview-player" class="m-auto rounded-lg bg-black h-full" autoplay controls muted>
          </video>
        </div>
        <div id="lex-stats", class="flex justify-between w-full text-[#606060] ">
          <div class="flex p-1 gap-4">
            <div class="flex flex-col">
              <label for="lex-audio-bitrate">Audio Bitrate (kbps): </label>
              <span id="lex-audio-bitrate">0</span>
            </div>
            <div class="flex flex-col">
              <label for="lex-video-bitrate">Video Bitrate (kbps): </label>
              <span id="lex-video-bitrate">0</span>
            </div>
            <div class="flex flex-col">
              <label for="lex-packet-loss">Packet loss (%): </label>
              <span id="lex-packet-loss">0</span>
            </div>
            <div class="flex flex-col">
              <label for="lex-time">Time: </label>
              <span id="lex-time">00:00:00</span>
            </div>
          </div>
          <div class="p-1 flex items-center">
            <div id="lex-status" class="w-3 h-3 rounded-full bg-red-500">
          </div>
          </div>
        </div>
        <div class="py-2.5">
          <button
            id="lex-button"
            class="rounded-lg w-full px-2.5 py-2.5 bg-brand/100 disabled:bg-brand/50 hover:bg-brand/90 text-white font-bold"
            disabled
          >
            Start streaming
          </button>
        </div>
      </div>
    </div>
    """
  end

  def handle_event(_event, _unsigned_params, %{assigns: %{pc: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("offer", unsigned_params, socket) do
    offer = SessionDescription.from_json(unsigned_params)
    {:ok, pc} = spawn_peer_connection(socket)

    :ok = PeerConnection.set_remote_description(pc, offer)

    [
      %{kind: :audio, receiver: %{track: audio_track}},
      %{kind: :video, receiver: %{track: video_track}}
    ] = PeerConnection.get_transceivers(pc)

    info = %{pc: pc, audio_track_id: audio_track.id, video_track_id: video_track.id}
    send(self(), {:live_ex_webrtc, info})

    {:ok, answer} = PeerConnection.create_answer(pc)
    :ok = PeerConnection.set_local_description(pc, answer)
    :ok = gather_candidates(pc)
    answer = PeerConnection.get_local_description(pc)

    socket = assign(socket, :pc, pc)
    socket = push_event(socket, "answer-#{socket.assigns.id}", SessionDescription.to_json(answer))

    {:noreply, socket}
  end

  def handle_event("ice", "null", socket) do
    :ok = PeerConnection.add_ice_candidate(socket.assigns.pc, %{candidate: ""})
    {:noreply, socket}
  end

  def handle_event("ice", unsigned_params, socket) do
    cand =
      unsigned_params
      |> Jason.decode!()
      |> ExWebRTC.ICECandidate.from_json()

    :ok = PeerConnection.add_ice_candidate(socket.assigns.pc, cand)

    {:noreply, socket}
  end

  defp spawn_peer_connection(socket) do
    pc_opts =
      [
        ice_servers: socket.assigns[:ice_servers],
        audio_codecs: socket.assigns[:audio_codecs],
        video_codecs: socket.assigns[:video_codecs],
        ice_port_range: socket.assigns[:ice_port_range]
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    gen_server_opts =
      [name: socket.assigns[:gen_server_name]]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    PeerConnection.start(pc_opts, gen_server_opts)
  end

  defp gather_candidates(pc) do
    # we either wait for all of the candidates
    # or whatever we were able to gather in one second
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> :ok
    end
  end
end
