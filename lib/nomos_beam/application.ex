defmodule NomosBeam.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NomosBeamWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nomos_beam, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NomosBeam.PubSub},
      NomosBeam.KeyboardServer,
      # Phase 1: NomosBeam.NousPort      — Jinterface connection to nous@localhost
      # Phase 2: NomosBeam.CtrlTreeProxy — ctrl-tree IPC bridge
      # Phase 3: NomosBeam.MountTable    — mDNS + Khepri peer discovery
      # Phase 4: NomosBeam.BeatSupervisor, NomosBeam.ConductorArc
      NomosBeamWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NomosBeam.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NomosBeamWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
