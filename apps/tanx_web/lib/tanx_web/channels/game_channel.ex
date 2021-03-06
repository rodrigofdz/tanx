defmodule TanxWeb.GameChannel do
  use TanxWeb, :channel

  require Logger

  def join("game:" <> game, %{"name" => player_name, "id" => player}, socket) do
    game_proc = Tanx.Cluster.game_process(game)
    case Tanx.ContinuousGame.rename_player(game_proc, player, player_name) do
      {:ok, ^player} ->
        {:ok, meta} = Tanx.Game.get_meta(game_proc)
        game_info = %{i: meta.id, n: meta.settings.display_name, d: meta.node}

        socket =
          socket
          |> assign(:game, game)
          |> assign(:player, player)
          |> assign(:player_name, player_name)

        {:ok, %{i: player, g: game_info}, socket}

      {:error, :player_not_found, _} ->
        {:error, %{e: "player_not_found"}}
    end
  end

  def join("game:" <> game, %{"name" => player_name}, socket) do
    game_proc = Tanx.Cluster.game_process(game)
    {:ok, player} = Tanx.ContinuousGame.add_player(game_proc, player_name)
    {:ok, meta} = Tanx.Game.get_meta(game_proc)
    game_info = %{i: meta.id, n: meta.settings.display_name, d: meta.node}

    socket =
      socket
      |> assign(:game, game)
      |> assign(:player, player)
      |> assign(:player_name, player_name)

    {:ok, %{i: player, g: game_info}, socket}
  end

  def handle_in("view_players", _msg, socket) do
    view =
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.view_players(socket.assigns[:player])
      |> TanxWeb.JsonData.format_players()

    push(socket, "view_players", view)
    {:noreply, socket}
  end

  def handle_in("view_structure", _msg, socket) do
    view =
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.view_static()
      |> TanxWeb.JsonData.format_structure()

    push(socket, "view_structure", view)
    {:noreply, socket}
  end

  def handle_in("view_arena", _msg, socket) do
    view =
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.view_arena(socket.assigns[:player])
      |> TanxWeb.JsonData.format_arena()

    push(socket, "view_arena", view)
    {:noreply, socket}
  end

  def handle_in("rename", %{"name" => name, "old_name" => old_name}, socket) do
    player = socket.assigns[:player]
    socket = assign(socket, :player_name, name)

    if player do
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.rename_player(player, name)
    end

    broadcast(socket, "chat_renamed", %{old_name: old_name, name: name})

    {:noreply, socket}
  end

  def handle_in("launch_tank", %{"entry_point" => entry_point}, socket) do
    player = socket.assigns[:player]

    if player do
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.start_tank(player, entry_point)
    end

    {:noreply, socket}
  end

  def handle_in("self_destruct_tank", _msg, socket) do
    player = socket.assigns[:player]

    if player do
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.destruct_tank(player)
    end

    {:noreply, socket}
  end

  def handle_in("control_tank", %{"button" => button, "down" => down}, socket)
      when button == "left" or button == "right" or button == "backward" or button == "forward" or
             button == "fire" do
    player = socket.assigns[:player]

    if player do
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.control_tank(player, String.to_atom(button), down)
    end

    {:noreply, socket}
  end

  def handle_in("heartbeat", _msg, socket) do
    {:noreply, socket}
  end

  def handle_in("chat_join", _, socket) do
    player_name = socket.assigns[:player_name]
    broadcast(socket, "chat_entered", %{name: player_name})
    {:noreply, socket}
  end

  def handle_in("chat_leave", _, socket) do
    player_name = socket.assigns[:player_name]
    broadcast(socket, "chat_left", %{name: player_name})
    {:noreply, socket}
  end

  def handle_in("chat_message", %{"content" => content}, socket) do
    player_name = socket.assigns[:player_name]
    broadcast(socket, "chat_message", %{content: content, name: player_name})
    {:noreply, socket}
  end

  def handle_in("leave", _, socket) do
    socket =
      case socket.assigns[:player] do
        nil ->
          socket

        player ->
          game_id = socket.assigns[:game]
          Logger.info("**** Removing #{inspect(player)} from #{inspect(game_id)}")
          game_id
          |> Tanx.Cluster.game_process()
          |> Tanx.ContinuousGame.remove_player(player)

          assign(socket, :player, nil)
      end
    {:noreply, socket}
  end

  def handle_in(msg, payload, socket) do
    Logger.error("Unknown message received on game channel: #{inspect(msg)}: #{inspect(payload)}")
    {:noreply, socket}
  end

  intercept(["view_players"])

  def handle_out("view_players", _event, socket) do
    view =
      socket.assigns[:game]
      |> Tanx.Cluster.game_process()
      |> Tanx.ContinuousGame.view_players(socket.assigns[:player])
      |> TanxWeb.JsonData.format_players()

    push(socket, "view_players", view)
    {:noreply, socket}
  end

  def handle_out(msg, payload, socket) do
    push(socket, msg, payload)
    {:noreply, socket}
  end

  def terminate(reason, socket) do
    Logger.info("Channel terminated due to #{inspect(reason)}")
    {reason, socket}
  end
end
