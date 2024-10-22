defmodule LiveExWebRTC.Publisher do
  @moduledoc """
  Component for sending audio and video via WebRTC from a browser to a Phoenix app (browser publishes).

  It will render a view with:
  * audio and video device selects
  * audio and video stream configs
  * stream preview
  * transmission stats

  Once rendered, your `Phoenix.LiveView` will receive `t:init_msg/0` and will start getting
  RTP audio and video packets that can be forwarded to other clients.

  Publisher always negotiates a single audio and video track.

  ## Assigns

  * `ice_servers` - a list of `t:ExWebRTC.PeerConnection.Configuration.ice_server/0`,
  * `ice_ip_filter` - `t:ExICE.ICEAgent.ip_filter/0`,
  * `ice_port_range` - `t:Enumerable.t(non_neg_integer())/1`,
  * `audio_codecs` - a list of `t:ExWebRTC.RTPCodecParameters.t/0`,
  * `video_codecs` - a list of `t:ExWebRTC.RTPCodecParameters.t/0`,
  * `gen_server_name` - `t:GenServer.name/0`

  ## JavaScript Hook

  Publisher live component requires JavaScript hook to be registered under `Publisher` name.
  The hook can be created using `createPublisherHook` function.
  For example:

  ```javascript
  import { createPublisherHook } from "live_ex_webrtc";
  let Hooks = {};
  const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
  Hooks.Publisher = createPublisherHook(iceServers);
  let liveSocket = new LiveSocket("/live", Socket, {
    // ...
    hooks: Hooks
  });
  ```

  ## Examples

  ```elixir
  TODO
  ```
  """
  use Phoenix.LiveComponent

  alias LiveExWebRTC.Publisher
  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Phoenix.PubSub

  defstruct id: nil,
            pc: nil,
            streaming?: false,
            audio_track_id: nil,
            video_track_id: nil,
            on_packet: nil,
            on_connected: nil,
            pubsub: nil,
            ice_servers: nil,
            ice_ip_filter: nil,
            ice_port_range: nil,
            audio_codecs: nil,
            video_codecs: nil,
            name: nil

  attr(:publisher, __MODULE__, required: true)

  slot :start
  slot :stop

  def studio(assigns) do
    ~H"""
    <div id={@publisher.id} phx-hook="Publisher" class="h-full w-full flex justify-between gap-6">
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
        <div :if={@publisher.streaming?} class="py-2.">
          <button
            id="lex-button"
            class="rounded-lg w-full px-2.5 py-2.5 bg-brand/100 disabled:bg-brand/50 hover:bg-brand/90 text-white font-bold"
            phx-click="stop-streaming"
          >
            <%= if @start == [] do %>
              Stop streaming
            <% else %>
              <%= render_slot(@stop, []) %>
            <% end %>
          </button>
        </div>
        <div :if={!@publisher.streaming?} class="py-2.5">
          <button
            id="lex-button"
            class="rounded-lg w-full px-2.5 py-2.5 bg-brand/100 disabled:bg-brand/50 hover:bg-brand/90 text-white font-bold"
            phx-click="start-streaming"
          >
            <%= if @start == [] do %>
              Start streaming
            <% else %>
              <%= render_slot(@start, []) %>
            <% end %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  def attach(socket, opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :pubsub,
        :on_packet,
        :on_connected,
        :ice_servers,
        :ice_ip_filter,
        :ice_port_range,
        :audio_codecs,
        :video_codecs
      ])

    publisher = %Publisher{
      id: Keyword.fetch!(opts, :id),
      pubsub: Keyword.fetch!(opts, :pubsub),
      on_packet: Keyword.get(opts, :on_packet, fn _kind, _packet, sock -> sock end),
      on_connected: Keyword.get(opts, :on_connected, fn sock -> sock end),
      ice_servers: Keyword.get(opts, :ice_servers, [%{urls: "stun:stun.l.google.com:19302"}]),
      ice_ip_filter: Keyword.get(opts, :ice_ip_filter),
      ice_port_range: Keyword.get(opts, :ice_port_range),
      audio_codecs: Keyword.get(opts, :audio_codecs),
      video_codecs: Keyword.get(opts, :video_codecs),
      name: Keyword.get(opts, :name)
    }

    socket
    |> assign(publisher: publisher)
    |> attach_hook(:publisher_infos, :handle_info, &attached_handle_info/2)
    |> attach_hook(:publisher_events, :handle_event, &attached_handle_event/3)
  end

  defp attached_handle_info({:live_ex_webrtc, :keyframe_req}, socket) do
    %{publisher: publisher} = socket.assigns

    if pc = publisher.pc do
      :ok = PeerConnection.send_pli(pc, publisher.video_track_id)
    end

    {:halt, socket}
  end

  defp attached_handle_info({:ex_webrtc, _pc, {:rtp, track_id, nil, packet}}, socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %Publisher{video_track_id: ^track_id} ->
        PubSub.broadcast(
          publisher.pubsub,
          "streams:video:#{publisher.id}",
          {:live_ex_webrtc, :video, packet}
        )

        %Phoenix.LiveView.Socket{} = new_socket = publisher.on_packet.(:video, packet, socket)
        {:halt, new_socket}

      %Publisher{audio_track_id: ^track_id} ->
        PubSub.broadcast(
          publisher.pubsub,
          "streams:audio:#{publisher.id}",
          {:live_ex_webrtc, :audio, packet}
        )

        %Phoenix.LiveView.Socket{} = new_socket = publisher.on_packet.(:audio, packet, socket)
        {:halt, new_socket}
    end
  end

  defp attached_handle_info({:ex_webrtc, _pid, {:connection_state_change, :connected}}, socket) do
    %{publisher: pub} = socket.assigns
    %Phoenix.LiveView.Socket{} = new_socket = pub.on_connected.(socket)
    {:halt, new_socket}
  end

  defp attached_handle_info({:ex_webrtc, _, _}, socket) do
    {:halt, socket}
  end

  defp attached_handle_info(_msg, socket), do: {:cont, socket}

  defp attached_handle_event("start-streaming", _, socket) do
    {:halt,
     socket
     |> assign(publisher: %Publisher{socket.assigns.publisher | streaming?: true})
     |> push_event("start-streaming", %{})}
  end

  defp attached_handle_event("stop-streaming", _, socket) do
    {:halt,
     socket
     |> assign(publisher: %Publisher{socket.assigns.publisher | streaming?: false})
     |> push_event("stop-streaming", %{})}
  end

  defp attached_handle_event("offer", unsigned_params, socket) do
    %{publisher: publisher} = socket.assigns
    offer = SessionDescription.from_json(unsigned_params)
    {:ok, pc} = spawn_peer_connection(socket)

    :ok = PeerConnection.set_remote_description(pc, offer)

    [
      %{kind: :audio, receiver: %{track: audio_track}},
      %{kind: :video, receiver: %{track: video_track}}
    ] = PeerConnection.get_transceivers(pc)

    {:ok, answer} = PeerConnection.create_answer(pc)
    :ok = PeerConnection.set_local_description(pc, answer)
    :ok = gather_candidates(pc)
    answer = PeerConnection.get_local_description(pc)

    # subscribe now that we are initialized
    PubSub.subscribe(publisher.pubsub, "publishers:#{publisher.id}")

    new_publisher = %Publisher{
      publisher
      | pc: pc,
        audio_track_id: audio_track.id,
        video_track_id: video_track.id
    }

    %Phoenix.LiveView.Socket{} = new_socket = new_publisher.on_connected.(socket)

    {:halt,
     new_socket
     |> assign(publisher: new_publisher)
     |> push_event("answer-#{publisher.id}", SessionDescription.to_json(answer))}
  end

  defp attached_handle_event("ice", "null", socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %Publisher{pc: nil} ->
        {:halt, socket}

      %Publisher{pc: pc} ->
        :ok = PeerConnection.add_ice_candidate(pc, %ICECandidate{candidate: ""})
        {:halt, socket}
    end
  end

  defp attached_handle_event("ice", unsigned_params, socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %Publisher{pc: nil} ->
        {:halt, socket}

      %Publisher{pc: pc} ->
        cand =
          unsigned_params
          |> Jason.decode!()
          |> ExWebRTC.ICECandidate.from_json()

        :ok = PeerConnection.add_ice_candidate(pc, cand)

        {:halt, socket}
    end
  end

  defp spawn_peer_connection(socket) do
    %{publisher: publisher} = socket.assigns

    pc_opts =
      [
        ice_servers: publisher.ice_servers,
        ice_ip_filter: publisher.ice_ip_filter,
        ice_port_range: publisher.ice_port_range,
        audio_codecs: publisher.audio_codecs,
        video_codecs: publisher.video_codecs
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    gen_server_opts =
      [name: publisher.name]
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
